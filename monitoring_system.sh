#!/bin/bash
# Monitoring & Notification System
# Sets up auditd rules, syslog, logwatch,
# wall alerts, and mail notifications.
set -euo pipefail

# Forcing Root Access
if [ "$EUID" -ne 0 ]; then
    echo "This must be run as root"
    exit 1
fi

# ─────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────
BACKUP_DIR="/home/ace/Desktop/SYSAD_PROJ/backups"
SOURCE_DIR="/home/ace/Desktop/SYSAD_PROJ/source_data"
SHARED_DIR="/home/ace/Desktop/SYSAD_PROJ/shared"
ADMIN_EMAIL="admin@localhost"
AUDIT_RULES_FILE="/etc/audit/rules.d/project.rules"
LOGWATCH_CONF="/etc/logwatch/conf/logwatch.conf"
SYSLOG_TAG="SYSAD_PROJECT"
MONITOR_LOG="/var/log/project_monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$MONITOR_LOG"
    # Also pipe to syslog so it appears in /var/log/syslog
    logger -t "$SYSLOG_TAG" "$1"
}

# ─────────────────────────────────────────────
# 1. auditd — log all file access events
#    on the project directories
# ─────────────────────────────────────────────
setup_auditd() {
    if ! command -v auditctl &>/dev/null; then
        log "auditd not installed. Install with: apt install auditd"
        return
    fi

    log "Configuring auditd rules..."

    mkdir -p "$(dirname "$AUDIT_RULES_FILE")"

    cat > "$AUDIT_RULES_FILE" <<EOF
# SYSAD PROJECT — audit rules
# Log all read/write/execute/attribute changes on project dirs

# Watch source_data for any file creation, modification, deletion
-w $SOURCE_DIR -p rwxa -k project_source

# Watch backup directory for writes and attribute changes
-w $BACKUP_DIR -p wa -k project_backup

# Watch shared workspace for all access
-w $SHARED_DIR -p rwxa -k project_shared

# Watch the password files used by security_system.sh
-w /etc/project_auth      -p rwa -k project_auth
-w /etc/project_auth_meta -p rwa -k project_auth_meta
EOF

    chmod 640 "$AUDIT_RULES_FILE"

    # Reload auditd rules
    if augenrules --load &>/dev/null; then
        log "auditd rules loaded from $AUDIT_RULES_FILE"
    else
        auditctl -R "$AUDIT_RULES_FILE" 2>/dev/null && log "auditd rules applied via auditctl." \
            || log "WARNING: Could not load auditd rules. Check auditd service status."
    fi

    # Ensure auditd starts on boot
    systemctl enable auditd 2>/dev/null && systemctl restart auditd 2>/dev/null \
        && log "auditd enabled and restarted." \
        || log "WARNING: Could not restart auditd."
}

# ─────────────────────────────────────────────
# 2. syslog — project events are already tagged
#    via logger -t SYSAD_PROJECT in the log()
#    function above. This section ensures rsyslog
#    writes them to a dedicated file as well.
# ─────────────────────────────────────────────
setup_syslog() {
    RSYSLOG_CONF="/etc/rsyslog.d/30-sysad-project.conf"

    if [ ! -f "$RSYSLOG_CONF" ]; then
        cat > "$RSYSLOG_CONF" <<EOF
# SYSAD PROJECT — route tagged messages to dedicated log
:programname, isequal, "$SYSLOG_TAG" /var/log/project_syslog.log
& stop
EOF
        chmod 644 "$RSYSLOG_CONF"
        systemctl restart rsyslog 2>/dev/null && log "rsyslog configured — project logs → /var/log/project_syslog.log" \
            || log "WARNING: Could not restart rsyslog."
    else
        log "rsyslog config already exists at $RSYSLOG_CONF — skipping."
    fi
}

# ─────────────────────────────────────────────
# 3. logwatch — daily log summary emailed to admin
# ─────────────────────────────────────────────
setup_logwatch() {
    if ! command -v logwatch &>/dev/null; then
        log "logwatch not installed. Install with: apt install logwatch"
        return
    fi

    log "Configuring logwatch..."

    # Override logwatch defaults to email admin daily
    mkdir -p /etc/logwatch/conf
    cat > "$LOGWATCH_CONF" <<EOF
# SYSAD PROJECT logwatch config
MailTo = $ADMIN_EMAIL
MailFrom = sysad-monitor@localhost
Output = mail
Format = html
Range = yesterday
Detail = med
Service = All
EOF
    chmod 644 "$LOGWATCH_CONF"

    # Register daily logwatch cron job
    CRON_FILE="/etc/cron.d/project_logwatch"
    if [ ! -f "$CRON_FILE" ]; then
        echo "0 7 * * * root /usr/sbin/logwatch --output mail >> /var/log/project_logwatch.log 2>&1" > "$CRON_FILE"
        chmod 644 "$CRON_FILE"
        log "logwatch daily cron registered (runs at 7:00 AM). Reports sent to $ADMIN_EMAIL"
    fi
}

