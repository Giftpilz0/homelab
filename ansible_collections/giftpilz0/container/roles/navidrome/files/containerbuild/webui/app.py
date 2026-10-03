from __future__ import annotations

import hmac
import json
import mimetypes
import os
import re
import shutil
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse, Response
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware
from webui.artwork import apply_artwork, fetch_release_artwork, read_embedded_cover
from webui.config import (
    DATA_DIR,
    IMPORT_DIR,
    MAX_ARTWORK_BYTES,
    ORIGINAL,
    PIPELINE_STAGES,
    ROOT,
    SUPPORTED_EXTENSIONS,
    TRANSCODED,
    UNTAGGED,
    WEBUI_HOST,
    WEBUI_PORT,
    WEBUI_TOKEN,
    WEBUI_WORKERS,
)
from webui.database import claim_job, connect, db_all, db_lock, db_one, db_run, init_db, now
from webui.maintenance import database_consistency, repair_beets_paths, transcoding_diff
from webui.media import (
    MutagenFile,
    album_files,
    audio_files,
    library_payload,
    managed_audio_files,
    read_metadata,
    safe_child as resolve_child,
)
from webui.transcoding import transcode_files


app = FastAPI(title="Music Library")
executor = ThreadPoolExecutor(max_workers=WEBUI_WORKERS)
cancel_flags: dict[str, threading.Event] = {}


class JobCancelled(Exception):
    pass


class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if WEBUI_TOKEN and request.url.path != "/health":
            supplied = request.headers.get("authorization", "")
            if hmac.compare_digest(supplied, f"Bearer {WEBUI_TOKEN}"):
                return await call_next(request)
            if supplied != f"Bearer {WEBUI_TOKEN}":
                return JSONResponse(
                    {"detail": "authentication required"},
                    status_code=401,
                    headers={"WWW-Authenticate": "Bearer"},
                )
        return await call_next(request)


app.add_middleware(AuthMiddleware)


class UrlRequest(BaseModel):
    url: str = Field(min_length=5, max_length=4096)


class ImportRequest(BaseModel):
    path: str = Field(min_length=1, max_length=4096)


class MetadataRequest(BaseModel):
    tracks: list[dict[str, Any]]


class ReleaseRequest(BaseModel):
    release_id: str
    track_ids: list[int] | None = None
    track_map: dict[str, int] | None = None


class DeleteRequest(BaseModel):
    path: str = Field(min_length=1, max_length=4096)
    confirmation: str = Field(min_length=1, max_length=32)


class ApproveRequest(BaseModel):
    fingerprint: bool = True
    replaygain: bool = True
    transcode: bool = True


class IdentifyRequest(BaseModel):
    force: bool = False
    track_ids: list[int] | None = None


class GroupMoveRequest(BaseModel):
    track_id: int
    target_track_id: int


class ClustersRequest(BaseModel):
    clusters: list[dict[str, Any]]


class LookupRequest(BaseModel):
    track_ids: list[int] | None = None
    query: str | None = None
    release_id: str | None = None


class LibraryActionRequest(BaseModel):
    path: str = Field(min_length=1, max_length=4096)
    action: str


def safe_child(parent: Path, candidate: str) -> Path:
    try:
        return resolve_child(parent, candidate)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc


def create_job(kind: str, source: str, options: dict[str, Any] | None = None) -> tuple[str, Path]:
    job_id = uuid.uuid4().hex
    staging = DATA_DIR / "staging" / job_id
    staging.mkdir(parents=True, exist_ok=True)
    cancel_flags[job_id] = threading.Event()
    timestamp = now()
    db_run(
        "INSERT INTO jobs(id,kind,status,source,staging_dir,options_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",
        (job_id, kind, "pending", source, str(staging), json.dumps(options or {}), timestamp, timestamp),
    )
    with db_lock, connect() as con:
        con.executemany(
            "INSERT INTO stages(job_id,name,label,status,position) VALUES(?,?,?,?,?)",
            [(job_id, name, label, "pending", position) for position, (name, label) in enumerate(PIPELINE_STAGES)],
        )
    return job_id, staging


def discard_job(job_id: str, staging: Path) -> None:
    if staging.exists():
        shutil.rmtree(staging)
    cancel_flags.pop(job_id, None)
    with db_lock, connect() as con:
        con.execute("DELETE FROM tracks WHERE job_id=?", (job_id,))
        con.execute("DELETE FROM events WHERE job_id=?", (job_id,))
        con.execute("DELETE FROM stages WHERE job_id=?", (job_id,))
        con.execute("DELETE FROM jobs WHERE id=?", (job_id,))


def update_job(job_id: str, status: str, error: str | None = None) -> None:
    db_run(
        "UPDATE jobs SET status=?, error=?, updated_at=? WHERE id=?",
        (status, error, now(), job_id),
    )


def event(job_id: str, message: str, level: str = "info") -> None:
    db_run(
        "INSERT INTO events(job_id,level,message,created_at) VALUES(?,?,?,?)",
        (job_id, level, message, now()),
    )


def set_stage(job_id: str, name: str, status: str, detail: str | None = None) -> None:
    timestamp = now()
    with db_lock, connect() as con:
        if status == "running":
            con.execute(
                "UPDATE stages SET status=?, detail=?, started_at=?, finished_at=NULL WHERE job_id=? AND name=?",
                (status, detail, timestamp, job_id, name),
            )
        else:
            con.execute(
                "UPDATE stages SET status=?, detail=?, finished_at=? WHERE job_id=? AND name=?",
                (status, detail, timestamp, job_id, name),
            )


def fail_stage(job_id: str, name: str, error: str) -> None:
    set_stage(job_id, name, "failed", error)


def complete_stage(job_id: str, name: str, detail: str | None = None) -> None:
    set_stage(job_id, name, "completed", detail)


def job_or_404(job_id: str) -> sqlite3.Row:
    job = db_one("SELECT * FROM jobs WHERE id=?", (job_id,))
    if not job:
        raise HTTPException(404, "job not found")
    return job


def beet_env() -> dict[str, str]:
    environment = os.environ.copy()
    environment["BEETSDIR"] = str(ROOT)
    venv_bin = str(ROOT / ".venv" / "bin")
    if venv_bin not in environment.get("PATH", ""):
        environment["PATH"] = venv_bin + os.pathsep + environment.get("PATH", "")
    return environment


