// Host tests for pure result interpretation only; no mocked platform success.
const path = require('node:path');
const assert = require('node:assert/strict');
const loadEts = require('./ets-test-runtime.cjs').createLoader();
const root = path.resolve(__dirname, '..');
const { assessReadPermission } = loadEts(path.join(root, 'entry/src/main/ets/domain/usecases/AssessReadPermission.ets'));
const { ProbeStatus } = loadEts(path.join(root, 'entry/src/main/ets/domain/models/ProbeResult.ets'));
const cases = [
  ['granted after dialog', [0, true, 0, true], ProbeStatus.Observed, false],
  ['granted without another dialog', [0, false, 0, true], ProbeStatus.Observed, false],
  ['explicit denial', [-1, true, 0, false], ProbeStatus.Blocked, true],
  ['denied with dialog suppressed', [-1, false, 0, false], ProbeStatus.Blocked, true],
  ['invalid permission request', [2, false, 0, false], ProbeStatus.Blocked, false],
  ['missing declaration reason', [-1, false, 2, false], ProbeStatus.Blocked, false],
  ['incomplete platform response', [undefined, undefined, undefined, false], ProbeStatus.Blocked, false],
  ['reported grant but access check denied', [0, true, 0, false], ProbeStatus.Blocked, false],
];
for (const [name, input, status, canOpenSettings] of cases) {
  const result = assessReadPermission(...input);
  assert.equal(result.status, status, name);
  assert.equal(result.canOpenPermissionSettings, canOpenSettings, name);
  if (input[1] === false) assert.ok(result.detail.includes('弹窗：未显示'), name);
  console.log('PASS ' + name);
}
console.log('8/8 pure permission interpretation tests passed. Native dialogs not executed.');
