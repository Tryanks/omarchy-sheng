#!/usr/bin/env bash
# 21-build-pkg.sh —— 在 ALARM chroot 里用 makepkg 构建本仓库的一个（或多个）包
#
# 用法: sudo scripts/host/21-build-pkg.sh <包目录名> [<包目录名> ...]
#   包目录名 = packages/<名字>/；对 linux-xiaomi-sheng 这类含子目录的包，
#   直接传相对路径，例如 linux-xiaomi-sheng/custom。
#   要一次构建 packages/ 下全部包，使用 --all（按目录名遍历，不写死包名列表）。
#
#   **不要**在命令行里写通配符（packages/*/）—— 脚本会拒绝含 * ? [ 的入参，
#   因为 GitHub Actions 里 `sudo bash script.sh packages/*/` 的通配符不会展开。
#
# 为什么必须保留 packages/ 的相对结构：
#   各 PKGBUILD 通过 $startdir 引用同级/上级文件：
#     $startdir/payload/...                      （alsa/sensors/devauth 的载荷）
#     $startdir/../_shared/deb2pkg.sh            （deb → pacman 载荷转换库）
#     $startdir/../../patches/...                （fastrpc / libssc 的补丁与 unit）
#   因此这里把整个 packages/ 拷进 chroot 的 /build/packages/，
#   再在 /build/packages/<包目录名> 里执行 makepkg。
#
# 为什么要 su 成 builder：
#   makepkg 拒绝以 root 运行（PKGBUILD 的构建脚本会被执行）。builder 用户由
#   scripts/host/20-alarm-chroot.sh 创建，并在 /etc/sudoers.d 里给了 NOPASSWD sudo，
#   因此 makepkg 的「安装依赖」步骤也能工作。makepkg 内部会自动调用 fakeroot
#   （base-devel 已包含 fakeroot），不需要手工再包一层。
#
# 环境变量：
#   ALARM_CHROOT   构建 chroot（默认 /mnt/alarm）
#   PKGS_OUT       构建产物回拷贝目录（默认 <仓库根>/pkgs）
#   BUILD_DIR      chroot 内的构建根（默认 /build）
#   BUILDER_USER   构建用户（默认 builder）
#   PKG_PREINSTALL 空格分隔的 .pkg.tar.zst 列表，先装进 chroot 再构建
#                  （用于包间依赖，例如 iio-sensor-proxy 需要本仓库构建的 libssc）
#   LOCAL_SOURCES_DIR  宿主目录，其中的文件会被拷进 chroot 的 $BUILD_DIR/pkgs，
#                  供 PKGBUILD 的 source=("<pkgname>.deb") 取用（**不**执行 pacman -U）。
#                  6 个 xiaomi-* 重打包包与 prebuilt 内核包都靠它提供载荷，
#                  文件名必须与 source=() 中一致（即 <pkgname>.deb）
#   MAKEPKG_ENV    makepkg 之前 export 的额外变量，例如 SHENG_DEVAUTH_REPO=...
#   KEEP_BUILD     true 时保留 chroot 内的 src/pkg 目录，便于排查失败
#   ALARM_SKIP_PKGS  --all 模式下要跳过的包目录名（空格分隔）。默认
#                  `firmware-xiaomi-sheng`：它的本地载荷必须先由
#                  scripts/stage-firmware.sh 生成，--all 模式下无法完成，
#                  跳过以免整个汇总作业失败（正经构建走 package-firmware 作业）
#
# 产出: $PKGS_OUT/<pkgname>-<pkgver>-<pkgrel>-aarch64.pkg.tar.zst
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"
# shellcheck source=alarm-lib.sh
source "$HERE/alarm-lib.sh"
require_root

REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ALARM_CHROOT="${ALARM_CHROOT:-/mnt/alarm}"
PKGS_OUT="${PKGS_OUT:-$REPO_ROOT/pkgs}"
BUILD_DIR="${BUILD_DIR:-/build}"
BUILDER_USER="${BUILDER_USER:-builder}"
PKG_PREINSTALL="${PKG_PREINSTALL:-}"
LOCAL_SOURCES_DIR="${LOCAL_SOURCES_DIR:-}"
MAKEPKG_ENV="${MAKEPKG_ENV:-}"
KEEP_BUILD="${KEEP_BUILD:-false}"
ALARM_SKIP_PKGS="${ALARM_SKIP_PKGS:-firmware-xiaomi-sheng}"

[[ "$#" -gt 0 ]] || die "用法: $0 <包目录名> [...] 或 $0 --all"
[[ -x "$ALARM_CHROOT/usr/bin/pacman" ]] || die "构建 chroot 未就绪: $ALARM_CHROOT（先运行 scripts/host/20-alarm-chroot.sh）"

