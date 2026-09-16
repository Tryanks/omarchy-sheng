import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Ui as Ui
import qs.Commons

Item {
  id: root
  property var shell: null
  property string view: "pen"
  property bool closingFromHost: false
  readonly property bool zh: Qt.locale().name.indexOf("zh") === 0
  readonly property string backend: "/usr/local/lib/omarchy-sheng/devices/"
  property var pen: ({})
  property bool penAlive: false
  property bool details: false
  property var fp: ({enrolled: [], total: 1, lockEnabled: false})
  property int fingerIndex: 0
  property string operation: ""
  property string feedback: ""
  property string outcome: "idle"
  property int stages: 0
  property bool confirmingDelete: false
  property string verifiedFinger: ""
  readonly property var fingers: ["right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger", "left-thumb", "left-index-finger", "left-middle-finger", "left-ring-finger", "left-little-finger"]
  readonly property string selectedFinger: fingers[fingerIndex]
  readonly property bool saved: (fp.enrolled || []).indexOf(selectedFinger) >= 0
  readonly property bool busy: fingerprint.running
  function tr(cn, en) { return zh ? cn : en }
  function fingerName(index) {
    var names = zh ? ["拇指", "食指", "中指", "无名指", "小指"] : ["Thumb", "Index", "Middle", "Ring", "Little"]
    return names[index % 5]
  }
  function fullFingerName(index) { return (index < 5 ? tr("右手", "Right ") : tr("左手", "Left ")) + fingerName(index) }
  function open(payload) {
    try { view = JSON.parse(payload || "{}").view === "fingerprint" ? "fingerprint" : "pen" } catch (_) { view = "pen" }
    window.visible = true
    if (view === "fingerprint" && !busy) start("status")
    Qt.callLater(function() { keys.forceActiveFocus() })
  }
  function close() {
    if (busy && (operation === "enroll" || operation === "verify")) fingerprint.signal(15)
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    confirmingDelete = false
  }
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("sheng.devices")
    else close()
  }
  function chooseView(value) {
    if (busy) return
    view = value
    confirmingDelete = false
    if (value === "fingerprint") start("status")
  }
  function start(action) {
    if (busy) return
    operation = action
    confirmingDelete = false
    stages = 0
    if (action !== "status") {
      outcome = "working"
      feedback = action === "delete" || action === "enable"
        ? tr("正在确认身份并保存设置…", "Authorizing and saving settings…")
        : tr("正在准备传感器…", "Preparing the sensor…")
    }
    fingerprint.command = ["python3", backend + "fingerprint_backend.py", action, selectedFinger]
    fingerprint.running = true
  }
  function receiveFingerprint(line) {
    var data
    try { data = JSON.parse(line) } catch (_) { return }
    if (data.enrolled !== undefined) fp = data
    if (data.event === "started") {
      feedback = operation === "enroll"
        ? tr("轻触电源键表面；采样后抬起，再换一个角度。", "Touch the power key. Lift between scans and vary the angle.")
        : tr("用所选手指轻触电源键表面。", "Touch the power key with the selected finger.")
    }
    if (data.event === "progress") {
      stages = data.stages || 0
      if (data.result === "enroll-stage-passed") feedback = tr("已采集。请抬起手指，稍微换个位置再贴上。", "Captured. Lift your finger, then touch a slightly different area.")
      else if (data.result === "verify-no-match") feedback = tr("未匹配，请使用所选的已录入手指重试。", "No match. Try the selected enrolled finger again.")
      else if (data.result.indexOf("retry") >= 0 || data.result.indexOf("short") >= 0 || data.result.indexOf("center") >= 0)
        feedback = tr("请抬起手指，让指腹充分接触后再试。", "Lift your finger, then place the pad fully on the sensor.")
    }
    if (data.event === "done") {
      outcome = data.ok ? "success" : "error"
      var messages = {
        "enroll-completed": tr("录入完成。下一步验证这枚指纹。", "Fingerprint saved. Verify it next."),
        "verify-match": tr("指纹匹配成功。", "Fingerprint matched."),
        "enabled": tr("锁屏指纹解锁已启用。", "Fingerprint unlocking is enabled."),
        "deleted": tr("已删除所选指纹。", "Fingerprint deleted."),
        "cancelled": tr("操作已取消。", "Operation cancelled."),
        "timeout": tr("等待超时，传感器已释放。准备好后可再试。", "Timed out. The sensor is released; try again when ready.")
      }
      feedback = messages[data.result] || tr("本次未完成，请稍后重试。", "Could not complete. Please try again.")
      if (data.result === "verify-match") verifiedFinger = selectedFinger
      if (data.result === "enroll-completed") stages = fp.total
      if (data.result === "deleted") verifiedFinger = ""
    }
    if (data.event === "error") {
      outcome = "error"
      feedback = data.message.indexOf("authorization-cancelled") >= 0
        ? tr("身份验证已取消，未删除指纹或更改解锁设置。", "Authorization cancelled. No fingerprint or unlock setting was changed.")
        : data.message.indexOf("AlreadyInUse") >= 0
          ? tr("传感器正被占用。请结束另一项指纹操作后重试。", "The sensor is in use. Finish the other fingerprint operation first.")
          : tr("指纹服务暂不可用。请稍后重试。", "Fingerprint service unavailable. Please try again.")
    }
  }

  Process {
    id: penProcess
    command: ["python3", root.backend + "pen_backend.py", "--watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try { root.pen = JSON.parse(line); root.penAlive = true; penTimeout.restart() } catch (_) {}
      }
    }
    onExited: { root.penAlive = false; penRestart.restart() }
  }
  Timer { id: penTimeout; interval: 15000; onTriggered: root.penAlive = false }
  Timer { id: penRestart; interval: 5000; onTriggered: penProcess.running = true }
  Process { id: pinch; onExited: function(code) { if (code !== 0) root.penAlive = false } }
  Process {
    id: fingerprint
    stdout: SplitParser { onRead: function(line) { root.receiveFingerprint(line) } }
    onExited: function(code) {
      if (code !== 0 && root.outcome === "working") {
        root.outcome = "error"
        root.feedback = root.tr("操作已结束。可以重新尝试。", "Operation ended. You can try again.")
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  component StatusRow: Row {
    property string label: ""
    property string value: ""
    property bool warning: false
    width: parent.width
    spacing: Style.space(12)
    Label { width: parent.width * 0.36; text: parent.label; color: Color.muted }
    Label { width: parent.width * 0.64 - parent.spacing; text: parent.value; horizontalAlignment: Text.AlignRight; color: parent.warning ? Color.urgent : Color.foreground }
  }

  FloatingWindow {
    id: window
    visible: false
    title: "Omarchy · Sheng"
    color: Color.popups.background
    implicitWidth: Style.space(520)
    implicitHeight: Math.min(Style.space(740), screen ? screen.height - Style.space(90) : 740)
    minimumSize: Qt.size(Style.space(420), Style.space(500))
    onVisibleChanged: if (!visible && !root.closingFromHost) root.requestClose()

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.requestClose()
      Controls.ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: Style.space(26)
        clip: true
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        Column {
          width: scroll.availableWidth
          spacing: Style.space(22)
          Ui.PanelHero {
            title: root.tr("设备设置", "Device settings")
            meta: "XIAOMI PAD 6S PRO"
            iconComponent: Label { text: "󰓶"; font.pixelSize: Style.font.displayLarge; color: Color.accent }
            trailingControl: Ui.PanelActionButton {
              iconText: "󰅖"; size: Style.space(34); focusable: true
              tooltipText: root.tr("关闭", "Close")
              onClicked: root.requestClose()
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Ui.Button {
              width: (parent.width - parent.spacing) / 2
              text: root.tr("手写笔", "Stylus"); iconText: "󰏪"
              selected: root.view === "pen"; bordered: true; focusable: true; enabled: !root.busy
              verticalPadding: Style.space(12)
              onClicked: root.chooseView("pen")
            }
            Ui.Button {
              width: (parent.width - parent.spacing) / 2
              text: root.tr("指纹", "Fingerprint"); iconText: "󰈷"
              selected: root.view === "fingerprint"; bordered: true; focusable: true; enabled: !root.busy
              verticalPadding: Style.space(12)
              onClicked: root.chooseView("fingerprint")
            }
          }

          Column {
            visible: root.view === "pen"
            width: parent.width
            spacing: Style.space(20)
            Ui.PanelSectionHeader { text: root.pen.name || root.tr("小米手写笔", "Xiaomi stylus") }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Label {
                text: root.penAlive && root.pen.battery !== null && root.pen.battery !== undefined ? root.pen.battery : "—"
                font.pixelSize: Style.font.displayLarge * 2.8
                color: Color.accent
              }
              Column {
                anchors.bottom: parent.bottom
                bottomPadding: Style.space(16)
                spacing: Style.space(5)
                Label { text: "%"; font.pixelSize: Style.font.display }
                Label { text: root.tr("电池电量", "BATTERY"); color: Color.muted; font.pixelSize: Style.font.caption }
              }
              Item { width: Math.max(10, parent.width - parent.children[0].width - parent.children[1].width - Style.space(90)); height: 1 }
              Label { text: "󰏪"; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Style.font.displayLarge * 1.8; color: Color.muted }
            }
            Rectangle {
              width: parent.width; height: Style.space(4); color: Util.alpha(Color.foreground, 0.12)
              Rectangle { height: parent.height; width: parent.width * (root.penAlive ? Math.max(0, root.pen.battery || 0) / 100 : 0); color: Color.accent
                Behavior on width { NumberAnimation { duration: 180 } }
              }
            }
            Column {
              width: parent.width; spacing: Style.space(16)
              StatusRow {
                label: root.tr("放置状态", "Placement")
                value: !root.penAlive || !root.pen.valid ? root.tr("暂不可用", "Unavailable") : root.pen.misplaced ? root.tr("请重新放置", "Reseat the pen") : root.pen.docked ? root.tr("已吸附", "Docked") : root.tr("已取下", "Detached")
                warning: root.pen.misplaced || false
              }
              StatusRow {
                label: root.tr("蓝牙", "Bluetooth")
                value: !root.penAlive ? "—" : root.pen.connected ? root.tr("已连接", "Connected") : !root.pen.powered ? root.tr("未开启", "Off") : root.pen.paired ? root.tr("已配对 · 未连接", "Paired · Disconnected") : root.tr("等待连接", "Not connected")
              }
            }
            Ui.PanelSeparator {}
            Label {
              width: parent.width
              color: root.pen.misplaced ? Color.urgent : Color.muted
              text: !root.penAlive ? root.tr("正在读取手写笔状态…", "Reading stylus status…")
                : root.pen.misplaced ? root.tr("请将手写笔重新贴合平板的磁吸充电位置。", "Reseat the stylus on the tablet’s magnetic charging edge.")
                : root.pen.battery === null ? root.tr("将手写笔吸附到充电位置，等待设备上报电量。", "Dock the stylus to receive its battery level.")
                : root.pen.docked ? root.tr("手写笔已放回磁吸位置。电量会随设备上报自动更新。", "The pen is docked. Battery readings update automatically.")
                : root.tr("取下即可书写；使用完毕后吸附回平板。", "Ready to write. Dock the pen when you’re done.")
            }
            Column {
              visible: root.pen.focusPro || false
              width: parent.width; spacing: Style.space(12)
              Ui.PanelSectionHeader { text: root.tr("轻捏触发力度", "PINCH ACTIVATION FORCE") }
              Row {
                width: parent.width; spacing: Style.space(6)
                Repeater {
                  model: 5
                  Ui.Button {
                    required property int index
                    width: (parent.width - parent.spacing * 4) / 5
                    text: String(index + 1); selected: root.pen.pinchLevel === index + 1
                    bordered: true; focusable: true; verticalPadding: Style.space(10)
                    enabled: !!root.pen.settingsReady && !pinch.running
                    onClicked: { pinch.command = ["python3", root.backend + "pen_backend.py", "--pinch", String(index + 1)]; pinch.running = true }
                  }
                }
              }
              Label { width: parent.width; color: Color.muted; text: !root.pen.settingsReady ? root.tr("连接并完成手写笔初始化后即可调整。", "Available once the pen is connected and ready.") : root.pen.pinchApplied ? root.tr("力度已应用 · 1 最轻，5 最重", "Applied · 1 lightest, 5 firmest") : root.tr("正在应用力度…", "Applying force setting…") }
            }
            Row {
              width: parent.width; spacing: Style.space(8)
              Ui.Button { text: root.tr("蓝牙设置", "Bluetooth"); iconText: "󰂯"; bordered: true; focusable: true; verticalPadding: Style.space(10); onClicked: { root.requestClose(); Quickshell.execDetached(["omarchy-shell", "omarchy.bluetooth", "open"]) } }
              Ui.Button { text: root.details ? root.tr("收起详情", "Less detail") : root.tr("设备详情", "Device details"); iconText: root.details ? "󰅃" : "󰅀"; focusable: true; verticalPadding: Style.space(10); onClicked: root.details = !root.details }
            }
            Column {
              visible: root.details; width: parent.width; spacing: Style.space(12)
              Ui.PanelSeparator {}
              StatusRow { label: root.tr("设备地址", "Address"); value: root.pen.address || "—" }
              StatusRow { label: root.tr("固件 / 软件", "Firmware / software"); value: (root.pen.firmware || "—") + " / " + (root.pen.software || "—") }
              StatusRow { label: "Hall 3 / 4"; value: String(root.pen.pen_hall3 ?? "—") + " / " + String(root.pen.pen_hall4 ?? "—") }
              StatusRow { label: "TX status"; value: String(root.pen.pen_tx_ss ?? "—") }
              StatusRow { label: "TX mA / mV"; value: String(root.pen.tx_iout ?? "—") + " / " + String(root.pen.tx_vout ?? "—") }
              Label { width: parent.width; text: root.tr("手写笔需要屏幕设为 60 Hz 或 120 Hz。", "The stylus requires a 60 Hz or 120 Hz display mode.") }
            }
          }

          Column {
            visible: root.view === "fingerprint"
            width: parent.width; spacing: Style.space(18)
            Ui.PanelHero {
              title: root.tr("电源键指纹", "Power-key fingerprint")
              meta: root.fp.sensor || root.tr("正在检测传感器", "Detecting sensor")
              detail: root.fp.lockEnabled ? root.tr("已启用", "Enabled") : root.tr("未启用", "Not enabled")
              iconComponent: Label { text: "󰈷"; font.pixelSize: Style.font.displayLarge * 1.5; color: Color.accent }
            }
            Label { width: parent.width; color: Color.muted; text: root.tr("轻触电源键表面，不要按下。指纹保存在本机，密码解锁始终可用。", "Touch the power key without pressing it. Fingerprints stay on this device; password unlock remains available.") }
            Ui.PanelSeparator {}
            Column {
              width: parent.width; spacing: Style.space(8)
              Repeater {
                model: 2
                Column {
                  required property int index
                  property int hand: index
                  width: parent.width; spacing: Style.space(8)
                  Ui.PanelSectionHeader { text: parent.hand === 0 ? root.tr("右手", "RIGHT HAND") : root.tr("左手", "LEFT HAND") }
                  Row {
                    width: parent.width; spacing: Style.space(6)
                    Repeater {
                      model: 5
                      Ui.Button {
                        required property int index
                        readonly property int finger: parent.parent.hand * 5 + index
                        width: (parent.width - parent.spacing * 4) / 5
                        text: root.fingerName(finger) + ((root.fp.enrolled || []).indexOf(root.fingers[finger]) >= 0 ? " ·" : "")
                        selected: root.fingerIndex === finger; bordered: true; focusable: true; enabled: !root.busy
                        verticalPadding: Style.space(12); horizontalPadding: Style.space(2)
                        onClicked: { root.fingerIndex = finger; root.confirmingDelete = false; root.feedback = ""; root.outcome = "idle"; root.stages = 0 }
                      }
                    }
                  }
                }
              }
            }
            StatusRow { label: root.fullFingerName(root.fingerIndex); value: root.saved ? root.tr("已录入", "Enrolled") : root.tr("尚未录入", "Not enrolled") }
            Ui.BorderSurface {
              width: parent.width
              implicitHeight: feedbackContent.implicitHeight + Style.space(28)
              color: Style.normalFillFor(Color.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
              radius: Style.cornerRadius
              Column {
                id: feedbackContent
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Style.space(14); spacing: Style.space(10)
                Label {
                  width: parent.width; font.bold: true
                  color: root.outcome === "error" ? Color.urgent : Color.accent
                  text: root.busy && root.operation !== "status" ? root.tr("正在处理", "In progress") : root.outcome === "success" ? root.tr("已完成", "Complete") : root.outcome === "error" ? root.tr("请再试一次", "Try again") : root.tr("准备就绪", "Ready")
                }
                Label { width: parent.width; text: root.feedback || (root.saved ? root.tr("可以验证这枚指纹，或删除后重新录入。", "Verify this fingerprint, or remove it to enroll again.") : root.tr("选择手指后开始录入。每次有效采集都会显示进度。", "Choose a finger to enroll. Each successful scan advances the progress.")) }
                Row {
                  visible: root.operation === "enroll" && (root.busy || root.stages > 0)
                  width: parent.width; spacing: Style.space(4)
                  Repeater {
                    model: Math.max(1, root.fp.total || 1)
                    Rectangle { required property int index; width: (parent.width - (Math.max(1, root.fp.total || 1) - 1) * parent.spacing) / Math.max(1, root.fp.total || 1); height: Style.space(4); color: index < root.stages ? Color.accent : Util.alpha(Color.foreground, 0.15) }
                  }
                }
                Label { visible: root.operation === "enroll" && root.busy; text: root.stages + " / " + (root.fp.total || 1); color: Color.muted; font.pixelSize: Style.font.caption }
              }
            }
            Row {
              width: parent.width; spacing: Style.space(8)
              Ui.Button {
                text: root.saved ? root.tr("验证指纹", "Verify fingerprint") : root.tr("开始录入", "Enroll fingerprint")
                iconText: "󰈷"; bordered: true; focusable: true; enabled: !root.busy && !!root.fp.sensor
                verticalPadding: Style.space(12)
                onClicked: root.start(root.saved ? "verify" : "enroll")
              }
              Ui.Button {
                visible: root.busy && (root.operation === "enroll" || root.operation === "verify")
                text: root.tr("取消", "Cancel"); focusable: true; verticalPadding: Style.space(12)
                onClicked: fingerprint.signal(15)
              }
              Ui.Button {
                visible: root.saved && !root.busy
                text: root.tr("删除", "Remove"); focusable: true; verticalPadding: Style.space(12)
                onClicked: root.confirmingDelete = !root.confirmingDelete
              }
              Ui.Button {
                visible: !root.fp.sensor && !root.busy
                text: root.tr("重新检测", "Retry detection"); focusable: true; verticalPadding: Style.space(12)
                onClicked: root.start("status")
              }
            }
            Column {
              visible: root.confirmingDelete; width: parent.width; spacing: Style.space(10)
              Label { width: parent.width; color: Color.urgent; text: root.tr("删除", "Remove ") + root.fullFingerName(root.fingerIndex) + root.tr("的指纹？删除最后一枚时会先验证身份。", "? Removing the last fingerprint requires authorization first.") }
              Row {
                spacing: Style.space(8)
                Ui.Button { text: root.tr("确认删除", "Remove fingerprint"); foreground: Color.urgent; bordered: true; focusable: true; enabled: !root.busy; onClicked: root.start("delete") }
                Ui.Button { text: root.tr("保留", "Keep"); focusable: true; onClicked: root.confirmingDelete = false }
              }
            }
            Ui.Button {
              visible: !root.fp.lockEnabled && root.verifiedFinger === root.selectedFinger && root.saved
              text: root.tr("启用锁屏指纹解锁", "Enable fingerprint unlocking")
              iconText: "󰌾"; bordered: true; focusable: true; enabled: !root.busy
              verticalPadding: Style.space(12)
              onClicked: root.start("enable")
            }
          }
        }
      }
    }
  }
}
