#!/usr/bin/env bash
# Compile x86_64 NitroGPU.app and package NitroGPU-Switcher.dmg.
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HACKINTOSH_DIR="$(cd -- "$APP_DIR/.." && pwd)"
OUT_DIR="${1:-$HACKINTOSH_DIR/out}"

mkdir -p "$OUT_DIR"
APP_BUNDLE="$OUT_DIR/NitroGPU.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$APP_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Compiling x86_64 NitroGPU.app..."
xcrun swiftc -target x86_64-apple-macos15.0 -O \
    -framework AppKit -framework Metal \
    "$APP_DIR/NitroGPU.swift" \
    -o "$APP_BUNDLE/Contents/MacOS/NitroGPU"

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

DMG_STAGE="$OUT_DIR/dmg-stage"
DMG_OUT="$OUT_DIR/NitroGPU-Switcher.dmg"
rm -rf "$DMG_STAGE" "$DMG_OUT"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> Packaging $DMG_OUT..."
hdiutil create -volname "NitroGPU Switcher" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_OUT" >/dev/null
rm -rf "$DMG_STAGE"

echo "Built: $APP_BUNDLE"
echo "DMG  : $DMG_OUT"
