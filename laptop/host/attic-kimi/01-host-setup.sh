#!/bin/bash
# 01-host-setup.sh — turn CachyOS laptop into the VM host. Run: sudo bash laptop/host/01-host-setup.sh
# Idempotent-ish. Makes backups next to every file it edits (.bak-YYYYmmdd-HHMMSS).
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root
STAMP=$(date +%Y%m%d-%H%M%S)
say() { echo; echo "== $* =="; }

if [ "$(id -u)" != 0 ]; then echo "run with sudo"; exit 1; fi

say "1/9 packages (qemu, libvirt, ovmf, virt-manager)"
pacman -S --needed --noconfirm qemu-full libvirt edk2-ovmf virt-manager

say "2/9 kernel cmdline: intel_iommu=on iommu=pt (Limine)"
cp /boot/limine.conf "/boot/limine.conf.bak-$STAMP"
sed -i 's/^  cmdline: quiet nowatchdog splash rw /  cmdline: quiet nowatchdog splash intel_iommu=on iommu=pt rw /' /boot/limine.conf
grep -q 'intel_iommu=on' /boot/limine.conf && echo "limine.conf updated"
echo "NOTE: limine-entry-tool regenerates this file on kernel updates - re-check the cmdline after major updates."

say "3/9 vfio-pci claims the GTX 1650 (10de:1f99 VGA + 10de:10fa audio)"
cat > /etc/modprobe.d/vfio-pci.conf <<'EOF'
options vfio-pci ids=10de:1f99,10de:10fa
EOF

say "4/9 blacklist nvidia on the host (dedicated to the Windows VM; revert = delete this file)"
cat > /etc/modprobe.d/blacklist-nvidia-vm.conf <<'EOF'
blacklist nvidia
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nvidia_drm
EOF

say "5/9 initramfs: load vfio_pci early"
cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak-$STAMP"
sed -i 's/^MODULES=()/MODULES=(vfio_pci)/' /etc/mkinitcpio.conf
mkinitcpio -P

say "6/9 libvirtd + default NAT network"
systemctl enable --now libvirtd
virsh net-info default | grep -q 'Active:.*yes' || virsh net-start default
virsh net-autostart default >/dev/null 2>&1 || true
usermod -aG libvirt "$SUDO_USER" || true

say "7/9 DHCP reservations in the default network"
for ent in "52:54:00:aa:bb:61:192.168.122.11:macos" "52:54:00:aa:bb:62:192.168.122.12:win10-gpu"; do
  MAC=${ent%%:*}; REST=${ent#*:}; IP=${REST%%:*}; NAME=${REST#*:}
  virsh net-update default add ip-dhcp-host --xml "<host mac='$MAC' name='$NAME' ip='$IP'/>" --config --live 2>/dev/null \
    && echo "  $NAME -> $IP" || echo "  $NAME reservation already present (or net-update failed - check with: virsh net-dumpxml default)"
done

say "8/9 VM images"
mkdir -p /var/lib/libvirt/images/macos /var/lib/libvirt/images/win10-gpu
cp laptop/vm/macos/opencore-lt.img /var/lib/libvirt/images/macos/opencore-lt.img
if [ ! -f /var/lib/libvirt/images/macos/nvme1-overlay.qcow2 ]; then
  # Copy-on-write overlay over the real Hackintosh disk: the VM never writes to /dev/nvme1n1.
  # A native macOS boot changes the backing disk and INVALIDATES this overlay: delete and recreate it.
  qemu-img create -f qcow2 -b /dev/nvme1n1 -F raw /var/lib/libvirt/images/macos/nvme1-overlay.qcow2
else
  echo "overlay already exists, keeping it"
fi
[ -f /var/lib/libvirt/images/win10-gpu/win10-lt.qcow2 ] || qemu-img create -f qcow2 /var/lib/libvirt/images/win10-gpu/win10-lt.qcow2 250G
if [ ! -f /var/lib/libvirt/images/win10-gpu/virtio-win.iso ]; then
  echo "downloading virtio-win.iso ..."
  curl -fL --retry 2 -o /var/lib/libvirt/images/win10-gpu/virtio-win.iso \
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso \
    || echo "WARN: virtio-win.iso download failed - retry manually, Windows install needs it for the virtio disk"
else
  echo "virtio-win.iso already present"
fi

say "9/9 define VMs"
# Set a VNC password for the consoles (QEMU VNC allows max 8 chars).
if [ -n "${VNC_PASS:-}" ]; then
  if [ "${#VNC_PASS}" -gt 8 ]; then
    echo "ERROR: VNC_PASS is ${#VNC_PASS} chars; QEMU VNC passwords are limited to 8. Re-run with a shorter password."; exit 1
  fi
  sed -i "s/passwd='[^']*'/passwd='${VNC_PASS//\'/}'/" laptop/vm/macos/macos.xml laptop/vm/windows/win10-gpu.xml
  echo "VNC password set from VNC_PASS env"
else
  echo "WARNING: VNC_PASS not set - consoles keep their current password (CHANGE_ME = localhost only)"
fi
virsh define laptop/vm/macos/macos.xml
virsh define laptop/vm/windows/win10-gpu.xml

say "DONE. Next: reboot the laptop, then run: sudo bash laptop/host/02-verify.sh"
echo "On reboot: Limine menu -> CachyOS as usual. NVIDIA stays blacklisted; Linux runs on Intel UHD."
