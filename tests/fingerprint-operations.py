#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/omarchy"))
from fingerprint_ops import delete_finger


class Device:
    def __init__(self):
        self.fingers = ["right-index-finger"]
        self.events = []

    def list_fingers(self):
        return self.fingers[:]

    def claim(self):
        self.events.append("claim")

    def release(self):
        self.events.append("release")

    def delete_record(self, finger):
        self.events.append("delete")
        self.fingers.remove(finger)


device = Device()


def cancelled(action):
    device.events.append("authorize:" + action)
    raise PermissionError("user cancelled password prompt")


try:
    delete_finger(device, "right-index-finger", cancelled)
    raise AssertionError("cancelled authorization succeeded")
except PermissionError:
    assert device.fingers == ["right-index-finger"]
    assert device.events == ["authorize:disable"]

device.events.clear()
remaining = delete_finger(device, "right-index-finger", lambda a: device.events.append("authorize:" + a))
assert remaining == []
assert device.events == ["authorize:disable", "claim", "delete", "release"]
print("PASS: cancelling authentication never deletes a saved fingerprint")
