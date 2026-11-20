# Open items and ideas

- Fan and keyboard RGB (NitroSense on Linux): candidate is the Linuwu-Sense AN515-55 patch (DKMS, replaces
  `acer_wmi`, 4-zone RGB, fan Auto/Max). Not installed. Take a snapper snapshot first.
  (`acer_wmi predator_v4=1` works for a test until the next reboot.)
- Windows activation: needs a volume license key for LTSC.
- Fingerprint: the MAFP dongle is dead; replace it with a libfprint-supported reader.
- `win-gpu stop` from the app grid (polkit dialog) is not yet tested; `sudo gpu-mode win-off` is.
- Windows on the GTX while macOS has the panel: possible in theory (different GPUs), not tested.
- Optional: remove the installer disk from `win10.xml` once Windows is set up.
