const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const saved=new Map();let flushes=0;
const store={async get(key,fallback){return saved.has(key)?saved.get(key):fallback;},async put(key,value){saved.set(key,value);},async flush(){flushes++;}};
const load=createLoader(new Map([['@kit.AbilityKit', { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1, COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1 } } }],['@kit.ArkData',{preferences:{async getPreferences(){return store;}}}]]));
const {WorkbenchPreferences}=load(path.resolve(__dirname,'../entry/src/main/ets/data/repositories/WorkbenchPreferences.ets'));
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
async function main(){
  await test('old installation defaults to gallery album and bottom three without altering stored bindings',async()=>{const settings=new WorkbenchPreferences({});assert.equal(await settings.loadLayout(),0);assert.equal(saved.size,0);});
  await test('legacy directory and dual modes are ignored without rewriting old preference keys',async()=>{
    saved.set('targetMode','both');saved.set('sourceMode',2);const settings=new WorkbenchPreferences({});

    await settings.save(1);assert.equal(saved.get('targetMode'),'both');assert.equal(saved.get('sourceMode'),2);
    assert.equal(await settings.loadLayout(),1);
    assert.equal(settings.load,undefined);assert.equal(settings.loadSource,undefined);assert.equal(saved.get('targetMode'),'both');
  });
  await test('unsupported stored options fall back to safe defaults',async()=>{saved.set('targetMode','unknown');saved.set('layout',3);saved.set('sourceMode',9);const settings=new WorkbenchPreferences({});assert.equal(await settings.loadLayout(),0);});
  await test('photo information defaults and explicit saved visibility survive reload',async()=>{const settings=new WorkbenchPreferences({});assert.equal((await settings.loadInfo()).dateFormat,'YYYY/MM/DD');await settings.save(0,{dateFormat:'YYYY-MM-DD',name:false,date:true,place:false,dimensions:true,bytes:true});const value=await settings.loadInfo();assert.equal(value.dateFormat,'YYYY-MM-DD');assert.equal(value.name,false);assert.equal(value.dimensions,true);assert.equal(value.bytes,true);});
  await test('album original-retention policy persists and unrelated saves do not silently reset it',async()=>{const settings=new WorkbenchPreferences({});assert.equal(await settings.loadKeepOriginal(),false);await settings.save(1,undefined,true);assert.equal(await new WorkbenchPreferences({}).loadKeepOriginal(),true);await settings.save();assert.equal(await settings.loadKeepOriginal(),true);await settings.save(1,undefined,false);assert.equal(await settings.loadKeepOriginal(),false);});
  await test('color mode defaults to system and persists day and night across reads', async () => {
    const prefs = new WorkbenchPreferences({});
    assert.equal(await prefs.loadColorMode(), -1);
    for (const mode of [0, 1, -1]) {
      await prefs.save(0, undefined, undefined, mode);
      await prefs.save();
      assert.equal(await new WorkbenchPreferences({}).loadColorMode(), mode);
    }
  });
  await test('retired optional preference is ignored and preserved even when its old value is invalid', async () => {
    saved.set('antiPeepEnabled', 'invalid');
    const prefs = new WorkbenchPreferences({});
    await prefs.save(0, undefined, true);
    assert.equal(await prefs.loadKeepOriginal(), true);
    assert.equal(saved.get('antiPeepEnabled'), 'invalid');
  });
  console.log(`${passed}/${passed} workbench preference compatibility checks passed.`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
