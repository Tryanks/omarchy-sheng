#!/usr/bin/env bash
# Official Omarchy edge is explicit; the Mac ARM application repo fills gaps.
# Policy follows omacom/omarchy-mac's source-qualified graphics transactions.
omarchy_sheng_targets() {
  printf '%s\n' omarchy/omarchy omarchy/omarchy-settings omarchy/omarchy-keyring \
    omarchy/ttf-jetbrains-mono-nerd-basic omarchy/xdg-terminal-exec omarchy/hyprland \
    omarchy/hyprtoolkit omarchy/hyprland-guiutils omarchy/quickshell-git
  if [[ -f /etc/omarchy-sheng/extra-targets.list ]]; then
    local target
    while read -r target; do
      [[ -n $target ]] || continue
      if pacman -Q "${target#*/}" >/dev/null 2>&1; then printf '%s\n' "$target"; fi
    done < /etc/omarchy-sheng/extra-targets.list
  fi
}

omarchy_sheng_upgrade_args() {
  local target names=() targets=()
  mapfile -t targets < <(omarchy_sheng_targets)
  for target in "${targets[@]}"; do names+=("${target#*/}"); done
  local IFS=,
  printf '%s\n' --ignore "${names[*]}" "${targets[@]}"
}

omarchy_sheng_prepare_sources() {
  local updated key=40DFB630FF42BCFFB047046CF0134EE680CAC571
  updated=$(mktemp)
  awk '
    /^[[:space:]]*\[/ { omit = ($0 ~ /^[[:space:]]*\[omarchy\][[:space:]]*(#.*)?$/) }
    !omit { print }
  ' /etc/pacman.conf > "$updated"
  cat >> "$updated" <<'EOF'

[omarchy]
Usage = Sync
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/edge/$arch
EOF
  # The published Mac repository supplies portable ARM apps (e.g. Ghostty).
  # Append after ALARM and official edge. The desktop pair/graphics remain
  # explicit official targets above, including during full system upgrades.
  # Current edge archives are unsigned: scope Optional to this repository;
  # signed packages still require trusted keys. Never weaken global trust.
  if ! grep -qE '^[[:space:]]*\[omarchy-aarch64\]' "$updated"; then
    cat >> "$updated" <<'EOF'

[omarchy-aarch64]
SigLevel = Optional TrustedOnly
Server = https://github.com/omarchy-mac/omarchy-pkgs-aarch64/releases/download/edge
EOF
  fi
  install -m644 "$updated" /etc/pacman.conf
  rm -f "$updated"
  if ! pacman-key --list-keys "$key" >/dev/null 2>&1; then
    pacman-key --recv-keys "$key" --keyserver hkps://keys.openpgp.org
  fi
  pacman-key --lsign-key "$key"
}

# Ordinary package names retain normal ALARM/Mac selection. Only targets not
# installable by name fall back to the signed, Sync-only official repository.
# -Sddp is a read-only lookup: dependencies are checked by the real transaction.
omarchy_sheng_resolve_install_target() {
  local target=$1
  # The fork also publishes legacy .NET 2.1 as a virtual provider. For the
  # unversioned modern runtime request, select its current vendor ARM package.
  if [[ $target == dotnet-runtime ]] && pacman -Si omarchy-aarch64/dotnet-runtime-bin >/dev/null 2>&1; then
    target=omarchy-aarch64/dotnet-runtime-bin
  fi
  if [[ $target == */* ]]; then
    printf '%s\n' "$target"
  elif pacman -Sddp --print-format '%r/%n' -- "$target" 2>/dev/null; then
    return
  elif pacman -Sddp --print-format '%r/%n' -- "omarchy/$target" 2>/dev/null; then
    return
  else
    echo "No ARM binary package found for: $target" >&2
    return 1
  fi
}
