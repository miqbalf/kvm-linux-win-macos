# Native macOS (Hackintosh boot) on the laptop

The laptop also boots macOS directly from its own disk through OpenCore, without Linux underneath. This page
covers that native boot: the EFI, what was changed to make it fast and stable, the tools installed on it, how
it is monitored, and how CachyOS runs inside it as a VM. (macOS as a VM under CachyOS is in
[03-macos.md](03-macos.md).)

| | |
|---|---|
| Laptop | Acer Nitro 5 AN515-55: i5-10300H, UHD 630 (used), GTX 1650 Mobile (powered off), 32 GB RAM |
| Disks | Samsung SSD 980 1TB = macOS + OpenCore ESP; WD SN530 512GB = CachyOS; Seagate 2TB HDD = `DATA_2TB` |
| macOS | 26.7.3 Tahoe (25G342), SMBIOS MacBookPro16,2 |
| OpenCore | 1.0.8 (REL-108-2026-09-27) |
| EFI | [`Hackintosh_EFI/ACER_NITRO_5_AN_515_55`](../../Hackintosh_EFI/ACER_NITRO_5_AN_515_55) (full EFI, serials redacted) |

**Disk numbers change between boots** (`disk0`/`disk1` swap). Mount the OpenCore ESP by partition UUID, never by
number. Once, `disk1s1` was the Linux ESP. Check `diskutil info <id>` (Partition UUID, contents) before any write.

## What was improved (2026-11-21/22)

| Change | Why | Result |
|---|---|---|
| `Kernel > Quirks > SetApfsTrimTimeout` -1 to **0** | APFS trimmed all free space of the 980 on every boot: `spaceman_scan_free_blocks ... trims took 51.15 s` | dyld-to-launchd 34 s to 0.9 s; boot to login **101 s to 49 s** |
| Monthly full trim (`laptop/macos/apfs-trim`) | trim 0 means no boot trim; the DRAM-less 980 still needs TRIM now and then | sets -1 for one boot every 30 days, then back to 0 |
| Debug boot-args removed (`-v debug=0x100 keepsyms=1 swd_panic=1`), `Misc > Debug > Target` 3 to 0 | not needed day to day | quieter, slightly faster boot |
| OpenCore 1.0.7 to **1.0.8**, AppleALC 1.9.8, AirportBrcmFixup 2.2.1 | current releases | `ocvalidate`: no issues |
| Removed `XHCI-unsupported`, `CPUFriend`, `CPUFriendDataProvider`, `CtlnaAHCIPort`, `ACPIMonitor`, `SMCLightSensor`, `SSDT-FANT`, `SSDT-off-gpu` | unused, wrong data for this CPU, or duplicate (`SSDT-NoHybGfx` already turns off the dGPU) | fewer kexts; CPU power management still native (see audit) |
| `NitroEC.kext` added, injected by OpenCore | fans + keyboard RGB in macOS (patched NitroSense-macOS); loading it from `/Library/Extensions` failed after a reboot (AuxKC) | survives reboots; app + daemon from the DMG release |

Backups of every EFI state are on the laptop's data disk: `DATA_2TB/Hackintosh/EFI_20261122_current_backup`
(original), `EFI_20261122_trimfix_oc107`, `EFI_20261122_oc108` (before NitroEC).

Known boot delay that is **not** an EFI problem: Bitdefender's EndpointSecurity client makes the kernel wait
30 s (`(EndpointSecurity) Early boot timed out. Resuming execs`). Kept on purpose.

## Audit (2026-11-22, OpenCore 1.0.8)

Checked on the running system (ioreg, unified log, system_profiler, fsck), not only the config:

