#!/bin/bash
# Main System: Final Integration

source ./backup_system.sh

# Initial Automation
echo "Initializing Project System..."
start_inotify
auto_cleanup

while true; do
    echo "------------------------------------------"
    echo "  SYSDAD PROJECT: BACKUP & SECURITY      "
    echo "------------------------------------------"
    echo "1. Run Manual Cleanup Check"
    echo "2. ACCESS MAIN BACKUP FOLDER (SECURITY)"
    echo "3. View System Logs & Alerts"
    echo "4. Recover a Deleted File"
    echo "5. Stop Monitor & Exit"
    echo "------------------------------------------"
    read -p "Select Option: " opt

    case $opt in
        1) auto_cleanup ;;
        2) 
            if ./security_system.sh; then
                echo "Access Granted."
                ls -R "$main_backup"
            else
                echo "$(date): SECURITY BREACH ATTEMPT" >> "$main_backup/alerts.log"
                echo "ALERT: Admin has been notified of the breach."
            fi ;;
        3) 
            echo "--- BACKUP LOGS ---"
            [ -f "$log_file" ] && tail -n 10 "$log_file"
            echo -e "\n--- SECURITY ALERTS ---"
            [ -f "$main_backup/alerts.log" ] && tail -n 5 "$main_backup/alerts.log" ;;
        4)
            read -p "Filename to recover: " fname
            read -p "Recover into which path? " rpath
            backup_recovered "$fname" "$rpath" ;;
        5) 
            stop_monitoring
            exit 0 ;;
    esac
    read -p "Press Enter to continue..."
done
