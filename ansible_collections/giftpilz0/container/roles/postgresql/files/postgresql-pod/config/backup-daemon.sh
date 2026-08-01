#!/bin/sh
set -eu

BACKUP_SCHEDULE_TIMES="${BACKUP_SCHEDULE_TIMES:-03:00}"

if ! printf '%s\n' "$BACKUP_SCHEDULE_TIMES" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]( ([01][0-9]|2[0-3]):[0-5][0-9])*$'; then
    echo "[ERROR] BACKUP_SCHEDULE_TIMES must contain one or more HH:MM times"
    exit 1
fi

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
