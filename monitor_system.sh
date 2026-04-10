#!/bin/bash
# Monitor System: Real-time Tracking & Zip Compression

set -uo pipefail

SOURCE_DIR="/home/leroy/Downloads/sysad1p2/source_data"
BACKUP_ROOT="/home/leroy/Downloads/sysad1p2/backups"
ADMIN_EMAIL="admin@example.com" 

mkdir -p "$SOURCE_DIR" "$BACKUP_ROOT"

echo "WATCHMAN ACTIVE: Monitoring $SOURCE_DIR"

inotifywait -m -r -e create,delete,modify "$SOURCE_DIR" --format '%e %f' | while read EVENT FILENAME; do
    [[ "$FILENAME" == .* ]] && continue 

    TODAY=$(date +%Y-%m-%d)
    TARGET_DIR="$BACKUP_ROOT/BackupFolder($TODAY)"
    mkdir -p "$TARGET_DIR"

    case "$EVENT" in
        "CREATE"|"MODIFY")
            sleep 0.5
            cp -p "$SOURCE_DIR/$FILENAME" "$TARGET_DIR/(CREATED)_$FILENAME"
            ;;
        "DELETE")
            # Wait for file system to stabilize
            sleep 1
            if [ -f "$TARGET_DIR/(CREATED)_$FILENAME" ]; then
                zip -jq "$TARGET_DIR/(DELETED)_$FILENAME.zip" "$TARGET_DIR/(CREATED)_$FILENAME"
                rm "$TARGET_DIR/(CREATED)_$FILENAME"
                wall "File $FILENAME deleted and zipped in backups."
            elif [ -f "$TARGET_DIR/(RECOVERED)_$FILENAME" ]; then
                zip -jq "$TARGET_DIR/(DELETED)_$FILENAME.zip" "$TARGET_DIR/(RECOVERED)_$FILENAME"
                rm "$TARGET_DIR/(RECOVERED)_$FILENAME"
                wall "File $FILENAME deleted and zipped in backups."
            fi
            ;;
    esac

    # 30-Day Policy
    find "$BACKUP_ROOT" -name "(DELETED)_*.zip" -mtime +30 -delete 2>/dev/null || true
done
