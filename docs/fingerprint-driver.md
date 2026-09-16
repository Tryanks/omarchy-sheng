# Fingerprint match latency

The device uses ianchb's private libfprint 1.94.10 / FPC1553 driver, shipped by
`xiaomi-sheng-fingerprint` 0.1.4. Its `run_verify` and `run_identify` wait for
finger removal after computing a match. fprintd cannot report the successful
authentication until these functions return. The user observed exactly this
delay in the settings verification flow.

The optional patch in `patches/fpc1553-report-match-immediately.patch` returns
successful matches immediately. It retains the trusted-application matching,
user/template checks, error handling, and removal waits on retry/mismatch.
The backend's `fpc_qtee_sensor_capture_sequence` already sends deep-sleep and
disables sensor wakeup after capture, including successful capture. The next
capture still waits for the previous finger to leave before accepting a new
touch. Enrollment is unchanged. A finger held on the sensor before starting
verification may therefore still need to be lifted and placed again.

Source is pinned to upstream commit
[`76e7301`](https://github.com/ianchb/xiaomi-sheng-fingerprint/tree/76e7301163b0e708f609c9864b3e5833e9f57402).
The build downloads a SHA-256-checked upstream libfprint tarball and applies
the upstream driver patch followed by our small patch. The driver retains
LGPL-2.1-or-later; upstream licensing and source remain available at that link.

## Build and validation

On native ARM64 Ubuntu 24.04, install the dependencies listed in
`.github/workflows/fingerprint.yml`, then run:

```sh
bash scripts/omarchy/build-fingerprint.sh /tmp/fpc1553-output
```

This does not install anything on a tablet. It runs the upstream backend tests
and our regression against the actual patched verification/identification
functions, with deterministic sensor/backend stubs. Success must return before
finger removal; mismatch, unknown templates, retry and backend errors must not
authenticate. The original driver's successful-match case fails this test.
These tests do not substitute for a real finger or validate physical sensor
power consumption.

The local ARM64 build was installed on the test tablet. Runtime linkage passed,
fprintd started, FPC1553 was detected and the enrolled right thumb remained
listed. Boot ID was unchanged. Actual touch-to-unlock latency after this patch
still requires a physical confirmation; it is not claimed as hardware-qualified.

This optional driver is **not included in preview.2 images**. Those retain the
upstream binary and its finger-removal behavior. A future device-package update
will replace a manually patched library; do not silently pin the whole package
or bypass upstream updates to preserve this experiment.

## Test-device rollback

The original private library on the test tablet is saved under
`/var/lib/omarchy-sheng/backups/fingerprint-before-immediate/` (root only).
To restore it when no fingerprint operation is in progress:

```sh
sudo install -m755 /var/lib/omarchy-sheng/backups/fingerprint-before-immediate/libfprint-2.so.2.0.0 /usr/lib/xiaomi-sheng-fingerprint/libfprint-2.so.2.0.0.restore
sudo mv /usr/lib/xiaomi-sheng-fingerprint/libfprint-2.so.2.0.0.restore /usr/lib/xiaomi-sheng-fingerprint/libfprint-2.so.2.0.0
sudo systemctl restart fprintd
```

Neither this replacement nor rollback removes enrollment databases or changes
password authentication. No reboot is required.
