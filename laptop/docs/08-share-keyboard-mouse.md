# Use the Mac's keyboard and mouse on the laptop (Deskflow)

Goal: one keyboard and mouse (on a separate Mac) for both computers. Move the pointer off the edge of the
Mac screen and it continues on the Linux laptop; the keyboard follows; text copy/paste works both ways.

Status: working 2026-11-20 (Deskflow 1.27, TLS). Layout: Mac | laptop (`nitro`) | Windows VM (`windows`).

## Which tool
| Option | Verdict |
|---|---|
| Apple Universal Control | Apple devices only. No Linux. |
| ShareMouse | Windows and macOS only. No Linux. |
| **Deskflow** | Free, open source (upstream of Synergy). macOS + Linux, works on GNOME Wayland. In the CachyOS/Arch repos (`deskflow`, 1.27). **Use this.** |
| Input Leap | Also works (Barrier fork), less active than Deskflow. |
| Mac Screen Sharing (VNC) to GNOME Remote Desktop | No app on the Mac, but it is a remote screen in a window, not one pointer across two screens. |

There is no way without an app on the Mac: macOS has no built-in protocol for this with Linux.

## Setup
The Mac is the **server** (it has the keyboard and mouse), the laptop is the **client**.
Traffic stays on the local network, encrypted with TLS. The laptop connects **out** to the Mac on TCP 24800,
so the laptop needs no firewall rule; on the Mac, allow Deskflow if the macOS firewall is on.

### Laptop (Linux)
```
sudo pacman -S deskflow
mkdir -p ~/.config/autostart && cp /usr/share/applications/org.deskflow.deskflow.desktop ~/.config/autostart/
```
1. Open **Deskflow** from the app grid, choose client mode ("use another computer's keyboard and mouse").
2. **Server address = the Mac's LAN IP** (Mac: System Settings > Wi-Fi > Details), not a screen name.
   **Computer name = `nitro`**, exactly the name of the laptop's screen in the Mac's layout.
   (First attempt here had them swapped: server `nitro`, name `cachyos-x8664`: nothing connects.)
   Both end up in `~/.config/Deskflow/Deskflow.conf` as `remoteHost=` and `computerName=`.
3. First connect: GNOME asks to allow **Remote interaction**: Allow (Wayland input goes through the
   RemoteDesktop portal / libei).
4. Accept the Mac's TLS fingerprint once (stored in `~/.config/Deskflow/tls/trusted-servers`).
5. Started at login by the autostart file above.

### Mac
1. Install. Deskflow is not in the main Homebrew casks (`brew install --cask deskflow` fails with
   "No Cask with this name exists"); it has its own tap:
   ```
   brew tap deskflow/tap
   brew install --cask deskflow/tap/deskflow
   ```
   Or the `.dmg` from github.com/deskflow/deskflow/releases (`macos-arm64` for Apple silicon, `macos-x86_64` for Intel).
2. Choose server mode. In the screen layout, drag a screen named `nitro` (same name as on the laptop)
   next to the Mac's screen, on the side where the laptop physically stands.
3. TLS is on by default; accept the laptop's fingerprint on the first connection
   (`~/Library/Deskflow/tls/trusted-clients`). Layout file: `~/Library/Deskflow/deskflow-server.conf`.
4. System Settings > Privacy & Security > **Accessibility**: allow Deskflow (needed to read the keyboard and mouse).

## Windows VM as a third screen
The Mac mouse does **not** work inside the Looking Glass window through the laptop client:
- Looking Glass only sends mouse input to Windows while it captures the pointer (Right Ctrl), and the Mac
  keyboard has no Right Ctrl.
- In capture mode Looking Glass reads relative mouse motion (pointer lock); Deskflow on GNOME Wayland moves the
  pointer with absolute positions through libei, so the captured cursor does not move.

Fix: Windows runs its own Deskflow client and is a screen of its own, right of the laptop:
`Mac | nitro (laptop) | windows`. Push the pointer off the laptop's right edge and it goes into Windows (shown in
the Looking Glass window), with the Mac keyboard. No capture key needed. Leave Looking Glass uncaptured.

