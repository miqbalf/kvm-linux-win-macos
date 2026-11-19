#!/bin/bash
# 00-inspect.sh — READ-ONLY inventory of the CachyOS host. Run: sudo bash laptop/host/00-inspect.sh
# Makes no changes. Output is printed for capture.
set -u
hr() { echo; echo "===== $* ====="; }

hr "boot loader config (/boot/limine.conf)"
cat /boot/limine.conf 2>/dev/null || ls /boot/*.conf /boot/limine* 2>/dev/null || echo "no limine.conf found"

hr "boot partition"
findmnt /boot

hr "mkinitcpio MODULES"
grep -E '^MODULES' /etc/mkinitcpio.conf
ls /etc/mkinitcpio.d/

hr "mkinitcpio presets (cachyos)"
cat /etc/mkinitcpio.d/*cachyos* 2>/dev/null

hr "virt packages installed"
pacman -Q 2>/dev/null | grep -Ei 'libvirt|qemu|edk2|ovmf|virt-manager|dnsmasq|iptables|nftables|firewalld|swtpm|mtools' || echo "none of the virt stack installed yet"

hr "nvidia packages"
pacman -Q 2>/dev/null | grep -Ei 'nvidia|open-gpu|nouveau' || echo none

hr "edk2 ovmf files"
ls -la /usr/share/edk2/x64/ 2>/dev/null || echo "edk2 not installed yet"

hr "lspci tree"
lspci -tv

hr "firewall / network"
systemctl is-active firewalld nftables iptables 2>/dev/null
ip -brief addr

hr "tailscale"
command -v tailscale && tailscale status 2>&1 | head -3 || echo "tailscale not installed"

hr "iommu in dmesg (expected: off for now)"
dmesg 2>/dev/null | grep -iE 'iommu|DMAR' | head -5 || echo "dmesg unreadable or no iommu lines"

hr "efi entries"
efibootmgr 2>/dev/null

hr "disk space /var/lib"
df -h /var/lib/libvirt /var/lib 2>/dev/null

hr "sudo-less check done"
echo "OK - no changes made"
