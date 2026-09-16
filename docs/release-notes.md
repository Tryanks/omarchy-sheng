Omarchy on Xiaomi Pad 6S Pro 12.4 (`sheng`, SM8550): upstream Omarchy ARM
userspace on the [code002-2/archlinux-sheng](https://github.com/code002-2/archlinux-sheng)
device base. This is a community preview, not an official Omarchy release.

- Matching single-system (`userdata`) and dual-boot (`linux`) boot/rootfs pairs.
- Upstream Omarchy desktop, first-login provisioning and default application list.
- ARM package source/keyring integration, touchscreen service enabled, 2x display scale.
- Software cursor workaround for the internal DSI display.
- Password lock PAM configured; official keyboard lid uses lock/blank only.
- Suspend/hibernation disabled after a deep-suspend reset on the test device.
- Charger-mode service enabled; low battery requests poweroff at 5%.
- On-screen fingerprint settings with explicit enrollment, verification and deletion.
- Per-image installed package manifest, source run/revision and SHA-256 checksums.

Default login: **`omarchy` / `omarchy`**. Root initially uses the same password.
These builds use `zh_CN.UTF-8`; upstream components without Chinese translations
still use English. No private SSH keys or Wi-Fi credentials are included.

## Verified so far

The desktop runs on the physical tablet: Omarchy 4.0.2-1, Hyprland 0.56.2-3,
Quickshell, a 3048x2032 144 Hz display, official pogo keyboard, touchpad,
touchscreen, visible pointer and brightness control. Upstream first-login
provisioning completed. Android/Linux dual-boot was verified on this device.

A fresh locally built single-system image has also booted on this tablet from
`userdata`. Automatic Wi-Fi/SSH, desktop startup and Chinese Pinyin input were
verified. It uses the same rootfs stages and device packages as CI. Published
CI rootfs bytes were build/filesystem-checked, not separately flashed; the exact
local/CI package difference and test scope are recorded in
[hardware validation](https://github.com/Tryanks/omarchy-sheng/blob/main/docs/hardware-validation.md).

After consolidation, the single-system root expanded to ~229 GiB and booted
again. The full upstream update flow completed successfully after the included
sudo/runtime-directory verification fix. The fix is checked inside both release
images and recorded as a release overlay in their source metadata.

## Known limits

Automatic rotation, pen pressure, fingerprint enrollment/unlock, cameras, audio quality,
powered-off charging and fast charging have not been fully qualified. The fingerprint
driver currently waits for finger removal before reporting a match. Deep suspend
caused an unexpected reset and is disabled; a closed cover does not mean low-power
sleep. Charger-mode enablement is not proof of zero-battery recovery. The default
application list is retained where ARM binaries exist; missing binary targets
include dotnet-runtime, obs-studio, obsidian, pinta and qemu-user-static-binfmt.
The installed image records omissions in
`/var/lib/omarchy-sheng/omitted-packages.txt`.

Read **INSTALL.md** and verify **SHA256SUMS** before flashing. Match the boot/rootfs
pair to the chosen partition layout. Single-system flashing destroys Android
userdata; partition resizing is a separate, device-specific operation.

Thanks to code002-2 and the upstream sheng contributors for the kernel, firmware
and device support, and the Omarchy contributors for the desktop.
