#!/bin/bash
# 01-host-setup.sh - make the CachyOS laptop a VM host WITHOUT touching boot or graphics.
# Run: sudo bash laptop/host/01-host-setup.sh      then: sudo bash laptop/host/02-verify.sh
#
# Hard rules (each one broke this laptop before, 2026-11-19):
#  - never edit /boot/limine.conf, /etc/default/limine, /etc/kernel/cmdline or mkinitcpio.conf
#  - never blacklist nvidia, never bind the GTX 1650 (01:00.x) to vfio-pci at boot
#    (only on demand, `gpu-mode win`, while GNOME does not use the GTX)
#  - only one display manager (gdm)
#  - never write to the real Hackintosh disk: the macOS VM uses a qcow2 overlay over /dev/hackintosh-disk
#    (udev name; /dev/nvmeXn1 numbering swaps between boots on this laptop)
# A snapper snapshot is taken first, so any change here can be rolled back from the Limine menu.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root
say() { echo; echo "== $* =="; }
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
USER_NAME=${SUDO_USER:?run with sudo from your own user, not as root}
IMG=/var/lib/libvirt/images

say "0 guard: refuse if a GPU-passthrough boot change is present"
bad=0
for f in /etc/modprobe.d/vfio-pci.conf /etc/modprobe.d/blacklist-nvidia-vm.conf; do
  [ -e "$f" ] && { echo "FOUND $f - remove it first (it blacks out the display)"; bad=1; }
done
grep -qE '^MODULES=\(.*vfio' /etc/mkinitcpio.conf && { echo "FOUND vfio in mkinitcpio MODULES"; bad=1; }
[ $bad = 0 ] || exit 1
echo ok

say "1 snapshot before changes"
snapper -c root create -t single -d "before 01-host-setup" --userdata important=yes && echo "snapshot taken"

say "2 packages"
pacman -S --needed --noconfirm qemu-full libvirt edk2-ovmf virt-manager swtpm dnsmasq \
  python-evdev mtools gnu-efi \
  acpica   # macOS on the panel: touchpad bridge, OpenCore image build; Windows: iasl for the battery SSDT

