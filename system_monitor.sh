#!/bin/bash
# Monitoring and Notification System

set -euo pipefail

# Variables
SOURCE_DIR="/home/leroy/Downloads/sysad1/source_data"
BACKUP_SCRIPT="/home/leroy/Downloads/sysad1/backup_system.sh"
LOG_FILE="/home/leroy/Downloads/sysad1/backups/backup.log"
AUTH_META="/etc/project_auth_meta"
MAX_DAYS=7

# Ensure we are root
if [ "$EUID" -ne 0 ]; then
    echo "Monitor must run as root."
    exit 1
fi

# Function to send alerts
send_alert() {
    local subject="$1"
    local body="$2"
    
    # wall sends the message to ALL open terminals (VS Code split terminals)
    echo -e "\n!!! $subject !!!\n$body" | wall
    logger -t SYSAD_ALERT "$subject: $body"
}

# Check Password Expiration
check_security_status() {
    if [ -f "$AUTH_META" ]; then
        last_change=$(cat "$AUTH_META")
        since=$(( ( $(date +%s) - last_change ) / 86400 ))
        
        if [ $since -ge $MAX_DAYS ]; then
            send_alert "SECURITY WARNING" "The System is Insecure, Files and Data may be Compromised. Renew password!"
        fi
    fi
}

# Real-time Monitoring Logic
monitor_changes() {
    echo "----------------------------------------------------------"
    echo "WATCHMAN ACTIVE: Monitoring $SOURCE_DIR"
    echo "Press Ctrl+C to stop monitoring."
    echo "----------------------------------------------------------"

    # inotifywait listens for new files (CREATE) or modifications (MODIFY)
    inotifywait -m -r -e create,modify "$SOURCE_DIR" --format '%w%f %e' | while read FILE_INFO EVENT; do
        
        FILENAME=$(basename "$FILE_INFO")
        DATE_STR=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo "Event Detected: $FILENAME was $EVENT"
        
        # Trigger Backup
        if bash "$BACKUP_SCRIPT"; then
            STATUS="SUCCESS"
        else
            STATUS="FAILED"
            send_alert "BACKUP FAILURE" "System failed to archive $FILENAME"
        fi

        # Write to log in a structured format (Date | File | Folder | Status)
        printf "%-20s | %-20s | %-15s | %-10s\n" "$DATE_STR" "$FILENAME" "$(date +%Y-%m-%d)" "$STATUS" >> "$LOG_FILE"
        
        # Re-check security status on every event
        check_security_status
    done
}

# Run it
monitor_changes
