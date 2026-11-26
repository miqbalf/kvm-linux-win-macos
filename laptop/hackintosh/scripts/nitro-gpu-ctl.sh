#!/usr/bin/env bash
# Scoped privileged helper for Nitro 5 Optimus switching and Auto-HDMI arming.
# Installed at /Library/NullMoth/nitro-gpu-ctl (root:wheel, 0755).
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

POLICY="/Library/GPUBundles/nvmtl-gpu-policy.txt"

current_mode() {
    if [[ -f "$POLICY" ]]; then
        local m
        m="$(awk '/^[[:space:]]*mode[[:space:]]+/{v=$2} END{print v}' "$POLICY" 2>/dev/null || true)"
        case "$m" in
            apple|nvidia|igpu) echo "$m"; return 0 ;;
        esac
    fi
    echo "apple"
}

arm_hdmi() {
    local heads armed piped
    heads="$(sysctl -n debug.nvaccel_heads_published 2>/dev/null || echo 0)"
    armed="$(sysctl -n debug.nvaccelfb 2>/dev/null || echo 0)"
    piped="$(sysctl -n debug.nvaccel_heads_piped 2>/dev/null || echo 0)"
    if [[ "${heads:-0}" == "0" ]]; then
        echo "No active NVIDIA display head published yet (heads=0). Make sure HDMI is connected and nvfbhotplugpoll=2 is set."
        return 0
    fi
    if [[ "${armed:-0}" != "0" ]] && (( (heads & ~piped) == 0 )); then
        sysctl -w debug.nvrmfb_agdc_k5=1 >/dev/null || true
        sysctl -w debug.nvrmfb_agdc=1 >/dev/null || true
        sysctl -w debug.nvaccel_iop=1 >/dev/null || true
        echo "NVIDIA display pipe already armed (heads=${heads}, piped=${piped}, nvaccelfb=${armed})."
        return 0
    fi
    echo "Arming hot-plugged NVIDIA display head (heads=${heads}, piped=${piped}, nvaccelfb=${armed})..."
    if [[ "${armed:-0}" == "0" ]]; then
        sysctl -w debug.nvaccelfb=1 >/dev/null || true
        sleep 1
        sysctl -w debug.nvaccelfb=4 >/dev/null || true
    else
        sysctl -w debug.nvaccelfb=3 >/dev/null || true
        sleep 1
    fi
    sysctl -w debug.nvrmfb_agdc_k5=1 >/dev/null || true
    sysctl -w debug.nvrmfb_agdc=1 >/dev/null || true
    sysctl -w debug.nvaccel_iop=1 >/dev/null || true
    echo "Armed: heads=$(sysctl -n debug.nvaccel_heads_published 2>/dev/null || echo 0) piped=$(sysctl -n debug.nvaccel_heads_piped 2>/dev/null || echo 0) nvaccelfb=$(sysctl -n debug.nvaccelfb 2>/dev/null || echo 0)"
}

activate_hdmi() {
    arm_hdmi
    local heads
    heads="$(sysctl -n debug.nvaccel_heads_published 2>/dev/null || echo 0)"
    if [[ "${heads:-0}" == "0" ]]; then
        echo "Cannot activate HDMI display: no monitor detected yet (heads=0)."
        return 1
    fi
    if ioreg -r -c NVRMNVDAFramebuffer -l -w0 2>/dev/null | grep -q '"IOUserClientCreator".*WindowServer'; then
        echo "WindowServer already attached to NVRMFramebuffer."
        return 0
    fi
    echo "Restarting WindowServer so macOS attaches to the hot-plugged HDMI display..."
    launchctl kickstart -k system/com.apple.WindowServer || killall -9 WindowServer
}

set_mode() {
    local new_mode="$1"
    case "$new_mode" in
        apple|nvidia|igpu) ;;
        *) echo "Invalid mode: $new_mode (expected apple|nvidia|igpu)" >&2; exit 2 ;;
    esac

    mkdir -p /Library/GPUBundles
    if [[ ! -f "$POLICY" ]]; then
        cat > "$POLICY" <<EOF
mode ${new_mode}

igpu WindowServer
igpu Dock
igpu Finder
igpu loginwindow
igpu SystemUIServer
EOF
    else
        /usr/bin/python3 - "$POLICY" "$new_mode" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]
text = path.read_text()
updated, n = re.subn(r"(?m)^([ \t]*mode[ \t]+)\S+.*$", rf"\g<1>{mode}", text, count=1)
if n == 0:
    updated = f"mode {mode}\n\n" + text
path.write_text(updated)
PY
    fi
    chown root:wheel "$POLICY"
    chmod 644 "$POLICY"
    echo "GPU policy mode set to: $new_mode"
}

watch_hdmi() {
    # Lightweight watcher for Auto-HDMI hotplug: waits until nvfbhotplugpoll
    # brings up an NVIDIA head on an unplugged boot, then arms nvaccelfb.
    while true; do
        sleep 3
        heads="$(sysctl -n debug.nvaccel_heads_published 2>/dev/null || echo -1)"
        [[ "$heads" == "-1" ]] && exit 0
        if [[ "$heads" != "0" ]]; then
            armed="$(sysctl -n debug.nvaccelfb 2>/dev/null || echo 0)"
            piped="$(sysctl -n debug.nvaccel_heads_piped 2>/dev/null || echo 0)"
            if [[ "$armed" == "0" ]] || (( (heads & ~piped) != 0 )); then
                arm_hdmi >/dev/null 2>&1 || true
            fi
        fi
    done
}

show_status() {
    local mode headless nvaccelfb heads bootargs poll
    mode="$(current_mode)"
    headless="$(sysctl -n debug.nvaccel_headless 2>/dev/null || echo 0)"
    nvaccelfb="$(sysctl -n debug.nvaccelfb 2>/dev/null || echo 0)"
    heads="$(sysctl -n debug.nvaccel_heads_published 2>/dev/null || echo 0)"
    bootargs="$(nvram boot-args 2>/dev/null || true)"
    poll="0"
    if [[ "$bootargs" =~ nvfbhotplugpoll=([0-9]+) ]]; then
        poll="${BASH_REMATCH[1]}"
    fi
    printf 'mode=%s\nheadless=%s\nnvaccelfb=%s\nheads=%s\nhotplug_poll=%s\n' \
        "$mode" "$headless" "$nvaccelfb" "$heads" "$poll"
}

cmd="${1:-status}"
case "$cmd" in
    status) show_status ;;
    set)
        [[ $# -eq 2 ]] || { echo "Usage: nitro-gpu-ctl set <apple|nvidia|igpu>" >&2; exit 2; }
        set_mode "$2"
        ;;
    arm-hdmi) arm_hdmi ;;
    activate-hdmi) activate_hdmi ;;
    watch-hdmi) watch_hdmi ;;
    *)
        echo "Usage: nitro-gpu-ctl <status | set <apple|nvidia|igpu> | arm-hdmi | activate-hdmi | watch-hdmi>" >&2
        exit 2
        ;;
esac
