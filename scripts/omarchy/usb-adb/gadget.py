#!/usr/bin/env python3
"""Own one USB-only ADB gadget. Stopping releases it and restores the USB role."""
import hashlib
import os
from pathlib import Path
import pwd
import signal
import subprocess
import time

GADGET = Path('/sys/kernel/config/usb_gadget/omarchy-sheng')
FFS = Path('/dev/usb-ffs/adb')
ROLE = Path('/sys/class/usb_role/a600000.usb-role-switch/role')
stopping = False


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


def write(name, value):
    (GADGET / name).write_text(str(value) + '\n')


def prepare(user):
    if GADGET.exists():
        raise RuntimeError('Existing omarchy-sheng gadget; stop the old instance first')
    GADGET.mkdir()
    write('idVendor', '0x18d1')
    write('idProduct', '0x4ee7')
    write('bcdUSB', '0x0300')
    write('bcdDevice', '0x0100')
    for directory in ('strings/0x409', 'configs/c.1/strings/0x409', 'functions/ffs.adb'):
        (GADGET / directory).mkdir(parents=True, exist_ok=True)
    serial = hashlib.sha256(Path('/etc/machine-id').read_bytes()).hexdigest()[:16]
    write('strings/0x409/serialnumber', 'sheng-' + serial)
    write('strings/0x409/manufacturer', 'Omarchy Sheng')
    write('strings/0x409/product', 'Omarchy Linux ADB')
    write('configs/c.1/strings/0x409/configuration', 'Linux shell (USB ADB)')
    write('configs/c.1/MaxPower', '500')
    (GADGET / 'configs/c.1/ffs.adb').symlink_to(GADGET / 'functions/ffs.adb')
    write('os_desc/qw_sign', 'MSFT100')
    write('os_desc/b_vendor_code', '0x01')
    write('os_desc/use', '1')
    (GADGET / 'os_desc/c.1').symlink_to(GADGET / 'configs/c.1')
    FFS.parent.mkdir(parents=True, exist_ok=True)
    FFS.parent.chmod(0o755)
    FFS.mkdir(exist_ok=True)
    subprocess.run(['mount', '-t', 'functionfs', '-o',
                    f'uid={user.pw_uid},gid={user.pw_gid},rmode=0700,fmode=0600', 'adb', str(FFS)], check=True)


def request_device_role():
    if not ROLE.exists() or read(ROLE) == 'device':
        return False
    # A mounted hub/storage device has priority: never steal an active OTG bus.
    if any(p.name[0].isdigit() and '-' in p.name and ':' not in p.name
           for p in Path('/sys/bus/usb/devices').iterdir()):
        return False
    port = Path('/sys/class/typec/port0')
    if '[source]' in read(port / 'power_role'):
        return False
    # Some sheng firmware leaves host selected even for a sink/computer cable.
    if Path('/sys/class/typec/port0-partner').exists():
        ROLE.write_text('device\n')
        return True
    return False


def cleanup():
    if not GADGET.exists():
        return
    if read(GADGET / 'UDC'):
        write('UDC', '')
    for name in ('os_desc/c.1', 'configs/c.1/ffs.adb'):
        (GADGET / name).unlink(missing_ok=True)
    if os.path.ismount(FFS):
        subprocess.run(['umount', str(FFS)], check=True)
    for name in ('functions/ffs.adb', 'configs/c.1/strings/0x409', 'configs/c.1', 'strings/0x409'):
        path = GADGET / name
        if path.exists():
            path.rmdir()
    GADGET.rmdir()


def main():
    global stopping
    def stop(*_):
        global stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    if not ROLE.exists() or not GADGET.parent.exists():
        raise RuntimeError('USB role/configfs not ready; systemd will retry')
    user = pwd.getpwnam(os.environ.get('ADBD_USER', 'omarchy'))
    previous_role, changed_role, child = read(ROLE), False, None
    # Another gadget belongs to another application; do not unbind or delete it.
    if any(read(p / 'UDC') for p in GADGET.parent.iterdir()):
        raise RuntimeError('A USB gadget already owns the controller')
    if os.path.ismount(FFS):
        raise RuntimeError('An existing FunctionFS mount belongs to another instance')
    owned = False
    try:
        if GADGET.exists():
            raise RuntimeError('Stale gadget; inspect it before restarting')
        owned = True
        prepare(user)
        access = subprocess.run(['runuser', '-u', user.pw_name, '--', 'test', '-w', str(FFS / 'ep0')])
        if access.returncode:
            raise RuntimeError('FunctionFS missing: refusing adbd TCP fallback')
        # No ADBD_PORT/ADB_TCP_PORT inherited. With ep0 present upstream starts USB only.
        environment = {'PATH': '/usr/local/bin:/usr/bin:/usr/share/omarchy/bin',
                       'HOME': user.pw_dir, 'USER': user.pw_name, 'LOGNAME': user.pw_name,
                       'ADBD_SHELL': '/bin/bash', 'LANG': 'C.UTF-8'}
        child = subprocess.Popen(['/usr/local/lib/omarchy-sheng/adbd', '--device_banner=device'],
                                 env=environment, user=user.pw_uid, group=user.pw_gid,
                                 extra_groups=os.getgrouplist(user.pw_name, user.pw_gid),
                                 cwd=user.pw_dir)
        while not stopping:
            if child.poll() is not None:
                raise RuntimeError(f'adbd exited with {child.returncode}')
            if not read(GADGET / 'UDC') and (FFS / 'ep1').exists():
                udcs = sorted(Path('/sys/class/udc').iterdir())
                if udcs:
                    # Retry asynchronous role changes without restarting the daemon.
                    try:
                        write('UDC', udcs[0].name)
                        print(f'USB ADB ready ({user.pw_name} shell, no pairing)', flush=True)
                    except OSError as error:
                        print(f'Waiting for UDC: {error}', flush=True)
                else:
                    changed_role = request_device_role() or changed_role
            time.sleep(2)
    finally:
        if child is not None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if owned:
            cleanup()
        if changed_role and read(ROLE) == 'device' and previous_role in ('host', 'none'):
            ROLE.write_text(previous_role + '\n')


if __name__ == '__main__':
    main()
