#!/usr/bin/env bash
# A device-aware full upgrade; no PC boot provisioning or unreviewed migrations.
set -euo pipefail
if (( EUID != 0 )); then exec sudo /usr/local/bin/omarchy-sheng-update "$@"; fi
source /usr/local/lib/omarchy-sheng/package-sources.sh
exec 9>/run/omarchy-sheng-update.lock
flock -n 9 || { echo 'Another sheng update is running.' >&2; exit 1; }
omarchy_sheng_prepare_sources
mapfile -t targets < <(omarchy_sheng_upgrade_args)
args=()
case "${1:-}" in
  -y) args+=(--noconfirm) ;;
  '') ;;
  *) echo 'Usage: omarchy-sheng-update [-y]' >&2; exit 2 ;;
esac
env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --needed "${args[@]}" "${targets[@]}"
/usr/local/lib/omarchy-sheng/verify.sh
install -d /var/lib/omarchy-sheng
pacman -Q > /var/lib/omarchy-sheng/packages.txt
echo 'Packages updated. Reboot to use the new desktop libraries.'
echo 'Device kernel/boot images and upstream PC migrations are managed separately.'
