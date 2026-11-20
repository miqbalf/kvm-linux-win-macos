# Fans, keyboard RGB, battery limit (NitroSense on Linux)

Acer's NitroSense app is Windows only. On Linux the same controls come from the `linuwu_sense` kernel module
(a fork of the stock `acer_wmi` driver), plus a small app and command from this repo.

## Use
- App grid > **Nitro Control**: live fan RPM and temperatures, fan mode (Auto / Max / Custom % per fan),
  keyboard effect and colors per zone, brightness, speed, direction, lights off, "Stop charging at 80%".
  Changes apply right away.
- Terminal:
  ```
  nitro                           # status
  nitro fan auto | max            # EC fan curve, or both fans 100%
  nitro fan 60 70                 # CPU 60%, GPU 70% fixed
  nitro rgb red                   # all 4 zones red
  nitro rgb cyan magenta orange white 80   # zone 1 (left) .. zone 4 (right), brightness 80%
  nitro rgb off
  nitro effect breath red         # breath | neon | wave | shift | zoom | meteor | twinkle  [color speed brightness dir]
  nitro battery-limit on|off      # stop charging at 80%
  ```
- The last fan and keyboard setting comes back at every login (`nitro restore`, autostart). Settings are in
  `~/.config/nitro/state`.
- The Fn keys on the laptop keep working (the module also does what `acer_wmi` did: hotkeys, Wi-Fi/Bluetooth rfkill).

Measured 2026-11-20: Auto about 1500 / 1900 rpm idle, 50% about 3400 / 3900 rpm, Max about 5700 / 6100 rpm (CPU / GPU fan).

## Install
```
sudo bash laptop/host/nitrosense/install.sh
```
Then log out and in once. The script:
1. Checks the model is an AN515-55 (other models use other WMI payloads).
2. Takes a snapper snapshot ("before linuwu_sense").
3. Clones [BillyAddlers/Linuwu-Sense-AN515-55-Patch](https://github.com/BillyAddlers/Linuwu-Sense-AN515-55-Patch)
   to `~/src/Linuwu-AN515-55` at the tested commit, and runs its `scripts/install-dkms.sh`:
   DKMS module (rebuilt on every kernel update), `acer_wmi` blacklisted, `/etc/modules-load.d/linuwu_sense.conf`,
   `linuwu_sense.service`, group `linuwu_sense` with the user in it, `/etc/tmpfiles.d/linuwu_sense.conf`.
4. Installs from `host/nitrosense/`: `nitro`, `nitro-control` + menu entry, the login restore
   (`/etc/xdg/autostart/nitro-restore.desktop`) and a drop-in for `linuwu_sense.service` that sets the sysfs
   permissions after the module loads.

Driver files: `/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/` with `nitro_sense/` (fan_speed,
battery_limiter, battery_calibration, usb_charging, backlight_timeout), `four_zoned_kb/` (per_zone_mode,
four_zone_mode) and `hwmon/hwmon*/` (fan1/fan2 RPM, temps).

## Undo
```
sudo bash ~/src/Linuwu-AN515-55/scripts/uninstall-dkms.sh     # back to the stock acer_wmi
sudo rm /usr/local/bin/nitro /usr/local/bin/nitro-control /usr/local/share/applications/nitro-control.desktop \
  /etc/xdg/autostart/nitro-restore.desktop
sudo rm -r /etc/systemd/system/linuwu_sense.service.d
```
Or boot the snapshot "before linuwu_sense" from the Limine menu.

## Notes
- No thermal profiles (quiet / balanced / performance) on this model: `platform_profile probe failed` in dmesg is
  expected. Fans are set directly.
- The driver saves the keyboard state in `/etc/four_zone_kb_state` at shutdown, but already scaled by the
  brightness, so colors got dimmer after each reboot. The login restore re-sends the original values.
- The upstream tmpfiles rule runs before the module loads at boot, so the files stayed root-only:
  `10-permissions.conf` re-applies it from `linuwu_sense.service`.
- Do not `systemctl restart linuwu_sense.service`: its ExecStop unloads the module.
- With an older `acer_wmi`, `modprobe acer_wmi predator_v4=1` gives fan modes until the next reboot (no RGB).