# ---------------------------------------------------------------------------
# 0) 挂虚拟文件系统（必须自己挂！）
#   20-alarm-chroot.sh 在"打包缓存快照前"会卸载 /proc /sys /dev（否则宿主内容会被打进快照），
#   因此本脚本拿到的 chroot 是干净的。而 makepkg/fakeroot 需要 /proc，且 ALARM tarball
#   自带的 /dev 对非 root 不可用 —— 实测症状是 makepkg 里 `> /dev/null` 报 Permission denied，
#   最终以 `ERROR: Failed to create the directory $BUILDDIR` 失败。详见 alarm-lib.sh。
# ---------------------------------------------------------------------------
alarm_mount_virtfs "$ALARM_CHROOT"

# ---------------------------------------------------------------------------
# 1) 解析要构建的包目录
# ---------------------------------------------------------------------------
PKG_SUBDIRS=()
if [[ "${1:-}" == "--all" ]]; then
  while IFS= read -r d; do
    name="${d%/}"; name="${name##*/}"
    # 跳过必须先 stage 载荷的包（见头部的 ALARM_SKIP_PKGS 说明），否则 makepkg
    # 会因为 source=() 里的本地文件不存在而失败
    skip=0
    for s in $ALARM_SKIP_PKGS; do
      [[ "$name" == "$s" ]] && skip=1
    done
    if [[ "$skip" -eq 1 ]]; then
      warn "--all：跳过 $name（需要先 stage 载荷，见 .github/workflows/_packages.yml 的 package-firmware 作业）"
      continue
    fi
    PKG_SUBDIRS+=("${d#"$REPO_ROOT/packages/"}")
  done < <(alarm_list_pkg_dirs "$REPO_ROOT/packages")
else
  for arg in "$@"; do
    # 拒绝通配符：CI 里 `packages/*/` 不会被展开成真实目录名
    case "$arg" in
      *'*'*|*'?'*|*'['*) die "入参含通配符（$arg）：请传真实目录名，或用 --all" ;;
    esac
    PKG_SUBDIRS+=("${arg%/}")
  done
fi
[[ "${#PKG_SUBDIRS[@]}" -gt 0 ]] || die "没有解析到任何包目录（packages/ 下没有 PKGBUILD？）"

