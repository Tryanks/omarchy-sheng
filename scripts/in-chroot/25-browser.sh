#!/usr/bin/env bash
# 25-browser.sh —— 可选：安装浏览器
#
# 对应 ubuntu-sheng 的 25-browser.sh，但 Arch 侧简单得多：
#   * Arch 官方仓库里的 firefox 就是普通的 pacman 包（没有 snap 过渡包问题），
#     直接 pacman -S 即可，不需要 Mozilla 官方 apt 源 + pin 优先级那一套
#   * browser 默认值因此从 none 改为 firefox（见 .github/workflows/rootfs.yml）
#
# 环境变量：
#   BROWSER  none / firefox
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/25-browser.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-pac.sh"

BROWSER="${BROWSER:-none}"

case "$BROWSER" in
  none|"")
    log "BROWSER=none：不安装浏览器"
    exit 0
    ;;
  firefox) ;;
  *) die "未知的 BROWSER: $BROWSER（可选 none / firefox）" ;;
esac

log "安装 Firefox（Arch 官方仓库）"
# 与其它阶段一致：先 -Syu 对齐（Arch 的 firefox 依赖较多，避免部分升级）
if [[ ${DESKTOP:-} == Omarchy ]]; then
  source /usr/local/lib/omarchy-sheng/package-sources.sh
  mapfile -t targets < <(omarchy_sheng_upgrade_args)
  env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --noconfirm --needed --color never "${targets[@]}"
else
  pacman -Syu --noconfirm --needed --color never
fi
pac_install firefox

log "Firefox 安装完成: $(pac_version firefox)"
