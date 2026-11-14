# Spec
- CPU Ryzen 5 4500 (6C/12T), board MSI B550-A PRO, 30 GB RAM
- GPUs: 2x RX 6700 XT (Navi 22, 1002:73df). GPU 1 at 12:00.0/.1 for VMs, GPU 2 at 23:00.0 for host services
- Host: Ubuntu 26.04, kernel 7.0, KVM, QEMU 10.2, libvirt 12 (not Proxmox)
- Disks: boot Ubuntu on an SSD; one SSD holds data and VM images; macOS lives on a 500 GB SATA SSD (APFS), boots through OpenCore 1.0.2; Windows disk is a 250 GB partition
- macOS: Sonoma 14.6.1, SMBIOS iMacPro1,1, NootRX kext for RDNA2
- Windows: 10 LTSC 2021 (support ends Jan 2027), virtio disk and net
- Network: libvirt NAT (192.168.122.0/24, DHCP reservation per VM), access via Tailscale forwarders on the host
- Host services on GPU 2: RAG, whisper, ComfyUI, inference, JupyterHub GPU lab; failover tolerates short outage
