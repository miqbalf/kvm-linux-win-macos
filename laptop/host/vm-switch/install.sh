#!/bin/bash
# Install the VM Switch app (switch Linux / Windows / macOS with buttons).
#   sudo bash laptop/host/vm-switch/install.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."   # repo root
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
pacman -S --needed --noconfirm python-gobject gtk4 libadwaita gnome-connections >/dev/null
install -m 755 laptop/host/gpu-mode /usr/local/sbin/gpu-mode          # has the mac-bg mode the app uses
install -m 755 laptop/host/win-gpu /usr/local/bin/win-gpu
install -m 755 laptop/host/vm-switch/vm-switch /usr/local/bin/vm-switch
install -m 644 laptop/host/vm-switch/vm-switch.desktop /usr/local/share/applications/vm-switch.desktop
install -m 644 laptop/host/vm-switch/local.kvm.gpu-mode.policy /usr/share/polkit-1/actions/local.kvm.gpu-mode.policy
echo "VM Switch installed: app grid > VM Switch"
