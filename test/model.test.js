const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const test = require("node:test");

const source = fs.readFileSync(new URL("../Model.js", `file://${__dirname}/`), "utf8")
  .replace(/^\.pragma library\s*/m, "");
const model = {};
vm.createContext(model);
vm.runInContext(source, model);

test("parseConfig normalizes persisted values", () => {
  assert.deepEqual(
    JSON.parse(JSON.stringify(model.parseConfig('{"screensaver":600,"display":120,"lock":900,"sleep":3600}'))),
    { screensaver: 600, display: 120, lock: 900, sleep: 3600 }
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(model.parseConfig("broken"))),
    { screensaver: 150, display: 0, lock: 300, sleep: 0 }
  );
});

test("formatDuration produces compact labels", () => {
  assert.equal(model.formatDuration(0), "Off");
  assert.equal(model.formatDuration(300), "5 min");
  assert.equal(model.formatDuration(3600), "1 hour");
  assert.equal(model.formatDuration(7200), "2 hours");
});

test("requestedSeconds rejects unusable values instead of coercing to Off", () => {
  assert.equal(model.requestedSeconds(-5), -1);
  assert.equal(model.requestedSeconds("nonsense"), -1);
  assert.equal(model.requestedSeconds(Infinity), -1);
  // 0 is only ever Off when the caller asks for it explicitly.
  assert.equal(model.requestedSeconds(0), 0);
  assert.equal(model.requestedSeconds(900), 900);
});

test("requestedSeconds rejects oversized values rather than clamping them", () => {
  // Clamping would turn an absurd setLock into a seven-day timeout, the same
  // silent weakening this guard exists to prevent. Reject, as the CLI does.
  assert.equal(model.requestedSeconds(2000000000), -1);
  assert.equal(model.requestedSeconds(model.maxTimeoutSeconds + 1), -1);
  assert.equal(model.requestedSeconds(model.maxTimeoutSeconds), model.maxTimeoutSeconds);
});

test("normalizedSeconds clamps persisted values below the 32-bit overflow", () => {
  // A config written before the bounds existed has no caller to reject to.
  assert.equal(model.normalizedSeconds(2000000000, 0, true), model.maxTimeoutSeconds);
  assert.ok(model.maxTimeoutSeconds * 1000 < 2147483647);
});

test("parseConfig bounds oversized persisted values", () => {
  const parsed = model.parseConfig('{"screensaver":150,"lock":300,"sleep":2000000000}');
  assert.equal(parsed.sleep, model.maxTimeoutSeconds);
  assert.ok(parsed.sleep * 1000 < 2147483647);
});

test("statusSummary includes all stages", () => {
  assert.equal(
    model.statusSummary(300, 120, 600, 1800),
    "Screen 5 min · Displays 2 min · Lock 10 min · Sleep 30 min"
  );
});
