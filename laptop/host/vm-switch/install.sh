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
install -m 755 laptop/host/gpu-mode /usr/local/sbin/gpu-mode          # has the mac-bg / hdmi-*-bg modes the app uses
install -m 755 laptop/host/linux-hdmi /usr/local/bin/linux-hdmi
install -m 755 laptop/host/win-gpu /usr/local/bin/win-gpu
if [ ! -e /etc/environment.d/90-gtx-free.conf.disabled ]; then
  install -D -m 644 laptop/host/session/90-gtx-free.conf /etc/environment.d/90-gtx-free.conf
fi
install -m 755 laptop/host/gtx-run /usr/local/bin/gtx-run
install -m 755 laptop/host/wexec /usr/local/bin/wexec
install -m 755 laptop/host/deskflow-mode /usr/local/bin/deskflow-mode
if [ -n "${SUDO_USER:-}" ]; then
  UHOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  systemctl_u=(sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" systemctl --user)
  "${systemctl_u[@]}" daemon-reload 2>/dev/null || true
  [ -x "$UHOME/.local/bin/winapps-sync" ] && install -m 755 -o "$SUDO_USER" -g "$SUDO_USER" laptop/host/winapps/winapps-sync "$UHOME/.local/bin/winapps-sync"
  install -D -m 644 -o "$SUDO_USER" -g "$SUDO_USER" laptop/host/looking-glass/client.ini "$UHOME/.config/looking-glass/client.ini"
fi
install -m 755 laptop/host/vm-switch/vm-switch /usr/local/bin/vm-switch
install -m 755 laptop/host/winapps/winapps-sync /usr/local/bin/winapps-sync   # Windows apps -> app grid
install -m 644 laptop/host/vm-switch/vm-switch.desktop /usr/local/share/applications/vm-switch.desktop
install -m 644 laptop/host/vm-switch/local.kvm.gpu-mode.policy /usr/share/polkit-1/actions/local.kvm.gpu-mode.policy
# Refresh Nitro Control too when it is installed (same GTX fix: draws on the Intel iGPU only).
[ -e /usr/local/bin/nitro-control ] && install -m 755 laptop/host/nitrosense/nitro-control /usr/local/bin/nitro-control
pkill -f /usr/local/bin/vm-switch 2>/dev/null || true   # an old copy still holds the GTX; reopen the app
echo "VM Switch installed: app grid > VM Switch"
