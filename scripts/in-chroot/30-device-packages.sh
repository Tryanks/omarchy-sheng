#!/usr/bin/env bash
# 30-device-packages.sh —— 安装全部设备功能包（/tmp/pkgs/*.pkg.tar.zst）并做设备侧收尾
#
# 对应 ubuntu-sheng 的 30-device-packages.sh，语义一致：
#   安装本地包 → 修复可执行权限 → depmod → enable 传感器/devauth 服务。
#
# Arch 侧差异（重要）：
#   * 全部设备包都是本仓库用 makepkg 构建的原生 pacman 包（见
#     scripts/host/21-build-pkg.sh 与 packages/_shared/deb2pkg.sh），因此依赖
#     解析由 pacman 完成；依赖缺失时 pacman -U 直接失败（不会像 apt 那样
#     静默留在半配置状态）
#   * ALARM 官方仓库里已经有 libssc 0.4.4-1 与 iio-sensor-proxy 3.9-1，而本仓库
#     构建的 libssc（0.4.2，带 QRTR 等待补丁）与 iio-sensor-proxy-sheng（3.9）
#     需要取而代之。pacman 默认拒绝「降级」，因此这里先把仓库版本移出
#     （-Rdd 不删依赖），再安装本地包
#   * 包内不 enable 服务（Arch 惯例 + 上游 postinst 的 enable 未移植），
#     统一在这里 systemctl enable
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/30-device-packages.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-pac.sh"

