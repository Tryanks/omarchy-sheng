#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""QML transport for sheng pen state; protocol based on ianchb/xiaomi-pen-status.

No GUI and no privileged writes. The persistent BlueZ connection owns only its
own bounded discovery session. stdout is NDJSON, never raw D-Bus objects.
"""
import argparse
import configparser
import json
import os
from pathlib import Path
import signal
import time

BASE = Path('/sys/devices/platform/pmic-glink/pmic_glink.power-supply.0/xiaomi')
READY = Path('/run/xiaomi-sheng-thp/p81c-fe11-ready')
CONFIG = Path.home() / '.config/omarchy/sheng-pen.json'
COMMAND_UUID = '0000fe11-aa6c-462a-964a-7f2ed5b3e512'


def read_int(path, base=0):
    try:
        return int(path.read_text().strip(), base)
    except (OSError, ValueError):
        return None


def sensor_state(base=BASE):
    values = {name: read_int(base / name) for name in
              ('pen_hall3', 'pen_hall4', 'pen_soc', 'pen_place_err', 'pen_tx_ss', 'tx_iout', 'tx_vout')}
    high, low = (read_int(base / name, 16) for name in ('pen_mac_h', 'pen_mac_l'))
    address = ''
    if high is not None and low is not None and (high or low):
        raw = f'{high & 0xffff:04X}{low & 0xffffffff:08X}'
        address = ':'.join(raw[i:i + 2] for i in range(0, 12, 2))
    soc = values['pen_soc']
    return dict(values, valid=any(values[k] is not None for k in ('pen_hall3', 'pen_hall4', 'pen_soc')),
                docked=values['pen_hall3'] == 0 or values['pen_hall4'] == 0,
                misplaced=values['pen_place_err'] not in (None, 0),
                battery=soc if soc is not None and 0 <= soc <= 100 else None, address=address)


def pinch_command(level):
    if type(level) is not int or not 1 <= level <= 5:
        raise ValueError('Pinch level must be 1–5')
    return bytes([0x5c, 0x04]) + (90 * level).to_bytes(2, 'big') + (45 * level).to_bytes(2, 'big')


def read_level():
    try:
        value = json.loads(CONFIG.read_text())['pinchLevel']
        return value if type(value) is int and 1 <= value <= 5 else 3
    except (OSError, ValueError, KeyError):
        old = configparser.ConfigParser()
        old.read(Path.home() / '.config/xiaomi-pen-status/xiaomi-pen-status.conf')
        try:
            return max(1, min(5, old.getint('focusPenPro', 'pinchLevel', fallback=3)))
        except ValueError:
            return 3


class Backend:
    def __init__(self):
        import dbus
        self.dbus = dbus
        self.bus = dbus.SystemBus()
        self.address = ''
        self.deadline = self.next_action = self.next_pinch = 0
        self.discovery = ''
        self.applied = None
        self.last_docked = self.last_powered = self.last_connected = False

    def interface(self, path, interface):
        return self.dbus.Interface(self.bus.get_object('org.bluez', str(path)), interface)

    def stop_discovery(self):
        if self.discovery:
            try:
                self.interface(self.discovery, 'org.bluez.Adapter1').StopDiscovery(timeout=2)
            except self.dbus.DBusException:
                pass
            self.discovery = ''

    def snapshot(self, act=False):
        state = sensor_state()
        state.update(powered=False, connected=False, paired=False, name='', focusPro=False,
                     settingsReady=False, pinchLevel=read_level(), pinchApplied=False, error='')
        now = time.monotonic()
        if state['address'] != self.address:
            self.stop_discovery()
            self.address, self.deadline, self.next_action = state['address'], now + 30, 0
        try:
            objects = self.interface('/', 'org.freedesktop.DBus.ObjectManager').GetManagedObjects(timeout=3)
            adapters = [(str(p), v['org.bluez.Adapter1']) for p, v in objects.items() if 'org.bluez.Adapter1' in v]
            devices = [(str(p), v['org.bluez.Device1']) for p, v in objects.items()
                       if str(v.get('org.bluez.Device1', {}).get('Address', '')).upper() == self.address and self.address]
            adapter, ap = adapters[0] if adapters else ('', {})
            path, dev = devices[0] if devices else ('', {})
            state.update(powered=bool(ap.get('Powered', False)), connected=bool(dev.get('Connected', False)),
                         paired=bool(dev.get('Paired', False)), name=str(dev.get('Name', '')))
            state['focusPro'] = state['name'] == 'Xiaomi Focus Pen Pro'
            if ((state['docked'] and not self.last_docked) or
                    (state['powered'] and not self.last_powered) or
                    (self.last_connected and not state['connected'])):
                self.deadline, self.next_action = now + 30, 0
            self.last_docked, self.last_powered, self.last_connected = state['docked'], state['powered'], state['connected']
            if act:
                if not self.address or state['connected'] or now >= self.deadline:
                    self.stop_discovery()
                if self.address and state['powered'] and not state['connected'] and now < self.deadline and now >= self.next_action:
                    if not path:
                        if not ap.get('Discovering') and not self.discovery:
                            iface = self.interface(adapter, 'org.bluez.Adapter1')
                            iface.SetDiscoveryFilter({'Transport': 'le'}, timeout=2)
                            iface.StartDiscovery(timeout=2)
                            self.discovery = adapter
                    else:
                        self.stop_discovery()
                        iface = self.interface(path, 'org.bluez.Device1')
                        # Async calls keep a slow radio from blocking state delivery.
                        method = iface.Connect if state['paired'] else iface.Pair
                        method(reply_handler=lambda: None, error_handler=lambda _e: None, timeout=8)
                    self.next_action = now + 5
                if path and state['connected'] and state['paired'] and not dev.get('Trusted'):
                    self.interface(path, 'org.freedesktop.DBus.Properties').Set(
                        'org.bluez.Device1', 'Trusted', self.dbus.Boolean(True), timeout=2)
            command = ''
            state.update(firmware='', software='')
            for p, interfaces in objects.items():
                prop = interfaces.get('org.bluez.GattCharacteristic1', {})
                if path and str(p).startswith(path + '/') and str(prop.get('UUID', '')).lower() == COMMAND_UUID:
                    command = str(p)
                if path and state['connected'] and str(p).startswith(path + '/'):
                    uuid = str(prop.get('UUID', '')).lower()
                    field = {'00002a26-0000-1000-8000-00805f9b34fb': 'firmware',
                             '00002a28-0000-1000-8000-00805f9b34fb': 'software'}.get(uuid)
                    if field:
                        value = prop.get('Value', [])
                        if not value and act:
                            value = self.interface(p, 'org.bluez.GattCharacteristic1').ReadValue({}, timeout=2)
                        state[field] = bytes(value).decode('utf-8', errors='replace').strip('\x00')[:64]
            try:
                ready = READY.read_text().strip().upper() == self.address
            except OSError:
                ready = False
            state['settingsReady'] = bool(state['focusPro'] and state['connected'] and dev.get('ServicesResolved') and command and ready)
            target = (command, state['pinchLevel']) if state['settingsReady'] else None
            if target is None:
                self.applied = None
            elif act and target != self.applied and now >= self.next_pinch:
                self.next_pinch = now + 3
                self.interface(command, 'org.bluez.GattCharacteristic1').WriteValue(
                    self.dbus.ByteArray(pinch_command(state['pinchLevel'])), {'type': 'command'}, timeout=2)
                self.applied = target
            state['pinchApplied'] = target is not None and self.applied == target
        except self.dbus.DBusException as error:
            state['error'] = error.get_dbus_name()
        return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pinch', type=int, choices=range(1, 6))
    parser.add_argument('--watch', action='store_true')
    args = parser.parse_args()
    if args.pinch is not None:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        tmp = CONFIG.with_suffix('.tmp')
        tmp.write_text(json.dumps({'pinchLevel': args.pinch}) + '\n')
        tmp.chmod(0o600)
        tmp.replace(CONFIG)
        return
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    backend, loop = Backend(), GLib.MainLoop()
    def tick():
        print(json.dumps(backend.snapshot(act=args.watch)), flush=True)
        return True
    def stop(*_):
        loop.quit()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        tick()
        if args.watch:
            GLib.timeout_add_seconds(2, tick)
            loop.run()
    finally:
        backend.stop_discovery()


if __name__ == '__main__':
    main()
