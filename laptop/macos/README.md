# Tools for the native macOS boot (Hackintosh)

Overview, EFI changes, audit and monitoring: [../docs/11-native-macos.md](../docs/11-native-macos.md).
EFI: [../../Hackintosh_EFI/ACER_NITRO_5_AN_515_55](../../Hackintosh_EFI/ACER_NITRO_5_AN_515_55).

| Folder | What | Install (on macOS) |
|---|---|---|
| `nitrosense/` | patched NitroSense-macOS for the AN515-55: `NitroEC.kext` (fans + RGB), app, daemon | DMG from the GitHub release `nitrosense-an515-55-v1.1.0`; kext injected by OpenCore |
| `apfs-trim/` | full APFS trim once every 30 days (boot trim is off) | `bash install.sh` |
| `hackmon/` | per-boot report: timeline, panics, NVMe/ACPI/kext/iGPU errors, temperatures | `bash install.sh` |
| `sleepmon/` | sleep/wake logger, failed-wake detection | `bash install.sh` |
| `cachyos-vm/` | real CachyOS disk in VMware Fusion, Linux apps as Mac windows (xpra), idle pause, shutdown guard | `bash setup.sh`, then `bash install-coherence.sh` on the desktop |
