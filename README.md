# GPU passthrough home server: macOS (and Windows) VMs on KVM

Field notes and working config for turning a desktop PC into an always-on Linux server that also runs
macOS (the main desktop, used remotely) and an occasional Windows VM, each with a passed-through AMD GPU.
All remote access goes over Tailscale; nothing here needs a public IP.

Status: macOS VM working (see docs/02-macos-vm.md for boot-reliability numbers). Windows GPU passthrough: planned, see docs/05-windows-vm.md.

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
