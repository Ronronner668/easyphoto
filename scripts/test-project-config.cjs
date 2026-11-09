const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const directory = path.resolve(__dirname, '../.test/project-config');
fs.mkdirSync(directory, { recursive: true });
const tool = path.join(__dirname, 'project-config.cjs');
function execute(...args) { return execFileSync(process.execPath, [tool, ...args], { encoding: 'utf8', windowsHide: true }); }
const fixture = path.join(directory, 'unicode.json5');
fs.writeFileSync(fixture, '\uFEFF' + `// comment
{module:{name:'entry', note:'中文😀', url:'https://example.invalid/a//b/*literal*/',
requestPermissions:[{name:'ohos.permission.READ_IMAGEVIDEO'}], abilities:[{name:'EntryAbility'}],},}`);
const ascii = execute('read', fixture);
assert.ok(/^[\x20-\x7E]+$/.test(ascii));
assert.equal(JSON.parse(ascii).module.note, '中文😀');
console.log('PASS native stdout remains ASCII while preserving Unicode and surrogate pairs');
execute('write-probes', fixture, 'enable');
const first = fs.readFileSync(fixture);
execute('write-probes', fixture, 'enable');
assert.deepEqual(fs.readFileSync(fixture), first);
const configured = JSON.parse(execute('read', fixture));
assert.equal(configured.module.note, '中文😀');
assert.equal(configured.module.url, 'https://example.invalid/a//b/*literal*/');
assert.equal(configured.module.requestPermissions[1].reason, '$string:gallery_write_reason');
console.log('PASS enable is byte-idempotent and preserves unrelated values and literal resource references');
for (const [name, content] of [
  ['malformed', '{module:[}'],
  ['missing-permissions', '{module:{name:"entry"}}'],
  ['nonfinite', '{module:{requestPermissions:[]},bad:Infinity}'],
]) {
  const target = path.join(directory, name + '.json5'); fs.writeFileSync(target, content);
  const outcome = spawnSync(process.execPath, [tool, 'write-probes', target, 'enable'], { encoding: 'utf8', windowsHide: true });
  assert.notEqual(outcome.status, 0); assert.equal(fs.readFileSync(target, 'utf8'), content);
  console.log('PASS ' + name + ' fails without changing the original file');
}
const temporary = fixture + '.config-' + process.pid + '.tmp';
fs.writeFileSync(temporary, 'preexisting owned by another attempt');
const beforeCollision = fs.readFileSync(fixture);
assert.throws(() => require('./project-config.cjs').atomicWrite(fixture, { module: {} }));
assert.deepEqual(fs.readFileSync(fixture), beforeCollision);
assert.equal(fs.readFileSync(temporary, 'utf8'), 'preexisting owned by another attempt');
console.log('PASS a temporary-name collision preserves both the original and preexisting temporary file');
console.log('6/6 project configuration checks passed. No dependencies downloaded or global encoding/settings changed.');
