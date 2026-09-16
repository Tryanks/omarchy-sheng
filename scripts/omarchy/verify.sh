#!/usr/bin/env bash
set -euo pipefail
for package in omarchy omarchy-settings hyprland hyprtoolkit hyprland-guiutils quickshell-git uwsm sddm; do
  pacman -Q "$package"
done
Hyprland --version
quickshell --version
for binary in /usr/bin/Hyprland /usr/bin/quickshell /usr/lib/libhyprtoolkit.so; do
  result=$(ldd "$binary")
  if grep -q 'not found' <<< "$result"; then
    printf '%s\n' "$result" >&2
    exit 1
  fi
done
test -s /usr/local/share/wayland-sessions/omarchy.desktop
test -s /etc/skel/.config/hypr/hyprland.lua
test ! -e /etc/mkinitcpio.conf.d/omarchy_hooks.conf
test ! -e /etc/limine-entry-tool.d/omarchy-uki.conf
echo 'Omarchy ARM payload and runtime linkage verified.'
