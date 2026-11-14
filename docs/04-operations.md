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
- Switching OS on the GPU: `ssh root@<host> vm-switch macos` or `vm-switch win10-gpu` (no host reboot). It stops whichever guest runs (ACPI shutdown, then force after 60 s), resets GPU 1 with `gpu1-reset` (default level 2), and starts the target with `vmctl start`. Tested: 3 of 3 macOS to Windows to macOS cycles, host stayed up, host GPU services unaffected.
- Do not start macOS right after Windows with a bare `vmctl start macos`: `vmctl` refuses (marker `/run/gpu1-last-guest`) until `gpu1-reset` or `vm-switch` has run.
- Reset levels (`gpu1-reset <level>`): 0 none, 2 remove + root-port bus reset + rescan with autoprobe off (default, safe), 3 kernel reset of the root port. Never bind `amdgpu` to GPU 1 as a "reset": that crashed the host (see docs/03).