def regenerate_playlists() -> None:
    result = subprocess.run(
        ["beet", "splupdate"],
        cwd=str(ROOT),
        env=beet_env(),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit status {result.returncode}"
        raise RuntimeError(f"beets playlist update failed: {detail}")
    source_dir = ORIGINAL / "playlists"
    destination_dir = TRANSCODED / "playlists"
    if not source_dir.exists():
        return
    destination_dir.mkdir(parents=True, exist_ok=True)
    for stale in destination_dir.glob("*.m3u"):
        if not (source_dir / stale.name).is_file():
            stale.unlink()
    for playlist in source_dir.glob("*.m3u"):
        lines = playlist.read_text(encoding="utf-8").splitlines(keepends=True)
        rewritten = []
        for line in lines:
            newline = line.endswith(("\n", "\r"))
            value = line.rstrip("\r\n")
            if value and not value.startswith("#") and Path(value).suffix.lower() in SUPPORTED_EXTENSIONS:
                value = str(Path(value).with_suffix(".opus")).replace(os.sep, "/")
            rewritten.append(value + ("\n" if newline else ""))
        (destination_dir / playlist.name).write_text("".join(rewritten), encoding="utf-8")


def add_tracks(job_id: str, paths: list[Path]) -> None:
    timestamp = now()
    with db_lock, connect() as con:
        for path in paths:
            metadata = read_metadata(path)
            try:
                has_embedded_cover = read_embedded_cover(path) is not None
            except Exception as exc:
                metadata["artwork_read_error"] = str(exc)
                has_embedded_cover = False
            con.execute(
                "INSERT INTO tracks(job_id,path,original_metadata_json,metadata_json,artwork_json,created_at) VALUES(?,?,?,?,?,?)",
                (
                    job_id,
                    str(path),
                    json.dumps(metadata),
                    json.dumps(metadata),
                    json.dumps({"embedded": True}) if has_embedded_cover else "{}",
                    timestamp,
                ),
            )


def mark_ready_for_review(job_id: str, count: int) -> None:
    complete_stage(job_id, "acquire", f"Staged {count} track(s)")
    set_stage(job_id, "fingerprint", "available", "Run fingerprinting from the review screen")
    set_stage(job_id, "review", "running", "Waiting for metadata approval")


def run_logged(job_id: str, command: list[str], cwd: Path | None = None) -> None:
    event(job_id, "$ " + " ".join(shlex_quote(x) for x in command))
    environment = os.environ.copy()
    environment["BEETSDIR"] = str(ROOT)
    venv_bin = str(ROOT / ".venv" / "bin")
    if venv_bin not in environment.get("PATH", ""):
        environment["PATH"] = venv_bin + os.pathsep + environment.get("PATH", "")
    process = subprocess.Popen(
        command,
        cwd=str(cwd or ROOT),
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    if process.stdout is None:
        process.kill()
        process.wait()
        raise RuntimeError("could not capture subprocess output")
    for line in process.stdout:
        if cancel_flags.get(job_id, threading.Event()).is_set():
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise JobCancelled("job cancelled by user")
        message = line.rstrip()
        if message:
            event(job_id, message)
    rc = process.wait()
    if cancel_flags.get(job_id, threading.Event()).is_set():
        raise JobCancelled("job cancelled by user")
    if rc:
        raise RuntimeError(f"command exited with status {rc}")


def shlex_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def download_worker(job_id: str, url: str, staging: Path) -> None:
    try:
        update_job(job_id, "downloading")
        set_stage(job_id, "acquire", "running", "Downloading with yt-dlp")
        event(job_id, f"Downloading {url}")
        output = str(staging / "%(artist,uploader)s" / "%(album,playlist,title)s" / "%(playlist_index|)s%(playlist_index& - |)s%(title)s.%(ext)s")
        command = [
            "yt-dlp", "--format", "bestaudio/best", "-x", "--audio-format", "opus",
            "--embed-metadata", "--embed-thumbnail", "--no-post-overwrites",
            "--restrict-filenames", "--windows-filenames", "--audio-quality", "0",
            "--retries", "10", "--fragment-retries", "10",
            "--output", output, "--yes-playlist" if "list=" in url else "--no-playlist", url,
        ]
        run_logged(job_id, command)
        paths = audio_files(staging)
        if not paths:
            raise RuntimeError("yt-dlp completed without producing an audio file")
        add_tracks(job_id, paths)
        complete_stage(job_id, "acquire", f"Downloaded {len(paths)} track(s)")
        set_stage(job_id, "fingerprint", "available", "Run fingerprinting from the review screen")
        update_job(job_id, "review")
        event(job_id, f"Downloaded {len(paths)} track(s); awaiting metadata review")
    except JobCancelled as exc:
        set_stage(job_id, "acquire", "skipped", "Cancelled by user")
        update_job(job_id, "cancelled", str(exc))
        event(job_id, "Download cancelled", "warning")
    except Exception as exc:
        fail_stage(job_id, "acquire", str(exc))
        update_job(job_id, "failed", str(exc))
        event(job_id, str(exc), "error")
    finally:
        cancel_flags.pop(job_id, None)


def apply_tag(path: Path, metadata: dict[str, Any]) -> None:
    if MutagenFile is None:
        raise RuntimeError("mutagen is not installed")
    media = MutagenFile(str(path), easy=True)
    if media is None:
        raise RuntimeError(f"unsupported audio file: {path.name}")
    allowed = {
        "title", "artist", "albumartist", "album", "date", "genre",
        "tracknumber", "tracktotal", "discnumber", "disctotal",
        "musicbrainz_albumid", "musicbrainz_trackid", "musicbrainz_releasegroupid",
        "musicbrainz_releasetrackid", "musicbrainz_workid",
        "musicbrainz_artistid", "musicbrainz_artistids",
        "musicbrainz_albumartistid", "musicbrainz_albumartistids",
        "artistsort", "albumartistsort", "albumsort", "originaldate",
        "barcode", "catalognumber", "label", "media", "country", "script",
        "language", "copyright", "comment", "grouping", "composer",
        "lyricist", "arranger", "compilation",
        "packaging", "length", "isrc",
    }
    allowed.update(key for key in metadata if key.startswith("musicbrainz_"))
    for key in allowed:
        if key not in metadata:
            continue
        value = metadata.get(key)
        if value is not None and str(value).strip():
            media[key] = [str(value).strip()]
        elif key in media:
            del media[key]
    media.save()


def fingerprint_file(path: Path) -> tuple[str, int]:
    result = subprocess.run(
        ["fpcalc", "-json", str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    payload = json.loads(result.stdout)
    fingerprint = str(payload.get("fingerprint", "")).strip()
    duration = int(float(payload.get("duration", 0)))
    if not fingerprint:
        raise RuntimeError(f"fpcalc returned no fingerprint for {path.name}")
    return fingerprint, duration


def acoustid_lookup(fingerprint: str, duration: int) -> list[dict[str, Any]]:
    api_key = os.getenv("ACOUSTID_API_KEY", "").strip()
    if not api_key:
        return []
    query = urllib.parse.urlencode(
        {
            "client": api_key,
            # AcoustID expects a space-separated list. urlencode() turns the
            # spaces into the required query-string separators.
            "meta": "recordings releasegroups releases",
            "duration": duration,
            "fingerprint": fingerprint,
            "format": "json",
        }
    )
    request = urllib.request.Request(
        f"https://api.acoustid.org/v2/lookup?{query}",
        headers={"User-Agent": "music-library-webui/0.1"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read())
    return payload.get("results", [])


def fingerprint_worker(job_id: str, track_ids: set[int] | None = None) -> None:
    try:
        update_job(job_id, "fingerprinting")
        set_stage(job_id, "fingerprint", "running", "Calculating Chromaprint fingerprints")
        tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
        if track_ids is not None:
            tracks = [track for track in tracks if track["id"] in track_ids]
        if not tracks:
            raise RuntimeError("no tracks were selected for fingerprinting")
        matches = 0
        for track in tracks:
            path = Path(track["path"])
            fingerprint, duration = fingerprint_file(path)
            matches_data = acoustid_lookup(fingerprint, duration)
            metadata = json.loads(track["metadata_json"])
            metadata["acoustid_fingerprint"] = fingerprint
            metadata["duration"] = duration
            metadata["acoustid_matches"] = matches_data
            if matches_data:
                matches += 1
            db_run(
                "UPDATE tracks SET metadata_json=? WHERE id=?",
                (json.dumps(metadata), track["id"]),
            )
        complete_stage(job_id, "fingerprint", f"Fingerprinted {len(tracks)} track(s); {matches} AcoustID match(es)")
        event(job_id, f"Fingerprinting complete: {matches} AcoustID match(es)")
        update_job(job_id, "review")
    except Exception as exc:
        fail_stage(job_id, "fingerprint", str(exc))
        update_job(job_id, "review", str(exc))
        event(job_id, str(exc), "error")
    finally:
        cancel_flags.pop(job_id, None)


def beet_queries(tracks: list[sqlite3.Row]) -> list[str]:
    queries: list[str] = []
    seen: set[str] = set()
    for track in tracks:
        metadata = json.loads(track["metadata_json"])
        mb_track_id = str(metadata.get("musicbrainz_trackid", "")).strip()
        if mb_track_id:
            query = f"mb_trackid:{mb_track_id}"
        else:
            album = str(metadata.get("album", "")).replace('"', '\\"').strip()
            albumartist = str(metadata.get("albumartist", "")).replace('"', '\\"').strip()
            if not album:
                continue
            query = f'album:"{album}"'
            if albumartist:
                query += f' albumartist:"{albumartist}"'
        if query not in seen:
            seen.add(query)
            queries.append(query)
    return queries


def beet_query_for_metadata(metadata: dict[str, Any]) -> str:
    mb_album_id = str(metadata.get("musicbrainz_albumid", "")).strip()
    if mb_album_id:
        return f"mb_albumid:{mb_album_id}"
    album = str(metadata.get("album", "")).replace('"', '\\"').strip()
    albumartist = str(metadata.get("albumartist", "")).replace('"', '\\"').strip()
    query = f'album:"{album}"'
    if albumartist:
        query += f' albumartist:"{albumartist}"'
    return query


def library_action_worker(job_id: str, source: Path, action: str) -> None:
    try:
        update_job(job_id, "processing")
        metadata = read_metadata(source)
        query = beet_query_for_metadata(metadata)
        if action == "fingerprint":
            set_stage(job_id, "fingerprint", "running", "Fingerprinting selected album")
            run_logged(job_id, ["beet", "fingerprint", query])
            complete_stage(job_id, "fingerprint", "Selected album fingerprinted")
        elif action == "replaygain":
            set_stage(job_id, "replaygain", "running", "Analyzing selected album")
            run_logged(job_id, ["beet", "replaygain", "-f", query])
            complete_stage(job_id, "replaygain", "Selected album ReplayGain updated")
        elif action == "transcode":
            set_stage(job_id, "transcode", "running", "Force-generating Opus files for selected album")
            sources = album_files(source)
            completed, failed = transcode_files(
                sources,
                ORIGINAL,
                TRANSCODED,
                lambda path, ok, detail, index, total: event(
                    job_id, f"Transcoding {index}/{total}: {path.name} ({detail})",
                    "error" if not ok else "info",
                ),
                force=True,
            )
            if failed:
                raise RuntimeError(f"{failed} album track(s) failed to transcode")
            complete_stage(job_id, "transcode", f"{completed} Opus file(s) regenerated")
        else:
            raise RuntimeError(f"unsupported library action: {action}")
        update_job(job_id, "completed")
        event(job_id, f"{action} completed for {query}")
    except Exception as exc:
        update_job(job_id, "failed", str(exc))
        event(job_id, str(exc), "error")
    finally:
        cancel_flags.pop(job_id, None)


def process_worker(job_id: str) -> None:
    job = job_or_404(job_id)
    try:
        update_job(job_id, "processing")
        tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
        if not tracks:
            raise RuntimeError("job contains no audio tracks")
        options = json.loads(job["options_json"] or "{}")
        set_stage(job_id, "review", "completed", "Approved by user")
        set_stage(job_id, "tag", "running", "Writing reviewed metadata")
        for track in tracks:
            metadata = json.loads(track["metadata_json"])
            apply_tag(Path(track["path"]), metadata)
            artwork = json.loads(track["artwork_json"] or "{}")
            proposed_artwork = artwork.get("proposed")
            if proposed_artwork:
                apply_artwork(Path(track["path"]), Path(proposed_artwork))
        complete_stage(job_id, "tag", "Metadata written to staged files")
        event(job_id, "Metadata written to staged files")

        # beets performs the canonical move and updates the library database.
        # The UI has already produced the reviewed tags.  -A prevents beets
        # from replacing them with a fresh automatic match; -q guarantees that
        # a duplicate or ambiguous album cannot block the worker indefinitely.
        set_stage(job_id, "import", "running", "Moving files through beets")
        run_logged(job_id, ["beet", "import", "-A", "-q", "-m", str(Path(job["staging_dir"]))])
        complete_stage(job_id, "import", "Files moved into the managed library")
        queries = beet_queries(tracks)
        if options.get("fingerprint", True):
            if queries:
                set_stage(job_id, "fingerprint", "running", "Fingerprinting approved tracks")
                run_logged(job_id, ["beet", "fingerprint", *queries])
                complete_stage(job_id, "fingerprint", "Approved tracks fingerprinted")
            else:
                set_stage(job_id, "fingerprint", "skipped", "No safe beets query could be built")
        else:
            set_stage(job_id, "fingerprint", "skipped", "Skipped by approval options")
        if options.get("replaygain", True) and queries:
            set_stage(job_id, "replaygain", "running", "Calculating ReplayGain for approved albums")
            run_logged(job_id, ["beet", "replaygain", "-f", *queries] if queries else ["beet", "replaygain", "-f"])
            complete_stage(job_id, "replaygain", "Approved albums analyzed")
        elif options.get("replaygain", True):
            set_stage(job_id, "replaygain", "skipped", "No safe beets query could be built")
        else:
            set_stage(job_id, "replaygain", "skipped", "Skipped by approval options")
        if options.get("transcode", True):
            set_stage(job_id, "transcode", "running", "Generating Opus serving files")
            sources = []
            for track in tracks:
                metadata = json.loads(track["metadata_json"])
                artist = str(metadata.get("albumartist") or metadata.get("artist") or "").casefold()
                album = str(metadata.get("album") or "").casefold()
                sources.extend(
                    candidate for candidate in managed_audio_files()
                    if str((read_metadata(candidate).get("albumartist") or read_metadata(candidate).get("artist") or "")).casefold() == artist
                    and str(read_metadata(candidate).get("album") or "").casefold() == album
                )
            sources = sorted(set(sources))
            completed, failed = transcode_files(
                sources,
                ORIGINAL,
                TRANSCODED,
                lambda path, ok, detail, index, total: event(
                    job_id, f"Transcoding {index}/{total}: {path.name} ({detail})",
                    "error" if not ok else "info",
                ),
            )
            if failed:
                raise RuntimeError(f"{failed} track(s) failed to transcode")
            complete_stage(job_id, "transcode", f"{completed} Opus file(s) generated")
        else:
            set_stage(job_id, "transcode", "skipped", "Skipped by approval options")
        set_stage(job_id, "playlists", "running", "Regenerating smart playlists")
        regenerate_playlists()
        complete_stage(job_id, "playlists", "Playlists regenerated")
        update_job(job_id, "completed")
        event(job_id, "Approved item is now in the library")
    except Exception as exc:
        for stage in ("tag", "import", "replaygain", "transcode", "playlists"):
            stage_row = db_one("SELECT status FROM stages WHERE job_id=? AND name=?", (job_id, stage))
            if stage_row and stage_row["status"] == "running":
                fail_stage(job_id, stage, str(exc))
        update_job(job_id, "failed", str(exc))
        event(job_id, str(exc), "error")
    finally:
        cancel_flags.pop(job_id, None)


def job_payload(job: sqlite3.Row) -> dict[str, Any]:
    tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job["id"],))
    events = db_all("SELECT level,message,created_at FROM events WHERE job_id=? ORDER BY id", (job["id"],))
    stages = db_all("SELECT * FROM stages WHERE job_id=? ORDER BY position", (job["id"],))
    return {
        "id": job["id"], "kind": job["kind"], "status": job["status"], "source": job["source"],
        "error": job["error"], "created_at": job["created_at"], "updated_at": job["updated_at"],
        "options": json.loads(job["options_json"] or "{}"),
        "tracks": [
            {
                **dict(t),
                "metadata": json.loads(t["metadata_json"]),
                "original_metadata": json.loads(t["original_metadata_json"]),
                "artwork": json.loads(t["artwork_json"] or "{}"),
            }
            for t in tracks
        ],
        "stages": [dict(stage) for stage in stages],
        "events": [dict(e) for e in events],
    }


def musicbrainz_request(path: str) -> dict[str, Any]:
    request = urllib.request.Request(
        "https://musicbrainz.org/ws/2/" + path,
        headers={"User-Agent": "music-library-webui/0.1 (personal library)"},
    )
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as exc:
            last_error = exc
            if exc.code not in {429, 500, 502, 503, 504} or attempt == 2:
                break
            time.sleep(float(2**attempt))
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            if attempt == 2:
                break
            time.sleep(float(2**attempt))
        except Exception as exc:
            raise HTTPException(502, f"MusicBrainz request failed: {exc}") from exc
    raise HTTPException(502, f"MusicBrainz is temporarily unavailable after 3 attempts: {last_error}") from last_error


def normalise_text(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value or "").casefold())


def metadata_group_key(metadata: dict[str, Any]) -> str:
    return "|".join(
        str(metadata.get(field) or "").strip()
        for field in ("albumartist", "artist", "album", "date")
    ).casefold()


def identification_metadata(metadata: dict[str, Any]) -> tuple[str, str, str]:
    artist = str(metadata.get("artist") or metadata.get("albumartist") or "").strip()
    title = str(metadata.get("title") or "").strip()
    album = str(metadata.get("album") or "").strip()
    title = re.sub(r"\s+\[(?:official|audio|lyrics?|music video)[^\]]*\]\s*$", "", title, flags=re.IGNORECASE)
    if not artist and " - " in title:
        inferred_artist, inferred_title = title.split(" - ", 1)
        if inferred_artist.strip() and inferred_title.strip():
            artist, title = inferred_artist.strip(), inferred_title.strip()
    return artist, title, album


def release_suggestions(tracks: list[sqlite3.Row]) -> list[dict[str, Any]]:
    groups: dict[tuple[str, str], list[sqlite3.Row]] = {}
    for track in tracks:
        metadata = json.loads(track["metadata_json"])
        artist, _title, album = identification_metadata(metadata)
        key = (artist, album)
        groups.setdefault(key, []).append(track)
    suggestions: dict[str, dict[str, Any]] = {}
    for (artist, album), group in groups.items():
        if album:
            query_parts = [f'release:"{album}"']
            if artist:
                query_parts.append(f'artist:"{artist}"')
            result = musicbrainz_request(
                f"release/?query={urllib.parse.quote(' AND '.join(query_parts))}&fmt=json&limit=12"
            )
        else:
            result = {"releases": []}
            for track in group:
                metadata = json.loads(track["metadata_json"])
                track_artist, title, _ = identification_metadata(metadata)
                if not title:
                    continue
                query_parts = [f'recording:"{title}"']
                if track_artist:
                    query_parts.append(f'artist:"{track_artist}"')
                recording_query = urllib.parse.quote(" AND ".join(query_parts))
                recording_result = musicbrainz_request(
                    f"recording/?query={recording_query}&inc=releases+artist-credits&fmt=json&limit=8"
                )
                for recording in recording_result.get("recordings", []):
                    for release in recording.get("releases", []):
                        release.setdefault("artist-credit", recording.get("artist-credit", []))
                        result["releases"].append(release)
        for release in result.get("releases", []):
            release_artist = ", ".join(item.get("name", "") for item in release.get("artist-credit", []))
            score = int(release.get("score", 0))
            if normalise_text(release.get("title")) == normalise_text(album):
                score += 25
            if normalise_text(release_artist) == normalise_text(artist):
                score += 15
            release_id = release.get("id")
            if release_id:
                suggestions[release_id] = {
                    "id": release_id,
                    "title": release.get("title", ""),
                    "artist": release_artist,
                    "date": release.get("date", ""),
                    "country": release.get("country", ""),
                    "track_count": len(group),
                    "score": score,
                    "source": "MusicBrainz release search",
                    "track_ids": [track["id"] for track in group],
                    "group_key": f"{artist}|{album}".casefold(),
                }
        for track in group:
            metadata = json.loads(track["metadata_json"])
            for match in metadata.get("acoustid_matches", []):
                for recording in match.get("recordings", []):
                    for release in recording.get("releases", []):
                        release_id = release.get("id")
                        if release_id and release_id not in suggestions:
                            suggestions[release_id] = {
                                "id": release_id,
                                "title": release.get("title", ""),
                                "artist": ", ".join(
                                    artist_credit.get("name", "")
                                    for artist_credit in recording.get("artists", [])
                                ),
                                "date": release.get("date", ""),
                                "country": release.get("country", ""),
                                "track_count": 1,
                                "score": int(float(match.get("score", 0)) * 100),
                                "source": "AcoustID release",
                                "track_ids": [track["id"] for track in group],
                                "group_key": f"{artist}|{album}".casefold(),
                            }
                    for release_group in recording.get("releasegroups", []):
                        release_id = release_group.get("id")
                        if release_id and release_id not in suggestions:
                            suggestions[release_id] = {
                                "id": release_id,
                                "title": release_group.get("title", ""),
                                "artist": ", ".join(
                                    artist_credit.get("name", "")
                                    for artist_credit in recording.get("artists", [])
                                ),
                                "date": "",
                                "country": "",
                                "track_count": 1,
                                "score": int(float(match.get("score", 0)) * 100),
                                "source": "AcoustID release group",
                                "track_ids": [track["id"] for track in group],
                                "group_key": f"{artist}|{album}".casefold(),
                            }
    return sorted(suggestions.values(), key=lambda item: (-item["score"], item["title"].casefold()))[:30]


def fetch_musicbrainz_release(release_id: str) -> tuple[str, dict[str, Any]]:
    try:
        return release_id, musicbrainz_request(
            f"release/{release_id}?inc=artists+recordings+release-groups&fmt=json"
        )
    except HTTPException as exc:
        if exc.status_code != 502:
            raise
        release_group = musicbrainz_request(
            f"release-group/{release_id}?inc=releases+artists&fmt=json"
        )
        releases = release_group.get("releases", [])
        if not releases or not releases[0].get("id"):
            raise HTTPException(502, "MusicBrainz release group has no releases") from exc
        concrete_id = releases[0]["id"]
        return concrete_id, musicbrainz_request(
            f"release/{concrete_id}?inc=artists+recordings+release-groups&fmt=json"
        )


@app.on_event("startup")
def startup() -> None:
    repair_beets_paths(ROOT)
    init_db()
    with db_lock, connect() as con:
        interrupted = con.execute(
            "SELECT id FROM jobs WHERE status IN ('downloading','fingerprinting','processing')"
        ).fetchall()
        if interrupted:
            ids = [row["id"] for row in interrupted]
            placeholders = ",".join("?" for _ in ids)
            con.execute(
                f"UPDATE jobs SET status='failed', error='Interrupted by application restart', updated_at=? WHERE id IN ({placeholders})",
                (now(), *ids),
            )
            con.execute(
                f"UPDATE stages SET status='failed', detail='Interrupted by application restart', finished_at=? WHERE job_id IN ({placeholders}) AND status='running'",
                (now(), *ids),
            )
            for job_id in ids:
                con.execute(
                    "INSERT INTO events(job_id,level,message,created_at) VALUES(?,?,?,?)",
                    (job_id, "warning", "Job interrupted by application restart", now()),
                )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return (Path(__file__).parent / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/api/jobs")
def list_jobs() -> list[dict[str, Any]]:
    return [job_payload(job) for job in db_all("SELECT * FROM jobs ORDER BY created_at DESC LIMIT 100")]


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str) -> dict[str, Any]:
    return job_payload(job_or_404(job_id))


@app.post("/api/jobs/{job_id}/cancel")
def cancel_job(job_id: str) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] != "downloading":
        raise HTTPException(409, "only active downloads can be cancelled")
    cancel_flags.setdefault(job_id, threading.Event()).set()
    event(job_id, "Cancellation requested", "warning")
    return {"status": "cancelling"}


@app.delete("/api/jobs")
def clear_finished_jobs(request: Request) -> dict[str, int]:
    if request.headers.get("x-confirm-delete") != "yes":
        raise HTTPException(400, "delete confirmation required")
    jobs = db_all("SELECT id,staging_dir FROM jobs WHERE status IN ('completed','failed','cancelled')")
    for job in jobs:
        staging = Path(job["staging_dir"])
        if staging.exists():
            shutil.rmtree(staging)
        cancel_flags.pop(job["id"], None)
    with db_lock, connect() as con:
        con.execute("DELETE FROM tracks WHERE job_id IN (SELECT id FROM jobs WHERE status IN ('completed','failed','cancelled'))")
        con.execute("DELETE FROM events WHERE job_id IN (SELECT id FROM jobs WHERE status IN ('completed','failed','cancelled'))")
        con.execute("DELETE FROM stages WHERE job_id IN (SELECT id FROM jobs WHERE status IN ('completed','failed','cancelled'))")
        con.execute("DELETE FROM jobs WHERE status IN ('completed','failed','cancelled')")
    return {"deleted": len(jobs)}


@app.delete("/api/jobs/{job_id}")
def delete_job(job_id: str, request: Request) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] in {"downloading", "fingerprinting", "processing"}:
        raise HTTPException(409, "running jobs cannot be deleted")
    if request.headers.get("x-confirm-delete") != "yes":
        raise HTTPException(400, "delete confirmation required")
    staging = Path(job["staging_dir"])
    if staging.exists():
        shutil.rmtree(staging)
    cancel_flags.pop(job_id, None)
    with db_lock, connect() as con:
        con.execute("DELETE FROM tracks WHERE job_id=?", (job_id,))
        con.execute("DELETE FROM events WHERE job_id=?", (job_id,))
        con.execute("DELETE FROM stages WHERE job_id=?", (job_id,))
        con.execute("DELETE FROM jobs WHERE id=?", (job_id,))
    return {"status": "deleted"}


