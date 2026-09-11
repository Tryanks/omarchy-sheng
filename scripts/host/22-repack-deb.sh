#!/usr/bin/env bash
# 22-repack-deb.sh —— 把 6 个 xiaomi-* 设备功能包的 deb「原生化」重打包为 pacman 包
#
# 用法: sudo scripts/host/22-repack-deb.sh [deb 目录] [包目录名 ...]
#   默认 deb 目录: <仓库根>/deb-out（与 ubuntu-sheng 的 fetch-xiaomi-debs.sh 一致）
#   默认包目录名: 由 deb 文件名推导（xiaomi-mipps-auth.deb → xiaomi-mipps-auth）
#
# 与 21-build-pkg.sh 的关系：
#   6 个 xiaomi-* 包的 PKGBUILD 都写 `source=("<pkgname>.deb")`，即要求 deb 就在
#   $startdir。本脚本负责把宿主上的 deb 放到 packages/<pkg>/ 下（并按 PKGBUILD
#   期望的文件名规范化，例如上游 release 资产常带版本号后缀），然后调用
#   21-build-pkg.sh 完成 makepkg 构建。
#
# 注意：本脚本会写 packages/ 目录（只添加被 .gitignore 的 .deb 载荷），
# 不会修改任何 PKGBUILD。
#
# 环境变量：
#   ALARM_CHROOT / PKGS_OUT / BUILDER_USER  透传给 21-build-pkg.sh
#   XIAOMI_PKGS  空格分隔的包目录名列表（覆盖默认的按文件名推导）
#
# 产出: $PKGS_OUT/<pkgname>-<pkgver>-<pkgrel>-aarch64.pkg.tar.*
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
# shellcheck source=alarm-lib.sh
source "$HERE/alarm-lib.sh"
require_root

REPO_ROOT="$(cd "$HERE/../.." && pwd)"
DEB_DIR="${1:-$REPO_ROOT/deb-out}"
shift || true

XIAOMI_PKGS="${XIAOMI_PKGS:-}"
if [[ "$#" -gt 0 ]]; then
  PKG_LIST=("$@")
elif [[ -n "$XIAOMI_PKGS" ]]; then
  # shellcheck disable=SC2206
  PKG_LIST=($XIAOMI_PKGS)
else
  # 按 packages/ 目录遍历，挑出所有 source 里声明了本地 .deb 的包（不写死包名列表）
  PKG_LIST=()
  while IFS= read -r dir; do
    name="${dir%/}"; name="${name##*/}"
    case "$name" in
      xiaomi-*) PKG_LIST+=("$name") ;;
    esac
  done < <(alarm_list_pkg_dirs "$REPO_ROOT/packages")
fi
[[ "${#PKG_LIST[@]}" -gt 0 ]] || die "没有找到任何 xiaomi-* 包目录"

log "待重打包（${#PKG_LIST[@]} 个）: ${PKG_LIST[*]}"
log "deb 来源目录: $DEB_DIR"

STAGE_DIRS=()
for pkg in "${PKG_LIST[@]}"; do
  pkg_dir="$REPO_ROOT/packages/$pkg"
  pkgbuild="$pkg_dir/PKGBUILD"
  [[ -f "$pkgbuild" ]] || { warn "跳过 $pkg：缺少 PKGBUILD"; continue; }

  # PKGBUILD 期望的本地文件名（source=() 里不含 ://、不以 git+ 开头、不含 ::）
  want="$(pkgbuild_local_sources "$pkgbuild" | head -n1 || true)"
  [[ -n "$want" ]] || { warn "跳过 $pkg：PKGBUILD 里没有本地 source 条目"; continue; }

  if [[ -f "$pkg_dir/$want" ]]; then
    log "$pkg：载荷已就位（$want）"
    STAGE_DIRS+=("$pkg")
    continue
  fi

  # 在 deb 目录里找匹配的 deb：
  #   1) 完全同名
  #   2) <包名>_<版本>_arm64.deb
  #   3) <包名>-<版本>-arm64.deb
  #   4) <包名>*.deb（兜底，取第一个）
  src=""
  for cand in \
    "$DEB_DIR/$want" \
    "$DEB_DIR/${pkg}_"*"_arm64.deb" \
    "$DEB_DIR/${pkg}-"*"-arm64.deb" \
    "$DEB_DIR/$pkg"*.deb; do
    if [[ -f "$cand" ]]; then
      src="$cand"
      break
    fi
  done

  if [[ -z "$src" ]]; then
    warn "跳过 $pkg：在 $DEB_DIR 找不到 $want 或 $pkg*.deb"
    continue
  fi

  log "$pkg：$src → packages/$pkg/$want"
  cp -f "$src" "$pkg_dir/$want"
  STAGE_DIRS+=("$pkg")
done

[[ "${#STAGE_DIRS[@]}" -gt 0 ]] || die "没有任何 xiaomi-* 包可以重打包（deb 是否已下载？见 scripts/packages/fetch-xiaomi-debs.sh）"

log "开始 makepkg 重打包"
bash "$HERE/21-build-pkg.sh" "${STAGE_DIRS[@]}"

log "xiaomi-* 重打包完成"
