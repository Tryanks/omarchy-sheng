#!/usr/bin/env python3
"""Native GTK settings for the device's existing fprintd implementation."""
import getpass
import subprocess
import threading

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk
from fingerprint_ops import delete_finger

FINGERS = [f"{hand}-{finger}" for hand in ("right", "left")
           for finger in ("index-finger", "thumb", "middle-finger", "ring-finger", "little-finger")]
LABELS = [f"{hand}{finger}" for hand in ("右手", "左手")
          for finger in ("食指", "拇指", "中指", "无名指", "小指")]


class FingerprintApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.omarchy.sheng.Fingerprint")
        self.device = None
        self.operation = None
        self.busy = False
        self.claimed = False
        self.stages = 0
        self.enrolled = []
        self.connect("activate", self.activate)

    def activate(self, _app):
        if self.get_active_window():
            self.get_active_window().present()
            return
        self.window = Gtk.ApplicationWindow(application=self, title="指纹设置")
        self.window.set_default_size(560, 460)
        self.window.connect("close-request", self.close)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                      margin_top=24, margin_bottom=24, margin_start=24, margin_end=24)
        self.window.set_child(box)
        title = Gtk.Label(label="电源键指纹识别", xalign=0)
        title.add_css_class("title-1")
        box.append(title)
        box.append(Gtk.Label(label="轻触电源键的表面，不要按下或长按。\n密码解锁始终保留；指纹仅在本机保存。", xalign=0, wrap=True))
        self.reader = Gtk.Label(label="正在检测传感器…", xalign=0)
        box.append(self.reader)
        self.saved = Gtk.Label(label="", xalign=0, wrap=True)
        box.append(self.saved)
        self.choice = Gtk.DropDown.new_from_strings(LABELS)
        box.append(self.choice)
        row = Gtk.Box(spacing=10)
        box.append(row)
        self.buttons = []
        for label, callback in [("录入指纹", self.enroll), ("验证指纹", self.verify), ("删除所选指纹", self.delete)]:
            button = Gtk.Button(label=label)
            button.connect("clicked", callback)
            row.append(button)
            self.buttons.append(button)
        self.progress = Gtk.ProgressBar(show_text=True)
        box.append(self.progress)
        self.status = Gtk.Label(label="检测完成后，点击“录入指纹”开始。", xalign=0, wrap=True)
        self.status.set_selectable(True)
        box.append(self.status)
        self.cancel = Gtk.Button(label="取消当前操作")
        self.cancel.connect("clicked", lambda *_: self.stop("操作已取消，未启用新的指纹解锁。"))
        self.cancel.set_sensitive(False)
        box.append(self.cancel)
        self.set_busy(True)
        self.window.present()
        self.work(self.connect_device, self.connected)

    def work(self, function, done):
        def worker():
            try:
                result, error = function(), None
            except Exception as exc:
                result, error = None, str(exc)
            GLib.idle_add(done, result, error)
        threading.Thread(target=worker, daemon=True).start()

    def proxy(self, path, interface):
        return Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SYSTEM, Gio.DBusProxyFlags.NONE,
                                             None, "net.reactivated.Fprint", path, interface, None)

    def call(self, method, params=None):
        return self.device.call_sync(method, params, Gio.DBusCallFlags.NONE, 30000, None).unpack()

    def connect_device(self):
        manager = self.proxy("/net/reactivated/Fprint/Manager", "net.reactivated.Fprint.Manager")
        path = manager.call_sync("GetDefaultDevice", None, Gio.DBusCallFlags.NONE, 10000, None).unpack()[0]
        self.device = self.proxy(path, "net.reactivated.Fprint.Device")
        self.device.connect("g-signal", self.signal)
        return self.list_fingers()

    def list_fingers(self):
        try:
            return self.call("ListEnrolledFingers", GLib.Variant("(s)", (getpass.getuser(),)))[0]
        except GLib.Error as error:
            if "NoEnrolledPrints" in str(error):
                return []
            raise

    def connected(self, fingers, error):
        self.set_busy(False)
        if error:
            self.status.set_text("无法连接指纹服务：" + error)
            for button in self.buttons:
                button.set_sensitive(False)
            return
        self.reader.set_text("传感器：" + self.device.get_cached_property("name").unpack())
        self.update_fingers(fingers)

    def update_fingers(self, fingers):
        self.enrolled = fingers
        names = [LABELS[FINGERS.index(f)] if f in FINGERS else f for f in fingers]
        self.saved.set_text("已录入：" + ("、".join(names) if names else "无"))

    def set_busy(self, value):
        self.busy = value
        for button in self.buttons:
            button.set_sensitive(not value)
        self.choice.set_sensitive(not value)
        self.cancel.set_sensitive(bool(self.operation) and not value)

    def selected(self):
        return FINGERS[self.choice.get_selected()]

    def authorize(self, action):
        subprocess.run(["pkexec", "/usr/local/lib/omarchy-sheng/fingerprint-auth.py", action], check=True)

    def claim(self):
        self.call("Claim", GLib.Variant("(s)", (getpass.getuser(),)))

    def release(self):
        self.call("Release")

    def delete_record(self, finger):
        self.call("DeleteEnrolledFinger", GLib.Variant("(s)", (finger,)))

    def start(self, operation):
        if self.busy or self.operation:
            return
        self.operation = operation
        self.stages = 0
        self.progress.set_fraction(0)
        self.set_busy(True)
        finger = self.selected()
        self.status.set_text("正在准备传感器…如弹出身份验证，请输入登录密码。")
        def start_device():
            self.call("Claim", GLib.Variant("(s)", (getpass.getuser(),)))
            self.claimed = True
            self.call(operation + "Start", GLib.Variant("(s)", (finger,)))
        def started(_result, error):
            if error:
                self.stop("无法开始：" + error)
                return
            self.busy = False
            self.cancel.set_sensitive(True)
            self.status.set_text("请轻触电源键。每次采样后抬起手指，稍微调整指腹位置再贴上。" if operation == "Enroll" else "请用刚才录入的手指轻触电源键。")
        self.work(start_device, started)

    def enroll(self, *_):
        if self.selected() in self.enrolled:
            self.status.set_text("这个手指已有记录。请先验证，或删除后重新录入。")
            return
        self.start("Enroll")

    def verify(self, *_):
        if self.selected() not in self.enrolled:
            self.status.set_text("请先选择一个已录入的手指。")
            return
        self.start("Verify")

    def signal(self, _proxy, _sender, name, parameters):
        GLib.idle_add(self.handle_signal, name, parameters.unpack())

    def handle_signal(self, name, values):
        if not self.operation or name != self.operation + "Status":
            return
        result, done = values
        if result == "enroll-stage-passed":
            self.stages += 1
            total = self.device.get_cached_property("num-enroll-stages").unpack()
            self.progress.set_fraction(min(self.stages / max(total, 1), 1))
            self.progress.set_text(f"已完成 {self.stages} / {total} 次有效采样")
            self.status.set_text("已采样。请抬起手指，换一点位置后再次轻触电源键。")
        elif result == "enroll-completed":
            self.progress.set_fraction(1)
            self.stop("录入完成。请选择“验证指纹”；验证成功后才能启用锁屏解锁。")
        elif result == "verify-match":
            self.stop("指纹匹配成功，正在启用锁屏指纹解锁…", enable=True)
        elif done:
            self.stop("操作未成功：" + result + "。可以重试，密码解锁不受影响。")
        else:
            messages = {"enroll-retry-scan": "请抬起手指后重新轻触。",
                        "enroll-remove-and-retry": "请先移开手指，再重新轻触。",
                        "verify-no-match": "指纹不匹配，请换回录入的手指。"}
            self.status.set_text(messages.get(result, "请调整手指后重试：" + result))

    def stop(self, message, enable=False, closing=False):
        operation, self.operation = self.operation, None
        self.set_busy(True)
        self.cancel.set_sensitive(False)
        self.status.set_text(message)
        def cleanup():
            try:
                if operation and self.claimed:
                    try:
                        self.call(operation + "Stop")
                    except GLib.Error:
                        pass
            finally:
                if self.claimed:
                    self.call("Release")
                    self.claimed = False
            if enable:
                self.authorize("enable")
            return self.list_fingers() if self.device else []
        def stopped(fingers, error):
            self.set_busy(False)
            if closing:
                self.window.destroy()
                return
            self.status.set_text("操作失败：" + error if error else ("验证成功，锁屏指纹解锁已启用。密码解锁仍然可用。" if enable else message))
            if not error:
                self.update_fingers(fingers)
        self.work(cleanup, stopped)

    def delete(self, *_):
        if self.selected() not in self.enrolled:
            self.status.set_text("所选手指没有已保存的指纹。")
            return
        dialog = Gtk.MessageDialog(transient_for=self.window, modal=True,
                                   text="删除所选指纹？", secondary_text="删除后可重新录入。密码解锁不受影响。",
                                   buttons=Gtk.ButtonsType.OK_CANCEL)
        def respond(dlg, response):
            dlg.destroy()
            if response != Gtk.ResponseType.OK:
                return
            self.set_busy(True)
            finger = self.selected()
            def remove():
                return delete_finger(self, finger, self.authorize)
            def removed(fingers, error):
                self.set_busy(False)
                self.status.set_text("删除失败：" + error if error else "已删除所选指纹。")
                if not error:
                    self.update_fingers(fingers)
            self.work(remove, removed)
        dialog.connect("response", respond)
        dialog.present()

    def close(self, *_):
        if self.busy:
            self.status.set_text("正在处理请求，请稍候完成或取消。")
            return True
        if self.operation or self.claimed:
            self.stop("正在取消…", closing=True)
            return True
        return False


if __name__ == "__main__":
    FingerprintApp().run()
