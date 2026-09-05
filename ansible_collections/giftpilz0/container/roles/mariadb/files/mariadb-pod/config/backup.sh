#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_COMPRESSION_LEVEL="${BACKUP_COMPRESSION_LEVEL:-6}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-mariadb}"
DB_NAMES="${DB_NAMES:-$DB_NAME}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"

mkdir -p "$BACKUP_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)

export MYSQL_PWD="$DB_PASSWORD"

if ! mariadb-admin --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" ping --silent >/dev/null 2>&1; then
    echo "[ERROR] MariaDB is not reachable at $DB_HOST:$DB_PORT"
    exit 1
fi

for database in $DB_NAMES; do
    backup_file="${database}_backup_${timestamp}.sql.gz"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup: $backup_file"

    mariadb-dump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --single-transaction --routines --triggers --events --databases "$database" | \
        gzip -c -"$BACKUP_COMPRESSION_LEVEL" > "${BACKUP_DIR}/${backup_file}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup complete: $(du -h "${BACKUP_DIR}/${backup_file}" | cut -f1)"
done

for database in $DB_NAMES; do
    find "$BACKUP_DIR" -name "${database}_backup_*.sql.gz" -type f -mtime "+${BACKUP_RETENTION_DAYS}" \
        -print -delete
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup finished"
