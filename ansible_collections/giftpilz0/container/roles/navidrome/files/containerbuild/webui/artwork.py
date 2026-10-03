from __future__ import annotations

import base64
import mimetypes
import urllib.request
from pathlib import Path

from mutagen import File as MutagenFile
from mutagen.flac import Picture
from mutagen.id3 import APIC, ID3
from mutagen.mp4 import MP4, MP4Cover
from mutagen.oggopus import OggOpus


def read_embedded_cover(path: Path) -> tuple[bytes, str] | None:
    media = MutagenFile(str(path), easy=False)
    if media is None:
        return None
    pictures = getattr(media, "pictures", None) or []
    if pictures:
        picture = next((item for item in pictures if getattr(item, "type", 0) == 3), pictures[0])
        return picture.data, picture.mime or "image/jpeg"
    tags = getattr(media, "tags", None) or {}
    for key in tags:
        if str(key).startswith("APIC"):
            picture = tags[key]
            return picture.data, picture.mime or "image/jpeg"
    encoded = tags.get("metadata_block_picture") if hasattr(tags, "get") else None
    if encoded:
        picture = Picture(base64.b64decode(encoded[0]))
        return picture.data, picture.mime or "image/jpeg"
    covr = tags.get("covr") if hasattr(tags, "get") else None
    if covr:
        picture = covr[0]
        mime = "image/png" if getattr(picture, "imageformat", None) == MP4Cover.FORMAT_PNG else "image/jpeg"
        return bytes(picture), mime
    return None


def fetch_release_artwork(release_id: str, destination: Path) -> Path | None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        f"https://coverartarchive.org/release/{release_id}/front-500",
        headers={"User-Agent": "music-library-webui/0.1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = response.read()
            mime = response.headers.get_content_type()
    except Exception:
        return None
    extension = mimetypes.guess_extension(mime) or ".jpg"
    target = destination.with_suffix(extension)
    target.write_bytes(data)
    return target


def embed_cover(path: Path, cover: tuple[bytes, str]) -> None:
    data, mime = cover
    media = MutagenFile(str(path), easy=False)
    if media is None:
        return
    if isinstance(media, OggOpus):
        picture = Picture()
        picture.type = 3
        picture.mime = mime
        picture.data = data
        media["metadata_block_picture"] = [base64.b64encode(picture.write()).decode("ascii")]
        media.save()
    elif isinstance(media, MP4):
        media["covr"] = [MP4Cover(data, imageformat=MP4Cover.FORMAT_PNG if mime == "image/png" else MP4Cover.FORMAT_JPEG)]
        media.save()
    elif path.suffix.lower() == ".mp3":
        tags = ID3(str(path))
        tags.delall("APIC")
        tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=data))
        tags.save(str(path))
    elif hasattr(media, "clear_pictures") and hasattr(media, "add_picture"):
        picture = Picture()
        picture.type = 3
        picture.mime = mime
        picture.data = data
        media.clear_pictures()
        media.add_picture(picture)
        media.save()


def apply_artwork(path: Path, artwork_path: Path) -> bool:
    if not artwork_path.is_file():
        return False
    mime = mimetypes.guess_type(artwork_path.name)[0] or "image/jpeg"
    embed_cover(path, (artwork_path.read_bytes(), mime))
    return True
