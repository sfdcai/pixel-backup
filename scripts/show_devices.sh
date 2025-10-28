#!/bin/sh -e

################################################################################
# Description: show all block devices present in the system
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./show_devices.sh
################################################################################

blkid -o list || blkid
