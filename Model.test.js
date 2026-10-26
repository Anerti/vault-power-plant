const assert = require("node:assert")
const M = require("./Model.js")

const states = { Charging: 1, Discharging: 2, FullyCharged: 4, PendingCharge: 5 }
const battery = (percentage, state, extra) => Object.assign({ isPresent: true, percentage, state }, extra)

const noon = new Date(2026, 0, 15, 12).getTime()
const start = M.dayStart(noon, 0)
const end = M.dayStart(noon, -1)
assert.strictEqual(end - start, 24 * 60 * 60 * 1000)
assert.strictEqual(M.dayStart(noon, 1), start - 24 * 60 * 60 * 1000)

const buckets = M.dayBuckets([
  { t: start - 1, v: 0.9 },
  { t: start, v: 0.25 },
  { t: start + 1000, v: 0.75 },
  { t: end - 1, v: 1 },
  { t: end, v: 0.1 }
], start, end, 24)
assert.strictEqual(buckets.length, 24)
assert.strictEqual(buckets[0], 0.5)
assert.strictEqual(buckets[23], 1)
assert.strictEqual(buckets.filter(b => b !== null).length, 2)
assert.deepStrictEqual(M.dayBuckets([], start, end, 4), [null, null, null, null])

const merged = M.mergeTelemetry({
  samples: [{ t: noon - 8 * 24 * 3600 * 1000, v: 0.5 }, { t: noon - 2000, v: 0.7 }, { t: noon - 1000, v: 2 }, null, { t: "x", v: 0.1 }, { t: noon, v: 0.6 }],
  apps: { [M.dayStart(noon, 7)]: { old: 5 }, [start]: { brave: 10, bad: "x", zero: 0 }, junk: { a: 1 } }
}, { samples: [{ t: noon, v: 0.61 }, { t: noon + 1000, v: 0.62 }], apps: { [start]: { brave: 12 } } }, noon, 2)
assert.deepStrictEqual(merged.samples, [{ t: noon, v: 0.6 }, { t: noon + 1000, v: 0.62 }],
  "bad, stale and duplicate samples dropped, then capped")
assert.deepStrictEqual(merged.apps, { [start]: { brave: 12 } }, "stale and junk days dropped, the live day wins")
assert.deepStrictEqual(M.mergeTelemetry({}, {}, noon, 10), { samples: [], apps: {} })

const min = 60 * 1000
const day = []
for (let m = 0; m <= 60; m++) day.push({ t: start + m * min, v: 1 })
for (let k = 1; k <= 60; k++) day.push({ t: start + (60 + k) * min, v: 1 - 0.01 * k })
for (let k = 0; k <= 10; k++) day.push({ t: start + (200 + k) * min, v: 0.4 + 0.01 * k })
const summary = M.daySummary(day, start, end)
assert.strictEqual(Math.round(summary.min * 100), 40)
assert.strictEqual(summary.max, 1)
assert.strictEqual(summary.batteryMs, 60 * min, "the plateau at 100% is not battery time")
assert.strictEqual(Math.round(summary.drained * 100), 60)
assert.strictEqual(Math.round(summary.charged * 100), 10)
assert.strictEqual(summary.recordedMs, 130 * min, "the gap is not recorded time")
assert.strictEqual(M.daySummary(day, end, end + 1000), null)
const held = []
for (let m = 0; m <= 360; m++) held.push({ t: start + m * min, v: m < 180 ? 0.8 : m < 360 ? 0.79 : 0.78 })
assert.strictEqual(M.daySummary(held, start, end).batteryMs, 2 * min, "a slow drop at a charge limit is not battery time")
assert.strictEqual(M.durationLabel(45 * min), "45m")
assert.strictEqual(M.durationLabel(130 * min), "2h 10m")

const ps1 = M.parsePs("  10   100 brave\n  11     5 claude\n  12     7 Web Content\n")
assert.deepStrictEqual(ps1["12"], { s: 7, app: "Web Content" })
const ps2 = M.parsePs("  10   130 brave\n  11     5 claude\n  12     2 bash\n  13     4 brave\n")
assert.deepStrictEqual(M.cpuDeltas(ps1, ps2), { brave: 34, bash: 2 }, "idle claude skipped, reused pid 12 and new pid 13 count in full")
const usage = M.addAppUsage({ 1: { old: 9 }, 100: { brave: 6 } }, "100", { brave: 34, bash: 2 }, 50)
assert.deepStrictEqual(usage, { 100: { brave: 40, bash: 2 } }, "days before the cutoff are dropped")
assert.deepStrictEqual(M.appUsageRows({ claude: 10, brave: 30, bash: 0 }, 0.4), [["brave", 0.3], ["claude", 0.1], ["bash", 0]])
assert.deepStrictEqual(M.appUsageRows({ brave: 30 }, 0), [], "no drain, nothing to split")
assert.deepStrictEqual(M.appUsageRows(undefined, 0.4), [])

