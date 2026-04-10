#!/bin/bash
# Auto Backup Monitoring System (Tracks file create/delete and organizes backups)
# need sudo apt install inotify-tools

set -e

# BASE SETUP 
BASE_DIR="$HOME/SYSAD_PROJ"
SOURCE_DIR="$BASE_DIR/source_data"
BACKUP_DIR="$BASE_DIR/MainBackupFolder"

# DATE ORGANIZATION 
TODAY=$(date +%Y-%m-%d)
TARGET="$BACKUP_DIR/$TODAY"

# LOG SYSTEM 
LOG_FILE="$BACKUP_DIR/backup.log"

# CREATE REQUIRED DIRECTORIES 
mkdir -p "$SOURCE_DIR"
mkdir -p "$TARGET"
mkdir -p "$BACKUP_DIR"

# PREPARE LOG FILE 
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

echo "Monitoring started on $SOURCE_DIR..."

# FILE MONITORING 
inotifywait -m -e create -e delete "$SOURCE_DIR" --format '%e %f' |

while read event file; do

    # TIMESTAMP 
    TIMESTAMP=$(date '+%H-%M-%S')

    # EVENT HANDLING 
    if [[ "$event" == "CREATE" ]]; then

        # BACKUP CREATED FILE
        if [ -f "$SOURCE_DIR/$file" ]; then
            cp "$SOURCE_DIR/$file" "$TARGET/(CREATED)_${TIMESTAMP}_$file"
            echo "$(date) CREATED: $file" >> "$LOG_FILE"
            echo "Created backup: $file"
        fi

    elif [[ "$event" == "DELETE" ]]; then

        # LOG DELETED FILE 
        echo "$file" > "$TARGET/(DELETED)_${TIMESTAMP}_$file"
        echo "$(date) DELETED: $file" >> "$LOG_FILE"
        echo "Deleted logged: $file"

    fi

done