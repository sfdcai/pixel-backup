#!/system/bin/sh
MODDIR="${0%/*}"
LINK_PATH="/data/local/tmp/pixel-backup"
if [ -L "$LINK_PATH" ] && [ "$(readlink "$LINK_PATH")" = "$MODDIR/scripts" ]; then
  rm -f "$LINK_PATH"
fi
