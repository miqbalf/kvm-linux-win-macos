#!/usr/bin/env bash
# Prepare a safe, isolated USB test OpenCore EFI (or staging folder) with the
# Acer Nitro AN515-55 GTX 1650 enabled in native-iGPU headless Optimus mode.
# Never modifies the internal SSD EFI partition.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HACKINTOSH_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

EFI_SRC="$HACKINTOSH_DIR/efi-backup/latest/EFI"
USB_DISK=""
MOUNT_TARGET=""
OUT_STAGE_DIR=""
ENABLE_RTD3=0
NO_FLIP=1
DEBUG_BOOT=1
AUTO_HDMI=1
NO_NVMEFIX=0
NVME_SAFE=0
MOUNTED_BY_US=0
MOUNT_POINT="/tmp/oc-usb-efi-$$"
SUDO_KEEPALIVE_PID=""

usage() {
    cat <<'EOF'
Usage: 04-prepare-usb-test-efi.sh (--disk diskX | --mount /Volumes/EFI | --out-dir <dir>) [options]

Targets (pick one):
  --disk <diskX>     External/USB disk (e.g. disk4). Verified non-internal; mounts ESP via sudo
  --mount <path>     Already-mounted USB EFI root directory (writes <path>/EFI)
  --out-dir <dir>    Offline staging directory (writes <dir>/EFI without touching disks)

Options:
  --efi-src <dir>    Source EFI directory (default: laptop/hackintosh/efi-backup/latest/EFI)
  --rtd3             Add SSDT-NXRTD3.aml and nvrtd3=1 nvrtd3off=NXOF nvrtd3on=NXO_ boot-args
                     (only enable once patched NVRM.kext is installed)
  --noflip           Keep -nvrmnoflip boot-arg (default; safer on 256 MB BAR1 without ReBAR)
  --allow-flip       Allow zero-copy scanout flips (omit -nvrmnoflip)
  --no-auto-hdmi     Omit nvfbhotplugpoll=2 nvagdcheads=1 (disables HDMI hotplug polling)
  --no-debug         Omit -v debug=0x100 keepsyms=1 swd_panic=1 and force quiet Misc.Debug (Target=0)
  --no-nvmefix       Add -nvmefoff boot-arg to disable NVMeFix.kext (workaround for NVMe MMIO drops)
  --nvme-safe        Apply --no-nvmefix plus disable ASPM/APST on RP09 NVMe (PciRoot(0x0)/Pci(0x1D,0x0))
  -h, --help         Show help
EOF
}

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) USB_DISK="${2:?missing disk id}"; shift 2 ;;
        --mount) MOUNT_TARGET="${2:?missing mount path}"; shift 2 ;;
        --out-dir) OUT_STAGE_DIR="${2:?missing output dir}"; shift 2 ;;
        --efi-src) EFI_SRC="${2:?missing source EFI dir}"; shift 2 ;;
        --rtd3) ENABLE_RTD3=1; shift ;;
        --noflip) NO_FLIP=1; shift ;;
        --allow-flip) NO_FLIP=0; shift ;;
        --no-auto-hdmi) AUTO_HDMI=0; shift ;;
        --no-debug) DEBUG_BOOT=0; shift ;;
        --no-nvmefix) NO_NVMEFIX=1; shift ;;
        --nvme-safe) NO_NVMEFIX=1; NVME_SAFE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

target_count=0
[[ -n "$USB_DISK" ]] && ((target_count+=1))
[[ -n "$MOUNT_TARGET" ]] && ((target_count+=1))
[[ -n "$OUT_STAGE_DIR" ]] && ((target_count+=1))
if [[ "$target_count" -ne 1 ]]; then
    echo "ERROR: Specify exactly one of --disk, --mount, or --out-dir." >&2
    usage
    exit 1
fi

if [[ ! -f "$EFI_SRC/OC/config.plist" ]]; then
    echo "ERROR: Source EFI missing OC/config.plist at: $EFI_SRC" >&2
    exit 1
fi

