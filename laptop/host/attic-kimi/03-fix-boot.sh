#!/bin/bash
# 03-fix-boot.sh - finish IOMMU + vfio boot setup on CachyOS/Limine, idempotently.
# Handles: limine-entry-tool regenerating limine.conf, and Limine booting a hashed-path
# initramfs that mkinitcpio -P does not update.
# Run: sudo bash laptop/host/03-fix-boot.sh   -> reboot -> sudo bash laptop/host/02-verify.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
STAMP=$(date +%Y%m%d-%H%M%S)

echo "== current state (uptime proves whether a reboot happened) =="
uptime -p
cat /proc/cmdline

echo; echo "== 1/5 modprobe: vfio claims GTX 1650, nvidia blacklisted on host =="
cat > /etc/modprobe.d/vfio-pci.conf <<'EOF'
options vfio-pci ids=10de:1f99,10de:10fa
EOF
cat > /etc/modprobe.d/blacklist-nvidia-vm.conf <<'EOF'
blacklist nvidia
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nvidia_drm
EOF
echo done

echo; echo "== 2/5 mkinitcpio MODULES =="
grep -q '^MODULES=(vfio_pci)' /etc/mkinitcpio.conf || {
  cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak-$STAMP"
  sed -i 's/^MODULES=()/MODULES=(vfio_pci)/' /etc/mkinitcpio.conf
}
grep '^MODULES' /etc/mkinitcpio.conf

echo; echo "== 3/5 rebuild initramfs =="
mkinitcpio -P

echo; echo "== 4/5 limine.conf surgery (cmdline + hashed initramfs path) =="
python3 - <<'PYEOF'
import re, hashlib, shutil, pathlib
conf = pathlib.Path('/boot/limine.conf')
out, copied, hashed = [], 0, 0
for line in conf.read_text().splitlines():
    m = re.match(r'^(\s*module_path:\s*boot\(\):)(\S+)#([0-9a-f]{64})\s*$', line)
    if m:
        pre, path, oldh = m.groups()
        kernel = pathlib.PurePosixPath(path).parent.name
        src = pathlib.Path('/boot') / f'initramfs-{kernel}.img'
        dst = pathlib.Path('/boot') / path.lstrip('/')
        if not dst.exists():
            alt = pathlib.Path('/boot') / (path.lstrip('/') + '#' + oldh)
            if alt.exists():
                dst = alt
        if src.exists() and dst.exists():
            if not src.samefile(dst) and src.read_bytes() != dst.read_bytes():
                shutil.copyfile(src, dst); copied += 1
            newh = hashlib.sha256(dst.read_bytes()).hexdigest()
            if newh != oldh:
                line = f'{pre}{path}#{newh}'; hashed += 1
    if re.match(r'^\s*cmdline:', line) and 'intel_iommu=on' not in line:
        line = line.replace(' splash ', ' splash intel_iommu=on iommu=pt ')
    out.append(line)
shutil.copyfile(conf, f'{conf}.bak-{__import__("datetime").datetime.now():%Y%m%d-%H%M%S}')
conf.write_text('\n'.join(out) + '\n')
print(f'initramfs files refreshed: {copied}, hash suffixes updated: {hashed}')
PYEOF

echo; echo "== 5/5 /etc/kernel/cmdline (for tools that regenerate the conf from it) =="
grep -m1 '^  cmdline: quiet nowatchdog splash intel_iommu=on iommu=pt rw ' /boot/limine.conf | sed 's/^  cmdline: //' > /etc/kernel/cmdline
cat /etc/kernel/cmdline

echo; echo "== summary =="
echo -n "limine.conf cmdline lines with intel_iommu=on: "; grep -c 'intel_iommu=on' /boot/limine.conf || true
lsinitcpio -m /boot/initramfs-linux-cachyos.img 2>/dev/null | grep -qx vfio_pci \
  && echo "initramfs-linux-cachyos contains vfio_pci" || echo "WARN: vfio_pci missing from initramfs-linux-cachyos"
echo
echo 'NEXT: reboot, then: sudo bash laptop/host/02-verify.sh  (paste the output)'
