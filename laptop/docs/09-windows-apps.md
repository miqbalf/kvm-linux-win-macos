# Windows apps in their own Linux windows (like Parallels Coherence)

[WinApps](https://github.com/winapps-org/winapps) shows single Windows programs as normal windows on the GNOME
desktop, each with its own icon in the app grid. It uses RDP RemoteApp (FreeRDP 3 on Linux), which needs
Windows Pro or Enterprise (here: Windows 10 Enterprise LTSC).

Status: working 2026-11-20. App grid folder **Windows**: every Start-menu program (12 on this VM: Edge,
Notepad, Calculator, NVIDIA App, ...) plus WinApps' Explorer, cmd, PowerShell, Paint. Tested: Paint opened as its own window on the GNOME desktop.

## How Parallels Coherence works, and what we copy
Parallels Coherence hides the Windows desktop. Every Windows program window becomes a normal Mac window,
the Windows Start-menu programs appear in the Mac Dock and Launchpad (folder "Windows Applications") with
their own icons, and that folder follows what you install or remove in Windows. Clipboard, files and sound
are shared. Windows keeps drawing its own title bars.

| Coherence | Here |
|---|---|
| Windows apps in Launchpad, folder "Windows Applications" | GNOME app grid, folder **Windows** (`winapps-sync`) |
| list follows installs/removals in Windows | `winapps-sync` runs each time VM Switch starts Windows; or run `winapps-sync` |
| app windows on the Mac desktop and Dock | FreeRDP RemoteApp windows; pin them to the GNOME dock |
| desktop hidden, no sign-out | separate RDP session for the apps (`fSingleSessionPerUser=0`); the desktop session is left alone |
| clipboard, home folder, sound | text clipboard, `\\tsclient\home`, sound to Linux |
| not here | Windows notification-area icons in the Linux top bar; file associations only for WinApps' built-in apps |

## Use
1. Start Windows: VM Switch > **Start Windows**. About 40 s later VM Switch syncs the Start-menu programs
   into the app grid (folder **Windows**, real icons).
2. Open a program: app grid > **Windows** > click it (or VM Switch > **Windows apps**). It opens in its own
   window. The first one takes a few seconds (RDP login), the next ones are quick.
3. Whole Windows desktop instead: VM Switch > **Show desktop** (Looking Glass, best for games and video).

Terminal: `winapps-sync` (sync the list now), `winapps windows` (whole desktop over RDP),
`winapps manual notepad.exe`, `winapps check`.
Linux home is `\\tsclient\home` in Windows; text clipboard works both ways; sound goes to Linux.

`winapps-sync` reads the Start menu through the QEMU guest agent (no RDP, no password), skips admin,
accessibility and uninstall entries, takes 256 px icons from the program files, and writes
`~/.local/share/applications/winapps-win-*.desktop` + `~/.local/share/winapps/apps/win-*/`.
A program removed in Windows loses its launcher on the next sync.

## Coherence vs. Looking Glass
| | Looking Glass window (`win-gpu`) | WinApps windows |
|---|---|---|
| Shows | the whole Windows desktop | single apps as Linux windows |
| Picture | uncompressed frames from the GTX | RDP stream (H.264) |
| Good for | games, video, anything fast | office, browser, tools |
| Session | Windows console | its own RDP session of the same user |

Sessions (`fSingleSessionPerUser=0`, set 2026-11-20): the app windows run in their own RDP session, so the
desktop session is not signed out. Windows 10 allows one *active* session: opening an app window while you
use the Looking Glass desktop locks that desktop (its programs keep running); log in there again to go back.
Tested: app windows open with no sign-out while a disconnected desktop session exists. Not yet tested: with
the desktop logged in on the Looking Glass window at the same moment.
The Deskflow client inside Windows runs in the desktop session: app windows get the Mac mouse through the
laptop (they are normal Linux windows).

## Setup
### Windows (done from Linux with `wexec win10-gpu '<PowerShell>'`, no clicks)
Values from WinApps `oem/RDPApps.reg` plus the GPU policy:
```
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server                         fDenyTSConnections = 0
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server                         fSingleSessionPerUser = 0   (apps in their own session, no sign-out)
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp     UserAuthentication = 1   (NLA)
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList  fDisabledAllowList = 1
HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services                 fAllowUnlistedRemotePrograms = 1
HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout                         IgnoreRemoteKeyboardLayout = 1
HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services                 bEnumerateHWBeforeSW = 1        (use the GTX in RDP sessions)
                                                                              AVC444ModePreferred = 1
                                                                              AVCHardwareEncodePreferred = 1  (NVENC)
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'; gpupdate /target:computer /force
```
Skipped from WinApps' `install.bat`: `Container.reg` (switches the clock to UTC; this VM uses local time).

### Linux
```
bash laptop/host/winapps/setup-winapps.sh <windows-user>
```
Installs `dialog` and `openbsd-netcat`, clones WinApps at the tested commit to `~/src/winapps`, writes
`~/.config/winapps/winapps.conf` and the password file `~/.config/winapps/rdp-pass` (mode 600, read through
`RDP_ASKPASS`, so it is not on the FreeRDP command line), then runs WinApps' `setup.sh --user --setupAllOfficiallySupportedApps` (no menus: app scan, `.desktop` entries
in `~/.local/share/applications`, `winapps` in `~/.local/bin`). Add your own installed programs later with
`bash ~/src/winapps/setup.sh --user --add-apps` (interactive).

Problems met during setup (2026-11-20):
| Symptom | Cause | Fix |
|---|---|---|
| `xf_setup_x11: failed to open display`, exit 14 | run over SSH, no `DISPLAY` | script borrows the desktop session's environment |
| setup hangs at `Password:` | FreeRDP 3.33 ignores `RDP_ASKPASS` / `FREERDP_ASKPASS` | `RDP_PASS="$(cat ~/.config/winapps/rdp-pass)"` (password is on the FreeRDP command line, visible to local users only) |
| `LOGON_MSG_BUMP_OPTIONS`, test times out | same user signed in on the console | sign out in Windows first |

Config choices:
- `WAFLAVOR="manual"` + `RDP_IP="192.168.122.13"`: WinApps only connects. With `libvirt` it would run
  `virsh start/suspend` on the VM itself, bypassing `gpu-mode` (the GTX must be moved first) and pausing a VM
  with a passed-through GPU.
- `AUTOPAUSE="off"` for the same reason.

Run it on the laptop's own terminal, or over SSH: the script then borrows `DISPLAY`/`XAUTHORITY` from the
desktop session (`systemctl --user show-environment`). Without that, WinApps' RDP test fails with
`xf_setup_x11: failed to open display` and "REMOTE DESKTOP PROTOCOL FAILURE" (exit 14).
App windows from the app grid open on the laptop screen as usual.

Uninstall: `bash ~/src/winapps/setup.sh --user --uninstall`; `rm -r ~/.config/winapps`.
