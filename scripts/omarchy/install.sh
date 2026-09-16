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
install -m755 "$HERE/pkg-add.sh" /usr/local/bin/omarchy-pkg-add
install -m755 "$HERE/pkg-install.sh" /usr/local/bin/omarchy-pkg-install
install -m755 "$HERE/pkg-present.sh" /usr/local/bin/omarchy-pkg-present
install -m755 "$HERE/pkg-missing.sh" /usr/local/bin/omarchy-pkg-missing
install -m644 "$HERE/session.lua" /usr/local/lib/omarchy-sheng/session.lua
install -m755 "$HERE/verify-power.py" /usr/local/lib/omarchy-sheng/verify-power.py
install -m755 "$HERE/configure-power.py" /usr/local/lib/omarchy-sheng/configure-power.py
install -m755 "$HERE/"fingerprint*.py "$HERE/fingerprint-launch.sh" /usr/local/lib/omarchy-sheng/
install -m644 "$HERE/fingerprint.desktop" /usr/local/lib/omarchy-sheng/
install -d /usr/local/lib/omarchy-sheng/power
find "$HERE/power" -maxdepth 1 -type f -exec install -m644 {} /usr/local/lib/omarchy-sheng/power/ \;
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
pacman -D --asexplicit "${desktop[@]}"
bash "$HERE/default-apps.sh"
# Shell settings stay upstream-owned. Only these two user override files differ.
install -m644 "$HERE/monitors.lua" /etc/skel/.config/hypr/monitors.lua
printf 'dofile("/usr/local/lib/omarchy-sheng/session.lua")\n' > /etc/skel/.config/hypr/autostart.lua
# Image stage 20 precedes the device packages in stage 30. Stage 40 must
# configure power afterwards; final verification never skips these checks.
if [[ -f /usr/lib/systemd/system/xiaomi-charger-mode.service ]]; then
  python3 "$HERE/configure-power.py"
  /usr/local/lib/omarchy-sheng/verify.sh
else
  /usr/local/lib/omarchy-sheng/verify.sh --payload-only
fi
install -d /var/lib/omarchy-sheng
pacman -Q > /var/lib/omarchy-sheng/packages.txt
echo 'Omarchy payload installed; user creation/session selection is a separate step.'
