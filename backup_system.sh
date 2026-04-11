#!/bin/bash
 
set -euo pipefail
 
main_backup="/home/yourdesktop/sysad_proj/backups"
watch_dir="/home"
log_file="$main_backup/backuplog.txt"
zip_archive="$main_backup/.deleted_archive"
 
monitoring_PID=""
 
umask 077
#initialized the needed folder and configured them
backup_dirs() {
    mkdir -p "$main_backup"
    mkdir -p "$zip_archive"
    chmod 700 "$main_backup" "$zip_archive"
 
    today=$(date +"%Y-%m-%d")
    today_folder="$main_backup/backupfolder($today)"
    mkdir -p "$today_folder"
 
    echo "Today's backup folder ready: backupfolder($today)"
}
 
get_today_folder() {
    today=$(date +"%Y-%m-%d")
    echo "$main_backup/backupfolder($today)"
}

#log event uses 3 argument
log_activity() {
    local category="$1"
    local action="$2"
    local detail="$3"
    local timestamp
 
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$timestamp, $category, $action, $detail" >> "$log_file"
}

#backup creation uses 1 argument 
backup_created() {
    local source="$1"
    local filename
    filename=$(basename "$source")
    local destination_folder
    destination_folder=$(get_today_folder)
    local destination="$destination_folder/CREATED_$filename"
 
    if [ ! -f "$source" ]; then
        echo "ERROR file not found: $source"
        return 1
    fi
 
    cp "$source" "$destination"
    echo "BACKUP created: CREATED_$filename"
    log_activity "BACKUP" "CREATED" "$filename -> $(basename "$destination_folder")"
}

#backup delete uses 1 argument
backup_deleted() {
    local source="$1"
    local filename
    filename=$(basename "$source")
    local destination_folder
    destination_folder=$(get_today_folder)
    local destination="$destination_folder/DELETED_$filename"
    local delete_date
    delete_date=$(date +%s)
    local zip_name="$zip_archive/DELETED_${filename}_deleted_${delete_date}.zip"
 
    if [ ! -f "$source" ]; then
        echo "ERROR file not found: $source"
        return 1
    fi
 
    cp "$source" "$destination"
    zip -j "$zip_name" "$source" > /dev/null 2>&1
    echo "BACKUP deleted file backed up: DELETED_$filename"
    echo "ZIP compressed archive saved for long term retention"
 
    echo "${destination}|${delete_date}" >> "$main_backup/.expiry_registry"
 
    log_activity "BACKUP" "DELETED" "$filename -> $(basename "$destination_folder") + ZIP archive saved"
}

#backup recover uses 2 argument
backup_recovered() {
    local filename="$1"
    local recover_into="$2"
 
    local found
    found=$(find "$main_backup" -name "DELETED_$filename" | sort | tail -1)
 
    if [ -z "$found" ]; then
        echo "ERROR No deleted backup found for: $filename"
        echo "Check the ZIP archive at: $zip_archive"
        return 1
    fi
 
    local destination_folder
    destination_folder=$(get_today_folder)
    local recovered_copy="$destination_folder/RECOVERED_$filename"
 
    cp "$found" "$recover_into/$filename"
    cp "$found" "$recovered_copy"
 
    if [ -f "$main_backup/.expiry_registry" ]; then
        sed -i "\|$found|d" "$main_backup/.expiry_registry"
    fi
 
    echo "BACKUP File recovered: $filename -> $recover_into"
    log_activity "BACKUP" "RECOVERED" "$filename recovered to $recover_into"
}

#automatically delete UNRECOVERED files that is 30 days old
auto_cleanup() {
    echo "CLEANUP checking for expired deleted files."
 
    if [ ! -f "$main_backup/.expiry_registry" ]; then
        echo "CLEANUP No expiry registry found."
        return 0
    fi
 
    local now
    now=$(date +%s)
    local thirty_days=$(( 30 * 86400 ))
    local cleaned=0
    local temp_registry
    temp_registry=$(mktemp)
 
    while IFS='|' read -r filepath delete_timestamp; do
        [ -z "$filepath" ] && continue
 
        local age=$(( now - delete_timestamp ))
 
        if [ "$age" -ge "$thirty_days" ]; then
            if [ -f "$filepath" ]; then
                local fname
                fname=$(basename "$filepath")
                rm -f "$filepath"
                echo "CLEANUP Expired and removed: $fname"
                log_activity "CLEANUP" "EXPIRED_DELETED" "$fname removed after 30 days (kept in ZIP archive)"
                cleaned=$(( cleaned + 1 ))
            fi
        else
            echo "${filepath}|${delete_timestamp}" >> "$temp_registry"
        fi
    done < "$main_backup/.expiry_registry"
 
    mv "$temp_registry" "$main_backup/.expiry_registry"
 
    if [ "$cleaned" -eq 0 ]; then
        echo "CLEANUP No expired files found. All good!"
    else
        echo "CLEANUP Removed $cleaned expired deleted files. ZIP archives are still kept."
    fi
}

