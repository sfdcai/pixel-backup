#!/bin/sh -e

################################################################################
# Description: find the path of the block device with the specified UUID
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./find_device.sh <UUID_FILE_PATH>
################################################################################

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <UUID_FILE_PATH>" >&2
  exit 1
fi

uuid_file=$1
if [ ! -r "$uuid_file" ]; then
  echo "unable to read UUID from '$uuid_file'" >&2
  exit 1
fi

uuid=$(tr -d '\n' <"$uuid_file")
if [ -z "$uuid" ]; then
  echo "file '$uuid_file' does not contain a UUID" >&2
  exit 1
fi

device_path=$(blkid -t UUID="$uuid" -o device | head -n 1)

if [ -z "$device_path" ]; then
  echo "no block device found with UUID '$uuid'" >&2
  exit 1
fi

printf '%s\n' "$device_path"
