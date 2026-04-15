#!/bin/bash
# Security System: Password Authorization & Aging
 
NOTIFY_EMAIL="nikkandoy9@gmail.com"
 
send_expiry_email() {
    local mins="$1"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
 
    local body="Backup System Report
==============================
Time     : $timestamp
Function : password_expiry
Detail   : Admin password has expired (${mins} minutes old)
Host     : $(hostname)
=============================="
 
    echo "$body" | msmtp -a gmail "$NOTIFY_EMAIL" 2>/dev/null
    echo "NOTIFICATION sent to $NOTIFY_EMAIL --- password expired"
}
 
# Forced Root Access
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Authorization system must be run with sudo/root."
    exit 1 
fi
 
# System-wide paths for credentials
pwd_f="/etc/project_auth"
mt_f="/etc/project_auth_meta"
 
# Initial Setting of Password for the System
if [ ! -f "$pwd_f" ]; then
    echo "--- SYSTEM INITIALIZATION: Set Admin Password ---"
    read -s -p "Create New Admin Password: " p; echo
    openssl passwd -6 "$p" > "$pwd_f"
    date +%s > "$mt_f"
    chmod 600 "$pwd_f" "$mt_f"
    echo "Password secured in $pwd_f"
fi
 
# 3-Attempt Login Policy
for i in {1..3}; do
    read -s -p "Enter Admin Password: " in; echo
    
    # Extract salt and verify SHA-512 hash
    salt=$(cut -d '$' -f3 "$pwd_f")
    if [ "$(openssl passwd -6 -salt "$salt" "$in")" == "$(cat "$pwd_f")" ]; then
        
        # Password Expiration Logic
        # FOR TEN MINS DEMO
        mins=$(( ($(date +%s) - $(cat "$mt_f")) / 60 ))
        if [ $mins -ge 1 ]; then
        #days=$(( ($(date +%s) - $(cat "$mt_f")) / 86400 ))
        #if [ $days -ge 7 ]; then
            echo "Warning: Password Expired. The System is Insecure, Files may be Compromised"
            send_expiry_email "$mins"
 
            # Require re-confirmation
            confirmed=false
            for j in {1..3}; do
                read -s -p "Re-enter Expired Password to Confirm: " confirm; echo
                confirm_salt=$(cut -d '$' -f3 "$pwd_f")
                if [ "$(openssl passwd -6 -salt "$confirm_salt" "$confirm")" == "$(cat "$pwd_f")" ]; then
                    confirmed=true
                    break
                fi
                echo "Incorrect. $((3-j)) confirmation attempts remaining."
            done
 
            if [ "$confirmed" = false ]; then
                echo "Confirmation failed. Password renewal failed."
                exit 1
            fi
 
            read -s -p "Enter New Password: " n; echo
            openssl passwd -6 "$n" > "$pwd_f"
            date +%s > "$mt_f"
            echo "Password successfully renewed."
        fi
        exit 0 # Access Granted
    fi
    echo "Access Denied. $((3-i)) attempts remaining."
done
 
exit 1 # Access Terminated