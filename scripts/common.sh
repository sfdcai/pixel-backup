#!/bin/sh
#
# shellcheck shell=sh

set -e

# Determine the absolute path to the directory containing this script. The
# scripts are usually executed from arbitrary working directories on the phone
# so relative lookups need to be robust.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Allow the user to provide an optional configuration file.  The defaults are
# sane for the original Pixel but power-users can override any of the exported
# variables below by creating a "pixel-backup.conf" file alongside the scripts
# or by pointing PIXEL_BACKUP_CONFIG to a different path.
PIXEL_BACKUP_CONFIG=${PIXEL_BACKUP_CONFIG:-$SCRIPT_DIR/../pixel-backup.conf}
if [ -f "$PIXEL_BACKUP_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$PIXEL_BACKUP_CONFIG"
fi

# Default configuration values.  They can be overridden via the optional config
# file or environment variables when invoking the scripts.
PIXEL_BACKUP_BINDING_NAME=${PIXEL_BACKUP_BINDING_NAME:-the_binding}
PIXEL_BACKUP_DRIVE_MOUNT_DIR=${PIXEL_BACKUP_DRIVE_MOUNT_DIR:-/mnt/pixel_backup_drive}
PIXEL_BACKUP_INTERNAL_MOUNT_POINT=${PIXEL_BACKUP_INTERNAL_MOUNT_POINT:-}
PIXEL_BACKUP_DISABLE_SELINUX=${PIXEL_BACKUP_DISABLE_SELINUX:-1}
PIXEL_BACKUP_MEDIA_SCAN=${PIXEL_BACKUP_MEDIA_SCAN:-1}
PIXEL_BACKUP_SKIP_DEVICE_CHECK=${PIXEL_BACKUP_SKIP_DEVICE_CHECK:-0}
PIXEL_BACKUP_DEBUG=${PIXEL_BACKUP_DEBUG:-0}
PIXEL_BACKUP_DRIVE_SOURCE=${PIXEL_BACKUP_DRIVE_SOURCE:-auto}
PIXEL_BACKUP_BINDING_SOURCE_REASON=""

if [ "$PIXEL_BACKUP_DEBUG" = "1" ]; then
  set -x
fi

log() {
  printf '[pixel-backup] %s\n' "$*" >&2
}

log_warn() {
  printf '[pixel-backup][warn] %s\n' "$*" >&2
}

log_debug() {
  if [ "$PIXEL_BACKUP_DEBUG" = "1" ]; then
    printf '[pixel-backup][debug] %s\n' "$*" >&2
  fi
}

require_global_mount_namespace() {
  if [ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]; then
    log "not running in global mount namespace, try elevating first"
    exit 1
  fi
}

ensure_directory() {
  mkdir -p "$1"
}

detect_android_version() {
  if [ -n "$PIXEL_BACKUP_ANDROID_VERSION" ]; then
    printf '%s\n' "$PIXEL_BACKUP_ANDROID_VERSION"
    return
  fi

  if command -v getprop >/dev/null 2>&1; then
    PIXEL_BACKUP_ANDROID_VERSION=$(getprop ro.build.version.release 2>/dev/null | awk -F'.' 'NF {print $1}' | tr -dc '0-9')
  fi

  if [ -z "$PIXEL_BACKUP_ANDROID_VERSION" ]; then
    PIXEL_BACKUP_ANDROID_VERSION=10
  fi

  printf '%s\n' "$PIXEL_BACKUP_ANDROID_VERSION"
}

internal_mount_root() {
  if [ -n "$PIXEL_BACKUP_INTERNAL_MOUNT_POINT" ]; then
    printf '%s\n' "$PIXEL_BACKUP_INTERNAL_MOUNT_POINT"
    return
  fi

  android_version=$(detect_android_version)
  log_debug "detected android version: $android_version"
  printf '%s\n' "/mnt/runtime/write/emulated/0"
}

drive_mount_point() {
  printf '%s\n' "$PIXEL_BACKUP_DRIVE_MOUNT_DIR"
}

resolve_drive_binding_source() {
  mount_root=$1
  binding_dir="$mount_root/$PIXEL_BACKUP_BINDING_NAME"

  case "$PIXEL_BACKUP_DRIVE_SOURCE" in
    root)
      PIXEL_BACKUP_BINDING_SOURCE_REASON="root"
      printf '%s\n' "$mount_root"
      ;;
    subdir)
      PIXEL_BACKUP_BINDING_SOURCE_REASON="subdir"
      printf '%s\n' "$binding_dir"
      ;;
    auto|*)
      if [ -d "$binding_dir" ]; then
        PIXEL_BACKUP_BINDING_SOURCE_REASON="auto-subdir"
        printf '%s\n' "$binding_dir"
      else
        PIXEL_BACKUP_BINDING_SOURCE_REASON="auto-root"
        printf '%s\n' "$mount_root"
      fi
      ;;
  esac
}

