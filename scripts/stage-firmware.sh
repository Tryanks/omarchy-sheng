#!/usr/bin/env bash
# stage-firmware.sh —— 把 ianchb/sheng-firmware（或自定义 repo/branch）的内容
# 打包成 firmware-xiaomi-sheng 的 PKGBUILD 载荷，让 makepkg 全程离线
#
# 用法: scripts/stage-firmware.sh <firmware_repo_url> <branch> <packages/firmware-xiaomi-sheng 目录>
set -euo pipefail

REPO="${1:?需要 firmware 仓库 URL}"
BRANCH="${2:-master}"
DEST="${3:?需要 firmware-xiaomi-sheng 包目录}"

[[ -d "$DEST" ]] || { echo "[stage-firmware] 目标目录不存在: $DEST" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[stage-firmware] 克隆 $REPO ($BRANCH)"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMP/src" >/dev/null 2>&1
rm -rf "$TMP/src/.git" "$TMP/src/.github"

# 上游仓库根本没有 .git 之外的东西可排除；用 --zstd 保持体积可控
tar -c --zstd -f "$DEST/sheng-firmware.tar.zst" -C "$TMP/src" .

SIZE="$(du -h "$DEST/sheng-firmware.tar.zst" | cut -f1)"
echo "[stage-firmware] 完成: $DEST/sheng-firmware.tar.zst ($SIZE)"
ls -1 "$TMP/src" | sed 's/^/    /'
