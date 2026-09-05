#!/bin/sh
set -eu

BACKUP_SCHEDULE_TIMES="${BACKUP_SCHEDULE_TIMES:-03:00}"

if ! printf '%s\n' "$BACKUP_SCHEDULE_TIMES" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]( ([01][0-9]|2[0-3]):[0-5][0-9])*$'; then
    echo "[ERROR] BACKUP_SCHEDULE_TIMES must contain one or more HH:MM times"
    exit 1
fi

until pg_isready -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" -q 2>/dev/null; do
    sleep 2
done
psql --host="${PGHOST:-127.0.0.1}" --port="${PGPORT:-5432}" \
    --username="${PGUSER:-postgres}" --dbname="${PGDATABASE:-postgres}" \
    --file=/usr/local/bin/init-databases.sql --no-password

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup daemon started (at ${BACKUP_SCHEDULE_TIMES})"

last_run=""
while true; do
    now=$(date '+%Y-%m-%d %H:%M')
    time=${now#* }

    case " $BACKUP_SCHEDULE_TIMES " in
        *" $time "*)
            if [ "$now" != "$last_run" ]; then
                backup.sh
                last_run="$now"
            fi
            ;;
    esac

    sleep 30
done
