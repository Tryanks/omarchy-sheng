#!/usr/bin/env bash
# 20-desktop.sh —— 安装桌面环境（GNOME / KDE Plasma / plasma-mobile / server）
#
# 对应 ubuntu-sheng 的 20-desktop.sh。Arch 侧差异：
#   * 不需要规避 snap：Arch 官方仓库没有 snapd，firefox/chromium 都是普通包
#     （因此 archlinux-sheng 没有 15-nosnap.sh）
#   * plymouth 在 ALARM 的 extra 仓库里，同样由 lists/plymouth.list 安装；
#     plymouth-theme-breeze / kde-config-plymouth 只在 AUR，**构建里不编 AUR**，
#     这里 best-effort 跳过并在下面注释里说明（README 也记了这一限制）
#   * 显示管理器：GNOME 用 gdm（不是 Ubuntu 的 gdm3）
#
# 环境变量（由 /root/build.env 提供）：
#   DESKTOP         GNOME / KDE Plasma / server
#   PLASMA_MOBILE   true/false
#   QUIET_BOOT      true/false（true 时安装 plymouth）
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/20-desktop.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-pac.sh"

: "${DESKTOP:?需要 DESKTOP}"
PLASMA_MOBILE="${PLASMA_MOBILE:-false}"
QUIET_BOOT="${QUIET_BOOT:-false}"

# 桌面包的依赖树很深，先 -Syu 对齐一次（避免「部分升级」），再装列表
if [[ "$DESKTOP" != "Omarchy" ]]; then
  pacman -Syu --noconfirm --needed --color never
fi

# 先整批安装列表（快到快，依赖解析最完整）；任何包在 ALARM 仓库里缺失/改名时
# 会自动退回逐个安装并跳过，最终清单由 90-verify.sh 硬校验。
case "$DESKTOP" in
  Omarchy)
    [[ "$ROOTFS_BASE" == "alarm" ]] || die "Omarchy requires ALARM"
    bash "$BUILD_DIR/omarchy/install.sh"
    ;;
  GNOME)
    log "安装 GNOME"
    pac_install_list_best_effort "$BUILD_DIR/lists/gnome.list"
    ;;
  "KDE Plasma")
    if [[ "$PLASMA_MOBILE" == "true" ]]; then
      log "安装 KDE Plasma Mobile"
      pac_install_list_best_effort "$BUILD_DIR/lists/kde-mobile.list"
    else
      log "安装 KDE Plasma"
      pac_install_list_best_effort "$BUILD_DIR/lists/kde.list"
    fi
    ;;
  server)
    log "desktop=server：不安装桌面环境"
    ;;
  *)
    die "未知的 DESKTOP: $DESKTOP（可选 GNOME / KDE Plasma / server）"
    ;;
esac

# 桌面环境安装后个别包名可能已变动，这里逐个 best-effort 补齐（失败只警告，
# 关键组件由 90-verify.sh 硬校验）。音频组件（pipewire* / wireplumber）与
# 字体由 lists/*.list 与 base.list 负责，这里只做兜底。
if [[ "$DESKTOP" != "server" ]]; then
  log "补齐桌面环境常用组件（best-effort）"
  pac_install_best_effort pipewire pipewire-pulse pipewire-alsa wireplumber
fi

# plymouth：与上游同样的条件（quiet_boot 且非 server）
if [[ "$QUIET_BOOT" == "true" && "$DESKTOP" != "server" ]]; then
  log "安装 Plymouth（quiet boot）"
  # 用 best-effort：ALARM 里 `plymouth` 已核实存在，但 `plymouth-themes` / `mkinitcpio`
  # 的包名未逐一核实（Arch 的默认主题通常随 plymouth 本体一起提供）。
  # 关键项由 90-verify.sh 的「quiet_boot 时 plymouth 必须装上」硬校验兜底。
  pac_install_list_best_effort "$BUILD_DIR/lists/plymouth.list"

  if [[ "$DESKTOP" == "KDE Plasma" ]]; then
    # AUR 包，构建里不编译：ALARM 官方仓库没有 plymouth-theme-breeze /
    # kde-config-plymouth。若确实需要 breeze 主题，请改用
    #   * 官方仓库的 plymouth-themes（已由 plymouth.list 安装），或
    #   * 在设备上手动 yaay/paru -S plymouth-theme-breeze
    # 这里 best-effort 尝试一次（若你自建了带这些包的仓库，就会装上）；
    # pac_install_best_effort 内部失败只打印警告，不会中断构建。
    pac_install_best_effort plymouth-theme-breeze kde-config-plymouth
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
      if plymouth-set-default-theme --list 2>/dev/null | grep -qx breeze; then
        plymouth-set-default-theme breeze || warn "设置 breeze 主题失败"
      else
        log "未找到 breeze 主题，保留 plymouth 默认主题"
      fi
    fi
  fi
else
  log "跳过 Plymouth"
fi

log "桌面环境安装完成: $DESKTOP"
