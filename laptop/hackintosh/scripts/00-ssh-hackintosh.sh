#!/usr/bin/env bash
# Sync hackintosh scripts, patches, and configs to ~/hackintosh-optimus on the
# Hackintosh and open an interactive SSH shell directly inside that folder.
#
# Use this when you want to SSH into the Hackintosh first and run commands
# natively with normal interactive sudo.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HACKINTOSH_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

HACKINTOSH_SSH="${HACKINTOSH_SSH:-nitro-mac}"
REMOTE_DIR="hackintosh-optimus"
PULL_AFTER=0
SSH_CTL="/tmp/oc-shell-ctl-$$"
SSH_OPTS=(
    -o "ControlMaster=auto"
    -o "ControlPath=$SSH_CTL"
    -o "ControlPersist=120"
)

cleanup() {
    ssh -O exit -o "ControlPath=$SSH_CTL" "$HACKINTOSH_SSH" >/dev/null 2>&1 || true
    rm -f "$SSH_CTL" 2>/dev/null || true
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: 00-ssh-hackintosh.sh [--host <ssh-host-or-user@ip>] [--pull-after]

Options:
  --host <target>  SSH target (default: $HACKINTOSH_SSH or "nitro-mac")
  --pull-after     When you exit the Hackintosh shell, run 02-sync-efi-to-repo.sh --pull-only
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) HACKINTOSH_SSH="$2"; shift 2 ;;
        --pull-after) PULL_AFTER=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

echo "==> Syncing scripts, patches, and configs to ${HACKINTOSH_SSH}:~/${REMOTE_DIR}/ ..."
rsync -az --delete \
    -e "ssh -o ControlMaster=auto -o ControlPath=$SSH_CTL -o ControlPersist=120" \
    --exclude='efi-backup/' \
    --exclude='work/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    "$HACKINTOSH_DIR/README.md" \
    "$HACKINTOSH_DIR/app" \
    "$HACKINTOSH_DIR/opencore" \
    "$HACKINTOSH_DIR/patches" \
    "$HACKINTOSH_DIR/scripts" \
    "${HACKINTOSH_SSH}:~/${REMOTE_DIR}/"

if [[ -d "$HACKINTOSH_DIR/out" ]]; then
    echo "==> Also syncing existing out/ build artifacts..."
    rsync -az -e "ssh -o ControlPath=$SSH_CTL" \
        "$HACKINTOSH_DIR/out" "${HACKINTOSH_SSH}:~/${REMOTE_DIR}/"
fi

echo "==> Opening interactive SSH shell on ${HACKINTOSH_SSH} in ~/${REMOTE_DIR}..."
ssh -t "${SSH_OPTS[@]}" "$HACKINTOSH_SSH" '
cd "$HOME/'"$REMOTE_DIR"'" || exit 1
cat <<BANNER

==================================================================
 Connected to Hackintosh: $(hostname) ($(sw_vers -productVersion 2>/dev/null || uname -s))
 Working dir: $PWD
------------------------------------------------------------------
 Quick commands (run in order; sudo will prompt cleanly here):
   1) Back up live ESP : ./scripts/01-backup-efi.sh
   2) Build patches    : ./scripts/03-build-optimus-patches.sh
   3) Install NullMoth : ./scripts/05-install-nullmoth-optimus.sh --release-dir /path/to/NullMoth-3.1
      (or patch only)  : ./scripts/05-install-nullmoth-optimus.sh --patch-only
   4) Prep USB test EFI: ./scripts/04-prepare-usb-test-efi.sh --efi-src "$HOME/efi-backup-latest/EFI" --disk diskX
   5) Verify after boot: ./scripts/06-verify-optimus.sh --with-sudo
   Type "exit" when done.
==================================================================

BANNER
exec "${SHELL:-/bin/zsh}" -l
'

if [[ "$PULL_AFTER" -eq 1 ]]; then
    echo "==> Pulling latest EFI backup back into repo (gitignored) and refreshing config-sanitized.plist..."
    "$SCRIPT_DIR/02-sync-efi-to-repo.sh" --host "$HACKINTOSH_SSH" --pull-only
fi
