#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_COMPRESSION_LEVEL="${BACKUP_COMPRESSION_LEVEL:-6}"

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-postgres}"
PGDATABASES="${PGDATABASES:-$PGDATABASE}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-}"

mkdir -p "$BACKUP_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)

export PGPASSWORD

if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -q 2>/dev/null; then
    echo "[ERROR] PostgreSQL is not reachable at $PGHOST:$PGPORT"
    exit 1
fi

for database in $PGDATABASES; do
    backup_file="${database}_backup_${timestamp}.dump"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup: $backup_file"
    pg_dump --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$database" \
        --format=custom --compress="$BACKUP_COMPRESSION_LEVEL" \
        --file="${BACKUP_DIR}/${backup_file}" --no-password

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup complete: $(du -h "${BACKUP_DIR}/${backup_file}" | cut -f1)"
done

for database in $PGDATABASES; do
    find "$BACKUP_DIR" -name "${database}_backup_*.dump" -type f -mtime "+${BACKUP_RETENTION_DAYS}" \
        -print -delete
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup finished"
