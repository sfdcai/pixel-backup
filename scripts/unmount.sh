#!/bin/sh -e

################################################################################
# Description: unmounts the block device previously mounted by mount_ext4.sh
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./unmount.sh
################################################################################


. "$(dirname "$0")/common.sh"

require_global_mount_namespace
require_pixel_xl

echo "[pixel-backup] 📟 Pixel 1 XL environment confirmed"

drive_mount_dir=$(drive_mount_point)
internal_binding_dir=$(internal_binding_path)

# Also unmount the legacy Android 10 path if present to avoid leaving stale
# mounts behind when switching devices/OS versions.
legacy_internal_dir="/mnt/runtime/write/emulated/0/$PIXEL_BACKUP_BINDING_NAME"

echo "[pixel-backup] 🔻 unmounting $internal_binding_dir"
unmount_if_mounted "$internal_binding_dir"
echo "[pixel-backup] 🔻 unmounting $legacy_internal_dir"
unmount_if_mounted "$legacy_internal_dir"
echo "[pixel-backup] 🔻 unmounting $drive_mount_dir"
unmount_if_mounted "$drive_mount_dir"

echo "[pixel-backup] ✅ external drive detached from Pixel 1 XL view"
