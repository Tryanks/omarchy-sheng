#!/usr/bin/env bash
set -euo pipefail
for package in omarchy omarchy-settings hyprland hyprtoolkit hyprland-guiutils quickshell-git uwsm sddm; do
  pacman -Q "$package"
done
# sudo clears XDG_RUNTIME_DIR; recent Hyprland needs one even for --version.
# Never borrow the logged-in user's runtime directory for a root check.
runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT
XDG_RUNTIME_DIR="$runtime" Hyprland --version
XDG_RUNTIME_DIR="$runtime" quickshell --version
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
[[ ${1:-} == --payload-only ]] || python3 /usr/local/lib/omarchy-sheng/verify-power.py
python3 -c 'import gi; gi.require_version("Gtk", "4.0"); from gi.repository import Gtk, Gio'
echo 'Omarchy ARM payload and runtime linkage verified.'
