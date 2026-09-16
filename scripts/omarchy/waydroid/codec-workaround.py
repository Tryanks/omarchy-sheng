#!/usr/bin/env python3
"""Avoid missing OMX HAL's endless retry on the pinned ARM64-only Android 13 image.

Waydroid #2397; exact AArch64 IOmxStore getService retry argument only.
Unknown images fail closed. Original system.img is never modified.
"""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

ORIGINAL = 'b343ab767e7511b7c3abd522184ff1db8bb4b2d0c4491ed8ac63ff63509e8a50'
PATCHED = '9bdf01dfd15160da62a0f7175219a84d197df25b72e8941b37b36b8b311b226c'
LIBRARY = 'system/lib64/android.hardware.media.omx@1.0.so'
OFFSET = 0x6243c


def patch(data):
    if hashlib.sha256(data).hexdigest() != ORIGINAL:
        raise ValueError('Unknown OMX library: requalify this image before applying the workaround')
    if data[OFFSET:OFFSET + 4] != bytes.fromhex('21008052'):
        raise ValueError('Unexpected retry instruction')
    result = data[:OFFSET] + bytes.fromhex('e1031f2a') + data[OFFSET + 4:]
    if hashlib.sha256(result).hexdigest() != PATCHED:
        raise ValueError('Patched library verification failed')
    return result


def install(image, overlay):
    with tempfile.TemporaryDirectory() as directory:
        extracted = Path(directory) / 'omx.so'
        subprocess.run(['debugfs', '-R', f'dump -p /{LIBRARY} {extracted}', str(image)],
                       check=True, capture_output=True, text=True)
        result = patch(extracted.read_bytes())
    dest = overlay / LIBRARY
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.read_bytes() == result:
        return
    temp = dest.with_suffix('.tmp')
    temp.write_bytes(result)
    temp.chmod(0o644)
    temp.replace(dest)


if __name__ == '__main__':
    install(Path(sys.argv[1]), Path(sys.argv[2]))
