#!/usr/bin/env bash
# Follow the installed upstream release's default apps, not a curated desktop.
# Only missing ARM binaries and device-inapplicable components are omitted.
set -euo pipefail
source /usr/local/lib/omarchy-sheng/package-sources.sh
install -d /etc/omarchy-sheng /var/lib/omarchy-sheng
report=/var/lib/omarchy-sheng/omitted-packages.txt
: > "$report"
declare -A available=() selected=()
while read -r repo package _; do
  [[ -n ${available[$package]:-} ]] || available[$package]=$repo
done < <(pacman -Sl)
while read -r target; do selected[${target#*/}]=$target; done < <(omarchy_sheng_targets)
targets=()
extra_targets=$(mktemp)
trap 'rm -f "$extra_targets"' EXIT
if [[ -f /etc/omarchy-sheng/extra-targets.list ]]; then
  cat /etc/omarchy-sheng/extra-targets.list > "$extra_targets"
fi
while read -r package; do
  [[ -n $package && $package != \#* ]] || continue
  case "$package" in
    asdcontrol) echo 'asdcontrol: Apple display hardware only' >> "$report"; continue ;;
    kernel-modules-hook) echo 'kernel-modules-hook: kernel/boot lifecycle belongs to sheng' >> "$report"; continue ;;
    nvim) package=neovim ;;
    quickshell) package=quickshell-git ;;
  esac
  if [[ -n ${selected[$package]:-} ]]; then
    continue
  elif [[ -n ${available[$package]:-} ]]; then
    target=${available[$package]}/$package
    targets+=("$target")
    [[ ${available[$package]} != omarchy ]] || echo "$target" >> "$extra_targets"
  else
    printf '%s: no binary target in configured ARM repositories\n' "$package" >> "$report"
  fi
done < /usr/share/omarchy/install/omarchy-base.packages
mapfile -t core_args < <(omarchy_sheng_upgrade_args)
env OMARCHY_UPDATE_PACMAN=1 pacman -Su --needed --noconfirm "${core_args[@]}" "${targets[@]}"
install -m644 "$extra_targets" /etc/omarchy-sheng/extra-targets.list
cat "$report"
