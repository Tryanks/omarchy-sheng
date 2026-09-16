#!/usr/bin/python3
"""Bounded fprintd operations over NDJSON. Enrollment stays exclusively in fprintd."""
import argparse
import getpass
import json
from pathlib import Path
import signal
import subprocess
import sys
from gi.repository import Gio, GLib

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fingerprint_ops import delete_finger

FINGERS = [f'{hand}-{finger}' for hand in ('right', 'left') for finger in
           ('thumb', 'index-finger', 'middle-finger', 'ring-finger', 'little-finger')]


def emit(**data):
    print(json.dumps(data), flush=True)


class Device:
    def __init__(self):
        self.claimed = False
        manager = self.proxy('/net/reactivated/Fprint/Manager', 'net.reactivated.Fprint.Manager')
        path = manager.call_sync('GetDefaultDevice', None, Gio.DBusCallFlags.NONE, 10000, None).unpack()[0]
        self.device = self.proxy(path, 'net.reactivated.Fprint.Device')

    @staticmethod
    def proxy(path, interface):
        return Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SYSTEM, Gio.DBusProxyFlags.NONE,
                                             None, 'net.reactivated.Fprint', path, interface, None)

    def call(self, method, arg=None):
        params = None if arg is None else GLib.Variant('(s)', (arg,))
        return self.device.call_sync(method, params, Gio.DBusCallFlags.NONE, 10000, None).unpack()

    def list_fingers(self):
        try:
            return self.call('ListEnrolledFingers', getpass.getuser())[0]
        except GLib.Error as error:
            if 'NoEnrolledPrints' in str(error):
                return []
            raise

    def claim(self):
        self.call('Claim', getpass.getuser())
        self.claimed = True

    def release(self):
        if self.claimed:
            try:
                self.call('Release')
            finally:
                self.claimed = False

    def delete_record(self, finger):
        self.call('DeleteEnrolledFinger', finger)

    @staticmethod
    def authorize(action):
        result = subprocess.run(['pkexec', '/usr/local/lib/omarchy-sheng/fingerprint-auth.py', action],
                                capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise RuntimeError('authorization-cancelled')

    def status(self):
        return dict(enrolled=self.list_fingers(), sensor=self.device.get_cached_property('name').unpack(),
                    total=self.device.get_cached_property('num-enroll-stages').unpack(),
                    lockEnabled=Path('/etc/pam.d/omarchy-lock-fingerprint').exists())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'enroll', 'verify', 'delete', 'enable'])
    parser.add_argument('finger', nargs='?', choices=FINGERS)
    args = parser.parse_args()
    device, operation, loop = None, None, GLib.MainLoop()
    result = {'result': 'cancelled', 'ok': False}
    finished = False
    try:
        device = Device()
        initial = device.status()
        emit(event='status', **initial)
        if args.action == 'status':
            return 0
        if args.action == 'enable':
            device.authorize('enable')
            emit(event='done', ok=True, result='enabled', **device.status())
            return 0
        if not args.finger:
            raise ValueError('Choose a finger first')
        if args.action == 'enroll' and args.finger in initial['enrolled']:
            raise ValueError('already-enrolled')
        if args.action in ('verify', 'delete') and args.finger not in initial['enrolled']:
            raise ValueError('not-enrolled')
        if args.action == 'delete':
            delete_finger(device, args.finger, device.authorize)
            emit(event='done', ok=True, result='deleted', **device.status())
            return 0
        operation = args.action.title()
        stages = 0
        def on_signal(_proxy, _sender, name, params):
            nonlocal stages, result, finished
            if name != operation + 'Status':
                return
            status, done = params.unpack()
            if status == 'enroll-stage-passed':
                stages += 1
            emit(event='progress', result=status, stages=stages, total=initial['total'])
            if done:
                finished = True
                result = dict(result=status, ok=status in ('enroll-completed', 'verify-match'))
                loop.quit()
        device.device.connect('g-signal', on_signal)
        def stop(*_):
            nonlocal finished
            finished = True
            loop.quit()
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        device.claim()
        device.call(operation + 'Start', args.finger)
        emit(event='started', operation=args.action)
        def expired():
            nonlocal result
            result = dict(result='timeout', ok=False)
            loop.quit()
            return False
        GLib.timeout_add_seconds(120 if args.action == 'enroll' else 30, expired)
        if not finished:
            loop.run()
        try:
            device.call(operation + 'Stop')
        except GLib.Error:
            pass
        operation = None
        device.release()
        emit(event='done', **result, **device.status())
        return 0 if result['ok'] else 1
    except Exception as error:
        emit(event='error', message=str(error), ok=False)
        return 1
    finally:
        if device and device.claimed:
            if operation:
                try:
                    device.call(operation + 'Stop')
                except GLib.Error:
                    pass
            try:
                device.release()
            except GLib.Error:
                pass


if __name__ == '__main__':
    sys.exit(main())
