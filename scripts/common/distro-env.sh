#!/usr/bin/env bash
# 公共环境：Arch 侧常量 + 底包选择 + 日志工具
# 被 host/ 与 in-chroot/ 下的脚本共同 source。
#
# 与 ubuntu-sheng 的差异：Arch 是滚动发行版，没有「版本 ↔ suite 代号」映射，
# 因此这里不再有 DISTRO_SERIES / DISTRO_SUITE，改为集中维护底包地址、镜像地址
# 与架构常量，避免散落在 workflow YAML 里。
#
# 两种底包（由 ROOTFS_BASE 选择，见下）：
#   * alarm      —— Arch Linux ARM 官方滚动 tarball + ALARM core/extra/alarm 仓库（默认）
#   * holo-core  —— Valve/Collabora 的 Holo Core（Steam Frame 的 Arch Linux aarch64 预览）
#                   rootfs 底座 + holo-packages 的 core/extra 仓库

log()  { printf '[%s] %s\n' "${0##*/}" "$*"; }
warn() { printf '[%s] 警告: %s\n' "${0##*/}" "$*" >&2; }
die()  { printf '[%s] 错误: %s\n' "${0##*/}" "$*" >&2; exit 1; }

# 镜像内由 workflow 写入的构建参数（/root/build.env）；宿主阶段不存在该文件
if [[ -f /root/build.env ]]; then
  set -a
  # shellcheck source=/dev/null
  . /root/build.env
  set +a
fi

# ---------------------------------------------------------------------------
# 架构
# ---------------------------------------------------------------------------
export ARCH="${ARCH:-aarch64}"

# ---------------------------------------------------------------------------
# 底包选择
# ---------------------------------------------------------------------------
export ROOTFS_BASE="${ROOTFS_BASE:-alarm}"
case "$ROOTFS_BASE" in
  alarm)             export ROOTFS_BASE="alarm" ;;
  holo|holo-core)    export ROOTFS_BASE="holo-core" ;;
  *) die "不支持的 ROOTFS_BASE: $ROOTFS_BASE（可选 alarm | holo-core）" ;;
esac

# ---------------------------------------------------------------------------
# Arch Linux ARM（滚动）
# ---------------------------------------------------------------------------
export ALARM_TARBALL_URL="${ALARM_TARBALL_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}"
# 包镜像：Server = $ALARM_MIRROR/$arch/$repo（写入镜像内 /etc/pacman.d/mirrorlist）
# 中国大陆可换用 https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm 等镜像
export ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"

# ---------------------------------------------------------------------------
# Holo Core（Valve/Collabora 的 Steam Frame aarch64 预览；内容冻结在 Arch 2025-11 状态）
#   rootfs：system.rootfs.zst（base + base-devel 底座，无内核镜像/DTB/桌面）
#   仓库：  <HOLO_MIRROR>/$repo/os/$arch，只有 core 与 extra，SigLevel = Optional
# ---------------------------------------------------------------------------
export HOLO_SNAPSHOT="${HOLO_SNAPSHOT:-mash-20251118.3}"
export HOLO_BASE_URL="${HOLO_BASE_URL:-https://holo-packages.steamos.cloud/holo-core-aarch64-preview}"
export HOLO_ROOTFS_URL="${HOLO_ROOTFS_URL:-${HOLO_BASE_URL}/${HOLO_SNAPSHOT}/system.rootfs.zst}"
export HOLO_MIRROR="${HOLO_MIRROR:-${HOLO_BASE_URL}/${HOLO_SNAPSHOT}}"

# ---------------------------------------------------------------------------
# 宿主上可复用的构建 chroot（供 makepkg 使用，见 host/20-alarm-chroot.sh）
#   两种底分开存放，避免快照缓存互相污染（holo 底 glibc 2.42 / ALARM 已 2.43）
# ---------------------------------------------------------------------------
export ALARM_CHROOT="${ALARM_CHROOT:-/mnt/alarm}"
export HOLO_CHROOT="${HOLO_CHROOT:-/mnt/holo}"

if [[ "$ROOTFS_BASE" == "holo-core" ]]; then
  export BUILD_CHROOT="${BUILD_CHROOT:-$HOLO_CHROOT}"
  export CHROOT_SNAPSHOT_TAG="holo-core-${HOLO_SNAPSHOT}"
  # holo 源缺 chrony/fprintd/sddm/kate/gnome/plymouth，用专门的包列表（见 scripts/lists-holo/）
  export LISTS_DIR="${LISTS_DIR:-lists-holo}"
else
  export BUILD_CHROOT="${BUILD_CHROOT:-$ALARM_CHROOT}"
  export CHROOT_SNAPSHOT_TAG="alarm"
  export LISTS_DIR="${LISTS_DIR:-lists}"
fi

# chroot 内可选的 AUR 源码包（官方仓库里没有的包）
# 语法：<包名>|<git 仓库 URL>，多个用空格分隔。默认留空。
export ALARM_AUR_SOURCE_PKGS="${ALARM_AUR_SOURCE_PKGS:-}"

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "需要 root 权限（请用 sudo 调用本脚本）"
}
