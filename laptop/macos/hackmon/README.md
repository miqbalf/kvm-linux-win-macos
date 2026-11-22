# hackmon: boot-speed and stability log for the Hackintosh

Writes one report per boot and a daily error report, so slow boots, panics and kext/SSDT problems show up over time.

Install on the Hackintosh (asks for sudo):
```
bash install.sh
```
- `com.local.hackmon`: 4 min after each boot, `hackmon report` writes `/Library/Logs/HackMon/boot-<date>.txt`
  and adds a row to `boots.csv`.
- `com.local.hackmon-daily`: 12:30 every day, `hackmon daily` (NVMe, ACPI, kext and iGPU errors of the last 24 h).

Commands: `hackmon summary` (table of all boots), `hackmon last` (latest report), `sudo hackmon report`.

A report holds:
- boot timeline from kernel start: dyld shared cache, launchd, Data volume mount, APFS boot trim, EndpointSecurity
  wait, login window,
- previous shutdown cause, kernel panics, NVMe/ACPI/kext/iGPU error counts with samples,
- sleep/wake, loaded third-party kexts, temperatures and fans (NitroEC).

It reads the unified log once per run (about 35 s). Known harmless lines are filtered (`NOISE` in the script):
Apple's missing `AppleKIS`, PPP/L2TP/PPTP and `IOVersatile` load failures, an IGPU info line.

Baseline 2026-11-22 (OpenCore 1.0.8, trim 0): dyld +1 s, launchd +2 s, Data +3 s, ES +35 s, login +49 s;
4 `AppleNVMe Assert failed` lines at boot (seen on every boot, no effect so far).