shopt -s nullglob
pkgs=(/tmp/pkgs/*.pkg.tar.zst)
[[ "${#pkgs[@]}" -gt 0 ]] || die "/tmp/pkgs 下没有 .pkg.tar.zst"

log "待安装设备包（${#pkgs[@]} 个）："
for f in "${pkgs[@]}"; do
  # 包名/版本直接从文件名解析（makepkg 的命名规则：
  # <pkgname>-<pkgver>-<pkgrel>-<arch>.pkg.tar.zst），避免依赖 pacman -Qp 的额外开关
  base="$(basename "$f")"
  base="${base%.pkg.tar.zst}"
  printf '    %-56s\n' "$base"
done

# ---------------------------------------------------------------------------
# 1) 移除 ALARM 仓库/基础镜像里与本地包冲突的版本
#    -Rdd：不删除依赖它的包，只删自己（随后会被本地包顶上）
#    * libssc / iio-sensor-proxy：ALARM extra 里本来就有（0.4.4-1 / 3.9-1，且
#      iio-sensor-proxy 依赖 libssc）。我们需要的是带 QRTR 等待补丁的 libssc
#      与显式 -Dssc-support=enabled 的 proxy，因此换成本仓库构建的包。
#    * linux-firmware*：ALARM 的 rootfs tarball 预装了 linux-firmware 元包
#      （它把 linux-firmware-qcom 放在 optdepends，不显式装就没有 Adreno 固件）。
#      Debian 侧 firmware-xiaomi-sheng 的语义就是「替换 linux-firmware」，
#      Arch 侧同样声明了 provides/conflicts/replaces=('linux-firmware')；但 pacman
#      与元包冲突时**不会**顺带移除它的分包，而分包与本包文件路径会重叠
#      （例如 ath12k/WCN7850/hw2.0/*），会让后面的 pacman -U 因文件冲突直接失败。
#      因此这里显式移除全部 linux-firmware* 包，设备固件统一由本仓库的包提供。
#      注意：ALARM 的 stock linux-aarch64（无 sheng DTB）由 linux-xiaomi-sheng 的
#      conflicts 自动移除，无需在此处理。
# ---------------------------------------------------------------------------
for name in libssc iio-sensor-proxy; do
  if pac_installed "$name"; then
    warn "移除仓库版本的 $name（$(pac_version "$name")），改用本仓库构建的本地包"
    pacman -Rdd --noconfirm --color never "$name" || warn "移除 $name 失败（继续）"
  fi
done

mapfile -t fw_pkgs < <(pacman -Qq --color never 2>/dev/null | grep -E '^linux-firmware' || true)
if [[ "${#fw_pkgs[@]}" -gt 0 ]]; then
  warn "移除基础镜像预装的固件包（${#fw_pkgs[@]} 个）：${fw_pkgs[*]}"
  pacman -Rdd --noconfirm --color never "${fw_pkgs[@]}" \
    || warn "移除固件包失败（若随后 pacman -U 报文件冲突，请检查本步骤）"
fi

# ---------------------------------------------------------------------------
# 2) 安装本地包
# ---------------------------------------------------------------------------
log "安装中（pacman -U）"
if ! pacman -U --noconfirm --needed --color never "${pkgs[@]}"; then
  # 第一次失败通常是缺少运行期依赖（本地包相互依赖或依赖官方仓库的包）。
  # pacman -U 本身不会去仓库解析依赖，因此这里再从仓库补装一轮依赖
  # （`yes |` 是为了自动接受可选的构建依赖，避免交互等待）。
  warn "首次安装失败，尝试从官方仓库补齐依赖后重试"
  yes | pacman -S --needed --color never base-devel >/dev/null 2>&1 || true
  pacman -U --noconfirm --color never "${pkgs[@]}" || die "设备包安装失败，请检查上面的依赖错误"
fi

# ---------------------------------------------------------------------------
# 3) 权限修复：deb2pkg 的载荷搬运可能保留上游 deb 的 644 权限，
#    pacman 的 fakeroot 打包不会自动补执行位，这里显式修复
# ---------------------------------------------------------------------------
log "修复可执行权限"
for f in /usr/bin/adsprpcd /usr/libexec/iio-sensor-proxy /usr/bin/monitor-sensor /usr/bin/ssccli; do
  if [[ -e "$f" ]]; then
    chmod +x "$f"
    printf '    +x %s\n' "$f"
  else
    printf '    (跳过，不存在) %s\n' "$f"
  fi
done

# ---------------------------------------------------------------------------
# 4) depmod：让 /usr/lib/modules/<kver>/modules.dep 等索引在镜像内就生成
# ---------------------------------------------------------------------------
KVER="$(ls -1 /usr/lib/modules 2>/dev/null | head -n1 || true)"
if [[ -n "$KVER" ]]; then
  log "为内核 $KVER 生成模块依赖索引（depmod）"
  depmod -a "$KVER" || warn "depmod 失败"
  [[ -f "/usr/lib/modules/$KVER/modules.dep" ]] || warn "modules.dep 未生成，开机可能无法加载模块"
else
  warn "未找到 /usr/lib/modules/*，内核包可能没有装上"
fi

# ---------------------------------------------------------------------------
# 5) 服务启用（与上游一致；Arch 下由本步骤显式 enable）
# ---------------------------------------------------------------------------
# 拼写务必照抄：unit 文件名与二进制都是 adsprpcd（a-d-s-p-r-p-c-d），
# 上游 workflow 的 enable 步骤把它写成 adsrpcd（少一个 rp）→ 那个 unit 永远启用不了。
# 这里**写死正确文件名**并先判断存在性（不要用通配符：adsrp*cd 与真实名在第 4 个字符
# 就不同，永远匹配不上，会静默走 warn 分支）。
if [[ -f /usr/lib/systemd/system/adsprpcd-sensorspd.service ]]; then
  systemctl enable adsprpcd-sensorspd.service || warn "启用 adsprpcd-sensorspd 失败"
else
  warn "未找到 adsprpcd-sensorspd.service（fastrpc 包可能没装上）"
fi
if [[ -f /usr/lib/systemd/system/sheng-devauth.service ]]; then
  systemctl enable sheng-devauth.service || warn "启用 sheng-devauth 失败"
fi
if [[ -f /usr/lib/systemd/system/xiaomi-mipps-auth.service ]]; then
  systemctl enable xiaomi-mipps-auth.service || warn "启用 xiaomi-mipps-auth 失败"
fi
if [[ -f /usr/lib/systemd/user/xiaomi-sheng-keyboard-helper-micmute.service ]]; then
  # user unit 需要 --global 才会对所有用户生效
  systemctl --global enable xiaomi-sheng-keyboard-helper-micmute.service \
    || warn "全局启用 xiaomi-sheng-keyboard-helper-micmute（user unit）失败"
fi

log "设备包安装完成"
