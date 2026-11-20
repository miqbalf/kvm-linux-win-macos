#!/bin/bash
# USB fingerprint reader MicroarrayTechnology MAFP (3274:8012, "TNP Nano") on the laptop.
# CachyOS libfprint 1.94.100 lists 3274:8012 under its mafpmoc driver, but opening fails:
#   "Open failed with error: transfer timed out" (USB resets), then "Device 3274:8012 is already open".
# Fix: libfprint 1.94.100 + the community driver jdillon/libfprint-microarray (reverse engineered from
# the Windows driver, enroll + verify confirmed), built here and used only by fprintd:
#   /usr/local/lib/libfprint-microarray/  +  fprintd drop-in LD_LIBRARY_PATH  (pacman files untouched;
#   a libfprint update does not undo it; remove = delete the drop-in and that folder).
# Plus: USB autosuspend off for this reader (udev).
# Run as your user (asks for sudo):  bash laptop/host/fingerprint/install.sh
# Then: fprintd-enroll   and   fprintd-verify   in a terminal on the laptop.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LIBFPRINT_TAG=v1.94.100                                        # = pacman libfprint 1.94.100
DRIVER_COMMIT=82cd97e                                          # jdillon/libfprint-microarray v1.0.0
SRC=$HOME/src
[ "$(id -u)" != 0 ] || { echo "run as your user, not root"; exit 1; }

mkdir -p "$SRC"
[ -d "$SRC/libfprint/.git" ] || git clone -q https://gitlab.freedesktop.org/libfprint/libfprint.git "$SRC/libfprint"
[ -d "$SRC/libfprint-microarray/.git" ] || git clone -q https://github.com/jdillon/libfprint-microarray "$SRC/libfprint-microarray"
git -C "$SRC/libfprint-microarray" checkout -q "$DRIVER_COMMIT"

cd "$SRC/libfprint"
git checkout -q -f "$LIBFPRINT_TAG" && git checkout -q -B microarray-8012
mkdir -p libfprint/drivers/microarray
cp "$SRC/libfprint-microarray/src/microarray.c" libfprint/drivers/microarray/
# 3274:8012 goes to the new driver, not mafpmoc.
sed -i '/{ .vid = 0x3274,  .pid = 0x8012,  },/d' libfprint/drivers/mafpmoc/mafpmoc.c
grep -q "'microarray'" meson.build || sed -i "s/^\(\s*\)'mafpmoc': {},/\1'mafpmoc': {},\n\1'microarray': {},/" meson.build
grep -q "drivers/microarray" libfprint/meson.build ||
  sed -i "s|^\(\s*\)'mafpmoc' : files('drivers/mafpmoc/mafpmoc.c'),|&\n\1'microarray' : files('drivers/microarray/microarray.c'),|" libfprint/meson.build
# introspection=true: with it off, meson 1.9 fails in tests/meson.build ("Foreach expects exactly 2 variables").
[ -f build/build.ninja ] || meson setup build --prefix=/usr -Ddoc=false -Dgtk-examples=false -Dintrospection=true -Dinstalled-tests=false >/dev/null
ninja -C build >/dev/null
LIB=build/libfprint/libfprint-2.so.2.0.0
# grep the file directly: "strings | grep -q" dies of SIGPIPE under pipefail and looks like a failure.
grep -qa FpiDeviceMicroarray "$LIB" || { echo "build has no microarray driver"; exit 1; }

echo "installing (sudo)"
sudo snapper -c root create -d "before libfprint-microarray" || true
sudo install -Dm755 "$LIB" /usr/local/lib/libfprint-microarray/libfprint-2.so.2.0.0
sudo ln -sf libfprint-2.so.2.0.0 /usr/local/lib/libfprint-microarray/libfprint-2.so.2
sudo install -Dm644 "$HERE/10-microarray.conf" /etc/systemd/system/fprintd.service.d/10-microarray.conf
sudo install -Dm644 "$HERE/61-mafp-no-autosuspend.rules" /etc/udev/rules.d/61-mafp-no-autosuspend.rules
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=3274
sudo systemctl daemon-reload && sudo systemctl restart fprintd
sleep 2
fprintd-list "$USER" 2>&1 | head -3 || true
echo "Now: fprintd-enroll   (touch the sensor until enroll-completed), then fprintd-verify"
