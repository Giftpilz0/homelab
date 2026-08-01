#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_COMPRESSION_LEVEL="${BACKUP_COMPRESSION_LEVEL:-6}"

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-postgres}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-}"

mkdir -p "$BACKUP_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="${PGDATABASE}_backup_${timestamp}.dump"

export PGPASSWORD

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup: $backup_file"

if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -q 2>/dev/null; then
    echo "[ERROR] PostgreSQL is not reachable at $PGHOST:$PGPORT"
    exit 1
fi

pg_dump --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" \
    --format=custom --compress="$BACKUP_COMPRESSION_LEVEL" \
    --file="${BACKUP_DIR}/${backup_file}" --no-password

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup complete: $(du -h "${BACKUP_DIR}/${backup_file}" | cut -f1)"

find "$BACKUP_DIR" -name "${PGDATABASE}_backup_*.dump" -type f -mtime "+${BACKUP_RETENTION_DAYS}" \
    -print -delete

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup finished"
