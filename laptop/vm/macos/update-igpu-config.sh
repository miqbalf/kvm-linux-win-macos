#!/bin/bash
# update-igpu-config.sh - regenerate only config.plist inside the existing macos-igpu OpenCore image.
# Use after changing make-vm-config.py; the GOP driver and GOP policy in the image stay as they are
# (a full rebuild needs build-igpu-image.sh, host mode and the GOP file). Run from the repo root:
#   sudo bash laptop/vm/macos/update-igpu-config.sh
# The previous image is kept as opencore-igpu.img.prev-config. Nothing touches the real Hackintosh disk.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
IMG=/var/lib/libvirt/images/macos/opencore-igpu.img
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$IMG" ] || { echo "missing $IMG (build it once with build-igpu-image.sh)"; exit 1; }
virsh -q list --name | grep -qx macos-igpu && { echo "macos-igpu is running: shut it down first"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 "$D/make-vm-config.py" "$D/oc-build/EFI/OC/config.plist.binary-bak" "$T/config.plist" --igpu "$@" | tail -1
cp -f "$IMG" "$IMG.prev-config"
mcopy -o -i "$IMG" "$T/config.plist" ::/EFI/OC/config.plist
mcopy -n -i "$IMG" ::/EFI/OC/config.plist "$T/check.plist"
cmp -s "$T/config.plist" "$T/check.plist" && echo "updated $IMG (previous: $IMG.prev-config)"
python3 -c "
import plistlib,sys; d=plistlib.load(open('$T/check.plist','rb'))
print('SetApfsTrimTimeout', d['Kernel']['Quirks']['SetApfsTrimTimeout'], '| boot-args:', d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']['boot-args'])"
