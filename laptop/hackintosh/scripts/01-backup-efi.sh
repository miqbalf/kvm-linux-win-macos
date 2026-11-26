#!/usr/bin/env bash
# Back up the live booted macOS EFI System Partition (ESP), NVRAM, and disk map.
# Run directly on the Hackintosh (local Terminal or interactive SSH session),
# or automatically from your controller Mac via ./scripts/02-sync-efi-to-repo.sh.
set -euo pipefail

DEST_ROOT="${1:-$HOME}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUT_DIR="${DEST_ROOT%/}/efi-backup-${STAMP}"
MOUNT_POINT="/tmp/oc-efi-backup-$$"
MOUNTED_BY_US=0
SUDO_KEEPALIVE_PID=""

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [[ "$MOUNTED_BY_US" -eq 1 ]] && mount | grep -q " on ${MOUNT_POINT} "; then
        sudo diskutil unmount "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: 01-backup-efi.sh must run on macOS (the Hackintosh itself)." >&2
    exit 1
fi

echo "==> Detecting booted OpenCore EFI partition..."
BOOT_PATH_RAW="$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:boot-path 2>/dev/null | awk '{print $2}' || true)"
if [[ -z "$BOOT_PATH_RAW" ]]; then
    echo "ERROR: Could not read OpenCore boot-path from NVRAM." >&2
    echo "Hint: set EFI_DISK=diskXs1 explicitly if booting via a non-standard loader." >&2
    exit 1
fi

# Expected format: PciRoot(...)/.../HD(1,GPT,<PARTITION-UUID>,...)/EFI\OC\OpenCore.efi
PART_UUID="$(printf '%s\n' "$BOOT_PATH_RAW" | sed -nE 's/.*HD\([0-9]+,GPT,([0-9A-Fa-f-]+),.*/\1/p')"
if [[ -z "${EFI_DISK:-}" ]]; then
    if [[ -z "$PART_UUID" ]]; then
        echo "ERROR: Could not parse GPT partition UUID from boot-path: $BOOT_PATH_RAW" >&2
        exit 1
    fi
    EFI_DISK="$(diskutil info "$PART_UUID" | awk -F: '/Device Identifier/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
fi

if [[ -z "$EFI_DISK" || ! -e "/dev/${EFI_DISK}" ]]; then
    echo "ERROR: Resolved EFI device '/dev/${EFI_DISK:-none}' does not exist." >&2
    exit 1
fi

echo "    Boot path : $BOOT_PATH_RAW"
echo "    EFI UUID  : ${PART_UUID:-unknown}"
echo "    EFI disk  : /dev/$EFI_DISK"
echo "    Backup dir: $OUT_DIR"

echo "==> Requesting sudo credentials once for ESP mount and raw partition read..."
sudo -v
(
    while true; do
        sleep 45
        sudo -n true 2>/dev/null || exit 0
    done
) </dev/null >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID="$!"

mkdir -p "$OUT_DIR"
printf '%s\n' "$BOOT_PATH_RAW" > "$OUT_DIR/boot-path.txt"
diskutil list > "$OUT_DIR/diskutil-list.txt"
diskutil info "$EFI_DISK" > "$OUT_DIR/diskutil-efi-info.txt"
nvram -xp > "$OUT_DIR/nvram.plist"

EXISTING_MNT="$(diskutil info "$EFI_DISK" | awk -F: '/Mount Point/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
if [[ -n "$EXISTING_MNT" && -d "$EXISTING_MNT" ]]; then
    SRC_MNT="$EXISTING_MNT"
    echo "==> Using already-mounted ESP at $SRC_MNT"
else
    mkdir -p "$MOUNT_POINT"
    echo "==> Temporarily mounting /dev/$EFI_DISK (read-only) at $MOUNT_POINT..."
    sudo mount -t msdos -o rdonly "/dev/$EFI_DISK" "$MOUNT_POINT"
    MOUNTED_BY_US=1
    SRC_MNT="$MOUNT_POINT"
fi

if [[ ! -d "$SRC_MNT/EFI" ]]; then
    echo "ERROR: $SRC_MNT/EFI does not exist; aborting backup." >&2
    exit 1
fi

echo "==> Copying EFI directory tree..."
mkdir -p "$OUT_DIR/EFI"
rsync -a --exclude='.Spotlight-V100' --exclude='.Trashes' --exclude='.fseventsd' --exclude='.TemporaryItems' \
    "$SRC_MNT/EFI/" "$OUT_DIR/EFI/"

if [[ "$MOUNTED_BY_US" -eq 1 ]]; then
    sudo umount "$MOUNT_POINT" || sudo diskutil unmount "$MOUNT_POINT"
    MOUNTED_BY_US=0
fi

echo "==> Taking raw ESP image /dev/r$EFI_DISK -> efi-partition.img..."
sudo dd if="/dev/r${EFI_DISK}" of="$OUT_DIR/efi-partition.img" bs=1m status=progress
sudo chown "$(id -un):$(id -gn)" "$OUT_DIR/efi-partition.img"

echo "==> Generating SHA256SUMS..."
(
    cd "$OUT_DIR"
    shasum -a 256 efi-partition.img nvram.plist EFI/OC/config.plist EFI/OC/OpenCore.efi > SHA256SUMS
)

ln -sfn "$OUT_DIR" "${DEST_ROOT%/}/efi-backup-latest"
echo "DONE: Backup saved to $OUT_DIR (symlinked at ${DEST_ROOT%/}/efi-backup-latest)"
