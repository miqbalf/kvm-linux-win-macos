#!/usr/bin/env bash
# Clone NullMoth upstream at a pinned commit, apply Optimus + RTD3 patches,
# run unit tests, compile x86_64 NVMTLDriver, build SSDT-NXRTD3.aml, and
# optionally build patched NVRM.kext when open-gpu-kernel-modules 620.70.06 is supplied.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HACKINTOSH_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$HACKINTOSH_DIR/patches"
WORK_DIR="$HACKINTOSH_DIR/work"
OUT_DIR="$HACKINTOSH_DIR/out"

PINNED_COMMIT="45040e97f705e7de684f8dac45ff71ade72a31ba"
NULLMOTH_REPO="https://github.com/nullmoth/nvidia-macos-driver.git"
VK_HEADERS_REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"

OGKM_SRC=""
CLEAN_WORK=0
NO_FETCH=0

usage() {
    cat <<'EOF'
Usage: 03-build-optimus-patches.sh [options]

Options:
  --ogkm <dir>   Path to pristine NVIDIA open-gpu-kernel-modules (620.70.06) tree
                 to also build patched NVRM.kext with RTD3 4-char method support
  --clean        Reset work/nvidia-macos-driver and out/ before building
  --no-fetch     Use existing clones in work/ without network access
  -h, --help     Show help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ogkm) OGKM_SRC="${2:?missing directory for --ogkm}"; shift 2 ;;
        --clean) CLEAN_WORK=1; shift ;;
        --no-fetch) NO_FETCH=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

mkdir -p "$WORK_DIR" "$OUT_DIR"
NM_DIR="$WORK_DIR/nvidia-macos-driver"
VK_DIR="$WORK_DIR/Vulkan-Headers"

if [[ "$CLEAN_WORK" -eq 1 ]]; then
    rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"
    if [[ -d "$NM_DIR/.git" ]]; then
        git -C "$NM_DIR" reset --hard HEAD
        git -C "$NM_DIR" clean -fdx
    fi
fi

if [[ ! -d "$NM_DIR/.git" ]]; then
    if [[ "$NO_FETCH" -eq 1 ]]; then
        echo "ERROR: $NM_DIR missing and --no-fetch set." >&2
        exit 1
    fi
    echo "==> Cloning nullmoth/nvidia-macos-driver..."
    git clone "$NULLMOTH_REPO" "$NM_DIR"
fi

echo "==> Checking out pinned commit $PINNED_COMMIT..."
if ! git -C "$NM_DIR" cat-file -e "${PINNED_COMMIT}^{commit}" 2>/dev/null; then
    [[ "$NO_FETCH" -eq 0 ]] || { echo "ERROR: Commit $PINNED_COMMIT not present locally." >&2; exit 1; }
    git -C "$NM_DIR" fetch origin
fi
git -C "$NM_DIR" checkout -f "$PINNED_COMMIT"
git -C "$NM_DIR" clean -fd

if [[ ! -d "$VK_DIR/include/vulkan" ]]; then
    if [[ "$NO_FETCH" -eq 1 ]]; then
        echo "ERROR: $VK_DIR/include/vulkan missing and --no-fetch set." >&2
        exit 1
    fi
    echo "==> Cloning KhronosGroup/Vulkan-Headers (shallow)..."
    git clone --depth 1 "$VK_HEADERS_REPO" "$VK_DIR"
fi

echo "==> Applying Optimus & RTD3 patches..."
for p in \
    "$PATCH_DIR/0001-optimus-policy-native-igpu-headless.patch" \
    "$PATCH_DIR/0002-rtd3-4char-acpi-method.patch"; do
    echo "    applying $(basename "$p")"
    git -C "$NM_DIR" apply "$p"
done

echo "==> Running unit tests..."
cc -Wall -Wextra -I"$NM_DIR/plugin" "$NM_DIR/tools/test_gpu_policy.c" -o "$OUT_DIR/test_gpu_policy"
"$OUT_DIR/test_gpu_policy"
python3 "$NM_DIR/tools/test_nv_rtd3_policy.py" "$NM_DIR"

echo "==> Building x86_64 patched NVMTLDriver..."
xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 \
    -Wno-protocol -Wno-incomplete-implementation -Werror=unguarded-availability-new \
    -I"$VK_DIR/include" \
    -o "$OUT_DIR/NVMTLDriver" \
    "$NM_DIR/plugin/NVMTLDevice.m" \
    "$NM_DIR/plugin/nvmtl_dlss.c" \
    "$NM_DIR/plugin/dlss/elfhost.c" \
    "$NM_DIR/plugin/dlss/lnxlibc.c" \
    -framework Foundation -framework Metal -framework IOSurface -framework IOKit -framework CoreFoundation -framework MetalFX -liconv
codesign -f -s - "$OUT_DIR/NVMTLDriver"

echo "==> Syntax-checking x86_64 kernel RTD3 unit..."
SDK_PATH="$(xcrun --show-sdk-path)"
KHDR="$SDK_PATH/System/Library/Frameworks/Kernel.framework/Headers"
RE_HDR="$NM_DIR/kexts/NVRM/accel/re"
xcrun clang++ -arch x86_64 -fsyntax-only -fapple-kext -mkernel -nostdinc \
    -I"$KHDR" -I"$NM_DIR/kexts/NVRM" -I"$RE_HDR" \
    "$NM_DIR/kexts/NVRM/nv_rtd3.cpp"

echo "==> Generating SSDT-NXRTD3.aml and staging policy template..."
python3 "$HACKINTOSH_DIR/opencore/acpi/build-rtd3-aml.py" -o "$OUT_DIR/SSDT-NXRTD3.aml"
cp "$HACKINTOSH_DIR/opencore/nvmtl-gpu-policy.txt" "$OUT_DIR/nvmtl-gpu-policy.txt"

echo "==> Building NitroGPU.app and NitroGPU-Switcher.dmg..."
bash "$HACKINTOSH_DIR/app/build-app.sh" "$OUT_DIR"

if [[ -n "$OGKM_SRC" ]]; then
    if [[ ! -d "$OGKM_SRC/src/nvidia" ]]; then
        echo "ERROR: Invalid open-gpu-kernel-modules directory: $OGKM_SRC" >&2
        exit 1
    fi
    echo "==> Building patched NVRM.kext against OGKM tree: $OGKM_SRC..."
    RM_WORK="$WORK_DIR/rm620"
    mkdir -p "$RM_WORK"
    bash "$NM_DIR/build/build_rm620.sh" "$RM_WORK" "$OGKM_SRC"
    bash "$NM_DIR/build/build_kms620.sh" "$RM_WORK"
    bash "$NM_DIR/build/build_nvrm.sh" "$NM_DIR/kexts/NVRM" "$RM_WORK/ogkm-${NV_VERSION:-620.70.06}" "$OUT_DIR/nvrm-build"
    echo "    Built NVRM.kext -> $OUT_DIR/nvrm-build/NVRM.kext"
else
    echo "NOTE: Skipped NVRM.kext build (pass --ogkm <open-gpu-kernel-modules-620.70.06> to build it)."
fi

echo "==> Output summary in $OUT_DIR:"
ls -lh "$OUT_DIR"
