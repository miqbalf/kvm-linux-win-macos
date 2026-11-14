# Lessons and breakthroughs
GPU init in macOS needed THREE QEMU changes. Compare `ioreg -r -n GFX0 -l -w0` IODeviceMemory with a real machine: it must list 2x256MB BARs.
1. Root port `hotplug=off`: otherwise GPU looks ejectable (eGPU) and fails.
2. `maxphysaddr limit=36`: default put 64-bit BARs near 224 GB and macOS dropped them. `pci-hole64-size=1024G` gives `PHYSMAP_PTOV bounds exceeded`.
3. Shrink BAR0/BAR2 from 16 GB to 256 MB (hook). Otherwise `KVM_SET_USER_MEMORY_REGION failed`.
Other findings
- Pass only 12:00.0, not the audio function 12:00.1: shared IRQ caused spinlock-timeout panics.
- NootRX panics "Failed to find a compatible GPU" if the GPU sits on the root bus: put it behind a pcie-root-port.
- e1000 NIC dead in macOS: use vmxnet3 plus built-in property.
- Ryzen 4500 has 12 threads; core/thread topology must match the real machine, and `cpus=1` was needed for Recovery without patches.
- Booting the real Hackintosh invalidates the overlay: recreate it.
- `virsh shutdown` is ignored by macOS until the dialog is clicked.
- Shared Tailscale jump hosts may forbid -L forwards: connect to the host directly.
- Boot loops: save the serial log on panic; check the job is alive before reporting it.
- The macOS disk shows SMART reallocated/uncorrectable sectors: back it up (Time Machine) and use the overlay.

## The intermittent boot panic (the longest chase)
- Symptom: macOS VM panics about 10 s after start on 1 in 5+ boots: `Double fault` with CR2 next to RSP (kernel stack overflow), right after AHCI disk init, same RIP every time.
- Not the cause (each tested with a loop): pause length between stop and start, `maxphysaddr limit=36` (10/12 still), removing the GPU (that config panics differently), PCI remove+rescan of the GPU in the hook (it stops the VM booting at all), 4 vCPU (10/10 panic with divide error).
- Cause/fix: the kernel serial console (`serial=3` boot-arg) added for debugging. Removing it gave 27 of 27 clean boots.
- Method lessons: (1) a test must prove the thing worked (ping + SSH banner), not only that a panic string is absent: three of my early loops reported false success because the VM never booted or the panic text did not match my grep; (2) check that a background job really is running before reporting it; (3) a debug option can itself be the bug.

## Switching the GPU between Windows and macOS without rebooting the host
- Observed once: after win10-gpu had been force-stopped right after its first AMD driver install, macOS panicked at boot in `AMDRadeonX6000_AmdPowerPlayHelper::powerUp` (3 of 3 tries) until the host rebooted. Navi 22 has no function-level reset and `vendor-reset` does not support it, so Linux only has bus-level resets.
- Not every Windows to macOS switch fails: a later plain stop+start (no reset) worked, so the failure depends on what the guest driver left in the card.
- What works (3 of 3 cycles macOS to Windows to macOS, ~7 min each): `vm-switch` = stop guest, `gpu1-reset 2`, start target. Level 2 removes the card's PCI devices, pulses a secondary bus reset on the host root port with `setpci`, then rescans with `/sys/bus/pci/drivers_autoprobe` set to 0 so that no driver binds, and binds vfio-pci by hand.
- What does NOT work or is dangerous:
  - Raw `setpci` secondary bus reset on the card's own switch ports without removing the devices first: config space is not restored, the GPU reads 0xffff and QEMU fails with "Unknown PCI header type '127'".
  - Letting `amdgpu` bind GPU 1 after a guest used it (as a "driver reset", or by a plain rescan when autoprobe is on): the whole host rebooted in testing (about 2 minutes of downtime for all docker services). Always rescan with autoprobe off.
  - PCI remove and rescan in the libvirt hook at VM start: the guest did not boot at all.
  - Writing `1` to `reset` of the card's upstream switch port: "Inappropriate ioctl for device".
- Safety net: `vmctl` records the last guest (`/run/gpu1-last-guest`, cleared by `gpu1-reset`) and refuses macOS after Windows unless the GPU was reset. If macOS panics in powerUp anyway, reboot the host.
- Serial console debugging: set `serial=3` in boot-args temporarily to read a panic, then remove it (it causes the early boot panic).
