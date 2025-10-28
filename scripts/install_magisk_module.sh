#!/system/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
MODULE_ID="pixel-backup"
MODULE_SOURCE="$REPO_ROOT/magisk"
MODULE_STAGE="/data/adb/modules_update/$MODULE_ID"
ENABLED_MARKER="/data/adb/modules/$MODULE_ID"

log() {
  printf '[pixel-backup] %s\n' "$1"
}

die() {
  log "ERROR: $1" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    die "run this installer as root (su)"
  fi
}

verify_device() {
  DEVICE="$(getprop ro.product.device)"
  MODEL="$(getprop ro.product.model)"
  case "$DEVICE" in
    marlin|marlin_sprout)
      return 0
      ;;
    *)
      die "device '$DEVICE' ($MODEL) is not a Pixel 1 XL; aborting"
      ;;
  esac
}

require_magisk() {
  if [ ! -d /data/adb ]; then
    die "Magisk not detected (missing /data/adb). Install Magisk first."
  fi
  mkdir -p /data/adb/modules_update
}

copy_module_files() {
  log "Staging Magisk module at $MODULE_STAGE"
  rm -rf "$MODULE_STAGE"
  mkdir -p "$MODULE_STAGE"

  for file in module.prop service.sh uninstall.sh; do
    if [ ! -f "$MODULE_SOURCE/$file" ]; then
      die "missing template file $file"
    fi
    cp "$MODULE_SOURCE/$file" "$MODULE_STAGE/$file"
    chmod 0644 "$MODULE_STAGE/$file"
  done
  chmod 0755 "$MODULE_STAGE/service.sh" "$MODULE_STAGE/uninstall.sh"

  mkdir -p "$MODULE_STAGE/system/bin"
  cp "$MODULE_SOURCE/system/bin/pixel-backup-shell" "$MODULE_STAGE/system/bin/pixel-backup-shell"
  chmod 0755 "$MODULE_STAGE/system/bin/pixel-backup-shell"

  mkdir -p "$MODULE_STAGE/scripts"
  for script in \
    common.sh \
    disable_tcp_debugging.sh \
    enable_tcp_debugging.sh \
    find_device.sh \
    force_media_scan.sh \
    mount_ext4.sh \
    remount_vfat.sh \
    run_as_termux.sh \
    show_devices.sh \
    start_global_shell.sh \
    unmount.sh
  do
    if [ ! -f "$REPO_ROOT/scripts/$script" ]; then
      die "missing script $script"
    fi
    cp "$REPO_ROOT/scripts/$script" "$MODULE_STAGE/scripts/$script"
    chmod 0755 "$MODULE_STAGE/scripts/$script"
  done

  if [ -f "$REPO_ROOT/pixel-backup.conf" ]; then
    log "Copying local pixel-backup.conf"
    cp "$REPO_ROOT/pixel-backup.conf" "$MODULE_STAGE/scripts/pixel-backup.conf"
    chmod 0644 "$MODULE_STAGE/scripts/pixel-backup.conf"
  fi
}

mark_for_install() {
  echo 1 > "$MODULE_STAGE/update"
  touch "$MODULE_STAGE/auto_mount"
  log "Module staged. Reboot to finalize installation."
  if [ -d "$ENABLED_MARKER" ]; then
    log "Existing module detected at $ENABLED_MARKER; it will be updated on reboot."
  fi
}

main() {
  log "Pixel Backup Magisk module installer starting"
  require_root
  verify_device
  require_magisk
  copy_module_files
  mark_for_install
  log "Done."
}

main "$@"
