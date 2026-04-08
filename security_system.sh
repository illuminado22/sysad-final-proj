#!/bin/bash
# Security System
set -euo pipefail

# Forcing Root Access
if [ "$EUID" -ne 0 ]; then
    echo "This must be run as root"
    exit 1
fi

# Variables
psswrd_file="/etc/project_auth"
mt_file="/etc/project_auth_meta"
max=7
ADMIN_EMAIL="admin@localhost"
umask 077

# ─────────────────────────────────────────────
# ORIGINAL: Creating Initial Password for the System
# ─────────────────────────────────────────────
ini_password() {
    if [ ! -f "$psswrd_file" ]; then
        echo "Warning!: No system password yet. Please create one."
        read -s -p "Enter your new password: " newpass
        echo
        specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)
        if ! [[ -n "$newpass" && ${#newpass} -ge 6 && "$newpass" =~ [A-Z] && "$newpass" =~ [0-9] && $specials -eq 1 ]]; then
            echo "Password must be at least 6 characters, include one uppercase letter, one number, and exactly one special character."
            exit 1
        fi
        openssl passwd -6 "$newpass" > "$psswrd_file"
        date +%s > "$mt_file"
        chmod 600 "$psswrd_file" "$mt_file"
        unset newpass specials
        echo "System Password Successfully Assigned."
    fi
}

# ─────────────────────────────────────────────
# ORIGINAL: Password Aging / Expiration
# ADDED: wall broadcast + mail alert
# ─────────────────────────────────────────────
psswrd_expiration() {
    if [ -f "$mt_file" ]; then
        last_change=$(cat "$mt_file")
        since=$(( ( $(date +%s) - last_change ) / 86400 ))

        # --- ADDED: warn admin by email at 5 days (2 days before expiry) ---
        if [ "$since" -ge 5 ] && [ "$since" -lt "$max" ]; then
            days_left=$(( max - since ))
            echo "WARNING: System password expires in $days_left day(s). Please renew it." \
                | mail -s "[SYSAD] Password Expiry Warning - $days_left day(s) left" "$ADMIN_EMAIL" 2>/dev/null || true
        fi

        if [ "$since" -ge "$max" ]; then
            # --- ADDED: broadcast to ALL logged-in users via wall ---
            wall "WARNING: The System is Insecure, Files and Data may be Compromised. Password has expired. Admin must renew immediately."

            # --- ADDED: email admin about expired password ---
            echo "CRITICAL: The system password has expired ($since days old). Login and run security_system.sh to renew." \
                | mail -s "[SYSAD] CRITICAL - System Password Expired" "$ADMIN_EMAIL" 2>/dev/null || true

            echo "WARNING: The System is Insecure, Files and Data may be Compromised"
            renew_psswrd
        fi
    fi
}

# ─────────────────────────────────────────────
# ORIGINAL: User Authentication
# ─────────────────────────────────────────────
authenticate() {
    max_attempts=3
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        echo -n "Enter the System Password: "
        read -s input
        echo
        if [[ -z "$input" ]]; then
            echo "Password cannot be empty."
            continue
        fi
        stored_hash=$(cat "$psswrd_file")
        salt=$(echo "$stored_hash" | cut -d '$' -f3)
        input_hash=$(openssl passwd -6 -salt "$salt" "$input")
        if [ "$input_hash" = "$stored_hash" ]; then
            echo "Access Granted."
            unset input input_hash
            psswrd_expiration
            return
        else
            echo "Incorrect password."
            attempt=$((attempt + 1))
        fi
    done
    echo "Too many failed attempts. Access denied."
    exit 1
}

# ─────────────────────────────────────────────
# ORIGINAL: Password Renewal
# ─────────────────────────────────────────────
renew_psswrd() {
    echo "Renew the system Password: "
    read -s -p "Enter the New Password: " newpass
    echo
    specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)
    if ! [[ -n "$newpass" && ${#newpass} -ge 6 && "$newpass" =~ [A-Z] && "$newpass" =~ [0-9] && $specials -eq 1 ]]; then
        echo "Password must be at least 6 characters, include one uppercase letter, one number, and exactly one special character."
        return
    fi
    openssl passwd -6 "$newpass" > "$psswrd_file"
    date +%s > "$mt_file"
    chmod 600 "$psswrd_file" "$mt_file"
    unset newpass specials
    echo "Password Successfully Renewed."

    # --- ADDED: notify admin that password was successfully renewed ---
    echo "The system password was renewed on $(date '+%Y-%m-%d %H:%M:%S')." \
        | mail -s "[SYSAD] System Password Renewed" "$ADMIN_EMAIL" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# ADDED: Register weekly cron job for expiry check
# Runs every Monday at 8 AM — only adds once
# ─────────────────────────────────────────────
setup_cron() {
    SCRIPT_PATH="$(realpath "$0")"
    CRON_JOB="0 8 * * 1 root bash $SCRIPT_PATH --cron-check >> /var/log/project_security.log 2>&1"
    CRON_FILE="/etc/cron.d/project_security"

    if [ ! -f "$CRON_FILE" ]; then
        echo "$CRON_JOB" > "$CRON_FILE"
        chmod 644 "$CRON_FILE"
        echo "Weekly password expiry cron job registered at $CRON_FILE"
    fi
}

# ─────────────────────────────────────────────
# ADDED: Cron-only mode (non-interactive expiry check)
# Called automatically by the cron job above
# ─────────────────────────────────────────────
cron_check() {
    if [ -f "$mt_file" ]; then
        last_change=$(cat "$mt_file")
        since=$(( ( $(date +%s) - last_change ) / 86400 ))
        days_left=$(( max - since ))

        if [ "$since" -ge "$max" ]; then
            wall "WARNING: The System is Insecure, Files and Data may be Compromised. Password expired ${since} days ago."
            echo "CRITICAL: Password expired ${since} days ago. Renew immediately by running security_system.sh." \
                | mail -s "[SYSAD] CRITICAL - Expired Password" "$ADMIN_EMAIL" 2>/dev/null || true
        elif [ "$since" -ge 5 ]; then
            echo "Reminder: System password expires in $days_left day(s). Please renew soon." \
                | mail -s "[SYSAD] Password Expiry Reminder - $days_left day(s) left" "$ADMIN_EMAIL" 2>/dev/null || true
        fi
    fi
    exit 0
}

# ─────────────────────────────────────────────
# Entry point — handle --cron-check flag
# ─────────────────────────────────────────────
if [[ "${1:-}" == "--cron-check" ]]; then
    cron_check
fi

ini_password
setup_cron
authenticate
