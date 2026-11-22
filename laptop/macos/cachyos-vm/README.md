# CachyOS (real disk) in VMware Fusion on the Hackintosh

Boots the laptop's own CachyOS install (WD SN530) inside VMware Fusion 25 from native macOS, so Linux is usable
without rebooting. No GPU in the VM (the GTX 1650 has no macOS driver and cannot be passed through on macOS);
for GPU work, reboot into CachyOS.

Why VMware: `open-vm-tools` is in the CachyOS repos (no out-of-tree module to rebuild on kernel updates),
`vmwgfx` gives 3D, nested VT-x is available. Parallels Tools must be rebuilt for every CachyOS kernel; UTM has
no nested virtualization.

Safety: macOS renumbers disks between boots (disk0/disk1 swapped on 2026-11-22), so `cachyos-vm` finds the SN530
by model, refuses a disk with APFS/HFS or the boot disk, unmounts anything macOS mounted on it, and rebuilds the
raw-disk descriptor on every start. Never run the VM while CachyOS is hibernated, and never boot CachyOS natively
while the VM runs.

Setup (Hackintosh, once): `bash setup.sh`. Start: `cachyos-vm`. Stop: `cachyos-vm stop`.
Guest prep (in CachyOS, once): `open-vm-tools` enabled, `nofail` on every non-root fstab entry, limine fallback
`EFI/BOOT/BOOTX64.EFI` present, no hibernation.
