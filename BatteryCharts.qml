import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var history: []
  property var appUsage: ({})
  property color foreground: "#fffacf"
  property string fontFamily: ""

  property int dayOffset: 0
  property bool tabCursor: false
  property string view: "chart"

  readonly property color dimColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
  readonly property color gridColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property var rankColors: [1, 0.8, 0.6].map(function(a) { return Qt.rgba(foreground.r, foreground.g, foreground.b, a) })

  readonly property real now: { root.history; return Date.now() }

  // the selected day's real length: 23 or 25 hours on DST change days
  readonly property real dayStartMs: Model.dayStart(now, dayOffset)
  readonly property real dayEndMs: Model.dayStart(now, dayOffset - 1)

  function samples() {
    return Model.dayBuckets(history, dayStartMs, dayEndMs, 96)
  }

  readonly property var summary: Model.daySummary(history, dayStartMs, dayEndMs)

  readonly property var summaryRows: {
    var s = summary
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

  readonly property var appRows: {
    return Model.appUsageRows(appUsage[dayStartMs], summary ? summary.drained : 0).map(function(r) {
      return [r[0], r[1] < 0.0005 ? "<0.1%" : Math.round(r[1] * 1000) / 10 + "%"]
    })
  }
  readonly property var listRows: view === "apps" ? appRows : summaryRows

  function weekdayLabel(offset) {
    if (offset === 0) return "TODAY"
    return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][new Date(Model.dayStart(root.now, offset)).getDay()]
  }

  onViewChanged: listFlick.contentY = 0
  onDayOffsetChanged: listFlick.contentY = 0

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
        visible: root.view === "chart"
        anchors.fill: parent
        anchors.margins: Style.space(8)
      }

      Flickable {
        id: listFlick
        visible: root.view !== "chart" && root.listRows.length > 0
        anchors.fill: parent
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(6)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        contentWidth: width
        contentHeight: Math.max(height, listColumn.implicitHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: listColumn.implicitHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: listFlick.interactive ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }

        Column {
          id: listColumn
          y: Math.max(0, (listFlick.height - implicitHeight) / 2)
          width: listFlick.width - Style.space(14)
          spacing: Style.space(8)

          Repeater {
            model: root.listRows

            Item {
              required property var modelData
              required property int index
              readonly property bool ranked: root.view === "apps" && index < root.rankColors.length
              width: parent.width
              height: rowValue.implicitHeight

              Text {
                anchors.left: parent.left
                anchors.right: rowValue.left
                anchors.rightMargin: Style.space(8)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: modelData[0]
                color: parent.ranked ? root.rankColors[index] : root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: parent.ranked
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
      }

      Text {
        visible: root.view !== "chart" && root.listRows.length === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.view === "apps" ? "NO BATTERY USE" : "NO TELEMETRY"
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

    property var points: root.samples()
    readonly property int count: points.length
    readonly property int filled: points.filter(function(p) { return p !== null }).length
    readonly property bool hasChart: filled >= 2
    property int hoverIndex: -1

    readonly property int padTop: 6
    readonly property int lineLeft: Math.round(Style.font.caption * 3.2)
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

    function indexAt(x, y) {
      if (x < lineLeft || x > width - 4) return -1
      var i = Math.floor((x - lineLeft) / ((width - lineLeft - 4) / count))
      return Math.max(0, Math.min(count - 1, i))
    }

    function slotInfo(i) {
      var start = root.dayStartMs
      var span = (root.dayEndMs - start) / count
      var clock = function(t) { var d = new Date(t); return hourText(d.getHours()) + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes() }
      var text = clock(start + i * span) + "–" + clock(start + (i + 1) * span)
      var v = points[i]
      if (v === null) return text + "\nNo data"
      text += "\n" + Math.round(v * 100) + "%"
      var prev = i > 0 ? points[i - 1] : null
      var delta = prev === null ? 0 : Math.round((v - prev) * 100)
      if (delta !== 0) text += "  (" + (delta > 0 ? "+" : "") + delta + "%)"
      return text
    }

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
        var at = (new Date(root.dayStartMs).setHours(hr) - root.dayStartMs) / (root.dayEndMs - root.dayStartMs)
        label(hourText(hr), padX + plotW * at, h - 3, hr === 0 ? "left" : (hr === 24 ? "right" : "center"), "bottom")
      }
    }
  }
}
