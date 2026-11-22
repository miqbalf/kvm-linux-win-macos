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

## First start and remote use (tested 2026-11-22)
- VMware asks for an admin password before it opens the raw disk. That dialog needs a desktop login: from SSH
  only, macOS refuses to create the authorization (`IdAuthCreateWithFork: child AuthorizationCreate() failed:
  -60008`) and the start ends with "The operation was canceled". Changing the `com.vmware.diskhelper.open`
  authorization right does not help. Start the VM from Terminal on the laptop's desktop (or through Screen
  Sharing). The launcher starts it headless (`nogui`) when there is no desktop session, but then the raw disk
  cannot be opened.
- Open VMware Fusion once by hand first, to finish its first-run setup.
- The vmx needs the PCIe bridges (`pciBridge0`, `pciBridge4`-`7`), otherwise `vmxnet3` fails with "No PCIe slot
  available for Ethernet0". If a start failed before, delete the `*.pciSlotNumber` lines VMware wrote into the vmx.
- Screen Sharing from another Mac: if Remote Management is on, the user must be on its access list, otherwise the
  login fails with a "wrong password" message (log: `remote management`, `not valid admin`):
  `sudo .../ARDAgent.app/Contents/Resources/kickstart -configure -access -on -users <user> -privs -all -restart -agent`.
- Guest IP: `cachyos-vm ip` (VMware NAT, 172.16.x.x). From another machine: `ssh -J <user>@<laptop> <user>@<guest-ip>`.
- In the VM, `libvirtd` and `linuwu_sense` fail (no KVM-capable nested setup, no Acer EC): harmless.
