#!/usr/bin/env bash
# 公共环境：Arch Linux ARM（ALARM）常量 + 日志工具
# 被 host/ 与 in-chroot/ 下的脚本共同 source。
#
# 与 ubuntu-sheng 的差异：Arch 是滚动发行版，没有「版本 ↔ suite 代号」映射，
# 因此这里不再有 DISTRO_SERIES / DISTRO_SUITE，改为集中维护 ALARM 的
# tarball 地址、镜像地址与架构常量，避免散落在 workflow YAML 里。

# 镜像内由 workflow 写入的构建参数（/root/build.env）；宿主阶段不存在该文件
if [[ -f /root/build.env ]]; then
  set -a
  # shellcheck source=/dev/null
  . /root/build.env
  set +a
fi

# ---------------------------------------------------------------------------
# Arch Linux ARM 常量
# ---------------------------------------------------------------------------
export ARCH="${ARCH:-aarch64}"

# 官方 aarch64 rootfs tarball（滚动更新，无版本号）
export ALARM_TARBALL_URL="${ALARM_TARBALL_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}"

# 包镜像：Server = $ALARM_MIRROR/$arch/$repo（写入镜像内 /etc/pacman.d/mirrorlist）
# 中国大陆可换用 https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm 等镜像
export ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"

# 宿主上可复用的 ALARM 构建 chroot（供 makepkg 使用，见 host/20-alarm-chroot.sh）
export ALARM_CHROOT="${ALARM_CHROOT:-/mnt/alarm}"

# chroot 内可选的 AUR 源码包（ALARM 的 core/extra/alarm 里没有的包）
# 语法：<包名>|<git 仓库 URL>，多个用空格分隔。
#   * 默认留空 —— 目前 10 个设备包的 makedepends 全部能从 ALARM 官方仓库满足
#   * 若将来某个依赖只存在于 AUR，在 workflow 里设置本变量即可（见 20-alarm-chroot.sh 的 *_aur_source）
export ALARM_AUR_SOURCE_PKGS="${ALARM_AUR_SOURCE_PKGS:-}"

log()  { printf '[%s] %s\n' "${0##*/}" "$*"; }
warn() { printf '[%s] 警告: %s\n' "${0##*/}" "$*" >&2; }
die()  { printf '[%s] 错误: %s\n' "${0##*/}" "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "需要 root 权限（请用 sudo 调用本脚本）"
}
