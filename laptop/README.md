# Laptop host: Acer Nitro AN515-55 on CachyOS

Windows 10 and macOS (the laptop's own Hackintosh disk) as KVM guests on a hybrid-GPU laptop.
Windows can run with the GTX 1650 passed through, shown in a Looking Glass window on the Linux desktop
(`win10-gpu`); Linux keeps the panel.
macOS can run two ways: in a window with a virtual display (`macos`), or full screen on the laptop's
own panel with the Intel iGPU passed through (`macos-igpu`, Metal 3).

| | |
|---|---|
| CPU / RAM | i5-10300H (4C/8T), 32 GB |
| GPUs | Intel UHD 630 00:02.0 (laptop panel, `i915`), GTX 1650 Mobile 01:00.0 (HDMI port only, `nvidia`) |
| Disks | WD SN530 = CachyOS (btrfs `@`, `@home`); Samsung 980 = real Hackintosh disk (APFS, read through an overlay only). nvme0/nvme1 numbering swaps between boots: use `/dev/hackintosh-disk` |
| Boot | Limine + snapper + limine-snapper-sync (snapshots in the boot menu) |

## Setup
```
sudo bash laptop/host/01-host-setup.sh   # packages, libvirt, ufw, udev, images, define VMs (takes a snapshot first)
sudo bash laptop/host/02-verify.sh       # health checks, run after every update/reboot
```
Windows installs from a copy of a Windows USB stick at `/var/lib/libvirt/images/win10/win10-installer.img`
(`dd if=/dev/sdX of=... bs=4M`; not downloaded by the script). Log out of GNOME once after setup.
macOS on the panel needs a one-time image build, see "macOS on the laptop panel: one-time build".

## Daily use

### macOS on the laptop panel (Linux <-> macOS)
The panel is wired only to the Intel iGPU, so **either Linux or macOS owns the screen, never both**.
Nothing is permanent: a laptop reboot always comes back to Linux.

**Go to macOS** (from a Linux terminal on the laptop, or over SSH):
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

### Windows on the GTX 1650 (Looking Glass window)
App grid > **Windows (GTX 1650)**, or in a terminal:
```
win-gpu          # moves the GTX to the VM, starts win10-gpu, opens the Looking Glass window
win-gpu stop     # shuts Windows down; the GTX goes back to Linux
```
- First start asks for the password (polkit), then about 30 s to the Windows desktop.
- **Right Ctrl** captures / releases keyboard and mouse (no Scroll Lock on this laptop).
  Hold Right Ctrl + F: full screen. Right Ctrl + Q or closing the window: only closes the window;
  Windows keeps running, `win-gpu` reopens it.
- Start > Shut down in Windows also returns the GTX to Linux (libvirt hook runs `gpu-mode win-off`).
- Close programs that use the GTX in Linux first (`gpu-mode win` stops with their names). The GNOME
  Settings app holds it: close Settings.
- Same as `sudo gpu-mode win` / `sudo gpu-mode win-off`. Status: `sudo gpu-mode status`.
- Run PowerShell in the guest from Linux: `wexec win10-gpu 'Get-Date'` (QEMU guest agent).
- RDP also works: 192.168.122.13.

### macOS in a window, Windows install/rescue
```
sudo virsh start macos      # 192.168.122.11, VNC 127.0.0.1:5902 (virtual display, no Metal)
sudo virsh start win10      # 192.168.122.13, VNC 127.0.0.1:5903 (no GTX; installer stick image attached)
sudo virsh shutdown <vm>
```
VNC from another machine: `ssh -L 5902:127.0.0.1:5902 <user>@<laptop>` then open `vnc://127.0.0.1:5902`.
The VNC password is in `/etc/libvirt/vnc-laptop.pass` (root only). Repo XML keeps `CHANGE_ME`.

## How Windows on the GTX works
The GTX 1650 has no display of its own on the laptop (it renders for the iGPU; only the HDMI port is wired to it).
In the VM, a virtual display driver gives Windows a 1920x1080 screen on the GTX; the Looking Glass host app
copies its frames into shared memory and the Linux client shows them.

| Part | File | Why |
|---|---|---|
| Switch | `host/gpu-mode win` / `win-off` | pins PCI power on, unloads nvidia with `rmmod`, moves 01:00.1 then 01:00.0 to `vfio-pci`, starts `win10-gpu`; back: VM off, nvidia reloaded |
| Auto return | `host/libvirt-hooks/qemu` | when `win10-gpu` stops, runs `gpu-mode win-off` |
| GNOME keeps off the GTX | `host/udev/63-gtx-no-gnome.rules`, `host/systemd/org.gnome.Shell@wayland.service.d/` | `mutter-device-ignore` + Mesa-only EGL: gnome-shell never opens the card, so it can leave nvidia without a logout |
| VM | `vm/windows/win10-gpu.xml` | q35/OVMF, same disk and NVRAM as `win10`; GTX with its own VBIOS (`gtx1650.rom`) and Acer subsystem IDs; fake battery SSDT (NVIDIA mobile driver needs one); hidden KVM; 64 MB ivshmem; SPICE 127.0.0.1:5904 for input/audio, no emulated video |
| Battery | `vm/windows/ssdt-battery.asl` | built with `iasl` by the setup script |
| Client | `host/looking-glass/` | B7 client build (with a nettle 4 patch), `client.ini`, launcher `host/win-gpu` + menu entry |
| Shared memory | `host/tmpfiles/looking-glass.conf` | `/dev/shm/looking-glass` owned by the desktop user, group kvm |

### Windows guest: one-time setup (inside `win10-gpu`, over RDP or VNC of `win10`)
1. Install Windows from the stick image with `sudo virsh start win10` (VNC 5903). Load the virtio storage driver
   from `virtio-win.iso` if no disk shows.
2. `virtio-win-guest-tools.exe` from `virtio-win.iso` (drivers + QEMU guest agent). Enable RDP.
3. Shut down, then `win-gpu` (Windows now has the GTX; the window stays black until steps 4-6 are done; use RDP).
4. NVIDIA notebook driver for the GTX 1650 from nvidia.com (DCH; 621.24 tested). No Code 43.
5. Looking Glass host **B7** (must match the client): `looking-glass-host-setup.exe /S`. It also installs the
   IVSHMEM driver.
6. Virtual display: **Virtual Display Driver 23.10.20.3** (IddSampleDriver). Newer 24.x/25.x builds need a
   newer IddCx than Windows 10 has (Code 31). Import its certificate into Local Machine Root and
   TrustedPublisher, create the device with nefcon:
   ```
   nefconc.exe --create-device-node --hardware-id Root\IddSampleDriver --class-name Display --class-guid 4D36E968-E325-11CE-BFC1-08002BE10318
   nefconc.exe --install-driver --inf-path C:\IddSampleDriver\IddSampleDriver.inf
   ```
   `C:\IddSampleDriver\option.txt` = `1` and `1920, 1080, 60` (two lines; only one mode, else Windows
   picks 640x480). Disable and enable the device after changing it.

## How macOS on the panel works
| Part | File | Why |
|---|---|---|
| Switch script | `host/gpu-mode` | stops GDM, moves 00:02.0 from `i915` to `vfio-pci`, starts `macos-igpu`; back: VM off, `i915`, backlight restore, GDM |
| Auto return | `host/libvirt-hooks/qemu` | when `macos-igpu` stops for any reason, runs `gpu-mode host` |
| Shutdown watchdog | `gpu-mode watchdog` (unit `gpu-mode-watchdog`) | macOS spins on one kernel address after Shut Down; after 20 s with no ping and an unchanged, non-halted RIP, the VM is forced off |
| Touchpad | `host/touchpad-bridge`, `host/udev/62-gpu-mode-touchpad.rules` | raw touchpad is absolute and has no tap-to-click without libinput; the bridge makes a relative uinput mouse with taps and scrolling |
| VM | `vm/macos/macos-igpu.xml` | i440fx machine + `x-igd-legacy-mode=on` (copies the real host bridge/LPC IDs the Intel GOP checks; q35 cannot do this), OpRegion, 64 MB stolen memory, iGPU at guest 00:02.0, USB keyboard + mouse |
| Panel init | `vm/macos/gop-policy/` + Intel GOP from the BIOS | OVMF has no Intel graphics driver. The BIOS's Intel GOP lights the eDP panel before macOS, but only starts when a `PLATFORM_GOP_POLICY` protocol (lid state + VBT) exists; `PlatformGopPolicy.efi` provides it. OpenCore loads both, then connects drivers |
| OpenCore config | `vm/macos/make-vm-config.py --igpu` | iGPU DeviceProperties, `igfxonln=1 -igfxblr amfi=0x80`, no `-v`, PNLF, no picker |

### macOS on the laptop panel: one-time build
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

## macOS VM OpenCore
`vm/macos/opencore-lt.img` is a VM-only copy of the laptop's EFI (gitignored: holds SMBIOS serials).
Regenerate its config from the real one with `vm/macos/make-vm-config.py` (XML output, laptop ACPI/kexts off,
only OpenRuntime driver), copy into the image (`mount -o loop opencore-lt.img /mnt/ocimg`), then reinstall it
with the setup script. Booting the Hackintosh natively invalidates `nvme1-overlay.qcow2`: delete it and rerun setup.

## Lessons (2026-11-19)
- Binding the GTX 1650 to vfio-pci and blacklisting nvidia at boot gave a black screen after login.
  Restored the fresh-install snapshot. Those scripts are in `host/attic-kimi/` and must not be run.
- `ly` and `gdm` were both enabled after install; only gdm now.
- OpenCore needs an XML `config.plist`; a binary plist gives `OC: Failed to parse configuration!`.
- Do not disable the `hypervisor` CPUID bit for the macOS VM on Intel: OpenCore then reads Intel MSRs
  that KVM rejects and faults with `#GP` inside OpenCore.efi.
- HfsPlus.efi / AudioDxe are left off in the VM config.
- GNOME suspends after 15 min idle on battery, which looks like a hang over SSH. Idle suspend on AC is off.
- NVMe numbering swaps between boots. Once the overlay was backed by the CachyOS disk and the VM showed the
  Limine menu. Always `/dev/hackintosh-disk` (udev rule 61-, must run after 60-persistent-storage).
- With the iGPU, applekeystored panicked on the OCLP-patched IO80211 code signature: `amfi=0x80`.
- `serial=3` slows macOS enough that the SSH banner times out: debug only.
- After the guest had the iGPU, `i915` comes back with backlight 0 (looks like a dead screen): `gpu-mode` restores it.
- Panel black in macOS with the iGPU: without firmware init, macOS uses 4-lane "fast link training" without a
  handshake (Linux uses 2 lanes, trained) and the panel never lights; setting backlight registers by hand did
  not help. Fix: run the BIOS Intel GOP in the VM (needs IGD legacy mode on i440fx + `PlatformGopPolicy.efi`);
  macOS then reuses the boot pipe.
- `-v` with a real panel: verbose text in the uncached GOP framebuffer is so slow that XNU fails with
  `Failed to start CPU 01, rebooting` (boot loop). No `-v` for `macos-igpu`.
- macOS has no PS/2 driver: the VM needs USB keyboard/mouse; the touchpad goes through `touchpad-bridge`.
- `gpu-mode host | head -1` killed the script mid-switch (SIGPIPE): `trap '' PIPE`.

## Lessons (2026-11-20, Windows on the GTX)
- `modprobe -r nvidia_drm` fails: it also tries to remove the shared dependency `i915`. Use `rmmod` per module.
- Unbinding the runtime-suspended GTX HDMI audio (01:00.1) froze the whole host. Pin `power/control=on` on
  00:01.0, 01:00.0 and 01:00.1 first, unbind the audio function first, each step under `timeout`.
- gnome-shell opens every DRM card at login and keeps the GTX busy: udev tag `mutter-device-ignore` plus
  Mesa-only EGL for gnome-shell. Without it the GTX cannot leave nvidia without a logout.
- Looking Glass client B7 does not build against nettle 4 (`sha1_digest` lost its length argument): patched in
  `build-client.sh`.
- Virtual Display Driver 25.x on Windows 10 21H2: Code 31 (IddCx too old). 23.10.20.3 works.
- With several modes in `option.txt`, Windows started at 640x480 (big, blurry window). Only 1920x1080 listed now.
- The laptop has no Scroll Lock: Looking Glass escape key is Right Ctrl.
