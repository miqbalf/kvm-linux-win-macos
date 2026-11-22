#!/bin/bash
# Build NitroSense-macOS with the AN515-55 patch (kext + nitroctl).
# Needs Command Line Tools (clang, swiftc, MacOSX SDK with Kernel.framework). No Xcode, no iasl.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HOME/src/ns55}"
UPSTREAM=https://github.com/Thatisjigen/NitroSense-macOS
BASE=efb14d4   # upstream "Version 1.1.0"

if [ ! -d "$SRC/.git" ]; then
    git clone "$UPSTREAM" "$SRC"
fi
cd "$SRC"
git checkout -q "$BASE"
git checkout -q -B an515-55
git apply --check "$HERE/an515-55.patch" 2>/dev/null && git apply "$HERE/an515-55.patch"
make kext cli
echo "Built: $SRC/build/NitroEC.kext and $SRC/build/nitroctl"
