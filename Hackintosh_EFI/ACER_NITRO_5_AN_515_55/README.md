# OpenCore EFI: Acer Nitro 5 AN515-55 (native macOS)

Working EFI of the laptop's native Hackintosh, copied from the boot EFI (`disk1s1`, Samsung SSD 980) on 2026-11-22.

| | |
|---|---|
| Laptop | Acer Nitro 5 AN515-55: i5-10300H, UHD 630 (used), GTX 1650 Mobile (disabled), 32 GB RAM |
| Disks | Samsung SSD 980 1TB (macOS), WD SN530 512GB (Linux), Seagate ST2000LM015 2TB HDD (data) |
| macOS | 26.7.3 Tahoe (25G342), SMBIOS MacBookPro16,2 |
| OpenCore | 1.0.7 RELEASE |
| SIP | `csr-active-config` `03080000` (unsigned kexts allowed) |

**Serials are removed.** Before booting, generate your own SMBIOS (MacBookPro16,2) with GenSMBIOS and fill in
`PlatformInfo > Generic`: `SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM` (and the same values under
`PlatformInfo > SMBIOS` if you use it). The placeholders are `REPLACE_WITH_YOUR_SERIAL`, `REPLACE_WITH_YOUR_MLB`,
an all-zero UUID and an all-zero ROM.

## Key choices
- dGPU off: `SSDT-NoHybGfx` + `-wegnoegpu`. macOS has no Turing (GTX 1650) driver.
- iGPU: WhateverGreen, `igfxonln=1`, `-igfxblr -igfxblt -igfxbls` (backlight).
- Wi-Fi: Broadcom via OCLP-style `IOSkywalkFamily` + `IO80211FamilyLegacy` + `AirportBrcmFixup`, AMFIPass
  (`-amfipassbeta`), `revpatch=sbvmm` (RestrictEvents) for updates. Realtek USB Wi-Fi kexts (`RtWlanU*`) are for
  a USB dongle.
- Input: VoodooPS2 (keyboard) + VoodooI2C/HID (trackpad).
- NVMe: NVMeFix. **`Kernel > Quirks > SetApfsTrimTimeout = 0`** (see below).

## Changes on 2026-11-22 (boot speed and stability)
1. `SetApfsTrimTimeout` -1 to **0**. The unified log showed APFS trimming all free space of the Samsung 980 on every
   boot before mounting the Data volume:
   `spaceman_scan_free_blocks: disk3 scan took 51.830329 s, trims took 51.154083 s` (886,592 extents).
   That is the ~35-50 s stall right after the dyld shared cache in verbose boot. The last Samsung panic
   (`nvme: "3rd party NVMe controller. Loss of MMIO space"`, 2026-11-21 23:38) also happened during boot, in this
   window. 0 disables the boot-time trim (macOS 12+ accepts only 0 or -1). The 980 still does its own garbage
   collection.
2. Debug boot-args removed: `-v debug=0x100 keepsyms=1 swd_panic=1`.
3. `Misc > Debug > Target` 3 to 0.

Monthly full trim: `laptop/macos/apfs-trim/` (`bash install.sh`) installs a LaunchDaemon that keeps
`SetApfsTrimTimeout = 0` but sets -1 once every 30 days, so the next boot does one full trim (about a minute
longer); at the following startup it puts 0 back. `sudo apfs-trim-cycle now` forces a full trim on the next
reboot, `apfs-trim-cycle status` shows the state. Keep 20 % or more of the 980 free: without TRIM a nearly
full DRAM-less SSD slows down (2026-11-22: 91 GB free of 931 GB).

Other boot delay, not EFI: Bitdefender's Endpoint Security early-boot client makes the kernel wait 30 s
(`(EndpointSecurity) Early boot timed out. Resuming execs`). Kept on purpose.

How to measure a boot (no verbose needed):
```
/usr/bin/log show --last boot --style compact --predicate 'eventMessage CONTAINS "spaceman_scan_free_blocks" OR eventMessage CONTAINS "hello, launchd" OR eventMessage CONTAINS "Early boot timed out"'
```
(`/usr/bin/log`, not `log`: zsh has a `log` builtin.)

Backup of the EFI before these changes: `DATA_2TB/Hackintosh/EFI_20261122_current_backup` on the laptop.
