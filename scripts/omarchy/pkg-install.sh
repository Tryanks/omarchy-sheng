#!/usr/bin/env bash
# Native Omarchy picker with installation delegated to the ARM source resolver.
set -euo pipefail
packages=$(pacman -Slq | sort -u | fzf --multi \
  --preview 'pacman -Sii {1} 2>/dev/null || pacman -Sii omarchy/{1}' \
  --preview-window 'down:65%:wrap' \
  --preview-label='alt-p: toggle description, alt-j/k: scroll, tab: multi-select' \
  --bind 'alt-p:toggle-preview,alt-j:preview-down,alt-k:preview-up') || exit 0
[[ -n $packages ]] || exit 0
mapfile -t selected <<< "$packages"
omarchy-pkg-add "${selected[@]}"
omarchy-show-done
