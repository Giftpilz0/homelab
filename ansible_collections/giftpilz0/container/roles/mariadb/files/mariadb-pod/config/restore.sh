#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-mariadb}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"

export MYSQL_PWD="$DB_PASSWORD"

list_backups() {
    echo "Available backups in $BACKUP_DIR:"
    echo ""
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "[ERROR] Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    find "$BACKUP_DIR" -name "${DB_NAME}_backup_*.sql.gz" -type f | sort -r | while IFS= read -r f; do
        size=$(du -h "$f" 2>/dev/null | cut -f1)
        date=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
        printf "  %-50s %10s  %s\n" "$(basename "$f")" "$size" "$date"
    done
}

restore_backup() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        echo "[ERROR] Backup file not found: $backup_file"
        exit 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting restore from: $(basename "$backup_file")"

    if ! mariadb-admin --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" ping --silent >/dev/null 2>&1; then
        echo "[ERROR] MariaDB is not reachable at $DB_HOST:$DB_PORT"
        exit 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating pre-restore backup..."
    backup.sh

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Recreating database..."
    mariadb --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restoring data..."
    gzip -cd "$backup_file" | mariadb --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore complete"
}

if [ "${1:-}" = "--list" ]; then
    list_backups
    exit 0
fi

backup_file="${1:-}"
if [ -z "$backup_file" ]; then
    echo "Usage: $0 [--list | <backup-file>]"
    echo ""
    list_backups
    exit 1
fi

if [ "${backup_file##*/}" = "$backup_file" ]; then
    backup_file="${BACKUP_DIR}/${backup_file}"
fi

restore_backup "$backup_file"
