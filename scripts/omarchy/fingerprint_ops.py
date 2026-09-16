"""Ordering of enrollment deletion and system authentication changes."""


def delete_finger(device, finger, authorize):
    if len(device.list_fingers()) <= 1:
        # A cancelled authorization must leave the saved fingerprint intact.
        authorize("disable")
    device.claim()
    try:
        device.delete_record(finger)
    finally:
        device.release()
    return device.list_fingers()
