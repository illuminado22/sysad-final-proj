#!/bin/bash
# Main System: Integration & Recovery

set -euo pipefail

SOURCE_DIR="/home/leroy/Downloads/sysad1p2/source_data"
BACKUP_ROOT="/home/leroy/Downloads/sysad1p2/backups"

mkdir -p "$SOURCE_DIR" "$BACKUP_ROOT"

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run as root."
    exit 1
fi

# Auto-start the background monitor with Absolute Path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! pgrep -f "monitor_system.sh" > /dev/null; then
    bash "$SCRIPT_DIR/monitor_system.sh" &
    echo "Background monitor active."
fi

recover_file() {
    echo "--- File Recovery Menu ---"
    # Use mapfile for safer array handling
    mapfile -t files < <(find "$BACKUP_ROOT" -type f -name "(DELETED)_*.zip")
    
    if [ ${#files[@]} -eq 0 ]; then
        echo "No deleted files found in $BACKUP_ROOT."
        return
    fi

    for i in "${!files[@]}"; do
        echo "$i) $(basename "${files[$i]}")"
    done

    read -p "Select file index: " idx
    
    if [[ -z "$idx" || ! "$idx" =~ ^[0-9]+$ || "$idx" -ge "${#files[@]}" ]]; then
        echo "Invalid selection."
        return
    fi

    selected_zip="${files[$idx]}"
    # Extract original name: remove (DELETED)_ and .zip
    base_name=$(basename "$selected_zip" | sed 's/(DELETED)_//;s/.zip//')
    target_folder=$(dirname "$selected_zip")

    # Extract and rename
    unzip -p "$selected_zip" > "$SOURCE_DIR/$base_name"
    mv "$selected_zip" "$target_folder/(RECOVERED)_$base_name"
    
    echo "File '$base_name' has been restored to source and labeled (RECOVERED) in backups."
}

while true; do
    echo -e "\n=========================================="
    echo "   SECURE BACKUP & RECOVERY PORTAL        "
    echo "=========================================="
    echo "1. View Source Folder"
    echo "2. Access Backup Storage (Auth)"
    echo "3. Recover Deleted File (Auth)"
    echo "4. Exit"
    read -p "Choice: " choice

    case $choice in
        1) ls -F "$SOURCE_DIR" ;;
        2) if bash "$SCRIPT_DIR/security_system.sh"; then ls -R "$BACKUP_ROOT"; fi ;;
        3) if bash "$SCRIPT_DIR/security_system.sh"; then recover_file; fi ;;
        4) echo "Shutting down portal."; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
