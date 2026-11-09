const fs = require('node:fs');
const path = require('node:path');
const studio = process.env.DEVECO_STUDIO_HOME || 'E:\\DevEcoStudio\\DevEco Studio';
const json5 = require(path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/json5'));

function readConfig(filename) {
  return json5.parse(fs.readFileSync(filename, 'utf8').replace(/^\uFEFF/, ''));
}
function json(value, pretty = false) {
  return JSON.stringify(value, (_, item) => {
    if (typeof item === 'number' && !Number.isFinite(item)) throw Error('Non-finite configuration number is unsupported');
    return item;
  }, pretty ? 2 : undefined);
}
function atomicWrite(filename, value) {
  const temporary = filename + '.config-' + process.pid + '.tmp';
  const serialized = json(value, true) + '\n';
  const descriptor = fs.openSync(temporary, 'wx');
  let closed = false;
  try {
    fs.writeFileSync(descriptor, serialized, 'utf8');
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    closed = true;
    fs.renameSync(temporary, filename);
  } finally {
    try { if (!closed) fs.closeSync(descriptor); }
    finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
  }
}
function run(args) {
  const [operation, filename, mode] = args;
  if (!filename) throw Error('Missing configuration path');
  const config = readConfig(filename);
  if (operation === 'read') {
    // Windows PowerShell 5.1 may decode native stdout using a legacy codepage.
    // ASCII JSON escapes preserve every Unicode value without changing global encoding.
    process.stdout.write(json(config).replace(/[^\x20-\x7E]/g, c => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')));
    return;
  }
  if (operation !== 'write-probes' || !['enable', 'disable'].includes(mode)) throw Error('Unknown configuration operation');
  if (!config.module || !Array.isArray(config.module.requestPermissions)) throw Error('Missing module.requestPermissions array');
  const permission = 'ohos.permission.WRITE_IMAGEVIDEO';
  const existing = config.module.requestPermissions.filter(item => item.name === permission);
  if ((mode === 'enable' && existing.length !== 1) || (mode === 'disable' && existing.length)) {
    const retained = config.module.requestPermissions.filter(item => item.name !== permission);
    if (mode === 'enable') retained.push({ name: permission, reason: '$string:gallery_write_reason',
      usedScene: { abilities: ['EntryAbility'], when: 'inuse' } });
    config.module.requestPermissions = retained;
    atomicWrite(filename, config);
  }
  process.stdout.write(mode === 'enable' ?
    'WRITE_IMAGEVIDEO declared. Update the debug Profile ACL in DevEco, rebuild, then request permission on the phone.\n' :
    'WRITE_IMAGEVIDEO disabled. Reading and generated document probes remain available.\n');
}
if (require.main === module) {
  try { run(process.argv.slice(2)); }
  catch (error) { console.error('Configuration operation failed: ' + error.message); process.exitCode = 1; }
}
module.exports = { readConfig, atomicWrite, run };