drive_binding_path() {
  resolve_drive_binding_source "$(drive_mount_point)"
}

internal_binding_path() {
  printf '%s/%s\n' "$(internal_mount_root)" "$PIXEL_BACKUP_BINDING_NAME"
}

is_path_mounted() {
  awk -v target="$1" '
    $2 == target { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' /proc/mounts
}

unmount_if_mounted() {
  if is_path_mounted "$1"; then
    umount -v "$1"
  fi
}

ensure_selinux_permissive() {
  if [ "$PIXEL_BACKUP_DISABLE_SELINUX" != "1" ]; then
    return
  fi

  if command -v getenforce >/dev/null 2>&1 && command -v setenforce >/dev/null 2>&1; then
    current_state=$(getenforce 2>/dev/null || true)
    if [ "$current_state" = "Enforcing" ]; then
      log "SELinux enforcing detected, attempting to switch to Permissive"
      if ! setenforce 0 2>/dev/null; then
        log_warn "failed to switch SELinux to permissive mode"
      fi
    fi
  fi
}

maybe_run_media_scan() {
  if [ "$PIXEL_BACKUP_MEDIA_SCAN" != "1" ]; then
    log_debug "media scan disabled via configuration"
    return
  fi

  trigger_media_scan
}

trigger_media_scan() {
  target_uri="file:///storage/emulated/0/$PIXEL_BACKUP_BINDING_NAME/"
  target_path="/storage/emulated/0/$PIXEL_BACKUP_BINDING_NAME"

  log "requesting media scan for $target_uri"

  scan_success=0

  if command -v am >/dev/null 2>&1; then
    if am broadcast \
      -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "$target_uri" >/dev/null 2>&1; then
      log_debug "media scanner broadcast succeeded"
      scan_success=1
    else
      log_warn "media scanner broadcast failed"
    fi
  else
    log_warn "am command not available; skipping broadcast path"
  fi

  if command -v cmd >/dev/null 2>&1; then
    if cmd activity call content://media/external/file \
      --user 0 \
      scanFile \
      "$target_uri" >/dev/null 2>&1; then
      log_debug "media provider scan via cmd activity succeeded"
      scan_success=1
    else
      log_debug "cmd activity scanFile call did not succeed"
    fi
  else
    log_debug "cmd binary not available; skipping activity call path"
  fi

  if command -v content >/dev/null 2>&1; then
    if content call \
      --uri content://media/external/file \
      --user 0 \
      --method scanFile \
      --arg "$target_path" >/dev/null 2>&1; then
      log_debug "media provider scan via content cli succeeded"
      scan_success=1
    else
      log_debug "content cli scanFile call did not succeed"
    fi
  else
    log_debug "content command not available; skipping direct provider call"
  fi

  if [ "$scan_success" -ne 1 ]; then
    log_warn "none of the media scan attempts reported success; Google Photos may need a manual refresh"
  fi
}

require_pixel_xl() {
  if [ "$PIXEL_BACKUP_SKIP_DEVICE_CHECK" = "1" ]; then
    log_warn "skipping Pixel XL device check (override enabled)"
    return
  fi

  if ! command -v getprop >/dev/null 2>&1; then
    log_warn "getprop not available; unable to verify device is Pixel 1 XL"
    return
  fi

  device_codename=$(getprop ro.product.device 2>/dev/null | tr '[:upper:]' '[:lower:]')
  device_model=$(getprop ro.product.model 2>/dev/null)

  if [ "$device_codename" = "marlin" ]; then
    log_debug "device check passed for Pixel 1 XL (marlin)"
    return
  fi

  if [ "$device_model" = "Pixel XL" ]; then
    log_debug "device check passed via model name"
    return
  fi

  log "this script set is tailored for the Pixel 1 XL (codename marlin). detected device='$device_codename', model='$device_model'"
  log "set PIXEL_BACKUP_SKIP_DEVICE_CHECK=1 to bypass if you really know what you're doing"
  exit 1
}
