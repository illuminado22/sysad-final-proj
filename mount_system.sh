#!/bin/bash
# Mount System
# Handles persistent mounting of the backup directory
# and proper permission setup for the shared workspace.
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
MOUNT_POINT="/mnt/project_backup"
BIND_TARGET="$BACKUP_DIR"
FSTAB_FILE="/etc/fstab"
AUTOFS_MASTER="/etc/auto.master"
AUTOFS_MAP="/etc/auto.project"
ADMIN_USER="ace"
SHARED_GROUP="sysad_users"
LOG_FILE="/var/log/project_mount.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────
# 1. Create required directories
# ─────────────────────────────────────────────
setup_directories() {
    log "Setting up directories..."
    mkdir -p "$BACKUP_DIR" "$SOURCE_DIR" "$SHARED_DIR" "$MOUNT_POINT"
    log "Directories ready: $BACKUP_DIR, $SOURCE_DIR, $SHARED_DIR, $MOUNT_POINT"
}

# ─────────────────────────────────────────────
# 2. Set ownership and permissions
#    chmod  — control read/write/execute bits
#    chown  — assign owner and group
#    setfacl — fine-grained per-user ACL on shared dir
# ─────────────────────────────────────────────
setup_permissions() {
    log "Applying permissions..."

    # Create shared group if it doesn't exist
    if ! getent group "$SHARED_GROUP" &>/dev/null; then
        groupadd "$SHARED_GROUP"
        log "Group '$SHARED_GROUP' created."
    fi

    # Add admin user to the shared group
    usermod -aG "$SHARED_GROUP" "$ADMIN_USER" 2>/dev/null || true

    # --- Backup directory: root-owned, group-readable, no world access ---
    chown -R root:"$SHARED_GROUP" "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR"

    # --- Source data: admin-owned, group can read/write ---
    chown -R "$ADMIN_USER":"$SHARED_GROUP" "$SOURCE_DIR"
    chmod 770 "$SOURCE_DIR"

    # --- Shared workspace: group-writable, setgid bit so new files inherit group ---
    chown -R "$ADMIN_USER":"$SHARED_GROUP" "$SHARED_DIR"
    chmod 2775 "$SHARED_DIR"    # setgid (2) + rwxrwxr-x

    # --- Mount point: root-owned, accessible ---
    chown root:root "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"

    # --- setfacl: give shared group rwx on shared dir, default ACL for new files ---
    if command -v setfacl &>/dev/null; then
        setfacl -m g:"$SHARED_GROUP":rwx "$SHARED_DIR"
        setfacl -m g:"$SHARED_GROUP":rwx "$SOURCE_DIR"
        # Default ACL — inherited by all new files/folders created inside
        setfacl -d -m g:"$SHARED_GROUP":rwx "$SHARED_DIR"
        setfacl -d -m g:"$SHARED_GROUP":rw  "$SOURCE_DIR"
        log "ACL rules applied via setfacl."
    else
        log "WARNING: setfacl not found — install acl package for fine-grained access control."
    fi

    log "Permissions set."
}

# ─────────────────────────────────────────────
# 3. Persistent bind mount via fstab
#    Bind-mounts backup dir to /mnt/project_backup
#    so it is always accessible at a stable path
#    and survives reboots automatically.
# ─────────────────────────────────────────────
setup_fstab() {
    log "Configuring fstab for persistent mount..."
    FSTAB_ENTRY="$BIND_TARGET  $MOUNT_POINT  none  bind,defaults  0  0"

    if grep -qF "$MOUNT_POINT" "$FSTAB_FILE"; then
        log "fstab entry already exists for $MOUNT_POINT — skipping."
    else
        echo "" >> "$FSTAB_FILE"
        echo "# SYSAD PROJECT — backup bind mount (added $(date '+%Y-%m-%d'))" >> "$FSTAB_FILE"
        echo "$FSTAB_ENTRY" >> "$FSTAB_FILE"
        log "fstab entry added: $FSTAB_ENTRY"
    fi

    # Mount now without requiring a reboot
    if mountpoint -q "$MOUNT_POINT"; then
        log "$MOUNT_POINT is already mounted."
    else
        mount --bind "$BIND_TARGET" "$MOUNT_POINT"
        log "$MOUNT_POINT mounted successfully."
    fi
}

# ─────────────────────────────────────────────
# 4. autofs — auto-mount on access, unmount when idle
#    Complements fstab: fstab = always mounted,
#    autofs = mount on demand (for shared network dirs)
# ─────────────────────────────────────────────
setup_autofs() {
    if ! command -v automount &>/dev/null; then
        log "autofs not installed. Install with: apt install autofs"
        return
    fi

    log "Configuring autofs..."

    # Add auto.master entry if not present
    if ! grep -qF "/mnt/auto_project" "$AUTOFS_MASTER"; then
        echo "/mnt/auto_project  $AUTOFS_MAP  --timeout=60" >> "$AUTOFS_MASTER"
        log "auto.master entry added."
    fi

    # Create the autofs map file
    cat > "$AUTOFS_MAP" <<EOF
# SYSAD PROJECT autofs map
# Format: key  options  location
backup  -fstype=none,bind  :$BACKUP_DIR
shared  -fstype=none,bind  :$SHARED_DIR
EOF
    chmod 644 "$AUTOFS_MAP"
    log "autofs map written to $AUTOFS_MAP"

    # Restart autofs to pick up changes
    systemctl restart autofs 2>/dev/null && log "autofs restarted." \
        || log "WARNING: Could not restart autofs. Check systemctl status autofs."
}

# ─────────────────────────────────────────────
# 5. Manual mount / unmount helpers
#    Called with: mount_system.sh --mount
#                 mount_system.sh --unmount
# ─────────────────────────────────────────────
manual_mount() {
    if mountpoint -q "$MOUNT_POINT"; then
        log "$MOUNT_POINT is already mounted."
    else
        mount --bind "$BIND_TARGET" "$MOUNT_POINT"
        log "Manual mount: $BIND_TARGET → $MOUNT_POINT"
    fi
}

manual_unmount() {
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT"
        log "Manual unmount: $MOUNT_POINT"
    else
        log "$MOUNT_POINT is not currently mounted."
    fi
}

# ─────────────────────────────────────────────
# 6. Verify current mount status
# ─────────────────────────────────────────────
show_status() {
    echo ""
    echo "=== Mount Status ==="
    if mountpoint -q "$MOUNT_POINT"; then
        echo "  $MOUNT_POINT  →  MOUNTED"
    else
        echo "  $MOUNT_POINT  →  NOT MOUNTED"
    fi
    echo ""
    echo "=== Permissions ==="
    ls -ld "$BACKUP_DIR" "$SOURCE_DIR" "$SHARED_DIR" "$MOUNT_POINT" 2>/dev/null || true
    echo ""
    echo "=== ACL Rules (source_data & shared) ==="
    if command -v getfacl &>/dev/null; then
        getfacl "$SOURCE_DIR" 2>/dev/null || true
        getfacl "$SHARED_DIR" 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────
case "${1:-}" in
    --mount)
        manual_mount
        ;;
    --unmount)
        manual_unmount
        ;;
    --status)
        show_status
        ;;
    *)
        log "=== Mount System Setup Starting ==="
        setup_directories
        setup_permissions
        setup_fstab
        setup_autofs
        show_status
        log "=== Mount System Setup Complete ==="
        ;;
esac
