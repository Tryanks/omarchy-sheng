#!/usr/bin/env bash
# Omarchy is opt-in: never let edge replace arbitrary ALARM packages.
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
  install -m644 "$updated" /etc/pacman.conf
  rm -f "$updated"
  if ! pacman-key --list-keys "$key" >/dev/null 2>&1; then
    pacman-key --recv-keys "$key" --keyserver hkps://keys.openpgp.org
  fi
  pacman-key --lsign-key "$key"
}
