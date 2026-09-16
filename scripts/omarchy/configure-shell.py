#!/usr/bin/env python3
"""Merge public shell defaults; never copy a live user's data into the image."""
import argparse
import configparser
import json
import shutil
from pathlib import Path

MONITOR = 'bitr0t.system-monitor'
DEVICES = 'sheng.devices'
SENSORS = ['cpu', 'memory', 'sensor:temperature:cpuss0_thermal-virtual-0:CPU:temp1_input']


def configure(home, root=Path('/')):
    config = home / '.config/omarchy'
    config.mkdir(parents=True, exist_ok=True)
    path = config / 'shell.json'
    default = root / 'usr/share/omarchy/config/omarchy/shell.json'
    data = json.loads((path if path.exists() else default).read_text())
    layout = data.setdefault('bar', {}).setdefault('layout', {})
    right = layout.setdefault('right', [])
    power = next((item for section in layout.values() if isinstance(section, list)
                  for item in section if item.get('id') == 'omarchy.power'), None)
    if power is None:
        power = {'id': 'omarchy.power'}
        right.append(power)
    power['showPercentage'] = True
    for plugin, settings in [(MONITOR, {'monitors': SENSORS, 'chipMode': 'instrument'}), (DEVICES, {})]:
        if not any(item.get('id') == plugin for section in layout.values()
                   if isinstance(section, list) for item in section):
            right.insert(0, {'id': plugin, **settings})
        for section in layout.values():
            if not isinstance(section, list):
                continue
            for item in section:
                if item.get('id') == MONITOR and 'monitors' in item:
                    item['monitors'] = [s.replace('cpuss0_thermal-virtual-0:temp1:', 'cpuss0_thermal-virtual-0:CPU:')
                                       .replace('qcom_battmgr_bat-virtual-0:temp:', 'qcom_battmgr_bat-virtual-0:Battery:')
                                       for s in item['monitors'] if not s.startswith('sensor:temperature:qcom_battmgr_bat-virtual-0:')]
        target = config / 'plugins' / plugin
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() and not target.is_symlink():
            target.symlink_to('/usr/share/omarchy-sheng/plugins/' + plugin)
    plugins = data.setdefault('plugins', [])
    if not any(item.get('id') == DEVICES for item in plugins):
        plugins.append({'id': DEVICES})
    if path.exists() and not path.with_suffix('.json.before-sheng-devices').exists():
        shutil.copy2(path, path.with_suffix('.json.before-sheng-devices'))
    temp = path.with_suffix('.json.tmp')
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    temp.replace(path)
    # Only the Omarchy panel owns pen Bluetooth pairing now.
    autostart = home / '.config/autostart/xiaomi-pen-status.desktop'
    autostart.parent.mkdir(parents=True, exist_ok=True)
    autostart.write_text('[Desktop Entry]\nType=Application\nName=Stylus Status\nHidden=true\n')
    mimefile = home / '.config/mimeapps.list'
    mime = configparser.ConfigParser(interpolation=None, strict=False)
    mime.optionxform = str
    mime.read(mimefile)
    if not mime.has_section('Default Applications'):
        mime.add_section('Default Applications')
    mime['Default Applications'].setdefault('application/vnd.android.package-archive', 'waydroid-install-apk.desktop')
    with mimefile.open('w') as stream:
        mime.write(stream, space_around_delimiters=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path('/'))
    parser.add_argument('--home', type=Path, help='Explicit existing user; otherwise only /etc/skel')
    args = parser.parse_args()
    configure(args.home or args.root / 'etc/skel', args.root)
