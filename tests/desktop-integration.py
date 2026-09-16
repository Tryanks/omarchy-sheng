#!/usr/bin/env python3
"""State/upgrade regressions for public defaults and hardware data boundaries."""
import importlib.util
import json
from pathlib import Path
import tempfile

BASE = Path(__file__).resolve().parents[1] / 'scripts/omarchy'


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, BASE / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


shell = module('shell_defaults', 'configure-shell.py')
pen = module('pen', 'devices/pen_backend.py')
codec = module('codec', 'waydroid/codec-workaround.py')

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    default = root / 'usr/share/omarchy/config/omarchy/shell.json'
    default.parent.mkdir(parents=True)
    default.write_text(json.dumps({'version': 1, 'bar': {'layout': {
        'left': [{'id': 'omarchy.menu'}], 'right': [{'id': 'omarchy.power'}]}}}))
    home = root / 'etc/skel'
    shell.configure(home, root)
    path = home / '.config/omarchy/shell.json'
    first = path.read_text()
    shell.configure(home, root)
    assert first == path.read_text(), 'reinstall changed public defaults'
    data = json.loads(first)
    widgets = data['bar']['layout']['right']
    monitor = next(w for w in widgets if w['id'] == shell.MONITOR)
    assert len([x for x in monitor['monitors'] if x.startswith('sensor:')]) == 1
    assert next(w for w in widgets if w['id'] == 'omarchy.power')['showPercentage']
    # Preserve unrelated plugin choices, layout and screen-lock settings.
    data['idle'] = {'lock': 601}
    data['plugins'].append({'id': 'my.private-plugin', 'option': 'preserve'})
    data['bar']['layout']['left'].append({'id': 'custom-clock'})
    monitor['monitors'] = ['cpu']
    path.write_text(json.dumps(data))
    shell.configure(home, root)
    merged = json.loads(path.read_text())
    assert merged['idle']['lock'] == 601
    assert merged['plugins'][-1]['id'] == 'my.private-plugin'
    assert merged['bar']['layout']['left'][-1]['id'] == 'custom-clock'
    assert next(w for w in merged['bar']['layout']['right'] if w['id'] == shell.MONITOR)['monitors'] == ['cpu']
    assert not (home / '.local/share/waydroid').exists()
    assert not (root / 'var/lib/fprint').exists()

    sysfs = root / 'sysfs'
    sysfs.mkdir()
    assert not pen.sensor_state(sysfs)['valid']
    for name, value in {'pen_hall3': '1', 'pen_hall4': '1', 'pen_soc': '255',
                        'pen_mac_h': 'A1B2', 'pen_mac_l': 'C3D4E5F6'}.items():
        (sysfs / name).write_text(value)
    state = pen.sensor_state(sysfs)
    assert state['battery'] is None, 'invalid pen battery displayed as a percentage'
    assert not state['docked']
    assert state['address'] == 'A1:B2:C3:D4:E5:F6'
    (sysfs / 'pen_hall4').write_text('0')
    (sysfs / 'pen_soc').write_text('73')
    assert pen.sensor_state(sysfs)['docked']
    assert pen.sensor_state(sysfs)['battery'] == 73
    for level in (0, 6, True, '3'):
        try:
            pen.pinch_command(level)
            raise AssertionError('invalid pinch level accepted')
        except ValueError:
            pass
    assert pen.pinch_command(1) == bytes.fromhex('5c04005a002d')
    assert pen.pinch_command(5) == bytes.fromhex('5c0401c200e1')

for unknown in (b'', b'\x7fELF' + b'\0' * 500000):
    try:
        codec.patch(unknown)
        raise AssertionError('unknown Android library patched')
    except ValueError:
        pass
print('PASS: public defaults preserve user choices, reject invalid sensor data and unknown Android binaries')
