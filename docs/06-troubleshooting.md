# Troubleshooting
| Symptom | Fix |
|---|---|
| Only Tiano core logo | check OpenCore boot entry and OVMF boot order |
| Panic spinlock timeout | remove GPU audio function from hostdev |
| Panic NootRX no compatible GPU | GPU must be behind pcie-root-port |
| PHYSMAP_PTOV panic | remove pci-hole64-size, use maxphysaddr limit 36 |
| KVM_SET_USER_MEMORY_REGION failed | BAR not shrunk: check hook ran |
| No network in macOS | vmxnet3 + built-in=01, create Ethernet service |
| Host services lose GPU | stale KFD node: reboot host after vfio binding |
| Stuck at kdp_core zlib | kernel panic dump, check cpus boot-arg and serial log |

## macOS desktop on the emulated VGA ("VRAM 3 MB, 1280x800"), Radeon shows 12 GB / Metal 3
- Symptom: `system_profiler SPDisplaysDataType` lists the Radeon (12 GB, Metal 3) but a second "3 MB" adapter at 1280x800 drives the display; `ioreg -r -c AMDRadeonX6000_AmdRadeonFramebuffer` shows `display-type = NONE`, `connector-type = 0` on every framebuffer.
- Meaning: the GPU works, but no monitor is connected to it. Check on the host which card the monitor is on: `for c in /sys/class/drm/card*-*; do echo $c $(cat $c/status); done`. A `connected` connector on a host-driven card (amdgpu) means the monitor is plugged into the host's GPU, not the passed-through one.
- Fix: plug the monitor (or a dummy HDMI/DisplayPort plug) into the passed-through card, then restart macOS; set the monitor input to match. Only after the Radeon shows a display remove the emulated VGA (`<video><model type='none'/></video>`), otherwise you lose the VNC console.

### Tried for "display-type NONE on all 4 framebuffers" (2026-11-14), none fixed it
- Monitor on a DisplayPort of the passed-through card (host confirms the other card's HDMI is the one with a monitor).
- Real VBIOS dumped from the card (`echo on > power/control; echo 1 > rom; cat rom`) and passed with `<rom bar='on' file='/usr/share/qemu/gpu1-vbios.rom'/>` (file must be under /usr/share/qemu; /var/lib/libvirt/images was "not found").
- OpenCore GOP `Resolution` 1920x1080@32: the emulated VGA stays 1280x800.
- Compared with the real Hackintosh EFI: same SMBIOS, same NootRX, no GPU DeviceProperties, no WhateverGreen; the only boot-arg differences are VM additions. So the cause is not OpenCore config.
- Not tried: debugging NootRX display detection itself (its licence forbids use with AI), a dummy plug (does not change DP AUX/EDID detection failing), a different macOS version.
- Practical state: the Radeon accelerates apps (12 GB, Metal 3), the desktop is shown through the emulated VGA. Treat as a known limitation.
