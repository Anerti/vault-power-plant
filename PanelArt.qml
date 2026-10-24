import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  property alias source: gif.source
  property bool playing: true

  property string phrase: ""
  property alias phraseOpacity: bubble.opacity

  readonly property rect sourceCrop: Qt.rect(145, 43, 223, 300)
  readonly property real posterAspect: 4 / 3

  implicitHeight: width > 0 ? width / posterAspect : Style.space(280)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.07)
    clip: true

    Canvas {
      id: sunburst
      anchors.fill: parent
      readonly property color tint: Color.accent
      onTintChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        var cx = width / 2, cy = height * 0.48, r = Math.max(width, height)
        var rgba = function(a) { return "rgba(" + Math.round(tint.r * 255) + "," + Math.round(tint.g * 255) + "," + Math.round(tint.b * 255) + "," + a + ")" }
        var fade = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 0.6)
        fade.addColorStop(0, rgba(0.16))
        fade.addColorStop(1, rgba(0))
        ctx.reset()
        ctx.fillStyle = fade
        for (var i = 0; i < 20; i++) {
          var a = i * Math.PI / 10
          ctx.beginPath()
          ctx.moveTo(cx, cy)
          ctx.arc(cx, cy, r, a, a + Math.PI / 30)
          ctx.closePath()
          ctx.fill()
        }
      }
    }

    Item {
      id: artScreen
      anchors.fill: parent
      clip: true

      AnimatedImage {
        id: gif
        anchors.fill: parent
        visible: false
        sourceClipRect: root.sourceCrop
        fillMode: Image.PreserveAspectFit
        playing: root.playing && root.visible
        cache: false
        smooth: true
      }

      MultiEffect {
        id: artFx
        anchors.fill: gif
        source: gif
        colorization: 1.0
        colorizationColor: Color.foreground
        blurEnabled: true
        blurMax: 16
        blur: 0
        autoPaddingEnabled: true
      }

      Canvas {
        id: scanlines
        anchors.fill: parent
        opacity: 0
        readonly property color tint: Color.background
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.fillStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.55)
          for (var y = 0; y < height; y += 3) ctx.fillRect(0, y, width, 1)
        }
      }

      transform: Scale { id: crtScale; origin.x: artScreen.width / 2; origin.y: artScreen.height / 2 }
    }

    Item {
      id: bubble
      visible: root.phrase !== ""
      z: 2
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(10)

      FontMetrics {
        id: bubbleMetrics
        font.family: Style.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
      }

      readonly property real boxWidth: Math.round(artScreen.width * 0.52)
      readonly property real boxHeight: Math.round(bubbleMetrics.height * 2 + Style.space(14))
      readonly property real tailHeight: Style.space(10)

      readonly property real tailCenter: boxWidth * 0.33

      width: boxWidth
      height: boxHeight + tailHeight

      Canvas {
        id: bubbleSurface
        anchors.fill: parent
        readonly property color fill: Color.background
        readonly property color stroke: Color.foreground
        onFillChanged: requestPaint()
        onStrokeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()

          var w = bubble.boxWidth
          var h = bubble.boxHeight
          var th = bubble.tailHeight
          var tw = Style.space(18)
          var r = Math.max(1, Style.space(12) - 1)
          var cx = bubble.tailCenter
          var left = cx - tw / 2
          var right = cx + tw / 2

          var tipX = cx - tw * 0.35

          ctx.beginPath()
          ctx.moveTo(1 + r, 1)
          ctx.lineTo(w - 1 - r, 1)
          ctx.arc(w - 1 - r, 1 + r, r, -Math.PI / 2, 0)
          ctx.lineTo(w - 1, h - 1 - r)
          ctx.arc(w - 1 - r, h - 1 - r, r, 0, Math.PI / 2)

          ctx.lineTo(right, h - 1)
          ctx.quadraticCurveTo(right - tw * 0.12, h - 1 + th * 0.55, tipX, h - 1 + th)
          ctx.quadraticCurveTo(left + tw * 0.15, h - 1 + th * 0.4, left, h - 1)

          ctx.lineTo(1 + r, h - 1)
          ctx.arc(1 + r, h - 1 - r, r, Math.PI / 2, Math.PI)
          ctx.lineTo(1, 1 + r)
          ctx.arc(1 + r, 1 + r, r, Math.PI, Math.PI * 1.5)
          ctx.closePath()

          ctx.fillStyle = Qt.rgba(fill.r, fill.g, fill.b, fill.a)
          ctx.fill()
          ctx.strokeStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, stroke.a)
          ctx.lineWidth = 2
          ctx.stroke()
        }
      }

      Text {
        id: bubbleText
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.space(16)
        height: bubble.boxHeight
        textFormat: Text.PlainText
        text: root.phrase.toUpperCase()
        color: Color.foreground
        font.family: Style.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
  }

  ParallelAnimation {
    id: crtOn
    NumberAnimation { target: crtScale; property: "yScale"; from: 0.01; to: 1; duration: 240; easing.type: Easing.OutCubic }
    NumberAnimation { target: crtScale; property: "xScale"; from: 1.25; to: 1; duration: 240; easing.type: Easing.OutCubic }
    NumberAnimation { target: artFx; property: "brightness"; from: 0.9; to: 0; duration: 420; easing.type: Easing.OutQuad }
    NumberAnimation { target: artFx; property: "blur"; from: 0.8; to: 0; duration: 420; easing.type: Easing.OutQuad }
    SequentialAnimation {
      NumberAnimation { target: scanlines; property: "opacity"; from: 1; to: 0.4; duration: 70 }
      NumberAnimation { target: scanlines; property: "opacity"; to: 0.9; duration: 50 }
      NumberAnimation { target: scanlines; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
    }
  }

  onPlayingChanged: if (playing) crtOn.restart()
}
