#!/bin/bash
# Install the VM Switch app (switch Linux / Windows / macOS with buttons).
#   sudo bash laptop/host/vm-switch/install.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."   # repo root
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
pacman -S --needed --noconfirm python-gobject gtk4 libadwaita >/dev/null
# VNC viewer for the "macOS in a window" / "Windows install" VMs. Optional: a bad mirror must not stop the install.
pacman -S --needed --noconfirm gnome-connections >/dev/null 2>&1 \
  || echo "WARN: gnome-connections not installed (mirror error?). Later: sudo pacman -Syu gnome-connections"
install -m 755 laptop/host/gpu-mode /usr/local/sbin/gpu-mode          # has the mac-bg mode the app uses
install -m 755 laptop/host/win-gpu /usr/local/bin/win-gpu
install -D -m 644 laptop/host/session/90-gtx-free.conf /etc/environment.d/90-gtx-free.conf
install -m 755 laptop/host/gtx-run /usr/local/bin/gtx-run
# Apply to the running session too (new apps and restarted services); a log out/in applies it everywhere.
[ -n "${SUDO_USER:-}" ] && sudo -u "$SUDO_USER" XDG_RUNTIME_DIR=/run/user/$(id -u "$SUDO_USER") systemctl --user daemon-reload 2>/dev/null || true
install -m 755 laptop/host/vm-switch/vm-switch /usr/local/bin/vm-switch
install -m 644 laptop/host/vm-switch/vm-switch.desktop /usr/local/share/applications/vm-switch.desktop
install -m 644 laptop/host/vm-switch/local.kvm.gpu-mode.policy /usr/share/polkit-1/actions/local.kvm.gpu-mode.policy
# Refresh Nitro Control too when it is installed (same GTX fix: draws on the Intel iGPU only).
[ -e /usr/local/bin/nitro-control ] && install -m 755 laptop/host/nitrosense/nitro-control /usr/local/bin/nitro-control
pkill -f /usr/local/bin/vm-switch 2>/dev/null || true   # an old copy still holds the GTX; reopen the app
echo "VM Switch installed: app grid > VM Switch"
