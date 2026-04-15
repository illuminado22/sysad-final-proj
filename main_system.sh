#!/bin/bash
# Main System Master Controller - SysAd Project
 
source "$(dirname "$0")/backup_system.sh"
 
echo "Initializing Project System..."
backup_dirs
daily_folder
 
if ! pgrep -x "inotifywait" > /dev/null; then
    start_inotify
fi
 
start_backup_monitor
 
auto_cleanup
 
while true; do
    echo "------------------------------------------"
    echo "   SYSAD PROJECT: BACKUP & SECURITY"
    echo "------------------------------------------"
    echo "  Base Directory  : $base_dir"
    echo "  Monitored Folder: $watch_dir"
    echo "------------------------------------------"
    echo "1. Run Manual Cleanup Check (30-day rule)"
    echo "2. ACCESS MAIN BACKUP FOLDER (SECURITY)"
    echo "3. View System Logs & Alerts"
    echo "4. Recover a Deleted File"
    echo "5. Check for Duplicate Files"
    echo "6. Stop Monitor & Exit"
    echo "------------------------------------------"
    read -p "Select Option: " opt
 
    case $opt in
        1)
            auto_cleanup
            echo "Cleanup check complete." ;;
        2)
            if bash "$(dirname "$0")/(updated)SECURITY_SYSTEM.sh"; then
                echo "Access Granted."
                ls -R "$main_backup"
            else
                echo "$(date): SECURITY BREACH ATTEMPT" >> "$main_backup/alerts.log"
                echo "ALERT: Breach attempt has been logged."
            fi ;;
        3)
            echo "--- BACKUP LOGS ---"
            [ -f "$log_file" ] && tail -n 10 "$log_file" || echo "No logs yet."
            echo ""
            echo "--- SECURITY ALERTS ---"
            [ -f "$main_backup/alerts.log" ] && tail -n 5 "$main_backup/alerts.log" || echo "No alerts." ;;
        4)
            read -p "Filename to recover (e.g., test.txt): " fname
            read -p "Enter recovery path (e.g., ./monitored_files/): " rpath
            backup_recovered "$fname" "$rpath" ;;
        5)
            check_all_duplicates ;;
        6)
            echo "Stopping monitor..."
            stop_monitoring
            stop_backup_monitor
            exit 0 ;;
        *)
            echo "Invalid option. Please choose 1-6." ;;
    esac
    read -p "Press Enter to continue..."
done