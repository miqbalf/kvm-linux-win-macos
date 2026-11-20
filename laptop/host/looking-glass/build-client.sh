#!/bin/bash
# Build and install the Looking Glass B7 client (must match the B7 host app in Windows).
#   sudo bash laptop/host/looking-glass/build-client.sh
# Source: looking-glass.io/artifact/B7/source. Build runs as the calling user in ~/src.
set -euo pipefail
USER_NAME=${SUDO_USER:?run with sudo from your user account}
SRC=$(getent passwd "$USER_NAME" | cut -d: -f6)/src
pacman -S --needed --noconfirm cmake spice-protocol wayland-protocols libsamplerate nettle libxpresent \
  libpipewire libpulse fontconfig libxkbcommon libxi libxss libxinerama libxcursor libxrandr binutils >/dev/null
sudo -u "$USER_NAME" bash -s "$SRC" <<'BUILD'
set -euo pipefail
SRC=$1; mkdir -p "$SRC"; cd "$SRC"
[ -s looking-glass-B7.tar.gz ] || curl -fsSL -o looking-glass-B7.tar.gz https://looking-glass.io/artifact/B7/source
[ -d looking-glass-B7 ] || tar xzf looking-glass-B7.tar.gz
cd looking-glass-B7
# nettle 4 (CachyOS 2026) dropped the length argument of sha1_digest(); PureSpice B7 still passes it.
f=repos/PureSpice/src/rsa.c
if ! grep -q NETTLE_VERSION_MAJOR "$f"; then
  sed -i 's|#include <nettle/asn1.h>|#include <nettle/version.h>\n#include <nettle/asn1.h>|' "$f"
  sed -i 's|^\(\s*\)sha1_digest(&ctx, SHA1_HASH_LEN, hash);|#if NETTLE_VERSION_MAJOR >= 4\n\1sha1_digest(\&ctx, hash);\n#else\n\1sha1_digest(\&ctx, SHA1_HASH_LEN, hash);\n#endif|' "$f"
fi
mkdir -p client/build && cd client/build
cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_BACKTRACE=no .. >/dev/null
make -j"$(nproc)" >/dev/null
BUILD
make -C "$SRC/looking-glass-B7/client/build" install >/dev/null
echo "installed: $(command -v looking-glass-client)"