@app.get("/api/library")
def get_library(q: str = "") -> list[dict[str, Any]]:
    return library_payload(q)


@app.get("/api/maintenance/database")
def check_database_consistency() -> dict[str, Any]:
    return database_consistency(ROOT, SUPPORTED_EXTENSIONS)


@app.post("/api/maintenance/database/repair")
def repair_database_consistency() -> dict[str, Any]:
    result = repair_beets_paths(ROOT)
    result["consistency"] = database_consistency(ROOT, SUPPORTED_EXTENSIONS)
    return result


@app.get("/api/maintenance/transcoding")
def check_transcoding_consistency() -> dict[str, Any]:
    return transcoding_diff(ROOT, SUPPORTED_EXTENSIONS)


@app.delete("/api/library/item")
def delete_library_item(request: DeleteRequest) -> dict[str, str]:
    if request.confirmation != "DELETE":
        raise HTTPException(400, "type DELETE to confirm library removal")
    source = safe_child(ORIGINAL, request.path)
    managed_roots = (ORIGINAL / "lossless_compression", ORIGINAL / "lossy_compression")
    if not source.exists() or not source.is_file() or not any(source == root or root in source.parents for root in managed_roots):
        raise HTTPException(404, "managed library file not found")
    if UNTAGGED in source.parents:
        raise HTTPException(400, "staged files must be removed from their job")
    result = subprocess.run(
        ["beet", "remove", "-f", f"path:{source}"],
        cwd=str(ROOT),
        env=beet_env(),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HTTPException(500, f"could not remove file from beets: {result.stderr.strip()}")
    relative = source.relative_to(ORIGINAL)
    transcoded = (TRANSCODED / relative).with_suffix(".opus")
    source.unlink()
    transcoded.unlink(missing_ok=True)
    regenerate_playlists()
    return {"status": "deleted", "path": str(relative)}


@app.delete("/api/library/album")
def delete_library_album(request: DeleteRequest) -> dict[str, Any]:
    if request.confirmation != "DELETE":
        raise HTTPException(400, "type DELETE to confirm library removal")
    source = safe_child(ORIGINAL, request.path)
    managed_roots = (ORIGINAL / "lossless_compression", ORIGINAL / "lossy_compression")
    if not source.is_file() or not any(source == root or root in source.parents for root in managed_roots):
        raise HTTPException(404, "managed library file not found")
    targets = album_files(source)
    for target in targets:
        result = subprocess.run(
            ["beet", "remove", "-f", f"path:{target}"],
            cwd=str(ROOT),
            env=beet_env(),
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise HTTPException(500, f"could not remove file from beets: {result.stderr.strip()}")
        relative = target.relative_to(ORIGINAL)
        (TRANSCODED / relative).with_suffix(".opus").unlink(missing_ok=True)
        target.unlink(missing_ok=True)
    regenerate_playlists()
    return {"status": "deleted", "count": len(targets)}


@app.post("/api/library/action", status_code=202)
def run_library_action(request: LibraryActionRequest) -> dict[str, str]:
    if request.action not in {"fingerprint", "replaygain", "transcode"}:
        raise HTTPException(400, "unsupported library action")
    source = safe_child(ORIGINAL, request.path)
    managed_roots = (ORIGINAL / "lossless_compression", ORIGINAL / "lossy_compression")
    if not source.is_file() or not any(source == root or root in source.parents for root in managed_roots):
        raise HTTPException(404, "managed library file not found")
    job_id, _ = create_job("maintenance", f"{request.action}: {request.path}", {"action": request.action})
    executor.submit(library_action_worker, job_id, source, request.action)
    return {"id": job_id}


@app.get("/api/jobs/{job_id}/tracks/{track_id}/cover")
def get_track_cover(job_id: str, track_id: int) -> Response:
    job_or_404(job_id)
    track = db_one("SELECT * FROM tracks WHERE job_id=? AND id=?", (job_id, track_id))
    if not track:
        raise HTTPException(404, "track not found")
    if MutagenFile is None:
        raise HTTPException(503, "mutagen is not installed")
    return cover_response(Path(track["path"]))


@app.get("/api/jobs/{job_id}/tracks/{track_id}/artwork")
def get_track_artwork(job_id: str, track_id: int, variant: str = "proposed") -> Response:
    job_or_404(job_id)
    track = db_one("SELECT * FROM tracks WHERE job_id=? AND id=?", (job_id, track_id))
    if not track:
        raise HTTPException(404, "track not found")
    artwork = json.loads(track["artwork_json"] or "{}")
    if variant == "proposed" and artwork.get("proposed"):
        path = Path(artwork["proposed"])
        if path.is_file():
            mime = mimetypes.guess_type(path.name)[0] or "image/jpeg"
            return Response(path.read_bytes(), media_type=mime)
    if variant == "proposed":
        return Response(status_code=204)
    return cover_response(Path(track["path"]))


@app.post("/api/jobs/{job_id}/tracks/{track_id}/artwork")
async def upload_track_artwork(job_id: str, track_id: int, file: UploadFile = File(...)) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "artwork can only be edited during review")
    track = db_one("SELECT * FROM tracks WHERE job_id=? AND id=?", (job_id, track_id))
    if not track:
        raise HTTPException(404, "track not found")
    mime = file.content_type or mimetypes.guess_type(file.filename or "")[0] or ""
    if not mime.startswith("image/"):
        raise HTTPException(400, "artwork upload must be an image")
    suffix = Path(file.filename or "artwork.jpg").suffix.lower() or ".jpg"
    if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        raise HTTPException(400, "unsupported artwork format")
    data = await file.read(MAX_ARTWORK_BYTES + 1)
    if len(data) > MAX_ARTWORK_BYTES:
        raise HTTPException(413, "artwork file is too large")
    destination = DATA_DIR / "staging" / job_id / "artwork" / f"manual{suffix}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    selected_metadata = json.loads(track["metadata_json"])
    selected_artist = str(selected_metadata.get("albumartist") or selected_metadata.get("artist") or "").casefold()
    selected_album = str(selected_metadata.get("album") or "").casefold()
    job_tracks = db_all("SELECT id,metadata_json FROM tracks WHERE job_id=?", (job_id,))
    with db_lock, connect() as con:
        for item in job_tracks:
            metadata = json.loads(item["metadata_json"])
            artist = str(metadata.get("albumartist") or metadata.get("artist") or "").casefold()
            album = str(metadata.get("album") or "").casefold()
            if artist == selected_artist and album == selected_album:
                con.execute(
                    "UPDATE tracks SET artwork_json=? WHERE id=? AND job_id=?",
                    (json.dumps({"proposed": str(destination), "source": "manual"}), item["id"], job_id),
                )
    event(job_id, "Uploaded replacement album artwork")
    return {"status": "saved", "path": str(destination)}


def cover_response(path: Path) -> Response:
    if MutagenFile is None:
        raise HTTPException(503, "mutagen is not installed")
    try:
        cover = read_embedded_cover(path)
        if cover:
            data, mime = cover
            return Response(data, media_type=mime)
    except Exception as exc:
        raise HTTPException(422, f"could not read artwork: {exc}") from exc
    return Response(status_code=204)


@app.get("/api/library/cover")
def get_library_cover(path: str) -> Response:
    source = safe_child(ORIGINAL, path)
    managed_roots = (ORIGINAL / "lossless_compression", ORIGINAL / "lossy_compression")
    if not source.is_file() or not any(source == root or root in source.parents for root in managed_roots):
        raise HTTPException(404, "managed library file not found")
    return cover_response(source)


@app.post("/api/jobs/url", status_code=202)
def create_url_job(request: UrlRequest) -> dict[str, str]:
    parsed = urllib.parse.urlparse(request.url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise HTTPException(400, "URL must use http or https")
    job_id, staging = create_job("url", request.url)
    executor.submit(download_worker, job_id, request.url, staging)
    return {"id": job_id}


@app.post("/api/jobs/upload", status_code=202)
async def create_upload_job(files: list[UploadFile] = File(...)) -> dict[str, str]:
    if not files:
        raise HTTPException(400, "at least one audio file is required")
    invalid = [
        Path(upload.filename or "upload.bin").name
        for upload in files
        if Path(upload.filename or "upload.bin").suffix.lower() not in SUPPORTED_EXTENSIONS
    ]
    if invalid:
        raise HTTPException(400, f"unsupported audio extension: {invalid[0]}")
    job_id, staging = create_job("upload", f"{len(files)} uploaded file(s)")
    try:
        for upload in files:
            name = Path(upload.filename or "upload.bin").name
            target = staging / name
            if target.exists():
                stem = target.stem
                suffix = target.suffix
                index = 2
                while target.exists():
                    target = staging / f"{stem} ({index}){suffix}"
                    index += 1
            with target.open("wb") as output:
                shutil.copyfileobj(upload.file, output)
        paths = audio_files(staging)
        if not paths:
            raise ValueError("no supported audio files uploaded")
        add_tracks(job_id, paths)
        mark_ready_for_review(job_id, len(paths))
        update_job(job_id, "review")
        event(job_id, f"Uploaded {len(paths)} track(s); awaiting metadata review")
        return {"id": job_id}
    except Exception as exc:
        discard_job(job_id, staging)
        raise HTTPException(500, f"could not stage uploaded files: {exc}") from exc


@app.post("/api/jobs/import", status_code=202)
def create_import_job(request: ImportRequest) -> dict[str, str]:
    source = safe_child(IMPORT_DIR, request.path)
    if not source.exists():
        raise HTTPException(404, "import path does not exist")
    paths = [source] if source.is_file() else audio_files(source)
    if not paths or any(path.suffix.lower() not in SUPPORTED_EXTENSIONS for path in paths):
        raise HTTPException(400, "no supported audio files found")
    job_id, staging = create_job("folder", str(source))
    try:
        for path in paths:
            relative = path.name if source.is_file() else path.relative_to(source)
            destination = staging / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
        staged = audio_files(staging)
        if not staged:
            raise ValueError("no supported audio files found")
        add_tracks(job_id, staged)
        mark_ready_for_review(job_id, len(staged))
        update_job(job_id, "review")
        event(job_id, f"Imported {len(staged)} track(s) into staging; awaiting metadata review")
        return {"id": job_id}
    except Exception as exc:
        discard_job(job_id, staging)
        raise HTTPException(500, f"could not stage import: {exc}") from exc


@app.post("/api/jobs/reprocess", status_code=202)
def create_reprocess_job(request: ImportRequest) -> dict[str, str]:
    """Copy an existing managed file into staging for metadata/gain repair."""
    source = safe_child(ORIGINAL, request.path)
    if not source.exists() or not source.is_file() or source.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise HTTPException(404, "managed audio file not found")
    job_id, staging = create_job("reprocess", str(source))
    try:
        destination = staging / source.name
        shutil.copy2(source, destination)
        add_tracks(job_id, [destination])
        mark_ready_for_review(job_id, 1)
        update_job(job_id, "review")
        event(job_id, "Existing file copied into staging for review")
        return {"id": job_id}
    except Exception as exc:
        discard_job(job_id, staging)
        raise HTTPException(500, f"could not stage file for reprocessing: {exc}") from exc


@app.put("/api/jobs/{job_id}/metadata")
def update_metadata(job_id: str, request: MetadataRequest) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "metadata can only be edited during review")
    with db_lock, connect() as con:
        for item in request.tracks:
            track_id = item.get("id")
            metadata = item.get("metadata")
            if not isinstance(track_id, int) or not isinstance(metadata, dict):
                raise HTTPException(400, "invalid track metadata payload")
            con.execute("UPDATE tracks SET metadata_json=? WHERE id=? AND job_id=?", (json.dumps(metadata), track_id, job_id))
    event(job_id, "Metadata draft saved")
    return {"status": "saved"}


@app.put("/api/jobs/{job_id}/groups")
def move_track_to_group(job_id: str, request: GroupMoveRequest) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "tracks can only be regrouped during review")
    tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
    by_id = {track["id"]: track for track in tracks}
    source = by_id.get(request.track_id)
    target = by_id.get(request.target_track_id)
    if source is None or target is None:
        raise HTTPException(404, "track not found in this job")
    target_metadata = json.loads(target["metadata_json"])
    target_key = target["group_key"] or metadata_group_key(target_metadata)
    target_members = [
        track["id"]
        for track in tracks
        if (track["group_key"] or metadata_group_key(json.loads(track["metadata_json"]))) == target_key
    ]
    if request.track_id not in target_members:
        target_members.append(request.track_id)
    placeholders = ",".join("?" for _ in target_members)
    with db_lock, connect() as con:
        con.execute(
            f"UPDATE tracks SET group_key=? WHERE job_id=? AND id IN ({placeholders})",
            (target_key, job_id, *target_members),
        )
    event(job_id, f"Moved track {request.track_id} into album group")
    return {"status": "grouped", "group_key": target_key}


