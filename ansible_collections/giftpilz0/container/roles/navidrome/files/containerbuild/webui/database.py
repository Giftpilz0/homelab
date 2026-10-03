from __future__ import annotations

import sqlite3
import threading
from datetime import UTC, datetime
from typing import Any

from webui.config import DATA_DIR, DB_PATH, PIPELINE_STAGES


db_lock = threading.RLock()


def now() -> str:
    return datetime.now(UTC).isoformat()


def connect() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA foreign_keys=ON")
    return con


def init_db() -> None:
    with db_lock, connect() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                source TEXT NOT NULL,
                staging_dir TEXT NOT NULL,
                options_json TEXT NOT NULL DEFAULT '{}',
                error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS tracks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                path TEXT NOT NULL,
                original_metadata_json TEXT NOT NULL DEFAULT '{}',
                metadata_json TEXT NOT NULL DEFAULT '{}',
                artwork_json TEXT NOT NULL DEFAULT '{}',
                group_key TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS stages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                label TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                detail TEXT,
                position INTEGER NOT NULL,
                started_at TEXT,
                finished_at TEXT,
                UNIQUE(job_id, name)
            );
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS tracks_job_idx ON tracks(job_id);
            CREATE INDEX IF NOT EXISTS events_job_idx ON events(job_id, id);
            CREATE INDEX IF NOT EXISTS stages_job_idx ON stages(job_id, position);
            """
        )
        columns = {row["name"] for row in con.execute("PRAGMA table_info(tracks)")}
        if "original_metadata_json" not in columns:
            con.execute("ALTER TABLE tracks ADD COLUMN original_metadata_json TEXT NOT NULL DEFAULT '{}'")
        if "artwork_json" not in columns:
            con.execute("ALTER TABLE tracks ADD COLUMN artwork_json TEXT NOT NULL DEFAULT '{}'")
        if "group_key" not in columns:
            con.execute("ALTER TABLE tracks ADD COLUMN group_key TEXT")
        job_columns = {row["name"] for row in con.execute("PRAGMA table_info(jobs)")}
        if "options_json" not in job_columns:
            con.execute("ALTER TABLE jobs ADD COLUMN options_json TEXT NOT NULL DEFAULT '{}'")
        jobs_without_stages = con.execute(
            "SELECT id,status FROM jobs WHERE id NOT IN (SELECT DISTINCT job_id FROM stages)"
        ).fetchall()
        for job in jobs_without_stages:
            for position, (name, label) in enumerate(PIPELINE_STAGES):
                stage_status = "completed" if job["status"] == "completed" else "pending"
                detail = None
                if job["status"] in {"review", "fingerprinting"} and name == "acquire":
                    stage_status, detail = "completed", "Existing staged job"
                if job["status"] in {"review", "fingerprinting"} and name == "review":
                    stage_status, detail = "running", "Waiting for metadata approval"
                con.execute(
                    "INSERT OR IGNORE INTO stages(job_id,name,label,status,detail,position) VALUES(?,?,?,?,?,?)",
                    (job["id"], name, label, stage_status, detail, position),
                )


def db_one(query: str, params: tuple[Any, ...] = ()) -> sqlite3.Row | None:
    with db_lock, connect() as con:
        return con.execute(query, params).fetchone()


def db_all(query: str, params: tuple[Any, ...] = ()) -> list[sqlite3.Row]:
    with db_lock, connect() as con:
        return con.execute(query, params).fetchall()


def db_run(query: str, params: tuple[Any, ...] = ()) -> None:
    with db_lock, connect() as con:
        con.execute(query, params)


def claim_job(job_id: str, expected_status: str, new_status: str) -> bool:
    with db_lock, connect() as con:
        result = con.execute(
            "UPDATE jobs SET status=?, error=NULL, updated_at=? WHERE id=? AND status=?",
            (new_status, now(), job_id, expected_status),
        )
        return result.rowcount == 1
