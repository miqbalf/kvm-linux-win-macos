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
- Windows -> macOS on GPU 1 needs a host reboot (Windows leaves the GPU in a state macOS panics on). macOS -> Windows and macOS -> macOS worked without. vmctl enforces via /run/gpu1-last-guest.

