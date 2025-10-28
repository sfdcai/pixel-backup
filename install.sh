#!/system/bin/sh
#
# pixel-backup one-line installer for the Google Pixel 1 XL (marlin)
#
# Usage (on device, as root):
#   curl -Ls https://raw.githubusercontent.com/sfdcai/pixel-backup/refs/heads/main/install.sh | sh
#
# Optional environment variables:
#   PIXEL_BACKUP_INSTALL_DIR   Override the installation directory
#                              (default: /data/local/tmp/pixel-backup)
#   PIXEL_BACKUP_TARBALL_URL   Override the tarball URL if you want to pin a
#                              specific release or mirror
#   PIXEL_BACKUP_BRANCH        Git ref to download when using the default
#                              tarball URL (default: main)
#
set -eu

INSTALL_DIR=${PIXEL_BACKUP_INSTALL_DIR:-/data/local/tmp/pixel-backup}
BRANCH=${PIXEL_BACKUP_BRANCH:-main}
DEFAULT_TARBALL_URL="https://codeload.github.com/sfdcai/pixel-backup/tar.gz/refs/heads/$BRANCH"
TARBALL_URL=${PIXEL_BACKUP_TARBALL_URL:-$DEFAULT_TARBALL_URL}
TMPDIR=${TMPDIR:-/data/local/tmp}
FETCH_TOOL=""
AUTO_INSTALL_MAGISK=0
SKIP_DEVICE_CHECK=${PIXEL_BACKUP_SKIP_DEVICE_CHECK:-0}

log() {
  printf '[pixel-backup] %s\n' "$1"
}

die() {
  log "ERROR: $1" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    die "run this installer via su (root)"
  fi
}

verify_device() {
  if [ "$SKIP_DEVICE_CHECK" = "1" ]; then
    log "Device guard disabled via PIXEL_BACKUP_SKIP_DEVICE_CHECK"
    return
  fi

  if ! command -v getprop >/dev/null 2>&1; then
    die "getprop is unavailable; run this installer from an Android shell"
  fi

  DEVICE="$(getprop ro.product.device 2>/dev/null || true)"
  MODEL="$(getprop ro.product.model 2>/dev/null || true)"
  case "$DEVICE" in
    marlin|marlin_sprout)
      return 0
      ;;
    *)
      die "device '$DEVICE' ($MODEL) is not a Pixel 1 XL; aborting"
      ;;
  esac
}

select_fetch_tool() {
  if command -v curl >/dev/null 2>&1; then
    FETCH_TOOL="curl"
  elif command -v wget >/dev/null 2>&1; then
    FETCH_TOOL="wget"
  else
    die "neither curl nor wget is available; install curl first"
  fi
}

require_tar() {
  if ! command -v tar >/dev/null 2>&1; then
    die "tar is required to unpack the toolkit"
  fi
}

cleanup() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

trap cleanup EXIT INT TERM

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --install-magisk)
        AUTO_INSTALL_MAGISK=1
        ;;
      --no-magisk)
        AUTO_INSTALL_MAGISK=0
        ;;
      --help|-h)
        cat <<'USAGE'
Pixel Backup one-line installer

Options:
  --install-magisk   Automatically run scripts/install_magisk_module.sh after
                     copying the toolkit (requires Magisk)
  --no-magisk        Explicitly skip the Magisk module installation step
  -h, --help         Show this help message

Environment variables:
  PIXEL_BACKUP_INSTALL_DIR   Install location (default /data/local/tmp/pixel-backup)
  PIXEL_BACKUP_BRANCH        Branch/ref to download (default main)
  PIXEL_BACKUP_TARBALL_URL   Override tarball URL entirely
USAGE
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done
}

create_workdir() {
  if command -v mktemp >/dev/null 2>&1; then
    WORK_DIR=$(mktemp -d "$TMPDIR/pixel-backup.XXXXXX")
  else
    WORK_DIR="$TMPDIR/pixel-backup.$$.$RANDOM"
    mkdir -p "$WORK_DIR"
  fi
  ARCHIVE_PATH="$WORK_DIR/pixel-backup.tar.gz"
}

download_repo() {
  log "Downloading pixel-backup from $TARBALL_URL"
  case "$FETCH_TOOL" in
    curl)
      curl -LfsSo "$ARCHIVE_PATH" "$TARBALL_URL" || die "failed to download repository"
      ;;
    wget)
      wget -qO "$ARCHIVE_PATH" "$TARBALL_URL" || die "failed to download repository"
      ;;
    *)
      die "internal error: fetch tool not selected"
      ;;
  esac
}

unpack_repo() {
  EXTRACT_DIR="$WORK_DIR/source"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR" || die "failed to unpack repository"
  SOURCE_DIR=$(ls -1 "$EXTRACT_DIR" | head -n 1)
  if [ -z "$SOURCE_DIR" ]; then
    die "unexpected tarball structure"
  fi
  SOURCE_PATH="$EXTRACT_DIR/$SOURCE_DIR"
}

stage_installation() {
  log "Installing toolkit to $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  (cd "$SOURCE_PATH" && tar -cf - .) | (cd "$INSTALL_DIR" && tar -xf -)
  chmod 0755 "$INSTALL_DIR"/*.sh 2>/dev/null || true
  if [ -d "$INSTALL_DIR/scripts" ]; then
    find "$INSTALL_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
  fi
  if [ -d "$INSTALL_DIR/magisk/system/bin" ]; then
    chmod 0755 "$INSTALL_DIR/magisk/system/bin"/* 2>/dev/null || true
  fi
}

maybe_install_magisk_module() {
  if [ "$AUTO_INSTALL_MAGISK" != "1" ]; then
    log "Skipping Magisk module installation (pass --install-magisk to enable)"
    return
  fi

  if [ ! -d /data/adb ]; then
    log "Magisk not detected; skipping module installation"
    return
  fi

  if [ ! -x "$INSTALL_DIR/scripts/install_magisk_module.sh" ]; then
    log "Magisk installer script missing or not executable"
    return
  fi

  log "Running Magisk module installer"
  (cd "$INSTALL_DIR/scripts" && ./install_magisk_module.sh) || die "Magisk module installation failed"
}

main() {
  parse_args "$@"
  require_root
  verify_device
  select_fetch_tool
  require_tar
  create_workdir
  download_repo
  unpack_repo
  stage_installation
  maybe_install_magisk_module
  log "Install complete. Scripts are available in $INSTALL_DIR/scripts"
  log "Use $INSTALL_DIR/scripts/start_global_shell.sh to enter the global namespace"
}

main "$@"
