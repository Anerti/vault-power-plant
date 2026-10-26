import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "anerti.vault-power-plant"
  ipcTarget: "omarchy.power"

  manageIpc: false
  property var batteryInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false

  readonly property var telemetry: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var batteryHistory: telemetry ? telemetry.batteryHistory : []
  readonly property var appUsage: telemetry ? telemetry.appUsage : ({})
  property var agentChoices: []
  property bool noAgentInstalled: false
  property int agentIndex: 0
  property int headerIndex: 1
  readonly property var viewOptions: [
    { value: "chart", label: "Chart", icon: "󰄪" },
    { value: "summary", label: "Summary", icon: "󰉹", tooltip: "Day stats" },
    { value: "apps", label: "Apps", icon: "󰀻", tooltip: "Estimated drain per app" }
  ]
  property string focusRow: "profiles"
  readonly property var focusRows: ["profiles", "telemetry"]
    .concat(telemetryOpen ? ["days", "views"] : [])
    .concat(agentChoices.length > 0 || noAgentInstalled ? ["agents"] : [])
  readonly property bool showPercentage: setting("showPercentage", false) === true
  readonly property bool telemetryOpen: setting("telemetryOpen", true) !== false

  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    if (dy !== 0) {
      focusRow = focusRows[Model.clampIndex(focusRows.indexOf(focusRow) + dy, focusRows.length)]
    } else if (focusRow === "profiles") {
      selectProfileByDelta(dx)
    } else if (focusRow === "telemetry") {
      headerIndex = Model.clampIndex(headerIndex + dx, 2)
    } else if (focusRow === "days") {
      charts.dayOffset = Math.max(0, Math.min(6, charts.dayOffset - dx))
    } else if (focusRow === "views") {
      var i = viewOptions.findIndex(function(o) { return o.value === charts.view })
      charts.view = viewOptions[Model.clampIndex(i + dx, viewOptions.length)].value
    } else if (focusRow === "agents") {
      agentIndex = Model.clampIndex(agentIndex + dx, Math.max(1, agentChoices.length))
    }
  }

  function toggleTelemetry() {
    saveSetting("telemetryOpen", !telemetryOpen)
    if (focusRows.indexOf(focusRow) < 0) focusRow = "telemetry"
  }

  function activateCursor() {
    if (focusRow === "profiles") activateSelectedProfile()
    else if (focusRow === "telemetry") {
      if (headerIndex === 0) askAgent()
      else toggleTelemetry()
    }
    else if (focusRow === "agents") {
      if (noAgentInstalled) setupAgent()
      else if (agentIndex < agentChoices.length) launchAgent(agentChoices[agentIndex])
    }
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: Model.batteryFull(UPower.displayDevice, root.discharging, upowerStates())
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color accentColor: Color.accent

  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  readonly property var activePhrases: {
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string bubblePhrase: {
    if (!rotatingPhrases) return ""
    return activePhrases[phraseIndex % activePhrases.length]
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function updateBattery(raw) {
    var next = Model.parseKeyValue(raw)

    if (Object.keys(next).length === 0) return
    var device = UPower.displayDevice
    next.rate = Model.rateLabel(next.rate, device ? device.changeRate : 0)
    batteryInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)

    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function saveSetting(name, value) {
    var next = {}
    next[name] = value
    root.settings = Object.assign({}, root.settings, next)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function togglePercentage() {
    saveSetting("showPercentage", !root.showPercentage)
  }

  function askAgent() {
    if (agentCheckProc.running) return
    agentCheckProc.running = true
  }

  function onAgentCheck(raw) {
    var check = Model.parseAgentCheck(raw)
    if (check.defaultAgent) {
      launchAgent("")
    } else {
      agentChoices = check.installed
      noAgentInstalled = check.installed.length === 0
      agentIndex = 0
      if (cursorActive && focusRow === "telemetry") focusRow = "agents"
    }
  }

  function setupAgent() {
    close()
    Util.execArgv(["omarchy-menu", "summon", "setup.default.agent"])
  }

  function launchAgent(pick) {
    Util.execArgv(["bash", "-c",
      'if [[ -n $1 ]]; then mkdir -p "$HOME/.config/omarchy/defaults" && printf "%s\\n" "$1" > "$HOME/.config/omarchy/defaults/agent" || exit 1; fi; exec omarchy-agent --prompt "$2"',
      "_", pick, Model.agentPrompt(root.batteryHistory, Date.now(), root.batteryInfo, root.activeProfile, root.appUsage)])
    agentChoices = []
    close()
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      focusRow = "profiles"
      headerIndex = 1
    } else {
      agentChoices = []
      noAgentInstalled = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBattery(text) }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process {
    id: agentCheckProc
    command: ["bash", "-lc",
      'd=$(omarchy-default-agent); if [[ -n $d ]] && omarchy-cmd-present "$d"; then echo "$d"; exit; fi; echo; for a; do omarchy-cmd-present "$a" && echo "$a"; done',
      "_"].concat(Model.agents.map(function(a) { return a.id }))
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onAgentCheck(text) }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Timer {
    id: phraseTimer
    interval: 8000
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: panelArt; property: "phraseOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: panelArt; property: "phraseOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  onRotatingPhrasesChanged: {
    if (!rotatingPhrases) {
      phraseSwap.stop()
      panelArt.phraseOpacity = 1.0
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.modeLabel().toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        PanelArt {
          id: panelArt
          width: parent.width
          source: Qt.resolvedUrl("assets/vault-boy-holding-glowing-lightbulb.gif")
          playing: root.opened
          phrase: root.bubblePhrase
        }

        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.accentColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            SequentialAnimation on opacity {
              running: root.charging && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "—" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "—") : (root.batteryFlowIdle ? "—" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : "Rate"
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "—" : (root.batteryInfo.rate || "—"))
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE · " + (root.discharging ? "ON BATTERY" : "ON AC")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: Model.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.focusRow === "profiles" && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusRow = "profiles"
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          Item {
            id: telemetryHeader
            readonly property bool hasCursor: root.cursorActive && root.focusRow === "telemetry"
            width: parent.width
            implicitHeight: Math.max(telemetryTitle.implicitHeight + Style.space(6), reportButton.height)

            PanelSectionHeader {
              id: telemetryTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "TELEMETRY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              id: telemetryChevron
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.telemetryOpen ? "󰅀" : "󰅂"
              color: telemetryTitle.color
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -Style.space(4)
              anchors.rightMargin: -Style.space(4)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.45)
              visible: telemetryHeader.hasCursor && root.headerIndex === 1
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleTelemetry()
            }

            PanelActionButton {
              id: reportButton
              anchors.right: telemetryChevron.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰚩"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              tooltipText: "AI report · shares 7 days of data"
              hasCursor: telemetryHeader.hasCursor && root.headerIndex === 0
              onClicked: root.askAgent()
            }
          }

          BatteryCharts {
            id: charts
            visible: root.telemetryOpen
            width: parent.width
            history: root.batteryHistory
            appUsage: root.appUsage
            foreground: root.accentColor
            fontFamily: root.bar.fontFamily
            tabCursor: root.cursorActive && root.focusRow === "days"
          }

          Row {
            id: viewRow
            visible: root.telemetryOpen
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.viewOptions
              Button {
                required property var modelData
                width: (viewRow.width - viewRow.spacing * (root.viewOptions.length - 1)) / root.viewOptions.length
                iconText: modelData.icon
                text: modelData.label
                tooltipText: modelData.tooltip || ""
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: charts.view === modelData.value
                hasCursor: root.cursorActive && root.focusRow === "views" && active
                onClicked: charts.view = modelData.value
              }
            }
          }

          Column {
            visible: root.agentChoices.length > 0 || root.noAgentInstalled
            width: parent.width
            spacing: Style.space(6)

            InfoLabel {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.noAgentInstalled
                ? "No AI agent installed. Set one up, then ask for the report again."
                : "No usable default agent. Pick one, it becomes your default and opens with the report:"
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.agentChoices
                Button {
                  required property string modelData
                  required property int index
                  text: Model.agentLabel(modelData)
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  hasCursor: root.cursorActive && root.focusRow === "agents" && root.agentIndex === index
                  onClicked: root.launchAgent(modelData)
                }
              }

              Button {
                visible: root.noAgentInstalled
                text: "Set up agent"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                hasCursor: root.cursorActive && root.focusRow === "agents"
                onClicked: root.setupAgent()
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
