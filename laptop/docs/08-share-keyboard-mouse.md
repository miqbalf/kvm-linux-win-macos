# Use the Mac's keyboard and mouse on the laptop (Deskflow)

Goal: one keyboard and mouse (on a separate Mac) for both computers. Move the pointer off the edge of the
Mac screen and it continues on the Linux laptop; the keyboard follows; text copy/paste works both ways.

Status: documented, not yet set up or tested on this laptop.

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
Traffic stays on the local network (TCP 24800), encrypted with TLS.

### Laptop (Linux)
```
sudo pacman -S deskflow
sudo ufw allow from <LAN subnet, e.g. 192.168.1.0/24> to any port 24800 proto tcp
```
1. Open **Deskflow** from the app grid, choose client mode ("use another computer's keyboard and mouse").
2. Server address: the Mac's LAN IP. Screen name: e.g. `nitro`.
3. First connect: GNOME asks to allow **Remote interaction**: Allow (Wayland input goes through the
   RemoteDesktop portal / libei).
4. Start Deskflow at login: Deskflow settings, or GNOME Settings > Apps > Deskflow > Autostart.

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
3. Turn on TLS; accept the laptop's fingerprint on the first connection.
4. System Settings > Privacy & Security > **Accessibility**: allow Deskflow (needed to read the keyboard and mouse).

## Limits on this laptop
- Works while the Linux desktop is shown. In macOS panel mode (`gpu-mode mac`) GNOME is stopped, so the
  Linux client is gone; run Deskflow as a client inside that macOS instead (same server, another screen name).
- Windows in the Looking Glass window: input reaches Windows only after Right Ctrl captures it.
- Screen lock / login screen on Linux: the client runs in the user session, so it does not work at the GDM
  login screen.