@app.put("/api/jobs/{job_id}/clusters")
def save_album_clusters(job_id: str, request: ClustersRequest) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "clusters can only be edited during review")
    options = json.loads(job["options_json"] or "{}")
    options["clusters"] = request.clusters
    db_run(
        "UPDATE jobs SET options_json=?, updated_at=? WHERE id=?",
        (json.dumps(options), now(), job_id),
    )
    return {"status": "saved"}


@app.post("/api/jobs/{job_id}/fingerprint", status_code=202)
def start_fingerprinting(job_id: str) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "job is not ready for fingerprinting")
    if not claim_job(job_id, job["status"], "fingerprinting"):
        raise HTTPException(409, "job changed before fingerprinting could start")
    executor.submit(fingerprint_worker, job_id)
    return {"status": "fingerprinting"}


@app.post("/api/jobs/{job_id}/identify")
def identify_job(job_id: str, request: IdentifyRequest) -> dict[str, Any]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "job is not ready for identification")
    tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
    selected_ids = set(request.track_ids or [track["id"] for track in tracks])
    if request.track_ids:
        tracks = [track for track in tracks if track["id"] in selected_ids]
    if not tracks:
        raise HTTPException(400, "no tracks were selected for identification")
    def needs_acoustid_refresh(track: sqlite3.Row) -> bool:
        metadata = json.loads(track["metadata_json"])
        matches = metadata.get("acoustid_matches") or []
        return (
            request.force
            or not metadata.get("acoustid_fingerprint")
            or any(
                not match.get("recordings")
                for match in matches
                if isinstance(match, dict)
            )
        )

    if any(needs_acoustid_refresh(track) for track in tracks):
        if not claim_job(job_id, job["status"], "fingerprinting"):
            raise HTTPException(409, "job changed before identification could start")
        fingerprint_worker(job_id, selected_ids)
        all_tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
        selected_ids = set(request.track_ids or [track["id"] for track in all_tracks])
        tracks = [track for track in all_tracks if track["id"] in selected_ids]
        if not tracks:
            raise HTTPException(400, "no tracks were selected for MusicBrainz application")
    suggestions = release_suggestions(tracks)
    acoustid_configured = bool(os.getenv("ACOUSTID_API_KEY", "").strip())
    event(job_id, f"Found {len(suggestions)} identification candidate(s)")
    if not acoustid_configured:
        event(job_id, "AcoustID lookup skipped: ACOUSTID_API_KEY is not configured", "warning")
    return {
        "suggestions": suggestions,
        "diagnostics": {
            "tracks_fingerprinted": sum(
                bool(json.loads(track["metadata_json"]).get("acoustid_fingerprint"))
                for track in tracks
            ),
            "acoustid_configured": acoustid_configured,
            "musicbrainz_fallback": True,
        },
    }