# ─────────────────────────────────────────────
# 4. wall alert broadcaster
#    Called by cron or other scripts to push
#    a visible warning to all logged-in users.
# ─────────────────────────────────────────────
broadcast_alert() {
    local message="${1:-SYSAD ALERT: Please check system status.}"
    wall "$message"
    log "wall broadcast sent: $message"
    echo "$message at $(date '+%Y-%m-%d %H:%M:%S')" \
        | mail -s "[SYSAD] System Alert" "$ADMIN_EMAIL" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# 5. Real-time audit event checker
#    Watches /var/log/audit/audit.log for
#    project-tagged events and mails admin
#    if suspicious activity is detected.
# ─────────────────────────────────────────────
watch_audit_log() {
    AUDIT_LOG="/var/log/audit/audit.log"

    if [ ! -f "$AUDIT_LOG" ]; then
        log "Audit log not found at $AUDIT_LOG — is auditd running?"
        return
    fi

    log "Watching audit log for project events... (Ctrl+C to stop)"

    tail -Fn0 "$AUDIT_LOG" | while read -r line; do
        # Check if the line relates to our project keys
        if echo "$line" | grep -qE 'key="project_(source|backup|shared|auth)"'; then
            event_time=$(date '+%Y-%m-%d %H:%M:%S')
            log "AUDIT EVENT: $line"

            # Alert on suspicious write/delete to auth files
            if echo "$line" | grep -q 'key="project_auth"'; then
                broadcast_alert "SECURITY ALERT: Access detected on system password files at $event_time"
            fi
        fi
    done
}

# ─────────────────────────────────────────────
# 6. Daily audit summary report to admin
# ─────────────────────────────────────────────
send_audit_report() {
    local report_date
    report_date=$(date '+%Y-%m-%d')

    {
        echo "SYSAD Project — Daily Audit Report for $report_date"
        echo "===================================================="
        echo ""
        echo "--- Backup directory events ---"
        ausearch -k project_backup --start today 2>/dev/null | tail -30 || echo "No events or ausearch unavailable."
        echo ""
        echo "--- Source data events ---"
        ausearch -k project_source --start today 2>/dev/null | tail -30 || echo "No events."
        echo ""
        echo "--- Auth file access events ---"
        ausearch -k project_auth --start today 2>/dev/null | tail -20 || echo "No events."
        echo ""
        echo "--- Recent project syslog entries ---"
        grep "$SYSLOG_TAG" /var/log/syslog 2>/dev/null | tail -30 || true
    } | mail -s "[SYSAD] Daily Audit Report - $report_date" "$ADMIN_EMAIL" 2>/dev/null \
        && log "Daily audit report sent to $ADMIN_EMAIL" \
        || log "WARNING: Could not send audit report email."
}

# ─────────────────────────────────────────────
# 7. Register cron for daily audit report
# ─────────────────────────────────────────────
setup_cron() {
    SCRIPT_PATH="$(realpath "$0")"
    CRON_FILE="/etc/cron.d/project_monitoring"

    if [ ! -f "$CRON_FILE" ]; then
        cat > "$CRON_FILE" <<EOF
# SYSAD PROJECT monitoring crons
# Daily audit summary at 6:00 AM
0 6 * * * root bash $SCRIPT_PATH --audit-report >> /var/log/project_monitor.log 2>&1
EOF
        chmod 644 "$CRON_FILE"
        log "Monitoring cron registered at $CRON_FILE"
    fi
}

# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────
case "${1:-}" in
    --audit-report)
        send_audit_report
        ;;
    --watch-audit)
        watch_audit_log
        ;;
    --alert)
        broadcast_alert "${2:-SYSAD ALERT: Attention required.}"
        ;;
    --status)
        echo "=== Monitoring Status ==="
        echo "auditd:   $(systemctl is-active auditd 2>/dev/null || echo 'not available')"
        echo "rsyslog:  $(systemctl is-active rsyslog 2>/dev/null || echo 'not available')"
        echo "autofs:   $(systemctl is-active autofs 2>/dev/null || echo 'not available')"
        echo "logwatch: $(command -v logwatch &>/dev/null && echo 'installed' || echo 'not installed')"
        echo ""
        echo "Recent monitor log:"
        tail -20 "$MONITOR_LOG" 2>/dev/null || echo "(no log yet)"
        ;;
    *)
        log "=== Monitoring System Setup Starting ==="
        setup_auditd
        setup_syslog
        setup_logwatch
        setup_cron
        log "=== Monitoring System Setup Complete ==="
        echo ""
        echo "To start real-time audit watching run:"
        echo "  bash monitoring_system.sh --watch-audit"
        echo ""
        echo "To manually broadcast an alert run:"
        echo "  bash monitoring_system.sh --alert 'Your message here'"
        ;;
esac
