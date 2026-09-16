#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
install -d /usr/local/lib/omarchy-sheng/devices /usr/local/bin /usr/local/share/applications
install -m644 "$HERE/devices/"*.py /usr/local/lib/omarchy-sheng/devices/
install -m644 "$HERE/fingerprint_ops.py" /usr/local/lib/omarchy-sheng/
install -m755 "$HERE/configure-shell.py" /usr/local/lib/omarchy-sheng/
install -m755 "$HERE/devices/launch.sh" /usr/local/bin/omarchy-sheng-devices
install -m644 "$HERE/devices/pen.desktop" /usr/local/share/applications/xiaomi-pen-status.desktop
install -Dm644 "$HERE/devices/sensors.conf" /etc/sensors.d/omarchy-sheng.conf
install -m755 "$HERE/fingerprint-launch.sh" /usr/local/bin/omarchy-setup-security-fingerprint
plugin=/usr/share/omarchy-sheng/plugins/sheng.devices
install -d "$plugin"
install -m644 "$HERE/devices/"*.qml "$HERE/devices/manifest.json" "$plugin/"
# Source-only native Quickshell plugin, pinned and retaining its MIT license.
revision=4f3f3dc71a2b7787ef8bc6cf85b078eb7661dc8a
monitor=/usr/share/omarchy-sheng/plugins/bitr0t.system-monitor
if [[ ! -f "$monitor/UPSTREAM_REVISION" ]] || [[ $(cat "$monitor/UPSTREAM_REVISION") != "$revision" ]]; then
  cache=$(mktemp -d)
  trap 'rm -rf "$cache"' EXIT
  git clone --quiet https://github.com/rmacy/omarchy-system-monitor "$cache/source"
  git -C "$cache/source" checkout --quiet "$revision"
  install -d "$monitor"
  cp -a "$cache/source/"*.qml "$cache/source/"*.js "$cache/source/manifest.json" \
    "$cache/source/qmldir" "$cache/source/LICENSE" "$cache/source/bin" "$monitor/"
  printf '%s\n' "$revision" > "$monitor/UPSTREAM_REVISION"
fi
python3 "$HERE/configure-shell.py"
update-desktop-database /usr/local/share/applications
