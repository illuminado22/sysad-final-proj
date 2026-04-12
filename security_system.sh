#!/bin/bash
# Security System: Password Authorization & Aging
 
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Authorization system must be run with sudo/root."
    exit 1 
fi
 
pwd_f="/etc/project_auth"
mt_f="/etc/project_auth_meta"
 
NOTIFY_EMAIL="nikkandoy9@gmail.com"
 
# --- FOR TESTING: 5 minutes = 300 seconds ---
EXPIRY_SECONDS=300
 
send_expiry_email() {
    local minutes_since="$1"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
 
    local body="Backup System Report
==============================
Time     : $timestamp
Function : password_expiry
Detail   : Admin password has expired (${minutes_since} minutes old - 5 minute test policy)
Host     : $(hostname)
=============================="
 
    echo "$body" | msmtp -a gmail "$NOTIFY_EMAIL" 2>/dev/null
    echo "NOTIFICATION sent to $NOTIFY_EMAIL --- password expired"
}
 
if [ ! -f "$pwd_f" ]; then
    echo "--- SYSTEM INITIALIZATION: Set Admin Password ---"
    read -s -p "Create New Admin Password: " p; echo
    openssl passwd -6 "$p" > "$pwd_f"
    date +%s > "$mt_f"
    chmod 600 "$pwd_f" "$mt_f"
    echo "Password secured in $pwd_f"
fi
 
for i in {1..3}; do
    read -s -p "Enter Admin Password: " in; echo
    
    salt=$(cut -d '$' -f3 "$pwd_f")
    if [ "$(openssl passwd -6 -salt "$salt" "$in")" == "$(cat "$pwd_f")" ]; then
        
        seconds_since=$(( $(date +%s) - $(cat "$mt_f") ))
        if [ "$seconds_since" -ge "$EXPIRY_SECONDS" ]; then
            minutes_since=$(( seconds_since / 60 ))
            echo "WARNING: Password has expired (${minutes_since} minutes old)."
            send_expiry_email "$minutes_since"
            echo "Please consider renewing your password for security."
        fi
        exit 0
    fi
    echo "Access Denied. $((3-i)) attempts remaining."
done
 
exit 1
 