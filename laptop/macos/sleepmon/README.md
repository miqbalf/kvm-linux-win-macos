# sleepmon: sleep/wake logger for the Hackintosh

Records every sleep and wake, and at the next boot detects a failed wake (last event was a sleep, no wake,
and the shutdown cause is not normal). Made to catch wake failures that happen only on the 2nd or 3rd cycle.

Install: `bash install.sh` (builds with `swiftc`, installs a LaunchDaemon, asks for sudo).
Report: `sleepmon-report` (counts, failed wakes with the cycle number, last 20 events), `sleepmon-report log`.

Per sleep: cycle number since boot, `hibernatemode`, battery, lid, CPU temperature, power assertions.
Per wake: seconds asleep, wake reason (from `pmset -g log`), any `Sleep Wake failure`.
Per boot: previous shutdown cause and the last power events before the boot.
Files: `/Library/Logs/SleepMon/sleepmon.log`, `/Library/Logs/SleepMon/events.csv`.

On this laptop VirtualSMC reports shutdown cause 5 ("software initiated") even after a kernel panic or a forced
power-off, so sleepmon does not use the cause: a boot whose last recorded event is a sleep counts as a failed wake.

Found with it on 2026-11-22: a DarkWake loop on 2026-11-18 22:08-22:14, a wake every 10-20 s
 (Intel USB device controller and CNVi wireless wake sources), with .
