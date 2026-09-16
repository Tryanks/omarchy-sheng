#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
version=v36.0.1-linux.2
sha=e7876da9ddf2fd74176de83b7ff276252292c0e5e1150565d53a812c6eab2442
dest=/usr/local/lib/omarchy-sheng
install -d "$dest" /usr/local/share/licenses/omarchy-sheng-adbd
if [[ ! -f "$dest/adbd" ]] || [[ $(sha256sum "$dest/adbd" | cut -d' ' -f1) != "$sha" ]]; then
  temp=$(mktemp)
  trap 'rm -f "$temp"' EXIT
  curl -fL --retry 3 "https://github.com/happyme531/standalone-linux-adbd/releases/download/$version/adbd-36.0.1-linux-aarch64-static" -o "$temp"
  printf '%s  %s\n' "$sha" "$temp" | sha256sum -c -
  install -m755 "$temp" "$dest/adbd"
fi
install -m644 "$HERE/usb-adb/gadget.py" "$dest/usb-adb.py"
install -m644 "$HERE/usb-adb/LICENSE" /usr/local/share/licenses/omarchy-sheng-adbd/LICENSE
install -m644 "$HERE/usb-adb/omarchy-sheng-adb.service" /etc/systemd/system/
install -d /etc/systemd/system/multi-user.target.wants
ln -sfn /etc/systemd/system/omarchy-sheng-adb.service /etc/systemd/system/multi-user.target.wants/omarchy-sheng-adb.service
# No daemon is started inside the image builder. Live installations start explicitly.
