# Charging and idle load follow-up (2026-09-17)

The user reported a Xiaomi 90W charger connected directly, delivering about 72W
while the tablet was powered off but charging slowly after booting Linux.

During the observed boot, `xiaomi-mipps-auth` ran before the Type-C data-role
node existed and while `pdo2` was zero. It skipped authentication and exited
successfully. Later the PDO was populated, but the USB-online trigger had already
recorded its attempt, leaving `pd_verifed=0` and `fastchg_mode=0`.

Before retry, USB telemetry was around 8.83V and 1.25–1.39A, with a reported
1.5A input limit. Battery capacity still increased from 12% at 03:52 to 18% at
04:09. Restarting the unmodified upstream authentication service with enumeration
complete verified the adapter and both battery gauges. It selected PD_PPS,
`pd_verifed=1`, `fastchg_mode=1`, and a 90W advertised profile. The service logged
a reverse-authentication timeout, but the main authentication succeeded and the
charging telemetry and capacity increase below were observed.

At 04:13, the charging-pump readings were 17.8V and 2.228A + 2.148A, approximately
78W combined bus power. This is a driver-derived estimate, not an external power
meter measurement; the 90W profile itself is not evidence of 90W actual input.
The ordinary USB current node remained at 72mA in this mode and must not be used
as total fast-charge current. Battery capacity had risen from 19% before retry
to 23%, with battery temperature 32.5°C.
At 04:15, capacity was 31%, battery temperature 35.0°C, and the combined
charging-pump estimate remained about 79W. No reboot occurred between samples.

A systemd drop-in now waits up to 20 seconds for the Type-C data-role and nonzero
PDO before the upstream authentication runs. It does not write electrical limits,
change the authentication algorithm or force an unverified charger into MiPPS.
Non-PD or missing nodes time out to the upstream eligibility check. Local
regression tests replay delayed PDO enumeration and verify bounded timeout;
the live ready-state check passes. A fresh cold boot with the charger attached
has not yet tested this ordering change. No reboot was performed for this fix.
Published preview.2 images predate this follow-up.

Separate load samples showed approximately 3% total CPU utilization with the
desktop idle, no Steam processes, negligible disk I/O, about 2GB RAM used and
9GB available. When Omarchy's Foot/ttfx screensaver started at 120 FPS, samples
rose to roughly 26–33% total CPU utilization; Foot's lifetime average was around
1.5 CPU cores during that short run. This animation is not a low-power sleep
state. These are observations under different activity states, not an isolated
power-consumption benchmark of the desktop or pointer guard.

Upstream authentication: <https://github.com/ianchb/xiaomi-mipps-auth>.
