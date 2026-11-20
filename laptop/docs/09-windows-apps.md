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
`~/.local/share/applications/winapps-win-*.desktop` (Exec `winapps-sync --open <id>`) + `~/.local/share/winapps/apps/win-*/`.
A program removed in Windows loses its launcher on the next sync.

## Coherence vs. Looking Glass
| | Looking Glass window (`win-gpu`) | WinApps windows |
|---|---|---|
| Shows | the whole Windows desktop | single apps as Linux windows |
| Picture | uncompressed frames from the GTX | RDP stream (H.264) |
| Good for | games, video, anything fast | office, browser, tools |
| Session | Windows console | its own RDP session of the same user |

Several programs at once (2026-11-20): each WinApps click is a new RDP connection. With
`fSingleSessionPerUser=0` every connection made a new Windows session, and Windows 10 (one active session)
asked to sign the other one out on every click. With `=1` a new connection takes the session over instead.
So the launchers (`winapps-sync --open`, also for WinApps' own Paint/Explorer/cmd entries) only open an RDP
connection for the first program. While one is open they start the next program inside that session via the
guest agent (SYSTEM: `WTSQueryUserToken` + `CreateProcessAsUser` into the Active `rdp-tcp#` session that runs
`rdpinit`); its window comes through the open connection. Tested: Notepad, Calculator, Paint together over one
FreeRDP process, no prompt. About 5 s per click (guest agent + PowerShell).
Still one at a time: the full desktop (Looking Glass, console session) and app windows; switching between them
takes the session over.

Single-instance programs (Edge, Chrome, Office, ...) open as app windows only when they do **not** already run
in the desktop session: a second copy hands off to the hidden one and exits, so no window appears (seen
2026-11-20: Edge left open on the Looking Glass desktop, Edge app window never showed). The launchers run
`winapps-sync --open <id>`, which checks first and shows a notification instead: close the program on the
desktop (VM Switch > Show desktop) or sign out there, then click again.
Dock names and icons (2026-11-20): one RDP connection carries every window a program opens, so an ArcGIS
installer started from Edge showed in the dock as Edge (WinApps' fixed `/wm-class`, and GNOME maps windows to
the launcher's systemd scope). Without `/wm-class`, FreeRDP calls every window `RAIL:<id>` ("RAIL" = the
RemoteApp part of RDP) and the dock showed "Rail". Now:
- `setup-winapps.sh` removes `/wm-class` from WinApps; `winapps-sync --open` starts FreeRDP in its own scope;
- `winapps-rail-names` (user service, python-xlib in `~/.local/share/winapps/venv`) renames each `RAIL:` window
  from its title: title contains a launcher name (e.g. "Microsoft Edge") -> that launcher (its icon, running dot);
  otherwise the title itself, with the icon Windows sends. 1x1 px untitled helper windows of the Windows shell
  are hidden from the dock (`_NET_WM_STATE_SKIP_TASKBAR`).
- Pinning: a window that matches a launcher (by its name, StartupWMClass or program name, e.g. "File Explorer"
  -> Explorer) belongs to that launcher and can be pinned (right-click > Pin to Dash). Windows that match no
  launcher (e.g. an installer) are GNOME "window-backed" apps and cannot be pinned; pin the program from the
  app grid folder Windows instead.
The Deskflow client inside Windows runs in the desktop session: app windows get the Mac mouse through the
laptop (they are normal Linux windows).

Black areas in app windows (2026-11-20): first setup had the GTX rendering RDP sessions
(`bEnumerateHWBeforeSW=1`, AVC444, NVENC) and Windows shadows/animations on. RemoteApp windows then showed
black regions. Both were switched off at once. Then the GTX was switched back on (shadows/animations
and AVC444/NVENC stay off), to find which one caused it: under test. Settings apply to the next app session
(sign out of the app session, or restart Windows). If black areas come back, set `bEnumerateHWBeforeSW=0` and
use the full desktop (Looking Glass) for GPU-heavy programs such as ArcGIS Pro.
ArcGIS Pro 3.8 needs the .NET 10 Desktop Runtime (installed 2026-11-20 from aka.ms/dotnet/10.0, Microsoft-signed).

## Setup
### Windows (done from Linux with `wexec win10-gpu '<PowerShell>'`, no clicks)
Values from WinApps `oem/RDPApps.reg` plus the GPU policy:
```
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server                         fDenyTSConnections = 0
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server                         fSingleSessionPerUser = 1   (one session per user; see "Several programs at once")
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp     UserAuthentication = 1   (NLA)
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList  fDisabledAllowList = 1
HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services                 fAllowUnlistedRemotePrograms = 1
HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout                         IgnoreRemoteKeyboardLayout = 1
HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services                 bEnumerateHWBeforeSW = 1   (GTX renders app windows; AVC444/NVENC stay off)
HKU\<user SID>\...\Explorer\VisualEffects                                      VisualFXSetting = 2   (no shadows/animations)
HKU\<user SID>\Control Panel\Desktop                                            UserPreferencesMask = 90 12 03 80 10 00 00 00, FontSmoothing = 2
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
