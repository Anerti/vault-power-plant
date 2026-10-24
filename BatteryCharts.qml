import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var history: []
  property color foreground: "#fffacf"
  property string fontFamily: ""

  property string chartType: "line"

  readonly property color dimColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
  readonly property color gridColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)

  function samples() {
    var h = Array.isArray(history) ? history : []
    if (h.length === 0) return []
    return Model.historyBuckets(h, bucketCount())
  }

  function bucketCount() {
    if (chartType === "radar") return 12
    if (chartType === "bar") return 36
    if (chartType === "line") return 96
    return 48
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
        model: ["line", "column", "bar", "radar"]

        Item {
          id: tab
          required property string modelData
          readonly property bool active: root.chartType === modelData

          width: tabLabel.implicitWidth + Style.space(14)
          height: tabLabel.implicitHeight + Style.space(10)

          Text {
            id: tabLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: tab.modelData.toUpperCase()
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
            onClicked: root.chartType = tab.modelData
          }
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
  }

  component ChartCanvas: Canvas {
    id: chart

    property string mode: "line"
    property var points: root.samples()
    readonly property int count: points.length

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

      if (chart.count < 2) {
        ctx.font = "bold 10px '" + family + "'"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillStyle = dim
        ctx.fillText(chart.count === 0 ? "AWAITING TELEMETRY" : "COLLECTING SAMPLES", w / 2, h / 2)
        return
      }

      var oldest = chart.points[0].t
      var newest = chart.points[chart.points.length - 1].t
      var spanMin = Math.max(1, Math.round((newest - oldest) / 60000))
      var spanText = spanMin >= 90 ? "-" + Math.round(spanMin / 60) + "H" : "-" + spanMin + "M"

      if (mode === "line" || mode === "column") {
        drawLineAndColumn(ctx, w, h, rgba, label, spanText)
      } else if (mode === "bar") {
        drawBar(ctx, w, h, rgba, label, spanText)
      } else {
        drawRadar(ctx, w, h, rgba, label)
      }
    }

    function drawLineAndColumn(ctx, w, h, rgba, label, spanText) {
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

      var xAt = function(i) { return padX + plotW * (chart.count === 1 ? 1 : i / (chart.count - 1)) }
      var clamp = function(v) { return Math.max(0, Math.min(1, v)) }
      var yAt = function(v) { return bottom - plotH * clamp(v) }

      if (mode === "line") {

        ctx.beginPath()
        ctx.moveTo(xAt(0), bottom)
        ctx.lineTo(xAt(0), yAt(chart.points[0].v))
        for (var i = 1; i < chart.count; i++) ctx.lineTo(xAt(i), yAt(chart.points[i].v))
        ctx.lineTo(xAt(chart.count - 1), bottom)
        ctx.closePath()
        ctx.fillStyle = rgba(0.13)
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(xAt(0), yAt(chart.points[0].v))
        for (var l = 1; l < chart.count; l++) ctx.lineTo(xAt(l), yAt(chart.points[l].v))
        ctx.strokeStyle = root.foreground
        ctx.lineWidth = 1.5
        ctx.stroke()

        var lx = xAt(chart.count - 1)
        var ly = yAt(chart.points[chart.count - 1].v)
        ctx.beginPath()
        ctx.arc(lx, ly, 2.5, 0, Math.PI * 2)
        ctx.fillStyle = root.foreground
        ctx.fill()
      } else {

        var step = plotW / chart.count
        var bw = Math.max(1, Math.min(10, step * 0.66))
        for (var b = 0; b < chart.count; b++) {
          var v = clamp(chart.points[b].v)
          var bx = padX + b * step + (step - bw) / 2
          var by = bottom - plotH * v
          ctx.fillStyle = rgba(0.35 + 0.65 * (chart.count === 1 ? 1 : b / (chart.count - 1)))
          ctx.fillRect(bx, by, bw, bottom - by)
        }
      }

      label(spanText, padX, h - 3, "left", "bottom")
      label("NOW", w, h - 3, "right", "bottom")
    }

    function drawBar(ctx, w, h, rgba, label, spanText) {
      var padL = 42, padTop = 6, padBottom = 16
      var plotW = w - padL - 4
      var rows = chart.count
      var rowH = (h - padTop - padBottom) / rows
      var barH = Math.max(2, Math.min(7, rowH * 0.62))
      var clamp = function(v) { return Math.max(0, Math.min(1, v)) }

      for (var i = 0; i < rows; i++) {
        var v = clamp(chart.points[i].v)
        var y = padTop + i * rowH + (rowH - barH) / 2

        ctx.fillStyle = rgba(0.08)
        ctx.fillRect(padL, y, plotW, barH)
        ctx.fillStyle = rgba(0.35 + 0.65 * (rows === 1 ? 1 : i / (rows - 1)))
        ctx.fillRect(padL, y, Math.max(1, plotW * v), barH)
      }

      label("0", padL, h - 3, "left", "bottom")
      label("50", padL + plotW / 2, h - 3, "center", "bottom")
      label("100", padL + plotW, h - 3, "right", "bottom")

      label("NOW", padL - 6, padTop + rowH / 2, "right", "middle")
      label(spanText, padL - 6, padTop + (rows - 1) * rowH + rowH / 2, "right", "middle")
    }

    function drawRadar(ctx, w, h, rgba, label) {
      var cx = w / 2, cy = h / 2
      var R = Math.min(w / 2, h / 2 - 10)
      var n = chart.count
      var clamp = function(v) { return Math.max(0.04, Math.min(1, v)) }
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

      ctx.beginPath()
      for (var d = 0; d < n; d++) {
        var v = clamp(chart.points[d].v)
        if (d === 0) ctx.moveTo(px(d, R * v), py(d, R * v))
        else ctx.lineTo(px(d, R * v), py(d, R * v))
      }
      ctx.closePath()
      ctx.fillStyle = rgba(0.20)
      ctx.fill()
      ctx.strokeStyle = root.foreground
      ctx.lineWidth = 1.5
      ctx.stroke()

      ctx.fillStyle = root.foreground
      for (var q = 0; q < n; q++) {
        var dv = clamp(chart.points[q].v)
        ctx.beginPath()
        ctx.arc(px(q, R * dv), py(q, R * dv), 1.8, 0, Math.PI * 2)
        ctx.fill()
      }

      label("100%", cx, cy - R - 6, "center", "middle")
    }
  }
}
