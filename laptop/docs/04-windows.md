# Windows on the GTX 1650

## Daily use
App grid > **VM Switch** > **Start Windows** (or the **Windows (GTX 1650)** launcher), or in a terminal:
```
win-gpu          # moves the GTX to the VM, starts win10-gpu, opens the Looking Glass window
win-gpu stop     # shuts Windows down; the GTX goes back to Linux
```
- First start asks for the password (polkit), then about 30 s to the Windows desktop.
- **Right Ctrl** captures / releases keyboard and mouse (no Scroll Lock on this laptop).
  Hold Right Ctrl + F: full screen. Right Ctrl + Q or closing the window: only closes the window;
  Windows keeps running, `win-gpu` reopens it.
- Start > Shut down in Windows also returns the GTX to Linux (libvirt hook runs `gpu-mode win-off`).
- The desktop session draws on the Intel GPU only (`/etc/environment.d/90-gtx-free.conf`), so normally
  nothing in Linux holds the GTX. If `gpu-mode win` still names a program, close it (or log out and in once
  after installing). Run a Linux app on the GTX on purpose with `gtx-run <app>`; close it before Windows.
- Same as `sudo gpu-mode win` / `sudo gpu-mode win-off`. Status: `sudo gpu-mode status`.
- Run PowerShell in the guest from Linux: `wexec win10-gpu 'Get-Date'` (QEMU guest agent).
- RDP also works: 192.168.122.13.

### Install / rescue (`win10`, no GTX)
```
sudo virsh start win10      # VNC 127.0.0.1:5903; the installer stick image is attached
sudo virsh shutdown win10
```
`win10` and `win10-gpu` share the disk: run only one.

## How it works
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
| Session GPU | `host/session/90-gtx-free.conf`, `host/gtx-run` | every desktop app uses Mesa EGL + Intel Vulkan only; `gtx-run` opts one app back into the GTX |
| Shared memory | `host/tmpfiles/looking-glass.conf` | `/dev/shm/looking-glass` owned by the desktop user, group kvm |

## One-time guest setup (inside Windows)
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
