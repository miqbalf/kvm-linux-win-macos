# macOS on the laptop

## Daily use
The panel is wired only to the Intel iGPU, so **either Linux or macOS owns the screen, never both**.
Nothing is permanent: a laptop reboot always comes back to Linux.

**Go to macOS**: VM Switch app > macOS > **Start on laptop screen**, or from a terminal (also over SSH):
```
sudo gpu-mode mac
```
- The Linux desktop closes (GDM stops) and the panel goes black for about 30 s.
- OpenCore and the Apple logo appear, then the macOS login screen (about 60-100 s in total).
- Keyboard and touchpad now belong to macOS: tap = click, two-finger tap = right click,
  two-finger move = scroll, pressing the pad = click.
- Leave Linux programs closed or saved first: the desktop session ends.

**Come back to Linux**, any of these:
1. In macOS: Apple menu > **Shut Down**. Linux login returns by itself within about 1 min.
   (macOS hangs at the very end of the shutdown in the VM; a watchdog notices and powers the VM off.)
2. From another machine: `ssh <user>@<laptop> sudo gpu-mode host` (about 40 s; macOS is powered off
   after 30 s, so save open documents in macOS first).
3. From the macOS Terminal: `ssh <user>@192.168.122.1 sudo gpu-mode host`
4. If nothing responds: hold the power button. The laptop reboots into Linux.

Status: `sudo gpu-mode status`. Log: `journalctl -t gpu-mode`.

Rules:
- Do not run `virsh start macos-igpu` by hand; always use `gpu-mode` (it frees the iGPU and starts the
  touchpad bridge first).
- `macos` and `macos-igpu` share one disk overlay: only one of them runs at a time (`gpu-mode` checks).
- If the panel stays black in Linux after coming back: `sudo gpu-mode host` again, else reboot.

### In a window (`macos`)
```
sudo virsh start macos      # 192.168.122.11, VNC 127.0.0.1:5902 (virtual display, no Metal)
sudo virsh shutdown macos
```
VNC from another machine: `ssh -L 5902:127.0.0.1:5902 <user>@<laptop>` then `vnc://127.0.0.1:5902`.
The VNC password is in `/etc/libvirt/vnc-laptop.pass` (root only). Repo XML keeps `CHANGE_ME`.

### How the panel mode works
| Part | File | Why |
|---|---|---|
| Switch script | `host/gpu-mode` | stops GDM, moves 00:02.0 from `i915` to `vfio-pci`, starts `macos-igpu`; back: VM off, `i915`, backlight restore, GDM |
| Auto return | `host/libvirt-hooks/qemu` | when `macos-igpu` stops for any reason, runs `gpu-mode host` |
| Shutdown watchdog | `gpu-mode watchdog` (unit `gpu-mode-watchdog`) | macOS spins on one kernel address after Shut Down; after 20 s with no ping and an unchanged, non-halted RIP, the VM is forced off |
| Touchpad | `host/touchpad-bridge`, `host/udev/62-gpu-mode-touchpad.rules` | raw touchpad is absolute and has no tap-to-click without libinput; the bridge makes a relative uinput mouse with taps and scrolling |
| VM | `vm/macos/macos-igpu.xml` | i440fx machine + `x-igd-legacy-mode=on` (copies the real host bridge/LPC IDs the Intel GOP checks; q35 cannot do this), OpRegion, 64 MB stolen memory, iGPU at guest 00:02.0, USB keyboard + mouse |
| Panel init | `vm/macos/gop-policy/` + Intel GOP from the BIOS | OVMF has no Intel graphics driver. The BIOS's Intel GOP lights the eDP panel before macOS, but only starts when a `PLATFORM_GOP_POLICY` protocol (lid state + VBT) exists; `PlatformGopPolicy.efi` provides it. OpenCore loads both, then connects drivers |
| OpenCore config | `vm/macos/make-vm-config.py --igpu` | iGPU DeviceProperties, `igfxonln=1 -igfxblr amfi=0x80`, no `-v`, PNLF, no picker |

## One-time build
1. Get the Intel GOP driver from this laptop's BIOS (read only; nothing is written to the BIOS):
   ```
   sudo pacman -S flashrom
   sudo flashrom -p internal --ifd -i bios -r bios-region.bin
   python3 -m venv venv && venv/bin/pip install uefi_firmware
   venv/bin/uefi-firmware-parser -b -e -q -o extract bios-region.bin
   grep -rl --include='*.pe' -a "$(printf 'I\0n\0t\0e\0l\0(\0R\0)\0 \0G\0O\0P\0')" extract   # the PE with "Intel(R) GOP Driver"
   ```
   Copy that file to `IntelGopDriver.efi` (BIOS V2.06: file `7755CA7B-...`). It is Intel's binary: not committed.
2. In Linux (host mode), from the repo root:
   ```
   sudo bash laptop/vm/macos/build-igpu-image.sh IntelGopDriver.efi
   ```
   This builds `PlatformGopPolicy.efi` with this laptop's VBT, `igd-gop.rom`, the iGPU `config.plist`, and installs
   `opencore-igpu.img` (previous copy kept as `*.prev`).
3. `sudo bash laptop/host/02-verify.sh`, then `sudo gpu-mode mac`.

