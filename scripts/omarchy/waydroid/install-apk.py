#!/usr/bin/python3
"""Install a standalone APK and report Android Package Manager's actual result."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid
import zipfile
import dbus


def run(args, timeout=15):
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout)


def install(paths):
    files = [Path(p).expanduser().resolve(strict=True) for p in paths]
    for p in files:
        if not p.is_file() or not zipfile.is_zipfile(p):
            raise ValueError(f"不是有效的 APK 文件：{p.name}")
        with zipfile.ZipFile(p) as z:
            if "AndroidManifest.xml" not in z.namelist():
                raise ValueError(f"不是独立 APK：{p.name}。请使用完整 APK 安装包。")
    cm = dbus.Interface(dbus.SystemBus().get_object("id.waydro.Container", "/ContainerManager"), "id.waydro.ContainerManager")
    state = str(cm.GetSession().get("state", "STOPPED"))
    if state not in ("RUNNING", "FROZEN"):
        started = run(["systemd-run", "--user", "--collect", "--unit=waydroid-session", "/usr/bin/waydroid", "session", "start"])
        if started.returncode:
            raise RuntimeError(started.stderr.strip())
    for _ in range(90):
        state = str(cm.GetSession().get("state", "STOPPED"))
        if state == "FROZEN":
            cm.Unfreeze()
        if state in ("RUNNING", "FROZEN"):
            ready = run(["waydroid", "prop", "get", "sys.boot_completed"])
            if ready.stdout.strip() == "1":
                break
        time.sleep(1)
    else:
        raise RuntimeError("Android 启动超时，请打开 Waydroid 后重试。")
    target = Path.home() / ".local/share/waydroid/data/waydroid_tmp"
    target.mkdir(parents=True, exist_ok=True)
    for p in files:
        temp = target / (uuid.uuid4().hex + ".apk")
        try:
            shutil.copyfile(p, temp)
            result = run(["pkexec", "/usr/local/lib/omarchy-sheng/waydroid/install-apk-helper.py", temp.name], timeout=180)
            if "Success" not in result.stdout.splitlines():
                detail = (result.stdout + result.stderr).strip()
                raise RuntimeError(f"{p.name} 安装失败：\n{detail or '没有收到 Android 的成功确认'}")
        finally:
            temp.unlink(missing_ok=True)
    return "安装完成，可从 Omarchy 应用菜单或 Waydroid 打开。"


def main():
    args = sys.argv[1:]
    quiet = bool(args and args[0] == "--non-interactive")
    if quiet:
        args.pop(0)
    if not args:
        choice = run(["zenity", "--file-selection", "--title=安装 Android 应用", "--file-filter=Android 应用 | *.apk"], timeout=3600)
        if choice.returncode:
            return 0
        args = [choice.stdout.strip()]
    progress = None
    try:
        if not quiet:
            progress = subprocess.Popen(["zenity", "--progress", "--pulsate", "--no-cancel", "--title=安装 Android 应用", "--text=正在准备 Android 并安装应用…"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        message = install(args)
        success = True
    except Exception as e:
        message, success = str(e), False
    finally:
        if progress:
            progress.terminate()
            progress.wait(timeout=5)
    if quiet:
        print(message)
    else:
        run(["zenity", "--info" if success else "--error", "--no-markup", "--title=安装 Android 应用", "--text=" + message], timeout=3600)
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
