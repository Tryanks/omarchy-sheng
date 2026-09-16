#!/usr/bin/env python3
"""Fetch verified public images during the build, never a user's Android data."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def stage(destination):
    pins = json.loads(Path(__file__).with_name('images.json').read_text())
    destination.mkdir(parents=True, exist_ok=True)
    for kind, pin in pins.items():
        image = destination / (kind + '.img')
        receipt = destination / (kind + '.json')
        if image.exists() and receipt.exists():
            record = json.loads(receipt.read_text())
            if record.get('zip_sha256') == pin['id']:
                with image.open('rb') as stream:
                    if hashlib.file_digest(stream, 'sha256').hexdigest() == record.get('image_sha256'):
                        continue
        with tempfile.TemporaryDirectory(dir=destination) as directory:
            archive = Path(directory) / 'image.zip'
            subprocess.run(['curl', '-fL', '--retry', '4', '--connect-timeout', '30',
                            '--max-time', '1800', pin['url'], '-o', str(archive)], check=True)
            with archive.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != pin['id']:
                raise ValueError('Waydroid archive SHA-256 mismatch: ' + kind)
            unpacked = Path(directory) / image.name
            with zipfile.ZipFile(archive) as z, z.open(image.name) as source, unpacked.open('wb') as out:
                shutil.copyfileobj(source, out)
            with unpacked.open('rb') as stream:
                raw_digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            unpacked.replace(image)
            receipt.write_text(json.dumps({'zip_sha256': digest, 'image_sha256': raw_digest}) + '\n')


if __name__ == '__main__':
    stage(Path('/usr/share/waydroid-extra/images'))
