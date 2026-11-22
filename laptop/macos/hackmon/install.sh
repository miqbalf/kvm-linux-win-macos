#!/bin/bash
# Install hackmon: boot report 4 min after every boot + daily error report.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sudo install -d /usr/local/bin /Library/Logs/HackMon
sudo install -m 755 -o root -g wheel "$HERE/hackmon" /usr/local/bin/hackmon
for p in com.local.hackmon com.local.hackmon-daily; do
    sudo install -m 644 -o root -g wheel "$HERE/$p.plist" /Library/LaunchDaemons/
    sudo launchctl bootout system/$p 2>/dev/null || true
done
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.hackmon-daily.plist
sudo /usr/local/bin/hackmon report
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.hackmon.plist 2>/dev/null || true
hackmon last
