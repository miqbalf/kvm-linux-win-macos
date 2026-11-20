# CLAUDE.md / AGENTS.md: instructions for AI agents working in this repo

Purpose: guideline plus config for KVM/libvirt GPU passthrough (macOS via OpenCore, Windows) on an AMD Ryzen + 2x RX 6700 XT host.

Rules
- All access is over Tailscale. Never write public IPs, Tailscale IPs, VNC passwords, SMBIOS serials or MLB into files. Use placeholders.
- No VM autostart. VMs start only on request (`scripts/vmctl start <vm>`).
- Host runs production services on GPU 2 (docker). Never touch GPU 2 or restart docker without asking. GPU 1 (12:00.x) is for VMs.
- Never write to the real Hackintosh disk directly: the macOS VM uses a copy-on-write qcow2 overlay over the raw disk plus a VM-only OpenCore copy. Booting the real Hackintosh invalidates the overlay; recreate it (docs/02).
- Verify before claiming stability: run `scripts/bootloop.sh N`, report N/N, save panic logs. Do not report a background job as running before checking its pid.
- Read docs/03-lessons-learned.md before changing the GPU or QEMU settings: three separate settings each broke GPU init.
- NootRX (RDNA2 kext) README forbids use with AI: do not have an agent read its source; use the docs here instead.
- Success criterion for a boot test is the guest answering ping AND an SSH banner (`nc <ip> 22`), never just "no panic string in the log". Do not add `serial=3` back for normal use (it caused boot panics).
- Switch OS on GPU 1 with `vm-switch <macos|win10-gpu>` (runs `gpu1-reset 2`: remove, bus reset, rescan with autoprobe OFF). NEVER bind amdgpu to GPU 1 or reset it with raw setpci without removing it first: amdgpu bind crashed the host. vmctl blocks macOS after Windows until the GPU was reset.

- Storage: share a plain data disk to the VMs over SMB (docs/07), never attach one raw disk to two guests, never share the disk holding VM images or Docker data (SSD_DATA). SMB must stay on virbr0 + Tailscale only. USB: scripts/usbctl, untested on storage sticks.

Laptop host (`laptop/`, Acer Nitro, separate from the desktop rules above)
- Read laptop/README.md and laptop/docs/05-lessons-learned.md first.
- Never bind the GTX 1650 to vfio-pci at boot, never blacklist nvidia, never hand-edit limine.conf (black screen, 2026-11-19). GPU switches only via `gpu-mode` / `win-gpu`.
- Hackintosh disk only through the overlay on `/dev/hackintosh-disk` (nvme numbering swaps).
- Take a snapper snapshot before boot, driver or kernel-module changes.