Setup in the Windows guest (done 2026-11-20, from Linux with `wexec`, no clicks in Windows):
1. Microsoft Visual C++ 2015-2022 x64 runtime (the Deskflow MSI stops with error 1603 / `ShowVCRedistError`
   without it): `vc_redist.x64.exe /install /quiet /norestart` from `https://aka.ms/vs/17/release/vc_redist.x64.exe`
   (check its Authenticode signature is Microsoft).
2. `deskflow-1.27.0-win-x64.msi` from the GitHub release (it is not Authenticode-signed: compare its SHA-256 with
   the `digest` shown for the asset on the release page), `msiexec /i deskflow.msi /qn`. Installs the
   `Deskflow` service (deskflow-daemon), which runs the client elevated in the user's session.
3. `%APPDATA%\Deskflow\Deskflow.conf` of the Windows user:
   ```
   [client]
   remoteHost=<Mac LAN IP>
   [core]
   computerName=windows
   coreMode=1
   [gui]
   enableUpdateCheck=false
   startCoreWithGui=true
   ```
4. Shortcut to `C:\Program Files\Deskflow\deskflow.exe` in the user's Startup folder (starts at login).
5. On the Mac: add a screen `windows` right of `nitro` in the Deskflow layout; accept the new fingerprint on both
   sides once (Windows log: `failed to verify server certificate fingerprint` until accepted).

The Windows VM reaches the Mac through the VM network (NAT), so the Mac sees it coming from the laptop's IP.

## Limits on this laptop
- Works while the Linux desktop is shown. In macOS panel mode (`gpu-mode mac`) GNOME is stopped, so the
  Linux client is gone; run Deskflow as a client inside that macOS instead (same server, another screen name).
- The `windows` screen only exists while Windows runs; when it is off, the pointer stops at the laptop's right edge.
- Screen lock / login screen on Linux: the client runs in the user session, so it does not work at the GDM
  login screen.

## Troubleshooting
- Laptop log says `detected X11 platform ... unable to open x11 display`: the client was started without the
  Wayland session environment (e.g. over SSH). Start it from the app grid or autostart, not from SSH.
- `connected to secure socket` repeating every second: a fingerprint is not trusted yet on one side.
  Accept it in the Deskflow window on both computers.
- Pointer does not move on the laptop although connected: GNOME's "Remote interaction" prompt was not
  allowed yet (Wayland input goes through the portal). Restart Deskflow on the laptop and click Allow.
- Allowing Deskflow's input starts `xdg-desktop-portal-gnome`; before the session-wide Intel-only setting
  (docs/04) that portal held the GTX and blocked Windows from starting.
- Pointer does not leave the Mac: Deskflow needs Accessibility permission on the Mac.

## Standalone Laptop <-> Windows Mode & Linux Terminal Overlay (`deskflow-mode`)
When working on just the laptop (Linux on `eDP-1`) + an external HDMI monitor (Windows on GTX 1650 passthrough)
without the separate Mac, switch Deskflow into **Local Server mode**:
- **In VM Switch → Mouse & Terminal Bridge (Deskflow):** click **Use Laptop <-> Windows** (pick edge `Right`, `Above`, `Left`, or `Below`).
- **From terminal:**
  - `deskflow-mode local [--side right|up|left|down]` — backs up your Mac client config (`~/.config/Deskflow/Deskflow.conf.mac`), configures CachyOS as Deskflow 1.27 server (`nitro`, `[internalConfig]` grid + `[computer_windows]` + `deskflow-server.conf` with `Ctrl+Super+Arrow` hotkeys), restarts Deskflow, and syncs Windows over QGA to `192.168.122.1`.
  - `deskflow-mode sync-windows` — updates Windows `Deskflow.conf` + exchanges TLS SHA-256 fingerprints (`C:\ProgramData\Deskflow\tls\` <-> `~/.config/Deskflow/tls/trusted-clients`).
  - `deskflow-mode mac` — restores the saved `Deskflow.conf.mac` client config on both CachyOS and Windows.
  - `deskflow-mode win-terminal` (**Linux terminal in Windows** in VM Switch) — creates a local-VM-only key (`from="192.168.122.13"`) and opens a live CachyOS SSH terminal (`wt.exe` / `cmd.exe`, plus a `Linux Terminal (CachyOS)` Desktop shortcut) right over the Windows passthrough screen.