DEST_ROOT=""
if [[ -n "$USB_DISK" ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: --disk mode requires macOS." >&2; exit 1; }
    DISK_INFO="$(diskutil info "/dev/${USB_DISK}" 2>/dev/null)" || { echo "ERROR: Unknown disk: $USB_DISK" >&2; exit 1; }
    IS_INTERNAL="$(printf '%s\n' "$DISK_INFO" | awk -F: '/^[[:space:]]*Internal:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    PROTOCOL="$(printf '%s\n' "$DISK_INFO" | awk -F: '/^[[:space:]]*Protocol:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    if [[ "$IS_INTERNAL" != "No" ]]; then
        echo "SAFETY ABORT: /dev/$USB_DISK is an internal disk (Internal: $IS_INTERNAL). Only external USB drives are allowed." >&2
        exit 1
    fi
    echo "==> Verified external disk /dev/$USB_DISK (Internal=$IS_INTERNAL, Protocol=${PROTOCOL:-unknown})"

    ESP_SLICE="$(diskutil list "/dev/$USB_DISK" | awk '/EFI/{print $NF; exit}')"
    [[ -n "$ESP_SLICE" ]] || ESP_SLICE="${USB_DISK}s1"
    ESP_INFO="$(diskutil info "/dev/$ESP_SLICE" 2>/dev/null)" || { echo "ERROR: Could not inspect ESP slice /dev/$ESP_SLICE" >&2; exit 1; }
    echo "==> Using USB EFI partition /dev/$ESP_SLICE"

    EXISTING_MNT="$(printf '%s\n' "$ESP_INFO" | awk -F: '/^[[:space:]]*Mount Point:/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    if [[ -n "$EXISTING_MNT" && -d "$EXISTING_MNT" ]]; then
        DEST_ROOT="$EXISTING_MNT"
    else
        echo "==> Requesting sudo once to mount /dev/$ESP_SLICE..."
        sudo -v
        ( while true; do sleep 45; sudo -n true 2>/dev/null || exit 0; done ) </dev/null >/dev/null 2>&1 &
        SUDO_KEEPALIVE_PID="$!"
        mkdir -p "$MOUNT_POINT"
        sudo diskutil mount -mountPoint "$MOUNT_POINT" "/dev/$ESP_SLICE"
        MOUNTED_BY_US=1
        DEST_ROOT="$MOUNT_POINT"
    fi
elif [[ -n "$MOUNT_TARGET" ]]; then
    [[ -d "$MOUNT_TARGET" ]] || { echo "ERROR: Mount directory does not exist: $MOUNT_TARGET" >&2; exit 1; }
    DEST_ROOT="$MOUNT_TARGET"
else
    mkdir -p "$OUT_STAGE_DIR"
    DEST_ROOT="$OUT_STAGE_DIR"
fi

if [[ -d "$DEST_ROOT/EFI" ]]; then
    BAK_NAME="EFI.pre-optimus-$(date +%Y-%m-%d_%H%M%S)"
    echo "==> Backing up existing $DEST_ROOT/EFI -> $DEST_ROOT/$BAK_NAME"
    cp -R "$DEST_ROOT/EFI" "$DEST_ROOT/$BAK_NAME"
fi

echo "==> Copying baseline EFI from $EFI_SRC -> $DEST_ROOT/EFI"
rm -rf "$DEST_ROOT/EFI"
mkdir -p "$DEST_ROOT/EFI"
cp -R "$EFI_SRC/." "$DEST_ROOT/EFI/"

if [[ "$ENABLE_RTD3" -eq 1 ]]; then
    RTD3_AML="$HACKINTOSH_DIR/out/SSDT-NXRTD3.aml"
    if [[ ! -f "$RTD3_AML" ]]; then
        echo "==> Generating SSDT-NXRTD3.aml..."
        python3 "$HACKINTOSH_DIR/opencore/acpi/build-rtd3-aml.py" -o "$DEST_ROOT/EFI/OC/ACPI/SSDT-NXRTD3.aml"
    else
        cp "$RTD3_AML" "$DEST_ROOT/EFI/OC/ACPI/SSDT-NXRTD3.aml"
    fi
fi

echo "==> Patching $DEST_ROOT/EFI/OC/config.plist for NullMoth Optimus test..."
python3 - "$DEST_ROOT/EFI/OC/config.plist" "$ENABLE_RTD3" "$NO_FLIP" "$DEBUG_BOOT" "$AUTO_HDMI" "$NO_NVMEFIX" "$NVME_SAFE" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
enable_rtd3 = bool(int(sys.argv[2]))
no_flip = bool(int(sys.argv[3]))
debug_boot = bool(int(sys.argv[4]))
auto_hdmi = bool(int(sys.argv[5]))
no_nvmefix = bool(int(sys.argv[6]))
nvme_safe = bool(int(sys.argv[7]))

with plist_path.open("rb") as f:
    cfg = plistlib.load(f)

# 1. Unhide GTX 1650 in ACPI (disable SSDT-NoHybGfx.aml / SSDT-off-gpu.aml)
acpi_add = cfg.setdefault("ACPI", {}).setdefault("Add", [])
seen_nxrtd3 = False
for entry in acpi_add:
    p = entry.get("Path", "")
    if p in ("SSDT-NoHybGfx.aml", "SSDT-off-gpu.aml"):
        entry["Enabled"] = False
    elif p == "SSDT-NXRTD3.aml":
        entry["Enabled"] = enable_rtd3
        seen_nxrtd3 = True

if enable_rtd3 and not seen_nxrtd3:
    acpi_add.append({
        "Comment": "AN515-55 4-char RTD3 wrappers (NXOF/NXO_) for NullMoth NVRM",
        "Enabled": True,
        "Path": "SSDT-NXRTD3.aml",
    })

# 2. Ensure IONDRVSupport is NOT blocked (needed by AppleIntelCFLGraphicsFramebuffer)
for blk in cfg.setdefault("Kernel", {}).setdefault("Block", []):
    if blk.get("Identifier") == "com.apple.iokit.IONDRVSupport":
        blk["Enabled"] = False

# 3. Rewrite boot-args cleanly
nvram_uuid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
nvram_add = cfg.setdefault("NVRAM", {}).setdefault("Add", {}).setdefault(nvram_uuid, {})
old_args = str(nvram_add.get("boot-args", "")).split()

strip_exact = {
    "-wegnoegpu",
    "-nvkmsnosmooth",
    "-nvrmnoflip",
    "-nvmefoff",
    "-v",
    "keepsyms=1",
    "swd_panic=1",
}
strip_prefix = (
    "nvfb=",
    "nvaccel=",
    "nvfbheads=",
    "nvfbhotplugpoll=",
    "nvagdcheads=",
    "nvrmsettle=",
    "gfxrst=",
    "nmhybrid=",
    "nvrtd3=",
    "nvrtd3off=",
    "nvrtd3on=",
    "nvrtd3res=",
    "amfi_get_out_of_my_way=",
    "amfi=",
    "ipc_control_port_options=",
    "debug=",
)

kept = [
    tok for tok in old_args
    if tok not in strip_exact and not tok.startswith(strip_prefix)
]

if debug_boot:
    kept.extend(["-v", "debug=0x100", "keepsyms=1", "swd_panic=1"])

kept.extend([
    "nvfb=1",
    "nvaccel=1",
    "nvfbheads=4",
    "-nvkmsnosmooth",
    "gfxrst=4",
    "amfi_get_out_of_my_way=0x1",
    "amfi=0x80",
    "ipc_control_port_options=0",
])

if no_flip:
    kept.append("-nvrmnoflip")
if auto_hdmi:
    kept.extend(["nvfbhotplugpoll=2", "nvagdcheads=1", "nvrmsettle=10000"])
if enable_rtd3:
    kept.extend(["nvrtd3=1", "nvrtd3off=NXOF", "nvrtd3on=NXO_"])
if no_nvmefix:
    kept.append("-nvmefoff")

nvram_add["boot-args"] = " ".join(kept)

# 4. When --no-debug is set, also keep Misc.Debug quiet (Target=0) so OpenCore adds zero log overhead
if not debug_boot:
    misc_dbg = cfg.setdefault("Misc", {}).setdefault("Debug", {})
    misc_dbg["AppleDebug"] = False
    misc_dbg["ApplePanic"] = True
    misc_dbg["DisableWatchDog"] = True
    misc_dbg["DisplayDelay"] = 0
    misc_dbg["DisplayLevel"] = 0
    misc_dbg["SysReport"] = False
    misc_dbg["Target"] = 0

# 5. Optional NVMe ASPM/APST safety overrides for Samsung SSD 980 on RP09@1d,0
dp_add = cfg.setdefault("DeviceProperties", {}).setdefault("Add", {})
rp09_path = "PciRoot(0x0)/Pci(0x1D,0x0)"
nvme_path = "PciRoot(0x0)/Pci(0x1D,0x0)/Pci(0x0,0x0)"
if nvme_safe:
    dp_add.setdefault(rp09_path, {})["pci-aspm-default"] = b"\x00\x00\x00\x00"
    nvme_props = dp_add.setdefault(nvme_path, {})
    nvme_props["pci-aspm-default"] = b"\x00\x00\x00\x00"
    nvme_props["ps-max-latency-us"] = b"\x00\x00\x00\x00\x00\x00\x00\x00"
else:
    for p in (rp09_path, nvme_path):
        if p in dp_add and isinstance(dp_add[p], dict):
            dp_add[p].pop("pci-aspm-default", None)
            dp_add[p].pop("ps-max-latency-us", None)
            if not dp_add[p]:
                del dp_add[p]

# Ensure OpenCore deletes existing NVRAM boot-args so updated args take effect without manual NVRAM reset
nvram_del = cfg.setdefault("NVRAM", {}).setdefault("Delete", {}).setdefault(nvram_uuid, [])
for k in ("boot-args", "csr-active-config"):
    if k not in nvram_del:
        nvram_del.append(k)

with plist_path.open("wb") as f:
    plistlib.dump(cfg, f, fmt=plistlib.FMT_XML, sort_keys=False)

print("Updated boot-args:", nvram_add["boot-args"])
PY

echo "DONE: Prepared test EFI at $DEST_ROOT/EFI"
echo "      Boot via Acer F12 boot menu and select your USB EFI before touching the internal NVMe ESP."