for sub in "${PKG_SUBDIRS[@]}"; do
  case "$sub" in
    /*|..|../*|*/../*) die "非法的包目录名: $sub" ;;
  esac
  [[ -f "$REPO_ROOT/packages/$sub/PKGBUILD" ]] || die "找不到 PKGBUILD: packages/$sub/PKGBUILD"
done

log "待构建（${#PKG_SUBDIRS[@]} 个）: ${PKG_SUBDIRS[*]}"

# ---------------------------------------------------------------------------
# 2) 把整个 packages/ 与待预装的包拷进 chroot（保留相对结构）
# ---------------------------------------------------------------------------
install -d "$PKGS_OUT"
install -d "$ALARM_CHROOT$BUILD_DIR/packages"

log "同步 packages/ → $ALARM_CHROOT$BUILD_DIR/packages"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$REPO_ROOT/packages/" "$ALARM_CHROOT$BUILD_DIR/packages/"
else
  # 没有 rsync 时（Ubuntu runner 默认没有）：整棵重建，避免残留上一轮中间产物
  rm -rf "${ALARM_CHROOT:?}${BUILD_DIR:?}/packages"
  install -d "$ALARM_CHROOT$BUILD_DIR/packages"
  cp -a "$REPO_ROOT/packages/." "$ALARM_CHROOT$BUILD_DIR/packages/"
fi
chmod -R a+rX "$ALARM_CHROOT$BUILD_DIR/packages"

# patches/ 也必须进 chroot：PKGBUILD 里用的是 `$startdir/../../patches/...`
# （在 $startdir=/build/packages/<pkg> 时解析为 /build/patches/...），
# 只拷 packages/ 会导致 fastrpc / libssc 的 package()/prepare() 报
# "No such file or directory"（实测踩过）。
install -d "$ALARM_CHROOT$BUILD_DIR/patches"
cp -a "$REPO_ROOT/patches/." "$ALARM_CHROOT$BUILD_DIR/patches/"
chmod -R a+rX "$ALARM_CHROOT$BUILD_DIR/patches"
log "同步 patches/ → $ALARM_CHROOT$BUILD_DIR/patches"

install -d "$ALARM_CHROOT$BUILD_DIR/pkgs"

# ---------------------------------------------------------------------------
# 2.6) 强制 makepkg 的产物目录
#   实测：ALARM 的 makepkg.conf 把 PKGDEST 指到 $startdir 之外，构建明明成功
#   （`==> Finished making: ...`）却在 $startdir 与 /build 下都找不到 .pkg.tar.zst。
#   与其猜它在哪，不如追加一条 PKGDEST 到 makepkg.conf 末尾（后赋值覆盖前面的），
#   把产物统一到 $BUILD_DIR/pkgs-out，收集逻辑就有了确定位置。
# ---------------------------------------------------------------------------
MAKEPKG_PKGDEST="$BUILD_DIR/pkgs-out"
install -d -m 777 "$ALARM_CHROOT$MAKEPKG_PKGDEST"
if ! grep -qE "^[[:space:]]*PKGDEST=$MAKEPKG_PKGDEST" "$ALARM_CHROOT/etc/makepkg.conf" 2>/dev/null; then
  printf '\n# archlinux-sheng：统一产物目录（构建脚本按此路径收集 .pkg.tar.zst）\nPKGDEST=%s\n' \
    "$MAKEPKG_PKGDEST" >> "$ALARM_CHROOT/etc/makepkg.conf"
  log "已设置 makepkg PKGDEST=$MAKEPKG_PKGDEST（chroot 内）"
fi
if [[ -n "$PKG_PREINSTALL" ]]; then
  log "预装包间依赖到 chroot: $PKG_PREINSTALL"
  for f in $PKG_PREINSTALL; do
    if [[ -f "$f" ]]; then
      cp -f "$f" "$ALARM_CHROOT$BUILD_DIR/pkgs/"
    else
      warn "预装包不存在，忽略: $f"
    fi
  done
  if compgen -G "$ALARM_CHROOT$BUILD_DIR/pkgs/*.pkg.tar.zst" >/dev/null 2>&1; then
    alarm_chroot_run "$ALARM_CHROOT" bash -c "pacman -U --noconfirm $BUILD_DIR/pkgs/*.pkg.tar.zst" \
      || die "预装依赖包失败（检查包间依赖是否已构建）"
  fi
fi

# ---------------------------------------------------------------------------
# 2.5) 本地载荷入 chroot（不安装，只供 PKGBUILD 的 source=() 取用）
#   6 个 xiaomi-* 重打包包与 prebuilt 内核包都声明了 source=("<pkgname>.deb")，
#   由第 4 步的 relocate_local_sources 从 $BUILD_DIR/pkgs 拷进各自 $startdir。
# ---------------------------------------------------------------------------
if [[ -n "$LOCAL_SOURCES_DIR" ]]; then
  [[ -d "$LOCAL_SOURCES_DIR" ]] || die "LOCAL_SOURCES_DIR 不存在: $LOCAL_SOURCES_DIR"
  log "同步本地载荷 → $BUILD_DIR/pkgs: $LOCAL_SOURCES_DIR"
  cp -f "$LOCAL_SOURCES_DIR"/* "$ALARM_CHROOT$BUILD_DIR/pkgs/" 2>/dev/null || true
  ls -1 "$ALARM_CHROOT$BUILD_DIR/pkgs" 2>/dev/null | sed 's/^/    /' || true
fi

# ---------------------------------------------------------------------------
# 3) makepkg 之前的环境准备
# ---------------------------------------------------------------------------
PKGBUILD_ENV=""
if [[ -n "$MAKEPKG_ENV" ]]; then
  # workflow 传入 `VAR=value VAR2=value2` 形式，直接拼进 su 的命令串
  PKGBUILD_ENV="export ${MAKEPKG_ENV}; "
  log "额外构建环境变量: $MAKEPKG_ENV"
fi

# 打印 /build 目录结构，便于排查 shellcheck/glob 之类的 YAML 误用
log "chroot 内 /build 结构（前 2 层）:"
find "$ALARM_CHROOT$BUILD_DIR" -maxdepth 2 -mindepth 1 | sed "s|$ALARM_CHROOT|    |" | head -n 40 || true

# ---------------------------------------------------------------------------
# 4) 本地载荷就位（PKGBUILD 的 source=() 里形如 <pkgname>.deb 的本地文件）
#    workflow 下载的 deb 放在 chroot 的 $BUILD_DIR/pkgs，而 PKGBUILD 期望它在
#    $startdir（makepkg 的 SRCDEST 默认等于 $startdir），因此这里把同名文件
#    拷进 $startdir，让 prebuilt 内核 / xiaomi-* 重打包包不需要人工改名步骤。
#    source=() 的解析由 alarm-lib.sh 的 pkgbuild_local_sources 提供。
# ---------------------------------------------------------------------------
relocate_local_sources() {
  local startdir="$1" host_dir="$ALARM_CHROOT$1" line base cand
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # 只处理本地文件（跳过 URL / git+ / 带 `::` 改名的条目）
    case "$line" in
      *'://'*|git+*|*::*) continue ;;
    esac
    [[ -f "$host_dir/$line" ]] && continue
    base="${line##*/}"
    for cand in "$ALARM_CHROOT$BUILD_DIR/pkgs/$line" "$ALARM_CHROOT$BUILD_DIR/pkgs/$base"; do
      if [[ -f "$cand" ]]; then
        cp -f "$cand" "$host_dir/$line"
        log "    本地载荷就位: $line ← ${cand#"$ALARM_CHROOT"}"
        break
      fi
    done
  done < <(pkgbuild_local_sources "$host_dir/PKGBUILD")
}

