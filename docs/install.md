# Omarchy sheng images

Only for Xiaomi Pad 6S Pro 12.4, codename **sheng**. Bootloader must be unlocked.
Back up data and original boot/partition information before changing partitions.
These images do not automatically repartition the tablet.

1. Verify `SHA256SUMS` after downloading all files for the selected mode.
2. If the rootfs is split, join `.part-00`, `.part-01`, etc. in numeric order:
   `cat omarchy-sheng-dual-rootfs.img.zst.part-* > rootfs.img.zst` (Linux/macOS),
   or `copy /b part-00+part-01 rootfs.img.zst` (Windows cmd; use actual filenames).
3. Decompress with `zstd -d <image>.img.zst -o rootfs.img`.

## Dual boot

Requires a separately prepared ext4-capable GPT partition named `linux` large
enough for the decompressed image, and Android retained on `userdata`. Use the
dual boot image with this layout. The tested device reserves slot A for Android
and slot B for Linux. Do not assume that every device already has this layout.

After confirming slot A contains the working Android boot image and the `linux`
partition is prepared, from bootloader fastboot:

```sh
fastboot flash linux rootfs.img
fastboot flash boot_b omarchy-sheng-dual-boot.img
fastboot set_active b
fastboot reboot
```

Select slot A in fastboot to return to Android; select B to return to Linux.
Do not format `userdata` when following this dual-boot procedure.

## Single system

Uses `PARTLABEL=userdata` for Linux. **Flashing this rootfs to userdata destroys
Android user data and replaces it with Linux.** Use the single-system boot image;
the dual image points at a different partition.

```sh
fastboot flash userdata rootfs.img
fastboot flash boot_b omarchy-sheng-single-boot.img
fastboot set_active b
fastboot reboot
```

If converting a previously split dual layout, consolidate its partitions first
to reclaim the old `linux` partition. That requires a layout-specific partition
plan; these commands deliberately do not guess disk geometry or modify the GPT.

## First boot and recovery

The root filesystem expands to its partition on first boot. Default image account:
`omarchy`, password `omarchy` (root has the same initial password). Change these
with `passwd` and `sudo passwd root`. Public images include no personal SSH keys
or Wi-Fi profiles. SDDM starts the upstream Omarchy UWSM session; the first login
initializes the user's theme and developer environment and may need Internet.

Use upstream `omarchy update`. ARM-specific source selection and keyring helpers
are provided by the device overlay. Boot images must always match the installed
sheng kernel module package; ordinary desktop updates do not flash boot images.

Original Android firmware/boot images and a known-good Linux image remain recovery
options with an unlocked bootloader. Never relock it while custom images are in use.

Hardware test status is listed in the release notes. A build and filesystem check
alone do not establish that a particular mode has been boot-tested.
