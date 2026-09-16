#!/usr/bin/env bash
# holo-lib.sh —— 宿主侧 Holo Core（Valve/Collabora 的 Steam Frame Arch aarch64 底）公共库
#
# 被以下脚本 source：
#   * host/01b-bootstrap-holo.sh   —— 往镜像里铺 Holo Core 底座
#   * host/20-alarm-chroot.sh      —— ROOTFS_BASE=holo-core 时准备构建 chroot
#
# 底包形态（实测）：system.rootfs.zst 是 zstd 压缩的 tar，解包后约 1.2 GB，
# 已安装包只有 140 个（base + base-devel + git/sudo/dracut/cryptsetup/e2fsprogs/kmod），
# **没有**内核镜像、DTB、initramfs、桌面与显示管理器 —— 内核与设备侧东西由本仓库提供。
#
# 本文件不定义 set -euo pipefail（由调用方设置），也不注册 trap。
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# 下载 Holo Core rootfs（已存在且非空则跳过，便于缓存复用）
#   用法: holo_fetch_rootfs <目标路径>
# ---------------------------------------------------------------------------
holo_fetch_rootfs() {
  local dest="${1:?用法: holo_fetch_rootfs <目标路径>}"
  install -d "$(dirname "$dest")"

  if [[ -s "$dest" ]]; then
    log "复用已下载的 Holo Core rootfs: $dest ($(du -h "$dest" | cut -f1))"
    return 0
  fi

  log "下载 Holo Core rootfs: $HOLO_ROOTFS_URL"
  if ! curl -fL --retry 3 --retry-delay 5 --connect-timeout 20 -o "$dest.part" "$HOLO_ROOTFS_URL"; then
    rm -f "$dest.part"
    die "无法下载 Holo Core rootfs（$HOLO_ROOTFS_URL）"
  fi
  mv -f "$dest.part" "$dest"

  # 健全性校验：确认是 zstd 归档，避免把 HTML 错误页当 rootfs 解包
  if ! zstd -t "$dest" >/dev/null 2>&1; then
    rm -f "$dest"
    die "下载到的文件不是有效的 zstd 归档: $dest（检查快照名 $HOLO_SNAPSHOT 是否存在）"
  fi
  log "已下载 Holo Core rootfs: $dest ($(du -h "$dest" | cut -f1))"
}

# ---------------------------------------------------------------------------
# 解包 Holo Core rootfs 到目标目录（需要 zstd；bsdtar/GNU tar 都支持 --zstd）
#   用法: holo_extract_rootfs <归档> <目标目录>
# ---------------------------------------------------------------------------
holo_extract_rootfs() {
  local archive="${1:?用法: holo_extract_rootfs <归档> <目标目录>}"
  local dest="${2:?用法: holo_extract_rootfs <归档> <目标目录>}"
  install -d "$dest"
  if ! tar --zstd -xpf "$archive" -C "$dest"; then
    die "解包 Holo Core rootfs 失败（宿主是否安装了 zstd？）"
  fi
  [[ -x "$dest/usr/bin/pacman" ]] || die "解包后找不到 $dest/usr/bin/pacman，rootfs 可能不完整"
}

# ---------------------------------------------------------------------------
# 写入 holo 仓库配置（core / extra，SigLevel = Optional）
#   holo 的包**没有做签名强校验**（官方给的 pacman.conf 就是 SigLevel = Optional），
#   因此不初始化密钥环；这里显式记录这一点，便于日后审计。
#   用法: holo_write_repo_config <root>
# ---------------------------------------------------------------------------
holo_write_repo_config() {
  local root="${1:?用法: holo_write_repo_config <root>}"
  install -d "$root/etc/pacman.d"

  cat > "$root/etc/pacman.d/mirrorlist" <<EOF
# archlinux-sheng：由 scripts/host/holo-lib.sh 生成（Holo Core ${HOLO_SNAPSHOT}）
Server = ${HOLO_MIRROR}/\$repo/os/\$arch
EOF

  # 用官方给的仓库集合覆盖：holo 只有 core 与 extra（没有 [alarm]/[community]）
  cat > "$root/etc/pacman.conf" <<'EOF'
# archlinux-sheng：Holo Core（Valve/Collabora 的 Arch Linux aarch64 预览）
# 上游给出的配置就是 SigLevel = Optional（包未强制签名），这里保持一致。
[options]
HoldPkg = pacman glibc
Architecture = aarch64
Color
CheckSpace
ParallelDownloads = 5
SigLevel = Optional TrustAll
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

  log "已写入 Holo Core 仓库配置（mirror=${HOLO_MIRROR}，core + extra，SigLevel=Optional）"
}

# ---------------------------------------------------------------------------
# 把宿主 DNS 写进 chroot/镜像（两种底共用；resolv.conf 可能是悬空软链，先删）
#   用法: chroot_write_dns <root>
# ---------------------------------------------------------------------------
chroot_write_dns() {
  local root="${1:?用法: chroot_write_dns <root>}"
  rm -f "$root/etc/resolv.conf"
  if [[ -r /etc/resolv.conf ]] && ! grep -qE '^[[:space:]]*nameserver[[:space:]]+127\.0\.0\.53' /etc/resolv.conf; then
    install -m644 /etc/resolv.conf "$root/etc/resolv.conf"
  else
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$root/etc/resolv.conf"
  fi
  log "chroot resolv.conf: $(tr '\n' ' ' < "$root/etc/resolv.conf")"
}
