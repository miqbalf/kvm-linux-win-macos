#!/bin/bash
# Install NitroSense-like fan + keyboard RGB control on the Acer Nitro AN515-55:
# the linuwu_sense kernel module (DKMS, rebuilt on every kernel update) and the `nitro` command.
#   sudo bash laptop/host/nitrosense/install.sh
# Undo: sudo bash ~/src/Linuwu-AN515-55/scripts/uninstall-dkms.sh  (back to the stock acer_wmi),
#       or boot the snapper snapshot this script takes first.
# Source: github.com/BillyAddlers/Linuwu-Sense-AN515-55-Patch, pinned to the tested commit.
set -euo pipefail
cd "$(dirname "$0")/../../.."   # repo root
USER_NAME=${SUDO_USER:?run with sudo from your user account}
SRC=$(getent passwd "$USER_NAME" | cut -d: -f6)/src/Linuwu-AN515-55
REPO=https://github.com/BillyAddlers/Linuwu-Sense-AN515-55-Patch
COMMIT=a18abd3cc476917adb62c1208c8e7196df5ca3d8   # tested 2026-11-20, kernel 7.3.4-cachyos

[ "$(cat /sys/class/dmi/id/product_name)" = "Nitro AN515-55" ] || { echo "not an AN515-55: WMI payloads differ, stop"; exit 1; }
pacman -S --needed --noconfirm dkms git "$(pacman -Qq linux-cachyos >/dev/null 2>&1 && echo linux-cachyos-headers || echo linux-headers)" >/dev/null
snapper -c root create -t single -d "before linuwu_sense (NitroSense fan/RGB)" --userdata important=yes || true

if [ ! -d "$SRC/.git" ]; then sudo -u "$USER_NAME" git clone -q "$REPO" "$SRC"; fi
sudo -u "$USER_NAME" git -C "$SRC" fetch -q origin
sudo -u "$USER_NAME" git -C "$SRC" checkout -q "$COMMIT"
# Upstream script: dkms add/build/install, blacklists acer_wmi, modules-load.d, linuwu_sense.service,
# group linuwu_sense (+ the user) and tmpfiles.d permissions for the sysfs files.
# Its last step (modinfo .../linuwu_sense.ko) fails on CachyOS, which installs .ko.zst: check DKMS instead.
SUDO_USER=$USER_NAME bash "$SRC/scripts/install-dkms.sh" || true
dkms status linuwu_sense | grep -q installed || { echo "ERROR: DKMS build/install failed"; exit 1; }
lsmod | grep -q '^linuwu_sense' || { echo "ERROR: linuwu_sense not loaded"; exit 1; }
install -m 755 laptop/host/nitrosense/nitro /usr/local/bin/nitro
install -m 755 laptop/host/nitrosense/nitro-control /usr/local/bin/nitro-control
install -m 644 laptop/host/nitrosense/nitro-control.desktop /usr/local/share/applications/nitro-control.desktop
install -m 644 laptop/host/nitrosense/nitro-restore.desktop /etc/xdg/autostart/nitro-restore.desktop
install -D -m 644 laptop/host/nitrosense/10-permissions.conf /etc/systemd/system/linuwu_sense.service.d/10-permissions.conf
systemctl daemon-reload   # not restart: its ExecStop unloads the module
systemd-tmpfiles --create /etc/tmpfiles.d/linuwu_sense.conf
echo; nitro status
echo "App: 'Nitro Control' in the app grid. Command: nitro. Log out and in once (group linuwu_sense)."
