# Use the Mac's keyboard and mouse on the laptop (Deskflow)

Goal: one keyboard and mouse (on a separate Mac) for both computers. Move the pointer off the edge of the
Mac screen and it continues on the Linux laptop; the keyboard follows; text copy/paste works both ways.

Status: set up 2026-11-20 (Deskflow 1.27 on both sides, TLS, laptop connected to the Mac).

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

## Limits on this laptop
- Works while the Linux desktop is shown. In macOS panel mode (`gpu-mode mac`) GNOME is stopped, so the
  Linux client is gone; run Deskflow as a client inside that macOS instead (same server, another screen name).
- Windows in the Looking Glass window: input reaches Windows only after Right Ctrl captures it.
- Screen lock / login screen on Linux: the client runs in the user session, so it does not work at the GDM
  login screen.

## Troubleshooting
- Laptop log says `detected X11 platform ... unable to open x11 display`: the client was started without the
  Wayland session environment (e.g. over SSH). Start it from the app grid or autostart, not from SSH.
- `connected to secure socket` repeating every second: a fingerprint is not trusted yet on one side.
  Accept it in the Deskflow window on both computers.
- Pointer does not move on the laptop although connected: GNOME's "Remote interaction" prompt was not
  allowed yet (Wayland input goes through the portal). Restart Deskflow on the laptop and click Allow.
- Pointer does not leave the Mac: Deskflow needs Accessibility permission on the Mac.
