#!/usr/bin/env bash
# Keep native Omarchy install commands usable with source-qualified ARM repos.
set -euo pipefail
if (( EUID != 0 )); then exec sudo /usr/local/bin/omarchy-pkg-add "$@"; fi
source /usr/local/lib/omarchy-sheng/package-sources.sh
targets=()
for package in "$@"; do
  name=${package#*/}
  if ! pacman -T "$name" >/dev/null 2>&1; then
    target=$(omarchy_sheng_resolve_install_target "$package") || exit 1
    targets+=("$target")
  fi
done
(( ${#targets[@]} == 0 )) || pacman -S --needed --noconfirm -- "${targets[@]}"
for package in "$@"; do pacman -T "${package#*/}" >/dev/null; done
# Newly installed official apps must keep receiving source-qualified updates.
if (( ${#targets[@]} )); then
  install -d /etc/omarchy-sheng
  list=/etc/omarchy-sheng/extra-targets.list
  touch "$list"
  for target in "${targets[@]}"; do
    if [[ $target == omarchy/* ]] && ! grep -qxF "$target" "$list"; then
      printf '%s\n' "$target" >> "$list"
    fi
  done
fi
