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
    JSON.parse(JSON.stringify(model.parseConfig('{"screensaver":600,"sleep":3600}'))),
    { screensaver: 600, sleep: 3600 }
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(model.parseConfig("broken"))),
    { screensaver: 150, sleep: 0 }
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(model.parseConfig('{"screensaver":0,"sleep":0}'))),
    { screensaver: 0, sleep: 0 }
  );
});

test("formatDuration produces compact labels", () => {
  assert.equal(model.formatDuration(0), "Off");
  assert.equal(model.formatDuration(300), "5 min");
  assert.equal(model.formatDuration(3600), "1 hour");
  assert.equal(model.formatDuration(7200), "2 hours");
});

test("statusSummary includes both stages", () => {
  assert.equal(model.statusSummary(300, 1800), "Screen 5 min · Sleep 30 min");
});
