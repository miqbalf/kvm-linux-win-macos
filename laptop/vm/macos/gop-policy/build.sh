#!/bin/bash
# Build PlatformGopPolicy.efi (UEFI boot-service driver) with gnu-efi.
# Usage: build.sh [vbt.bin] [out.efi]   default vbt: this laptop's i915 VBT from debugfs (host mode only)
set -euo pipefail
cd "$(dirname "$0")"
VBT=${1:-}
OUT=${2:-PlatformGopPolicy.efi}
if [ -z "$VBT" ]; then
  VBT=$(mktemp); sudo cat /sys/kernel/debug/dri/0000:00:02.0/i915_vbt > "$VBT"
fi
[ "$(head -c4 "$VBT")" = '$VBT' ] || { echo "not a VBT: $VBT"; exit 1; }
xxd -i -n vbt_bin "$VBT" > vbt.h
B=$(mktemp -d)
gcc -I/usr/include/efi -I/usr/include/efi/x86_64 -DGNU_EFI_USE_MS_ABI -O2 -fpic -ffreestanding \
    -fno-stack-protector -fno-stack-check -fshort-wchar -mno-red-zone -maccumulate-outgoing-args \
    -Wall -c PlatformGopPolicy.c -o "$B/p.o"
ld -shared -Bsymbolic -nostdlib -T /usr/lib/elf_x86_64_efi.lds /usr/lib/crt0-efi-x86_64.o "$B/p.o" \
   -o "$B/p.so" -L/usr/lib -lgnuefi -lefi
objcopy -I elf64-x86-64 -O pei-x86-64 --subsystem=efi-bsd -j .text -j .sdata -j .data -j .rodata -j .dynamic -j .dynsym -j .rel -j .rela -j '.rel.*' \
        -j '.rela.*' -j .reloc "$B/p.so" "$OUT"
rm -rf "$B"
echo "built $OUT ($(stat -c %s "$OUT") bytes)"
