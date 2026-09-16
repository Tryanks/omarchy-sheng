#!/usr/bin/env bash
# Read-only integration check against real ARM repository databases.
# Run on the configured tablet/rootfs; no refresh, install or upgrade occurs.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo/scripts/omarchy/package-sources.sh"
for pair in \
  ghostty=omarchy-aarch64/ghostty \
  typora=omarchy/typora \
  obsidian=omarchy-aarch64/obsidian-appimage \
  dotnet-runtime=omarchy-aarch64/dotnet-runtime-bin; do
  requested=${pair%%=*}
  expected=${pair#*=}
  actual=$(omarchy_sheng_resolve_install_target "$requested")
  [[ $actual == "$expected" ]] || {
    printf 'FAIL: %s resolved to %s, expected %s\n' "$requested" "$actual" "$expected" >&2
    exit 1
  }
  echo "PASS: $requested -> $actual"
done
if omarchy_sheng_resolve_install_target sheng-regression-nonexistent-package >/dev/null 2>&1; then
  echo 'FAIL: nonexistent package resolved' >&2
  exit 1
fi
mapfile -t args < <(omarchy_sheng_upgrade_args)
selection=$(pacman -Sup --noconfirm --print-format '%r/%n' "${args[@]}")
while read -r target; do
  grep -qxF "$target" <<< "$selection" || { echo "FAIL: upgrade omitted $target" >&2; exit 1; }
  name=${target#*/}
  if grep -xF "omarchy-aarch64/$name" <<< "$selection"; then
    echo "FAIL: upgrade selected supplement for $name" >&2
    exit 1
  fi
done < <(omarchy_sheng_targets)
echo 'PASS: complete upgrade preserves official desktop and graphics sources'
