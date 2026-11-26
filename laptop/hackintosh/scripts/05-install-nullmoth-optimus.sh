#!/usr/bin/env bash
# Install (or update) NullMoth + Optimus policy + no-wsreset guard on the Hackintosh.
# Must be run ON the Hackintosh (macOS Tahoe).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HACKINTOSH_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$HACKINTOSH_DIR/out"

RELEASE_DIR=""
PATCH_ONLY=0
NVMTL_BIN="$OUT_DIR/NVMTLDriver"
POLICY_SRC="$HACKINTOSH_DIR/opencore/nvmtl-gpu-policy.txt"
CTL_SRC="$SCRIPT_DIR/nitro-gpu-ctl.sh"
APP_SRC="$OUT_DIR/NitroGPU.app"
NVRM_KEXT=""
AUTO_HDMI_DAEMON=1
PASSWORDLESS_GUI=0
SUDO_KEEPALIVE_PID=""

usage() {
    cat <<'EOF'
Usage: 05-install-nullmoth-optimus.sh (--release-dir <dir> | --patch-only) [options]

Modes:
  --release-dir <dir>     Path to unpacked NullMoth release package (contains install.sh)
                          Runs upstream install.sh first, then installs patched binaries/policy
  --patch-only            Patch an existing NullMoth installation in /Library/GPUBundles

Options:
  --nvmtl-bin <file>      Patched NVMTLDriver Mach-O binary (default: out/NVMTLDriver)
  --policy <file>         Policy file (default: opencore/nvmtl-gpu-policy.txt)
  --nvrm-kext <dir>       Optional patched NVRM.kext (with RTD3 4-char support) to install
  --no-auto-hdmi-daemon   Skip installing LaunchDaemon that arms hot-plugged HDMI
  --passwordless-gui      Allow NitroGPU.app to switch modes via sudo -n without admin popup
  -h, --help              Show help
EOF
}

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release-dir) RELEASE_DIR="${2:?missing release dir}"; shift 2 ;;
        --patch-only) PATCH_ONLY=1; shift ;;
        --nvmtl-bin) NVMTL_BIN="${2:?missing NVMTLDriver path}"; shift 2 ;;
        --policy) POLICY_SRC="${2:?missing policy file}"; shift 2 ;;
        --nvrm-kext) NVRM_KEXT="${2:?missing NVRM.kext path}"; shift 2 ;;
        --no-auto-hdmi-daemon) AUTO_HDMI_DAEMON=0; shift ;;
        --passwordless-gui) PASSWORDLESS_GUI=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: Run this script directly on the Hackintosh (macOS)." >&2; exit 1; }
[[ -f "$NVMTL_BIN" ]] || { echo "ERROR: Patched NVMTLDriver not found at: $NVMTL_BIN (run 03-build-optimus-patches.sh first)." >&2; exit 1; }
[[ -f "$POLICY_SRC" ]] || { echo "ERROR: Policy file not found at: $POLICY_SRC" >&2; exit 1; }

if [[ -z "$RELEASE_DIR" && "$PATCH_ONLY" -eq 0 ]]; then
    echo "ERROR: Specify --release-dir <unpacked NullMoth package> or --patch-only." >&2
    usage
    exit 1
fi

echo "==> Requesting sudo once for /Library installation..."
sudo -v
( while true; do sleep 45; sudo -n true 2>/dev/null || exit 0; done ) </dev/null >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID="$!"

# 1. Protect Intel UHD 630 WindowServer session from wsreset
sudo mkdir -p /Library/NullMoth
sudo touch /Library/NullMoth/no-wsreset
sudo chown root:wheel /Library/NullMoth/no-wsreset
sudo chmod 644 /Library/NullMoth/no-wsreset
echo "==> Installed /Library/NullMoth/no-wsreset guard."

# 2. Optional fresh NullMoth base installation (never pass NM_PRIMARY_GPU=1 on hybrid laptop)
if [[ -n "$RELEASE_DIR" ]]; then
    [[ -f "$RELEASE_DIR/install.sh" ]] || { echo "ERROR: $RELEASE_DIR/install.sh not found." >&2; exit 1; }
    echo "==> Running NullMoth base installer from $RELEASE_DIR..."
    sudo env -u NM_PRIMARY_GPU bash "$RELEASE_DIR/install.sh" --payload "$RELEASE_DIR"
fi

BUNDLE_DIR="/Library/GPUBundles/NVMTLDriver.bundle"
TARGET_BIN="$BUNDLE_DIR/Contents/MacOS/NVMTLDriver"
POLICY_DST="/Library/GPUBundles/nvmtl-gpu-policy.txt"

[[ -d "$BUNDLE_DIR/Contents/MacOS" ]] || {
    echo "ERROR: $BUNDLE_DIR missing. Install a NullMoth release package via --release-dir first." >&2
    exit 1
}

STAMP="$(date +%Y-%m-%d_%H%M%S)"
BAK_DIR="/Library/NullMoth/optimus-backup-${STAMP}"
sudo mkdir -p "$BAK_DIR"
echo "==> Backing up current NVMTLDriver.bundle & policy -> $BAK_DIR"
sudo ditto "$BUNDLE_DIR" "$BAK_DIR/NVMTLDriver.bundle"
[[ ! -e "$POLICY_DST" ]] || sudo cp -p "$POLICY_DST" "$BAK_DIR/"

