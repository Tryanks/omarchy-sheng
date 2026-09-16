#!/usr/bin/env bash
# Run as root on ALARM aarch64, both inside the image and on an existing sheng.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run as root.' >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo 'Native aarch64 required.' >&2; exit 1; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/package-sources.sh"
install -d /usr/local/lib/omarchy-sheng /usr/local/bin /etc/pacman.d/hooks
install -m755 "$HERE/"{package-sources,preserve-system,verify}.sh /usr/local/lib/omarchy-sheng/
install -m755 "$HERE/update.sh" /usr/local/bin/omarchy-update-system-pkgs
install -m755 "$HERE/update-keyring.sh" /usr/local/bin/omarchy-update-keyring
install -m644 "$HERE/session.lua" /usr/local/lib/omarchy-sheng/session.lua
# Remove only the aliases from our initial bring-up profile, not upstream files.
if [[ $(readlink /usr/local/bin/omarchy-update || true) == omarchy-sheng-update ]]; then
  rm /usr/local/bin/omarchy-update
fi
cat > /etc/pacman.d/hooks/01-omarchy-sheng-preserve.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = omarchy-settings
[Action]
Description = Preserving sheng system configuration...
When = PreTransaction
Exec = /usr/local/lib/omarchy-sheng/preserve-system.sh save
AbortOnFail
EOF
cat > /etc/pacman.d/hooks/99-omarchy-sheng-restore.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = omarchy-settings
[Action]
Description = Restoring sheng system configuration...
When = PostTransaction
Exec = /usr/local/lib/omarchy-sheng/preserve-system.sh restore
EOF
omarchy_sheng_prepare_sources
mapfile -t targets < <(omarchy_sheng_upgrade_args)
mapfile -t desktop < <(grep -vE '^\s*(#|$)' "$HERE/packages.list")
env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --needed --noconfirm "${targets[@]}" "${desktop[@]}"
bash "$HERE/default-apps.sh"
# Shell settings stay upstream-owned. Only these two user override files differ.
install -m644 "$HERE/monitors.lua" /etc/skel/.config/hypr/monitors.lua
printf 'dofile("/usr/local/lib/omarchy-sheng/session.lua")\n' > /etc/skel/.config/hypr/autostart.lua
/usr/local/lib/omarchy-sheng/verify.sh
install -d /var/lib/omarchy-sheng
pacman -Q > /var/lib/omarchy-sheng/packages.txt
echo 'Omarchy payload installed; user creation/session selection is a separate step.'
