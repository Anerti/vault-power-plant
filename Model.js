function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? clamp01(device.percentage) : 0
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v))
}

function historyPush(history, fraction, maxSamples) {
  var next = Array.isArray(history) ? history.slice() : []
  next.push({ t: Date.now(), v: clamp01(fraction) })
  while (next.length > maxSamples) next.shift()
  return next
}

function mergeTelemetry(stored, current, now, maxSamples) {
  var cutoff = now - 7 * 24 * 60 * 60 * 1000
  var all = (Array.isArray(stored.samples) ? stored.samples : []).filter(function(s) {
    return s && typeof s.t === "number" && typeof s.v === "number" && s.v >= 0 && s.v <= 1
  }).map(function(s) { return { t: s.t, v: s.v } }).concat(current.samples || [])
  all.sort(function(a, b) { return a.t - b.t })
  var samples = []
  for (var i = 0; i < all.length; i++) {
    if (samples.length > 0 && all[i].t === samples[samples.length - 1].t) continue
    if (all[i].t >= cutoff) samples.push(all[i])
  }
  var apps = {}
  var dayCutoff = dayStart(now, 6)
  for (var day in stored.apps || {}) {
    if (isNaN(day) || Number(day) < dayCutoff) continue
    apps[day] = {}
    for (var app in stored.apps[day]) if (typeof stored.apps[day][app] === "number" && stored.apps[day][app] > 0) apps[day][app] = stored.apps[day][app]
  }
  return { samples: samples.slice(Math.max(0, samples.length - maxSamples)), apps: Object.assign(apps, current.apps) }
}

function dayStart(now, offset) {
  var d = new Date(now)
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - offset)
  return d.getTime()
}

function dayBuckets(history, start, end, count) {
  var h = Array.isArray(history) ? history : []
  var sums = [], ns = []
  for (var i = 0; i < count; i++) { sums.push(0); ns.push(0) }
  var span = (end - start) / count
  for (var j = 0; j < h.length; j++) {
    if (h[j].t < start || h[j].t >= end) continue
    var k = Math.min(count - 1, Math.floor((h[j].t - start) / span))
    sums[k] += h[j].v
    ns[k]++
  }
  var out = []
  for (var b = 0; b < count; b++) out.push(ns[b] ? clamp01(sums[b] / ns[b]) : null)
  return out
}

function daySummary(history, start, end) {
  var h = (Array.isArray(history) ? history : []).filter(function(s) { return s.t >= start && s.t < end })
  if (h.length === 0) return null
  var s = { min: h[0].v, max: h[0].v, recordedMs: 0, batteryMs: 0, drained: 0, charged: 0 }
  var runStart = -1, runEnd = -1
  var closeRun = function() { if (runStart >= 0) s.batteryMs += runEnd - runStart; runStart = -1 }
  for (var i = 1; i < h.length; i++) {
    var a = h[i - 1], b = h[i]
    s.min = Math.min(s.min, b.v)
    s.max = Math.max(s.max, b.v)
    if (b.t - a.t > 5 * 60 * 1000) { closeRun(); continue }
    s.recordedMs += b.t - a.t
    if (b.v > a.v) {
      s.charged += b.v - a.v
      closeRun()
    } else if (b.v < a.v) {
      s.drained += a.v - b.v
      if (runStart >= 0 && b.t - runEnd > 30 * 60 * 1000) closeRun()
      if (runStart < 0) runStart = a.t
      runEnd = b.t
    }
  }
  closeRun()
  return s
}

function parsePs(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 3 || isNaN(parts[1])) continue
    out[parts[0]] = { s: Number(parts[1]), app: parts.slice(2).join(" ") }
  }
  return out
}

function cpuDeltas(prev, next) {
  var out = {}
  for (var pid in next) {
    var p = prev[pid]
    var d = p && p.app === next[pid].app && p.s <= next[pid].s ? next[pid].s - p.s : next[pid].s
    if (d > 0) out[next[pid].app] = (out[next[pid].app] || 0) + d
  }
  return out
}

function addAppUsage(usage, dayKey, deltas, cutoff) {
  var next = {}
  for (var k in usage || {}) if (Number(k) >= cutoff) next[k] = Object.assign({}, usage[k])
  var day = next[dayKey] || (next[dayKey] = {})
  for (var app in deltas) day[app] = (day[app] || 0) + deltas[app]
  return next
}

function appUsageRows(apps, drained) {
  var names = Object.keys(apps || {})
  var total = names.reduce(function(sum, n) { return sum + apps[n] }, 0)
  if (total <= 0 || !(drained > 0)) return []
  names.sort(function(a, b) { return apps[b] - apps[a] })
  return names.map(function(n) { return [n, drained * apps[n] / total] })
}

function durationLabel(ms) {
  var m = Math.round(ms / 60000)
  return m < 60 ? m + "m" : Math.floor(m / 60) + "h " + m % 60 + "m"
}