| Area | Evidence | State |
|---|---|---|
| CPU power management | `X86PlatformPlugin` loaded, `plugin-type = 1`, no speed or thermal limit recorded | OK (CPUFriend not needed) |
| dGPU off | `ioreg -l \| grep -c '"vendor-id" = <de100000>'` = 0; only UHD 630 in `system_profiler SPDisplaysDataType` | OK, GTX powered off by `SSDT-NoHybGfx` |
| iGPU | `AAPL,ig-platform-id` `0900A53E`, device-id `9B3E`, framebuffer active, 0 errors | OK |
| Audio | AppleALC layout 21, internal speaker + microphone | OK |
| Wi-Fi / Bluetooth | Broadcom Wi-Fi `en1`; BCM20702 Bluetooth on | OK |
| USB | USBToolBox map; internal hub, BT, webcam present | OK |
| ACPI | EC, PNLF, PMCR, HPET, USBX, SBUS present; 0 ACPI errors | OK |
| Kexts | 30 third-party kexts loaded, 0 kext errors per boot (Apple's own `AppleKIS`, PPP and `IOVersatile` load failures are normal) | OK |
| APFS | `diskutil verifyVolume` on the Data volume: `appears to be OK` | OK |
| Boot | dyld +1 s, launchd +2 s, Data +3-5 s, ES +35 s, login +49-50 s | OK |
| NVMe | 4 to 39 `AppleNVMe Assert failed` lines per boot, mostly when a FAT partition is opened or closed | **watch** (the 980 had a `Loss of MMIO space` panic on 2026-11-21, during the old boot-trim window; none since) |
| Battery | 2575 of 3733 mAh design (69 %) | worn cell (hardware) |
| Sleep | sleep and wake work; wake reason always `XDCI CNVW/`; a DarkWake loop (wake every 10-20 s) on 2026-11-18 | **watch**, see below |
| `hibernatemode` | 25: every sleep writes all RAM (32 GB) to the 980 | recommend `sudo pmset -a hibernatemode 0` (not yet applied) |
| Shutdown cause | VirtualSMC reports 5 ("software initiated") even after a kernel panic or forced power-off | unreliable; do not use it as evidence |

Temperatures: CPU 73-92 °C at light load. In the audit the load came from Google Drive (`fileproviderd` 267 %
CPU) and Spotlight, not from power management.

## Tools installed on macOS

| Tool | Path in repo | What | Command |
|---|---|---|---|
| NitroSense (NitroEC) | `laptop/macos/nitrosense` | fans + keyboard RGB; app, daemon `nitrod`, `nitroctl` | `nitroctl status` |
| apfs-trim-cycle | `laptop/macos/apfs-trim` | full APFS trim once every 30 days | `apfs-trim-cycle status` |
| hackmon | `laptop/macos/hackmon` | one report per boot (timeline, panics, NVMe/ACPI/kext/iGPU errors, temps) + daily errors | `hackmon summary`, `hackmon last` |
| sleepmon | `laptop/macos/sleepmon` | every sleep/wake cycle; failed wakes detected at the next boot | `sleepmon-report` |
| cachyos-vm | `laptop/macos/cachyos-vm` | the real CachyOS disk in VMware Fusion; Linux apps as Mac windows (xpra) | `cachyos-vm`, `linux-app <app>` |

Logs: `/Library/Logs/HackMon/`, `/Library/Logs/SleepMon/`, `/var/log/nitrod.log`.

## Monitoring: what to look at

- After a few days: `hackmon summary` (one row per boot). Slow boot = look at `login_s`; stability = `panics30d`,
  `nvme`, `kext`. A new `Kernel-*.panic` in `/Library/Logs/DiagnosticReports` is the first thing to read.
- After a bad wake: `sleepmon-report`. It shows `FAILED WAKE` and the cycle number of the sleep that failed.
- Planned fix once a failed wake is captured: stop `XDCI` (USB device controller) and `CNVW` (CNVi wireless, no
  Intel card in this laptop) from waking the machine (`_PRW` / `GPRW` instant-wake patch), and set
  `hibernatemode 0`.

## CachyOS inside macOS (VMware Fusion, same physical disk)

Details in [`laptop/macos/cachyos-vm/README.md`](../macos/cachyos-vm/README.md). Summary:
- One Linux install: the VM boots the real SN530 disk (raw disk). No second VM disk.
- VMware asks for an admin password before it opens the raw disk, and that dialog only works with the Fusion
  window. Start: `cachyos-vm` (or click a Linux app), enter the password, hide the window with Cmd+H.
- Linux apps as Mac windows with xpra (Fusion's Unity mode is Windows-only): `~/Applications/CachyOS Apps`.
- Idle: the VM is **paused** after 15 min without Linux windows (no CPU, RAM kept, VMware keeps the disk).
  Clicking an app unpauses it.
- macOS shutdown/restart/logout: `cachyos-vm-guard` shuts CachyOS down cleanly first, so booting CachyOS
  natively afterwards is safe.
- **Never suspend the VM** and never boot CachyOS natively while it is suspended or running.

Incident 2026-11-22: after a VM suspend, VMware's MountHelper mounted the guest's `/boot` (FAT) in macOS while
the suspended guest still had it open. macOS's FAT driver looped on
`cluster 13084 is free where it should be in use` (2.4 million log lines in 13 min) and the Mac froze.
`fsck_msdos -y /dev/rdiskNs1` fixed it; only macOS Spotlight files on the ESP were damaged. Fixes: pause instead
of suspend, `release_disk` after stop, `/boot` automount in the guest (`guest-fix-boot.sh`), VM reduced to
4 vCPU / 8 GB.

## Open items

- Run `guest-fix-boot.sh` in CachyOS once (needs sudo in the guest).
- Decide `hibernatemode 0`.
- Wake-source fix for `XDCI` / `CNVW` after sleepmon captures a failed wake.
- NitroSense: hide the "Nitro mode" control on the AN515-55 (firmware rejects WMBH 0x16 with status 0x01);
  status lines "Nitro mode" and "Power" use AN515-57 semantics.
- Keep watching the NVMe asserts on the Samsung 980.