# ---------------------------------------------------------------------------
# 5) 逐包构建
# ---------------------------------------------------------------------------
BUILT=()
for sub in "${PKG_SUBDIRS[@]}"; do
  startdir="$BUILD_DIR/packages/$sub"
  log "构建 packages/$sub"

  # 清掉上一轮产物，保证后面"本次构建产出了什么"的判据成立。
  # 注意：清理范围是**整棵构建树**而不是只看 $startdir —— 实测 ALARM 的 makepkg.conf
  # 并不把包放在 $startdir（PKGDEST 指向别处），所以判据不能假设位置。
  rm -rf "${ALARM_CHROOT:?}${startdir}/src" "${ALARM_CHROOT:?}${startdir}/pkg" 2>/dev/null || true
  find "$ALARM_CHROOT$BUILD_DIR" -maxdepth 5 -name '*.pkg.tar.zst' -delete 2>/dev/null || true

  alarm_chroot_run "$ALARM_CHROOT" chown -R "${BUILDER_USER}:${BUILDER_USER}" "$startdir" \
    || die "chown $startdir 失败"

  relocate_local_sources "$startdir"

  # makepkg 以 builder 身份执行；PKGBUILD 的 arch=('aarch64') 与 chroot 架构一致
  # -s：让 makepkg 用 sudo 自动安装缺失的 depends/makedepends
  #     （builder 在 /etc/sudoers.d 里有 NOPASSWD，20-alarm-chroot.sh 已配置）。
  #     缺了 -s 的话 meson/ninja/autoconf/protobuf 这类构建依赖不会被装上，构建必失败。
  alarm_chroot_run "$ALARM_CHROOT" su - "$BUILDER_USER" -c \
    "${PKGBUILD_ENV}cd '$startdir' && makepkg -sf --noconfirm --nocolor" \
    || die "makepkg 构建失败: packages/$sub"

  # 收集产物：优先从我们强制的 PKGDEST 取；同时在整个 chroot 里兜底搜索
  # （排除挂载点），并打印实际位置便于诊断。
  produced=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && produced+=("$f")
  done < <(find "$ALARM_CHROOT$MAKEPKG_PKGDEST" -maxdepth 2 -name '*.pkg.tar.zst' 2>/dev/null || true)

  if [[ "${#produced[@]}" -eq 0 ]]; then
    warn "在 $MAKEPKG_PKGDEST 没找到产物，改为全 chroot 搜索"
    while IFS= read -r f; do
      [[ -n "$f" ]] && produced+=("$f")
    done < <(find "$ALARM_CHROOT" -xdev -name '*.pkg.tar.zst' \
               -not -path "$ALARM_CHROOT/proc/*" -not -path "$ALARM_CHROOT/sys/*" \
               -not -path "$ALARM_CHROOT/dev/*" 2>/dev/null || true)
  fi

  [[ "${#produced[@]}" -gt 0 ]] || die "packages/$sub 构建后没有产出 *.pkg.tar.zst（PKGDEST=$MAKEPKG_PKGDEST，且全 chroot 搜索为空）"

  for f in "${produced[@]}"; do
    cp -f "$f" "$PKGS_OUT/"
    BUILT+=("$(basename "$f")")
    log "    → $(basename "$f")   (来自 ${f#"$ALARM_CHROOT"})"
    rm -f "$f"
  done
done

log "构建完成（${#BUILT[@]} 个产物）："
ls -lh "$PKGS_OUT" | sed 's/^/    /'

# 卸载虚拟文件系统（保持与 20-alarm-chroot.sh 一致的状态；
# 后续的"保存 chroot 快照"步骤本身也会再卸载一次，幂等）
alarm_umount_virtfs "$ALARM_CHROOT"
