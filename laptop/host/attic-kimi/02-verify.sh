#!/bin/bash
# 02-verify.sh — run AFTER reboot. Run: sudo bash laptop/host/02-verify.sh
set -u
ok=0; bad=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "  OK   $1"; ok=$((ok+1)); else echo "  FAIL $1"; bad=$((bad+1)); fi }

echo "== IOMMU enabled =="
chk "intel_iommu=on in cmdline"        "grep -q 'intel_iommu=on' /proc/cmdline"
chk "iommu groups exist"               "ls -A /sys/kernel/iommu_groups 2>/dev/null | grep -q ."

echo "== GTX 1650 on vfio-pci =="
chk "01:00.0 driver is vfio-pci"       "[ \"\$(lspci -ks 01:00.0 | grep -oP 'Kernel driver in use: \\K.*')\" = vfio-pci ]"
chk "01:00.1 driver is vfio-pci"       "[ \"\$(lspci -ks 01:00.1 | grep -oP 'Kernel driver in use: \\K.*')\" = vfio-pci ]"
chk "nvidia module not loaded"         "! lsmod | grep -q '^nvidia'"

echo "== IOMMU groups of interest =="
for d in 0000:01:00.0 0000:01:00.1; do
  g=$(readlink /sys/bus/pci/devices/$d/iommu_group 2>/dev/null | xargs -r basename)
  echo "  $d -> group $g"
done
echo "  full group listing:"
for g in /sys/kernel/iommu_groups/*; do
  echo "    group $(basename $g): $(ls $g/devices 2>/dev/null | tr '\n' ' ')"
done

echo "== host still on Intel graphics =="
chk "i915 loaded"                      "lsmod | grep -q '^i915'"
chk "internal panel driven by i915"    "ls /sys/class/drm 2>/dev/null | grep -q eDP"
chk "vfio_pci in initramfs (cachyos)"  "lsinitcpio -m /boot/initramfs-linux-cachyos.img 2>/dev/null | grep -qx vfio_pci"

echo "== libvirt =="
chk "libvirtd active"                  "systemctl is-active --quiet libvirtd"
chk "default network active"           "virsh net-info default | grep -q 'Active:.*yes'"
echo
virsh list --all
echo
echo "result: $ok ok, $bad failed"
[ $bad -eq 0 ] && echo "ALL GOOD - ready for: virsh start macos (VNC 127.0.0.1:5902)"
