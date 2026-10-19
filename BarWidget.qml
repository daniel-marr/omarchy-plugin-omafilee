import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar button for the converter. The converter window itself is the plugin's
// keepLoaded panel entry point, so there is one window however many bars
// (monitors) show this button; every instance just toggles it.
BarWidget {
  id: root

  readonly property string pluginId: "daniel-marr.omafilee"
  readonly property string icon: String.fromCodePoint(0xF04E1)
  property bool converterOpen: false

  readonly property var pluginShell: root.bar && root.bar.shell ? root.bar.shell : null

  function sync() {
    root.converterOpen = root.pluginShell ? root.pluginShell.isPluginOpen(root.pluginId) === true : false
  }

  function toggle() {
    if (root.pluginShell) root.pluginShell.toggle(root.pluginId, "")
    else Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", root.pluginId, ""])
    Qt.callLater(root.sync)
  }

  // The shell exposes open state as a query, not a signal; a cheap poll keeps
  // the highlight right when the panel is toggled by IPC or another monitor.
  Timer {
    interval: 500
    repeat: true
    running: true
    onTriggered: root.sync()
  }

  Component.onCompleted: sync()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    // A touch larger than the bar's 13px default glyph.
    slotSize: Math.max(Style.bar.statusSlot, 24)
    opticalSize: 18
    fontSize: 16
    active: root.converterOpen
    activeColor: Commons.Color.accent
    tooltipText: root.converterOpen ? "Close Filee converter" : "Open Filee converter"
    onPressed: function(b) { if (b === Qt.LeftButton) root.toggle() }
  }
}
