#!/usr/bin/env bash
# Assemble a fresh image natively on ARM64 Linux, using the same stages as CI.
# Supply matching, already-built device pacman packages and an upstream boot.img.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run as root inside ARM64 Linux.' >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo 'Native aarch64 Linux is required.' >&2; exit 1; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
packages=$(realpath "${1:?device package directory required}")
boot=$(realpath "${2:?matching boot image required}")
output=$(realpath -m "${3:?new output directory required}")
label=${4:-userdata}
[[ $label == userdata || $label == linux ]] || exit 1
[[ ! -e $output ]] || { echo "Refusing existing output directory: $output" >&2; exit 1; }
for name in linux-xiaomi-sheng fastrpc libssc iio-sensor-proxy-sheng sheng-sensors sheng-devauth alsa-xiaomi-sheng firmware-xiaomi-sheng; do
  compgen -G "$packages/$name-*.pkg.tar.*" >/dev/null || { echo "Missing package: $name" >&2; exit 1; }
done
python3 - "$boot" "$label" <<'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
assert data[:8] == b'ANDROID!', 'Not an Android boot image'
assert ('root=PARTLABEL=' + sys.argv[2]).encode() + b' ' in data[:4096], 'Boot root label mismatch'
PY
mkdir -p "$output"
mount_dir="$output/mount"
image="$output/rootfs.img"
export ROOTFS_BASE=alarm DEVICE_PACKAGES_DIR="$packages"
export ALARM_MIRROR="${ALARM_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm}"
export ALARM_TARBALL_URL="${ALARM_TARBALL_URL:-https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz}"
cleanup() {
  if mountpoint -q "$mount_dir/var/cache/pacman/pkg"; then umount "$mount_dir/var/cache/pacman/pkg"; fi
  bash "$repo/scripts/host/03-umount-chroot.sh" "$mount_dir"
  if mountpoint -q "$mount_dir"; then umount "$mount_dir"; fi
}
trap cleanup EXIT
cp "$boot" "$output/boot.img"
bash "$repo/scripts/host/00-prepare-image.sh" "$image" 24G "$mount_dir"
bash "$repo/scripts/host/01-bootstrap-arch.sh" "$mount_dir"
bash "$repo/scripts/host/02-mount-chroot.sh" "$mount_dir" "$output/boot.img"
if [[ -n ${PACMAN_CACHE_DIR:-} ]]; then
  mkdir -p "$PACMAN_CACHE_DIR" "$mount_dir/var/cache/pacman/pkg"
  mount --bind "$PACMAN_CACHE_DIR" "$mount_dir/var/cache/pacman/pkg"
fi
cat > "$mount_dir/root/build.env" <<EOF
DESKTOP=Omarchy
PLASMA_MOBILE=false
BROWSER=none
AUTOLOGIN=true
USERNAME=omarchy
HOSTNAME=xiaomi-sheng
LANGUAGE=zh_CN.UTF-8
QUIET_BOOT=true
BOOT_MODE=local
PARTITION_LABEL=$label
KERNEL_SOURCE=prebuilt
ARCH=aarch64
ROOTFS_BASE=alarm
EOF
chmod 600 "$mount_dir/root/build.env"
for stage in 10-base 20-desktop 25-browser 30-device-packages 40-system-config 90-verify; do
  echo "=== Local build: $stage ==="
  chroot "$mount_dir" "/root/sheng-build/in-chroot/$stage.sh"
done
chroot "$mount_dir" pacman -Q > "$output/packages.txt"
if mountpoint -q "$mount_dir/var/cache/pacman/pkg"; then umount "$mount_dir/var/cache/pacman/pkg"; fi
chroot "$mount_dir" pacman -Scc --noconfirm --color never
rm -f "$mount_dir/etc/resolv.conf" "$mount_dir/root/build.pw"
ln -s /run/NetworkManager/resolv.conf "$mount_dir/etc/resolv.conf"
rm -rf "$mount_dir/root/sheng-build" "$mount_dir/tmp/pkgs"
bash "$repo/scripts/host/03-umount-chroot.sh" "$mount_dir"
bash "$repo/scripts/host/04-finalize-image.sh" "$image" "$mount_dir"
trap - EXIT
rmdir "$mount_dir"
git -C "$repo" rev-parse HEAD > "$output/SOURCE_REVISION"
(cd "$output" && sha256sum rootfs.img boot.img packages.txt > SHA256SUMS)
echo "Fresh image ready: $output"
