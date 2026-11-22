#!/bin/bash
# Install the AN515-55 NitroEC.kext into /Library/Extensions and load it.
# First time: macOS asks to allow the extension (System Settings > Privacy & Security), then a restart.
set -euo pipefail
SRC="${1:-$HOME/src/ns55}"
sudo rm -rf /Library/Extensions/NitroEC.kext
sudo cp -R "$SRC/build/NitroEC.kext" /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/NitroEC.kext
sudo kmutil load -p /Library/Extensions/NitroEC.kext || echo "If asked: allow it, restart, then run nitroctl status."
sudo install -m 755 "$SRC/build/nitroctl" /usr/local/bin/nitroctl
nitroctl status || true