## OpenCore for the VMs
`vm/macos/opencore-lt.img` is a VM-only copy of the laptop's EFI (gitignored: holds SMBIOS serials).
Regenerate its config from the real one with `vm/macos/make-vm-config.py` (XML output, laptop ACPI/kexts off,
only OpenRuntime driver), copy into the image (`mount -o loop opencore-lt.img /mnt/ocimg`), then reinstall it
with the setup script. Booting the Hackintosh natively invalidates `nvme1-overlay.qcow2`. `gpu-mode mac` detects this
(fingerprint of the APFS container superblock and checkpoint area, stored in `nvme1-overlay.qcow2.base-fp`) and
recreates the overlay by itself; `sudo gpu-mode new-overlay` does it by hand. A stale overlay looks like OpenCore
"Halting on critical error" with only vCPU0 running (2026-11-22).

## Speed: making the VM boot like the native OpenCore boot (2026-11-22)
Lessons from the native boot ([11-native-macos.md](11-native-macos.md)) applied to the VM:

Done in the repo. Apply to the existing image (only `config.plist` changes, GOP stays):
`sudo bash laptop/vm/macos/update-igpu-config.sh` (or a full `build-igpu-image.sh` rebuild):
- `SetApfsTrimTimeout = 0` (the input config is an old backup with -1: about 50 s of trim on every boot).
- No debug boot-args (`-v keepsyms=1 debug=0x100`) and no OpenCore logging unless `--debug`.

To measure in the guest after a boot (same as native):
```
/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS "spaceman_scan_free_blocks" OR eventMessage CONTAINS "hello, launchd" OR eventMessage CONTAINS "Early boot timed out"'
```
or `hackmon report` (installed on the same macOS, so it also runs in the VM).

- Half the laptop for macOS (both domains, 2026-11-22): 4 vCPUs (`cores='2' threads='2'`) pinned to host
  cores 2-3 (CPUs 2,6,3,7; CPU n and n+4 are siblings), QEMU emulator threads on cores 0-1, 16 GiB RAM
  (was 6 unpinned vCPUs, 12 GiB). Defined domains backed up in `~/vm-xml-backup/` before `virsh define`.

Measured 2026-11-22 (QEMU start to guest kernel / login window / ping), fresh overlay:

| Layout and config | Kernel | Login | Ping (`gpu-mode` log) |
|---|---|---|---|
| 6 vCPU unpinned, 12 GiB, old config (trim -1, debug) | - | - | about 90 s |
| 6 vCPU unpinned, 12 GiB, trim 0, no debug | 15 s | 69 s | 75 s |
| 4 vCPU pinned, 16 GiB, trim 0, no debug (kept) | 5 s | 71 s | 95 s |

Kernel to login is 54-66 s against 49 s native; about 30 s of it is the Bitdefender early-boot wait (also native).
Half the CPUs costs about 20 s until the network is up, as expected for a parallel boot; kept on request so Linux
keeps half the laptop.

Next candidates, to test one at a time and measure (not done yet):
1. (`iothread` is not possible: the disks are SATA, QEMU iothreads need virtio-blk/scsi.)
2. Compare boot and UI speed against the old 6 vCPU layout if 4 pinned vCPUs feel slower.
3. Memory: 12 GB without hugepages now; try transparent hugepages (`always`/`madvise`) before static hugepages
   (static ones take RAM away from Linux and Windows).
4. Disk path: SATA (AHCI) on `machine='pc'`. q35 + a faster controller is possible but changes the PCI layout the
   iGPU DeviceProperties rely on (`PciRoot(0x0)/Pci(0x2,0x0)`): test carefully.
5. The overlay `nvme1-overlay.qcow2` grows with every guest write; a large, fragmented overlay on btrfs slows I/O
   (consider `chattr +C` on the images directory for new files, or periodically recreating the overlay).
6. Inside the guest: Bitdefender's 30 s ES wait and Spotlight/Google Drive indexing apply to the VM too.

## Wi-Fi and Bluetooth in the VM (Continuity, Universal Control) (2026-11-22)
Universal Control needs Apple Bluetooth LE plus Wi-Fi (AWDL) in the Mac itself; the VM's virtual NIC behind NAT
has neither, so it never worked in KVM. `gpu-mode mac` now passes the laptop's Apple BCM4360 Wi-Fi (PCI `09:00.0`,
`14e4:43a0`, own IOMMU group 18) and Apple Bluetooth (USB `05ac:828f`) to `macos-igpu`. libvirt (`managed='yes'`)
takes them from `wl`/`btusb` at start and returns them at shutdown. The VM OpenCore config enables
AirportBrcmFixup and its injectors and adds `brcmfx-wowl=0`, as on the native boot (the OCLP Wi-Fi root patch
is on the shared disk).

- Opt-in, experimental: `sudo gpu-mode mac-bg --radios` (or the switch on the macOS card in VM Switch).
  The first try (2026-11-22) hung at the Apple logo; without `--radios` both radios stay with Linux.
- Linux has no network while macOS has the radios (`wlan0` is its only link; Ethernet is unplugged). A USB
  Wi-Fi dongle (TP-Link TL-WN823N, `rtl8xxxu`) keeps Linux online: `sudo gpu-mode net-backup` copies the
  current Wi-Fi profile to it (route metric 700, so the built-in card stays preferred). VM Switch shows both
  cards in its Network section, with a "Connect as backup" button.
- Run the switch as `mac-bg` over SSH (own systemd unit, survives an SSH drop).
- Back to Linux: Apple menu > Shut Down in macOS (or `osascript -e 'tell app "System Events" to shut down'`).
