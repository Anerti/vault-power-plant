// Run: node Model.test.js
const assert = require("node:assert")
const M = require("./Model.js")

const states = { Charging: 1, Discharging: 2, FullyCharged: 4, PendingCharge: 5 }
const battery = (percentage, state, extra) => Object.assign({ isPresent: true, percentage, state }, extra)

// January: no DST change, so the day is exactly 24h in any time zone.
const noon = new Date(2026, 0, 15, 12).getTime()
const start = M.dayStart(noon, 0)
const end = M.dayStart(noon, -1)
assert.strictEqual(end - start, 24 * 60 * 60 * 1000)
assert.strictEqual(M.dayStart(noon, 1), start - 24 * 60 * 60 * 1000)

// dayBuckets keeps [start, end), averages each slot and leaves empty slots null.
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

// daySummary: an hour held at 100% plugged in, an hour draining to 40%, a gap, then 10 minutes charging.
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
// Plugged in at a charge limit: 80% for 3h, self-discharge to 79%, 3h more, to 78%. Only the two drops count.
const held = []
for (let m = 0; m <= 360; m++) held.push({ t: start + m * min, v: m < 180 ? 0.8 : m < 360 ? 0.79 : 0.78 })
assert.strictEqual(M.daySummary(held, start, end).batteryMs, 2 * min, "a slow drop at a charge limit is not battery time")
assert.strictEqual(M.durationLabel(45 * min), "45m")
assert.strictEqual(M.durationLabel(130 * min), "2h 10m")

// The status script reads 0W on batteries whose power_now fails; UPower's rate fills in.
assert.strictEqual(M.rateLabel("12.5W", 3), "12.5W")
assert.strictEqual(M.rateLabel("0W", -5.6377), "5.6W")
assert.strictEqual(M.rateLabel("0W", 0), "0W")

// Full at 99% (common battery behaviour) must read as full, like the icon.
assert.strictEqual(M.modeLabel(battery(0.99, states.FullyCharged), false, states), "Fully charged")
assert.strictEqual(M.batteryIcon(battery(0.99, states.FullyCharged), false, states), "󰂅")
assert.strictEqual(M.modeLabel(battery(1, states.Charging), false, states), "Fully charged")
assert.strictEqual(M.modeLabel(battery(0.5, states.Charging, { changeRate: 20, timeToFull: 3600 }), false, states), "Charging")
assert.strictEqual(M.modeLabel(battery(0.5, states.Discharging), true, states), "On battery")
assert.strictEqual(M.modeLabel({ isPresent: false }, false, states), "")

// Charge limit: plugged in but held below full.
assert.strictEqual(M.chargeThresholdActive(battery(0.8, states.FullyCharged), false, states), true)
assert.strictEqual(M.chargeThresholdActive(battery(0.8, states.PendingCharge), false, states), true)
assert.strictEqual(M.chargeThresholdActive(battery(0.5, states.Charging, { changeRate: 0.1 }), false, states), true)
assert.strictEqual(M.chargeThresholdActive(battery(0.5, states.Charging, { changeRate: 20, timeToFull: 3600 }), false, states), false)
assert.strictEqual(M.chargeThresholdActive(battery(0.8, states.FullyCharged), true, states), false)
assert.strictEqual(M.modeLabel(battery(0.8, states.FullyCharged), false, states), "Threshold")

// Agent check: default first, installed agents after; an unset default leaves the first line empty.
assert.deepStrictEqual(M.parseAgentCheck("opencode\n"), { defaultAgent: "opencode", installed: [] })
assert.deepStrictEqual(M.parseAgentCheck("\nclaude\ncodex\n"), { defaultAgent: "", installed: ["claude", "codex"] })
assert.deepStrictEqual(M.parseAgentCheck(""), { defaultAgent: "", installed: [] })
assert.strictEqual(M.agentLabel("cursor-agent"), "Cursor CLI")
assert.strictEqual(M.agentLabel("unknown"), "unknown")

// The prompt carries the data itself, so the agent never needs a command or file.
const prompt = M.agentPrompt([{ t: start, v: 0.5 }, { t: start + 15 * 60 * 1000, v: 0.48 }], noon, { cycles: "19" }, "balanced")
assert.ok(prompt.includes("Do not run commands"))
assert.ok(prompt.includes("cycles 19") && prompt.includes("balanced"))
assert.ok(prompt.includes("Thu: 50 48 - "), "today's slots, gaps as -")
assert.ok(prompt.includes("Fri: no data"), "days before the history are marked empty")
assert.ok(!/history\.json|upower|journalctl/.test(prompt))
const fullWeek = []
for (let t = M.dayStart(noon, 6); t < noon; t += 60 * 1000) fullWeek.push({ t, v: 1 })
assert.ok(M.agentPrompt(fullWeek, noon, {}, "").length < 16000, "prompt goes through argv, keep it small")

console.log("Model.test.js: ok")
