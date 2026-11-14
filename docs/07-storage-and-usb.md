# Storage sharing and USB

## Design: share over the network, do not attach a raw disk to several guests
Two operating systems writing the same disk at once corrupt it. So an internal data disk is mounted on the host and shared over SMB to every VM and to your own devices. macOS, Windows and Linux all speak SMB, and the host keeps ownership of the filesystem.
Never share the disk that holds a VM image or the host's Docker data; only a plain data disk.

## What runs on the reference host
- Disk: 3.6 TB HDD (NTFS, SMART clean, label DATA_HDD) mounted at `/mnt/DATA_HDD` through `/etc/fstab` (`ntfs3`, `nofail`, owned by the system user `vmshare`).
- Samba share `DATA_HDD`, user `vmshare` (no shell). Password in `/root/.vmshare-smb-password` on the host (mode 600); rotate with `smbpasswd vmshare`.
- Reachable only from the VM network (`virbr0`, host address 192.168.122.1) and from Tailscale. Never from the LAN or the internet: Samba binds `lo` and `virbr0`; `smb-tailscale.service` forwards the Tailscale address to local Samba (Samba skips point-to-point interfaces such as `tailscale0`); `ufw` allows 445 only on `tailscale0` and `virbr0`.
- Hardening: SMB3 minimum, `map to guest = never`, anonymous access restricted, encryption when the client supports it, NetBIOS off, recycle bin and system folders hidden.
- Tested: login works, wrong password and anonymous access are refused, LAN address refused, write works, share listed from a Mac over Tailscale.

## Connect
| From | How |
|---|---|
| your Mac (Tailscale on) | Finder, ⌘K, `smb://<host>/DATA_HDD`, user `vmshare` |
| macOS VM | Finder, ⌘K, `smb://192.168.122.1/DATA_HDD` |
| Windows VM | Explorer address bar `\\192.168.122.1\DATA_HDD`, or `net use Z: \\192.168.122.1\DATA_HDD /user:vmshare` |
| Linux | `mount -t cifs //<host>/DATA_HDD /mnt/x -o username=vmshare` |
Get the password: `ssh root@<host> cat /root/.vmshare-smb-password`.

## Set it up on another disk or host
`scripts/setup-share /dev/sdXN SHARE_NAME` (root, Tailscale up). It follows the steps above; read it before running. Files: `host/samba/smb.conf.template`, `host/systemd/smb-tailscale.service.template`.

## USB passthrough
`scripts/usbctl` hot-plugs a USB device from the host into a running VM (libvirt `hostdev`, by vendor:product id).
```bash
ssh root@<host> usbctl list                              # find the id, e.g. 0781:5581
ssh root@<host> usbctl attach macos 0781:5581            # or win10-gpu
ssh root@<host> usbctl detach macos 0781:5581
```
- While attached, the host cannot use the device.
- Do not attach the keyboard or mouse you control the host with (you would lose it).
- A whole USB controller can instead be passed through like the GPU (vfio-pci); that needs the controller in its own IOMMU group and is not set up here.
- Status: written from the standard libvirt mechanism, not yet tested on a storage stick (none was plugged in). Test with a spare USB stick before relying on it.
- Linux does not need passthrough for sticks: mount them on the host and share a folder over SMB if you want both guests to see them.
