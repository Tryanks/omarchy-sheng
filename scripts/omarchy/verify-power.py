#!/usr/bin/env python3
"""Check the image defaults without locking, suspending or running charger mode."""
import configparser
import sys
from pathlib import Path


def verify(root: Path):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    pam = root / "etc/pam.d/omarchy-lock-password"
    require(pam.is_file() and "pam_unix.so" in pam.read_text(), "missing password lock PAM")
    fingerprint = root / "etc/pam.d/omarchy-lock-fingerprint"
    if fingerprint.exists():
        require((root / "var/lib/omarchy-sheng/fingerprint-lock-enabled").is_file(), "fingerprint enabled without user setup")
        require("auth required pam_fprintd.so" in fingerprint.read_text(), "fingerprint PAM must require authentication")
    for filename, section, expected in [
        ("etc/systemd/logind.conf.d/60-omarchy-sheng.conf", "Login", {
            "HandleLidSwitch": "ignore", "HandleLidSwitchExternalPower": "ignore",
            "HandleLidSwitchDocked": "ignore", "IdleAction": "ignore"}),
        ("etc/systemd/sleep.conf.d/60-omarchy-sheng.conf", "Sleep", {
            "AllowSuspend": "no", "AllowHibernation": "no", "AllowHybridSleep": "no",
            "AllowSuspendThenHibernate": "no"}),
        ("etc/UPower/UPower.conf", "UPower", {
            "CriticalPowerAction": "PowerOff", "UsePercentageForPolicy": "true",
            "PercentageLow": "20.0", "PercentageCritical": "10.0", "PercentageAction": "5.0"}),
    ]:
        config = configparser.ConfigParser()
        config.read(root / filename)
        for key, value in expected.items():
            require(config.get(section, key, fallback=None) == value, f"{filename}: {key} must be {value}")
    service = "usr/lib/systemd/system/xiaomi-charger-mode.service"
    link = root / "etc/systemd/system/sysinit.target.wants/xiaomi-charger-mode.service"
    require((root / service).is_file(), "charger service missing")
    require(link.is_symlink() and str(link.readlink()) == "/" + service, "charger service not enabled")
    require("ConditionKernelCommandLine=androidboot.mode=charger" in (root / service).read_text(), "charger boot guard missing")
    require((root / "usr/local/lib/omarchy-sheng/lid.sh").is_file(), "lid helper missing")
    require((root / "usr/local/lib/omarchy-sheng/wait-charger.py").is_file(), "charger readiness helper missing")
    require((root / "etc/systemd/system/xiaomi-mipps-auth.service.d/60-sheng-readiness.conf").is_file(), "charger readiness ordering missing")
    require((root / "usr/local/share/applications/omarchy-sheng-fingerprint.desktop").is_file(), "fingerprint settings entry missing")
    require((root / "usr/local/lib/omarchy-sheng/fingerprint-auth.py").is_file(), "fingerprint authentication helper missing")
    require((root / "usr/local/lib/omarchy-sheng/fingerprint_ops.py").is_file(), "fingerprint operations module missing")
    require((root / "etc/polkit-1/rules.d/00-omarchy-sheng-admin.rules").is_file(), "active administrator identity rule missing")
    print("Sheng power and lock defaults verified (no hardware actions performed).")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1] if len(sys.argv) > 1 else "/"))
    except ValueError as error:
        sys.exit(str(error))
