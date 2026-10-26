import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "Model.js" as Model

// One per shell: the bar widget exists once per monitor, so sampling and history.json live here.
Item {
  id: root
  visible: false

  property var batteryHistory: []
  property var appUsage: ({})
  property bool telemetryReady: false
  property var appsPrev: null
  readonly property int batteryHistoryMax: 7 * 1440
  readonly property string telemetryDataDir: Quickshell.env("HOME") + "/.config/omarchy/vault-power-plant"
  readonly property string telemetryHistoryPath: telemetryDataDir + "/history.json"

  readonly property bool batteryPresent: !!(UPower.displayDevice && UPower.displayDevice.isPresent)
  readonly property bool discharging: batteryPresent && UPower.onBattery

  function onTelemetryLoaded() {
    var stored = { samples: Array.from(telemetryAdapter.samples || []), apps: telemetryAdapter.apps }
    // JsonAdapter reports broken JSON as a normal empty load; set the file aside before a save overwrites it
    try { JSON.parse(telemetryFile.text()) } catch (e) {
      console.warn("anerti.vault-power-plant: history.json is corrupt, moving it aside and starting fresh")
      stored = {}
      if (!telemetryBackupProc.running) telemetryBackupProc.running = true
    }
    var merged = Model.mergeTelemetry(stored, { samples: root.batteryHistory, apps: root.appUsage },
      Date.now(), root.batteryHistoryMax)
    root.batteryHistory = merged.samples
    root.appUsage = merged.apps
    root.telemetryReady = true
  }

  function onAppsSample(raw) {
    var next = Model.parsePs(raw)
    if (root.appsPrev && root.discharging) {
      root.appUsage = Model.addAppUsage(root.appUsage, String(Model.dayStart(Date.now(), 0)),
        Model.cpuDeltas(root.appsPrev, next), Model.dayStart(Date.now(), 6))
    }
    root.appsPrev = root.discharging ? next : null
  }

  function saveTelemetry() {
    if (!root.telemetryReady) return
    telemetryAdapter.samples = root.batteryHistory
    telemetryAdapter.apps = root.appUsage
    telemetryFile.writeAdapter()
  }

  Component.onCompleted: telemetryEnsureDirProc.running = true
  Component.onDestruction: saveTelemetry()

  FileView {
    id: telemetryFile
    path: root.telemetryHistoryPath
    printErrors: true
    atomicWrites: true
    // the file is small; a blocking write lets the save on destruction finish
    blockWrites: true
    onLoaded: root.onTelemetryLoaded()
    // a missing file is created by telemetryEnsureDirProc; an unreadable one is left alone
    onLoadFailed: root.telemetryReady = true

    JsonAdapter {
      id: telemetryAdapter
      property var samples: []
      property var apps: ({})
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
    command: ["bash", "-c", "[[ -s \"$1\" ]] && mv -f \"$1\" \"$1.corrupt-$(date +%s%N)\"",
      "_", root.telemetryHistoryPath]
  }

  Timer {
    id: telemetrySaveTimer
    interval: 10 * 60 * 1000
    onTriggered: root.saveTelemetry()
  }

  Process {
    id: appsProc
    command: ["ps", "-eo", "pid=,times=,comm="]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onAppsSample(text) }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.batteryPresent || !root.telemetryReady) return
      root.batteryHistory = Model.historyPush(root.batteryHistory, Model.batteryFraction(UPower.displayDevice), root.batteryHistoryMax)
      if (!telemetrySaveTimer.running) telemetrySaveTimer.start()
      if (root.discharging) { if (!appsProc.running) appsProc.running = true }
      else root.appsPrev = null
    }
  }
}