# 3. Replace NVMTLDriver binary inside NVMTLDriver.bundle, preserve sibling dylibs/tools, re-seal
echo "==> Installing patched NVMTLDriver into $BUNDLE_DIR..."
sudo cp "$NVMTL_BIN" "$TARGET_BIN"
sudo xattr -dr com.apple.quarantine "$BUNDLE_DIR" /Library/GPUBundles/nvmtl 2>/dev/null || true
sudo chown -R root:wheel "$BUNDLE_DIR"
sudo chmod 755 "$TARGET_BIN"
sudo chmod -R go-w,a+rX "$BUNDLE_DIR"
sudo codesign --force --sign - "$BUNDLE_DIR"
sudo codesign --verify --strict "$BUNDLE_DIR"

# 4. Install policy file (root:wheel 0644 required by NVMTLDevice.m security check)
echo "==> Installing $POLICY_DST (root:wheel, 0644)..."
sudo cp "$POLICY_SRC" "$POLICY_DST"
sudo xattr -d com.apple.quarantine "$POLICY_DST" 2>/dev/null || true
sudo chown root:wheel "$POLICY_DST"
sudo chmod 644 "$POLICY_DST"

# 4b. Install nitro-gpu-ctl helper, optional Auto-HDMI LaunchDaemon, and NitroGPU.app
if [[ -f "$CTL_SRC" ]]; then
    echo "==> Installing /Library/NullMoth/nitro-gpu-ctl..."
    sudo cp "$CTL_SRC" /Library/NullMoth/nitro-gpu-ctl
    sudo chown root:wheel /Library/NullMoth/nitro-gpu-ctl
    sudo chmod 755 /Library/NullMoth/nitro-gpu-ctl

    PLIST_DST="/Library/LaunchDaemons/com.nullmoth.nitro-hdmi-watch.plist"
    if [[ "$AUTO_HDMI_DAEMON" -eq 1 ]]; then
        echo "==> Installing Auto-HDMI LaunchDaemon ($PLIST_DST)..."
        sudo tee "$PLIST_DST" >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.nullmoth.nitro-hdmi-watch</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Library/NullMoth/nitro-gpu-ctl</string>
		<string>watch-hdmi</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ThrottleInterval</key>
	<integer>10</integer>
</dict>
</plist>
PLIST
        sudo chown root:wheel "$PLIST_DST"
        sudo chmod 644 "$PLIST_DST"
        sudo launchctl bootout system/com.nullmoth.nitro-hdmi-watch 2>/dev/null || true
        sudo launchctl bootstrap system "$PLIST_DST" 2>/dev/null || sudo launchctl load -w "$PLIST_DST" 2>/dev/null || true
    fi

    if [[ "$PASSWORDLESS_GUI" -eq 1 ]]; then
        SUDOERS_TMP="/tmp/nitro-gpu-ctl-sudoers-$$"
        printf '%s ALL=(root) NOPASSWD: /Library/NullMoth/nitro-gpu-ctl *\n' "$(id -un)" > "$SUDOERS_TMP"
        if visudo -cf "$SUDOERS_TMP" >/dev/null 2>&1; then
            sudo cp "$SUDOERS_TMP" /etc/sudoers.d/nitro-gpu-ctl
            sudo chown root:wheel /etc/sudoers.d/nitro-gpu-ctl
            sudo chmod 440 /etc/sudoers.d/nitro-gpu-ctl
            echo "==> Enabled scoped passwordless sudo for /Library/NullMoth/nitro-gpu-ctl"
        fi
        rm -f "$SUDOERS_TMP"
    fi
fi

if [[ -d "$APP_SRC/Contents/MacOS" ]]; then
    echo "==> Installing /Applications/NitroGPU.app..."
    sudo rm -rf /Applications/NitroGPU.app
    sudo ditto "$APP_SRC" /Applications/NitroGPU.app
    sudo xattr -dr com.apple.quarantine /Applications/NitroGPU.app 2>/dev/null || true
    sudo chown -R root:wheel /Applications/NitroGPU.app
    sudo chmod -R go-w,a+rX /Applications/NitroGPU.app
fi

# 5. Verify _windowserver can read both bundle and policy
echo "==> Verifying _windowserver read access..."
sudo su -m _windowserver -c "test -r '$TARGET_BIN' && test -r '$POLICY_DST'"

# 6. Optional RTD3-patched NVRM.kext replacement + kmutil rebuild
if [[ -n "$NVRM_KEXT" ]]; then
    [[ -d "$NVRM_KEXT/Contents/MacOS" ]] || { echo "ERROR: Invalid NVRM.kext: $NVRM_KEXT" >&2; exit 1; }
    echo "==> Installing patched NVRM.kext into /Library/Extensions/NVRM.kext..."
    if [[ -d /Library/Extensions/NVRM.kext ]]; then
        sudo ditto /Library/Extensions/NVRM.kext "$BAK_DIR/NVRM.kext"
        sudo rm -rf /Library/Extensions/NVRM.kext
    fi
    sudo ditto "$NVRM_KEXT" /Library/Extensions/NVRM.kext
    sudo chown -R root:wheel /Library/Extensions/NVRM.kext
    sudo chmod -R go-w,a+rX /Library/Extensions/NVRM.kext
    sudo codesign --force --sign - /Library/Extensions/NVRM.kext
    sudo codesign --verify --strict /Library/Extensions/NVRM.kext

    echo "==> Rebuilding Auxiliary Kernel Collection via kmutil..."
    K_OPT=()
    [[ -f /System/Library/Kernels/kernel ]] && K_OPT=(--kernel /System/Library/Kernels/kernel)
    sudo kmutil install --volume-root / --update-all --collection-format kc --allow-missing-kdk "${K_OPT[@]}"
fi

echo "DONE: NullMoth Optimus installation complete. Reboot using your USB test EFI first."
