#!/bin/bash
# Auto Mounting System

set -euo pipefail

# Forcing Root Access
if [ "$EUID" -ne 0 ]; then
    echo "This must be run as root"
    exit 1
fi

# Variables
fstab_file="/etc/fstab"
mount_log="/var/log/auto_mount.log"
auto_mount_dir="/mnt/auto_mounts"
date_format='+%Y-%m-%d %H:%M:%S'

# Create necessary directories
mkdir -p "$auto_mount_dir"
mkdir -p /var/log

# Security Settings
umask 077

#logging activity function
log_activity() {
    local message="$1"
    echo "$(date "$date_format") - $message" >> "$mount_log"
    echo "$message"
}


#fstab for automatic mounting of directory 
setup_fstab_mount() {
    local source_path="$1"
    local mount_point="$2"
    
    if [ ! -d "$source_path" ]; then
        log_activity "ERROR: Source path $source_path does not exist"
        return 1
    fi
    
    mkdir -p "$mount_point"
    
    if grep -q "$mount_point" "$fstab_file" 2>/dev/null; then
        log_activity "WARNING: Mount point $mount_point already exists in fstab"
        return 1
    fi
    
    echo "$source_path $mount_point none bind 0 0" >> "$fstab_file"
    log_activity "Added to fstab: $source_path -> $mount_point"
    echo "Added permanent mount to fstab. Run 'mount -a' to activate."
    return 0
}


#manual mount function
manual_mount() {
    local source_path="$1"
    local mount_point="$2"
    
    if [ ! -d "$source_path" ]; then
        log_activity "ERROR: Source path $source_path does not exist"
        return 1
    fi
    
    mkdir -p "$mount_point"
    
    if mountpoint -q "$mount_point"; then
        log_activity "WARNING: $mount_point is already mounted"
        return 1
    fi
    
    mount --bind "$source_path" "$mount_point"
    log_activity "Manually mounted: $source_path -> $mount_point"
    echo "Successfully mounted $source_path to $mount_point"
    return 0
}


#manual unmount function 
manual_unmount() {
    local mount_point="$1"
    
    if ! mountpoint -q "$mount_point"; then
        log_activity "WARNING: $mount_point is not currently mounted"
        return 1
    fi
    
    if umount "$mount_point"; then
        log_activity "Manually unmounted: $mount_point"
        echo "Successfully unmounted $mount_point"
        return 0
    else
        log_activity "ERROR: Failed to unmount $mount_point (may be in use)"
        echo "Error: Failed to unmount (directory may be in use)"
        return 1
    fi
}

#creating the directory
create_mount_folder() {
    local folder_path="$1"
    local parent_path="${2:-$auto_mount_dir}"
    
    mkdir -p "$parent_path/$folder_path"
    log_activity "Created mount folder: $parent_path/$folder_path at $(date "$date_format")"
    echo "Created folder: $parent_path/$folder_path"
    return 0
}

#control ownership and permission
set_mount_permissions() {
    local mount_point="$1"
    local owner="$2"
    local permissions="$3"
    
    if [ ! -d "$mount_point" ]; then
        log_activity "ERROR: Mount point $mount_point does not exist"
        return 1
    fi
    
    if chown "$owner" "$mount_point"; then
        log_activity "Changed ownership of $mount_point to $owner"
    else
        log_activity "ERROR: Failed to change ownership of $mount_point"
        return 1
    fi
    
    if chmod "$permissions" "$mount_point"; then
        log_activity "Changed permissions of $mount_point to $permissions"
        echo "Permissions updated: $mount_point (owner: $owner, perms: $permissions)"
        return 0
    else
        log_activity "ERROR: Failed to set permissions on $mount_point"
        return 1
    fi
}


#ACL permission 
set_acl_permissions() {
    local mount_point="$1"
    local user="$2"
    local acl_perms="$3"
    
    if ! command -v setfacl &> /dev/null; then
        log_activity "ERROR: setfacl tool not available"
        return 1
    fi
    
    if [ ! -d "$mount_point" ]; then
        log_activity "ERROR: Mount point $mount_point does not exist"
        return 1
    fi
    
    if setfacl -m "u:$user:$acl_perms" "$mount_point"; then
        log_activity "Set ACL for user $user on $mount_point: $acl_perms"
        echo "ACL permissions set for $user on $mount_point"
        return 0
    else
        log_activity "ERROR: Failed to set ACL permissions on $mount_point"
        return 1
    fi
}


#view ACL permission 
get_acl_permissions() {
    local mount_point="$1"
    
    if ! command -v getfacl &> /dev/null; then
        log_activity "ERROR: getfacl tool not available"
        return 1
    fi
    
    if [ ! -d "$mount_point" ]; then
        log_activity "ERROR: Mount point $mount_point does not exist"
        return 1
    fi
    
    echo "ACL Permissions for $mount_point"
    getfacl "$mount_point"
    log_activity "Viewed ACL for $mount_point"
    return 0
}


#init
log_activity "Auto Mounting System initialized"

#user choice
main() {
    local command="$1"
    
    case "$command" in
        fstab)
            if [ $# -lt 3 ]; then
                echo "Usage: $0 fstab <source_path> <mount_point>"
                return 1
            fi
            setup_fstab_mount "$2" "$3"
            ;;
        mount)
            if [ $# -lt 3 ]; then
                echo "Usage: $0 mount <source_path> <mount_point>"
                return 1
            fi
            manual_mount "$2" "$3"
            ;;
        unmount)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 unmount <mount_point>"
                return 1
            fi
            manual_unmount "$2"
            ;;
        mkdir)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 mkdir <folder_path> [parent_path]"
                return 1
            fi
            create_mount_folder "$2" "${3:-}"
            ;;
        chmod)
            if [ $# -lt 4 ]; then
                echo "Usage: $0 chmod <mount_point> <owner> <permissions>"
                return 1
            fi
            set_mount_permissions "$2" "$3" "$4"
            ;;
        setacl)
            if [ $# -lt 4 ]; then
                echo "Usage: $0 setacl <mount_point> <user> <acl_perms>"
                return 1
            fi
            set_acl_permissions "$2" "$3" "$4"
            ;;
        getacl)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 getacl <mount_point>"
                return 1
            fi
            get_acl_permissions "$2"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
