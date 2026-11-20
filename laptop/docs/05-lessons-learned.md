# Lessons learned (laptop)

Read before changing boot, GPU or VM settings.

## 2026-11-19: host and macOS
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

## 2026-11-20: Windows on the GTX
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

## 2026-11-20: USB fingerprint dongle (MAFP 3274:8012)
- Linux: libfprint `mafpmoc` handshake times out; a build with a community microarray driver also times out.
  Raw USB writes succeed, the device never replies.
- Windows VM (USB passthrough): driver 9.47 crashes, 9.32 installs but has 0 biometric units, 18.5 sends its
  handshake 50+ times with 0 replies (usbmon). Other USB port: same.
- Conclusion: the dongle is dead (likely a failed firmware update from the old Windows 11 install). Stock
  libfprint restored. Do not spend more time on it; buy a supported reader (libfprint list) if needed.

## 2026-11-20: fans and keyboard RGB
- Upstream Linuwu-Sense does not build on kernel 7.2+ (sysfs API change); the AN515-55 patch fork does, and adds
  working 4-zone RGB payloads for this model.
- The driver's saved keyboard state is already scaled by brightness: colors dim at every reboot. Restore the
  original values at login instead (`nitro restore`).
- Its tmpfiles permissions run before the module loads at boot: re-run them from `linuwu_sense.service`.
- `systemctl restart linuwu_sense.service` unloads the module (ExecStop=rmmod).

## 2026-11-20: VM Switch app
- `gpu-mode mac` stops GDM, which ends every process of the desktop session, including an app that started
  the switch. The app uses `gpu-mode mac-bg`, which re-runs the switch as its own system unit (`systemd-run`).
- pkexec + a polkit action with `auth_admin_keep` for `/usr/local/sbin/gpu-mode`: one password prompt, then
  remembered for a few minutes; no NOPASSWD sudo.
- Screenshots of a GTK app while the screen is locked come out empty; render in a headless nested compositor
  instead: `mutter --headless --no-x11 --virtual-monitor 1280x1000 --wayland-display vs-shot`.
- Every GTK4 app opens all GPUs for drawing (NVIDIA EGL and Vulkan), so VM Switch itself blocked
  `gpu-mode win` ("programs still use the GTX: python3"). VM Switch and Nitro Control now set
  `__EGL_VENDOR_LIBRARY_FILENAMES` (Mesa) and `VK_DRIVER_FILES` (Intel) before loading GTK. Then
  `xdg-desktop-portal-gnome` (started when Deskflow asked for input permission) blocked it the same way.
  Final fix for the whole session: `/etc/environment.d/90-gtx-free.conf` (Mesa EGL + Intel Vulkan only for every
  user-session process) and `gtx-run` to opt one app back into the GTX.

## VM disks on btrfs: cache='none' gives false checksum errors (2026-11-20)
- Symptom: kernel log `BTRFS warning ... csum failed root 274 ino ... direct IO failed ... err no 10`, 350 times
  on `win10.qcow2` (86 blocks), mostly during big installs in Windows.
- Cause: `cache='none' io='native'` = O_DIRECT. On copy-on-write btrfs the guest can change a buffer while it is
  written or read, so the checksum check fails for that I/O and the guest gets a read error.
- Data was fine: a full buffered read of the 200 GB image afterwards found 0 unreadable blocks.
- Fix: `cache='writeback' io='threads'` for all VMs (repo XMLs + `host/vm-disk-writeback.sh` for defined VMs).

