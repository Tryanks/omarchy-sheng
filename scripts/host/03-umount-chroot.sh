#!/usr/bin/env bash
# 03-umount-chroot.sh —— 逆序卸载虚拟文件系统（即使前序步骤失败也要执行）
#
# 与 ubuntu-sheng 相同（本步骤与发行版无关）。
#
# 用法: sudo scripts/host/03-umount-chroot.sh [挂载点]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
require_root

MOUNT="${1:-/mnt/rootfs}"

# pacman-key leaves GnuPG daemons rooted in the image. Stop them before unmount;
# a lazy unmount would hide a still-live filesystem from the final fsck step.
if [[ -x "$MOUNT/usr/bin/gpgconf" ]]; then
  chroot "$MOUNT" gpgconf --homedir /etc/pacman.d/gnupg --kill all || true
fi

for d in dev/pts dev proc sys; do
  target="$MOUNT/$d"
  if mountpoint -q "$target"; then
    umount "$target" || die "Cannot unmount $target; refusing lazy filesystem cleanup"
    log "已卸载 $target"
  fi
done

# 注意：这里只卸载 chroot 用的虚拟文件系统，不卸载镜像本身
# （镜像的卸载由 04-finalize-image.sh 负责，否则 e2fsck 会拒绝在"已挂载"的文件上运行）
log "虚拟文件系统清理完成"
