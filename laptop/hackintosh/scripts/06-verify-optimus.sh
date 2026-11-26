#!/usr/bin/env bash
# Read-only health verification for NullMoth Optimus offload on Hackintosh (macOS).
set -euo pipefail

WITH_SUDO=0
if [[ "${1:-}" == "--with-sudo" ]]; then
    WITH_SUDO=1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: Run this verification script on the Hackintosh (macOS)." >&2
    exit 1
fi

echo "=== 1. OS & Boot Args ==="
sw_vers
echo -n "boot-args: "
nvram boot-args 2>/dev/null || echo "<unset>"
echo -n "csr-active-config: "
nvram csr-active-config 2>/dev/null || echo "<unset>"

echo
echo "=== 2. Display & GPU Topology (SPDisplaysDataType) ==="
system_profiler SPDisplaysDataType | sed -n '/Graphics\/Displays:/,$p'

echo
echo "=== 3. Loaded Framebuffer & NullMoth Kexts ==="
kmutil showloaded 2>/dev/null | grep -E 'AppleIntel|IONDRV|nullmoth|NVRM|NVAccel|NMX' || echo "<none matched>"

echo
echo "=== 4. NullMoth Sysctls (headless / flip / RTD3 / hybrid) ==="
sysctl -a 2>/dev/null | grep -E '^(debug\.(nv|nm)|hw\.nv)' || echo "<no NullMoth sysctls active>"

echo
echo "=== 5. PCI Visibility of NVIDIA dGPU (vendor 10de) ==="
ioreg -r -p IODeviceTree -c IOPCIDevice -l -w0 2>/dev/null | grep -A3 -E '"vendor-id" = <de100000>|"IOName" = "display"' | head -n 40 || true

echo
echo "=== 6. Policy, Bundle Seal & no-wsreset Guard ==="
for p in /Library/NullMoth/no-wsreset /Library/GPUBundles/nvmtl-gpu-policy.txt /Library/GPUBundles/NVMTLDriver.bundle; do
    if [[ -e "$p" ]]; then
        ls -ld "$p"
    else
        echo "MISSING: $p"
    fi
done
if [[ -d /Library/GPUBundles/NVMTLDriver.bundle ]]; then
    codesign --verify --strict /Library/GPUBundles/NVMTLDriver.bundle && echo "codesign verify: OK" || echo "codesign verify: FAILED"
fi

if [[ "$WITH_SUDO" -eq 1 ]]; then
    echo
    echo "=== 7. _windowserver Read Access Check ==="
    sudo su -m _windowserver -c 'test -r /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver && test -r /Library/GPUBundles/nvmtl-gpu-policy.txt && echo "_windowserver readability: OK"'
fi

echo
echo "=== 8. Recent Kernel / Metal Policy Logs (last 10m) ==="
log show --last 10m --predicate 'eventMessage CONTAINS "gpu policy" OR eventMessage CONTAINS "nvrm" OR eventMessage CONTAINS "rtd3" OR eventMessage CONTAINS "NVMTL"' 2>/dev/null | tail -n 30 || true
