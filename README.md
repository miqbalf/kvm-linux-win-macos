# GPU passthrough home server: macOS (and Windows) VMs on KVM

Field notes and working config for turning a desktop PC into an always-on Linux server that also runs
macOS (the main desktop, used remotely) and an occasional Windows VM, each with a passed-through AMD GPU.
All remote access goes over Tailscale; nothing here needs a public IP.

Status: macOS VM working (see docs/02-macos-vm.md for boot-reliability numbers). Windows GPU passthrough: planned, see docs/05-windows-vm.md.

## Quick commands (replace `<host>` with your host's Tailscale name)
```bash
# macOS -> Windows (stops macOS, resets the GPU, starts Windows; no host reboot, ~2 min)
ssh root@<host> vm-switch win10-gpu
#   then: Windows App / RDP to <host>:3389   (console fallback: ssh -L 5903:127.0.0.1:5903 root@<host>, VNC to localhost:5903)

# Windows -> macOS
ssh root@<host> vm-switch macos
#   then: Finder > Go > Connect to Server > vnc://<host>:5900   (Screen Sharing)

ssh root@<host> vmctl status               # what is running, guest IP
ssh root@<host> vmctl force-stop macos     # pull the plug (macOS ignores ACPI shutdown)
ssh root@<host> vmctl start macos          # start without switching (refuses macOS right after Windows)
```
RDP is for Windows (port 3389), Screen Sharing/VNC is for macOS (port 5900). Error 0x204 in the RDP client usually means the Windows VM is not running.

| Doc | What |
|---|---|
| docs/00-spec.md | Hardware and software spec |
| docs/01-host-setup.md | Host: vfio binding, libvirt hook, services |
| docs/02-macos-vm.md | macOS VM: config, boot args, results |
| docs/03-lessons-learned.md | Root causes and breakthroughs (read this first when something panics) |
| docs/04-operations.md | Start, stop, connect, add a VM |
| docs/05-windows-vm.md | Windows VM and GPU passthrough |
| docs/06-troubleshooting.md | Symptom to fix table |
| host/, vm/, scripts/ | The actual files |

Placeholders: `${TAILSCALE_IP}`, `<host>` (host Tailscale name). Replace with your own. Never commit real IPs, VNC passwords or OpenCore serials.
