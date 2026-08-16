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

test("statusSummary includes all stages", () => {
  assert.equal(
    model.statusSummary(300, 120, 600, 1800),
    "Screen 5 min · Displays 2 min · Lock 10 min · Sleep 30 min"
  );
});
