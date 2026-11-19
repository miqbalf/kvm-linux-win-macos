#!/bin/bash
# build-igpu-image.sh - build the OpenCore image for macOS on the laptop panel (domain macos-igpu).
# Run on the laptop in HOST mode (needs i915 for the VBT), from the repo root:
#   sudo bash laptop/vm/macos/build-igpu-image.sh <IntelGopDriver.efi>
# Input: the Intel GOP driver extracted from this laptop's BIOS (README "Get the Intel GOP").
# Output, in /var/lib/libvirt/images/macos/ (the previous image is kept as *.prev):
#   igd-gop.rom          GOP as PCI option ROM (IGD legacy mode in QEMU requires a ROM)
#   opencore-igpu.img    opencore-lt.img + iGPU config.plist + PlatformGopPolicy.efi + IntelGopDriver.efi
# Nothing here touches the real Hackintosh disk or the laptop BIOS.
set -euo pipefail
GOP=$(readlink -f "${1:?usage: build-igpu-image.sh IntelGopDriver.efi}")
D=$(cd "$(dirname "$0")" && pwd)
IMG=/var/lib/libvirt/images/macos
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$D/opencore-lt.img" ] || { echo "missing $D/opencore-lt.img (VM copy of the laptop EFI)"; exit 1; }
[ -f "$D/oc-build/EFI/OC/config.plist.binary-bak" ] || { echo "missing oc-build/EFI/OC/config.plist.binary-bak"; exit 1; }
command -v mcopy >/dev/null || pacman -S --needed --noconfirm mtools gnu-efi
[ -e /sys/kernel/debug/dri/0000:00:02.0/i915_vbt ] || { echo "iGPU not on i915: run 'sudo gpu-mode host' first"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat /sys/kernel/debug/dri/0000:00:02.0/i915_vbt > "$T/vbt.bin"
bash "$D/gop-policy/build.sh" "$T/vbt.bin" "$T/PlatformGopPolicy.efi"
python3 "$D/make-gop-rom.py" "$GOP" "$T/igd-gop.rom"
python3 "$D/make-vm-config.py" "$D/oc-build/EFI/OC/config.plist.binary-bak" "$T/config.plist" --igpu | tail -1
cp "$D/opencore-lt.img" "$T/oc.img"
mcopy -o -i "$T/oc.img" "$T/PlatformGopPolicy.efi" ::/EFI/OC/Drivers/PlatformGopPolicy.efi
mcopy -o -i "$T/oc.img" "$GOP" ::/EFI/OC/Drivers/IntelGopDriver.efi
mcopy -o -i "$T/oc.img" "$T/config.plist" ::/EFI/OC/config.plist

for f in igd-gop.rom opencore-igpu.img; do [ -f "$IMG/$f" ] && cp -f "$IMG/$f" "$IMG/$f.prev"; done
install -m 644 "$T/igd-gop.rom" "$IMG/igd-gop.rom"
install -m 644 "$T/oc.img" "$IMG/opencore-igpu.img"
echo "installed $IMG/igd-gop.rom and $IMG/opencore-igpu.img (previous: *.prev)"
