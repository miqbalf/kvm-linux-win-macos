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

## Seamless Linux apps ("coherence", 2026-11-22)
Fusion's Unity mode supports only Windows guests, so Linux apps are shown with xpra (guest: `pacman -S xpra`,
Mac: Xpra.app from xpra.org). Install on the Hackintosh desktop: `bash install-coherence.sh`.
- `linux-app <cmd>`: unpauses/starts the VM, opens the app as a Mac window. `linux-app attach`, `linux-app stop`.
- `linux-apps-sync`: one Mac app per guest `.desktop` entry in `~/Applications/CachyOS Apps` (icons included).
- `cachyos-vm-idle` (LaunchAgent): pauses the VM after 15 min with no xpra windows. Pause, not suspend: VMware
  keeps the raw disk, so nothing gets remounted in macOS and unpausing needs no password.
- `cachyos-vm-guard` (LaunchAgent): clean guest shutdown when macOS shuts down/restarts/logs out, so a native
  CachyOS boot is always safe; warns at login if a suspended state exists.
- `guest-fix-boot.sh` (run once in CachyOS): `/boot` automount with 60 s idle unmount, Spotlight/fseventsd
  blocked on the ESP, `cachyos-vm-noidle.service` (idle-sleep inhibitor only under VMware).
- ssh alias `cachyos-vm` uses a passphrase-less key `~/.ssh/cachyos_vm` (guest reachable only via VMware NAT).

Incident 2026-11-22: after a suspend, VMware's MountHelper mounted the guest's `/boot` (FAT) in macOS while the
suspended guest still had it mounted. macOS's FAT driver looped (`cluster 13084 is free where it should be in
use`, 2.4 million log lines in 13 min) and froze the Mac; `fsck_msdos -y` repaired it (only macOS Spotlight files
were damaged). Hence: no suspend, `release_disk` after stop, `/boot` automount in the guest.
VM size 4 vCPU / 8 GB (6 vCPU / 16 GB made suspend take 70 s and loaded the host).
