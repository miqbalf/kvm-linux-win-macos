#!/bin/bash
# 02-verify.sh - health check for the laptop host. Run any time, and after every update or reboot:
#   sudo bash laptop/host/02-verify.sh
# Every FAIL in "host safety" is something that once made the laptop hang or boot to a black screen.
set -u
ok=0; bad=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "  OK   $1"; ok=$((ok+1)); else echo "  FAIL $1"; bad=$((bad+1)); fi }

echo "== host safety (display + boot) =="
chk "no vfio-pci modprobe config"            "[ ! -e /etc/modprobe.d/vfio-pci.conf ]"
chk "nvidia not blacklisted"                 "! grep -rqs '^blacklist nvidia' /etc/modprobe.d"
chk "no vfio in mkinitcpio MODULES"          "! grep -qE '^MODULES=\(.*vfio' /etc/mkinitcpio.conf"
chk "no vfio on kernel cmdline"              "! grep -q vfio /proc/cmdline"
chk "GTX 1650 driven by nvidia"              "[ \"\$(basename \$(readlink /sys/bus/pci/devices/0000:01:00.0/driver))\" = nvidia ]"
chk "Intel UHD driven by i915"               "[ \"\$(basename \$(readlink /sys/bus/pci/devices/0000:00:02.0/driver))\" = i915 ]"
chk "only gdm as display manager"            "systemctl is-enabled gdm && ! systemctl is-enabled ly@tty2"
chk "booted from @ (not a snapshot)"         "grep -q 'rootflags=subvol=/@ ' /proc/cmdline"
chk "no failed systemd units"                "[ -z \"\$(systemctl --failed --no-legend)\" ]"
chk "sshd enabled"                           "systemctl is-enabled sshd"
chk "snapper has an important snapshot"      "snapper -c root list | grep -q important=yes"

echo "== VM host =="
chk "/dev/kvm present"                       "[ -c /dev/kvm ]"
chk "libvirtd active"                        "systemctl is-active libvirtd"
chk "default network active"                 "virsh net-info default | grep -q 'Active:.*yes'"
chk "VM win10 defined"                       "virsh dominfo win10"
chk "VM macos defined"                       "virsh dominfo macos"
chk "sleep-inhibit hook installed"          "cmp -s /etc/libvirt/hooks/qemu laptop/host/libvirt-hooks/qemu"
chk "no VM set to autostart"                 "[ -z \"\$(virsh list --all --autostart --name | grep .)\" ]"
chk "macOS overlay exists"                   "[ -f /var/lib/libvirt/images/macos/nvme1-overlay.qcow2 ]"
chk "/dev/hackintosh-disk is the Samsung 980" "[ \"\$(lsblk -dno MODEL /dev/hackintosh-disk)\" = 'Samsung SSD 980 1TB' ]"
chk "hackintosh-disk is not the host root"   "[ \"\$(readlink -f /dev/hackintosh-disk)\" != /dev/\$(lsblk -no PKNAME \$(findmnt -no SOURCE / | sed 's/\\[.*//')) ]"
chk "overlay backs /dev/hackintosh-disk"     "qemu-img info /var/lib/libvirt/images/macos/nvme1-overlay.qcow2 | grep -q 'backing file: /dev/hackintosh-disk'"
chk "gpu-mode installed and current"         "cmp -s /usr/local/sbin/gpu-mode laptop/host/gpu-mode"
chk "touchpad-bridge installed and current"  "cmp -s /usr/local/sbin/touchpad-bridge laptop/host/touchpad-bridge"
chk "touchpad udev rule installed"           "[ -f /etc/udev/rules.d/62-gpu-mode-touchpad.rules ]"
chk "python-evdev installed"                 "python3 -c 'import evdev'"
chk "opencore-igpu.img has the GOP drivers"  "mdir -i /var/lib/libvirt/images/macos/opencore-igpu.img ::/EFI/OC/Drivers | grep -q INTELG && mdir -i /var/lib/libvirt/images/macos/opencore-igpu.img ::/EFI/OC/Drivers | grep -q PLATFO"
chk "igd-gop.rom present"                    "[ -s /var/lib/libvirt/images/macos/igd-gop.rom ]"
for d in macos macos-igpu; do
  chk "$d: no raw /dev/nvme* in config"     "! virsh dumpxml $d | grep -q '/dev/nvme'"
done

echo; echo "OK=$ok FAIL=$bad"
[ $bad = 0 ]
