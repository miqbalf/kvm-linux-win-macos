#!/bin/bash
# Run in CachyOS (VM or native) with sudo. Protects /boot (FAT ESP, shared with macOS VMware use):
#  - /boot mounted only on access, unmounted after 60 s idle (a paused/suspended VM rarely holds it open)
#  - macOS junk removed, Spotlight/fseventsd told to never write there
#  - idle sleep blocked while running as a VMware guest
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo bash "$0" "$@"
snapper -c root create -d "before /boot automount (cachyos-vm)" 2>/dev/null || true
cp -a /etc/fstab /etc/fstab.bak-$(date +%Y%m%d%H%M)
# add automount options to the /boot line (only once)
if ! grep -qE '^\S+\s+/boot\s+vfat\s+\S*x-systemd.automount' /etc/fstab; then
    sed -i -E 's#^(\S+\s+/boot\s+vfat\s+)(\S+)#\1\2,noauto,x-systemd.automount,x-systemd.idle-timeout=60#' /etc/fstab
fi
grep -E '\s/boot\s' /etc/fstab
ls /boot >/dev/null    # make sure it is mounted for the cleanup
rm -rf /boot/.Spotlight-V100 /boot/.fseventsd /boot/.Trashes /boot/.TemporaryItems
find /boot -name '._*' -delete
touch /boot/.metadata_never_index
mkdir -p /boot/.fseventsd && touch /boot/.fseventsd/no_log
install -m 644 "$(dirname "$0")/cachyos-vm-noidle.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cachyos-vm-noidle.service || true
sync; umount /boot 2>/dev/null || true
systemctl restart boot.automount
systemctl is-active boot.automount cachyos-vm-noidle.service || true
echo "kernel files:"; ls /boot | grep -E 'vmlinuz|initramfs|limine' | head
