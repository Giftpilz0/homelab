#!/bin/sh
set -eu

BACKUP_SCHEDULE_TIMES="${BACKUP_SCHEDULE_TIMES:-03:00}"
export MYSQL_PWD="${DB_PASSWORD:-}"

if ! printf '%s\n' "$BACKUP_SCHEDULE_TIMES" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]( ([01][0-9]|2[0-3]):[0-5][0-9])*$'; then
    echo "[ERROR] BACKUP_SCHEDULE_TIMES must contain one or more HH:MM times"
    exit 1
fi

until mariadb-admin --host="${DB_HOST:-127.0.0.1}" --port="${DB_PORT:-3306}" \
    --user="${DB_USER:-root}" ping --silent >/dev/null 2>&1; do
    sleep 2
done
mariadb --host="${DB_HOST:-127.0.0.1}" --port="${DB_PORT:-3306}" \
    --user="${DB_USER:-root}" < /usr/local/bin/init-databases.sql

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
