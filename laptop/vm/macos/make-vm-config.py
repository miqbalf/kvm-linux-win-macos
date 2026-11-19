#!/usr/bin/env python3
"""Turn the laptop's real Hackintosh OpenCore config into a VM-only config.

Usage: python3 make-vm-config.py <in config.plist> <out config.plist> [--igpu] [--serial]
  --serial: add serial=3 (kernel log on the VM serial port). Debug only: on the desktop it caused boot panics.
  --igpu: keep the real iGPU DeviceProperties (UHD 630 passed through at 00:02.0, domain macos-igpu)
Reads the real config (XML or binary), writes XML (OpenCore cannot parse binary plists).
SMBIOS is kept as-is and is never printed. The real EFI on nvme1n1 is never touched.

Why each change (2026-11-19 laptop VM boot):
- binary plist  -> "OC: Failed to parse configuration!"
- laptop ACPI tables (DMAR, EC, PNLF, XOSI, ...) describe Acer hardware that QEMU does not have
- ProtectUefiServices is a real-firmware quirk; OVMF hit a #GP inside an OpenCore image with it on
- hardware kexts (touchpad, Realtek, Broadcom, battery, sensors) have no device in the VM
"""
import plistlib, sys

src, dst = sys.argv[1], sys.argv[2]
IGPU = '--igpu' in sys.argv[3:]
d = plistlib.load(open(src, 'rb'))

# ACPI: no laptop tables, renames or deletes in the VM.
for sect in ('Add', 'Patch', 'Delete'):
    for e in d['ACPI'].get(sect, []):
        e['Enabled'] = False

if IGPU:
    # Panel backlight device for AppleBacklight/WhateverGreen; without it the eDP panel stays dark.
    for e in d['ACPI'].get('Add', []):
        if e.get('Path') == 'SSDT-PNLF.aml':
            e['Enabled'] = True

# Booter: firmware quirks for real boards off.
d['Booter']['Quirks']['ProtectUefiServices'] = False

# Kexts: keep the VM core plus what an OCLP-patched install expects.
KEEP = {
    'Lilu.kext', 'VirtualSMC.kext', 'WhateverGreen.kext', 'RestrictEvents.kext',
    'AMFIPass.kext', 'IOSkywalkFamily.kext', 'IO80211FamilyLegacy.kext',
    'IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext', 'BlueToolFixup.kext',
}
for k in d['Kernel']['Add']:
    k['Enabled'] = k['BundlePath'] in KEEP
d['Kernel']['Quirks']['ProvideCurrentCpuInfo'] = True

# boot-args: drop laptop-only args (iGPU backlight, Broadcom, RTC, audio).
nv = d['NVRAM']['Add'].setdefault('7C436110-AB2A-4BBB-A880-FE41995C9F82', {})
nv['boot-args'] = '-v keepsyms=1 debug=0x100 revpatch=sbvmm -amfipassbeta'
if IGPU:
    # from the real laptop config: keep the panel online, backlight register fix
    # amfi=0x80: with the iGPU attached, applekeystored died on the OCLP-patched IO80211.framework
    # (code signature) despite AMFIPass -> kernel panic, black screen (2026-11-19).
    nv['boot-args'] += ' igfxonln=1 -igfxblr amfi=0x80'
    # No verbose text on the real panel: drawing it into the uncached GOP framebuffer is so slow
    # that XNU times out starting the other CPUs ("Failed to start CPU 01, rebooting", 2026-11-19).
    nv['boot-args'] = nv['boot-args'].replace('-v ', '', 1)
if '--serial' in sys.argv[3:]:
    nv['boot-args'] += ' serial=3 msgbuf=1048576'
d['NVRAM'].setdefault('Delete', {}).setdefault('7C436110-AB2A-4BBB-A880-FE41995C9F82', [])
if 'boot-args' not in d['NVRAM']['Delete']['7C436110-AB2A-4BBB-A880-FE41995C9F82']:
    d['NVRAM']['Delete']['7C436110-AB2A-4BBB-A880-FE41995C9F82'].append('boot-args')

# DeviceProperties: only the vmxnet3 NIC at 00:04.0 (built-in so macOS creates a network service).
props = d['DeviceProperties']['Add']
nic = props.get('PciRoot(0x0)/Pci(0x4,0x0)', {})
nic['built-in'] = b'\x01'
new = {'PciRoot(0x0)/Pci(0x4,0x0)': nic}
if IGPU and 'PciRoot(0x0)/Pci(0x2,0x0)' in props:
    new['PciRoot(0x0)/Pci(0x2,0x0)'] = props['PciRoot(0x0)/Pci(0x2,0x0)']
d['DeviceProperties']['Add'] = new

# UEFI drivers: only OpenRuntime. HfsPlus.efi (Apple binary) and AudioDxe fault (#GP) under the
# strict memory protection of current OVMF builds. The macOS disk is APFS, OpenCore loads apfs.efi itself.
for drv in d['UEFI']['Drivers']:
    drv['Enabled'] = drv.get('Path') in ('OpenRuntime.efi', 'ResetNvramEntry.efi')
if IGPU:
    # Intel GOP from the laptop BIOS + a minimal PLATFORM_GOP_POLICY (gop-policy/): the GOP refuses to
    # start without that protocol. With it the GOP lights the eDP panel before macOS, and macOS reuses
    # that link (without it macOS does 4-lane fast link training and the panel stays dark).
    # Policy first, then the GOP; ConnectDrivers binds the GOP to the iGPU.
    names = [x.get('Path') for x in d['UEFI']['Drivers']]
    for path in ('IntelGopDriver.efi', 'PlatformGopPolicy.efi'):
        if path not in names:
            d['UEFI']['Drivers'].insert(0, {'Arguments': '', 'Comment': path, 'Enabled': True,
                                            'LoadEarly': False, 'Path': path})
    d['UEFI']['Drivers'].sort(key=lambda x: {'PlatformGopPolicy.efi': 0, 'IntelGopDriver.efi': 1}.get(x.get('Path'), 2))
    for drv in d['UEFI']['Drivers']:
        if drv.get('Path') in ('PlatformGopPolicy.efi', 'IntelGopDriver.efi'):
            drv['Enabled'] = True
    d['UEFI']['ConnectDrivers'] = True
d['UEFI'].setdefault('Audio', {})['AudioSupport'] = False
d['UEFI'].setdefault('APFS', {})['EnableJumpstart'] = True

# Picker: built-in text picker, longer timeout, so VNC shows what happens.
d['Misc']['Boot']['PickerMode'] = 'Builtin'
d['Misc']['Boot']['Timeout'] = 5
if IGPU:
    # No firmware display on the panel before macOS (OVMF has no Intel GOP): a picker would be
    # invisible and a stray key press stops its countdown. Boot the default entry directly.
    d['Misc']['Boot']['ShowPicker'] = False

plistlib.dump(d, open(dst, 'wb'), fmt=plistlib.FMT_XML, sort_keys=False)
print('kexts on:', [k['BundlePath'] for k in d['Kernel']['Add'] if k['Enabled']])
print('wrote', dst)
