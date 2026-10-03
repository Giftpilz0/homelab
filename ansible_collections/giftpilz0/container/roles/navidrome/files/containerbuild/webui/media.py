from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from webui.config import ORIGINAL, SUPPORTED_EXTENSIONS, TRANSCODED

try:
    from mutagen import File as MutagenFile
except ImportError:  # pragma: no cover - dependency is declared in pyproject.toml
    MutagenFile = None


def safe_child(parent: Path, candidate: str) -> Path:
    path = (parent / candidate).resolve()
    if path != parent and parent not in path.parents:
        raise ValueError("path escapes configured directory")
    return path


def audio_files(root: Path) -> list[Path]:
    return sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def managed_audio_files() -> list[Path]:
    return audio_files(ORIGINAL / "lossless_compression") + audio_files(ORIGINAL / "lossy_compression")


def read_metadata(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": str(path),
        "filename": path.name,
        "title": path.stem,
        "artist": "",
        "albumartist": "",
        "album": "",
        "date": "",
        "genre": "",
        "tracknumber": "",
        "tracktotal": "",
        "discnumber": "",
        "disctotal": "",
        "duration": 0.0,
    }
    if MutagenFile is None:
        return result
    try:
        media = MutagenFile(str(path), easy=True)
        if media is None:
            return result
        if media.info and hasattr(media.info, "length"):
            result["duration"] = round(float(media.info.length), 2)
        for key in result:
            if key in {"path", "filename", "duration"}:
                continue
            value = media.get(key)
            if value:
                result[key] = value[0] if isinstance(value, list) else str(value)
        for key, value in media.items():
            if key.startswith("musicbrainz_") and key not in result:
                result[key] = value[0] if isinstance(value, list) else str(value)
        if not result.get("tracknumber"):
            match = re.match(r"^(\d{1,3})[\s\.\-_]+(.+)$", result["title"])
            if match:
                result["tracknumber"] = str(int(match.group(1)))
                result["title"] = match.group(2).strip()
    except Exception as exc:  # malformed downloads should remain reviewable
        result["read_error"] = str(exc)
    return result


def album_files(source: Path) -> list[Path]:
    metadata = read_metadata(source)
    wanted_artist = str(metadata.get("albumartist") or metadata.get("artist") or "").casefold()
    wanted_album = str(metadata.get("album") or "").casefold()
    if not wanted_album:
        return [source]
    result = []
    for candidate in managed_audio_files():
        candidate_metadata = read_metadata(candidate)
        artist = str(candidate_metadata.get("albumartist") or candidate_metadata.get("artist") or "").casefold()
        album = str(candidate_metadata.get("album") or "").casefold()
        if artist == wanted_artist and album == wanted_album:
            result.append(candidate)
    return result or [source]


def library_payload(query: str = "") -> list[dict[str, Any]]:
    albums: dict[tuple[str, str, str], dict[str, Any]] = {}
    needle = query.casefold().strip()
    for path in managed_audio_files():
        metadata = read_metadata(path)
        albumartist = metadata.get("albumartist") or metadata.get("artist") or "Unknown artist"
        album = metadata.get("album") or "Unknown album"
        year = metadata.get("date") or ""
        key = (str(albumartist), str(album), str(year))
        searchable = f"{albumartist} {album} {year} {metadata.get('artist', '')} {metadata.get('title', '')}".casefold()
        if needle and needle not in searchable:
            continue
        relative = path.relative_to(ORIGINAL)
        entry = albums.setdefault(
            key,
            {
                "key": "|".join(key),
                "albumartist": albumartist,
                "album": album,
                "year": year,
                "cover_path": str(relative),
                "representative_path": str(relative),
                "tracks": [],
            },
        )
        transcoded = (TRANSCODED / relative).with_suffix(".opus")
        entry["tracks"].append(
            {
                "path": str(relative),
                "title": metadata.get("title") or path.stem,
                "artist": metadata.get("artist", ""),
                "tracknumber": metadata.get("tracknumber", ""),
                "discnumber": metadata.get("discnumber", ""),
                "format": path.suffix.lower().lstrip("."),
                "has_transcode": transcoded.exists(),
            }
        )

    def position(value: Any) -> tuple[int, int, str]:
        text = str(value or "").strip()
        match = re.match(r"(\d+)(?:/(\d+))?", text)
        if not match:
            return (10**9, 10**9, text.casefold())
        return (int(match.group(1)), int(match.group(2) or 0), text.casefold())

    for album in albums.values():
        album["tracks"].sort(
            key=lambda track: (
                position(track["discnumber"]),
                position(track["tracknumber"]),
                track["title"].casefold(),
            )
        )
    result = list(albums.values())
    result.sort(key=lambda album: (
        str(album["albumartist"]).casefold(),
        str(album["year"]),
        str(album["album"]).casefold(),
    ))
    return result
