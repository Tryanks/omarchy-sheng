#!/usr/bin/env bash
# Upstream update workflow, with the distribution's ARM keyring selected.
set -euo pipefail
if (( EUID != 0 )); then exec sudo /usr/local/bin/omarchy-update-keyring "$@"; fi
source /usr/local/lib/omarchy-sheng/package-sources.sh
omarchy_sheng_prepare_sources
pacman -Sy --noconfirm archlinuxarm-keyring
