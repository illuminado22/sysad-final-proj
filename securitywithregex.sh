#!/bin/bash
# Security System: Password Authorization & Aging
 
# Forced Root Access
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Authorization system must be run with sudo/root."
    exit 1 
fi
 
# System paths for credentials
pwd_f="/etc/project_auth"
mt_f="/etc/project_auth_meta"

# Regex pattern for password validation
# User password must have 6+ chars, 1 uppercase, 1 digit, exactly 1 special character
regex='^(?=(.*[^a-zA-Z0-9]){1}$)(?=.*[A-Z])(?=.*[0-9]).{6,}$'
 
# Initial Setting of Password for the System
if [ ! -f "$pwd_f" ]; then
    echo "--- SYSTEM INITIALIZATION: Set Admin Password ---"
    
    while true; do
        read -s -p "Create New Admin Password: " p; echo
        
        if [[ "$p" =~ $regex ]]; then
            openssl passwd -6 "$p" > "$pwd_f"
            date +%s > "$mt_f"
            chmod 600 "$pwd_f" "$mt_f"
            echo "Password secured in $pwd_f"
            break
        else
            echo "Invalid password."
            echo "Must be at least 6 characters, include 1 uppercase, 1 number, and exactly 1 special character."
        fi
    done
fi
 
# 3-Attempt Login Policy
for i in {1..3}; do
    read -s -p "Enter Admin Password: " in; echo
    
    salt=$(cut -d '$' -f3 "$pwd_f")
    if [ "$(openssl passwd -6 -salt "$salt" "$in")" == "$(cat "$pwd_f")" ]; then
        
        # Password Expiration Logic (10 mins demo)
        mins=$(( ($(date +%s) - $(cat "$mt_f")) / 60 ))
        if [ $mins -ge 10 ]; then
            echo "Warning: Password Expired. The System is Insecure, Files may be Compromised"
 
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

            # NEW PASSWORD WITH REGEX CHECK
            while true; do
                read -s -p "Enter New Password: " n; echo
                
                if [[ "$n" =~ $regex ]]; then
                    openssl passwd -6 "$n" > "$pwd_f"
                    date +%s > "$mt_f"
                    echo "Password successfully renewed."
                    break
                else
                    echo "Invalid password."
                    echo "Must be at least 6 characters, include 1 uppercase, 1 number, and exactly 1 special character."
                fi
            done
        fi
        exit 0
    fi
    echo "Access Denied. $((3-i)) attempts remaining."
done
 
exit 1
