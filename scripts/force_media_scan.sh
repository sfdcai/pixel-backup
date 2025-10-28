#!/bin/sh -e

################################################################################
# Description: force a rescan of the mounted media so Google Photos sees files
# Contributors: Pixel Backup Gang
# Usage: ./force_media_scan.sh
################################################################################

. "$(dirname "$0")/common.sh"

require_global_mount_namespace
require_pixel_xl

echo "[pixel-backup] 📡 forcing media index refresh for Pixel 1 XL"

internal_binding_dir=$(internal_binding_path)
drive_binding_dir=$(drive_binding_path)

echo "[pixel-backup] 🔎 checking mount paths"
if [ ! -d "$drive_binding_dir" ]; then
  log_warn "drive binding directory '$drive_binding_dir' not found; make sure the drive is mounted"
fi

if [ ! -d "$internal_binding_dir" ]; then
  log_warn "internal binding directory '$internal_binding_dir' not found; run mount_ext4.sh or remount_vfat.sh first"
fi

trigger_media_scan

echo "[pixel-backup] ✅ media scan requests dispatched; verify results in Google Photos"
