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

## Switching the GPU between Windows and macOS needs a host reboot
- Observed: after win10-gpu ran with the GPU (Windows installed an AMD driver), macOS panicked on every start inside `AMDRadeonX6000_AmdPowerPlayHelper::powerUp` (3 of 3 tries, plus a manual secondary bus reset). A host reboot fixed it.
- Why: Navi 22 has no function-level reset and vendor-reset does not support it. Linux can only bus-reset it, which does not clear what a guest driver left behind. A forced stop of a guest has the same effect.
- Rule: Windows then macOS needs a host reboot. macOS then Windows booted fine in one test (not proven further); macOS then macOS is fine (27 boots). `vmctl` records the last guest in `/run/gpu1-last-guest` (cleared on reboot) and refuses macOS after Windows until you reboot (override: `FORCE=1`, expect a panic).
- Tried and rejected: PCI remove + rescan in the libvirt hook (VM did not boot at all).
- Serial console debugging: set `serial=3` in boot-args temporarily to read a panic, then remove it (it causes the early boot panic).
