# Acer Nitro AN515-55 Hackintosh — NullMoth Optimus & EFI Automation

Bare-metal **macOS Tahoe** configuration, automated EFI backup tooling, ACPI RTD3 builders, and **NullMoth (`nvidia-macos-driver`) Optimus offload patches** for the **Acer Nitro AN515-55** (`i5-10300H`, Intel UHD 630 + NVIDIA GTX 1650 Mobile `10de:1f99`, SMBIOS `MacBookPro16,2`).

> **Scope & License Notice**
> - Upstream [`nullmoth/nvidia-macos-driver`](https://github.com/nullmoth/nvidia-macos-driver) is licensed under **PolyForm-Noncommercial-1.0.0**.
> - This repository stores only our source patches (`patches/`), pure-Python ACPI AML generator (`opencore/acpi/`), per-app policy template (`opencore/nvmtl-gpu-policy.txt`), sanitized `config.plist`, and automation scripts. Compiled NullMoth binaries, local EFI raw backups, and clones stay in gitignored directories (`efi-backup/`, `work/`, `out/`).

---

## 1. Hardware Reality: MUXless Optimus on macOS

On the Acer Nitro AN515-55:

| Display Path / GPU | Hardware Wiring | Role on macOS Tahoe |
|---|---|---|
| **Intel UHD 630** (`0x3e9b`) | Drives internal 144 Hz eDP panel (`AppleIntelCFLGraphicsFramebuffer` via WhateverGreen) | Primary display & `WindowServer` compositor |
| **NVIDIA GTX 1650 Mobile** (`10de:1f99`) | Physical HDMI output only (no hardware MUX; USB-C has no DP Alt Mode) | Headless Metal offload (`debug.nvaccel_headless=1`) + optional HDMI external display |

Because there is no hardware display MUX switch, software cannot re-wire the internal laptop panel electrically to the dGPU. "Optimus switching" works as **render offload + idle D3cold power-down**:

1. **UHD 630** owns the internal screen and `WindowServer`.
2. **GTX 1650** executes Metal workloads for selected apps (`IOSurface` copy-out to UHD 630) via `NVMTLDriver.bundle`.
3. **Per-app policy** ([`nvmtl-gpu-policy.txt`](opencore/nvmtl-gpu-policy.txt)) & **NitroGPU Switcher** ([`app/`](app/NitroGPU.swift)) let you switch modes like NitroSense: **Auto (`mode apple`)**, **NVIDIA (`mode nvidia`)**, and **iGPU Eco (`mode igpu`)**.
4. **Auto-HDMI** (`nvfbhotplugpoll=2` + `nitro-gpu-ctl arm-hdmi` / LaunchDaemon) polls Turing HDMI connectors every 2 s and arms hot-plugged displays without forcing an external monitor at boot.
5. **RTD3 D3cold** ([`SSDT-NXRTD3.asl`](opencore/acpi/SSDT-NXRTD3.asl)) exposes 4-character ACPI wrapper methods `NXOF` and `NXO_` under `\_SB.PCI0` so idle GTX 1650 sessions power off `\_SB.PCI0.PEG0.PG00` cleanly.

---

## 2. Why Two NullMoth Patches Were Needed

Pinned upstream base tested: `45040e97f705e7de684f8dac45ff71ade72a31ba`.

1. [`0001-optimus-policy-native-igpu-headless.patch`](patches/0001-optimus-policy-native-igpu-headless.patch)
   - Upstream `NVMTLDevice.m` only consulted `/Library/GPUBundles/nvmtl-gpu-policy.txt` when `debug.nmhybrid > 0` (`NMIntelFB.kext` mode for Intel 12th+ laptops), and only supported `mode apple` and `mode nvidia`.
   - Upstream `NVMTLDevice.m` also blocked `WindowServer` unconditionally whenever `debug.nvaccel_headless == 1` — which breaks external HDMI displays hot-plugged *after* an unplugged boot (`debug.nvaccel_headless` stays `1` for the boot even after `debug.nvaccelfb=1` arms `NVRMFramebuffer`).
   - On Comet Lake (`UHD 630`), macOS uses native `AppleIntelCFLGraphicsFramebuffer`, leaving `debug.nmhybrid == 0` and setting `debug.nvaccel_headless == 1`.
   - This patch:
     - Activates per-app policy evaluation whenever `nmp_hybrid_active_for_policy(nmhybrid, nvaccel_headless, has_policy_file) > 0` (covering both headless offload and HDMI-connected dual-GPU boots with an explicit root-owned policy file), and adds **`mode igpu`** (stay on UHD 630 unless explicitly pinned with `nvidia <ProcessName>`).
     - Adds `nmp_windowserver_headless_block()` + `WindowServer` bypass in `nvmtl_gpu_policy_allows()` so `WindowServer` stays off GTX 1650 while headless (`debug.nvaccelfb == 0`) yet receives the GTX 1650 Metal device once HDMI connects and arms `NVRMFramebuffer` (`debug.nvaccelfb != 0`).
     - Gates `nmp_gpu_headless()` (`nvmtl_vk.c`) on `nvaccel_armed && iop_flip_on` (`debug.nvaccel_iop_flip != 0`) so `WindowServer` uses shared BAR1 VRAM only when zero-copy flips are enabled, keeping `-nvrmnoflip` copy-path sessions on system-memory copy-out instead of saturating the 256 MB BAR1 window.
     - Fixes `NVMTLEventSync.m` (`holds->early = nvmtl_ws_surface_wait() && nvmtl_vk_surface_share_on()`) so private copy-out surfaces do not drop their kernel hold before `nvmtlSurfaceOut` finishes copying to system memory.

2. [`0002-rtd3-4char-acpi-method.patch`](patches/0002-rtd3-4char-acpi-method.patch)
   - macOS `IOACPIPlatformDevice::evaluateObject()` rejects dotted/multi-segment names longer than 4 characters with `kIOReturnBadArgument` (`0xe00002c2`).
   - Verified in Acer OEM `SSDT5.dsl` + `IOService`: the first `IOACPIPlatformDevice` parent of `PEG0@1` is `PCI0@0` (`\_SB.PCI0`), and GPU power gating lives at `\_SB.PCI0.PEG0.PG00._OFF` / `_ON` (guarded by `OSYS > 0x07D9`, satisfied by `SSDT-XOSI.aml`).
   - Adds `nvrtd3off=<4char>` / `nvrtd3on=<4char>` and direct `IOACPIPlane` target lookup while keeping existing `nvrtd3res=` compatibility.
   - Paired with [`SSDT-NXRTD3.aml`](opencore/acpi/build-rtd3-aml.py) (`Scope (\_SB.PCI0)` defining `NXOF` and `NXO_`).

---

## 3. Critical AN515-55 Pitfalls Avoided by These Scripts

- **Do NOT block `com.apple.iokit.IONDRVSupport`**: Desktop NullMoth configs block it, but on this laptop `AppleIntelCFLGraphicsFramebuffer` depends on it (`4` active dependents observed live).
- **Do NOT enable `nmhybrid=1` or `NMIntelFB.kext`**: UHD 630 already has native Metal 3 acceleration via WhateverGreen.
- **Keep `/Library/NullMoth/no-wsreset`**: Prevents NullMoth's LaunchDaemon from killing `WindowServer` on Intel FB0.
- **Keep `gfxrst=4`**: Required whenever `WhateverGreen.kext` is loaded alongside NullMoth to avoid boot-screen mapping panics.
- **Leave `NM_PRIMARY_GPU` unset (`0`)**: Keeps Intel UHD 630 as the primary display adapter.
- **BAR1 / Resizable BAR note**: Acer Insyde BIOS hides Above 4G Decoding / ReBAR by default (~208 MB usable inside 256 MB BAR1 even with OpenCore `ResizeAppleGpuBars = -1`). Default `-nvrmnoflip` (`--noflip`) keeps copy-path scanout; `nmp_gpu_headless()` keeps `WindowServer` on system-memory copy-out unless `debug.nvaccel_iop_flip != 0`. Test zero-copy scanout via `nitro-gpu-ctl activate-hdmi --flip` or `hdmi-flip on --restart` (and revert via `hdmi-flip off --restart`). Do **not** flash unverified unlocked BIOS mods without a hardware SPI programmer backup.
- **NVMe / Sleep performance note (`Samsung SSD 980 1TB`):** Use `--no-debug` for quiet OpenCore/macOS boot (`Target=0`, no `-v debug=0x100 keepsyms=1 swd_panic=1`), and `--nvme-safe` if `NVMeFix.kext` ASPM/APST causes `Loss of MMIO space` panics on `RP09@1d,0`. Also run `sudo pmset -a hibernatemode 0 disksleep 0 powernap 0`: this keeps S3 Sleep-to-RAM intact while preventing 32 GB hibernate disk dumps and awake 10-minute NVMe idle drops.

---

## 4. Layout

```text
laptop/hackintosh/
├── README.md
├── app/
│   ├── Info.plist                    # App bundle metadata (NSSupportsAutomaticGraphicsSwitching=YES)
│   ├── NitroGPU.swift                # Native Nitro 5 menu bar + window app (Auto / NVIDIA / iGPU + HDMI)
│   └── build-app.sh                  # Compiles x86_64 NitroGPU.app & packages NitroGPU-Switcher.dmg
├── opencore/
│   ├── config-sanitized.plist        # Real Hackintosh OC config with serials/MLB/ROM/UUID scrubbed
│   ├── nvmtl-gpu-policy.txt          # Per-app Optimus policy template ("mode apple", root:wheel 0644)
│   └── acpi/
│       ├── SSDT-NXRTD3.asl           # Readable ASL source for NXOF / NXO_ under \_SB.PCI0
│       ├── SSDT-NoHybGfx.dsl         # Decompiled baseline dGPU-hiding SSDT for reference
│       └── build-rtd3-aml.py         # Zero-dependency AML builder (no iasl required)
├── patches/
│   ├── 0001-optimus-policy-native-igpu-headless.patch
│   └── 0002-rtd3-4char-acpi-method.patch
├── scripts/
│   ├── sanitize-config.py            # Scrubs PlatformInfo + Misc.Security secrets before git commit
│   ├── nitro-gpu-ctl.sh              # Scoped helper (/Library/NullMoth/nitro-gpu-ctl): set/status/arm-hdmi/activate-hdmi/hdmi-flip/watch-hdmi
│   ├── 00-ssh-hackintosh.sh          # Syncs app/scripts/configs/patches to ~/hackintosh-optimus and opens SSH shell
│   ├── 01-backup-efi.sh              # Runs on Hackintosh: mounts booted ESP, creates raw .img + SHA256SUMS
│   ├── 02-sync-efi-to-repo.sh        # Runs on controller Mac: runs remote backup (real PTY for sudo), pulls & sanitizes
│   ├── 03-build-optimus-patches.sh   # Clones NullMoth + Vulkan-Headers, patches, tests, builds NVMTLDriver & NitroGPU DMG
│   ├── 04-prepare-usb-test-efi.sh    # Builds updated OpenCore EFI (with nvfbhotplugpoll=2 Auto-HDMI enabled by default)
│   ├── 05-install-nullmoth-optimus.sh# Installs NullMoth, NVMTLDriver, policy, nitro-gpu-ctl, LaunchDaemon & NitroGPU.app
│   ├── 06-verify-optimus.sh          # Read-only inspection of GPUs, kexts, sysctls, bundle seal, logs
│   └── apply-efi-update.sh           # Installs staged EFI onto the UUID-verified booted internal ESP
├── efi-backup/                       # GITIGNORED: raw ESP images, EFI/, nvram.plist
├── work/                             # GITIGNORED: upstream clones & build trees
└── out/                              # GITIGNORED: NVMTLDriver, SSDT-NXRTD3.aml, NitroGPU.app, NitroGPU-Switcher.dmg
```

---

## 5. Automated End-to-End Workflow (USB-First Safe Flow)

### Step A — Back up the live Hackintosh EFI into `efi-backup/`

From your controller Mac (uses `~/.ssh/config` host `nitro-mac`, or pass `--host <user>@<HACKINTOSH_IP>`):

```bash
cd laptop/hackintosh
# Option 1 (automated one-shot with interactive sudo prompt):
./scripts/02-sync-efi-to-repo.sh --host <user>@<HACKINTOSH_IP>

# Option 2 (SSH into the Hackintosh first, with everything synced to ~/hackintosh-optimus):
./scripts/00-ssh-hackintosh.sh --host <user>@<HACKINTOSH_IP> --pull-after
# Inside the Hackintosh SSH shell, run: ./scripts/01-backup-efi.sh (then type exit)
```

What `02-sync-efi-to-repo.sh` automates:
- Uploads `01-backup-efi.sh` via `scp` and runs it over a real `ssh -t` PTY (without `<` stdin redirection so `sudo` prompts cleanly).
- Dynamically detects the live booted ESP GPT UUID from OpenCore `boot-path` NVRAM (never hardcoding `disk1s1`).
- Dumps raw `efi-partition.img`, copies `EFI/`, saves `nvram.plist`, `diskutil-list.txt`, and `SHA256SUMS`.
- Pulls the backup into gitignored `efi-backup/<timestamp>/`, updates `efi-backup/latest`, and regenerates `opencore/config-sanitized.plist`.

### Step B — Build patched `NVMTLDriver`, policy, and `SSDT-NXRTD3.aml`

Run on macOS (Xcode CommandLineTools + `git` + `python3`; works on both Apple Silicon and Intel x86_64):

```bash
./scripts/03-build-optimus-patches.sh
```

To **also** compile a custom `NVRM.kext` with RTD3 4-character method support (`0002`), pass a pristine `NVIDIA/open-gpu-kernel-modules` `620.70.06` checkout:

```bash
./scripts/03-build-optimus-patches.sh --ogkm /path/to/open-gpu-kernel-modules-620.70.06
```

Artifacts land in `laptop/hackintosh/out/`:
- `NVMTLDriver` (`x86_64` ad-hoc signed bundle binary with `mode apple / nvidia / igpu`)
- `SSDT-NXRTD3.aml` (unless pre-compiled elsewhere)
- `nvmtl-gpu-policy.txt`
- `NitroGPU.app` & `NitroGPU-Switcher.dmg` (menu bar & control window switcher)
- Optional `nvrm-build/NVRM.kext` (when `--ogkm` was supplied)

### Step C — Prepare & Boot the Updated OpenCore EFI (First Reboot If Starting Fresh)

NullMoth's upstream `install.sh` requires the NVIDIA GPU (`vendor-id 0x10de`) to already be visible on PCIe (`ioreg -r -c IOPCIDevice -d 1 | grep -q '"vendor-id" = <de100000>'`) — otherwise it aborts cleanly with `no NVIDIA GPU found on PCI`.

Therefore, **if your Hackintosh currently boots with `-wegnoegpu` / `SSDT-NoHybGfx.aml`**:
1. Build the updated EFI onto a FAT32 USB drive (recommended) OR export to a folder:
   ```bash
   # USB drive (check identifier via diskutil list):
   ./scripts/04-prepare-usb-test-efi.sh --disk disk4
   # Or stage to a folder for direct ESP update (after backing up in Step A):
   ./scripts/04-prepare-usb-test-efi.sh --out-dir ~/Downloads/Nitro-AN515-55-Optimus

   # Optional flags:
   #   --allow-flip    omit -nvrmnoflip (default keeps copy-path -nvrmnoflip for 256 MB BAR1)
   #   --no-auto-hdmi  omit nvfbhotplugpoll=2 nvagdcheads=1
   #   --no-debug      omit -v debug=0x100 keepsyms=1 swd_panic=1 and set Misc.Debug.Target=0
   #   --no-nvmefix    add -nvmefoff boot-arg (bypass NVMeFix.kext)
   #   --nvme-safe     apply --no-nvmefix plus disable ASPM/APST on RP09 NVMe (PciRoot(0x0)/Pci(0x1D,0x0))
   #   --rtd3          enable SSDT-NXRTD3.aml + nvrtd3=1 (only after --ogkm NVRM.kext)
   ```
   `04-prepare-usb-test-efi.sh` disables `SSDT-NoHybGfx.aml`, removes `-wegnoegpu`, adds `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth gfxrst=4 amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 -nvrmnoflip nvfbhotplugpoll=2 nvagdcheads=1 nvrmsettle=10000` (overriding Turing's 100 s unplaced-BAR1 wait down to 10 s), keeps `IONDRVSupport` unblocked, and adds `boot-args` to `NVRAM.Delete`.
2. **Reboot once** with the updated EFI (via F12 USB boot menu first, or apply staged EFI to the booted ESP with `./scripts/apply-efi-update.sh --src ~/Downloads/EFI-optimus --reboot`) so macOS unhides GTX 1650 (`10de:1f99`) on PCIe while still running Intel UHD 630.

### Step D — Install NullMoth + Optimus Patch + NitroGPU Switcher

Download and unpack the official **NullMoth 3.1** release tarball (`nullmoth-nvidia-*.tar.gz` extracting `pkgroot/`) on the Hackintosh, sync `laptop/hackintosh` with `./scripts/00-ssh-hackintosh.sh`, and run:

```bash
# First time (runs NullMoth install.sh, then installs patched NVMTLDriver, policy,
# no-wsreset, /Library/NullMoth/nitro-gpu-ctl, Auto-HDMI LaunchDaemon, and /Applications/NitroGPU.app):
./scripts/05-install-nullmoth-optimus.sh --release-dir ~/Downloads/pkgroot

# Or update/patch an existing NullMoth installation without re-running install.sh:
./scripts/05-install-nullmoth-optimus.sh --patch-only

# Optional: allow NitroGPU.app 1-click switching without macOS admin dialog prompts:
./scripts/05-install-nullmoth-optimus.sh --patch-only --passwordless-gui

# Optional: install custom RTD3 NVRM.kext built with --ogkm:
./scripts/05-install-nullmoth-optimus.sh --patch-only --nvrm-kext ./out/nvrm-build/NVRM.kext
```

**Expected macOS security prompts (cannot be automated safely):**
- On first third-party kernel extension install (`kmutil`), macOS requires manual user confirmation in **System Settings → Privacy & Security** ("Allow" system software from NullMoth / reboot prompt).

Reboot again after installation so macOS loads the new Auxiliary Kernel Collection (`NVRM`, `NVAccel`, `NVRMFB`, `NVRMAGDC`).

### Step E — Switch Modes (`NitroGPU.app` / CLI) & Verify Auto-HDMI

- **GUI (`NitroGPU.app` or `NitroGPU-Switcher.dmg`):** Launch **NitroGPU Switcher** from `/Applications` (also adds `N5 · Auto` / `N5 · GTX` / `N5 · iGPU` to the menu bar) to click between **Auto (Optimus)**, **NVIDIA Mode**, and **iGPU Mode**, click **Test Metal GPUs**, or click **Activate HDMI Display** (prompts once to reset `WindowServer` if HDMI was hot-plugged after boot).
- **CLI (`/Library/NullMoth/nitro-gpu-ctl`):**
  ```bash
  /Library/NullMoth/nitro-gpu-ctl status
  sudo /Library/NullMoth/nitro-gpu-ctl set nvidia       # apple | nvidia | igpu
  sudo /Library/NullMoth/nitro-gpu-ctl arm-hdmi         # kernel arm only
  sudo /Library/NullMoth/nitro-gpu-ctl activate-hdmi    # arms kernel + restarts WindowServer if needed (logs out session)
  sudo /Library/NullMoth/nitro-gpu-ctl activate-hdmi --flip  # arms + enables iop_flip=1 + restarts WindowServer with shared BAR1 VRAM
  sudo /Library/NullMoth/nitro-gpu-ctl hdmi-flip <on|off> [--restart]  # toggle zero-copy scanout flip (restart WindowServer when switching mode)
  ```
- **Verify everything:**
  ```bash
  ./scripts/06-verify-optimus.sh --with-sudo
  ```

Expected signals (verified on Acer Nitro AN515-55, macOS Tahoe `26.7.3`):
- `SPDisplaysDataType` shows the internal `1920 x 1080 @ 144.00Hz` panel driven by **Intel UHD Graphics 630** (`Metal 3`) and **NVIDIA GeForce GTX 1650** (4 GB, `Metal 4`) — plus attached external HDMI monitors (verified live with Samsung `LS24AG32x` @ `1920 x 1080 @ 144.00Hz`).
- `kmutil showloaded` lists `AppleIntelCFLGraphicsFramebuffer`, `IONDRVSupport`, `NVRM`, `NVAccel`, `NVRMFB`, `NVRMAGDC`, and `NMXAudio`.
- When HDMI is connected and armed: `debug.nvaccelfb=1`, `debug.nvaccel_heads_published=1`, `debug.nvaccel_heads_registered=1`, `debug.nvaccel_heads_piped=1`, `debug.nvaccel_iop=1`, `debug.nvaccel_iop_ok` increments live, and `ioreg -r -c NVRMNVDAFramebuffer` shows `WindowServer` attached as a user client.
- `codesign --verify --strict /Library/GPUBundles/NVMTLDriver.bundle` passes cleanly and `/Library/NullMoth/no-wsreset` exists.
- **Auto-HDMI notes:**
  - `nvfbhotplugpoll=2 nvagdcheads=1 nvrmsettle=10000 -nvrmnoflip` polls Turing HDMI every 2 s (`nvrm-fb.cpp`), exposes all 4 head slots in `NVRMAGDC`, keeps `NVAccel` on the safe copy path (`-nvrmnoflip`), and trims Turing's 256 MB BAR1 settle delay to 10 s.
  - `com.nullmoth.nitro-hdmi-watch` runs `nitro-gpu-ctl arm-hdmi` automatically when an external display hot-plugs after boot (and uses `debug.nvaccelfb=3` if a head publishes after arming).
  - If HDMI was hot-plugged *after* an unplugged boot, `WindowServer` ignores `SIGTERM` from plain `killall WindowServer`; clicking **Activate HDMI Display** in `NitroGPU.app` (or running `sudo /Library/NullMoth/nitro-gpu-ctl activate-hdmi`) runs `launchctl kickstart -k system/com.apple.WindowServer || killall -9 WindowServer`, while `0001` ensures `WindowServer` receives the NVIDIA Metal device (`debug.nvaccelfb != 0`) instead of hitting `"Failed to create MetalDevice"`. Pass `--flip` (or `hdmi-flip on --restart`) to restart `WindowServer` with `debug.nvaccel_iop_flip=1` and shared BAR1 VRAM enabled.
- **Test coverage:**
  - Offline host checks: `test_gpu_policy` (`34/34` assertions passed, `0 failed`), `test_nv_rtd3_policy.py` (`all passed`), `build-rtd3-aml.py` (`169` bytes, ACPI checksum valid).
  - Note: RTD3 D3cold kernel path (`0002-rtd3-4char-acpi-method.patch`) is verified via offline host unit tests and x86_64 kernel compilation syntax checks; runtime D3cold testing requires supplying pristine NVIDIA open-gpu-kernel-modules `620.70.06` sources via `--ogkm` when building `NVRM.kext`.

---

## 6. Sudo Automation & Manual Security Step Directions

Scripts `01`, `04` (`--disk`), and `05` request `sudo -v` **once** at startup and refresh the timestamp in a trapped background keepalive until exit. You never type `sudo` repeatedly inside loops, and no permanent root privilege persists afterward.

### Optional: Scoped `sudoers.d` for Unattended SSH EFI Backups (Security Warning)

If you want `02-sync-efi-to-repo.sh` to run `01-backup-efi.sh` without prompting for a password over SSH, you can manually add a tightly scoped `sudoers` drop-in on the Hackintosh — **only do this manually on the machine itself**:

```bash
# 1. Replace <USER> with your Hackintosh username; find your exact EFI slice first:
diskutil list

# 2. Edit safely with visudo (validates syntax so you never lock out sudo):
sudo visudo -f /etc/sudoers.d/hackintosh-efi-backup
```

Example minimal rule (granting only mount/umount/dd/chown — never grant `NOPASSWD: ALL` cleanly across arbitrary binaries):

```sudoers
# Security note: restrict commands and run only with key-based SSH auth.
<USER> ALL=(root) NOPASSWD: /sbin/mount -t msdos -o rdonly /dev/disk* /tmp/oc-efi-backup-*
<USER> ALL=(root) NOPASSWD: /sbin/umount /tmp/oc-efi-backup-*, /usr/sbin/diskutil unmount /tmp/oc-efi-backup-*
<USER> ALL=(root) NOPASSWD: /bin/dd if=/dev/rdisk* of=/Users/<USER>/efi-backup-* bs=1m status=progress
<USER> ALL=(root) NOPASSWD: /usr/sbin/chown <USER>\:* /Users/<USER>/efi-backup-*
```

> [!WARNING]
> **Security trade-off:**
> - Allowing passwordless `dd if=/dev/rdisk*` lets any compromised process running under `<USER>` read raw block devices.
> - Keeping `csr-active-config=0x803` + `amfi_get_out_of_my_way=0x1` reduces macOS SIP and AMFI enforcement cleanly required for third-party GPU kexts (`kmutil`) and OCLP Broadcom Wi-Fi patches.
> - **Recommendation:** Keep interactive `sudo -v` (no `NOPASSWD`), use SSH public-key authentication only, and remove `/etc/sudoers.d/hackintosh-efi-backup` after initial setup.

---

## 7. Rollback & Restoring the Clean Baseline

- **If USB test EFI fails to boot or panics:** Unplug USB and reboot normally — the internal SSD EFI was never modified.
- **If you want to undo NullMoth completely on macOS:**
  - Use NullMoth's built-in `uninstall.sh` from your NullMoth release package (or boot macOS Recovery / USB recovery EFI and remove NullMoth kexts from `/Library/Extensions` + run `kmutil install`), and restore `/Library/NullMoth/optimus-backup-*` if only reverting the patched bundle.
- **If the internal SSD EFI ever needs full restoration:** Mount your internal ESP from macOS / Recovery and restore from `efi-backup/latest/EFI/` (or verify against `efi-backup/latest/SHA256SUMS`).
