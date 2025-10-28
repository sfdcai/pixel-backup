#!/bin/sh -e

################################################################################
# Description: mounts the specified ext4 block device to /the_binding
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./mount_ext4.sh <BLOCK_DEVICE_PATH>
################################################################################

. "$(dirname "$0")/common.sh"

require_global_mount_namespace
require_pixel_xl

echo "[pixel-backup] 📟 Pixel 1 XL environment confirmed"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /dev/block/<label> e.g. $0 /dev/block/sdg1" >&2
  exit 1
fi

ext4_blockdev_path=$1

echo "[pixel-backup] 🔍 checking block device at $ext4_blockdev_path"

if [ ! -e "$ext4_blockdev_path" ]; then
  echo "[pixel-backup] ❌ block device '$ext4_blockdev_path' was not found" >&2
  exit 1
fi

file_type=$(stat -c %F "$ext4_blockdev_path" 2>/dev/null || true)
if [ "$file_type" != "block special file" ]; then
  echo "[pixel-backup] ❌ expected a block device, but '$ext4_blockdev_path' is '$file_type'" >&2
  exit 1
fi

drive_mount_dir=$(drive_mount_point)
drive_binding_dir=$(drive_binding_path)
internal_binding_dir=$(internal_binding_path)

echo "[pixel-backup] 📁 mounting $ext4_blockdev_path -> $drive_mount_dir"
echo "[pixel-backup] 🔗 binding target inside internal storage: $internal_binding_dir"

if is_path_mounted "$drive_mount_dir"; then
  echo "[pixel-backup] ❌ mount point '$drive_mount_dir' is already in use" >&2
  exit 1
fi

if is_path_mounted "$internal_binding_dir"; then
  echo "[pixel-backup] ❌ internal mount point '$internal_binding_dir' is already in use" >&2
  exit 1
fi

ensure_directory "$drive_mount_dir"
ensure_directory "$drive_binding_dir"

cleanup_on_failure() {
  status=$?
  if [ $status -ne 0 ]; then
    log_warn "mount_ext4.sh failed with status $status, cleaning up"
    unmount_if_mounted "$internal_binding_dir"
    unmount_if_mounted "$drive_mount_dir"
  fi
  exit $status
}

trap cleanup_on_failure EXIT

echo "[pixel-backup] 🧰 mounting ext4 filesystem with read/write permissions"
mount -t ext4 -o nosuid,nodev,noexec,noatime "$ext4_blockdev_path" "$drive_mount_dir"

echo "[pixel-backup] 🛡️ applying permissive permissions for shared storage"
chmod -R 0777 "$drive_binding_dir"
chown -R sdcard_rw:sdcard_rw "$drive_mount_dir" 2>/dev/null || true

echo "[pixel-backup] 🔐 evaluating selinux state"
ensure_selinux_permissive

echo "[pixel-backup] 🧱 ensuring binding directories exist"
ensure_directory "$internal_binding_dir"

echo "[pixel-backup] 🔄 exposing drive contents to internal storage"
if mount -t sdcardfs -o nosuid,nodev,noexec,noatime,gid=9997 "$drive_binding_dir" "$internal_binding_dir"; then
  echo "[pixel-backup] ✅ sdcardfs bind established"
else
  log_warn "sdcardfs bind failed, attempting plain bind mount"
  mount -o bind "$drive_binding_dir" "$internal_binding_dir"
  echo "[pixel-backup] ✅ plain bind mount established"
fi

trap - EXIT

maybe_run_media_scan

echo "[pixel-backup] 🎉 ext4 drive mounted successfully for Google Photos"
