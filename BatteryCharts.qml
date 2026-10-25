import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var history: []
  property color foreground: "#fffacf"
  property string fontFamily: ""

  // 0 = today, 6 = six days ago
  property int dayOffset: 0
  // Keyboard cursor sits on the day tabs; the panel owns the focus state.
  property bool tabCursor: false
  // Show the selected day's stats in place of the chart.
  property bool showSummary: false

  readonly property color dimColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
  readonly property color gridColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)

  // Re-read the clock on every new sample so day boundaries roll over at midnight.
  readonly property real now: { root.history; return Date.now() }

  function samples() {
    var start = Model.dayStart(root.now, dayOffset)
    var end = Model.dayStart(root.now, dayOffset - 1)
    // 96 slots = 15 minutes each.
    return Model.dayBuckets(history, start, end, 96)
  }

  // [label, value] pairs for the summary view; empty when the day has no samples.
  readonly property var summaryRows: {
    var s = Model.daySummary(history, Model.dayStart(now, dayOffset), Model.dayStart(now, dayOffset - 1))
    if (!s) return []
    var pct = function(v) { return Math.round(v * 100) + "%" }
    var hours = s.batteryMs / 3600000
    return [
      ["Recorded", Model.durationLabel(s.recordedMs)],
      ["Range", pct(s.min) + " – " + pct(s.max)],
      ["On battery", Model.durationLabel(s.batteryMs)],
      ["Drained", pct(s.drained)],
      ["Average drain", hours > 0 ? Math.round(s.drained * 1000 / hours) / 10 + "%/h" : "—"],
      ["Charged", "+" + pct(s.charged)]
    ]
  }

  function weekdayLabel(offset) {
    if (offset === 0) return "TODAY"
    return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][new Date(Model.dayStart(root.now, offset)).getDay()]
  }

  implicitHeight: layout.implicitHeight

  Column {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(6)

    Row {
      id: dayTabs
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [6, 5, 4, 3, 2, 1, 0]

        Tab {
          required property int modelData
          width: (dayTabs.width - dayTabs.spacing * 6) / 7
          label: root.weekdayLabel(modelData)
          active: root.dayOffset === modelData
          hasCursor: root.tabCursor && active
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
        visible: !root.showSummary
        anchors.fill: parent
        anchors.margins: Style.space(8)
      }

      Column {
        visible: root.showSummary && root.summaryRows.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(14)
        spacing: Style.space(8)

        Repeater {
          model: root.summaryRows

          Item {
            required property var modelData
            width: parent.width
            height: rowValue.implicitHeight

            Text {
              textFormat: Text.PlainText
              text: modelData[0]
              color: root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              id: rowValue
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: modelData[1]
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
        }
      }

      Text {
        visible: root.showSummary && root.summaryRows.length === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "NO TELEMETRY"
        color: root.dimColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: chartMouse
        visible: chart.visible
        anchors.fill: chart
        hoverEnabled: true
        // Hidden by the summary while hovered, so no exit event comes.
        onVisibleChanged: if (!visible) chart.hoverIndex = -1
        onPositionChanged: function(mouse) { chart.hoverIndex = chart.hasChart ? chart.indexAt(mouse.x, mouse.y) : -1 }
        onExited: chart.hoverIndex = -1

        PanelToolTip {
          visible: chart.hoverIndex >= 0
          delay: 0
          text: chart.hoverIndex >= 0 ? chart.slotInfo(chart.hoverIndex) : ""
          x: chartMouse.mouseX + Style.space(12)
          y: chartMouse.mouseY - height - Style.space(8)
        }
      }
    }
  }

  component Tab: Item {
    id: tab
    property string label: ""
    property bool active: false
    property bool hasCursor: false
    signal clicked()

    implicitWidth: tabLabel.implicitWidth + Style.space(14)
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
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "transparent"
      border.width: 1
      border.color: root.dimColor
      visible: tab.hasCursor
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

    // One value per time slot of the selected day; null where no sample was taken.
    property var points: root.samples()
    readonly property int count: points.length
    readonly property int filled: points.filter(function(p) { return p !== null }).length
    readonly property bool hasChart: filled >= 2
    // Slot under the pointer, -1 when not hovering.
    property int hoverIndex: -1

    // Plot margins, shared by the draw functions and indexAt().
    readonly property int padTop: 6
    // Room for the "100%" axis label.
    readonly property int lineLeft: Math.round(Style.font.caption * 3.2)
    // Label height plus a gap below the 0% line.
    readonly property int padBottom: Style.font.caption + 14

    onPointsChanged: requestPaint()
    onHoverIndexChanged: requestPaint()
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
      var smallFont = Style.font.caption + "px '" + family + "'"

      var label = function(text, x, y, align, baseline) {
        ctx.font = smallFont
        ctx.textAlign = align || "left"
        ctx.textBaseline = baseline || "middle"
        ctx.fillStyle = dim
        ctx.fillText(text, x, y)
      }

      ctx.lineWidth = 1

      if (!chart.hasChart) {
        ctx.font = "bold " + Style.font.bodySmall + "px '" + family + "'"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillStyle = dim
        var empty = root.dayOffset > 0 ? "NO TELEMETRY" : "AWAITING TELEMETRY"
        ctx.fillText(chart.filled === 0 ? empty : "COLLECTING SAMPLES", w / 2, h / 2)
        return
      }

      drawLine(ctx, w, h, rgba, label)
    }

    function hourText(hour) {
      return (hour < 10 ? "0" : "") + hour
    }

    // Map a pointer position to a slot, using the same geometry as the draw functions; -1 outside the plot.
    function indexAt(x, y) {
      if (x < lineLeft || x > width - 4) return -1
      var i = Math.floor((x - lineLeft) / ((width - lineLeft - 4) / count))
      return Math.max(0, Math.min(count - 1, i))
    }

    // "14:00–15:00", then the level and its change since the slot before.
    function slotInfo(i) {
      var span = 1440 / count
      var clock = function(m) { return hourText(Math.floor(m / 60)) + ":" + (m % 60 < 10 ? "0" : "") + m % 60 }
      var text = clock(i * span) + "–" + clock((i + 1) * span)
      var v = points[i]
      if (v === null) return text + "\nNo data"
      text += "\n" + Math.round(v * 100) + "%"
      var prev = i > 0 ? points[i - 1] : null
      var delta = prev === null ? 0 : Math.round((v - prev) * 100)
      if (delta !== 0) text += "  (" + (delta > 0 ? "+" : "") + delta + "%)"
      return text
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

    function drawLine(ctx, w, h, rgba, label) {
      var padX = chart.lineLeft, padTop = chart.padTop, padBottom = chart.padBottom
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

      if (chart.hoverIndex >= 0) {
        var hx = Math.round(xAt(chart.hoverIndex)) + 0.5
        ctx.beginPath()
        ctx.moveTo(hx, padTop)
        ctx.lineTo(hx, bottom)
        ctx.strokeStyle = rgba(0.5)
        ctx.lineWidth = 1
        ctx.stroke()
        if (chart.points[chart.hoverIndex] !== null) {
          ctx.beginPath()
          ctx.arc(xAt(chart.hoverIndex), yAt(chart.points[chart.hoverIndex]), 3, 0, Math.PI * 2)
          ctx.fillStyle = root.foreground
          ctx.fill()
        }
      }

      for (var hr = 0; hr <= 24; hr += 6) {
        label(hourText(hr), padX + plotW * hr / 24, h - 3, hr === 0 ? "left" : (hr === 24 ? "right" : "center"), "bottom")
      }
    }
  }
}
