# Host setup
1. Enable IOMMU/SVM in BIOS; ReBAR can stay on (the hook shrinks BARs for macOS).
2. Bind GPU 1 to vfio-pci at boot: `host/udev/40-vfio-gpu1.rules` (driver_override), `host/vfio-gpu1-bind` (retry fallback), `host/systemd/vfio-gpu1.service` (Before=docker.service), `/etc/modules-load.d/vfio-pci.conf` containing `vfio-pci`, then `update-initramfs -u`. driverctl did not work on this kernel. Unbinding amdgpu live leaves a stale KFD node for host GPU services: bind at boot, reboot once.
3. libvirt hook `host/libvirt-hooks/qemu` -> `/etc/libvirt/hooks/qemu` (chmod +x, restart libvirtd). On VM prepare it unbinds the GPU, shrinks BAR0/BAR2 to 256 MB (`resourceN_resize` = 8), rebinds to vfio-pci.
4. Remote console/Screen Sharing: `host/systemd/vnc-macos.service.template` (socat from the host's Tailscale address :5900 to the guest). Fill in `${TAILSCALE_IP}`.
5. DHCP reservation in the libvirt `default` network for each VM MAC.
6. Firewall: ufw allow on tailscale0 only; allow virbr0.
