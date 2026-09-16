#!/usr/bin/python3
"""Initialize from public, preinstalled images; preserve existing Android user data."""
import argparse
import configparser
import importlib.util
from pathlib import Path
import subprocess
import sys


def main():
    config = Path('/var/lib/waydroid/waydroid.cfg')
    if not config.exists():
        subprocess.run(['waydroid', 'init', '-i', '/usr/share/waydroid-extra/images'], check=True)
    cfg = configparser.ConfigParser()
    cfg.read(config)
    if cfg['waydroid']['arch'] != 'arm64_only':
        raise RuntimeError('Only the qualified arm64_only image is supported')
    image = Path(cfg['waydroid']['images_path']) / 'system.img'
    spec = importlib.util.spec_from_file_location('codec', Path(__file__).with_name('codec-workaround.py'))
    codec = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(codec)
    codec.install(image, Path('/var/lib/waydroid/overlay'))
    if 'properties' not in cfg:
        cfg['properties'] = {}
    cfg['properties']['debug.stagefright.ccodec'] = '1'
    # Existing Android language/timezone choices are retained.
    locale = Path('/etc/locale.conf').read_text() if Path('/etc/locale.conf').exists() else ''
    cfg['properties'].setdefault('persist.sys.locale', 'zh-CN' if 'zh_CN' in locale else 'en-US')
    zone = str(Path('/etc/localtime').resolve()).split('/zoneinfo/')
    if len(zone) == 2:
        cfg['properties'].setdefault('persist.sys.timezone', zone[1])
    temp = config.with_suffix('.tmp')
    with temp.open('w') as stream:
        cfg.write(stream)
    temp.chmod(config.stat().st_mode & 0o777)
    temp.replace(config)
    # Same generator as waydroid upgrade --offline, without stopping a live container.
    sys.path.insert(0, '/usr/lib/waydroid')
    import tools
    args = argparse.Namespace()
    tools.prep_args(args)
    tools.actions.upgrader.get_config(args)
    tools.helpers.lxc.make_base_props(args)
    ready = Path('/var/lib/omarchy-sheng/waydroid-ready')
    ready.parent.mkdir(parents=True, exist_ok=True)
    ready.write_text('20260403-arm64-only-codec2-v1\n')


if __name__ == '__main__':
    main()