def clean_tag(text: str) -> str:
    if not text:
        return ""
    # Strip year prefixes like '2013 - ', '[2013] ', '2013- '
    t = re.sub(r"^(?:\[\d{4}\]|\d{4}\s*[-_–]\s*)", "", text).strip()
    # Strip edition/version specifiers in brackets/parentheses
    t = re.sub(
        r"\s*[\(\[](?:deluxe|remaster|edition|bonus|version|explicit|special|expanded|reissue|anniversary|flac|lossy)[^\)\]]*[\)\]]",
        "",
        t,
        flags=re.I,
    ).strip()
    # Replace underscores with spaces (e.g. Motionless_In_White)
    t = t.replace("_", " ").strip()
    return t


def normalize_title(title: str) -> str:
    # Strip leading track numbers like "01 - ", "01_", "01. "
    t = re.sub(r"^\d+\s*[-_.]\s*", "", str(title))
    return re.sub(r"[^a-z0-9]+", "", t.casefold())


def match_tracks(release_tracks: list[dict[str, Any]], staged_tracks: list[dict[str, Any]]) -> tuple[dict[str, int], dict[str, int]]:
    assignments: dict[str, int] = {}
    scores: dict[str, int] = {}
    matrix: list[tuple[int, int, int]] = []
    
    for r_idx, r_t in enumerate(release_tracks):
        r_title_norm = normalize_title(r_t.get("title", ""))
        r_artist_norm = re.sub(r"[^a-z0-9]+", "", str(r_t.get("artist", "")).casefold())
        r_pos = int(r_t.get("position", r_idx + 1))
        raw_len = float(r_t.get("length", 0))
        r_len = raw_len / 1000.0 if raw_len > 1000 else raw_len
        
        for s_t in staged_tracks:
            score = 0
            s_title_norm = normalize_title(s_t.get("title", ""))
            s_artist_norm = re.sub(r"[^a-z0-9]+", "", str(s_t.get("artist", "")).casefold())
            
            # Title similarity
            if r_title_norm and s_title_norm:
                if r_title_norm == s_title_norm:
                    score += 50
                elif r_title_norm in s_title_norm or s_title_norm in r_title_norm:
                    score += 35
            # Track position
            try:
                num_match = re.match(r"(\d+)", str(s_t.get("tracknumber", "")))
                if num_match and int(num_match.group(1)) == r_pos:
                    score += 30
            except Exception:
                pass
            # Artist similarity
            if r_artist_norm and s_artist_norm:
                if r_artist_norm == s_artist_norm:
                    score += 15
                elif r_artist_norm in s_artist_norm or s_artist_norm in r_artist_norm:
                    score += 10
            # Duration match
            s_dur = float(s_t.get("duration", 0))
            if r_len > 0 and s_dur > 0:
                diff = abs(r_len - s_dur)
                if diff <= 2.0:
                    score += 30
                elif diff <= 6.0:
                    score += 20
                elif diff <= 15.0:
                    score += 10
                elif diff > 45.0:
                    score -= 20
                    
            if score >= 25:
                matrix.append((score, r_idx, s_t["id"]))
                
    matrix.sort(key=lambda x: -x[0])
    used_release = set()
    used_staged = set()
    for score, r_idx, s_id in matrix:
        if r_idx not in used_release and s_id not in used_staged:
            assignments[str(r_idx)] = s_id
            scores[str(r_idx)] = score
            used_release.add(r_idx)
            used_staged.add(s_id)
            
    return assignments, scores


