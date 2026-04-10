#!/bin/bash
# Security System: Final Version

set -euo pipefail

# Force Root Access
if [ "$EUID" -ne 0 ]; then
    echo "Error: Authorization system must be run as root."
    exit 1
fi

psswrd_file="/etc/project_auth"
mt_file="/etc/project_auth_meta"
max_days=7

# Initial Setup if no password exists
if [ ! -f "$psswrd_file" ]; then
    echo "------------------------------------------------"
    echo "SYSTEM FIRST-TIME SETUP: Create Admin Password"
    echo "------------------------------------------------"
    while true; do
        read -s -p "New Admin Password: " newpass
        echo
        specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)
        if [[ ${#newpass} -ge 6 && "$newpass" =~ [A-Z] && "$newpass" =~ [0-9] && $specials -eq 1 ]]; then
            openssl passwd -6 "$newpass" > "$psswrd_file"
            date +%s > "$mt_file"
            chmod 600 "$psswrd_file" "$mt_file"
            echo "Password successfully encrypted and saved."
            break
        else
            echo "Requirement: 6+ chars, 1 Upper, 1 Num, 1 Special char."
        fi
    done
fi

# Authentication Logic
attempt=0
while [ $attempt -lt 3 ]; do
    read -s -p "Enter Admin Password: " input
    echo
    stored_hash=$(cat "$psswrd_file")
    salt=$(echo "$stored_hash" | cut -d '$' -f3)
    input_hash=$(openssl passwd -6 -salt "$salt" "$input")

    if [ "$input_hash" = "$stored_hash" ]; then
        # Check Expiration
        last_change=$(cat "$mt_file")
        since=$(( ($(date +%s) - last_change) / 86400 ))
        if [ $since -ge $max_days ]; then
            echo "WARNING: Password has expired (7-day policy)."
            read -s -p "Enter New Password: " renew
            echo
            openssl passwd -6 "$renew" > "$psswrd_file"
            date +%s > "$mt_file"
            echo "Password rotated."
        fi
        exit 0 
    else
        attempt=$((attempt + 1))
        echo "Incorrect. $((3 - attempt)) attempts left."
    fi
done

echo "Terminating: Too many failed attempts."
exit 1
