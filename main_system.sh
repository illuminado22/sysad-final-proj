#!/bin/bash
# Main System Master Controller - SysAd Project

# Imports the backup functions
source ./backup_system.sh

# Initial Setup: Ensure monitoring starts as soon as the script runs
echo "Initializing Project System..."
if ! pgrep -x "inotifywait" > /dev/null; then
    start_inotify
fi
auto_cleanup

while true; do
    echo "------------------------------------------"
    echo "  SYSDAD PROJECT: BACKUP & SECURITY      "
    echo "------------------------------------------"
    echo "1. Run Manual Cleanup Check (30-day rule)"
    echo "2. ACCESS MAIN BACKUP FOLDER (SECURITY)"
    echo "3. View System Logs & Alerts"
    echo "4. Recover a Deleted File"
    echo "5. Stop Monitor & Exit"
    echo "------------------------------------------"
    read -p "Select Option: " opt

    case $opt in
        1) 
            auto_cleanup 
            echo "Cleanup check complete." ;;
        2) 
            # Calls the security script. It must be in the same folder.
            if ./security_system.sh; then
                echo "Access Granted."
                ls -R "$main_backup"
            else
                # Logs the breach attempt if password fails or script fails
                echo "$(date): SECURITY BREACH ATTEMPT" >> "$main_backup/alerts.log"
                echo "ALERT: Admin has been notified of the breach."
            fi ;;
        3) 
            echo "--- BACKUP LOGS ---"
            [ -f "$log_file" ] && tail -n 10 "$log_file" || echo "No logs yet."
            echo -e "\n--- SECURITY ALERTS ---"
            [ -f "$main_backup/alerts.log" ] && tail -n 5 "$main_backup/alerts.log" || echo "No alerts." ;;
        4)
            read -p "Filename to recover (e.g., test.txt): " fname
            read -p "Enter recovery path (e.g., ./monitored_files/): " rpath
            backup_recovered "$fname" "$rpath" ;;
        5) 
            echo "Stopping monitor..."
            stop_monitoring
            exit 0 ;;
        *)
            echo "Invalid option. Please choose 1-5." ;;
    esac
    read -p "Press Enter to continue..."
done
