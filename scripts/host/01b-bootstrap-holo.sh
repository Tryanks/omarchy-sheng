#!/usr/bin/env bash
# 01b-bootstrap-holo.sh —— 往已挂载的镜像里铺 Holo Core（Steam Frame 的 Arch aarch64 预览）底座
#
# 与 01-bootstrap-arch.sh（ALARM 路径）的差异：
#   * 底包不是滚动 tarball，而是 Valve/Collabora 发布的 system.rootfs.zst 快照
#     （内容冻结在 Arch 的 2025-11 状态，glibc 2.42）
#   * 仓库不是 ALARM 的 core/extra/alarm，而是 holo-packages 的 core/extra，
#     **SigLevel = Optional**（包未强制签名），因此不做 pacman-key init/populate
#   * 底座里已经有 base + base-devel（140 个包），10-base.sh 只需补差额
#
# 环境变量（默认值见 scripts/common/distro-env.sh）：
#   HOLO_SNAPSHOT / HOLO_BASE_URL / HOLO_ROOTFS_URL / HOLO_MIRROR
#
# 用法: sudo scripts/host/01b-bootstrap-holo.sh [挂载点]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
# shellcheck source=alarm-lib.sh
source "$HERE/alarm-lib.sh"
# shellcheck source=holo-lib.sh
source "$HERE/holo-lib.sh"
require_root

[[ "$ROOTFS_BASE" == "holo-core" ]] || die "本脚本只在 ROOTFS_BASE=holo-core 时使用（当前: $ROOTFS_BASE）"

MOUNT="${1:-/mnt/rootfs}"
[[ -d "$MOUNT" ]] || die "挂载点不存在: $MOUNT"

# ---------------------------------------------------------------------------
# 1) 取 Holo Core rootfs（快照固定，可用 HOLO_SNAPSHOT 覆盖）
# ---------------------------------------------------------------------------
_HOLO_TMP="$(mktemp -d)"
trap 'rm -rf "$_HOLO_TMP"' EXIT
HOLO_ROOTFS_PATH="${HOLO_ROOTFS_PATH:-$_HOLO_TMP/system.rootfs.zst}"
holo_fetch_rootfs "$HOLO_ROOTFS_PATH"

# ---------------------------------------------------------------------------
# 2) 解包到挂载点（tar --zstd；需要宿主安装 zstd）
# ---------------------------------------------------------------------------
log "解包 Holo Core rootfs（$HOLO_SNAPSHOT）到 $MOUNT"
holo_extract_rootfs "$HOLO_ROOTFS_PATH" "$MOUNT"

# 底座里没有 /dev /proc /sys /run /tmp 等目录，先补齐（挂载 virtfs 与 systemd 都要用）
holo_ensure_base_dirs "$MOUNT"

# ---------------------------------------------------------------------------
# 3) 仓库配置（core + extra，SigLevel=Optional）
# ---------------------------------------------------------------------------
holo_write_repo_config "$MOUNT"

# ---------------------------------------------------------------------------
# 4) DNS + 让 pacman 能在 chroot 里工作（mtab 软链 / 下载沙箱；CheckSpace 保留）
# ---------------------------------------------------------------------------
chroot_write_dns "$MOUNT"
alarm_tune_pacman_for_chroot "$MOUNT"

# ---------------------------------------------------------------------------
# 5) 同步数据库（无需密钥环：SigLevel = Optional）
# ---------------------------------------------------------------------------
log "同步包数据库（pacman -Sy）"
alarm_chroot_run "$MOUNT" pacman -Sy --noconfirm || die "pacman -Sy 失败（检查 Holo Core 源是否可达）"

# 记录底座版本，便于日志里核对（os-release 由 Holo Core 提供）
log "引导完成：Holo Core $HOLO_SNAPSHOT（ROOTFS_BASE=$ROOTFS_BASE）"
sed 's/^/    /' "$MOUNT/etc/os-release" 2>/dev/null || true
