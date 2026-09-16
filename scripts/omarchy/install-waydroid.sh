#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest=/usr/local/lib/omarchy-sheng/waydroid
install -d "$dest" /etc/polkit-1/rules.d /usr/local/share/applications /etc/systemd/system/waydroid-container.service.d
install -m644 "$HERE/waydroid/"*.py "$HERE/waydroid/images.json" "$dest/"
chmod 755 "$dest/install-apk-helper.py"
install -m755 "$HERE/waydroid/install-apk.py" /usr/local/bin/waydroid-install-apk
install -m644 "$HERE/waydroid/50-omarchy-sheng-apk.rules" /etc/polkit-1/rules.d/
install -m644 "$HERE/waydroid/install-apk.desktop" /usr/local/share/applications/waydroid-install-apk.desktop
install -m644 "$HERE/waydroid/omarchy-sheng-waydroid.service" /etc/systemd/system/
printf '[Unit]\nRequires=omarchy-sheng-waydroid.service\nAfter=omarchy-sheng-waydroid.service\n' > /etc/systemd/system/waydroid-container.service.d/50-sheng-init.conf
if [[ ! -f /var/lib/waydroid/waydroid.cfg ]]; then
  python3 "$dest/stage-images.py"
  python3 "$dest/codec-workaround.py" /usr/share/waydroid-extra/images/system.img /var/lib/omarchy-sheng/waydroid-verified-overlay
  # Validation only. First boot recreates the overlay after Waydroid's initializer.
  rm -rf /var/lib/omarchy-sheng/waydroid-verified-overlay
fi
systemctl enable omarchy-sheng-waydroid.service waydroid-container.service
update-desktop-database /usr/local/share/applications
