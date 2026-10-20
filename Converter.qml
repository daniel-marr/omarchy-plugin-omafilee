import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "FileeModel.js" as Model

// Filee's donut, drawn in the Omarchy theme. Drop files on the middle and the
// conversions for that file type fan out around it; click one to convert. Or
// drop straight onto a slice to convert in one go, as in Filee itself.
//
// A real (xdg-toplevel) window titled "OmaFilee", so Hyprland moves it with
// its own Super+drag. The plugin registers its own Hyprland rules at runtime
// (see hyprLua): float and pin the window, place it top-right under the bar
// each time it opens, and raise it above other windows. It closes only from
// the bar button (or `omarchy-shell shell hide daniel-marr.omafilee`).
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // Catalogue from `filee formats` / `filee presets`, loaded once, plus the
  // user's own donuts from the Filee app when they exist.
  property var formats: ({})
  property var extMap: ({})
  property var presets: []
  property var userProfiles: null
  property bool catalogReady: false
  property string catalogError: ""

  property var files: []
  property var dragFiles: []
  property bool dragActive: false
  property var hover: ({ kind: "outside", index: -1 })

  property bool busy: false
  property var activeSlice: null
  property var result: null
  property var pendingRequest: null

  readonly property real outerRadius: Style.space(150)
  readonly property real innerRadius: outerRadius * 0.42
  readonly property real popOut: Style.space(7)
  readonly property real shadowMargin: Style.space(16)
  readonly property real side: 2 * (outerRadius + popOut + shadowMargin)

  readonly property color fg: Commons.Color.popups.text
  // Opaque: the theme's popup background can carry alpha.
  readonly property color bg: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 1)
  readonly property color border: Commons.Color.popups.border
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Style.font.family

  readonly property var shownFiles: dragActive && dragFiles.length > 0 ? dragFiles : files
  readonly property var profile: shownFiles.length === 0 || !catalogReady ? null
    : (userProfiles ? Model.selectUserProfile(userProfiles, shownFiles) : Model.selectDefaultProfile(shownFiles, formats))
  readonly property var slices: profile ? Model.slicesFor(profile, presets) : []
  readonly property int hoverIndex: hover.kind === "slice" && !busy ? hover.index : -1

  readonly property var icons: ({
    drop: String.fromCodePoint(0xF0552),
    file: String.fromCodePoint(0xF0214),
    files: String.fromCodePoint(0xF0222),
    done: String.fromCodePoint(0xF012C),
    failed: String.fromCodePoint(0xF0026)
  })

  // ------------------------------------------------------------ lifecycle

  // Payload (all optional):
  //   {"files": ["/abs/path", ...], "preset": "to-webp", "convert": true}
  // loads files, and converts with the preset when asked.
  function open(payloadJson) {
    root.opened = true
    if (!root.catalogReady && !formatsProc.running) root.loadCatalog()
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }
    if (Array.isArray(payload.files))
      root.loadFiles(payload.files.slice(0, 200).filter(function(p) { return typeof p === "string" }))
    if (typeof payload.preset === "string" && /^[A-Za-z0-9._-]{1,48}$/.test(payload.preset)) {
      root.pendingRequest = { preset: payload.preset, convert: payload.convert === true }
      root.applyPendingRequest()
    }
  }

  function close() {
    root.opened = false
    root.hover = { kind: "outside", index: -1 }
  }

  function applyPendingRequest() {
    var req = root.pendingRequest
    if (!req || !root.catalogReady) return
    root.pendingRequest = null
    var slice = root.presets.find(function(p) { return p.id === req.preset })
    if (!slice) { root.showError("Unknown preset " + req.preset); return }
    if (req.convert) root.convert(slice)
  }

  // ------------------------------------------------------------ files

  function loadFiles(paths) {
    root.files = Model.toFiles(paths, root.extMap)
    root.result = null
  }

  function clearFiles() {
    root.files = []
    root.result = null
  }

  function showError(message) {
    root.result = { ok: false, done: 0, failed: 0, outputs: [], error: Model.cap(message), failedSources: [] }
  }

  // ------------------------------------------------------------ filee CLI

  // Resolve filee from PATH, falling back to install.sh's ~/.local/bin link;
  // arguments go through "$@", never into the script text.
  function fileeArgv(args) {
    return ["bash", "-c",
      "f=$(command -v filee || true); [ -n \"$f\" ] || f=\"$HOME/.local/bin/filee\"; exec \"$f\" \"$@\"",
      "filee"].concat(args)
  }

  function loadCatalog() {
    root.catalogError = ""
    formatsProc.command = root.fileeArgv(["formats"])
    formatsProc.running = true
  }

  function convert(slice) {
    if (root.busy || !slice) return
    var wildcard = root.files.find(function(f) { return !Model.isLiteralPath(f.path) })
    if (wildcard) {
      root.showError("Rename file and try again.")
      return
    }
    var usable = root.files.filter(function(f) { return f.format !== "" })
    if (usable.length === 0) {
      root.showError(root.files.length === 0 ? "No files" : "Filee doesn't know these files")
      return
    }
    root.result = null
    root.activeSlice = slice
    convertProc.command = root.fileeArgv(Model.convertArgs(usable, slice.id))
    root.busy = true
    convertProc.running = true
  }

  function cancel() {
    if (convertProc.running) convertProc.signal(15)
  }

  function finishConvert(exitCode, stdoutText, stderrText) {
    root.busy = false
    var parsed = Model.parseResult(stdoutText)
    if (!parsed.ok) {
      var err = String(stderrText || "").trim().split("\n").pop()
      root.showError(err !== "" ? err : (exitCode === 0 ? parsed.error : "Filee exited with code " + exitCode))
      return
    }
    var summary = Model.summarize(parsed)
    root.result = summary
    // Keep failed files loaded so another slice can be tried.
    root.files = root.files.filter(function(f) { return summary.failedSources.indexOf(f.path) >= 0 })
  }

  function openPath(path) {
    if (path) Quickshell.execDetached(["xdg-open", path])
  }

  // ------------------------------------------------------------ input

  function hitAt(x, y) {
    return Model.hitTest(root.side / 2, root.side / 2, x, y, root.innerRadius, root.outerRadius, root.slices.length, root.popOut)
  }

  function clicked(hit, button) {
    if (hit.kind === "center") {
      if (button === Qt.RightButton) { root.clearFiles(); return }
      if (root.busy) root.cancel()
      else if (root.result && root.result.outputs.length > 0)
        root.openPath(root.result.outputs.length === 1 ? Model.dirname(root.result.outputs[0]) : Model.dirname(root.result.outputs[0]))
      else if (root.files.length > 0) root.clearFiles()
      else if (!pickProc.running) pickProc.running = true
      return
    }
    if (hit.kind === "slice" && !root.busy && root.files.length > 0 && button === Qt.LeftButton)
      root.convert(root.slices[hit.index])
    else if ((hit.kind === "ring" || hit.kind === "slice") && root.files.length === 0 && !pickProc.running)
      pickProc.running = true
  }

  readonly property string centerTitle: {
    if (root.catalogError !== "") return "Unavailable"
    if (root.busy) return "Converting"
    if (root.dragActive) return root.hoverIndex >= 0 ? root.slices[root.hoverIndex].name
      : root.hover.kind === "center" ? "Drop here" : (root.dragFiles.length === 1 ? root.dragFiles[0].name : root.dragFiles.length + " files")
    if (root.hoverIndex >= 0 && root.files.length > 0) return root.slices[root.hoverIndex].name
    if (root.result) return root.result.ok ? "Done"
      : root.result.done > 0 ? root.result.failed + " failed" : "Failed"
    if (root.files.length === 1) return root.files[0].name
    if (root.files.length > 1) return root.files.length + " files"
    return "Filee"
  }

  readonly property string centerSubtitle: {
    if (root.catalogError !== "") return root.catalogError
    if (root.busy) return (root.activeSlice ? root.activeSlice.name + " · " : "") + "click to cancel"
    if (root.dragActive) return root.hoverIndex >= 0 ? "Drop to convert" : "Drop, then pick a format"
    if (root.hoverIndex >= 0 && root.files.length > 0) return "Click to convert"
    if (root.result && !root.result.ok && root.result.error !== "") return root.result.error
    if (root.result) return root.result.done + (root.result.done === 1 ? " file saved" : " files saved") + " · open folder"
    if (root.files.length > 0) return "Pick a format · click to clear"
    if (!root.catalogReady) return "Loading formats…"
    return "Drop files or\nclick to choose"
  }

  readonly property string centerIcon: root.result && !root.busy && !root.dragActive
    ? (root.result.ok ? root.icons.done : root.icons.failed)
    : root.shownFiles.length > 1 ? root.icons.files
    : root.shownFiles.length === 1 ? root.icons.file
    : root.icons.drop

  // ------------------------------------------------------------ processes

  Process {
    id: formatsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseFormats(text)
        root.formats = parsed.formats
        root.extMap = parsed.extMap
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || Object.keys(root.extMap).length === 0) {
        root.catalogError = exitCode === 127 ? "Install the filee CLI (see README)" : "Couldn't read Filee's formats"
        return
      }
      presetsProc.command = root.fileeArgv(["presets"])
      presetsProc.running = true
    }
  }

  Process {
    id: presetsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.presets = Model.parsePresets(text)
    }
    onExited: {
      root.catalogReady = true
      // Files that arrived before the catalogue had no extension map yet.
      if (root.files.length > 0) root.loadFiles(root.files.map(function(f) { return f.path }))
      root.applyPendingRequest()
    }
  }

  // The Filee app writes its donuts here once you customise them.
  FileView {
    id: profilesFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/Filee/profiles.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.userProfiles = Model.parseUserProfiles(text())
    onLoadFailed: root.userProfiles = null
  }

  Process {
    id: convertProc
    stdout: StdioCollector { id: convertOut; waitForEnd: true }
    stderr: StdioCollector { id: convertErr; waitForEnd: true }
    onExited: function(exitCode) { root.finishConvert(exitCode, convertOut.text, convertErr.text) }
  }

  Process {
    id: pickProc
    command: ["omarchy-file-select", "--title", "Choose files to convert", "--multiple"]
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadFiles(String(pickOut.text || "").split("\n"))
    }
  }

  // ------------------------------------------------------------ hyprland

  // Window rules for the donut, registered with `hyprctl eval` so the plugin
  // needs no edits to the user's Hyprland config. They only ever match this
  // window (class org.quickshell, title OmaFilee). A config reload wipes
  // Hyprland's Lua state, so they are registered again on config.reloaded;
  // the version guard stops a shell restart from adding duplicates.
  readonly property string hyprLua: [
    "local V = 'omafilee-2'",
    "if _G.omafilee_rules == V then return end",
    "_G.omafilee_rules = V",
    "local GAP, SHADOW = " + Math.round(Style.gapsOut) + ", " + Math.round(root.shadowMargin),
    "local function ours(w) return w and w.class == 'org.quickshell' and w.title == 'OmaFilee' end",
    // Top-right of its monitor, just under the bar, with the window's
    // transparent shadow margin hanging past the corner. The rule places it
    // before it maps, so Hyprland's popin grows it in place rather than
    // sliding it in from wherever it would otherwise open.
    "local function target(m)",
    "  local r = m.reserved",
    "  return m.width / m.scale - r.right - GAP + SHADOW, r.top + GAP - SHADOW",
    "end",
    "local right, top = target(hl.get_active_monitor())",
    "hl.window_rule({",
    "  match = { class = '^org\\\\.quickshell$', title = '^OmaFilee$' },",
    "  tag = '-default-opacity', float = true, pin = true, no_initial_focus = true, no_dim = true,",
    "  opacity = '1 1', border_size = 0, rounding = 0, no_shadow = true, no_blur = true,",
    "  animation = 'popin 60%',",
    "  move = { '(' .. math.floor(right) .. '-window_w)', tostring(math.floor(top)) },",
    "})",
    // A monitor whose bar differs from the one at registration: correct it.
    "hl.on('window.open', function(w)",
    "  if not ours(w) then return end",
    "  local m = w.monitor or hl.get_active_monitor()",
    "  local r, t = target(m)",
    "  local x, y = math.floor(m.x + r - w.size.x), math.floor(m.y + t)",
    "  if math.abs(w.at.x - x) > 1 or math.abs(w.at.y - y) > 1 then",
    "    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = w }))",
    "  end",
    "end)",
    // Hyprland has no always-on-top rule; raise the donut whenever focus moves.
    "hl.on('window.active', function()",
    "  for _, w in ipairs(hl.get_windows({ class = 'org.quickshell' })) do",
    "    if w.mapped and w.title == 'OmaFilee' then",
    "      hl.dispatch(hl.dsp.window.alter_zorder({ mode = 'top', window = w }))",
    "    end",
    "  end",
    "end)"
  ].join("\n")

  function installHyprRules() {
    if (!hyprRulesProc.running) hyprRulesProc.running = true
  }

  Process {
    id: hyprRulesProc
    command: ["hyprctl", "eval", root.hyprLua]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out !== "" && out !== "ok") console.warn("omafilee: hyprctl eval:", Model.cap(out))
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") root.installHyprRules()
    }
  }

  Component.onCompleted: {
    installHyprRules()
    loadCatalog()
  }

  // ------------------------------------------------------------ window

  FloatingWindow {
    id: win
    title: "OmaFilee"
    visible: root.opened
    implicitWidth: root.side
    implicitHeight: root.side
    // Fixed size, so Super+right-drag can't stretch the donut.
    minimumSize: Qt.size(root.side, root.side)
    maximumSize: Qt.size(root.side, root.side)
    color: "transparent"
    // Only the donut takes input; the transparent corners pass clicks through.
    mask: Region { item: hitCircle; shape: RegionShape.Ellipse }

    Item {
      id: hitCircle
      anchors.centerIn: parent
      width: 2 * (root.outerRadius + root.popOut)
      height: width
    }

    Item {
      id: donut
      anchors.fill: parent

      Canvas {
        id: ring
        anchors.fill: parent
        antialiasing: true

        property int hoverIndex: root.hoverIndex
        property int activeIndex: root.busy && root.activeSlice
          ? root.slices.findIndex(function(s) { return s.id === root.activeSlice.id }) : -1
        property int count: root.slices.length
        property color fg: root.fg
        property color bg: root.bg
        property color border: root.border
        property color accent: root.accent
        property bool dimmed: root.busy
        onHoverIndexChanged: requestPaint()
        onActiveIndexChanged: requestPaint()
        onCountChanged: requestPaint()
        onFgChanged: requestPaint()
        onBgChanged: requestPaint()
        onBorderChanged: requestPaint()
        onAccentChanged: requestPaint()
        onDimmedChanged: requestPaint()
        Connections {
          target: root
          function onSlicesChanged() { ring.requestPaint() }
        }

        function css(c, a) {
          return Qt.rgba(c.r, c.g, c.b, a === undefined ? c.a : a)
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2
          var cy = height / 2
          var r2 = root.outerRadius
          var r1 = root.innerRadius
          var gapPx = Style.space(3)

          // Soft drop shadow so the donut lifts off any wallpaper.
          var shadowR = r2 + root.shadowMargin
          var g = ctx.createRadialGradient(cx, cy + 4, r2 - 18, cx, cy + 4, shadowR)
          g.addColorStop(0, "rgba(0,0,0,0.22)")
          g.addColorStop(1, "rgba(0,0,0,0)")
          ctx.fillStyle = g
          ctx.beginPath()
          ctx.arc(cx, cy + 4, shadowR, 0, 2 * Math.PI)
          ctx.fill()

          // Solid backplate, so the gaps between slices read as dividers
          // rather than windows onto whatever is behind the donut.
          ctx.beginPath()
          ctx.arc(cx, cy, r2, 0, 2 * Math.PI)
          ctx.fillStyle = Qt.darker(bg, 1.35)
          ctx.fill()

          var n = count
          if (n === 0) {
            ctx.beginPath()
            ctx.arc(cx, cy, r2, 0, 2 * Math.PI)
            ctx.moveTo(cx + r1, cy)
            ctx.arc(cx, cy, r1, 0, 2 * Math.PI)
            ctx.fillRule = Qt.OddEvenFill
            ctx.fillStyle = css(bg, 1)
            ctx.fill()
            ctx.lineWidth = Math.max(1, Style.space(1.5))
            ctx.strokeStyle = css(border, 0.7)
            ctx.stroke()
            return
          }

          var span = 2 * Math.PI / n
          for (var i = 0; i < n; i++) {
            var hot = i === hoverIndex || i === activeIndex
            var mid = i * span
            var off = hot ? root.popOut : 0
            var ox = cx + off * Math.sin(mid)
            var oy = cy - off * Math.cos(mid)
            var ho = Math.max(0.001, span / 2 - gapPx / 2 / r2)
            var hi = Math.max(0.001, span / 2 - gapPx / 2 / r1)
            // Canvas angles run clockwise from 3 o'clock; ours from 12.
            ctx.beginPath()
            ctx.arc(ox, oy, r2, mid - ho - Math.PI / 2, mid + ho - Math.PI / 2, false)
            ctx.arc(ox, oy, r1, mid + hi - Math.PI / 2, mid - hi - Math.PI / 2, true)
            ctx.closePath()
            ctx.fillStyle = css(bg, 1)
            ctx.fill()
            if (hot) {
              ctx.fillStyle = css(accent, 0.28)
              ctx.fill()
            }
            ctx.lineWidth = Math.max(1, Style.space(hot ? 2 : 1.25))
            ctx.strokeStyle = hot ? css(accent, 1) : css(border, dimmed ? 0.25 : 0.55)
            ctx.stroke()
          }
        }
      }

      // Slice labels, centred in each slice's band.
      Repeater {
        model: root.slices

        Text {
          id: label
          required property var modelData
          required property int index
          readonly property real span: 2 * Math.PI / root.slices.length
          readonly property real mid: index * span
          readonly property bool hot: index === root.hoverIndex
          readonly property real radius: (root.outerRadius + root.innerRadius) / 2 + (hot ? root.popOut : 0)
          readonly property real band: root.outerRadius - root.innerRadius - Style.space(10)
          readonly property real chord: 2 * radius * Math.sin(Math.min(Math.PI / 2, span / 2)) - Style.space(8)

          textFormat: Text.PlainText
          text: modelData.name
          width: Math.max(Style.space(36), Math.min(band, chord))
          x: root.side / 2 + radius * Math.sin(mid) - width / 2
          y: root.side / 2 - radius * Math.cos(mid) - height / 2
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: hot ? root.fg : Util.alpha(root.fg, 0.85)
          opacity: root.busy && root.activeSlice && root.activeSlice.id !== modelData.id ? 0.4 : 1
          font.family: root.fontFamily
          font.pixelSize: root.slices.length > 9 ? Style.font.caption : Style.font.bodySmall
          font.bold: hot
        }
      }

      // Indeterminate progress: an accent arc chasing round the ring.
      Canvas {
        id: spinner
        anchors.fill: parent
        visible: root.busy
        property color accent: root.accent
        onAccentChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.lineWidth = Style.space(4)
          ctx.lineCap = "round"
          ctx.strokeStyle = ring.css(accent, 1)
          ctx.beginPath()
          ctx.arc(width / 2, height / 2, root.outerRadius + root.popOut + Style.space(4), -Math.PI / 2, 0)
          ctx.stroke()
        }
        RotationAnimation on rotation {
          running: spinner.visible
          from: 0
          to: 360
          duration: 1100
          loops: Animation.Infinite
        }
      }

      // The hole: drop target, file summary, status and result.
      Rectangle {
        id: hole
        anchors.centerIn: parent
        width: 2 * (root.innerRadius - Style.space(4))
        height: width
        radius: width / 2
        color: root.hover.kind === "center" && (root.dragActive || root.files.length > 0 || root.result)
          ? Qt.tint(root.bg, Util.alpha(root.accent, 0.22)) : root.bg
        border.width: Math.max(1, Style.space(root.dragActive && root.hover.kind === "center" ? 2 : 1.5))
        border.color: root.dragActive && root.hover.kind === "center" ? root.accent : Util.alpha(root.border, 0.8)

        Column {
          anchors.centerIn: parent
          width: hole.width * 0.82
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.centerIcon
            color: root.result && !root.busy && !root.dragActive && !root.result.ok ? Commons.Color.urgent : root.accent
            font.family: root.fontFamily
            font.pixelSize: Math.min(Style.font.display, Math.round(hole.width * 0.16))
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: root.centerTitle
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Math.min(Style.font.body, Math.round(hole.width * 0.09))
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            // The hole narrows below its middle: two short lines, sized to it.
            width: hole.width * 0.72
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.centerSubtitle
            color: root.result && !root.result.ok && !root.busy && !root.dragActive ? Commons.Color.urgent : Util.alpha(root.fg, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Math.min(Style.font.caption, Math.round(hole.width * 0.072))
          }
        }
      }

      // Click a slice or the hole. Moving is Hyprland's Super+drag.
      MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: (root.hover.kind === "slice" && root.files.length > 0 && !root.busy) || root.hover.kind === "center"
          ? Qt.PointingHandCursor : Qt.ArrowCursor

        onPositionChanged: function(mouse) { root.hover = root.hitAt(mouse.x, mouse.y) }
        onClicked: function(mouse) { root.clicked(root.hitAt(mouse.x, mouse.y), mouse.button) }
        onExited: root.hover = { kind: "outside", index: -1 }
      }

      DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]

        function pathsOf(drag) {
          return (drag.urls || []).map(function(u) { return Model.urlToPath(u.toString()) })
        }

        onEntered: function(drag) {
          root.dragFiles = Model.toFiles(pathsOf(drag), root.extMap)
          root.dragActive = true
          root.hover = root.hitAt(drag.x, drag.y)
          drag.accept(Qt.CopyAction)
        }
        onPositionChanged: function(drag) { root.hover = root.hitAt(drag.x, drag.y) }
        onExited: {
          root.dragActive = false
          root.dragFiles = []
          root.hover = { kind: "outside", index: -1 }
        }
        onDropped: function(drop) {
          var hit = root.hitAt(drop.x, drop.y)
          var slice = hit.kind === "slice" ? root.slices[hit.index] : null
          root.loadFiles(pathsOf(drop))
          root.dragActive = false
          root.dragFiles = []
          root.hover = hit
          drop.accept(Qt.CopyAction)
          if (slice) root.convert(slice)
        }
      }
    }
  }
}
