#!/bin/bash
set -eu

CONTAINER_NAME="${CONTAINER_NAME:-postgresql-backup}"
DB_TYPE="PostgreSQL"
BACKUP_PATTERN="*_backup_*.dump"

if ! command -v gum >/dev/null 2>&1; then
    echo "[ERROR] gum is required. Install with your package manager."
    exit 1
fi

if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    echo "[ERROR] Container '$CONTAINER_NAME' not found. Is $DB_TYPE running?"
    exit 1
fi

while true; do
    choice=$(gum choose --header "${DB_TYPE} Backup Manager" \
        "Create Backup" \
        "Restore Backup" \
        "List Backups" \
        "Exit")

    case "$choice" in
        "Create Backup")
            if gum confirm "Create a new backup?"; then
                gum spin --title "Creating backup..." -- podman exec "$CONTAINER_NAME" backup.sh
                echo ""
                gum style --foreground 2 "Backup created!"
            fi
            ;;
        "Restore Backup")
            backups=()
            while IFS= read -r file; do
                backups+=("$(basename "$file")")
            done < <(podman exec "$CONTAINER_NAME" sh -c "find /backups -maxdepth 1 -name '$BACKUP_PATTERN' -type f | sort -r")

            if [ ${#backups[@]} -eq 0 ]; then
                gum style --foreground 1 "No backups found."
            else
                choice=$(gum choose --header "Select backup to restore:" "${backups[@]}")
                if [ -n "$choice" ]; then
                    gum style --foreground 3 "WARNING: This will overwrite the current database!"
                    if gum confirm "Restore '$choice'?"; then
                        gum spin --title "Restoring..." -- podman exec "$CONTAINER_NAME" restore.sh "$choice"
                        echo ""
                        gum style --foreground 2 "Restore complete!"
                    fi
                fi
            fi
            ;;
        "List Backups")
            echo ""
            podman exec "$CONTAINER_NAME" restore.sh --list | gum pager
            ;;
        *)
            exit 0
            ;;
    esac

    echo ""
    gum confirm "Return to menu?" || exit 0
    echo ""
done
