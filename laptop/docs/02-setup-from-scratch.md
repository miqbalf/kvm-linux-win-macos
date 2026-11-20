# Setup from scratch (in order)

Everything here runs on the laptop, from the repo root. Each step can be repeated.

## 1. BIOS and OS
1. BIOS: VT-x and VT-d on (default on the AN515-55, BIOS V2.06). Secure Boot off.
2. Install CachyOS with GNOME, btrfs, Limine and snapper (installer defaults). Only `gdm` as display manager
   (`ly` was also enabled after install: disable it).
3. IOMMU on: add `intel_iommu=on iommu=pt` to `KERNEL_CMDLINE` in `/etc/default/limine`, run `sudo limine-update`,
   reboot. This is the only boot change. Never bind the GTX to vfio-pci at boot and never blacklist nvidia
   (that gave a black screen after login, see lessons).
4. `sudo systemctl enable --now sshd` (manage the laptop over SSH while the panel belongs to macOS).

## 2. Host setup
```
git clone <this repo> ~/kvm-linux-win-macos && cd ~/kvm-linux-win-macos
sudo bash laptop/host/00-inspect.sh      # read-only report of IOMMU groups, GPUs, disks
sudo bash laptop/host/01-host-setup.sh   # snapshot first, then packages, libvirt, network, udev, images, VMs,
                                         # gpu-mode, Looking Glass client, launcher
sudo bash laptop/host/02-verify.sh       # health checks; rerun after every update or reboot
```
Log out of GNOME once afterwards (GNOME then ignores the GTX).

What the setup script installs:
| Installed to | From |
|---|---|
| `/usr/local/sbin/gpu-mode` | `host/gpu-mode` |
| `/usr/local/sbin/touchpad-bridge` | `host/touchpad-bridge` |
| `/usr/local/bin/win-gpu`, `/usr/local/bin/wexec` | `host/win-gpu`, `host/wexec` |
| `/usr/local/share/applications/win-gpu.desktop` | `host/looking-glass/win-gpu.desktop` |
| `~/.config/looking-glass/client.ini` | `host/looking-glass/client.ini` |
| `/etc/libvirt/hooks/qemu` | `host/libvirt-hooks/qemu` |
| `/etc/udev/rules.d/61-,62-,63-*.rules` | `host/udev/` |
| `/etc/systemd/user/org.gnome.Shell@wayland.service.d/10-no-nvidia-egl.conf` | `host/systemd/` |
| `/etc/tmpfiles.d/looking-glass.conf` | `host/tmpfiles/` |
| libvirt domains `macos`, `macos-igpu`, `win10`, `win10-gpu` | `vm/` (VNC password from `/etc/libvirt/vnc-laptop.pass`) |
| `/var/lib/libvirt/images/win10/{ssdt-battery.aml,gtx1650.rom}` | built from `vm/windows/ssdt-battery.asl`; VBIOS read from the card |

## 3. macOS
1. VM OpenCore copy: see [03-macos.md](03-macos.md), "OpenCore for the VMs".
2. Panel mode one-time build (Intel GOP from the BIOS): [03-macos.md](03-macos.md), "One-time build".
3. `sudo gpu-mode mac`.

## 4. Windows
1. Copy a Windows 10 USB stick: `sudo dd if=/dev/sdX of=/var/lib/libvirt/images/win10/win10-installer.img bs=4M`.
2. Install with `sudo virsh start win10` (VNC 127.0.0.1:5903), then the guest setup in
   [04-windows.md](04-windows.md).
3. `win-gpu`.

## 5. Fans and keyboard RGB (optional)
`sudo bash laptop/host/nitrosense/install.sh`, log out and in once. See [07-fan-and-rgb.md](07-fan-and-rgb.md).

## Not in the repo (never commit)
OpenCore images and configs with SMBIOS serials, the Intel GOP driver, the GTX VBIOS, disk images, the VNC
password, the Windows account and unattend file. See `laptop/.gitignore`.
