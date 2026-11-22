#!/bin/bash
# Build and install sleepmon (needs Xcode Command Line Tools for swiftc). Asks for sudo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
swiftc -O -o "$HERE/sleepmon" "$HERE/sleepmon.swift"
sudo install -d /Library/Logs/SleepMon
sudo install -m 755 -o root -g wheel "$HERE/sleepmon" "$HERE/sleepmon-report" /usr/local/bin/
sudo install -m 644 -o root -g wheel "$HERE/com.local.sleepmon.plist" /Library/LaunchDaemons/
sudo launchctl bootout system/com.local.sleepmon 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.sleepmon.plist
sleep 3; tail -5 /Library/Logs/SleepMon/sleepmon.log
