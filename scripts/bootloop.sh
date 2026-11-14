#!/bin/bash
# pingloop.sh N: success = guest answers ping within 90s (no serial dependence)
ok=0
for n in $(seq 1 $1); do
  virsh destroy macos >/dev/null 2>&1; sleep 5; virsh start macos >/dev/null 2>&1
  r=FAIL; for i in $(seq 1 18); do sleep 5; ping -c1 -W1 ${GUEST_IP:-192.168.122.135} >/dev/null 2>&1 && echo | nc -w2 ${GUEST_IP:-192.168.122.135} 22 | grep -q SSH-2.0 && { r="OK@$((i*5))s"; break; }; done
  case $r in OK*) ok=$((ok+1));; esac; echo "boot $n: $r"
done; echo "SUMMARY $ok/$1"; echo DONE
