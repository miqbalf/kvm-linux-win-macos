#!/bin/bash
# One-time setup on the Hackintosh: VM folder, launcher in /usr/local/bin, and keep macOS from
# auto-mounting the Linux ESP (FAT) of the SN530.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VMDIR="$HOME/Virtual Machines.localized/CachyOS-physical.vmwarevm"
mkdir -p "$VMDIR"
[ -f "$VMDIR/CachyOS-physical.vmx" ] || cp "$HERE/CachyOS-physical.vmx" "$VMDIR/"
sudo install -m 755 "$HERE/cachyos-vm" /usr/local/bin/cachyos-vm
# fstab noauto for the Linux ESP, by volume UUID (survives disk renumbering)
for d in $(diskutil list physical | awk '/^\/dev\/disk/ {print $1}'); do
    if diskutil info "$d" | grep -q "Media Name:.*WDC PC SN530"; then
        U=$(diskutil info "${d}s1" | awk -F': *' '/Volume UUID/ {print $2}')
        if [ -n "$U" ] && ! grep -q "$U" /etc/fstab 2>/dev/null; then
            echo "UUID=$U none msdos rw,noauto" | sudo tee -a /etc/fstab
        fi
    fi
done
echo "Done. Start with: cachyos-vm"
