# Omarchy on Xiaomi Pad 6S Pro (sheng)

Arch Linux ARM + the sheng device packages + upstream Omarchy ARM desktop.
Forked from [code002-2/archlinux-sheng](https://github.com/code002-2/archlinux-sheng).
The device kernel, Android boot image, firmware and ext4 rootfs stay with sheng.
Omarchy supplies Hyprland, Quickshell, UWSM, SDDM and user configuration.

**Running on hardware.** Omarchy starts through SDDM/UWSM on sheng, with the
official keyboard, touchpad and touch confirmed. See [hardware validation](docs/hardware-validation.md)
for exact versions and limits. [Download single and dual boot preview images](https://github.com/Tryanks/omarchy-sheng/releases/tag/v0.1.0-preview.2).
Do not interpret a successful build as a hardware test. This is a community port, not an official Omarchy release.

## Images

Run **Build RootFS** with `desktop=Omarchy`, `rootfs_base=alarm`:

| Mode | Root partition | Use |
| --- | --- | --- |
| `dual (linux)` | `PARTLABEL=linux` | Keep Android on its own userdata partition and boot slot |
| `single (userdata)` | `PARTLABEL=userdata` | Replace Android userdata with Linux |

Each run builds a matching `boot.img` and `rootfs.img`, a package manifest and
SHA-256 checksums. Both images use ext4 and first-boot `x-systemd.growfs`; no
Limine, EFI partition, UKI or Btrfs is involved. Never mix boot images and kernel
module packages from different releases. Partitioning and slot selection are
explicit flashing operations; the desktop installer does neither.

Default image login is `omarchy` / `omarchy`; change it on first use. Public
images contain no personal SSH keys or Wi-Fi credentials. Only Omarchy is
installed in Omarchy images; the KDE desktop is not bundled (upstream apps such
as Kdenlive can depend on KDE libraries).

## Build locally on ARM64 Linux

`scripts/build-local.sh` runs the same bootstrap, installation, device setup and
verification stages as CI. On an ARM Mac, run it inside a native ARM64 Linux VM
(such as OrbStack). It does not run directly on macOS.

Supply a flat directory of the device `.pkg.tar.*` artifacts and a matching
single-system or dual-boot `boot.img` from the same kernel release:

```sh
sudo env ALARM_TARBALL_PATH=/path/to/ArchLinuxARM-aarch64-latest.tar.gz \
  PACMAN_CACHE_DIR=/path/to/pacman-cache \
  bash scripts/build-local.sh /path/to/device-packages /path/to/boot.img \
  /path/to/new-output-directory userdata
```

Use `linux` instead of `userdata` for dual boot. The output directory must not
already exist. The builder creates a fresh image, reuses signed package downloads,
and produces checksums and a package manifest. Device packages can be built using
`packages/` or reused from a matching CI run; the rootfs is assembled locally.
Default local settings are Omarchy, Chinese locale, and `omarchy` / `omarchy`.
Wi-Fi credentials and private access configuration are never part of this builder.

## Existing sheng Arch installation

Back up configuration and record `pacman -Q` first. As root on **aarch64 ALARM**:

```bash
bash scripts/omarchy/install.sh
```

This installs the desktop payload. New accounts created afterwards inherit
`/etc/skel`; existing users must explicitly merge those defaults with their own
configuration. Select **Omarchy (Hyprland uwsm)** in SDDM. The upstream default app list is installed wherever ARM binary targets exist;
missing packages are recorded in `/var/lib/omarchy-sheng/omitted-packages.txt`.
The first real login
runs unmodified upstream user provisioning with a live DBus/Wayland/user-systemd session.
The installer never runs `omarchy-apply-system` or changes device partitions.

## Lock, lid, charging and fingerprints

Password locking is configured explicitly. Closing the official keyboard cover
locks and blanks the display; opening it wakes the display without unlocking.
System suspend/hibernation is disabled pending investigation of an unexpected
reset during deep suspend on the test tablet. A closed cover therefore does not
imply low-power sleep. Battery policy warns at 20%, becomes critical at 10%, and
requests an orderly poweroff at 5%.

The upstream `xiaomi-charger-mode` service is enabled for
`androidboot.mode=charger` boots only. It has **not** yet been tested through a
powered-off charging cycle or battery depletion; enabling it is not proof that
zero-battery recovery or charging protections are qualified.

Open **Fingerprint Settings / 指纹设置** in the application launcher to enroll,
verify or delete a power-button fingerprint. The GTK window shows the FPC1553
sensor's enrollment progress and allows cancellation. Only a successful
verification followed by administrator authorization enables fingerprint lock
authentication; password unlock remains available. No fingerprints ship in an
image. The device's existing fprintd/private-libfprint stack stores the records.
This integration enables lock-screen authentication, not sudo or polkit bypasses.
Administrator prompts authenticate the active local wheel user, avoiding the
ALARM base image's residual `alarm` account.
An [optional fingerprint latency patch](docs/fingerprint-driver.md) is being
validated separately; preview.2 keeps the upstream finger-removal behavior.

For existing installations, apply these defaults as root from this checkout:

```sh
python3 scripts/omarchy/configure-power.py
install -m755 scripts/omarchy/{verify.sh,verify-power.py,preserve-system.sh} /usr/local/lib/omarchy-sheng/
install -m644 scripts/omarchy/session.lua /usr/local/lib/omarchy-sheng/session.lua
systemctl daemon-reload
systemctl reload systemd-logind
systemctl restart upower
```

Reload Hyprland configuration in the desktop session. Existing users must have
the `session.lua` include in their Hyprland autostart overrides as described
above. This procedure does not reboot, suspend, start charger mode, or enroll.

## Updates

Charging startup timing and measured idle/screensaver load are documented in
[charging validation](docs/charging-validation.md).

Use upstream `omarchy update`. The sheng overlay changes only the package-source
and ALARM keyring stages; the upstream workflow remains in charge.
The Omarchy edge repository is **Sync only**. Explicit source-qualified targets
select the Omarchy/Hyprland/Quickshell package set during a **full** ALARM upgrade;
`--ignore` prevents `--needed` from letting a different repository replace an
unchanged selected graphics package. Official packages retain required signature
verification.

Application installation also uses the [Omarchy Mac ARM supplement](https://github.com/omarchy-mac/omarchy-pkgs-aarch64)
after ALARM. This supplies portable ARM applications including Ghostty. Its current
edge artifacts are unsigned, so only that repository uses `Optional TrustedOnly`;
global and official-repository trust settings are unchanged. The sheng updater
keeps the desktop pair and selected graphics packages on official Omarchy edge,
not the supplement's Mac-specific desktop packages.

Use the native Install menu or `omarchy-pkg-add ghostty`. Installation helpers
resolve official Sync-only targets explicitly and recognize virtual package
providers such as `obsidian-appimage`. With bare pacman, official-only applications
still require a qualified target, for example `sudo pacman -S omarchy/typora`.
These helpers do not make x86-only applications available on ARM. See
[ARM application sources](docs/arm-app-sources.md) for validation and image scope.

Omarchy and omarchy-settings upgrade as an exact-version pair. The current
published ARM payload is 4.0.2; package availability can lag the upstream Git tag.
Library linkage is checked after installation. Settings transaction hooks preserve
ALARM identity, NSS/PAM and the device Plymouth configuration. Interrupted settings
transactions retain their recovery copy under `/var/lib/omarchy-sheng/`.

Device boot/kernel updates are managed separately. New Omarchy releases require bring-up review; this rolling ARM port
is experimental. Keep backups before upgrades. Settings and package versions
used by an image are recorded in its package manifest.

The upstream updater checks for a PC-style `vmlinuz` when deciding whether to
offer a reboot. On sheng it can show "Linux kernel has been updated" even when
the kernel is unchanged; that message does not mean it flashed a boot image.

## Scope and sources

- [Upstream device build documentation](README.upstream.md)
- [Omarchy](https://github.com/omacom/omarchy)
- [Omarchy packages](https://github.com/omacom/omarchy-pkgs)
- [Omarchy Mac source-selection policy](https://github.com/omacom/omarchy-mac)

The upstream device packages and firmware retain their original licensing.
This fork does not relicense third-party payloads. New integration lives under
`scripts/omarchy`; upstream boot/device ownership is intentionally retained.
