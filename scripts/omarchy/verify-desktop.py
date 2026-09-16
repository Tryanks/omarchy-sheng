#!/usr/bin/env python3
"""Verify installed integration and keep personal state out of public images."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--image', action='store_true')
args = parser.parse_args()

for name in (
    '/usr/local/bin/omarchy-sheng-devices',
    '/usr/local/bin/omarchy-setup-security-fingerprint',
    '/usr/local/lib/omarchy-sheng/devices/pen_backend.py',
    '/usr/local/lib/omarchy-sheng/devices/fingerprint_backend.py',
    '/usr/share/omarchy-sheng/plugins/sheng.devices/Devices.qml',
    '/usr/share/omarchy-sheng/plugins/bitr0t.system-monitor/BarWidget.qml',
    '/usr/share/omarchy-sheng/plugins/bitr0t.system-monitor/LICENSE',
    '/usr/local/lib/omarchy-sheng/adbd',
    '/usr/local/share/licenses/omarchy-sheng-adbd/LICENSE',
    '/usr/local/lib/omarchy-sheng/usb-adb.py',
    '/usr/local/lib/omarchy-sheng/waydroid/first-boot.py',
    '/usr/local/bin/waydroid-install-apk',
    '/etc/polkit-1/rules.d/50-omarchy-sheng-apk.rules',
    '/usr/share/applications/com.tryanks.tcode.desktop',
    '/usr/share/licenses/tcode-bin/LICENSE',
    '/usr/local/lib/omarchy-sheng/rounded-cursor.lua',
):
    assert Path(name).is_file() and Path(name).stat().st_size, 'Missing: ' + name

for service in ('omarchy-sheng-adb.service', 'omarchy-sheng-waydroid.service', 'waydroid-container.service'):
    subprocess.run(['systemctl', 'is-enabled', '--quiet', service], check=True)
subprocess.run(['pacman', '-Q', 'tcode-bin', 'waydroid', 'lm_sensors', 'python-dbus'], check=True)
adb_unit = Path('/etc/systemd/system/omarchy-sheng-adb.service').read_text()
assert 'SocketBindDeny=any' in adb_unit, 'ADB TCP fallback guard missing'

if args.image:
    subprocess.run(['pacman', '-Q', 'xiaomi-sheng-fingerprint'], check=True)
    data = json.loads(Path('/etc/skel/.config/omarchy/shell.json').read_text())
    widgets = [w for section in data['bar']['layout'].values() for w in section]
    assert next(w for w in widgets if w['id'] == 'omarchy.power')['showPercentage']
    monitors = next(w for w in widgets if w['id'] == 'bitr0t.system-monitor')['monitors']
    assert monitors == ['cpu', 'memory', 'sensor:temperature:cpuss0_thermal-virtual-0:CPU:temp1_input']
    for kind in ('system', 'vendor'):
        assert Path('/usr/share/waydroid-extra/images', kind + '.img').stat().st_size > 0
        record = json.loads(Path('/usr/share/waydroid-extra/images', kind + '.json').read_text())
        pins = json.loads(Path('/usr/local/lib/omarchy-sheng/waydroid/images.json').read_text())
        assert record['zip_sha256'] == pins[kind]['id']
    assert not Path('/var/lib/omarchy-sheng/waydroid-ready').exists(), 'First boot already ran in image'
    for directory in ('/var/lib/fprint', '/var/lib/waydroid/data', '/etc/skel/.local/share/waydroid'):
        assert not any(p.is_file() for p in Path(directory).rglob('*')), 'Personal state in image: ' + directory

print('Tablet desktop integration verified' + ('; public image state is clean.' if args.image else '.'))
