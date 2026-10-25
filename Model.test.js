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

console.log("Model.test.js: ok")
