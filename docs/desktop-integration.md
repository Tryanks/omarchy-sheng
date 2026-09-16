# Tablet desktop integration

This describes the source for the next image, not the already published
preview.2 assets. Both partition layouts use the same desktop payload.

## Device settings and monitor

`omarchy-sheng-devices pen` and `omarchy-sheng-devices fingerprint` open native
Quickshell panels built with Omarchy's UI components. The application launchers
and pen bar widget open the same panel. Pen status comes from the upstream
hardware interfaces; unknown battery readings remain unknown. Bluetooth pairing
and settings are restricted to the pen address reported by the device.

Fingerprint operations use the existing fprintd stack. Enrollment, verification,
cancellation and deletion are explicit UI actions. Enabling lock authentication
is separate from verification and requires administrator authorization. Deletion
requests authorization before touching enrolled records. Fingerprint templates
stay in fprintd's local storage; neither templates nor a user's enrollment state
are build inputs.

The system monitor is rmacy/omarchy-system-monitor at
`4f3f3dc71a2b7787ef8bc6cf85b078eb7661dc8a`, retaining its MIT license. Defaults
show CPU usage, memory usage and the `cpuss0_thermal` sensor labeled CPU. This is
one CPU thermal-zone measurement, not a maximum across all silicon sensors.
The existing power widget shows the battery percentage. Adreno utilization is
not supplied by this plugin's NVIDIA-specific GPU monitor.

## Waydroid and APK installation

`images.json` pins public vanilla ARM64-only system/vendor images. Build-time
downloads verify their archive hashes and record extracted image hashes. A first
boot unit runs Waydroid's initializer with those local images before starting
the container. No Android accounts, installed applications or userdata are
imported from the development tablet.

The OMX workaround validates the exact original library hash, then writes a
small overlay. It avoids repeatedly querying a missing vendor OMX service;
software CCodec is selected. It is not hardware video acceleration. Unknown
library versions fail validation rather than receiving an unverified patch.

Opening an APK uses `waydroid-install-apk`. It starts the current user's session,
waits for Android, stages the APK, and reports Android Package Manager's actual
result. The polkit helper accepts only a UUID-named regular APK staged by the
active local wheel user for that same Waydroid session. It exposes no generic
root command execution. Users can install further ARM-compatible APKs. The
distribution does not bundle Bilibili or other third-party APKs.

## USB shell

The image enables `omarchy-sheng-adb.service`. AOSP-derived standalone adbd is
pinned to happyme531/standalone-linux-adbd `v36.0.1-linux.2` and verified by SHA-256.
The supervisor configures FunctionFS and launches adbd as the selected desktop
user. A USB-connected host can use `adb shell`, `adb push` and `adb pull` without
authentication. Shell access has the same account permissions and sudo policy
as that user. No user credential is embedded in the daemon.

There is no TCP listener: FunctionFS readiness is checked before launch and the
unit denies socket binding to prevent the daemon's TCP fallback. USB role
selection avoids taking an occupied host bus away from connected USB devices;
this does not promise simultaneous Type-C host and peripheral roles.

```sh
sudo systemctl disable --now omarchy-sheng-adb.service
sudo systemctl enable --now omarchy-sheng-adb.service
```

## Tcode packaging

Tcode is installed as the pacman package `tcode-bin`, using a reviewed snapshot
of the AUR recipe at `47f070ef530b4e22f5cdd8233b6020498fe19c83`. This ARM image
snapshot selects aarch64, includes the upstream MIT license, disables unnecessary
stripping of the supplied release binary, and corrects the archive checksum to
the **reissued** 0.1.52 release published on 2026-09-16 at 21:56 UTC:

`dde8b9a9e9f4896173f5541f3911de439756f71cee6c0e4868d72b189e4d694a`

The withdrawn artifact is not accepted. The reviewed PKGBUILD is built as an
unprivileged user, then installed with pacman. The package name/version remain
compatible with upstream AUR updates using the existing `yay` helper. AUR itself
is not a pacman binary repository. Only the application is installed; agent
accounts, projects and personal application settings remain the user's own.

## Validation boundaries

On the development tablet, the QML panels were opened and visually inspected;
the owner reported repeated successful keyboard and fingerprint use. This is
positive manual validation, not a completed stress test of every lid/fold state.
The pen's settings need the corresponding physical pen for end-to-end checks.

Waydroid and Bilibili HD were exercised on the existing installation, and the new
APK installation path successfully reinstalled Bilibili HD. USB ADB shell exit
status and a push/pull file round trip were verified, including service stop and
restart. Offline first boot from a newly built image still needs a separate
hardware test. Steam, FEX game settings and downloaded games are device-only
experiments and are not bundled by these installers.
