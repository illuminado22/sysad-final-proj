#!/bin/bash
# Backup System
set -euo pipefail

# Forcing Root Access
if [ "$EUID" -ne 0 ]; then
    echo "This must be run as root"
    exit 1
fi

# ─────────────────────────────────────────────
# ORIGINAL: Variables
# ─────────────────────────────────────────────
backupdr="/home/ace/Desktop/SYSAD_PROJ/backups"
today=$(date +%Y-%m-%d)
targetdr="$backupdr/$today"
ADMIN_EMAIL="admin@localhost"
LOG_FILE="$backupdr/backup.log"
SOURCE_DIR="/home/ace/Desktop/SYSAD_PROJ/source_data"

# ─────────────────────────────────────────────
# ADDED: Table log header — written once if log is new
# Format: Date/Time | Filename | Daily Folder | Status
# ─────────────────────────────────────────────
init_log() {
    if [ ! -f "$LOG_FILE" ]; then
        printf "%-22s | %-40s | %-12s | %-10s\n" \
            "Date/Time" "Filename" "Daily Folder" "Status" >> "$LOG_FILE"
        printf '%s\n' "$(printf '─%.0s' {1..95})" >> "$LOG_FILE"
    fi
}

# ─────────────────────────────────────────────
# ADDED: Log a single file entry with status
# ─────────────────────────────────────────────
log_entry() {
    local filename="$1"
    local folder="$2"
    local status="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%-22s | %-40s | %-12s | %-10s\n" \
        "$timestamp" "$filename" "$folder" "$status" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────
# ORIGINAL: Create daily folder
# ADDED: chmod/chown on created directory
# ─────────────────────────────────────────────
setup_dirs() {
    today=$(date +%Y-%m-%d)
    targetdr="$backupdr/$today"
    mkdir -p "$targetdr"
    mkdir -p "$SOURCE_DIR"
    # --- ADDED: secure the backup target folder ---
    chmod 750 "$targetdr"
    chown root:root "$targetdr"
}

# ─────────────────────────────────────────────
# ORIGINAL: Copy files + compress
# CHANGED: cp replaced with rsync (as per tools list)
# ADDED: per-file status logging, mail alert
# ─────────────────────────────────────────────
run_backup() {
    setup_dirs
    init_log

    local backed_up=0
    local failed=0

    echo "$(date '+%Y-%m-%d %H:%M:%S') --- Starting backup for $today ---" >> "$LOG_FILE"

    # --- CHANGED: rsync instead of cp -r ---
    for filepath in "$SOURCE_DIR"/*; do
        [ -e "$filepath" ] || continue
        filename=$(basename "$filepath")

        if rsync -aq "$filepath" "$targetdr/"; then
            log_entry "$filename" "$today" "SUCCESS"
            backed_up=$((backed_up + 1))
        else
            log_entry "$filename" "$today" "FAILED"
            failed=$((failed + 1))
        fi
    done

    # --- ORIGINAL: compress the folder ---
    if tar -czf "$backupdr/${today}.tar.gz" -C "$backupdr" "$today" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Backup compressed: ${today}.tar.gz" >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Compression failed for $today" >> "$LOG_FILE"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') --- Backup complete. Backed up: $backed_up | Failed: $failed ---" >> "$LOG_FILE"
    printf '%s\n' "$(printf '─%.0s' {1..95})" >> "$LOG_FILE"

    # --- ADDED: email admin with backup summary ---
    {
        echo "Backup Summary for $today"
        echo "========================="
        echo "Files backed up : $backed_up"
        echo "Files failed    : $failed"
        echo "Archive         : $backupdr/${today}.tar.gz"
        echo ""
        echo "--- Last log entries ---"
        tail -20 "$LOG_FILE"
    } | mail -s "[SYSAD] Backup Report - $today (OK: $backed_up | FAIL: $failed)" "$ADMIN_EMAIL" 2>/dev/null || true

    echo "Backup complete — $backed_up files backed up, $failed failed."
}

# ─────────────────────────────────────────────
# ADDED: Real-time inotifywait watcher
# Watches source_data/ and triggers a backup
# immediately whenever a new file is created
# ─────────────────────────────────────────────
watch_mode() {
    if ! command -v inotifywait &>/dev/null; then
        echo "inotifywait not found. Install with: apt install inotify-tools"
        exit 1
    fi

    echo "Watching $SOURCE_DIR for new files... (Ctrl+C to stop)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') inotifywait watcher started." >> "$LOG_FILE"

    inotifywait -m -e close_write,moved_to --format '%f' "$SOURCE_DIR" 2>/dev/null | \
    while read -r new_file; do
        echo "New file detected: $new_file — triggering backup..."
        setup_dirs
        init_log

        filepath="$SOURCE_DIR/$new_file"
        if rsync -aq "$filepath" "$targetdr/"; then
            log_entry "$new_file" "$(date +%Y-%m-%d)" "SUCCESS"
            echo "$(date '+%Y-%m-%d %H:%M:%S') Real-time backup: $new_file SUCCESS" >> "$LOG_FILE"
        else
            log_entry "$new_file" "$(date +%Y-%m-%d)" "FAILED"
            echo "$(date '+%Y-%m-%d %H:%M:%S') Real-time backup: $new_file FAILED" >> "$LOG_FILE"
        fi

        # Re-compress archive after each real-time backup
        tar -czf "$backupdr/$(date +%Y-%m-%d).tar.gz" -C "$backupdr" "$(date +%Y-%m-%d)" 2>/dev/null || true

        # Notify admin of real-time backup
        echo "Real-time backup triggered by new file: $new_file at $(date '+%Y-%m-%d %H:%M:%S')" \
            | mail -s "[SYSAD] Real-time Backup - $new_file" "$ADMIN_EMAIL" 2>/dev/null || true
    done
}

# ─────────────────────────────────────────────
# ADDED: Register cron job for daily scheduled backup
# Runs every day at 2:00 AM — only adds once
# ─────────────────────────────────────────────
setup_cron() {
    SCRIPT_PATH="$(realpath "$0")"
    CRON_FILE="/etc/cron.d/project_backup"

    if [ ! -f "$CRON_FILE" ]; then
        echo "0 2 * * * root bash $SCRIPT_PATH --backup >> /var/log/project_backup.log 2>&1" > "$CRON_FILE"
        chmod 644 "$CRON_FILE"
        echo "Daily backup cron job registered at $CRON_FILE (runs at 2:00 AM daily)"
    fi
}

# ─────────────────────────────────────────────
# Entry point — mode selection
#   --backup  : run one-time backup (used by cron)
#   --watch   : start real-time inotifywait watcher
#   (no flag) : run backup once + setup cron + start watcher
# ─────────────────────────────────────────────
case "${1:-}" in
    --backup)
        run_backup
        ;;
    --watch)
        watch_mode
        ;;
    *)
        run_backup
        setup_cron
        echo ""
        echo "Starting real-time file watcher (background process)..."
        # Launch watcher in background so the script doesn't block
        nohup bash "$(realpath "$0")" --watch >> /var/log/project_backup_watch.log 2>&1 &
        echo "Watcher running in background (PID $!). Log: /var/log/project_backup_watch.log"
        ;;
esac
