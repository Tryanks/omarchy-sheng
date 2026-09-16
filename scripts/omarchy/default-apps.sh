#!/usr/bin/env bash
# Follow the installed upstream release's default apps, not a curated desktop.
# Only missing ARM binaries and device-inapplicable components are omitted.
set -euo pipefail
source /usr/local/lib/omarchy-sheng/package-sources.sh
install -d /etc/omarchy-sheng /var/lib/omarchy-sheng
report=/var/lib/omarchy-sheng/omitted-packages.txt
: > "$report"
declare -A selected=()
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
  elif target=$(omarchy_sheng_resolve_install_target "$package" 2>/dev/null); then
    targets+=("$target")
    [[ $target != omarchy/* ]] || echo "$target" >> "$extra_targets"
  else
    printf '%s: no binary target in configured ARM repositories\n' "$package" >> "$report"
  fi
done < /usr/share/omarchy/install/omarchy-base.packages
mapfile -t core_args < <(omarchy_sheng_upgrade_args)
env OMARCHY_UPDATE_PACMAN=1 pacman -Su --needed --noconfirm "${core_args[@]}" "${targets[@]}"
# --needed can leave a previously installed dependency marked as a dependency.
# These are default applications, so removing a former desktop must retain them.
names=()
for target in "${targets[@]}"; do names+=("${target#*/}"); done
(( ${#names[@]} == 0 )) || pacman -D --asexplicit "${names[@]}"
install -m644 "$extra_targets" /etc/omarchy-sheng/extra-targets.list
cat "$report"
