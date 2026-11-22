#!/bin/bash
# Headless Linux RDP while macOS has the laptop screen (gpu-mode mac). Run once from the repo root:
#   sudo bash laptop/host/headless-rdp/setup.sh
# - user units in /etc/systemd/user (headless GNOME Shell + gnome-remote-desktop --headless)
# - lingering for the desktop user, so its systemd user manager runs without a login
# - RDP TLS certificate, user name and a random password (~/.config/linux-rdp-password, mode 600)
# - ufw: port 3389 from the LAN and Tailscale only
# - the current gpu-mode (starts the target in mac mode, stops it before GDM in host mode)
set -euo pipefail
cd "$(dirname "$0")/../../.."
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:-$(id -nu 1000)}; H=$(getent passwd "$U" | cut -d: -f6)
pacman -S --needed --noconfirm gnome-remote-desktop openssl >/dev/null
D=laptop/host/headless-rdp
install -D -m 644 $D/linux-headless-shell.service /etc/systemd/user/linux-headless-shell.service
install -D -m 644 $D/linux-headless-rdp.target /etc/systemd/user/linux-headless-rdp.target
install -D -m 644 $D/grd-headless-override.conf /etc/systemd/user/gnome-remote-desktop-headless.service.d/override.conf
loginctl enable-linger "$U"
install -m 755 laptop/host/gpu-mode /usr/local/sbin/gpu-mode
sudo -u "$U" XDG_RUNTIME_DIR=/run/user/$(id -u "$U") bash -s <<'USER'
set -eu
D=~/.local/share/gnome-remote-desktop; mkdir -p "$D"
[ -f "$D/rdp-tls.crt" ] || openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/CN=$(hostname)" \
  -keyout "$D/rdp-tls.key" -out "$D/rdp-tls.crt" 2>/dev/null
chmod 600 "$D/rdp-tls.key"
P=~/.config/linux-rdp-password
[ -s "$P" ] || (umask 077; openssl rand -base64 24 | tr -d '/+=' | cut -c1-16 > "$P")
g() { grdctl --headless "$@" 2>&1 | grep -vE 'TPM|x509_utils|certificate is invalid' || true; }
g rdp set-tls-cert "$D/rdp-tls.crt"; g rdp set-tls-key "$D/rdp-tls.key"
g rdp set-credentials "$(id -un)" "$(cat "$P")"; g rdp disable-view-only; g rdp enable
systemctl --user daemon-reload
USER
if systemctl is-active -q ufw; then
  ufw allow from 192.168.1.0/24 to any port 3389 proto tcp comment 'Linux RDP (LAN)' >/dev/null
  ufw allow in on tailscale0 to any port 3389 proto tcp comment 'Linux RDP (Tailscale)' >/dev/null
fi
echo "Headless RDP ready. In mac mode connect to this laptop on port 3389 as $U."
echo "Password: $H/.config/linux-rdp-password"
