#!/bin/bash
# Install the "coherence" setup on the Hackintosh: Linux apps as Mac apps, auto resume, auto suspend.
# Run in Terminal on the laptop's desktop (not SSH) while the CachyOS VM is running.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for f in cachyos-vm linux-app linux-apps-sync cachyos-vm-idle cachyos-vm-guard; do
    sudo install -m 755 "$HERE/$f" /usr/local/bin/$f
done
for a in local.cachyos-vm-idle local.cachyos-vm-guard; do
    install -m 644 "$HERE/$a.plist" ~/Library/LaunchAgents/
    launchctl bootout gui/$(id -u)/$a 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$a.plist
done
cachyos-vm start
linux-apps-sync
open "$HOME/Applications/CachyOS Apps"
