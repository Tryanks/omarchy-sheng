#!/usr/bin/env python3
"""Give boot-time Type-C enumeration time to finish before upstream MiPPS auth."""
import time
from pathlib import Path


def ready(sysfs):
    # A partner event can precede the port's data_role and charger PDO data.
    if not any((port / "data_role").is_file()
               for port in (sysfs / "class/typec").glob("port*")):
        return False
    for node in (sysfs / "devices/platform/pmic-glink").glob("*/xiaomi/pdo2"):
        try:
            value = node.read_text().strip()[:8]
            if len(value) == 8 and int(value, 16) != 0:
                return True
        except (OSError, ValueError):
            continue
    return False


def wait_ready(sysfs, timeout=20, interval=0.1):
    deadline = time.monotonic() + timeout
    while True:
        if ready(sysfs):
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(interval, remaining))


if __name__ == "__main__":
    # A non-PD charger may never publish PDOs. Bound the delay, then leave all
    # eligibility decisions, authentication and electrical policy upstream.
    result = wait_ready(Path("/sys"))
    print("MiPPS readiness: " + ("Type-C and PDO ready" if result else
                                "wait expired; deferring eligibility to upstream"))