@app.post("/api/jobs/{job_id}/cluster")
def cluster_job(job_id: str) -> dict[str, Any]:
    job = job_or_404(job_id)
    tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
    clusters_dict: dict[str, dict[str, Any]] = {}
    unclustered_ids: list[int] = []
    staging = Path(job["staging_dir"])
    
    for track in tracks:
        metadata = json.loads(track["metadata_json"])
        artist = str(metadata.get("albumartist") or metadata.get("artist") or "").strip()
        album = str(metadata.get("album") or "").strip()
        path = Path(track["path"])
        
        if not album and path.parent != staging and staging in path.parents:
            album = path.parent.name
            
        if album:
            key = f"{artist} - {album}" if artist else album
            if key not in clusters_dict:
                clusters_dict[key] = {
                    "id": f"cluster_{len(clusters_dict) + 1}",
                    "name": key,
                    "artist": artist or "Unknown Artist",
                    "album": album,
                    "track_ids": [],
                    "total_duration": 0.0,
                }
            clusters_dict[key]["track_ids"].append(track["id"])
            clusters_dict[key]["total_duration"] += float(metadata.get("duration", 0))
        else:
            unclustered_ids.append(track["id"])
            
    clusters = list(clusters_dict.values())
    for c in clusters:
        c["total_duration"] = round(c["total_duration"], 2)
        c["track_count"] = len(c["track_ids"])
        
    return {
        "clusters": clusters,
        "unclustered_track_ids": unclustered_ids,
    }


