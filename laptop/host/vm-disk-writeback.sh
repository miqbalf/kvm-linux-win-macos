#!/bin/bash
# Switch the laptop VMs' qcow2 disks from cache='none' (O_DIRECT) to cache='writeback' io='threads'.
# Why: the images live on btrfs with copy-on-write and checksums. With O_DIRECT the guest can change a buffer
# while it is being written, so btrfs stores a checksum that no longer matches the data; later reads fail with
# "BTRFS ... csum failed ... direct IO failed ... err no 10" and the guest gets read errors
# (seen 2026-11-20 on win10.qcow2: 350 errors, 86 blocks). Buffered writes do not have this problem.
# Only touches VMs that are shut off. No sudo needed (user in group libvirt).
set -euo pipefail
V="virsh -c qemu:///system"
for vm in win10-gpu win10 macos macos-igpu; do
  $V dominfo "$vm" >/dev/null 2>&1 || continue
  if [ "$($V domstate "$vm")" != "shut off" ]; then echo "$vm: running, skipped (shut it down first)"; continue; fi
  x=$(mktemp); $V dumpxml --inactive --security-info "$vm" > "$x"
  if grep -q "cache='none'" "$x"; then
    sed -i "s/cache='none' io='native'/cache='writeback' io='threads'/; s/cache='none'/cache='writeback'/" "$x"
    $V define "$x" >/dev/null && echo "$vm: now $(grep -oE "cache='[a-z]+'( io='[a-z]+')?" "$x" | head -1)"
  else
    echo "$vm: already $(grep -oE "cache='[a-z]+'" "$x" | head -1)"
  fi
  rm -f "$x"
done
