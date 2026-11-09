const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const src = name => path.resolve(__dirname, '../entry/src/main/ets', name + '.ets');
function fixture() {
  const env = { calls: 0, keep: false, mode: 'album', layout: 0 };
  const overrides = new Map([['@kit.AbilityKit', { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1, COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1 } } }], [src('data/repositories/WorkbenchPreferences'), { WorkbenchPreferences: class {
    async load() { if (env.failLoad) throw Error('read'); if (env.holdLoad) await new Promise(r => env.resumeLoad = r); return env.mode; }
    async loadLayout() { if(env.failLoad)throw Error('read');if(env.holdLoad)await new Promise(r=>env.resumeLoad=r);return env.layout; }
    async loadInfo() { return { name: true, date: true, place: true, dimensions: true, bytes: false, dateFormat: 'YYYY/MM/DD' }; }
    async loadKeepOriginal() { return env.keep; }
    async loadColorMode() { return -1; }
    async save(...args) {
      env.calls++; env.args = args;
      if (env.holdSave) await new Promise(r => env.resumeSave = r);
      if (env.failSave) throw Error('flush');
    }
  } }]]);
  const { SettingsViewModel } = createLoader(overrides, { Observed: v => v })(src('viewmodels/SettingsViewModel'));
  const model = new SettingsViewModel(); model.initialize({ getApplicationContext: () => ({ setColorMode: mode => { env.applied = mode; } }) }); return { env, model };
}
let passed = 0; async function test(name, action) { await action(); passed++; console.log('PASS ' + name); }
async function main() {
  await test('loaded settings have no unsaved changes and do not write', async () => {
    const { env, model } = fixture(); await model.load(); assert.equal(model.dirty(), false); assert.equal(env.calls, 0);
  });
  await test('all editable fields trigger unsaved protection and reverting values removes it', async () => {
    const { model } = fixture(); await model.load();
    for (const [key, value] of [['draftLayout',1],['draftKeepOriginal',true]]) {
      const old = model[key]; model[key] = value; assert.equal(model.dirty(),true); model[key] = old; assert.equal(model.dirty(),false);
    }
    for (const key of ['name','date','place','dimensions','bytes','dateFormat']) {
      const old = model.draftInfo[key]; model.draftInfo[key] = typeof old === 'boolean' ? !old : 'YYYY-MM-DD';
      assert.equal(model.dirty(),true); model.draftInfo[key]=old;assert.equal(model.dirty(),false);
    }
  });
  await test('discard restores saved values without writing preferences', async () => {
    const { env, model } = fixture(); await model.load(); model.draftKeepOriginal=true;model.draftInfo.name=false;
    model.discard(); assert.equal(model.dirty(),false);assert.equal(model.draftInfo.name,true);assert.equal(env.calls,0);
  });
  await test('save commits the full draft while preserving the removed legacy source key', async () => {
    const { env, model } = fixture(); await model.load();model.draftKeepOriginal=true;
    assert.equal(await model.save(),true); assert.equal(model.dirty(),false);assert.equal(env.args[0],0);assert.equal(env.args[2],true);
  });
  await test('appearance takes effect only after a successful save', async () => {
    const { env, model } = fixture(); await model.load();
    model.draftColorMode = 0;
    assert.equal(model.dirty(), true); assert.equal(env.applied, undefined);
    model.discard(); assert.equal(model.draftColorMode, -1);
    model.draftColorMode = 1; env.failSave = true;
    assert.equal(await model.save(), false); assert.equal(env.applied, undefined);
    env.failSave = false;
    assert.equal(await model.save(), true);
    assert.equal(env.applied, 1); assert.equal(env.args[3], 1);
  });
  await test('failed save leaves dirty protection and draft intact for retry', async () => {
    const { env, model } = fixture(); await model.load();model.draftLayout=1;env.failSave=true;
    assert.equal(await model.save(),false);assert.equal(model.dirty(),true);assert.equal(model.draftLayout,1);assert.ok(model.error);
    env.failSave=false;assert.equal(await model.save(),true);assert.equal(model.dirty(),false);
  });
  await test('repeated save and discard while saving cannot race the accepted draft', async () => {
    const { env, model } = fixture(); await model.load();model.draftKeepOriginal=true;env.holdSave=true;const pending=model.save();
    assert.equal(await model.save(),false);model.discard();assert.equal(model.draftKeepOriginal,true);assert.equal(env.calls,1);
    env.resumeSave();assert.equal(await pending,true);assert.equal(model.saving,false);
  });
  await test('read failure disables editing and save rather than creating defaults', async () => {
    const { env, model } = fixture();env.failLoad=true;await model.load();assert.equal(model.ready,false);assert.ok(model.error);
    assert.equal(await model.save(),false);assert.equal(env.calls,0);
  });
  await test('disposed load and save cannot publish late settings or report navigation success', async () => {
    const first=fixture();first.env.holdLoad=true;const reading=first.model.load();first.model.dispose();first.env.resumeLoad();await reading;assert.equal(first.model.ready,false);
    const { env, model }=fixture();await model.load();model.draftLayout=1;env.holdSave=true;const writing=model.save();model.dispose();env.resumeSave();assert.equal(await writing,false);
  });
  console.log(`${passed}/${passed} settings draft checks passed with explicit preference substitutes.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
