from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Callable

from mutagen import File as MutagenFile
from mutagen.oggopus import OggOpus

from webui.artwork import embed_cover, read_embedded_cover


LOSSLESS = {".flac", ".wav", ".aiff", ".aif", ".alac"}
LOSSY = {".mp3", ".m4a", ".aac", ".ogg", ".opus", ".wma", ".mka"}


def _bitrate(source: Path) -> str:
    if source.suffix.lower() in LOSSLESS:
        return "192k"
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(source)],
            capture_output=True,
            text=True,
            check=True,
        )
        streams = json.loads(probe.stdout).get("streams", [])
        value = next(
            (int(stream["bit_rate"]) for stream in streams if stream.get("codec_type") == "audio" and str(stream.get("bit_rate", "")).isdigit()),
            128000,
        )
        return f"{max(64, min(value, 192000) // 1000 // 8 * 8)}k"
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, json.JSONDecodeError):
        return "128k"


def transcode_one(source: Path, destination: Path, force: bool = False) -> tuple[bool, str]:
    destination = destination.with_suffix(".opus")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and not force:
        return False, "skipped (exists)"
    command = [
        "ffmpeg", "-y", "-i", str(source), "-map", "0:a", "-c:a", "libopus",
        "-b:a", _bitrate(source), "-vbr", "on", "-compression_level", "10",
        "-application", "audio", "-map_metadata", "0", "-loglevel", "error", str(destination),
    ]
    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
        source_media = MutagenFile(str(source), easy=True)
        destination_media = OggOpus(str(destination))
        if source_media:
            for key, values in source_media.items():
                destination_media[key] = values
        destination_media.save()
        cover = read_embedded_cover(source)
        if cover:
            embed_cover(destination, cover)
        return True, "transcoded"
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        destination.unlink(missing_ok=True)
        return False, str(exc)


def transcode_files(
    sources: list[Path],
    original_root: Path,
    transcoded_root: Path,
    on_result: Callable[[Path, bool, str, int, int], None] | None = None,
    force: bool = False,
) -> tuple[int, int]:
    completed = failed = 0
    total = len(sources)
    for index, source in enumerate(sources, 1):
        relative = source.relative_to(original_root)
        ok, detail = transcode_one(source, transcoded_root / relative, force=force)
        if detail == "transcoded":
            completed += 1
        elif ok is False and "skipped" not in detail:
            failed += 1
        if on_result:
            on_result(source, ok or "skipped" in detail, detail, index, total)
    return completed, failed
