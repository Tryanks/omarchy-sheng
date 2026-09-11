#!/usr/bin/env bash
# 10-fetch-kernel.sh —— prebuilt 内核：从 ianchb/sm8550-mainline 最新 release
# 下载 boot.img（按 boot mode / quiet boot 选不同变体）与 linux-xiaomi-sheng deb
#
# 与 ubuntu-sheng 的 10-fetch-kernel.sh 完全一致：上游 release 产物就是
# boot_sheng_*.img + linux-xiaomi-sheng*.deb，与发行版无关；deb 随后由
# packages/linux-xiaomi-sheng/prebuilt/PKGBUILD 原生化重打包为 pacman 包
# （见 scripts/host/21-build-pkg.sh 与 README 的「原生化重打包方案」）。
#
# 环境变量：
#   BOOT_IMG_PATTERN  例如 boot_sheng_dualboot_plymouth.img
#   KERNEL_RELEASES_REPO  默认 ianchb/sm8550-mainline
#   GH_TOKEN          GitHub Actions 自动注入
#
# 产出: boot.img、debs/<内核 deb>
#
# 用法: scripts/host/10-fetch-kernel.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/distro-env.sh
source "$HERE/../common/distro-env.sh"

REPO="${KERNEL_RELEASES_REPO:-ianchb/sm8550-mainline}"
PATTERN="${BOOT_IMG_PATTERN:?需要 BOOT_IMG_PATTERN（见 workflow 的 boot mode 解析）}"

mkdir -p debs

TAG="$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName')"
[[ -n "$TAG" ]] || die "无法获取 $REPO 的 release tag"

log "使用 $REPO 的 release: $TAG"
gh release download "$TAG" --repo "$REPO" \
  --pattern "$PATTERN" \
  --pattern 'linux-xiaomi-sheng*.deb' \
  --clobber --dir debs

[[ -f "debs/$PATTERN" ]] || die "未下载到 boot 镜像: $PATTERN（该 release 里可能没有这个变体）"
mv "debs/$PATTERN" boot.img

log "boot.img 就绪: $(du -h boot.img | cut -f1)"
ls -1 debs | sed 's/^/    /'