@app.post("/api/jobs/{job_id}/lookup")
def lookup_job(job_id: str, request: LookupRequest) -> dict[str, Any]:
    job = job_or_404(job_id)
    all_tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
    target_ids = set(request.track_ids or [t["id"] for t in all_tracks])
    tracks = [t for t in all_tracks if t["id"] in target_ids]
    if not tracks:
        raise HTTPException(400, "no tracks selected for lookup")
        
    staged_items = []
    staging_dir = Path(job["staging_dir"]) if job["staging_dir"] else None
    for t in tracks:
        m = json.loads(t["metadata_json"])
        p = Path(t["path"])
        album = str(m.get("album") or "").strip()
        artist = str(m.get("artist") or m.get("albumartist") or "").strip()
        # Fallback to parent directory names if missing
        if not album and staging_dir and p.parent != staging_dir and staging_dir in p.parents:
            album = clean_tag(p.parent.name)
            if not artist and p.parent.parent != staging_dir and staging_dir in p.parent.parents:
                artist = clean_tag(p.parent.parent.name)
        staged_items.append({
            "id": t["id"],
            "path": t["path"],
            "filename": p.name,
            "title": m.get("title") or p.stem,
            "artist": artist,
            "album": album,
            "tracknumber": m.get("tracknumber") or "",
            "duration": float(m.get("duration", 0)),
        })
        
    target_releases: list[tuple[str, dict[str, Any]]] = []
    seen_ids: set[str] = set()

    def add_target_release(rel_id: str) -> bool:
        if rel_id in seen_ids:
            return False
        try:
            concrete_id, rel = fetch_musicbrainz_release(rel_id)
            if concrete_id not in seen_ids:
                seen_ids.add(concrete_id)
                target_releases.append((concrete_id, rel))
                return True
        except Exception:
            pass
        return False

    if request.release_id:
        try:
            concrete_id, rel = fetch_musicbrainz_release(request.release_id)
            seen_ids.add(concrete_id)
            target_releases.append((concrete_id, rel))
        except Exception as exc:
            raise HTTPException(400, f"could not fetch release: {exc}") from exc
    elif request.query:
        mbid_m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", request.query, re.I)
        if mbid_m:
            add_target_release(mbid_m.group(1))
        if not target_releases:
            clean_q = clean_tag(request.query)
            q_attempts = [request.query.strip()]
            if clean_q and clean_q != request.query.strip():
                q_attempts.append(clean_q)
            for q_str in q_attempts:
                try:
                    res = musicbrainz_request(f"release/?query={urllib.parse.quote(q_str)}&fmt=json&limit=5")
                    for r in res.get("releases", [])[:3]:
                        add_target_release(r["id"])
                    if target_releases:
                        break
                except Exception:
                    continue
    else:
        albums: dict[tuple[str, str], list[dict[str, Any]]] = {}
        for s in staged_items:
            key = (s["artist"], s["album"])
            albums.setdefault(key, []).append(s)
            
        for (artist, album), group in albums.items():
            clean_alb = clean_tag(album)
            clean_art = clean_tag(artist)
            attempts = []
            if clean_alb and clean_art:
                attempts.append(f'release:"{clean_alb}" AND artist:"{clean_art}"')
                attempts.append(f"{clean_alb} {clean_art}")
            if album and artist and (album != clean_alb or artist != clean_art):
                attempts.append(f'release:"{album}" AND artist:"{artist}"')
                attempts.append(f"{album} {artist}")
            if clean_alb:
                attempts.append(f'release:"{clean_alb}"')
                attempts.append(clean_alb)
            if not attempts and group:
                sample_t = group[0]["title"]
                clean_sample = clean_tag(sample_t)
                if clean_art:
                    attempts.append(f"{clean_sample} {clean_art}")
                else:
                    attempts.append(clean_sample)

            for q_str in attempts:
                try:
                    res = musicbrainz_request(f"release/?query={urllib.parse.quote(q_str)}&fmt=json&limit=5")
                    found = False
                    for r in res.get("releases", [])[:3]:
                        if add_target_release(r["id"]):
                            found = True
                    if found:
                        break
                except Exception:
                    continue
                
    results = []
    seen_ids = set()
    for concrete_id, release in target_releases:
        if concrete_id in seen_ids:
            continue
        seen_ids.add(concrete_id)
        
        release_artist = ", ".join(a.get("name", "") for a in release.get("artist-credit", []))
        tracks_list = []
        total_len_ms = 0
        idx = 0
        for medium in release.get("media", []):
            disc = medium.get("position", 1)
            for track in medium.get("tracks", []):
                rec = track.get("recording", track)
                rec_artist = ", ".join(a.get("name", "") for a in rec.get("artist-credit", [])) or release_artist
                t_len = int(track.get("length") or rec.get("length") or 0)
                total_len_ms += t_len
                tracks_list.append({
                    "index": idx,
                    "position": int(track.get("position", idx + 1)),
                    "discnumber": int(disc),
                    "title": rec.get("title") or track.get("title", ""),
                    "length": t_len,
                    "artist": rec_artist,
                    "recording_id": rec.get("id", ""),
                    "track_id": track.get("id", ""),
                })
                idx += 1
                
        mapping, scores = match_tracks(tracks_list, staged_items)
        
        alternatives = []
        rg_id = release.get("release-group", {}).get("id")
        if rg_id:
            try:
                rg_data = musicbrainz_request(f"release-group/{rg_id}?inc=releases&fmt=json")
                for r in rg_data.get("releases", []):
                    alternatives.append({
                        "id": r.get("id"),
                        "title": r.get("title"),
                        "date": r.get("date", ""),
                        "country": r.get("country", ""),
                        "track_count": r.get("track-count", 0),
                        "status": r.get("status", ""),
                    })
            except Exception:
                pass
                
        matched_count = len(mapping)
        confidence = round(sum(scores.values()) / max(1, matched_count)) if matched_count else 0
        
        results.append({
            "release_id": concrete_id,
            "title": release.get("title", ""),
            "artist": release_artist,
            "date": release.get("date", ""),
            "country": release.get("country", ""),
            "total_length": total_len_ms,
            "matched_count": matched_count,
            "total_tracks": len(tracks_list),
            "confidence": confidence,
            "mapping": mapping,
            "scores": scores,
            "tracks": tracks_list,
            "alternatives": alternatives,
            "release": release,
            "source_track_ids": [s["id"] for s in staged_items],
            "cover_url": f"/api/musicbrainz/release/{concrete_id}/cover",
        })
        
    results.sort(key=lambda r: (-r["matched_count"], -r["confidence"]))
    return {"releases": results}


