#!/bin/bash
# Install apfs-trim-cycle (LaunchDaemon: at boot + daily 12:00).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sudo install -d /usr/local/sbin
sudo install -m 755 -o root -g wheel "$HERE/apfs-trim-cycle" /usr/local/sbin/apfs-trim-cycle
sudo install -m 644 -o root -g wheel "$HERE/com.local.apfs-trim-cycle.plist" /Library/LaunchDaemons/
sudo launchctl bootout system/com.local.apfs-trim-cycle 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.apfs-trim-cycle.plist
sudo /usr/local/sbin/apfs-trim-cycle status