say "3 libvirt + NAT network (virtual Ethernet for the VMs, works over host Wi-Fi)"
systemctl enable --now libvirtd.socket libvirtd
# (no 'cmd | grep -q' under pipefail: grep exits early, SIGPIPE fails the pipe)
[[ "$(virsh net-info default 2>/dev/null)" =~ Active:[[:space:]]+yes ]] || virsh net-start default
virsh net-autostart default >/dev/null
usermod -aG libvirt "$USER_NAME"
for ent in "52:54:00:aa:bb:61:192.168.122.11:macos" "52:54:00:aa:bb:63:192.168.122.13:win10"; do
  MAC=${ent:0:17}; REST=${ent:18}; IP=${REST%%:*}; NAME=${REST#*:}
  [[ "$(virsh net-dumpxml default)" == *"$MAC"* ]] && { echo "  $NAME reservation present"; continue; }
  virsh net-update default add ip-dhcp-host --xml "<host mac='$MAC' name='$NAME' ip='$IP'/>" --config --live >/dev/null
  echo "  $NAME -> $IP"
done

say "4 firewall: let VM traffic through ufw (default policy denies routed traffic)"
if command -v ufw >/dev/null && [[ "$(ufw status)" == *'Status: active'* ]]; then
  ufw allow in on virbr0 >/dev/null
  ufw route allow in on virbr0 >/dev/null
  ufw route allow out on virbr0 >/dev/null
  echo "ufw: virbr0 allowed"
fi

say "4b libvirt hook: block idle suspend while a VM runs"
install -D -m 755 laptop/host/libvirt-hooks/qemu /etc/libvirt/hooks/qemu
systemctl restart libvirtd
echo "hook installed"

say "4c stable name for the Hackintosh disk"
install -m 644 laptop/host/udev/61-hackintosh-disk.rules /etc/udev/rules.d/61-hackintosh-disk.rules
udevadm control --reload; udevadm trigger --subsystem-match=block --action=change; udevadm settle
HD=$(readlink -f /dev/hackintosh-disk) || true
ROOTDISK=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')")
[ -b "$HD" ] || { echo "ERROR: /dev/hackintosh-disk missing"; exit 1; }
[ "$HD" != "$ROOTDISK" ] || { echo "ERROR: /dev/hackintosh-disk is the host root disk"; exit 1; }
echo "hackintosh disk: $HD (host root: $ROOTDISK)"

say "5 VM images"
mkdir -p "$IMG/macos" "$IMG/win10"
install -m 644 laptop/vm/macos/opencore-lt.img "$IMG/macos/opencore-lt.img"
if [ ! -f "$IMG/macos/nvme1-overlay.qcow2" ]; then
  # Reads the disk only for its size. All VM writes go to the overlay file.
  qemu-img create -f qcow2 -b /dev/hackintosh-disk -F raw "$IMG/macos/nvme1-overlay.qcow2"
else
  echo "macOS overlay exists, kept (recreate it after booting the Hackintosh natively)"
fi
[ -f "$IMG/win10/win10.qcow2" ] || qemu-img create -f qcow2 -o preallocation=metadata "$IMG/win10/win10.qcow2" 200G
if [ ! -f "$IMG/win10/virtio-win.iso" ]; then
  curl -fsSL --retry 2 -o "$IMG/win10/virtio-win.iso" \
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso \
    || echo "WARN: virtio-win.iso download failed, retry later"
fi
[ -f "$IMG/win10/win10-installer.img" ] || echo "TODO: copy the Windows USB stick: dd if=/dev/sdX of=$IMG/win10/win10-installer.img bs=4M"

say "6 VNC password (kept outside the repo)"
PASSFILE=/etc/libvirt/vnc-laptop.pass
if [ ! -s "$PASSFILE" ]; then
  ( umask 077; head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-8 > "$PASSFILE" )
  echo "new VNC password written to $PASSFILE (root only)"
fi
VNC_PASS=$(cat "$PASSFILE")

say "7 define VMs (password substituted in a temp copy, repo files keep CHANGE_ME)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for x in laptop/vm/macos/macos.xml laptop/vm/macos/macos-igpu.xml laptop/vm/windows/win10.xml; do
  sed "s/passwd='[^']*'/passwd='$VNC_PASS'/" "$x" > "$tmp/$(basename "$x")"
  virsh define "$tmp/$(basename "$x")"
done
# win10-gpu: same disk and NVRAM as win10, GTX 1650 passed through on demand (gpu-mode win)
virsh define laptop/vm/windows/win10-gpu.xml

say "8 Windows on the GTX 1650 (Looking Glass window on the Linux desktop)"
iasl -p "$IMG/win10/ssdt-battery" laptop/vm/windows/ssdt-battery.asl >/dev/null && echo "battery SSDT built"
if [ ! -s "$IMG/win10/gtx1650.rom" ] && [ "$(basename "$(readlink /sys/bus/pci/devices/0000:01:00.0/driver)")" = nvidia ]; then
  R=/sys/bus/pci/devices/0000:01:00.0/rom   # the card's own VBIOS; read only
  echo 1 > $R; cat $R > "$IMG/win10/gtx1650.rom"; echo 0 > $R
  echo "GTX VBIOS saved ($(stat -c %s "$IMG/win10/gtx1650.rom") bytes)"
fi
# GNOME must never open the GTX, else it cannot leave the nvidia driver without a logout.
install -m 644 laptop/host/udev/63-gtx-no-gnome.rules /etc/udev/rules.d/63-gtx-no-gnome.rules
install -D -m 644 laptop/host/systemd/org.gnome.Shell@wayland.service.d/10-no-nvidia-egl.conf \
  /etc/systemd/user/org.gnome.Shell@wayland.service.d/10-no-nvidia-egl.conf
sed "s/USER/$USER_NAME/" laptop/host/tmpfiles/looking-glass.conf > /etc/tmpfiles.d/looking-glass.conf
systemd-tmpfiles --create /etc/tmpfiles.d/looking-glass.conf
command -v looking-glass-client >/dev/null || bash laptop/host/looking-glass/build-client.sh
UHOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
install -D -m 644 -o "$USER_NAME" -g "$USER_NAME" laptop/host/looking-glass/client.ini "$UHOME/.config/looking-glass/client.ini"
install -m 755 laptop/host/win-gpu /usr/local/bin/win-gpu
install -m 755 laptop/host/wexec /usr/local/bin/wexec
install -D -m 644 laptop/host/looking-glass/win-gpu.desktop /usr/local/share/applications/win-gpu.desktop
echo "launcher: 'Windows (GTX 1650)' in the app grid, or win-gpu / win-gpu stop"
bash laptop/host/vm-switch/install.sh
echo "GNOME ignores the GTX after the next login (log out once)"

install -m 755 laptop/host/gpu-mode /usr/local/sbin/gpu-mode
install -m 755 laptop/host/touchpad-bridge /usr/local/sbin/touchpad-bridge
install -m 644 laptop/host/udev/62-gpu-mode-touchpad.rules /etc/udev/rules.d/62-gpu-mode-touchpad.rules
udevadm control --reload
[ -f "$IMG/macos/opencore-igpu.img" ] || echo "TODO: build opencore-igpu.img: sudo bash laptop/vm/macos/build-igpu-image.sh <IntelGopDriver.efi> (laptop/docs/03-macos.md)"

say "DONE. No reboot needed. Check: sudo bash laptop/host/02-verify.sh"
echo "Start VMs only on request: sudo virsh start win10 | sudo virsh start macos"