@app.get("/api/musicbrainz/release/{release_id}/cover")
def get_musicbrainz_release_cover(release_id: str) -> Response:
    if not re.fullmatch(r"[0-9a-f-]{20,}", release_id, re.IGNORECASE):
        raise HTTPException(400, "invalid MusicBrainz release id")
    req = urllib.request.Request(
        f"https://coverartarchive.org/release/{release_id}/front-250",
        headers={"User-Agent": "music-library-webui/0.1"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            data = res.read()
            mime = res.headers.get_content_type() or "image/jpeg"
            return Response(data, media_type=mime, headers={"Cache-Control": "public, max-age=86400"})
    except Exception:
        return Response(status_code=204)


@app.get("/api/jobs/{job_id}/musicbrainz-release/{release_id}")
def preview_musicbrainz_release(job_id: str, release_id: str) -> dict[str, Any]:
    job = job_or_404(job_id)
    if job["status"] not in {"review", "failed"}:
        raise HTTPException(409, "job is not awaiting metadata review")
    if not re.fullmatch(r"[0-9a-f-]{20,}", release_id, re.IGNORECASE):
        raise HTTPException(400, "invalid MusicBrainz release or release-group id")
    concrete_id, release = fetch_musicbrainz_release(release_id)
    release_artist = ", ".join(a.get("name", "") for a in release.get("artist-credit", []))
    tracks = []
    total_length_ms = 0
    index = 0
    for medium in release.get("media", []):
        disc = medium.get("position", 1)
        for track in medium.get("tracks", []):
            recording = track.get("recording", track)
            rec_artists = ", ".join(
                artist.get("name", "")
                for artist in recording.get("artist-credit", track.get("artist-credit", []))
            ) or release_artist
            t_len = int(track.get("length") or recording.get("length") or 0)
            total_length_ms += t_len
            tracks.append({
                "index": index,
                "position": int(track.get("position", index + 1)),
                "discnumber": int(disc),
                "title": recording.get("title") or track.get("title", ""),
                "length": t_len,
                "artist": rec_artists,
                "recording_id": recording.get("id", ""),
                "track_id": track.get("id", ""),
            })
            index += 1

    alternatives = []
    rg_id = release.get("release-group", {}).get("id")
    if rg_id:
        try:
            rg_data = musicbrainz_request(f"release-group/{rg_id}?inc=releases&fmt=json")
            for r in rg_data.get("releases", []):
                alternatives.append({
                    "id": r.get("id"),
                    "title": r.get("title"),
                    "date": r.get("date", ""),
                    "country": r.get("country", ""),
                    "track_count": r.get("track-count", 0),
                    "status": r.get("status", ""),
                })
        except Exception:
            pass

    return {
        "release_id": concrete_id,
        "title": release.get("title", ""),
        "artist": release_artist,
        "date": release.get("date", ""),
        "country": release.get("country", ""),
        "release": release,
        "tracks": tracks,
        "total_length": total_length_ms,
        "alternatives": alternatives,
        "cover_url": f"/api/musicbrainz/release/{concrete_id}/cover",
    }


@app.post("/api/jobs/{job_id}/musicbrainz-release")
def apply_musicbrainz_release(job_id: str, request: ReleaseRequest) -> dict[str, Any]:
    job = job_or_404(job_id)
    if job["status"] != "review":
        raise HTTPException(409, "job is not awaiting review")
    release_id = request.release_id
    if not re.fullmatch(r"[0-9a-f-]{20,}", release_id, re.IGNORECASE):
        raise HTTPException(400, "invalid MusicBrainz release or release-group id")
    release_id, release = fetch_musicbrainz_release(release_id)
    recordings = []
    for medium in release.get("media", []):
        disc_num = medium.get("position", 1)
        for track in medium.get("tracks", []):
            t_copy = dict(track)
            t_copy["_discnumber"] = disc_num
            recordings.append(t_copy)
    all_tracks = db_all("SELECT * FROM tracks WHERE job_id=? ORDER BY id", (job_id,))
    selected_ids = set(request.track_ids or [track["id"] for track in all_tracks])
    tracks = [track for track in all_tracks if track["id"] in selected_ids]
    album_artist = ", ".join(
        artist.get("name", "") for artist in release.get("artist-credit", [])
    ).strip(", ")
    album = release.get("title", "")
    updates: list[dict[str, Any]] = []
    track_by_id = {track["id"]: track for track in tracks}
    assignments: list[tuple[int, sqlite3.Row]] = []
    if request.track_map:
        for raw_index, raw_track_id in request.track_map.items():
            try:
                release_index = int(raw_index)
                track_id = int(raw_track_id)
            except (TypeError, ValueError) as exc:
                raise HTTPException(400, "invalid release track mapping") from exc
            if 0 <= release_index < len(recordings) and track_id in track_by_id:
                assignments.append((release_index, track_by_id[track_id]))
    else:
        assignments = list(enumerate(tracks[: len(recordings)]))
    for index, track in assignments:
        metadata = json.loads(track["metadata_json"])
        if index < len(recordings):
            release_track = recordings[index]
            recording = release_track.get("recording", release_track)
            recording_artists = recording.get("artist-credit", release_track.get("artist-credit", []))
            release_artists = release.get("artist-credit", [])
            release_group = release.get("release-group", {})
            metadata.update(
                {
                    "title": recording.get("title", metadata.get("title", "")),
                    "artist": ", ".join(
                        artist.get("name", "") for artist in recording_artists
                    ).strip(", ") or album_artist,
                    "albumartist": album_artist,
                    "album": album,
                    "date": release.get("date", metadata.get("date", "")),
                    "tracknumber": str(release_track.get("position", index + 1)),
                    "tracktotal": str(len(recordings)),
                    "discnumber": str(release_track.get("_discnumber", 1)),
                    "musicbrainz_albumid": release_id,
                    "musicbrainz_trackid": recording.get("id", ""),
                    "musicbrainz_releasetrackid": release_track.get("id", ""),
                    "musicbrainz_releasegroupid": release_group.get("id", ""),
                    "musicbrainz_artistid": next(
                        (
                            artist.get("artist", {}).get("id") or artist.get("id", "")
                            for artist in recording_artists
                        ),
                        "",
                    ),
                    "musicbrainz_albumartistid": next(
                        (
                            artist.get("artist", {}).get("id") or artist.get("id", "")
                            for artist in release_artists
                        ),
                        "",
                    ),
                }
            )
            if release.get("barcode"):
                metadata["barcode"] = release["barcode"]
            if release.get("country"):
                metadata["country"] = release["country"]
            if release.get("status"):
                metadata["musicbrainz_release_status"] = release["status"]
            if release.get("packaging"):
                metadata["packaging"] = release["packaging"]
            if recording.get("length"):
                metadata["length"] = str(recording["length"])
            if recording.get("isrcs"):
                metadata["isrc"] = ", ".join(recording["isrcs"])
        updates.append({"id": track["id"], "metadata": metadata})
    update_metadata(job_id, MetadataRequest(tracks=updates))
    artwork_path = fetch_release_artwork(
        release_id,
        DATA_DIR / "staging" / job_id / "artwork" / f"release_{release_id}",
    )
    if artwork_path:
        assigned_ids = [track["id"] for _, track in assignments]
        with db_lock, connect() as con:
            for t_id in assigned_ids:
                con.execute(
                    "UPDATE tracks SET artwork_json=? WHERE id=? AND job_id=?",
                    (json.dumps({"proposed": str(artwork_path), "release_id": release_id}), t_id, job_id),
                )
        event(job_id, "Downloaded proposed album artwork from Cover Art Archive")
    else:
        event(job_id, "No artwork was found for this MusicBrainz release", "warning")
    event(job_id, f"Applied MusicBrainz release {album}")
    return {"release": release, "tracks": updates}


@app.post("/api/jobs/{job_id}/approve", status_code=202)
def approve_job(job_id: str, request: ApproveRequest) -> dict[str, str]:
    job = job_or_404(job_id)
    if job["status"] != "review":
        raise HTTPException(409, "job is not awaiting review")
    if not claim_job(job_id, "review", "processing"):
        raise HTTPException(409, "job changed before processing could start")
    db_run(
        "UPDATE jobs SET options_json=?, updated_at=? WHERE id=?",
        (request.model_dump_json(), now(), job_id),
    )
    executor.submit(process_worker, job_id)
    return {"status": "processing"}


@app.get("/api/musicbrainz/search")
def search_musicbrainz(q: str, type: str = "release") -> dict[str, Any]:
    if not q.strip():
        raise HTTPException(400, "query is required")
    query_str = q.strip()
    mbid_m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", query_str, re.I)
    if mbid_m:
        try:
            cid, rel = fetch_musicbrainz_release(mbid_m.group(1))
            return {"releases": [rel]}
        except Exception:
            pass
    if type == "artist":
        clean_art = clean_tag(query_str)
        q_enc = urllib.parse.quote(f'artist:"{clean_art}"')
        try:
            res = musicbrainz_request(f"release/?query={q_enc}&fmt=json&limit=25")
            if res.get("releases"):
                return res
        except Exception:
            pass
        return musicbrainz_request(f"artist/?query={urllib.parse.quote(query_str)}&fmt=json&limit=20")
        
    clean_q = clean_tag(query_str)
    try:
        res = musicbrainz_request(f"release/?query={urllib.parse.quote(query_str)}&fmt=json&limit=20")
        if res.get("releases"):
            return res
    except Exception:
        pass
    if clean_q and clean_q != query_str:
        try:
            res = musicbrainz_request(f"release/?query={urllib.parse.quote(clean_q)}&fmt=json&limit=20")
            if res.get("releases"):
                return res
        except Exception:
            pass
    return {"releases": []}


@app.get("/api/musicbrainz/release/{release_id}")
def get_musicbrainz_release(release_id: str) -> dict[str, Any]:
    if not re.fullmatch(r"[0-9a-f-]{20,}", release_id, re.IGNORECASE):
        raise HTTPException(400, "invalid MusicBrainz release id")
    return musicbrainz_request(
        f"release/{release_id}?inc=artists+recordings+release-groups&fmt=json"
    )


@app.get("/api/import-files")
def list_import_files() -> list[str]:
    if not IMPORT_DIR.exists():
        return []
    return [str(path.relative_to(IMPORT_DIR)) for path in audio_files(IMPORT_DIR)]


def main() -> None:
    import uvicorn
    uvicorn.run("webui.app:app", host=WEBUI_HOST, port=WEBUI_PORT)
