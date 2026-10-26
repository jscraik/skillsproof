// Exercise the real rendered command and clipboard handler without app startup.
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
const source = readFileSync(join(__dirname, '../verification/prototypes/prototype.js'), 'utf8');
const button = {dataset: {action: 'copy-tessl-fix'}};
const controls = {registry: {value: 'live'}, tesslExample: {value: 'missing'}};
const context = vm.createContext({
  document: {
    addEventListener() {},
    getElementById(id) { return controls[id] || null; },
    querySelector() { return null; },
    querySelectorAll(selector) { return selector === '[data-action]' ? [button] : []; },
  },
  window: {}, Date,
});
// Definitions are the production code; omit only the browser bootstrap tail.
vm.runInContext(source.slice(0, source.indexOf('if(new URLSearchParams')), context);
vm.runInContext('copy = (text) => { globalThis.copied = text; };', context);
const paths = ["/tmp/normal path/SKILL.md", "/tmp/a'; printf INJECTED; #/SKILL.md", "/tmp/$(printf BAD)/`printf BAD`/SKILL.md", "~/a'b/SKILL.md"];
for (const path of paths) {
  context.inputPath = path;
  const html = vm.runInContext('skill.path = inputPath; bind(); registry()', context);
  button.onclick();
  const command = context.copied;
  // A harmless shell function replaces tessl: no real CLI or network operation.
  const result = spawnSync('/bin/sh', ['-c', 'tessl() { printf "%s\\0" "$@"; }; ' + command], {encoding: 'utf8', timeout: 2000});
  assert.equal(result.status, 0);
  assert.deepEqual(result.stdout.split('\0'), ['review', 'fix', path.replace(/^~/, '/Users/jamiecraik'), '']);
  const escaped = command.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  assert.ok(html.includes(escaped), 'rendered command must match clipboard command');
}
console.log('Prototype command round trips passed (4 paths; no real tessl execution).');
