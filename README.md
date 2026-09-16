# Omarchy on Xiaomi Pad 6S Pro (sheng)

Arch Linux ARM + the sheng device packages + upstream Omarchy ARM desktop.
Forked from [code002-2/archlinux-sheng](https://github.com/code002-2/archlinux-sheng).
The device kernel, Android boot image, firmware and ext4 rootfs stay with sheng.
Omarchy supplies Hyprland, Quickshell, UWSM, SDDM and user configuration.

**Bring-up in progress.** Hardware results and downloadable image links will be
recorded here after verification. Do not interpret a successful build as a
hardware test. This is a community port, not an official Omarchy release.

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

Default image login is `username` / `password`; change it on first use. Public
images contain no personal SSH keys or Wi-Fi credentials. Only Omarchy is
installed in Omarchy images; the KDE desktop is not bundled (upstream apps such
as Kdenlive can depend on KDE libraries).

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

## Updates

Use upstream `omarchy update`. The sheng overlay changes only the package-source
and ALARM keyring stages; the upstream workflow remains in charge.
The Omarchy edge repository is **Sync only**. Explicit source-qualified targets
select the Omarchy/Hyprland/Quickshell package set during a **full** ALARM upgrade;
`--ignore` prevents `--needed` from letting a different repository replace an
unchanged selected graphics package. Signing verification stays enabled.

Omarchy and omarchy-settings upgrade as an exact-version pair. The current
published ARM payload is 4.0.2; package availability can lag the upstream Git tag.
Library linkage is checked after installation. Settings transaction hooks preserve
ALARM identity, NSS/PAM and the device Plymouth configuration. Interrupted settings
transactions retain their recovery copy under `/var/lib/omarchy-sheng/`.

Device boot/kernel updates are managed separately. New Omarchy releases require bring-up review; this rolling ARM port
is experimental. Keep backups before upgrades. Settings and package versions
used by an image are recorded in its package manifest.

## Scope and sources

- [Upstream device build documentation](README.upstream.md)
- [Omarchy](https://github.com/omacom/omarchy)
- [Omarchy packages](https://github.com/omacom/omarchy-pkgs)
- [Omarchy Mac source-selection policy](https://github.com/omacom/omarchy-mac)

The upstream device packages and firmware retain their original licensing.
This fork does not relicense third-party payloads. New integration lives under
`scripts/omarchy`; upstream boot/device ownership is intentionally retained.
