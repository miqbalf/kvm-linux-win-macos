# macOS VM
Config: `vm/macos/macos.xml` (set your own VNC password). Domain boots the real macOS disk through a qcow2 overlay (`qemu-img create -f qcow2 -b /dev/sdX -F raw overlay.qcow2`) and a VM-only OpenCore image copy (never the real EFI).

Key settings
- CPU host-passthrough, 6 cores x 2 threads, `<cache mode=passthrough/>`, topoext. AMD kernel patches in OpenCore with core count 6; boot-arg `cpus=4` (more not tested)
- `<maxphysaddr mode='passthrough' limit='36'/>` so OVMF places 64-bit BARs low
- GPU hostdev 12:00.0 only, on a `pcie-root-port` with `-global pcie-root-port.hotplug=off` and `-global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off`
- NIC vmxnet3 at 00:04.0; OpenCore DeviceProperties `built-in=01` on that path so macOS makes a network service
- OpenCore: NootRX enabled, boot-args `revpatch=cpuname shikigva=128 keepsyms=1 debug=0x100 cpus=4 -no_compat_check agdpmod=pikera` (no `serial=3`: see docs/03), ReloadOptionRoms on, hardware kexts for real board (Realtek, Wi-Fi, sensors) disabled. WhateverGreen not needed.
- Emulated VGA kept as console; GPU renders to a connected display (or dummy plug)

Reliability (`scripts/bootloop.sh N`, destroy+start each boot, panic and ping+VNC check):
- first loop: 2 of 5 clean (3 panics early, cause unsaved)
- second loop: 6 of 6 clean
- third loop (10 boots): 8 clean, 2 panics (same kernel double fault ~10 s into boot, saved logs identical crash address)
- 4 vCPU (2 cores x 2 threads) variant: 10 of 10 panic (divide error). Keep 12 vCPU, 6 cores x 2 threads.
- `vmctl start` watchdog test (8 starts): all 8 came up within 2 tries; 3 on try 1, 5 needed a restart.

Final fix: removing `serial=3` from the OpenCore boot-args. With it, the kernel hit a stack-overflow double fault about 10 s into boot on 1 in 5 or more starts. After removal: 12 of 12 then 15 of 15 boots OK (pass = guest answers ping and an SSH banner, roughly 20 s after start). `vmctl start macos` still retries up to 3 times as a safety net.
Cost: no kernel serial log. Use the SSH/VNC checks above, or re-add `serial=3` temporarily to debug a panic.

Editing OpenCore boot-args in the VM-only image (VM stopped): `mount -o loop,offset=$((2048*512)) opencore-vm.img /mnt/ocv`, edit `/mnt/ocv/EFI/OC/config.plist` (key `boot-args`), `umount /mnt/ocv`. Keep a backup copy of the image first. The OpenCore config is not in this repo because it holds SMBIOS serials.
