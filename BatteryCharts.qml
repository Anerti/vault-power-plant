import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var history: []
  property color foreground: "#fffacf"
  property string fontFamily: ""

  property string chartType: "line"
  // 0 = today, 6 = six days ago
  property int dayOffset: 0

  readonly property color dimColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
  readonly property color gridColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)

  // Re-read the clock on every new sample so day boundaries roll over at midnight.
  readonly property real now: { root.history; return Date.now() }

  function samples() {
    var start = Model.dayStart(root.now, dayOffset)
    var end = Model.dayStart(root.now, dayOffset - 1)
    return Model.dayBuckets(history, start, end, bucketCount())
  }

  function bucketCount() {
    if (chartType === "radar" || chartType === "bar") return 24
    if (chartType === "line") return 96
    return 48
  }

  function weekdayLabel(offset) {
    return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][new Date(Model.dayStart(root.now, offset)).getDay()]
  }

  implicitHeight: layout.implicitHeight

  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(6)

    Row {
      spacing: Style.space(4)

      Repeater {
        model: [6, 5, 4, 3, 2, 1, 0]

        Tab {
          required property int modelData
          label: root.weekdayLabel(modelData)
          active: root.dayOffset === modelData
          onClicked: root.dayOffset = modelData
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(190)

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
      }

      ChartCanvas {
        id: chart
        anchors.fill: parent
        anchors.margins: Style.space(8)
        mode: root.chartType
      }
    }

    // < TYPE > pager, same pattern as agx.screen-time's week navigation.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)

      Chevron { glyph: ""; step: -1 }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.chartType.toUpperCase()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
      }

      Chevron { glyph: ""; step: 1 }
    }
  }

  readonly property var chartTypes: ["line", "column", "bar", "radar"]

  component Chevron: Text {
    id: chevron
    property int step: 1
    property alias glyph: chevron.text
    readonly property int target: root.chartTypes.indexOf(root.chartType) + step

    anchors.verticalCenter: parent.verticalCenter
    color: chevronMouse.enabled && chevronMouse.containsMouse ? root.foreground : root.dimColor
    opacity: chevronMouse.enabled ? 1.0 : 0.25
    Behavior on opacity { NumberAnimation { duration: 150 } }
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall

    MouseArea {
      id: chevronMouse
      anchors.fill: parent
      anchors.margins: -Style.space(6)
      hoverEnabled: true
      enabled: chevron.target >= 0 && chevron.target < root.chartTypes.length
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.chartType = root.chartTypes[chevron.target]
    }
  }

  component Tab: Item {
    id: tab
    property string label: ""
    property bool active: false
    signal clicked()

    width: tabLabel.implicitWidth + Style.space(14)
    height: tabLabel.implicitHeight + Style.space(10)

    Text {
      id: tabLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tab.label
      color: tab.active ? root.foreground : root.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: tab.active
      font.letterSpacing: 1.0

      Behavior on color { ColorAnimation { duration: 160 } }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 2
      radius: 1
      color: root.foreground
      visible: tab.active
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.clicked()
    }
  }

  component ChartCanvas: Canvas {
    id: chart

    property string mode: "line"
    // One value per time slot of the selected day; null where no sample was taken.
    property var points: root.samples()
    readonly property int count: points.length
    readonly property int filled: points.filter(function(p) { return p !== null }).length

    onModeChanged: requestPaint()
    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: requestPaint()

    Connections {
      target: root
      function onForegroundChanged() { chart.requestPaint() }
      function onFontFamilyChanged() { chart.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      if (w <= 0 || h <= 0) return

      var fg = root.foreground

      var rgba = function(a) {
        return "rgba(" + Math.round(fg.r * 255) + "," + Math.round(fg.g * 255) + "," + Math.round(fg.b * 255) + "," + a + ")"
      }
      var dim = root.dimColor
      var family = root.fontFamily && root.fontFamily.length > 0 ? root.fontFamily : "sans-serif"
      var smallFont = "8px '" + family + "'"

      var label = function(text, x, y, align, baseline) {
        ctx.font = smallFont
        ctx.textAlign = align || "left"
        ctx.textBaseline = baseline || "middle"
        ctx.fillStyle = dim
        ctx.fillText(text, x, y)
      }

      ctx.lineWidth = 1

      var minPoints = mode === "radar" ? 3 : 2
      if (chart.filled < minPoints) {
        ctx.font = "bold 10px '" + family + "'"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillStyle = dim
        var empty = root.dayOffset > 0 ? "NO TELEMETRY" : "AWAITING TELEMETRY"
        ctx.fillText(chart.filled === 0 ? empty : "COLLECTING SAMPLES", w / 2, h / 2)
        return
      }

      if (mode === "line" || mode === "column") {
        drawLineAndColumn(ctx, w, h, rgba, label)
      } else if (mode === "bar") {
        drawBar(ctx, w, h, rgba, label)
      } else {
        drawRadar(ctx, w, h, rgba, label)
      }
    }

    function hourText(hour) {
      return (hour < 10 ? "0" : "") + hour
    }

    // Call fn(a, b) for each run of consecutive filled slots, so gaps (sleep, shutdown) stay visible.
    function forEachRun(fn) {
      var runStart = -1
      for (var r = 0; r <= count; r++) {
        var has = r < count && points[r] !== null
        if (has && runStart < 0) runStart = r
        if (!has && runStart >= 0) { fn(runStart, r - 1); runStart = -1 }
      }
    }

    function drawLineAndColumn(ctx, w, h, rgba, label) {
      var padX = 30, padTop = 6, padBottom = 14
      var plotW = w - padX - 4
      var plotH = h - padTop - padBottom
      var bottom = padTop + plotH

      for (var g = 0; g <= 4; g++) {
        var gy = Math.round(bottom - plotH * g / 4) + 0.5
        ctx.beginPath()
        ctx.moveTo(padX, gy)
        ctx.lineTo(w, gy)
        ctx.strokeStyle = g === 0 ? rgba(0.35) : root.gridColor
        ctx.stroke()
        label((g * 25) + "%", 2, gy)
      }

      var step = plotW / chart.count
      var xAt = function(i) { return padX + step * (i + 0.5) }
      var yAt = function(v) { return bottom - plotH * v }

      if (mode === "line") {
        var dot = function(i, r) {
          ctx.beginPath()
          ctx.arc(xAt(i), yAt(chart.points[i]), r, 0, Math.PI * 2)
          ctx.fillStyle = root.foreground
          ctx.fill()
        }

        chart.forEachRun(function(a, b) {
          // A lone slot has no line to draw, so mark it with a dot.
          if (a === b) return dot(a, 1.8)

          ctx.beginPath()
          ctx.moveTo(xAt(a), bottom)
          for (var i = a; i <= b; i++) ctx.lineTo(xAt(i), yAt(chart.points[i]))
          ctx.lineTo(xAt(b), bottom)
          ctx.closePath()
          ctx.fillStyle = rgba(0.13)
          ctx.fill()

          ctx.beginPath()
          ctx.moveTo(xAt(a), yAt(chart.points[a]))
          for (var l = a + 1; l <= b; l++) ctx.lineTo(xAt(l), yAt(chart.points[l]))
          ctx.strokeStyle = root.foreground
          ctx.lineWidth = 1.5
          ctx.stroke()
        })

        var last = chart.count - 1
        while (chart.points[last] === null) last--
        dot(last, 2.5)
      } else {

        var bw = Math.max(1, Math.min(10, step * 0.66))
        for (var b = 0; b < chart.count; b++) {
          if (chart.points[b] === null) continue
          var bx = padX + b * step + (step - bw) / 2
          var by = yAt(chart.points[b])
          ctx.fillStyle = rgba(0.35 + 0.65 * b / (chart.count - 1))
          ctx.fillRect(bx, by, bw, bottom - by)
        }
      }

      for (var hr = 0; hr <= 24; hr += 6) {
        label(hourText(hr), padX + plotW * hr / 24, h - 3, hr === 0 ? "left" : (hr === 24 ? "right" : "center"), "bottom")
      }
    }

    function drawBar(ctx, w, h, rgba, label) {
      var padL = 42, padTop = 6, padBottom = 16
      var plotW = w - padL - 4
      var rows = chart.count
      var rowH = (h - padTop - padBottom) / rows
      var barH = Math.max(2, Math.min(7, rowH * 0.62))

      for (var i = 0; i < rows; i++) {
        var y = padTop + i * rowH + (rowH - barH) / 2

        ctx.fillStyle = rgba(0.08)
        ctx.fillRect(padL, y, plotW, barH)
        if (chart.points[i] !== null) {
          ctx.fillStyle = rgba(0.35 + 0.65 * i / (rows - 1))
          ctx.fillRect(padL, y, Math.max(1, plotW * chart.points[i]), barH)
        }
        if (i % 6 === 0) label(hourText(i * 24 / rows) + "H", padL - 6, padTop + i * rowH + rowH / 2, "right", "middle")
      }

      label("0", padL, h - 3, "left", "bottom")
      label("50", padL + plotW / 2, h - 3, "center", "bottom")
      label("100", padL + plotW, h - 3, "right", "bottom")
    }

    function drawRadar(ctx, w, h, rgba, label) {
      var cx = w / 2, cy = h / 2
      var R = Math.min(w / 2 - 16, h / 2 - 10)
      var n = chart.count
      // Keep 0% off the exact center so the point stays visible. `i % n` lets a full-day run wrap back to 00H.
      var radius = function(i) { return R * Math.max(0.04, chart.points[i % n]) }
      var angle = function(i) { return -Math.PI / 2 + Math.PI * 2 * i / n }
      var px = function(i, r) { return cx + Math.cos(angle(i)) * r }
      var py = function(i, r) { return cy + Math.sin(angle(i)) * r }

      ctx.lineWidth = 1
      ctx.strokeStyle = root.gridColor
      for (var ring = 1; ring <= 3; ring++) {
        var rr = R * ring / 3
        ctx.beginPath()
        for (var s = 0; s < n; s++) {
          if (s === 0) ctx.moveTo(px(s, rr), py(s, rr))
          else ctx.lineTo(px(s, rr), py(s, rr))
        }
        ctx.closePath()
        ctx.stroke()
      }

      ctx.beginPath()
      for (var p = 0; p < n; p++) {
        ctx.moveTo(cx, cy)
        ctx.lineTo(px(p, R), py(p, R))
      }
      ctx.stroke()

      // Fill a wedge from the center for each run; empty hours (sleep, not yet happened) stay blank.
      var drawRun = function(a, b) {
        ctx.beginPath()
        ctx.moveTo(cx, cy)
        for (var i = a; i <= b; i++) ctx.lineTo(px(i, radius(i)), py(i, radius(i)))
        ctx.closePath()
        ctx.fillStyle = rgba(0.20)
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(px(a, radius(a)), py(a, radius(a)))
        for (var l = a + 1; l <= b; l++) ctx.lineTo(px(l, radius(l)), py(l, radius(l)))
        ctx.strokeStyle = root.foreground
        ctx.lineWidth = 1.5
        ctx.stroke()
      }
      if (chart.filled === n) drawRun(0, n)
      else chart.forEachRun(drawRun)

      ctx.fillStyle = root.foreground
      for (var q = 0; q < n; q++) {
        if (chart.points[q] === null) continue
        ctx.beginPath()
        ctx.arc(px(q, radius(q)), py(q, radius(q)), 1.8, 0, Math.PI * 2)
        ctx.fill()
      }

      label("00H", cx, cy - R - 6, "center", "middle")
      label("06H", cx + R + 4, cy, "left", "middle")
      label("12H", cx, cy + R + 6, "center", "middle")
      label("18H", cx - R - 4, cy, "right", "middle")
    }
  }
}
