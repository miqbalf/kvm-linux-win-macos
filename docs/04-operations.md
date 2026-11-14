# Operations (all over Tailscale)
Replace `<host>` with the host's Tailscale name.
- Start macOS: `ssh root@<host> vmctl start macos` (no autostart)
- Status / IP: `ssh root@<host> vmctl status`, `vmctl ip macos`
- Connect: Screen Sharing / VNC to `<host>:5900` (forwarder to the guest). SSH to guest: `ssh -J root@<host> <user>@<guest-ip>`
- Stop: click Shut Down in macOS, or `vmctl force-stop macos` (like pulling power)
- Restart: `vmctl restart macos`
- Console (emulated VGA): `ssh -L 5902:127.0.0.1:5902 root@<host>` then VNC to localhost:5902
- Add a VM: copy `vm/macos/macos.xml`, new name/uuid/MAC/disk, add a DHCP reservation, add a forwarder service on a new Tailscale port, `virsh define`. Extend the hook `case` for the guest if it uses GPU 1. Only one VM may use GPU 1 at a time.
- Check health: `virsh list --all`, `systemctl is-active vfio-gpu1 vnc-macos libvirtd`
- Going from Windows back to macOS requires `systemctl reboot` on the host (see docs/03). macOS to Windows did not in testing. vmctl enforces the Windows to macOS case.