function rateLabel(raw, changeRate) {
  if (parseFloat(raw) > 0) return raw
  var r = Math.abs(Number(changeRate) || 0)
  return r > 0 ? Math.round(r * 10) / 10 + "W" : raw
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function batteryFull(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent || onBattery || chargeThresholdActive(d, onBattery, states)) return false
  return d.state === states.FullyCharged || d.percentage >= 1
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (batteryFull(d, onBattery, states)) return "Fully charged"
  return "Charging"
}

var agents = [
  { id: "claude", label: "Claude" },
  { id: "codex", label: "Codex" },
  { id: "copilot", label: "Copilot" },
  { id: "cursor-agent", label: "Cursor CLI" },
  { id: "gemini", label: "Gemini" },
  { id: "grok", label: "Grok" },
  { id: "hermes", label: "Hermes" },
  { id: "muse", label: "Muse Code" },
  { id: "omp", label: "omp" },
  { id: "openclaw", label: "OpenClaw" },
  { id: "opencode", label: "OpenCode" },
  { id: "pi", label: "Pi" }
]

function agentLabel(id) {
  for (var i = 0; i < agents.length; i++) if (agents[i].id === id) return agents[i].label
  return id
}

function parseAgentCheck(raw) {
  var lines = String(raw || "").split("\n")
  var installed = []
  for (var i = 1; i < lines.length; i++) if (lines[i].trim()) installed.push(lines[i].trim())
  return { defaultAgent: lines[0].trim(), installed: installed }
}

function agentPrompt(history, now, info, profile, appUsage) {
  var status = Object.keys(info || {}).map(function(k) { return k + " " + info[k] }).join(", ")
  var days = [], appDays = []
  for (var offset = 6; offset >= 0; offset--) {
    var start = dayStart(now, offset)
    var end = dayStart(now, offset - 1)
    var slots = dayBuckets(history, start, end, 96)
    var d = new Date(start)
    var label = d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2) + " " +
      ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()]
    var empty = slots.every(function(v) { return v === null })
    days.push(label + ": " + (empty ? "no data" : slots.map(function(v) { return v === null ? "-" : Math.round(v * 100) }).join(" ")))
    var s = daySummary(history, start, end)
    var apps = (appUsage || {})[start] || {}
    var rows = appUsageRows(apps, s ? s.drained : 0).slice(0, 10)
    if (rows.length > 0) appDays.push(label + ": " + rows.map(function(r) {
      return r[0] + " " + Math.round(r[1] * 1000) / 10 + "% (" + Math.round(apps[r[0]] / 60) + " CPU min)"
    }).join(", "))
  }
  return [
    "Act as a data scientist specialised in laptop power and battery health. Analyse my battery usage over the last 7 days and tell me how to get the best out of this laptop's battery.",
    "",
    "Use only the data in this message. Do not run commands, read files, search the web or use any tool: everything available is below. If a question cannot be answered from this data, say so instead of looking it up.",
    "",
    "Battery now: " + (status || "unknown") + ".",
    "Active power profile: " + (profile || "unknown") + ".",
    "",
    "Charge level in % per 15-minute slot, local time, 96 slots per day from 00:00. \"-\" means no sample: the laptop was off, asleep or the desktop shell was not running.",
    days.join("\n"),
    "",
    "Battery drain per app, top 10 per day: estimated % of battery each app used, then the CPU minutes it ran while on battery. The day's measured drain is split between apps by their share of on-battery CPU time, so screen and idle drain are spread across them too. Process names are cut to 15 characters.",
    appDays.length > 0 ? appDays.join("\n") : "No per-app data recorded yet.",
    "",
    "Give me:",
    "1. A short summary of the week: hours on battery vs plugged in, average and peak drain (%/h), typical charge sessions, time spent above 80% and below 20%.",
    "2. A per-day table: date, min and max charge, hours on battery, average drain.",
    "3. Anything unusual: fast drains, deep discharges, long stretches held at 100%.",
    "4. Which apps or processes cost the most battery across the week, which ones look abnormal (a background process with heavy CPU time, a drain spike tied to one app), and what to do about each.",
    "5. The 3 to 5 changes that would help most (charge limit, power profile, charging habits, sleep, heavy apps), each with the evidence from my data and the expected gain.",
    "",
    "Do not change any system setting. When a change needs a command, show it to me instead. Keep it short and concrete, with numbers."
  ].join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    batteryFull: batteryFull,
    clamp01: clamp01,
    historyPush: historyPush,
    mergeTelemetry: mergeTelemetry,
    dayStart: dayStart,
    dayBuckets: dayBuckets,
    daySummary: daySummary,
    durationLabel: durationLabel,
    parsePs: parsePs,
    cpuDeltas: cpuDeltas,
    addAppUsage: addAppUsage,
    appUsageRows: appUsageRows,
    rateLabel: rateLabel,
    agents: agents,
    agentLabel: agentLabel,
    parseAgentCheck: parseAgentCheck,
    agentPrompt: agentPrompt
  }
}
