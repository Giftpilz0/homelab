from __future__ import annotations

import os
import shutil
import sqlite3
import subprocess
from pathlib import Path
from typing import Any

from mutagen import File as MutagenFile

from webui.artwork import read_embedded_cover


PATH_COLUMNS = (("items", "path"), ("items", "destination"), ("albums", "artpath"))
CHECKED_TAGS = ("title", "artist", "albumartist", "album", "date", "tracknumber", "discnumber", "genre")


def repair_beets_paths(root: Path) -> dict[str, Any]:
    database = root / "beets_library.db"
    if not database.exists():
        return {"status": "missing", "message": "beets_library.db does not exist", "updated": 0}
    with sqlite3.connect(database) as con:
        row = con.execute("SELECT path FROM items LIMIT 1").fetchone()
        if not row:
            return {"status": "ok", "message": "beets database is empty", "updated": 0}
        stored = row[0].decode("utf-8", "replace") if isinstance(row[0], bytes) else str(row[0])
        marker = "/original/"
        index = stored.find(marker)
        if index < 0:
            return {"status": "warning", "message": "could not locate /original/ in stored paths", "updated": 0}
        old_prefix = stored[:index]
        new_prefix = str(root)
        if old_prefix == new_prefix:
            return {"status": "ok", "message": "beets paths already point to this library root", "updated": 0}
        updated = 0
        for table, column in PATH_COLUMNS:
            try:
                con.execute(
                    f"UPDATE {table} SET {column}=CAST(replace(CAST({column} AS TEXT), ?, ?) AS BLOB) WHERE {column} IS NOT NULL",
                    (old_prefix, new_prefix),
                )
                updated += con.execute("SELECT changes()").fetchone()[0]
            except sqlite3.OperationalError:
                continue
        con.commit()
    return {"status": "fixed", "message": f"updated beets paths from {old_prefix} to {new_prefix}", "updated": updated}


def _beets_paths(root: Path) -> tuple[set[Path], str | None]:
    venv_bin = str(root / ".venv" / "bin")
    search_path = os.environ.get("PATH", "") + os.pathsep + venv_bin
    beet = shutil.which("beet") or shutil.which("beet", path=search_path)
    if beet is None:
        return set(), "beet executable was not found in PATH"
    env = os.environ.copy()
    env["BEETSDIR"] = str(root)
    if venv_bin not in env.get("PATH", ""):
        env["PATH"] = venv_bin + os.pathsep + env.get("PATH", "")
    result = subprocess.run(
        [beet, "ls", "-f", "$path"],
        cwd=str(root),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        return set(), result.stderr.strip() or "beet ls failed"
    paths = set()
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        path = Path(line.strip()).expanduser()
        paths.add((path if path.is_absolute() else root / path).resolve())
    return paths, None


def database_consistency(root: Path, audio_extensions: set[str]) -> dict[str, Any]:
    tracked, error = _beets_paths(root)
    if error:
        return {"status": "error", "error": error, "missing": [], "untracked": []}
    managed = [
        path
        for directory in (root / "original" / "lossless_compression", root / "original" / "lossy_compression")
        if directory.exists()
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in audio_extensions
    ]
    managed_paths = {path.resolve() for path in managed}
    missing = sorted(str(path) for path in tracked if not path.exists())
    untracked = sorted(str(path.relative_to(root / "original")) for path in managed_paths if path not in tracked)
    return {
        "status": "ok" if not missing and not untracked else "warning",
        "tracked": len(tracked),
        "managed_files": len(managed),
        "missing": missing,
        "untracked": untracked,
    }


def _tags(path: Path) -> dict[str, str]:
    try:
        media = MutagenFile(str(path), easy=True)
    except Exception:
        return {}
    if media is None:
        return {}
    result = {}
    for key in CHECKED_TAGS:
        value = media.get(key)
        if value:
            result[key] = str(value[0] if isinstance(value, list) else value).split("/", 1)[0]
    return result


def transcoding_diff(root: Path, audio_extensions: set[str]) -> dict[str, Any]:
    original = root / "original"
    transcoded = root / "transcoded"
    differences = []
    missing = []
    checked = 0
    for source in (
        path for directory in (original / "lossless_compression", original / "lossy_compression")
        if directory.exists() for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in audio_extensions
    ):
        relative = source.relative_to(original)
        destination = (transcoded / relative).with_suffix(".opus")
        if not destination.exists():
            missing.append(str(relative))
            continue
        checked += 1
        issues = []
        source_tags = _tags(source)
        destination_tags = _tags(destination)
        for key in CHECKED_TAGS:
            if source_tags.get(key, "") != destination_tags.get(key, ""):
                issues.append({"field": key, "source": source_tags.get(key, ""), "transcoded": destination_tags.get(key, "")})
        try:
            source_cover = read_embedded_cover(source)
            destination_cover = read_embedded_cover(destination)
        except Exception:
            source_cover = destination_cover = None
        if source_cover and not destination_cover:
            issues.append({"field": "artwork", "source": "present", "transcoded": "missing"})
        if issues:
            differences.append({"path": str(relative), "issues": issues})
    return {
        "status": "ok" if not missing and not differences else "warning",
        "checked": checked,
        "missing": missing,
        "differences": differences,
    }
