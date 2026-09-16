import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "sheng.devices"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏪"
    slotSize: Style.bar.statusSlot
    tooltipText: Qt.locale().name.indexOf("zh") === 0 ? "手写笔状态" : "Stylus status"
    onPressed: Quickshell.execDetached(["omarchy-shell", "shell", "summon", "sheng.devices", '{"view":"pen"}'])
  }
}
