#!/usr/bin/env bash
# Controller-side helper: trigger remote live EFI backup on the Hackintosh
# (or pull existing efi-backup-latest), store locally under the gitignored
# efi-backup/ folder, and refresh opencore/config-sanitized.plist for git.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HACKINTOSH_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BACKUP_ROOT="$HACKINTOSH_DIR/efi-backup"
REPO_CONFIG_OUT="$HACKINTOSH_DIR/opencore/config-sanitized.plist"

HACKINTOSH_SSH="${HACKINTOSH_SSH:-nitro-mac}"
PULL_ONLY=0
SSH_CTL="/tmp/oc-sync-ctl-$$"
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
Usage: 02-sync-efi-to-repo.sh [--host <ssh-host-or-user@ip>] [--pull-only]

Options:
  --host <target>  SSH target (default: $HACKINTOSH_SSH or "nitro-mac")
  --pull-only      Skip running 01-backup-efi.sh; pull remote ~/efi-backup-latest only
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) HACKINTOSH_SSH="$2"; shift 2 ;;
        --pull-only) PULL_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ "$PULL_ONLY" -eq 0 ]]; then
    if [[ ! -t 0 ]]; then
        echo "NOTE: No local interactive terminal detected; sudo will fail unless passwordless sudo is configured." >&2
    fi
    REMOTE_TMP="/tmp/01-backup-efi-$$.sh"
    echo "==> Uploading 01-backup-efi.sh to ${HACKINTOSH_SSH}:${REMOTE_TMP}..."
    scp -q "${SSH_OPTS[@]}" "$SCRIPT_DIR/01-backup-efi.sh" "${HACKINTOSH_SSH}:${REMOTE_TMP}"

    echo "==> Running 01-backup-efi.sh on ${HACKINTOSH_SSH} with interactive TTY for sudo..."
    if [[ -t 0 ]]; then
        ssh -t "${SSH_OPTS[@]}" "$HACKINTOSH_SSH" "bash '${REMOTE_TMP}'; rc=\$?; rm -f '${REMOTE_TMP}'; exit \$rc"
    else
        ssh "${SSH_OPTS[@]}" "$HACKINTOSH_SSH" "bash '${REMOTE_TMP}'; rc=\$?; rm -f '${REMOTE_TMP}'; exit \$rc"
    fi
fi

REMOTE_LATEST="$(ssh "${SSH_OPTS[@]}" "$HACKINTOSH_SSH" 'if [ -d "$HOME/efi-backup-latest" ]; then (cd -P "$HOME/efi-backup-latest" && pwd -P); else ls -1dt "$HOME"/efi-backup-* 2>/dev/null | head -n1; fi')"
if [[ -z "$REMOTE_LATEST" ]]; then
    echo "ERROR: No ~/efi-backup-* directory found on ${HACKINTOSH_SSH}." >&2
    exit 1
fi

REMOTE_NAME="$(basename "$REMOTE_LATEST")"
LOCAL_DEST="$BACKUP_ROOT/${REMOTE_NAME#efi-backup-}"
mkdir -p "$LOCAL_DEST"

echo "==> Syncing ${HACKINTOSH_SSH}:${REMOTE_LATEST}/ -> $LOCAL_DEST/ ..."
rsync -avh --progress -e "ssh -o ControlPath=$SSH_CTL" "${HACKINTOSH_SSH}:${REMOTE_LATEST}/" "$LOCAL_DEST/"

ln -sfn "$LOCAL_DEST" "$BACKUP_ROOT/latest"

if [[ -f "$LOCAL_DEST/EFI/OC/config.plist" ]]; then
    echo "==> Updating sanitized OpenCore config -> $REPO_CONFIG_OUT"
    python3 "$SCRIPT_DIR/sanitize-config.py" "$LOCAL_DEST/EFI/OC/config.plist" "$REPO_CONFIG_OUT"
else
    echo "WARNING: $LOCAL_DEST/EFI/OC/config.plist not found; skipped sanitization." >&2
fi

echo "DONE: Local backup stored in $LOCAL_DEST (gitignored)."
echo "      Sanitized config updated at $REPO_CONFIG_OUT (safe to commit)."
