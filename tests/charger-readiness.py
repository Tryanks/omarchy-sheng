#!/usr/bin/env python3
"""Replay the observed partner-before-PDO boot race without electrical writes."""
import importlib.util
import tempfile
import threading
import time
from pathlib import Path

source = Path(__file__).resolve().parents[1] / "scripts/omarchy/power/wait-charger.py"
spec = importlib.util.spec_from_file_location("wait_charger", source)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    pdo = root / "devices/platform/pmic-glink/battery/xiaomi/pdo2"
    role = root / "class/typec/port0/data_role"
    pdo.parent.mkdir(parents=True)
    role.parent.mkdir(parents=True)
    pdo.write_text("00000000\n")
    assert not helper.wait_ready(root, timeout=0)
    role.write_text("host [device]\n")
    assert not helper.wait_ready(root, timeout=0)

    def enumerate_later():
        time.sleep(0.05)
        pdo.write_text("0002d12c\n")

    worker = threading.Thread(target=enumerate_later)
    worker.start()
    assert helper.wait_ready(root, timeout=1, interval=0.01)
    worker.join()
    assert helper.wait_ready(root, timeout=0)
    for value in ("", "malformed", "00000000\n"):
        pdo.write_text(value)
        assert not helper.wait_ready(root, timeout=0)
    pdo.unlink()
    start = time.monotonic()
    assert not helper.wait_ready(root, timeout=0.05, interval=0.01)
    assert time.monotonic() - start < 0.5
print("PASS: delayed PDO readiness, malformed/missing data and bounded non-PD wait")
