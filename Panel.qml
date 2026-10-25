import QtQuick
import Quickshell
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

  property var batteryHistory: []
  readonly property int batteryHistoryMax: 7 * 1440
  readonly property string telemetryDataDir: Quickshell.env("HOME") + "/.config/omarchy/vault-power-plant"
  readonly property string telemetryHistoryPath: telemetryDataDir + "/history.json"
  property bool telemetryReady: false
  property bool telemetryBackupAttempted: false
  // Installed agents to pick from when no default agent is set; empty hides the picker.
  property var agentChoices: []
  property bool noAgentInstalled: false
  property int agentIndex: 0
  // 0 = summary toggle, 1 = AI report.
  property int actionIndex: 0
  // Keyboard rows, top to bottom as drawn: up/down picks the row, left/right moves within it.
  property string focusRow: "profiles"
  readonly property var focusRows: agentChoices.length > 0 || noAgentInstalled
    ? ["profiles", "days", "actions", "agents"]
    : ["profiles", "days", "actions"]
  readonly property bool showPercentage: setting("showPercentage", false) === true

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
    } else if (focusRow === "days") {
      // Tabs run oldest to newest, so right means a smaller day offset.
      charts.dayOffset = Math.max(0, Math.min(6, charts.dayOffset - dx))
    } else if (focusRow === "actions") {
      actionIndex = Model.clampIndex(actionIndex + dx, 2)
    } else if (focusRow === "agents") {
      agentIndex = Model.clampIndex(agentIndex + dx, Math.max(1, agentChoices.length))
    }
  }

  function activateCursor() {
    if (focusRow === "profiles") activateSelectedProfile()
    else if (focusRow === "actions") {
      if (actionIndex === 0) charts.showSummary = !charts.showSummary
      else askAgent()
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

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
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
    if (fullyCharged) return []
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

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function onTelemetryLoaded() {
    var list = telemetryAdapter.samples
    // JsonAdapter hands back a Qt sequence, not a JS array, so Array.isArray() is false here.
    var checks = list ? Array.from(list) : []
    var clean = []
    for (var i = 0; i < checks.length; i++) {
      var s = checks[i]
      if (s && typeof s.t === "number" && typeof s.v === "number" && s.v >= 0 && s.v <= 1)
        clean.push({ t: s.t, v: s.v })
    }
    clean = clean.concat(root.batteryHistory)
    clean.sort(function(a, b) { return a.t - b.t })
    var cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000
    var kept = []
    for (var j = 0; j < clean.length; j++) {
      if (kept.length > 0 && clean[j].t === kept[kept.length - 1].t) continue
      if (clean[j].t >= cutoff) kept.push(clean[j])
    }
    while (kept.length > root.batteryHistoryMax) kept.shift()
    root.batteryHistory = kept
    root.telemetryReady = true
  }

  function onTelemetryLoadFailed() {
    console.warn("anerti.vault-power-plant: telemetry history load failed, starting empty")
    if (!root.telemetryBackupAttempted) {
      root.telemetryBackupAttempted = true
      telemetryBackupProc.running = true
    }
    root.telemetryReady = true
  }

  function persistHistory() {
    if (!root.telemetryReady) return
    // start(), not restart(): the next sample lands before 10 min, so restart() would never fire.
    if (!telemetrySaveTimer.running) telemetrySaveTimer.start()
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
      // Pressed from the keyboard: land on the choices that just appeared.
      if (cursorActive && focusRow === "actions") focusRow = "agents"
    }
  }

  // Omarchy's picker also installs; it opens the agent without our prompt, so the user retries the report after.
  function setupAgent() {
    close()
    Util.execArgv(["omarchy-menu", "summon", "setup.default.agent"])
  }

  // Saves `pick` as Omarchy's default agent (when given), then opens the default agent with the prompt.
  // Writes the defaults file directly: omarchy-default-agent would open the agent itself, without the prompt.
  function launchAgent(pick) {
    Util.execArgv(["bash", "-c",
      'if [[ -n $1 ]]; then mkdir -p "$HOME/.config/omarchy/defaults" && printf "%s\\n" "$1" > "$HOME/.config/omarchy/defaults/agent" || exit 1; fi; exec omarchy-agent --prompt "$2"',
      "_", pick, Model.agentPrompt(root.batteryHistory, Date.now(), root.batteryInfo, root.activeProfile)])
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
      actionIndex = 0
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

  FileView {
    id: telemetryFile
    path: root.telemetryHistoryPath
    printErrors: true
    atomicWrites: true
    onLoaded: root.onTelemetryLoaded()
    onLoadFailed: root.onTelemetryLoadFailed()

    JsonAdapter {
      id: telemetryAdapter
      property var samples: []
    }
  }

  Process {
    id: telemetryEnsureDirProc
    command: ["bash", "-c",
      "mkdir -p \"$1\"; [[ -f \"$2\" ]] || printf '{\"samples\":[]}\\n' > \"$2\"",
      "_", root.telemetryDataDir, root.telemetryHistoryPath]
    onExited: telemetryFile.reload()
  }

  Process {
    id: telemetryBackupProc
    // Without python3 we cannot tell a corrupt file from a valid one, so leave it alone.
    command: ["bash", "-c",
      "if [[ -s \"$1\" ]] && command -v python3 >/dev/null && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$1\" 2>/dev/null; then mv -f \"$1\" \"$1.corrupt-$(date +%s)\"; fi",
      "_", root.telemetryHistoryPath]
  }

  // Batch writes: the full 7-day history is ~10k samples, too much to rewrite every minute.
  Timer {
    id: telemetrySaveTimer
    interval: 10 * 60 * 1000
    repeat: false
    onTriggered: {
      telemetryAdapter.samples = root.batteryHistory
      telemetryFile.writeAdapter()
    }
  }

  Process {
    id: agentCheckProc
    // Login shell so agents installed through mise are on PATH, as Util.execArgv does for the launch.
    command: ["bash", "-lc",
      'd=$(omarchy-default-agent); if [[ -n $d ]] && omarchy-cmd-present "$d"; then echo "$d"; exit; fi; echo; for a; do omarchy-cmd-present "$a" && echo "$a"; done',
      "_"].concat(Model.agents.map(function(a) { return a.id }))
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onAgentCheck(text) }
  }

  Component.onCompleted: telemetryEnsureDirProc.running = true

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.batteryPresent || !root.telemetryReady) return
      root.batteryHistory = Model.historyPush(root.batteryHistory, root.batteryFraction, root.batteryHistoryMax)
      root.persistHistory()
    }
  }

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
              running: root.charging && !root.fullyCharged && root.opened
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
            // Omarchy keeps one profile for AC and one for battery; this sets the current source's.
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

          PanelSectionHeader {
            text: "TELEMETRY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          BatteryCharts {
            id: charts
            width: parent.width
            history: root.batteryHistory
            foreground: root.accentColor
            fontFamily: root.bar.fontFamily
            tabCursor: root.cursorActive && root.focusRow === "days"
          }

          Row {
            id: actionRow
            width: parent.width
            spacing: Style.space(6)

            Button {
              width: (actionRow.width - actionRow.spacing) / 2
              iconText: charts.showSummary ? "󰄪" : "󰉹"
              text: charts.showSummary ? "Chart" : "Summary"
              tooltipText: charts.showSummary ? "Show the selected day's chart" : "Show the selected day's stats"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              hasCursor: root.cursorActive && root.focusRow === "actions" && root.actionIndex === 0
              onClicked: charts.showSummary = !charts.showSummary
            }

            Button {
              width: (actionRow.width - actionRow.spacing) / 2
              iconText: "󰚩"
              text: "AI report"
              tooltipText: "Ask an AI agent to analyse the last 7 days"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              hasCursor: root.cursorActive && root.focusRow === "actions" && root.actionIndex === 1
              onClicked: root.askAgent()
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
