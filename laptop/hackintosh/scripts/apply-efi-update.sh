#!/usr/bin/env bash
# Safely install an updated OpenCore EFI directory onto the currently booted
# macOS EFI System Partition (resolved via OpenCore NVRAM boot-path UUID).
# Must run on the Hackintosh (macOS).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_EFI=""
DO_REBOOT=0
MOUNT_POINT="/tmp/oc-efi-apply-$$"
MOUNTED_BY_US=0
SUDO_KEEPALIVE_PID=""

usage() {
    cat <<'EOF'
Usage: apply-efi-update.sh --src <EFI-dir> [--reboot]

Options:
  --src <dir>   Source EFI directory containing OC/config.plist and BOOT/
  --reboot      Run sudo reboot immediately after verifying & unmounting ESP
EOF
}

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [[ "$MOUNTED_BY_US" -eq 1 ]] && mount | grep -q " on ${MOUNT_POINT} "; then
        sudo umount "$MOUNT_POINT" >/dev/null 2>&1 || sudo diskutil unmount "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src) SRC_EFI="${2:?missing EFI dir}"; shift 2 ;;
        --reboot) DO_REBOOT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: Run this on the Hackintosh (macOS)." >&2; exit 1; }
[[ -n "$SRC_EFI" && -f "$SRC_EFI/OC/config.plist" ]] || {
    echo "ERROR: Invalid --src '$SRC_EFI' (missing OC/config.plist)." >&2
    exit 1
}
plutil -lint "$SRC_EFI/OC/config.plist" >/dev/null

BOOT_PATH_RAW="$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:boot-path 2>/dev/null | awk '{print $2}' || true)"
PART_UUID="$(printf '%s\n' "$BOOT_PATH_RAW" | sed -nE 's/.*HD\([0-9]+,GPT,([0-9A-Fa-f-]+),.*/\1/p')"
if [[ -z "$PART_UUID" ]]; then
    echo "ERROR: Could not read booted EFI partition UUID from OpenCore NVRAM." >&2
    exit 1
fi
EFI_DISK="$(diskutil info "$PART_UUID" | awk -F: '/Device Identifier/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
[[ -n "$EFI_DISK" && -e "/dev/$EFI_DISK" ]] || {
    echo "ERROR: Resolved EFI device '/dev/${EFI_DISK:-none}' does not exist." >&2
    exit 1
}

echo "==> Target booted ESP : /dev/$EFI_DISK (UUID $PART_UUID)"
echo "==> Source EFI        : $SRC_EFI"
echo "==> Source boot-args  : $(plutil -extract NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args raw "$SRC_EFI/OC/config.plist" 2>/dev/null || echo unknown)"

sudo -v
( while true; do sleep 45; sudo -n true 2>/dev/null || exit 0; done ) </dev/null >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID="$!"

EXISTING_MNT="$(diskutil info "$EFI_DISK" | awk -F: '/Mount Point/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
if [[ -n "$EXISTING_MNT" && -d "$EXISTING_MNT" ]]; then
    DEST_MNT="$EXISTING_MNT"
else
    mkdir -p "$MOUNT_POINT"
    sudo mount -t msdos "/dev/$EFI_DISK" "$MOUNT_POINT"
    MOUNTED_BY_US=1
    DEST_MNT="$MOUNT_POINT"
fi

if [[ -d "$DEST_MNT/EFI" ]]; then
    BAK_DIR="$HOME/efi-pre-apply-$(date +%Y-%m-%d_%H%M%S)"
    echo "==> Saving safety copy -> $BAK_DIR/EFI"
    mkdir -p "$BAK_DIR"
    rsync -a --exclude='.Spotlight-V100' --exclude='.Trashes' --exclude='.fseventsd' \
        "$DEST_MNT/EFI/" "$BAK_DIR/EFI/"
fi

echo "==> Installing $SRC_EFI -> $DEST_MNT/EFI/..."
sudo rsync -a --delete --exclude='.Spotlight-V100' --exclude='.Trashes' --exclude='.fseventsd' \
    "$SRC_EFI/" "$DEST_MNT/EFI/"
sudo plutil -lint "$DEST_MNT/EFI/OC/config.plist"
sync

if [[ "$MOUNTED_BY_US" -eq 1 ]]; then
    sudo umount "$MOUNT_POINT" || sudo diskutil unmount "$MOUNT_POINT"
    MOUNTED_BY_US=0
fi

echo "DONE: Updated /dev/$EFI_DISK EFI successfully."
if [[ "$DO_REBOOT" -eq 1 ]]; then
    echo "==> Rebooting now..."
    sudo reboot
fi
