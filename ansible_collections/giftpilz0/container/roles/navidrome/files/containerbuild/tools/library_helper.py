#!/usr/bin/env python3
"""
helper.py — music library transcoder + yt-dlp + beets wrapper

Folder layout (relative to this script):
  original/
    lossless_compression/   FLAC, WAV, AIFF
    lossy_compression/      MP3, M4A, Opus
    untagged/               freshly downloaded, pending beets import
  transcoded/               mirrors original/, all files as .opus

Commands:
  transcode               transcode ./original → ./transcoded (skips existing)
  transcode --force       re-transcode everything
  transcode --dry-run     preview without running ffmpeg
  transcode --jobs N      override worker count (default: cpu_count)

  download URL            download to ./original/untagged via yt-dlp

  import                  beet import ./original/untagged (interactive)
  import --auto           auto-accept best match (-A)

  playlist                regenerate playlists/ and playlists_transcoded/ from config
  relocate                rewrite DB paths to match current filesystem location
  clean                   remove DB entries for files deleted from disk
  beet ARGS...            escape hatch: run any beet sub-command directly
  info                    show library stats and missing transcodes
  check-transcoded        compare metadata between originals and transcoded files
  audit                   report files in imported dirs not tracked by beets
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import json
import logging
import os
import resource
import shutil
import sqlite3
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, NamedTuple

try:
    from mutagen import File as MutagenFile
    from mutagen.flac import Picture
    from mutagen.mp4 import MP4Cover
    from mutagen.oggopus import OggOpus as MutagenOggOpus
    _MUTAGEN_OK = True
except ImportError:
    _MUTAGEN_OK = False

# ── Constants ─────────────────────────────────────────────────────────────────

SCRIPT_DIR     = Path(__file__).resolve().parents[1]
ORIGINAL_DIR   = SCRIPT_DIR / "original"
TRANSCODED_DIR = SCRIPT_DIR / "transcoded"
UNTAGGED_DIR   = ORIGINAL_DIR / "untagged"
BEETS_CONFIG   = SCRIPT_DIR / "config.yaml"

LOSSLESS_EXTS  = {".flac", ".wav", ".aiff", ".aif", ".alac"}
LOSSY_EXTS     = {".mp3", ".m4a", ".aac", ".ogg", ".opus", ".wma", ".mka"}
ALL_EXTS       = LOSSLESS_EXTS | LOSSY_EXTS

# Extensions that get re-mapped to .opus in transcoded playlists
_TRANSCODE_EXTS = {".flac", ".wav", ".aiff", ".aif", ".alac",
                   ".mp3", ".m4a", ".aac", ".ogg", ".wma", ".mka"}

LOSSLESS_BITRATE = "192k"
LOSSY_DEFAULT    = "128k"
LOSSY_CAP        = 192_000

# Raised fd limit for large parallel chroma fingerprint runs
_FD_TARGET = 65536

# Picture type 3 = "Cover (front)" per the ID3/FLAC spec
_COVER_FRONT = 3

# Max items shown in info/audit listings before truncation
_LIST_PREVIEW = 30

YT_FORMAT_SELECTOR = (
    "bestaudio[acodec=opus]/bestaudio[ext=webm]/"
    "bestaudio[ext=m4a]/bestaudio/best"
)
YT_OUTPUT_TEMPLATE = (
    "%(artist,uploader)s"
    "/%(album,playlist,title)s"
    "/%(playlist_index|)s%(playlist_index& - |)s%(title)s.%(ext)s"
)

# ── Logging ───────────────────────────────────────────────────────────────────

log = logging.getLogger("helper")


def setup_logging(verbose: bool = False) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter(
        "%(asctime)s  %(levelname)-8s  %(message)s",
        datefmt="%H:%M:%S",
    ))
    logging.root.setLevel(logging.DEBUG if verbose else logging.INFO)
    logging.root.addHandler(handler)

# ── Dependency checks ─────────────────────────────────────────────────────────

def require(*tools: str) -> None:
    missing = [t for t in tools if not shutil.which(t)]
    if missing:
        sys.exit(
            f"[ERROR] Missing tool(s): {', '.join(missing)}\n"
            "        See README.md for installation instructions."
        )
    if not _MUTAGEN_OK:
        sys.exit(
            "[ERROR] Python package 'mutagen' not found.\n"
            "        pip install --user mutagen"
        )

# ── Beets wrapper ─────────────────────────────────────────────────────────────

def _make_beet_env() -> dict[str, str]:
    """Return an env dict with BEETSDIR set so beet finds config.yaml."""
    env = os.environ.copy()
    env["BEETSDIR"] = str(SCRIPT_DIR)
    return env


def run_beets(beet_args: list[str]) -> int:
    if not shutil.which("beet"):
        sys.exit("[ERROR] 'beet' not found — see README.md")
    if not BEETS_CONFIG.exists():
        sys.exit(f"[ERROR] config.yaml not found at {BEETS_CONFIG}")

    # Large album imports (e.g. 60-track soundtracks) can exhaust the default
    # 1024 fd limit when chroma opens many files in parallel.
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        desired = min(_FD_TARGET, hard) if hard != resource.RLIM_INFINITY else _FD_TARGET
        if soft < desired:
            resource.setrlimit(resource.RLIMIT_NOFILE, (desired, hard))
    except OSError:
        log.debug("Could not raise RLIMIT_NOFILE — continuing with default")

    cmd = ["beet", *beet_args]
    log.info("Running: %s", " ".join(cmd))
    return subprocess.run(cmd, env=_make_beet_env(), check=False).returncode

# ── ffprobe helpers ───────────────────────────────────────────────────────────

class StreamInfo(NamedTuple):
    codec_name: str
    codec_type: str
    bit_rate: int | None


def probe_file(path: Path) -> list[StreamInfo]:
    try:
        raw = subprocess.run(
            [
                "ffprobe", "-v", "quiet",
                "-print_format", "json",
                "-show_streams", str(path),
            ],
            capture_output=True, text=True, check=True,
        )
        return [
            StreamInfo(
                codec_name=s.get("codec_name", ""),
                codec_type=s.get("codec_type", ""),
                bit_rate=(
                    int(br)
                    if (br := s.get("bit_rate")) and str(br).isdigit()
                    else None
                ),
            )
            for s in json.loads(raw.stdout).get("streams", [])
        ]
    except (subprocess.CalledProcessError, json.JSONDecodeError, OSError) as exc:
        log.warning("ffprobe failed for %s: %s", path.name, exc)
        return []


def source_audio_bitrate(streams: list[StreamInfo]) -> int | None:
    return next(
        (s.bit_rate for s in streams if s.codec_type == "audio" and s.bit_rate),
        None,
    )

# ── Cover-art extraction + Opus embedding ────────────────────────────────────
# ffmpeg's libopus muxer does not reliably write METADATA_BLOCK_PICTURE, so
# cover art is handled separately via mutagen after each transcode.

def _extract_cover_flac(f: Any) -> tuple[bytes, str] | None:
    """Extract cover from FLAC/OggVorbis Picture blocks."""
    pictures = getattr(f, "pictures", None)
    if not pictures:
        return None
    pics = sorted(pictures, key=lambda p: (p.type != _COVER_FRONT, 0))
    pic = pics[0]
    return pic.data, pic.mime or "image/jpeg"


def _extract_cover_id3(tags: Any) -> tuple[bytes, str] | None:
    """Extract cover from ID3 APIC frames."""
    apic_keys = [k for k in tags if isinstance(k, str) and k.startswith("APIC")]
    if not apic_keys:
        return None
    preferred = sorted(apic_keys, key=lambda k: (tags[k].type != _COVER_FRONT, k))
    apic = tags[preferred[0]]
    return apic.data, apic.mime or "image/jpeg"


def _extract_cover_mp4(tags: Any) -> tuple[bytes, str] | None:
    """Extract cover from MP4 'covr' atom."""
    covr = tags.get("covr") if hasattr(tags, "get") else None
    if not covr:
        return None
    raw = covr[0]
    mime = (
        "image/png"
        if getattr(raw, "imageformat", None) == MP4Cover.FORMAT_PNG
        else "image/jpeg"
    )
    return bytes(raw), mime


def _extract_cover_vorbis(tags: Any) -> tuple[bytes, str] | None:
    """Extract cover from Vorbis METADATA_BLOCK_PICTURE tag."""
    mbp = None
    with contextlib.suppress(Exception):
        mbp = tags.get("metadata_block_picture") or tags.get("METADATA_BLOCK_PICTURE")
    if not mbp:
        return None
    with contextlib.suppress(Exception):
        pic = Picture(base64.b64decode(mbp[0]))
        return pic.data, pic.mime or "image/jpeg"
    return None


def _extract_cover_wma(tags: Any) -> tuple[bytes, str] | None:
    """Extract cover from WMA/ASF WM/Picture tag."""
    wm_pic = None
    with contextlib.suppress(Exception):
        wm_pic = tags.get("WM/Picture")
    if not wm_pic:
        return None
    with contextlib.suppress(Exception):
        raw_bytes = (
            bytes(wm_pic[0].value)
            if hasattr(wm_pic[0], "value")
            else bytes(wm_pic[0])
        )
        if b"\xff\xd8\xff" in raw_bytes:
            return raw_bytes[raw_bytes.index(b"\xff\xd8\xff"):], "image/jpeg"
        if b"\x89PNG" in raw_bytes:
            return raw_bytes[raw_bytes.index(b"\x89PNG"):], "image/png"
    return None


def _read_cover_from_mutagen(src: Path) -> tuple[bytes, str] | None:
    """Read cover art from any supported audio file via mutagen."""
    try:
        f = MutagenFile(str(src), easy=False)
    except Exception:  # noqa: BLE001 — mutagen raises various internal errors
        return None
    if f is None:
        return None

    tags: Any = getattr(f, "tags", None) or {}

    return (
        _extract_cover_flac(f)
        or _extract_cover_id3(tags)
        or _extract_cover_mp4(tags)
        or _extract_cover_vorbis(tags)
        or _extract_cover_wma(tags)
    )


# Multi-value Vorbis comment keys that ffmpeg incorrectly joins with ";" (no space)
# when copying from FLAC.  We read them from the source and rewrite after transcode.
_MULTIVAL_VORBIS_KEYS = ("genre", "genres", "artist", "artists", "composer")


def _fix_multival_tags(src: Path, opus_path: Path) -> None:
    """
    Re-write multi-value Vorbis comment tags in the Opus file.

    ffmpeg's -map_metadata joins multiple Vorbis entries as "A;B" (no space).
    We read the original values from the source file and write them back to
    the Opus as a single properly-joined string ("A; B") to match beets' format.
    """
    try:
        src_f = MutagenFile(str(src), easy=False)
    except Exception:  # noqa: BLE001
        return
    if src_f is None:
        return

    # Vorbis-comment-like sources store tags directly on the file object
    src_tags: Any = src_f if hasattr(src_f, "keys") else (getattr(src_f, "tags", None) or {})

    updates: dict[str, list[str]] = {}
    for key in _MULTIVAL_VORBIS_KEYS:
        for variant in (key, key.upper()):
            try:
                val = src_tags.get(variant)
            except Exception:  # noqa: BLE001
                continue
            if not val:
                continue
            if isinstance(val, list) and len(val) > 1:
                # Preserve as a list of separate values — not a joined string
                updates[key] = [str(v).strip() for v in val]
            break  # found this key, move on

    if not updates:
        return

    try:
        opus_f = MutagenOggOpus(str(opus_path))
        for key, values in updates.items():
            # Write as separate Vorbis comment entries — same as the source FLAC.
            # Joining into one string would cause beets to see a different value
            # than what it reads from the FLAC (which returns only the first entry).
            opus_f[key] = values
        opus_f.save()
        log.debug("  fixed multi-value tags %s in %s", list(updates), opus_path.name)
    except Exception as exc:  # noqa: BLE001
        log.warning("  multi-value tag fix failed for %s: %s", opus_path.name, exc)


def embed_cover_into_opus(opus_path: Path, cover_data: bytes, mime: str) -> bool:
    try:
        pic = Picture()
        pic.type = _COVER_FRONT
        pic.mime = mime
        pic.desc = ""
        pic.width = pic.height = pic.depth = pic.colors = 0
        pic.data = cover_data
        tags = MutagenOggOpus(str(opus_path))
        tags["metadata_block_picture"] = [
            base64.b64encode(pic.write()).decode("ascii")
        ]
        tags.save()
    except Exception as exc:  # noqa: BLE001 — mutagen raises various internal errors
        log.warning("  mutagen cover embed failed for %s: %s", opus_path.name, exc)
        return False
    else:
        return True

# ── Transcoding ───────────────────────────────────────────────────────────────

def choose_bitrate(ext: str, streams: list[StreamInfo]) -> str:
    if ext in LOSSLESS_EXTS:
        return LOSSLESS_BITRATE
    src_br = source_audio_bitrate(streams)
    if src_br:
        return f"{max(64, (min(src_br, LOSSY_CAP) // 8000) * 8)}k"
    return LOSSY_DEFAULT


def build_ffmpeg_cmd(input_path: Path, output_path: Path, bitrate: str) -> list[str]:
    return [
        "ffmpeg", "-y",
        "-i", str(input_path),
        "-map", "0:a",
        "-c:a", "libopus",
        "-b:a", bitrate,
        "-vbr", "on",
        "-compression_level", "10",
        "-application", "audio",
        "-frame_duration", "20",
        "-packet_loss", "0",
        "-map_metadata", "0",
        str(output_path),
        "-loglevel", "warning",
        "-stats",
    ]


def transcode_file(
    input_path: Path,
    output_path: Path,
    dry_run: bool = False,
    force: bool = False,
) -> tuple[bool, str]:
    output_path = output_path.with_suffix(".opus")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.exists() and not force:
        return True, "skipped (exists)"

    ext     = input_path.suffix.lower()
    streams = probe_file(input_path)
    bitrate = choose_bitrate(ext, streams)
    cmd     = build_ffmpeg_cmd(input_path, output_path, bitrate)

    if dry_run:
        return True, f"[DRY RUN] {' '.join(cmd)}"

    result = subprocess.run(cmd, capture_output=True, check=False)
    if result.returncode != 0:
        log.debug("  ffmpeg stderr: %s", result.stderr.decode(errors="replace"))
        output_path.unlink(missing_ok=True)
        return False, f"ffmpeg error (rc={result.returncode})"

    # Fix multi-value tags that ffmpeg joins incorrectly (e.g. "Punk Rock;Rock")
    _fix_multival_tags(input_path, output_path)

    art_note = ""
    cover = _read_cover_from_mutagen(input_path)
    if cover:
        img_data, mime = cover
        art_note = (
            "  +cover"
            if embed_cover_into_opus(output_path, img_data, mime)
            else "  cover-FAILED"
        )

    src_tag = "  lossless" if ext in LOSSLESS_EXTS else ""
    return True, f"transcoded [{bitrate}{src_tag}{art_note}]"


def collect_files(root: Path, *, exclude: Path | None = None) -> list[Path]:
    """
    Recursively collect all supported audio files under *root*.

    Pass ``exclude`` to skip an entire subtree (e.g. ``UNTAGGED_DIR`` so
    that un-imported files are not transcoded before tagging).
    """
    exclude_resolved = exclude.resolve() if exclude else None
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dp = Path(dirpath)
        if exclude_resolved and dp.resolve() == exclude_resolved:
            dirnames.clear()   # prune the walk — don't descend into it
            continue
        for fn in filenames:
            p = dp / fn
            if p.suffix.lower() in ALL_EXTS:
                files.append(p)
    return sorted(files)


def transcode_library(
    dry_run: bool = False,
    force: bool = False,
    jobs: int | None = None,
) -> None:
    workers = jobs or os.cpu_count() or 1
    # Skip untagged/ — files there haven't been through beets yet and
    # should not be transcoded before tagging.
    files = collect_files(ORIGINAL_DIR, exclude=UNTAGGED_DIR)
    total = len(files)

    if total == 0:
        log.warning("No supported audio files found in %s", ORIGINAL_DIR)
        return

    log.info("Found %d file(s) — transcoding with %d worker(s)", total, workers)

    ok = err = skip = 0
    width = len(str(total))

    def _job(args: tuple[int, Path]) -> tuple[int, bool, str, Path]:
        _idx, src = args
        rel = src.relative_to(ORIGINAL_DIR)
        success, msg = transcode_file(
            src, TRANSCODED_DIR / rel, dry_run=dry_run, force=force,
        )
        return _idx, success, msg, rel

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(_job, j): j for j in enumerate(files, 1)}
        for fut in as_completed(futures):
            idx, success, msg, rel = fut.result()
            level = logging.INFO if success else logging.ERROR
            icon  = "✓" if success else "✗"
            log.log(level, "[%*d/%d] %s  %s  — %s", width, idx, total, icon, rel, msg)
            if "skipped" in msg:
                skip += 1
            elif success:
                ok += 1
            else:
                err += 1

    log.info("─" * 60)
    log.info("Results:  %d transcoded  |  %d skipped  |  %d failed", ok, skip, err)
    if err:
        log.warning("Some files failed — run with -v for ffmpeg stderr details.")

# ── yt-dlp download ───────────────────────────────────────────────────────────

def download(url: str) -> None:
    # ffmpeg is required by yt-dlp's --embed-thumbnail post-processor
    require("yt-dlp", "ffmpeg")
    UNTAGGED_DIR.mkdir(parents=True, exist_ok=True)

    playlist_flags = ["--yes-playlist"] if "list=" in url else ["--no-playlist"]

    cmd: list[str] = [
        "yt-dlp",
        "--format", YT_FORMAT_SELECTOR,
        "-x",
        "--audio-format", "opus",
        "--no-post-overwrites",
        "--embed-metadata",
        "--embed-thumbnail",
        "--parse-metadata", "%(release_year,upload_date)s:%(meta_date)s",
        "--parse-metadata", "%(track_number,playlist_index)s:%(meta_track)s",
        *playlist_flags,
        "--output", str(UNTAGGED_DIR / YT_OUTPUT_TEMPLATE),
        "--restrict-filenames",
        "--windows-filenames",
        "--audio-quality", "0",
        "--concurrent-fragments", "4",
        "--retries", "10",
        "--fragment-retries", "10",
        url,
    ]

    log.info("Running: %s", " ".join(cmd))
    subprocess.run(cmd, check=False)

# ── Info ──────────────────────────────────────────────────────────────────────


def show_info() -> None:
    require("ffprobe")
    orig_files = collect_files(ORIGINAL_DIR, exclude=UNTAGGED_DIR)
    fmt_count: dict[str, int] = {}
    missing: list[Path] = []

    for src in orig_files:
        ext = src.suffix.lower()
        fmt_count[ext] = fmt_count.get(ext, 0) + 1
        rel = src.relative_to(ORIGINAL_DIR)
        if not (TRANSCODED_DIR / rel).with_suffix(".opus").exists():
            missing.append(rel)

    print()
    print("  Library overview")
    print("  ────────────────────────────────────────")
    print(f"  Original root   : {ORIGINAL_DIR}")
    print(f"  Transcoded root : {TRANSCODED_DIR}")
    print()
    print("  Source format breakdown:")
    for ext, n in sorted(fmt_count.items()):
        tag = "(lossless)" if ext in LOSSLESS_EXTS else "(lossy)  "
        print(f"    {ext:<8} {tag}  {n:>5} file(s)")
    print()
    print(f"  Total source files : {len(orig_files)}")
    print(f"  Missing transcodes : {len(missing)}")
    if missing:
        print()
        print("  Files not yet transcoded:")
        for rel in missing[:_LIST_PREVIEW]:
            print(f"    {rel}")
        if len(missing) > _LIST_PREVIEW:
            print(f"    … and {len(missing) - _LIST_PREVIEW} more")
    print()

# ── Audit ─────────────────────────────────────────────────────────────────────

def show_audit() -> None:
    """
    Report audio files in the imported dirs that are not tracked by beets.
    Scans lossless_compression/ and lossy_compression/, then queries the beets
    DB for all known paths via ``beet ls -f '$path'`` and prints the difference.
    """
    result = subprocess.run(
        ["beet", "ls", "-f", "$path"],
        capture_output=True, text=True, env=_make_beet_env(), check=False,
    )
    if result.returncode != 0:
        sys.exit(f"[ERROR] beet ls failed:\n{result.stderr.strip()}")

    tracked = {Path(p.strip()) for p in result.stdout.splitlines() if p.strip()}

    imported_dirs = [
        ORIGINAL_DIR / "lossless_compression",
        ORIGINAL_DIR / "lossy_compression",
    ]

    untracked: list[Path] = []
    for d in imported_dirs:
        if not d.exists():
            continue
        for dirpath, _, filenames in os.walk(d):
            for fn in filenames:
                p = Path(dirpath) / fn
                if p.suffix.lower() in ALL_EXTS and p not in tracked:
                    untracked.append(p)

    untracked.sort()

    print()
    print("  Untracked files in imported directories")
    print("  ────────────────────────────────────────")
    if not untracked:
        print("  All files are tracked by beets.")
    else:
        print(f"  {len(untracked)} file(s) not in the beets library:\n")
        for p in untracked:
            print(f"    {p.relative_to(ORIGINAL_DIR)}")
        print()
        print("  Run `python helper.py import` to import them, or move them")
        print("  to original/untagged/ first if they need tagging.")
    print()

# ── Clean ─────────────────────────────────────────────────────────────────────

def show_clean(force: bool = False) -> None:
    """
    Find DB entries whose file no longer exists on disk and remove them.
    Without --force, lists what would be removed and asks for confirmation.
    Removal is batched into one or more ``beet remove`` calls.
    """
    result = subprocess.run(
        ["beet", "ls", "-f", "$path"],
        capture_output=True, text=True, env=_make_beet_env(), check=False,
    )
    if result.returncode != 0:
        sys.exit(f"[ERROR] beet ls failed:\n{result.stderr.strip()}")

    missing = [
        p.strip() for p in result.stdout.splitlines()
        if p.strip() and not Path(p.strip()).exists()
    ]

    if not missing:
        print("\n  Database is clean — no missing files.\n")
        return

    print(f"\n  {len(missing)} DB entry/entries with no file on disk:\n")
    for p in missing:
        print(f"    {p}")
    print()

    if not force:
        try:
            answer = input(
                "  Remove these entries from the database? [y/N] "
            ).strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            sys.exit(0)
        if answer != "y":
            print("  Aborted.\n")
            return

    # Use exact path queries instead of path:: regex queries. In beets, `path:`
    # uses a dedicated path matcher that understands the BLOB-backed path field,
    # while `path::` falls back to a generic regex query and misses these items.
    max_batch_chars = 12_000
    batches: list[list[str]] = []
    current_batch: list[str] = []
    current_chars = 0

    for path in missing:
        term = f"path:{path}"
        if current_batch and current_chars + len(term) + 1 > max_batch_chars:
            batches.append(current_batch)
            current_batch = []
            current_chars = 0
        current_batch.append(term)
        current_chars += len(term) + 1

    if current_batch:
        batches.append(current_batch)

    for index, batch in enumerate(batches, start=1):
        query_args = [
            f"{term}," if i < len(batch) - 1 else term
            for i, term in enumerate(batch)
        ]
        rc = run_beets(["remove", "-f", *query_args])
        if rc != 0:
            log.warning(
                "beet remove batch %d/%d returned non-zero exit code %d",
                index,
                len(batches),
                rc,
            )
            return

    print(f"\n  Removed {len(missing)} entry/entries.\n")

# ── Check transcoded metadata ─────────────────────────────────────────────────
# Reads tags from each source file and its corresponding .opus in transcoded/
# and reports any fields that differ.  Uses mutagen (already required for
# transcoding) so no new dependencies are needed.

_TAG_MAP: dict[str, list[str]] = {
    # field name → possible Vorbis comment / ID3 / MP4 key variants
    "title":       ["title", "TIT2", "\xa9nam"],
    "artist":      ["artist", "TPE1", "\xa9ART"],
    "albumartist": ["albumartist", "TPE2", "aART"],
    "album":       ["album", "TALB", "\xa9alb"],
    "date":        ["date", "TDRC", "\xa9day"],
    "tracknumber": ["tracknumber", "TRCK", "trkn"],
    "discnumber":  ["discnumber", "TPOS", "disk"],
    "genre":       ["genre", "TCON", "\xa9gen"],
}


def _read_tags(path: Path) -> dict[str, str]:
    """Extract a normalised {field: value} dict from any supported file."""
    try:
        f = MutagenFile(str(path), easy=False)
    except Exception:  # noqa: BLE001 — mutagen raises various internal errors
        return {}
    if f is None:
        return {}
    # OggOpus / Vorbis tags are stored directly on the file object
    tags: Any = f if hasattr(f, "keys") else (getattr(f, "tags", None) or {})

    result: dict[str, str] = {}
    for field, keys in _TAG_MAP.items():
        for key in keys:
            try:
                val = tags.get(key) or tags.get(key.upper())
            except Exception:  # noqa: BLE001 — various tag-format exceptions
                log.debug("Could not read tag key %r from %s", key, path.name)
                continue
            if val is None:
                continue
            # mutagen returns lists for most tag types
            raw = val[0] if isinstance(val, list) else val
            # MP4 stores tracknumber/discnumber as (number, total) tuples
            if isinstance(raw, tuple):
                raw = raw[0]
            # ID3 frames have a .text attribute
            text = str(getattr(raw, "text", [raw])[0] if hasattr(raw, "text") else raw)
            text = text.strip()
            if text:
                result[field] = text
                break
    return result


def _has_cover(path: Path) -> bool:
    return _read_cover_from_mutagen(path) is not None


def _normalise_track_field(value: str) -> str:
    """Collapse '3/12' fractional track/disc strings to just '3'."""
    return value.split("/", 1)[0].strip()


def _compare_tags(
    src: Path,
    opus: Path,
) -> list[str]:
    """
    Return a list of human-readable difference lines between *src* and *opus*.
    An empty list means all checked tags and cover art match.
    """
    src_tags  = _read_tags(src)
    opus_tags = _read_tags(opus)
    issues: list[str] = []

    for field in _TAG_MAP:
        sv = src_tags.get(field, "")
        ov = opus_tags.get(field, "")
        if field in ("tracknumber", "discnumber"):
            sv = _normalise_track_field(sv)
            ov = _normalise_track_field(ov)
        if sv != ov:
            issues.append(f"    {field}: {sv!r} → {ov!r}")

    src_cover  = _has_cover(src)
    opus_cover = _has_cover(opus)
    if src_cover and not opus_cover:
        issues.append(
            "    cover art: present in source, missing in transcoded"
        )
    elif not src_cover and opus_cover:
        issues.append(
            "    cover art: missing in source, present in transcoded"
        )

    return issues


def show_check_transcoded() -> None:
    if not _MUTAGEN_OK:
        sys.exit("[ERROR] mutagen not installed — pip install --user mutagen")

    orig_files = collect_files(ORIGINAL_DIR, exclude=UNTAGGED_DIR)
    all_issues: list[str] = []
    checked = missing_transcode = 0

    for src in orig_files:
        rel  = src.relative_to(ORIGINAL_DIR)
        opus = (TRANSCODED_DIR / rel).with_suffix(".opus")

        if not opus.exists():
            missing_transcode += 1
            continue

        checked += 1
        field_issues = _compare_tags(src, opus)
        if field_issues:
            all_issues.append(f"  {rel}\n" + "\n".join(field_issues))

    print()
    print(
        f"  Checked {checked} transcoded file(s)  "
        f"({missing_transcode} source(s) not yet transcoded)"
    )
    print()

    if not all_issues:
        print("  All metadata matches.\n")
        return

    print(f"  {len(all_issues)} file(s) with metadata differences:\n")
    print("  ────────────────────────────────────────")
    for issue in all_issues:
        print(issue)
    print()
    print("  Re-transcode to fix:  python helper.py transcode --force")
    print()

# ── Playlist generation ───────────────────────────────────────────────────────
# beet splupdate writes to original/playlists/ with paths relative to that dir:
#   ../lossless_compression/Artist/2020 - Album/01 - Track.flac
#
# _generate_transcoded_playlists copies each .m3u to transcoded/playlists/ and
# swaps the audio extension to .opus.  The ../ prefix stays identical since both
# playlist dirs sit at the same depth inside their respective trees.

def _generate_transcoded_playlists() -> None:
    src_dir  = ORIGINAL_DIR / "playlists"
    dest_dir = TRANSCODED_DIR / "playlists"

    if not src_dir.exists():
        log.warning("original/playlists/ not found — skipping transcoded generation")
        return

    dest_dir.mkdir(parents=True, exist_ok=True)

    for m3u in src_dir.glob("*.m3u"):
        lines     = m3u.read_text(encoding="utf-8").splitlines(keepends=True)
        new_lines: list[str] = []
        changed   = 0
        for line in lines:
            stripped = line.rstrip("\n\r")
            if stripped and not stripped.startswith("#"):
                p = Path(stripped.replace("/", os.sep))
                if p.suffix.lower() in _TRANSCODE_EXTS:
                    p = p.with_suffix(".opus")
                    changed += 1
                stripped = str(p).replace(os.sep, "/")
            new_lines.append(stripped + "\n")
        (dest_dir / m3u.name).write_text("".join(new_lines), encoding="utf-8")
        log.info(
            "  %s → transcoded/playlists/ (%d path(s) rewritten)",
            m3u.name, changed,
        )

# ── DB relocation ─────────────────────────────────────────────────────────────
# The beets DB stores absolute paths at import time.  When the library moves or
# a different user mounts it at a different path, every stored path is stale.
# This function does a pure find-and-replace inside the SQLite DB — no files
# are touched on disk.  It detects the old prefix automatically from the DB,
# so the user doesn't need to know or supply the previous location.

# These are the only columns in beets' schema that store file-system paths.
# Table and column names come from our own constant list, so the f-string
# below is safe from injection (user values go through parameterised queries).
_DB_PATH_COLUMNS: list[tuple[str, str]] = [
    ("items", "path"),
    ("items", "destination"),
    ("albums", "artpath"),
]


def _relocate_db() -> None:
    db_path = SCRIPT_DIR / "beets_library.db"
    if not db_path.exists():
        sys.exit(f"[ERROR] DB not found: {db_path}")

    con = sqlite3.connect(db_path)
    try:
        # Detect old prefix: take the stored path of the first item, strip
        # everything from /original/ onward to get the root that changed.
        row = con.execute("SELECT path FROM items LIMIT 1").fetchone()
        if not row:
            log.info("DB is empty — nothing to relocate.")
            return

        # paths are stored as bytes in beets' SQLite DB
        stored = row[0]
        if isinstance(stored, bytes):
            stored = stored.decode("utf-8", errors="replace")

        # Find the /original/ anchor in the stored path
        marker = "/original/"
        idx = stored.find(marker)
        if idx == -1:
            sys.exit(
                f"[ERROR] Could not find '{marker}' in stored path:\n  {stored}\n"
                "        Is 'original/' still the library subdirectory?"
            )

        old_prefix = stored[:idx]  # e.g. /home/bob/Downloads/musik
        if old_prefix == str(SCRIPT_DIR):
            log.info("DB paths already point to current location — nothing to do.")
            return

        log.info("Old prefix: %s", old_prefix)
        log.info("New prefix: %s", str(SCRIPT_DIR))

        # beets stores paths as BLOBs (bytes), so replace on the text
        # representation then cast back.
        # Table/column names are from our own constant — no injection risk.
        for table, col in _DB_PATH_COLUMNS:
            with contextlib.suppress(sqlite3.OperationalError):
                # column may not exist in older schema versions
                con.execute(
                    f"UPDATE {table} SET {col} = CAST("          # noqa: S608
                    f"  replace(CAST({col} AS TEXT), ?, ?) "
                    f"AS BLOB) WHERE {col} IS NOT NULL",
                    (old_prefix, str(SCRIPT_DIR)),
                )

        con.commit()
        count = con.execute("SELECT changes()").fetchone()[0]
        log.info(
            "Done — updated paths in DB (last statement affected %d row(s)).", count,
        )
        log.info("Run 'python helper.py beet update' to verify.")

    finally:
        con.close()

# ── Argument parser ───────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="helper",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = p.add_subparsers(dest="command", metavar="COMMAND")

    # transcode
    tc = sub.add_parser(
        "transcode", help="Transcode ./original → ./transcoded (Opus)",
    )
    tc.add_argument("--force",   action="store_true", help="Re-transcode existing files")
    tc.add_argument("--dry-run", action="store_true", help="Preview without running ffmpeg")
    tc.add_argument("--jobs",    type=int, default=None, metavar="N",
                    help="Worker count (default: cpu_count)")
    tc.add_argument("-v", "--verbose", action="store_true")

    # download
    dl = sub.add_parser(
        "download", help="Download audio via yt-dlp into ./original/untagged",
    )
    dl.add_argument("url", metavar="URL")
    dl.add_argument("-v", "--verbose", action="store_true")

    # import
    im = sub.add_parser("import", help="beet import ./original/untagged")
    im.add_argument("--auto", action="store_true", help="Auto-accept best match (-A)")
    im.add_argument("-v", "--verbose", action="store_true")

    # playlist
    sub.add_parser(
        "playlist",
        help="Run beet splupdate then generate playlists_transcoded/",
    )

    # relocate
    sub.add_parser(
        "relocate",
        help=(
            "Rewrite DB paths to match current filesystem location "
            "(run once after moving the library or on a new machine)"
        ),
    )

    # clean
    cl = sub.add_parser("clean", help="Remove DB entries for files deleted from disk")
    cl.add_argument("--force", action="store_true", help="Skip confirmation prompt")

    # beet passthrough
    bg = sub.add_parser("beet", help="Run any beet sub-command directly")
    bg.add_argument("beet_args", nargs=argparse.REMAINDER, metavar="ARGS")

    # info
    sub.add_parser("info", help="Show library stats and missing transcodes")

    # check-transcoded
    sub.add_parser(
        "check-transcoded",
        help="Compare metadata between originals and transcoded files",
    )

    # audit
    sub.add_parser(
        "audit", help="Show files in imported dirs not tracked by beets",
    )

    return p

# ── Dispatch ──────────────────────────────────────────────────────────────────

def _dispatch(args: argparse.Namespace) -> None:  # noqa: C901, PLR0912
    """Execute the sub-command selected by *args.command*."""
    cmd = args.command

    if cmd == "transcode":
        require("ffmpeg", "ffprobe")
        transcode_library(dry_run=args.dry_run, force=args.force, jobs=args.jobs)

    elif cmd == "download":
        download(url=args.url)

    elif cmd == "import":
        beet_args = ["import", *(("-A",) if args.auto else ()), str(UNTAGGED_DIR)]
        sys.exit(run_beets(beet_args))

    elif cmd == "playlist":
        rc = run_beets(["splupdate"])
        if rc == 0:
            _generate_transcoded_playlists()
        sys.exit(rc)

    elif cmd == "relocate":
        _relocate_db()

    elif cmd == "clean":
        show_clean(force=args.force)

    elif cmd == "beet":
        beet_args = args.beet_args
        if beet_args and beet_args[0] == "--":
            beet_args = beet_args[1:]
        sys.exit(run_beets(beet_args))

    elif cmd == "info":
        show_info()

    elif cmd == "check-transcoded":
        show_check_transcoded()

    elif cmd == "audit":
        show_audit()


def main() -> None:
    parser = build_parser()
    args   = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    setup_logging(getattr(args, "verbose", False))
    _dispatch(args)


if __name__ == "__main__":
    main()
