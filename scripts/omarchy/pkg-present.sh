#!/usr/bin/env bash
# Account for ARM packages such as obsidian-appimage providing upstream names.
set -euo pipefail
packages=()
for package in "$@"; do packages+=("${package#*/}"); done
exec pacman -T -- "${packages[@]}" >/dev/null 2>&1
