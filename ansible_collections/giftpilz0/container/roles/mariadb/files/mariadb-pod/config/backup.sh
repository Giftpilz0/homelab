#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_COMPRESSION_LEVEL="${BACKUP_COMPRESSION_LEVEL:-6}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-mariadb}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"

mkdir -p "$BACKUP_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="${DB_NAME}_backup_${timestamp}.sql.gz"

export MYSQL_PWD="$DB_PASSWORD"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup: $backup_file"

if ! mariadb-admin --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" ping --silent >/dev/null 2>&1; then
    echo "[ERROR] MariaDB is not reachable at $DB_HOST:$DB_PORT"
    exit 1
fi

mariadb-dump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
    --single-transaction --routines --triggers --events --databases "$DB_NAME" | \
    gzip -c -"$BACKUP_COMPRESSION_LEVEL" > "${BACKUP_DIR}/${backup_file}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup complete: $(du -h "${BACKUP_DIR}/${backup_file}" | cut -f1)"

find "$BACKUP_DIR" -name "${DB_NAME}_backup_*.sql.gz" -type f -mtime "+${BACKUP_RETENTION_DAYS}" \
    -print -delete

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup finished"