#if the folder isn't created just to catch it
daily_folder() {
    local today_folder
    today_folder=$(get_today_folder)
    if [ ! -d "$today_folder" ]; then
        mkdir -p "$today_folder"
        chmod 700 "$today_folder"
        echo "New daily folder created: $(basename "$today_folder")"
        log_activity "SYSTEM" "DAILY_FOLDER_CREATED" "$(basename "$today_folder")"
    fi
}

#check if the tool is installed 
check_inotify() {
    if ! command -v inotifywait &> /dev/null; then
        echo "WARNING inotify is not yet installed."
        echo "Run: sudo apt install inotify-tools"
        return 1
    fi
    return 0
}

#start monitoring
start_inotify() {
    if ! check_inotify; then
        return 1
    fi
 
    export main_backup log_file zip_archive watch_dir
 
    inotifywait -mr -e create -e delete --format "%e %w%f" "$watch_dir" 2>/dev/null | \
    while read -r event filepath; do
 
        if [[ "$filepath" == "$main_backup"* ]]; then
            continue
        fi
 
        filename=$(basename "$filepath")
 
        if [[ "$filename" == .* ]]; then
            continue
        fi
 
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        today=$(date +"%Y-%m-%d")
        destination_folder="$main_backup/backupfolder($today)"
        mkdir -p "$destination_folder"
 
        case "$event" in
            CREATE)
                sleep 0.5
                if [ -f "$filepath" ]; then
                    cp "$filepath" "$destination_folder/CREATED_$filename" 2>/dev/null
                    echo "[$timestamp] AUTO-MONITORING CREATED $filename" >> "$log_file"
                    echo "MONITORING Auto-backed up new file: $filename"
                fi
                ;;
 
            DELETE)
                found_copy=$(find "$main_backup" -name "CREATED_$filename" | sort | tail -1)
 
                if [ -n "$found_copy" ]; then
                    delete_date=$(date +%s)
                    destination_deleted="$destination_folder/DELETED_$filename"
                    zip_name="$main_backup/.deleted_archive/DELETED_${filename}_deleted_${delete_date}.zip"
 
                    cp "$found_copy" "$destination_deleted" 2>/dev/null
                    zip -j "$zip_name" "$found_copy" > /dev/null 2>&1
                    echo "${destination_deleted}|${delete_date}" >> "$main_backup/.expiry_registry"
                    echo "[$timestamp] AUTO-MONITORING DELETED $filename -> ZIP archive saved" >> "$log_file"
                    echo "MONITORING Auto-backed up deleted file: $filename"
                else
                    echo "[$timestamp] AUTO-MONITORING DELETED $filename (No backup copy found to ZIP)" >> "$log_file"
                    echo "MONITORING Detected deletion: $filename (no prior backup found)"
                fi
                ;;
        esac
    done &
 
    monitoring_PID=$!
    echo "Auto-monitoring started in background (PID is $monitoring_PID)"
    echo "Monitoring: $watch_dir"
    log_activity "SYSTEM" "MONITORING_STARTED" "Monitoring $watch_dir (PID is $monitoring_PID)"
}

#stop monitoring
stop_monitoring() {
    if [ -n "${monitoring_PID:-}" ] && kill -0 "$monitoring_PID" 2>/dev/null; then
        kill "$monitoring_PID" 2>/dev/null
        echo "Auto-monitoring stopped (PID is $monitoring_PID)"
        log_activity "SYSTEM" "MONITORING_STOPPED" "$monitoring_PID stopped"
        monitoring_PID=""
    else
        echo "No active monitor to stop."
    fi
}