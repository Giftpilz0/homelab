#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-postgres}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-}"

export PGPASSWORD

list_backups() {
    echo "Available backups in $BACKUP_DIR:"
    echo ""
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "[ERROR] Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    find "$BACKUP_DIR" -name "${PGDATABASE}_backup_*.dump" -type f | sort -r | while IFS= read -r f; do
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

    if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -q 2>/dev/null; then
        echo "[ERROR] PostgreSQL is not reachable at $PGHOST:$PGPORT"
        exit 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating pre-restore backup..."
    backup.sh

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restoring data..."
    pg_restore --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" \
        --clean --if-exists --no-owner --exit-on-error --no-password "$backup_file"

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
