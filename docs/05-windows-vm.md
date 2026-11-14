# Windows VM with GPU passthrough
Domain `win10-gpu` (derived from the existing `win10-ltsc` by `vm/windows/make-win-gpu-xml.py`): same virtio disk, new MAC and VNC port, plus both GPU functions (12:00.0 VGA and 12:00.1 audio) as hostdevs. Do not run it together with `win10-ltsc` (same disk) or with macOS (same GPU).

Results (2026-11-14)
- Boots with the GPU attached, Windows reaches the desktop, RDP port answers on the guest NAT address.
- Host log shows `reset done` for both functions, so the GPU resets cleanly (unlike macOS where only 12:00.0 is passed).
- No BAR shrink, maxphysaddr or hotplug tweaks needed. The macOS hook only runs for guest `macos`.
- Still to verify inside Windows: Device Manager shows the Radeon with a working driver (install AMD Adrenalin if Windows Update does not).

Start / stop: `vmctl start win10-gpu`, `vmctl stop win10-gpu`. Connect: RDP to the guest through a Tailscale forwarder (same pattern as vnc-macos.service on port 3389).
Windows 10 LTSC support ends Jan 2027.

## How to run and check it
1. `vm-switch win10-gpu` (stops macOS if running, resets the GPU, starts Windows; no host reboot)
2. `ssh root@<host> vmctl start win10-gpu`, find the guest address with `vmctl ip win10-gpu`.
3. RDP to the guest through a Tailscale forwarder (`host/systemd/rdp-win10.service.template`: set `${TAILSCALE_IP}`; target is the win10-gpu guest address, port 3389), or use the console on VNC port 5903 over an SSH tunnel.
4. In Windows open Device Manager, Display adapters: expect "AMD Radeon RX 6700 XT". If it shows a generic adapter or error 43, install the AMD Adrenalin driver and reboot.
5. Back to macOS: `vm-switch macos`.

Offline evidence (Windows disk read-only after a clean shutdown): Windows enumerated PCI\VEN_1002&DEV_73DF and staged an AMD display driver from Windows Update (u0420529.inf, signature OK). Install completion was cut off by my shutdown.
Second run (after a host reboot, 8 min uptime, clean ACPI shutdown, disk read offline afterwards):
- DriverStore holds `u0420529.inf` with `amdkmdag.sys` (AMD display driver from Windows Update).
- The SYSTEM registry hive records `oem16.inf ... ati2mtag_Navi22:32.0.21030.2001` for `PCI\VEN_1002&DEV_73DF&REV_C5` and an `amdkmdag` service key: Windows matched and installed the Radeon driver for the passed-through card.
- Not seen directly: the Device Manager state (no Code 43 observed; no way to read it offline). Check it once on first use.

How to read a Windows guest offline from the host (guest must be shut off): `L=$(losetup -rfP --show /dev/<windisk>); mount -t ntfs3 -o ro ${L}p3 /mnt/winro`, then look at `Windows/INF/setupapi.dev.log` and `strings -el Windows/System32/config/SYSTEM`. Never read it while the guest runs: the data is stale.

## In-guest confirmation (2026-11-14)
Read from inside the running guest by a startup script (method below), `pnputil /enum-devices /class Display`:
```
Device Description: AMD Radeon RX 6700 XT
Manufacturer Name:  Advanced Micro Devices, Inc.
Status:             Started
Driver Name:        oem16.inf
```
The Windows GPU passthrough works: both functions are passed, Windows installed the AMD driver from Windows Update, and the card is started without errors (no Code 43).

### Run a command in a Windows guest with no login (no RDP, no password)
With the guest shut off, mount its disk on the host (`losetup -fP --show /dev/<windisk>; mount -t ntfs3 -o rw <loop>p3 /mnt/winro`), add a local-policy machine startup script, boot, wait, shut down, read the output file offline, then delete the helper files:
- `Windows/System32/GroupPolicy/gpt.ini`: `[General]`, `gPCMachineExtensionNames=[{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B6664F-4972-11D1-A7CA-0000F87571E3}]`, `Version=1` (CRLF)
- `Windows/System32/GroupPolicy/Machine/Scripts/scripts.ini`: `[Startup]`, `0CmdLine=check.cmd`, `0Parameters=` (CRLF), plus an empty `psscripts.ini`
- `Windows/System32/GroupPolicy/Machine/Scripts/Startup/check.cmd`: for example `pnputil /enum-devices /class Display > C:\out.txt`
Output is ANSI text; read it with `tr -d '\r\000'`. Works while the NTFS volume is clean enough for ntfs3 to mount read-write.

Status: boots, GPU functions attach, resets clean. Driver installed and bound (see above); the live Device Manager state is the only part not seen.
