#!/usr/bin/env python3
"""Install sheng power defaults into a live system or mounted image; never start services."""
import re
import shutil
import sys
from pathlib import Path


def configure(root: Path):
    source = Path(__file__).resolve().parent
    files = {
        "lock-password.pam": "etc/pam.d/omarchy-lock-password",
        "logind.conf": "etc/systemd/logind.conf.d/60-omarchy-sheng.conf",
        "sleep.conf": "etc/systemd/sleep.conf.d/60-omarchy-sheng.conf",
        "lid.sh": "usr/local/lib/omarchy-sheng/lid.sh",
        "polkit-admin.rules": "etc/polkit-1/rules.d/00-omarchy-sheng-admin.rules",
        "wait-charger.py": "usr/local/lib/omarchy-sheng/wait-charger.py",
        "mipps-ready.conf": "etc/systemd/system/xiaomi-mipps-auth.service.d/60-sheng-readiness.conf",
    }
    charger = root / "usr/lib/systemd/system/xiaomi-charger-mode.service"
    if not charger.is_file():
        raise SystemExit("xiaomi-charger-mode must be installed before power configuration")
    for name, target in files.items():
        dest = root / target
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / "power" / name, dest)
        dest.chmod(0o755 if name.endswith(".sh") else 0o644)

    # Keep an explicitly enabled fingerprint, but remove the upstream false
    # positive: its grep for 'finger' also matches 'no fingers enrolled'.
    fingerprint = root / "etc/pam.d/omarchy-lock-fingerprint"
    if fingerprint.exists() and not (root / "var/lib/omarchy-sheng/fingerprint-lock-enabled").exists():
        saved = root / "var/lib/omarchy-sheng/disabled-pam/omarchy-lock-fingerprint"
        saved.parent.mkdir(parents=True, exist_ok=True)
        fingerprint.replace(saved)

    for name, target in {
        "fingerprint-ui.py": "usr/local/lib/omarchy-sheng/fingerprint-ui.py",
        "fingerprint-auth.py": "usr/local/lib/omarchy-sheng/fingerprint-auth.py",
        "fingerprint_ops.py": "usr/local/lib/omarchy-sheng/fingerprint_ops.py",
        "fingerprint-launch.sh": "usr/local/bin/omarchy-setup-security-fingerprint",
        "fingerprint.desktop": "usr/local/share/applications/omarchy-sheng-fingerprint.desktop",
    }.items():
        dest = root / target
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, dest)
        dest.chmod(0o644 if name.endswith(".desktop") else 0o755)

    upower = root / "etc/UPower/UPower.conf"
    text = upower.read_text() if upower.exists() else "[UPower]\n"
    for key, value in {
        "UsePercentageForPolicy": "true",
        "PercentageLow": "20.0",
        "PercentageCritical": "10.0",
        "PercentageAction": "5.0",
        "CriticalPowerAction": "PowerOff",
    }.items():
        pattern = rf"(?m)^{key}=.*$"
        if re.search(pattern, text):
            text = re.sub(pattern, f"{key}={value}", text)
        else:
            text = text.replace("[UPower]", f"[UPower]\n{key}={value}", 1)
    upower.parent.mkdir(parents=True, exist_ok=True)
    upower.write_text(text)
    upower.chmod(0o644)

    # Equivalent to systemctl enable, with no connection to the host manager.
    link = root / "etc/systemd/system/sysinit.target.wants/xiaomi-charger-mode.service"
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink():
        link.unlink()
    link.symlink_to("/usr/lib/systemd/system/xiaomi-charger-mode.service")
    print("Configured password lock, lid-only blanking, no suspend, 5% poweroff, charger boot.")


if __name__ == "__main__":
    configure(Path(sys.argv[1] if len(sys.argv) > 1 else "/").resolve())
