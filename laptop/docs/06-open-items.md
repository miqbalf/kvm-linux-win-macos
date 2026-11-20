# Open items and ideas

- Windows activation: needs a volume license key for LTSC.
- Fingerprint: the MAFP dongle is dead; replace it with a libfprint-supported reader.
- `win-gpu stop` from the app grid (polkit dialog) is not yet tested; `sudo gpu-mode win-off` is.
- Windows on the GTX while macOS has the panel: possible in theory (different GPUs), not tested.
- Optional: remove the installer disk from `win10.xml` once Windows is set up.
- Fan/RGB: the driver has no thermal profiles on this model; a custom fan curve (temperature -> %) could be
  a small user service on top of `nitro fan`.
