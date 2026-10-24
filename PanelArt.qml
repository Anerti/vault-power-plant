import QtQuick
import QtQuick.Effects
import qs.Commons

// The popup's art as a large poster, like the section art above the Vault
// menu: a big 4:3 picture on the menu's accent sunburst, cropped tight to the
// figure, tinted in the theme's foreground, and switched on with the menu's
// CRT reveal (scale, glow, and scanlines).
Item {
  id: root

  property alias source: gif.source
  property bool playing: true

  // Union of the GIF's frame bounds plus a small margin. The source is mostly
  // transparent padding, so cropping to the figure is what makes it read as a
  // poster instead of a small stamp in the middle of the popup.
  readonly property rect sourceCrop: Qt.rect(145, 43, 223, 300)
  readonly property real posterAspect: 4 / 3

  implicitHeight: width > 0 ? width / posterAspect : Style.space(280)

  // The menu's poster: a faint accent wash under an accent sunburst.
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
