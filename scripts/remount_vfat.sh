#!/bin/sh -e

################################################################################
# Description: remounts /the_binding in the specified mounted vfat folder to the internal storage
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./remount_vfat.sh <DIRECTORY_PATH>
# Example: ./remount_vfat.sh /mnt/media_rw/2IDK-11F4
################################################################################

. "$(dirname "$0")/common.sh"

require_global_mount_namespace
require_pixel_xl

echo "[pixel-backup] 📟 Pixel 1 XL environment confirmed"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /mnt/media_rw/<label>" >&2
  exit 1
fi

mounted_drive_path=$1
echo "[pixel-backup] 🔍 checking mounted directory $mounted_drive_path"
if [ ! -e "$mounted_drive_path" ]; then
  echo "[pixel-backup] ❌ directory '$mounted_drive_path' was not found" >&2
  exit 1
fi
if [ ! -d "$mounted_drive_path" ]; then
  echo "[pixel-backup] ❌ path '$mounted_drive_path' was not a directory" >&2
  exit 1
fi

fs_type=$(stat -f -c %T "$mounted_drive_path" 2>/dev/null || true)
case "$fs_type" in
  msdos|vfat|fuseblk|fuse)
    ;;
  *)
    log_warn "expected a FAT/vfat filesystem but detected '$fs_type'"
    ;;
esac

drive_binding_dir="$mounted_drive_path/$PIXEL_BACKUP_BINDING_NAME"
internal_binding_dir=$(internal_binding_path)

echo "[pixel-backup] 🔗 binding $drive_binding_dir -> $internal_binding_dir"

if is_path_mounted "$internal_binding_dir"; then
  echo "[pixel-backup] ❌ internal mount point '$internal_binding_dir' is already in use" >&2
  exit 1
fi

ensure_directory "$drive_binding_dir"
ensure_directory "$internal_binding_dir"

echo "[pixel-backup] 🔄 exposing drive contents to internal storage"
if mount -t sdcardfs -o nosuid,nodev,noexec,noatime,gid=9997 "$drive_binding_dir" "$internal_binding_dir"; then
  echo "[pixel-backup] ✅ sdcardfs bind established"
else
  log_warn "sdcardfs bind failed, attempting plain bind mount"
  mount -o bind "$drive_binding_dir" "$internal_binding_dir"
  echo "[pixel-backup] ✅ plain bind mount established"
fi

maybe_run_media_scan

echo "[pixel-backup] 🎉 vfat drive remounted successfully for Google Photos"
