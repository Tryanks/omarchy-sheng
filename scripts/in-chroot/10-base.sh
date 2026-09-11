#!/usr/bin/env bash
# 10-base.sh —— 在 chroot 内安装基础系统包（Arch Linux ARM）
#
# 对应 ubuntu-sheng 的 10-base.sh（那边是 apt 源 + base.list）。
# 与 Debian/Ubuntu 的差异：
#   * Arch 的「基础系统」已由 ALARM tarball 提供（systemd / pacman / glibc / bash），
#     这里只需要 -Syu 对齐一次数据库 + 安装 base.list 里补充的工具
#   * 没有 policy-rc.d 之类的 postinst 垫片（见 lib-pac.sh 顶部说明）
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/10-base.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-pac.sh"

log "刷新包数据库并全量更新（Arch 是滚动发行版，必须先 -Syu 再装包）"
pacman -Syu --noconfirm --needed --color never

log "安装基础包（scripts/lists/base.list）"
pac_install_list "$BUILD_DIR/lists/base.list"

log "基础包安装完成"
