#!/usr/bin/python3
"""Privileged lock-only PAM setup, authorized by pkexec; never stores biometric data."""
import os
import pwd
import sys
from pathlib import Path
from gi.repository import Gio, GLib

if os.geteuid() != 0 or len(sys.argv) != 2 or sys.argv[1] not in ("enable", "disable"):
    sys.exit("Use pkexec fingerprint-auth.py enable|disable")
uid = int(os.environ.get("PKEXEC_UID", "0"))
if uid == 0:
    sys.exit("An authenticated desktop user is required")
user = pwd.getpwuid(uid).pw_name
pam = Path("/etc/pam.d/omarchy-lock-fingerprint")
marker = Path("/var/lib/omarchy-sheng/fingerprint-lock-enabled")
if sys.argv[1] == "enable":
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    path = bus.call_sync("net.reactivated.Fprint", "/net/reactivated/Fprint/Manager",
                         "net.reactivated.Fprint.Manager", "GetDefaultDevice", None,
                         GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 10000, None).unpack()[0]
    fingers = bus.call_sync("net.reactivated.Fprint", path, "net.reactivated.Fprint.Device",
                           "ListEnrolledFingers", GLib.Variant("(s)", (user,)),
                           GLib.VariantType.new("(as)"), Gio.DBusCallFlags.NONE, 10000, None).unpack()[0]
    if not fingers:
        sys.exit("Enroll and verify a fingerprint first")
    if not Path("/etc/pam.d/omarchy-lock-password").is_file():
        sys.exit("Password fallback must be configured first")
    pam.write_text("#%PAM-1.0\nauth required pam_fprintd.so\naccount include system-local-login\n")
    pam.chmod(0o644)
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text("enabled\n")
    marker.chmod(0o644)
else:
    pam.unlink(missing_ok=True)
    marker.unlink(missing_ok=True)
