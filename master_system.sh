#!/bin/bash
# Master Controller 

set -euo pipefail

# Define Paths
BASE_DIR="/home/leroy/Downloads/sysad1"
SOURCE_DIR="$BASE_DIR/source_data"
MOUNT_POINT="/mnt/auto_mounts/backup_source"

# 1. Force Root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo bash master_system.sh"
    exit 1
fi

clear
echo "--- Initializing SysAd Security Gate ---"

# 2. Run Security System
if ! bash "$BASE_DIR/security_system.sh"; then
    echo "Authentication Failed. Exiting."
    exit 1
fi

echo "--- Setting up Infrastructure ---"

# 3. Setup Mounting
mkdir -p "$SOURCE_DIR"

bash "$BASE_DIR/auto_mounting.sh" fstab "$SOURCE_DIR" "$MOUNT_POINT" || true

# Activate the mount
mount -a || echo "Note: Mount already active."

echo "--- Starting Real-Time Watchman ---"for SysAd1 Framework

# 4. Launch Monitor
bash "$BASE_DIR/system_monitor.sh"
