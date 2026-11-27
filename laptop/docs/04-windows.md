# Windows 10 (`win10-gpu` and Virtual GPU `win10`)

## Two Windows modes (shared disk)
| Mode | GPU / Displays | Best for | Start |
|---|---|---|---|
| **GTX 1650 Passthrough (`win10-gpu`)** | Full GTX 1650 + physical HDMI port | Games, GPU CAD (`ArcGIS Pro`), native HDMI display | VM Switch → **Start (GTX 1650)** or `win-gpu` |
| **Virtual GPU (`win10`)** | `virtio-gpu` + FreeRDP desktop/RemoteApps | Working side-by-side with Linux dual monitors (`eDP-1` + `HDMI-2`) | VM Switch → **Start (Virtual GPU)** or `virsh -c qemu:///system start win10` |

## Daily use (GTX 1650 passthrough)
App grid > **VM Switch** > **Start (GTX 1650)** (or the **Windows (GTX 1650)** launcher), or in a terminal:
```
win-gpu             # moves the GTX to the VM, starts win10-gpu, opens Looking Glass (unless external-only enabled)
win-gpu --no-lg     # start cleanly without opening the Looking Glass window (for physical external HDMI)
win-gpu desktop     # open Looking Glass explicitly anytime
win-gpu stop        # shuts Windows down; the GTX goes back to Linux
```
- **External monitor direct mode (no Linux popup window):** In **VM Switch → Windows**, enable **External monitor only** (creates `~/.config/vm-switch/no-looking-glass`). Windows starts directly on the external HDMI display with no extra Looking Glass popup on Linux; click **Open Looking Glass** (`win-gpu desktop`) whenever you want the window.
- **Smoother Looking Glass mouse:** `looking-glass/client.ini` sets `rawMouse=yes`, `mouseSmoothing=no`, `scaleCursor=yes`, `alwaysShowCursor=yes`, and `helpMenuDelay=400` so captured and uncaptured pointers behave predictably. For multi-screen Linux + HDMI passthrough, **Deskflow local server (`deskflow-mode local`)** lets one pointer glide seamlessly between the Linux laptop panel and the Windows HDMI monitor without SPICE pointer capture (see [docs/08](08-share-keyboard-mouse.md)).
- First start asks for the password (polkit), then about 30 s to the Windows desktop.
- **Right Ctrl** captures / releases keyboard and mouse inside Looking Glass (no Scroll Lock on this laptop).
  Hold Right Ctrl + F: full screen. Right Ctrl + Q or closing the window: only closes the window;
  Windows keeps running, `win-gpu desktop` reopens it.
- Start > Shut down in Windows also returns the GTX to Linux (libvirt hook runs `gpu-mode win-off`).
- The desktop session draws on the Intel GPU only (`/etc/environment.d/90-gtx-free.conf`), so normally
  nothing in Linux holds the GTX. If `gpu-mode win` still names a program, close it (or log out and in once
  after installing). Run a Linux app on the GTX on purpose with `gtx-run <app>`; close it before Windows.
- Same as `sudo gpu-mode win` / `sudo gpu-mode win-off`. Status: `sudo gpu-mode status`.
- **External HDMI on Linux:** Because the HDMI port is wired to the GTX 1650 and GNOME ignores the GTX in GTX-passthrough mode (`host/udev/63-gtx-no-gnome.rules`), use **VM Switch → Connect external HDMI** (`linux-hdmi on --restart`) when you want Linux to drive `eDP-1` + `HDMI-2` (for Linux work or **Virtual GPU** Windows), and **Switch to GTX passthrough mode** (`linux-hdmi off --restart`) before starting `win-gpu` again.
- Run PowerShell in the active guest from Linux: `wexec auto 'Get-Date'` (QEMU guest agent, targets `win10-gpu` or `win10`).
- RDP also works on both modes: `192.168.122.13` (`winapps windows` for resizable full desktop).

### Virtual GPU (`win10` · compatible with Linux External HDMI)
`win10` and `win10-gpu` share `/var/lib/libvirt/images/win10/win10.qcow2` and NVRAM (run only one at a time):
- Start via **VM Switch → Start (Virtual GPU)** (no `sudo` needed for members of group `libvirt`).
- Click **Open desktop** (`winapps windows`) for a resizable/maximizable full Windows desktop that can be dragged between the laptop panel and external Linux HDMI, OR open individual apps from **Windows apps** (`WinApps` Coherence).
- VNC rescue console (`127.0.0.1:5903`) remains available under **VM Switch → More → Windows VNC fallback**.

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
