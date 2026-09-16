#!/usr/bin/env bash
# The package stage of upstream `omarchy update`; retain its other stages.
set -euo pipefail
if (( EUID != 0 )); then exec sudo /usr/local/bin/omarchy-update-system-pkgs "$@"; fi
source /usr/local/lib/omarchy-sheng/package-sources.sh
exec 9>/run/omarchy-sheng-update.lock
flock -n 9 || { echo 'Another sheng update is running.' >&2; exit 1; }
omarchy_sheng_prepare_sources
mapfile -t targets < <(omarchy_sheng_upgrade_args)
env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --needed --noconfirm "${targets[@]}"
/usr/local/lib/omarchy-sheng/verify.sh
install -d /var/lib/omarchy-sheng
pacman -Q > /var/lib/omarchy-sheng/packages.txt
echo 'Packages updated. Reboot to use the new desktop libraries.'
echo 'Device kernel/boot images remain managed by sheng.'
