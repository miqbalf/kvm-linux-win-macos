# USB fingerprint reader (MicroarrayTechnology MAFP, 3274:8012)

Device: small USB fingerprint dongle, `lsusb`: `3274:8012 MicroarrayTechnology MAFP General Device`
(sold as "TNP Nano USB Fingerprint Reader"). Plug it straight into the laptop, not through a hub
(through a hub it failed with `device descriptor read/64, error -110`).

Status 2026-11-20: **this reader does not work, on Linux or Windows.** Replace it with a reader that libfprint
lists as supported (https://fprint.freedesktop.org/supported-devices.html).

Evidence:
- stock `mafpmoc` and the community `microarray` driver both stop at the first reply: `transfer timed out`;
- raw USB probe (pyusb): writes to EP 0x03 are accepted, but nothing ever comes back on EP 0x83 or 0x82, for the
  handshake (0x23) and for VfyPwd 0x13, ReadSysPara 0x0F, 0x1D, also after a USB reset;
- passed through to the Windows VM: Windows installs the maker's driver ("Microarray Fingerprint Reader",
  18.5.54.172, `MafpWinbioSensor.DLL`), but the device fails with Code 10 ("cannot start") and
  `WinBioEnumBiometricUnits` finds 0 fingerprint units.

## What happened
| Where | Result |
|---|---|
| Ubuntu 26.04 PC (libfprint 1.95.1+tod1) | `No devices available`: no driver for 3274:8012 |
| Laptop, CachyOS libfprint 1.94.100 (`mafpmoc` lists 3274:8012) | device found, but enroll fails: `Open failed with error: transfer timed out`, USB resets, then `Device 3274:8012 is already open` |
| Upstream | "mafpmoc: add PID 8012" is MR !492, a draft |

## Fix
Community driver [jdillon/libfprint-microarray](https://github.com/jdillon/libfprint-microarray) (v1.0.0,
reverse engineered from the Windows driver, enroll and verify confirmed on this reader model), compiled into
libfprint 1.94.100. Only fprintd uses it; pacman's libfprint stays untouched.
```
bash laptop/host/fingerprint/install.sh     # as your user; builds, then sudo: snapshot + install
fprintd-enroll                              # on the laptop itself (not over SSH): touch until enroll-completed
fprintd-verify                              # expect verify-match
```
What `install.sh` puts on the system:
| File | Why |
|---|---|
| `/usr/local/lib/libfprint-microarray/libfprint-2.so.2*` | libfprint with driver `microarray` claiming 3274:8012 (removed from `mafpmoc`) |
| `/etc/systemd/system/fprintd.service.d/10-microarray.conf` | `LD_LIBRARY_PATH` for fprintd only |
| `/etc/udev/rules.d/61-mafp-no-autosuspend.rules` | USB autosuspend off for the reader |

Undo: delete those three, `sudo systemctl daemon-reload && sudo systemctl restart fprintd` (or the snapper
snapshot "before libfprint-microarray").

Build note: meson 1.9 fails with `-Dintrospection=false` (`tests/meson.build: Foreach expects exactly 2
variables`), so the build keeps introspection on.

Driver limits (from its README): every new enrollment clears all fingerprints stored on the reader; no identify
(1:N), only verify. Login/sudo with the finger (PAM) is a later step, after verify works.
