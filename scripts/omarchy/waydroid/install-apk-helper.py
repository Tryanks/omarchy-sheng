#!/usr/bin/python3
"""Privileged bridge limited to installing one caller-owned APK into their Android."""
import os
from pathlib import Path
import pwd
import re
import stat
import subprocess
import sys
import dbus


def main():
    uid = int(os.environ['PKEXEC_UID'])
    if uid == 0 or len(sys.argv) != 2 or not re.fullmatch(r'[0-9a-f]{32}\.apk', sys.argv[1]):
        raise RuntimeError('Invalid caller or staged APK name')
    user = pwd.getpwuid(uid)
    cm = dbus.Interface(dbus.SystemBus().get_object('id.waydro.Container', '/ContainerManager'),
                        'id.waydro.ContainerManager')
    session = cm.GetSession()
    if int(session['user_id']) != uid or session['state'] not in ('RUNNING', 'FROZEN'):
        raise RuntimeError('No Android session owned by this user')
    stage = Path(user.pw_dir) / '.local/share/waydroid/data/waydroid_tmp'
    apk = stage / sys.argv[1]
    info = apk.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != uid:
        raise RuntimeError('Staged APK must be a regular file owned by the caller')
    if session['state'] == 'FROZEN':
        cm.Unfreeze()
    result = subprocess.run(['/usr/bin/waydroid', 'shell', '--', '/system/bin/pm', 'install', '-r',
                             '/data/waydroid_tmp/' + apk.name], timeout=150)
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
