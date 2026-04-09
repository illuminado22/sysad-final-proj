#!/bin/bash

set -euo pipefail

# Variables
source_data="/home/leroy/Downloads/sysad1/source_data"
backup_root="/home/leroy/Downloads/sysad1/backups"
today=$(date +%Y-%m-%d)
target_dir="$backup_root/$today"

# 1. Ensure the backup destination exists
mkdir -p "$target_dir"

# 2. Copy files from source to the daily folder
cp -rp "$source_data"/* "$target_dir/"

# 3. Compress the daily folder into a .tar.gz archive
tar -czf "$backup_root/${today}.tar.gz" -C "$backup_root" "$today"

# 4. Clean up the uncompressed daily folder to save disk space
rm -rf "$target_dir"

exit 0