assert.strictEqual(M.rateLabel("12.5W", 3), "12.5W")
assert.strictEqual(M.rateLabel("0W", -5.6377), "5.6W")
assert.strictEqual(M.rateLabel("0W", 0), "0W")

assert.strictEqual(M.modeLabel(battery(0.99, states.FullyCharged), false, states), "Fully charged")
assert.strictEqual(M.batteryIcon(battery(0.99, states.FullyCharged), false, states), "󰂅")
assert.strictEqual(M.modeLabel(battery(1, states.Charging), false, states), "Fully charged")
assert.strictEqual(M.modeLabel(battery(0.5, states.Charging, { changeRate: 20, timeToFull: 3600 }), false, states), "Charging")
assert.strictEqual(M.modeLabel(battery(0.5, states.Discharging), true, states), "On battery")
assert.strictEqual(M.modeLabel({ isPresent: false }, false, states), "")
assert.strictEqual(M.batteryFull(battery(1, states.Charging), false, states), true)
assert.strictEqual(M.batteryFull(battery(1, states.FullyCharged), true, states), false)
assert.strictEqual(M.batteryFull(battery(0.8, states.FullyCharged), false, states), false, "held at a limit is not full")

assert.strictEqual(M.chargeThresholdActive(battery(0.8, states.FullyCharged), false, states), true)
assert.strictEqual(M.chargeThresholdActive(battery(0.8, states.PendingCharge), false, states), true)
assert.strictEqual(M.chargeThresholdActive(battery(0.5, states.Charging, { changeRate: 0.1 }), false, states), true)
assert.strictEqual(M.chargeThresholdActive(battery(0.5, states.Charging, { changeRate: 20, timeToFull: 3600 }), false, states), false)
assert.strictEqual(M.chargeThresholdActive(battery(0.8, states.FullyCharged), true, states), false)
assert.strictEqual(M.modeLabel(battery(0.8, states.FullyCharged), false, states), "Threshold")

assert.deepStrictEqual(M.parseAgentCheck("opencode\n"), { defaultAgent: "opencode", installed: [] })
assert.deepStrictEqual(M.parseAgentCheck("\nclaude\ncodex\n"), { defaultAgent: "", installed: ["claude", "codex"] })
assert.deepStrictEqual(M.parseAgentCheck(""), { defaultAgent: "", installed: [] })
assert.strictEqual(M.agentLabel("cursor-agent"), "Cursor CLI")
assert.strictEqual(M.agentLabel("unknown"), "unknown")

const prompt = M.agentPrompt([{ t: start, v: 0.5 }, { t: start + 15 * 60 * 1000, v: 0.48 }], noon, { cycles: "19" }, "balanced")
assert.ok(prompt.includes("Do not run commands"))
assert.ok(prompt.includes("cycles 19") && prompt.includes("balanced"))
assert.ok(prompt.includes("Thu: 50 48 - "), "today's slots, gaps as -")
assert.ok(prompt.includes("Fri: no data"), "days before the history are marked empty")
assert.ok(!/history\.json|upower|journalctl/.test(prompt))
assert.ok(prompt.includes("No per-app data recorded yet."))
const appPrompt = M.agentPrompt([{ t: start, v: 0.5 }, { t: start + 60 * 1000, v: 0.46 }], noon, {}, "", { [start]: { brave: 1800, claude: 600 } })
assert.ok(appPrompt.includes("Thu: brave 3% (30 CPU min), claude 1% (10 CPU min)"), appPrompt)
const fullWeek = []
for (let t = M.dayStart(noon, 6); t < noon; t += 60 * 1000) fullWeek.push({ t, v: (t / 60000) % 2 ? 0.9 : 0.89 })
const fullApps = {}
for (let o = 0; o < 7; o++) {
  fullApps[M.dayStart(noon, o)] = {}
  for (let a = 0; a < 300; a++) fullApps[M.dayStart(noon, o)]["process-name-" + a] = a + 1
}
assert.ok(M.agentPrompt(fullWeek, noon, {}, "", fullApps).length < 16000, "prompt goes through argv, keep it small")

console.log("Model.test.js: ok")
