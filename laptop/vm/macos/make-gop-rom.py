#!/usr/bin/env python3
"""Wrap the laptop's Intel GOP driver (UEFI x64 PE) into a PCI option ROM for the passed-through iGPU.

Why: OVMF has no Intel graphics driver, so with the UHD 630 passed through nobody powers the eDP
panel before macOS, and macOS then finds no display at all (black screen, 2026-11-19). The GOP from
the laptop's own BIOS, given to the VM as the iGPU's option ROM, lets OVMF light the panel.

Get the GOP (read-only, nothing is written to the BIOS):
  sudo flashrom -p internal --ifd -i bios -r bios-region.bin
  uefi-firmware-parser -b -e -q -o extract bios-region.bin      (pip install uefi_firmware)
  the PE whose UTF-16 strings contain "Intel(R) GOP Driver" (AN515-55 BIOS V2.06: file 7755CA7B-...)
The GOP binary is Intel's: it is not committed (gitignored *.efi, *.rom).

Usage: make-gop-rom.py IntelGopDriver.efi out.rom [vendor_hex device_hex]   (default 8086 9bc4)
Same layout as edk2 EfiRom without compression: EFI ROM header, PCIR 3.0, PE image, 512-byte padded.
"""
import struct, sys

src, dst = sys.argv[1], sys.argv[2]
vendor = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x8086
device = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x9BC4

pe = open(src, 'rb').read()
assert pe[:2] == b'MZ', 'not a PE image'
peoff = struct.unpack_from('<I', pe, 0x3C)[0]
assert pe[peoff:peoff + 4] == b'PE\0\0', 'no PE signature'
machine = struct.unpack_from('<H', pe, peoff + 4)[0]
subsystem = struct.unpack_from('<H', pe, peoff + 0x5C)[0]
assert machine == 0x8664 and subsystem in (11, 12), f'expected x64 driver, got machine {machine:#x} subsystem {subsystem}'

HDR, PCIR = 0x1C, 0x1C
img_off = (HDR + PCIR + 0x1F) & ~0x1F          # 32-byte aligned image start
total = img_off + len(pe)
total = (total + 511) & ~511
blocks = total // 512
assert blocks <= 0xFFFF

rom = bytearray(total)
# EFI_PCI_EXPANSION_ROM_HEADER
struct.pack_into('<HHIHHH8sHH', rom, 0,
                 0xAA55, blocks, 0x0EF1, subsystem, machine, 0,   # sig, init size, EFI sig, subsys, machine, uncompressed
                 b'\0' * 8, img_off, HDR)                          # reserved, image offset, PCIR offset
# PCI_3_0_DATA_STRUCTURE
struct.pack_into('<4sHHHHB3sHHBBHHH', rom, HDR,
                 b'PCIR', vendor, device, 0, PCIR, 3,
                 bytes([0x00, 0x00, 0x03]),                        # class code: VGA (prog-if, subclass, base class)
                 blocks, 0, 3, 0x80,                               # image length, code rev, code type EFI, last image
                 blocks, 0, 0)
rom[img_off:img_off + len(pe)] = pe
open(dst, 'wb').write(rom)
print(f'{dst}: {total} bytes, {vendor:04x}:{device:04x}, image at {img_off:#x}')
