# Open items and ideas

- Windows activation: needs a volume license key for LTSC.
- Fingerprint: the MAFP dongle is dead; replace it with a libfprint-supported reader.
- `win-gpu stop` from the app grid (polkit dialog) is not yet tested; `sudo gpu-mode win-off` is.
- Windows on the GTX while macOS has the panel: possible in theory (different GPUs), not tested.
- Optional: remove the installer disk from `win10.xml` once Windows is set up.
- Fan/RGB: the driver has no thermal profiles on this model; a custom fan curve (temperature -> %) could be
  a small user service on top of `nitro fan`.

Native macOS boot (details in [11-native-macos.md](11-native-macos.md)):
- Run `laptop/macos/cachyos-vm/guest-fix-boot.sh` once in CachyOS (`/boot` automount, Spotlight block, idle inhibitor).
- Decide `sudo pmset -a hibernatemode 0` (now 25: every sleep writes 32 GB to the Samsung 980).
- Wake-source fix for `XDCI` / `CNVW` (`_PRW`/`GPRW` patch) once sleepmon captures a failed wake.
- NitroSense on macOS: hide "Nitro mode" (WMBH 0x16 rejected on the AN515-55); fix the "Nitro mode"/"Power" status lines.
- Watch `AppleNVMe Assert failed` counts in `hackmon summary`.
