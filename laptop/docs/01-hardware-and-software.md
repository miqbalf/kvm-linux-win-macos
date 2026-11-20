# Hardware and software

## The laptop
| Part | Device | PCI / USB ID | Used by |
|---|---|---|---|
| Model | Acer Nitro AN515-55, BIOS V2.06 (2021-08-19) | | |
| CPU | Intel i5-10300H, 4 cores / 8 threads, VT-x + VT-d | | host; VMs get vCPUs |
| RAM | 32 GB | | host; macOS VM and Windows VM each take a share |
| iGPU | Intel UHD 630 (CometLake-H GT2) | 00:02.0 `8086:9bc4` | Linux desktop on the panel; **macOS** in `gpu-mode mac` |
| dGPU | NVIDIA GTX 1650 Mobile (TU117M) | 01:00.0 `10de:1f99` | Linux (nvidia driver, idle); **Windows** in `gpu-mode win` |
| dGPU audio | NVIDIA HDMI audio | 01:00.1 `10de:10fa` | moves with the GTX |
| PCIe root port of the GTX | | 00:01.0 | power pinned during a switch |
| Panel | 15.6" eDP, wired **only** to the iGPU | | whoever owns the iGPU |
| HDMI port | wired to the GTX | | |
| Disk 1 | WD SN530 512 GB NVMe | `15b7:5009` | CachyOS (btrfs `@`, `@home`), VM images in `/var/lib/libvirt/images` |
| Disk 2 | Samsung 980 1 TB NVMe | `144d:a809` | the real Hackintosh disk (APFS). VMs read it only through a qcow2 overlay. Name: `/dev/hackintosh-disk` (nvme0/nvme1 swap between boots) |
| Wi-Fi | Broadcom BCM4360 (Apple card) | 09:00.0 `14e4:43a0` | host only (`broadcom-wl`) |
| Ethernet | Killer E2600 | 08:00.0 | host only |
| Bluetooth | Apple BCM2046 | USB `05ac:828f` | host only |
| Webcam | Chicony HD | USB `04f2:b64f` | host |
| Keyboard RGB | 4-zone backlight, controlled over Acer WMI | | `linuwu_sense` module: `nitro`, Nitro Control |
| Fans | 2 (CPU, GPU), controlled by the EC over Acer WMI | | `linuwu_sense`: auto / max / fixed % |
| Keyboard, touchpad | internal (PS/2 keyboard, I2C touchpad) | | host; given to macOS in `gpu-mode mac` (touchpad through `touchpad-bridge`) |
| Fingerprint dongle | MicroarrayTechnology MAFP | USB `3274:8012` | **dead**: answers nothing on Linux or Windows (see lessons) |

## Host software (tested versions, 2026-11-20)
| | |
|---|---|
| OS | CachyOS, kernel `linux-cachyos` 7.3.4, `linux-cachyos-nvidia-open`, nvidia-utils 620.70 |
| Boot | Limine 12.10 + snapper 0.13 + limine-snapper-sync (snapshots bootable from the menu) |
| Kernel cmdline | `intel_iommu=on iommu=pt` (in `/etc/default/limine`, then `limine-update`) |
| Desktop | GNOME 51 + GDM 51 (Wayland), Mesa 26.2 |
| VM stack | QEMU 11.1.3, libvirt 12.9, edk2-ovmf 202608 (`OVMF_CODE.4m.fd`) |
| Fan / RGB driver | `linuwu_sense` 25.701 (BillyAddlers AN515-55 patch, DKMS), replaces `acer_wmi` |
| Windows viewer | Looking Glass client B7 (built from source, `host/looking-glass/build-client.sh`) |

## Guests
| VM | Machine | Display | Use |
|---|---|---|---|
| `macos-igpu` | i440fx + OVMF, OpenCore (`opencore-igpu.img`) | iGPU passed through, laptop panel, Metal 3 | macOS full screen on the laptop |
| `macos` | q35 + OVMF, OpenCore (`opencore-lt.img`) | virtual (VNC 5902) | macOS in a window / over VNC |
| `win10-gpu` | q35 + OVMF | GTX passed through + virtual display driver, Looking Glass | Windows daily use |
| `win10` | q35 + OVMF | virtual (VNC 5903) | Windows install / rescue |

Both macOS VMs boot the Hackintosh disk through one overlay (`nvme1-overlay.qcow2`): only one runs at a time.
Both Windows VMs share `win10.qcow2` and its NVRAM: only one runs at a time.

Windows guest: Windows 10 Enterprise LTSC 21H2, virtio-win guest tools, NVIDIA notebook driver 621.24 (DCH),
Looking Glass host B7, Virtual Display Driver 23.10.20.3.

## Who owns what in each mode
| Mode | Panel + iGPU | GTX 1650 | Keyboard / touchpad | How to enter |
|---|---|---|---|---|
| Linux | Linux (GNOME) | Linux nvidia driver (idle) | Linux | default after every boot |
| Linux + Windows | Linux (GNOME) | Windows VM | Linux; Windows window grabs them with Right Ctrl | `win-gpu` |
| macOS | macOS VM | Linux (idle) | macOS | `sudo gpu-mode mac` |
