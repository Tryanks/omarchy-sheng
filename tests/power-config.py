#!/usr/bin/env python3
"""Regression checks for missing lock/charger provisioning and lid-only actions."""
import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[1] / "scripts/omarchy"


def module(name):
    spec = importlib.util.spec_from_file_location(name, BASE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


configure = module("configure-power").configure
verify = module("verify-power").verify

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    service = root / "usr/lib/systemd/system/xiaomi-charger-mode.service"
    service.parent.mkdir(parents=True)
    service.write_text("[Unit]\nConditionKernelCommandLine=androidboot.mode=charger\n")
    try:
        verify(root)
        raise AssertionError("unconfigured image incorrectly passed")
    except ValueError as error:
        assert "missing password lock PAM" in str(error)
    configure(root)
    configure(root)  # Repeat installation must be safe and deterministic.
    verify(root)
    for relative in ("etc/pam.d/omarchy-lock-password",
                     "etc/systemd/system/sysinit.target.wants/xiaomi-charger-mode.service"):
        path = root / relative
        path.unlink()
        try:
            verify(root)
            raise AssertionError(f"missing {relative} incorrectly passed")
        except ValueError:
            pass
        configure(root)

    # Exercise the actual lid handler. No process may request system suspend.
    bindir = root / "bin"
    bindir.mkdir()
    log = root / "actions"
    for name, body in {
        "timeout": 'shift; exec "$@"',
        "busctl": 'echo "b $TEST_LID"',
        "sleep": ":",
        "omarchy-system-sleep-lock": 'echo lock >> "$TEST_LOG"; exit "${TEST_LOCK_EXIT:-0}"',
        "omarchy-brightness-keyboard": 'echo "keyboard $*" >> "$TEST_LOG"',
        "omarchy-brightness-display": 'echo "display $*" >> "$TEST_LOG"',
        "omarchy-system-wake": 'echo wake >> "$TEST_LOG"',
    }.items():
        path = bindir / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
    env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}", TEST_LOG=str(log))
    for action, state, code, expected in [
        ("close", "true", "0", "lock\nkeyboard off\ndisplay off\n"),
        ("open", "false", "0", "wake\n"),
        ("close", "false", "0", ""),  # Folding back is not closing the lid.
        ("close", "true", "1", "lock\n"),  # Never claim blanking is a secure lock.
    ]:
        log.write_text("")
        result = subprocess.run(["bash", str(BASE / "power/lid.sh"), action],
                                env=dict(env, TEST_LID=state, TEST_LOCK_EXIT=code))
        assert result.returncode == int(code)
        assert log.read_text() == expected, log.read_text()
print("PASS: provisioning omissions detected; lid locks before blanking, never suspends or unlocks")
