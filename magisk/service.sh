#!/system/bin/sh
# Ensure the Pixel Backup scripts remain accessible from /data/local/tmp/pixel-backup
# so Google Photos and manual shells can reuse the same tooling.
MODDIR="${0%/*}"
SCRIPTS_DIR="$MODDIR/scripts"
TARGET_DIR="/data/local/tmp"
LINK_PATH="$TARGET_DIR/pixel-backup"
LOG_TAG="PixelBackup"

log_print() {
  if command -v log >/dev/null 2>&1; then
    log -p i -t "$LOG_TAG" "$1"
  else
    printf '%s\n' "$1"
  fi
}

wait_for_target() {
  local tries=0
  while [ $tries -lt 30 ]; do
    if [ -d "$TARGET_DIR" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  mkdir -p "$TARGET_DIR"
}

wait_for_target
if [ ! -d "$SCRIPTS_DIR" ]; then
  log_print "Pixel Backup scripts missing from $SCRIPTS_DIR; skipping link"
  exit 0
fi

rm -rf "$LINK_PATH"
ln -s "$SCRIPTS_DIR" "$LINK_PATH"
chmod 0755 "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
log_print "Pixel Backup scripts available at $LINK_PATH"
