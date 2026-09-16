# Hardware bring-up: 2026-09-17

Device: Xiaomi Pad 6S Pro 12.4 (`sheng`, SM8550), 12 GB RAM, official pogo keyboard.

## Confirmed on the physical tablet

- Android slot A and Arch Linux slot B both booted before the desktop migration.
- Omarchy 4.0.2-1 / Hyprland 0.56.2-3 / Quickshell 0.3.0.r20.g28771c7-3
  installed on the existing Arch sheng root; SDDM launched its upstream UWSM session.
- Unmodified upstream user provisioning and first-run steps completed; both
  `finalize-user` and `first-run-user` markers present.
- DSI-1: 3048x2032, 144 Hz, scale 2, DRM backend and explicit sync supported.
- GPU detected as Qualcomm FD740. No Hyprland config errors.
- Keyboard, touchpad and touchscreen independently confirmed by the user.
- Hardware cursor was invisible despite functional input. Switching only
  `cursor.no_hardware_cursors=true` restored it; user confirmed normal movement.
- Brightness works in the real desktop session via brightnessctl/logind. A
  root-SSH `runuser` invocation has no seat and cannot test those permissions.
- Foot mapped a real terminal window; btop and Neovim ran visibly.
- No failed system or user systemd units after first-run.
- Wi-Fi, SSH and PipeWire service availability retained.

## Limits

This validates the desktop on an existing dual-boot Arch installation. Fresh
release rootfs images require their own build/filesystem checks; neither a new
flash of the release rootfs nor a destructive single-system conversion has been
performed on this tablet. The single-system variant uses the upstream boot
image with `PARTLABEL=userdata`, and must not be described as independently
hardware-tested.

Automatic rotation, pen pressure, fingerprint enrollment, cameras, audio quality,
suspend/resume and charging performance are not yet fully qualified. There is no
claim that every optional application has been exercised merely because its ARM
package installed.

Missing default binary targets are recorded per image in
`/var/lib/omarchy-sheng/omitted-packages.txt`. The initial set is dotnet-runtime,
obs-studio, obsidian, pinta and qemu-user-static-binfmt. Apple-only asdcontrol and
the PC kernel-modules-hook are excluded because sheng owns those device paths.

The upstream package's `version` file still says `4.0.0.alpha`; `pacman -Q omarchy`
is the authoritative installed package version used for this report.
