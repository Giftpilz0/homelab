from __future__ import annotations

import os
from pathlib import Path


ROOT = Path(os.getenv("MUSIC_LIBRARY_ROOT", Path(__file__).resolve().parents[1])).resolve()
ORIGINAL = ROOT / "original"
UNTAGGED = ORIGINAL / "untagged"
TRANSCODED = ROOT / "transcoded"
IMPORT_DIR = Path(os.getenv("WEBUI_IMPORT_DIR", UNTAGGED)).resolve()
DATA_DIR = Path(os.getenv("WEBUI_DATA_DIR", ROOT / "webui-data")).resolve()
DB_PATH = Path(os.getenv("WEBUI_DB", DATA_DIR / "webui.sqlite3")).resolve()
WEBUI_TOKEN = os.getenv("WEBUI_TOKEN", "").strip()
WEBUI_HOST = os.getenv("WEBUI_HOST", "0.0.0.0")
WEBUI_PORT = int(os.getenv("WEBUI_PORT", "8080"))
WEBUI_WORKERS = max(1, int(os.getenv("WEBUI_WORKERS", "1")))
MAX_ARTWORK_BYTES = 20 * 1024 * 1024
SUPPORTED_EXTENSIONS = {
    ".flac",
    ".wav",
    ".aiff",
    ".aif",
    ".alac",
    ".mp3",
    ".m4a",
    ".aac",
    ".ogg",
    ".opus",
    ".wma",
    ".mka",
}
PIPELINE_STAGES = (
    ("acquire", "Acquire"),
    ("fingerprint", "Fingerprint"),
    ("review", "Metadata review"),
    ("tag", "Write tags"),
    ("import", "Library import"),
    ("replaygain", "ReplayGain"),
    ("transcode", "Opus transcode"),
    ("playlists", "Playlists"),
)
