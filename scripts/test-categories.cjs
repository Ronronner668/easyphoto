const assert = require('node:assert/strict');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { createLoader } = require('./ets-test-runtime.cjs');
const src = relative => path.resolve(__dirname, '../entry/src/main/ets', relative + '.ets');
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS ' + name); }
function fixture() {
  const db = new DatabaseSync(':memory:');
  const env = { failOnName:'', closed:0, folder:undefined, albums:[], holdFolder:false };
  const store = {
    async executeSql(sql, args = []) {
      if (env.failOnName && sql.startsWith('INSERT INTO categories') && args[1] === env.failOnName) throw Error('storage failed');
      db.prepare(sql).run(...args);
    },
    async querySql(sql, args = []) {
      const rows = db.prepare(sql).all(...args); let index = -1;
      return { rowCount: rows.length, goToFirstRow: () => { index = 0; return rows.length > 0; },
        goToNextRow: () => ++index < rows.length,
        getString: column => String(Object.values(rows[index])[column]), getLong: column => Number(Object.values(rows[index])[column]),
        close: () => { env.closed++; } };
    },
    beginTransaction() { db.exec('BEGIN'); }, commit() { db.exec('COMMIT'); }, rollBack() { db.exec('ROLLBACK'); },
  };
  class Provider {
    async albums() { if(env.holdAlbums) await new Promise(resolve=>{env.finishAlbums=resolve;});return structuredClone(env.albums); }
  }
  const load = createLoader(new Map([['@kit.ArkData', {relationalStore:{SecurityLevel:{S1:1},getRdbStore:async()=>store}}],
    [src('platform/media/LocalTargetProvider'),{LocalTargetProvider:Provider}]]));
  const model = load(src('domain/models/Category'));
  const rules = load(src('domain/usecases/CategoryRules'));
  const Repository = load(src('data/repositories/CategoryRepository')).CategoryRepository;
  const Service = load(src('services/operations/CategoryService')).CategoryService;
  return {db,env,model,rules,Repository,Service,repository:new Repository({}),service:new Service({})};
}
async function main() {
  await test('seven presets seed once and an intentionally empty library stays empty across instances', async () => {
    const {db,repository,Repository} = fixture(); try {
      const snapshot = await repository.load(); assert.deepEqual(snapshot.categories.map(x=>x.name), ['旅游','美食','人像','风景','建筑','宠物','其他']);
      snapshot.categories = []; await repository.save(snapshot); assert.equal((await new Repository({}).load()).categories.length, 0);
    } finally { db.close(); }
  });
  await test('create rename reorder remove persist without changing caller snapshot', async () => {
    const {db,service,Repository} = fixture(); try {
      const before = await service.load(); let next = await service.create(before, '  测试  ');
      assert.equal(before.categories.length, 7); assert.equal(next.categories[7].name, '测试');
      const id = next.categories[7].id; next = await service.rename(next,id,'旅行'); next = await service.reorder(next,id,-1);
      assert.equal(next.categories[6].name,'旅行'); next = await service.remove(next,id);
      assert.equal((await new Repository({}).load()).categories.length,7);
    } finally { db.close(); }
  });
  await test('duplicate invalid and excessive category names never enter the database', async () => {
    const {db,service} = fixture(); try {
      let value = await service.load();
      for (const name of ['旅游','  ','x'.repeat(17),'name\nline']) await assert.rejects(service.create(value,name));
      value = await service.create(value,'Travel'); await assert.rejects(service.create(value,'travel'));
      for(let index=value.categories.length;index<30;index++) value=await service.create(value,'分类'+index);
      await assert.rejects(service.create(value,'超过上限')); assert.equal((await service.load()).categories.length,30);
    } finally { db.close(); }
  });
  await test('stale revision cannot overwrite a newer category edit', async () => {
    const {db,service} = fixture(); try {
      const old = await service.load(); const next = await service.create(old,'新增');
      await assert.rejects(service.remove(old,old.categories[0].id), /过期/);
      assert.equal((await service.load()).revision,next.revision); assert.equal((await service.load()).categories.length,8);
    } finally { db.close(); }
  });
  await test('SQL failure in replacement rolls back delete inserts and revision together', async () => {
    const {db,service,env} = fixture(); try {
      const old = await service.load(); env.failOnName = '失败分类';
      await assert.rejects(service.create(old,'失败分类')); env.failOnName='';
      assert.deepEqual(await service.load(), old);
    } finally { db.close(); }
  });
  await test('bindings preserve opaque long references and both target modes independently', async () => {
    const {db,service,env,model,Repository} = fixture(); try {
      let value=await service.load(); const id=value.categories[0].id;
      const ref="opaque://相册?'"+'x'.repeat(3000); env.albums=[new model.TargetRef(model.TargetKind.Album,ref,"A'); --")];
      value=await service.bindAlbum(value,id,env.albums[0]);
      env.folder=new model.TargetRef(model.TargetKind.Directory,'opaque:directory?token=保留','旅游目录');
      value.categories[0].directory=env.folder;value=await new Repository({}).save(value);
      const restored=await new Repository({}).load(); assert.equal(restored.categories[0].album.reference,ref);
      assert.equal(restored.categories[0].directory.reference,env.folder.reference);
      value=await service.unbind(value,id,model.TargetKind.Album); assert.equal(value.categories[0].album,undefined);
      assert.equal(value.categories[0].directory.reference,env.folder.reference);
    } finally { db.close(); }
  });
  await test('new directory bindings cannot be committed through category service', async()=>{
    const {db,service,model}=fixture();try{const value=await service.load();value.categories[0].directory=new model.TargetRef(model.TargetKind.Directory,'legacy:folder','old');
      await assert.rejects(service.commit(value),/仅保留/);assert.equal((await service.load()).categories[0].directory,undefined);
    }finally{db.close();}
  });
  await test('vanished album is rejected without changing saved target', async () => {
    const {db,service,model} = fixture(); try {
      const value=await service.load(); await assert.rejects(service.bindAlbum(value,value.categories[0].id,new model.TargetRef(model.TargetKind.Album,'missing','不存在')));
      assert.deepEqual(await service.load(),value);
    } finally { db.close(); }
  });
  await test('boundary reorder and missing category are rejected', async () => {
    const {db,service} = fixture(); try {
      const value=await service.load(); await assert.rejects(service.reorder(value,value.categories[0].id,-1));
      await assert.rejects(service.reorder(value,value.categories[0].id,2)); await assert.rejects(service.remove(value,'missing'));
      assert.deepEqual(await service.load(),value);
    } finally { db.close(); }
  });
  await test('future schema and missing metadata preserve existing records rather than reseeding', async () => {
    const {db,service,Repository} = fixture(); try {
      await service.load(); db.exec('UPDATE organizer_meta SET schema_version=2');
      await assert.rejects(new Repository({}).load(),/版本/); assert.equal(db.prepare('SELECT count(*) AS n FROM categories').get().n,7);
      db.exec('DELETE FROM organizer_meta'); await assert.rejects(new Repository({}).load(),/缺失/);
      assert.equal(db.prepare('SELECT count(*) AS n FROM categories').get().n,7);
    } finally { db.close(); }
  });
  await test('another page cannot write while album lookup owns the process lease', async () => {
    const {db,service,env,Service,model} = fixture(); try {
      const value=await service.load(); env.holdAlbums=true; env.albums=[new model.TargetRef(model.TargetKind.Album,'album:target','A')];const pending=service.bindAlbum(value,value.categories[0].id,env.albums[0]);
      while(!env.finishAlbums) await Promise.resolve(); await assert.rejects(new Service({}).create(value,'另一页'),/另一页/);
      env.finishAlbums(); await pending; assert.equal((await service.load()).categories.length,7);
    } finally { db.close(); }
  });
  await test('startup readers wait for active lease and see the committed album binding', async () => {
    const {db,service,env,Service,model}=fixture();try {
      const original=await service.load();env.holdAlbums=true;
      env.albums=[new model.TargetRef(model.TargetKind.Album,'album:target','A')];const pending=service.bindAlbum(original,original.categories[0].id,env.albums[0]);
      while(!env.finishAlbums)await Promise.resolve();
      let settled=false;const reader=new Service({}).load().then(value=>{settled=true;return value;});
      await Promise.resolve();assert.equal(settled,false);env.finishAlbums();await pending;
      assert.deepEqual(await reader,await service.load());
      const [a,b]=await Promise.all([new Service({}).load(),new Service({}).load()]);assert.deepEqual(a,b);
    }finally{db.close();}
  });
  await test('mismatched target kinds cannot be saved in a category binding', async () => {
    const {db,model,rules} = fixture(); try {
      const category=new model.Category('test','旅游');
      category.album=new model.TargetRef(model.TargetKind.Directory,'opaque:D','目录');
      assert.throws(()=>rules.validateCategories([category]),/目标绑定/);
      category.album=undefined; category.directory=new model.TargetRef(model.TargetKind.Album,'opaque:A','相册');
      assert.throws(()=>rules.validateCategories([category]),/目标绑定/);
    } finally { db.close(); }
  });
  await test('draft binding and edits stay private until explicit save commits them together', async () => {
    const {db,service,env,model,Repository}=fixture(); try {
      const original=await service.load(); service.beginEditing();
      let draft=await service.rename(original,original.categories[0].id,'草稿');
      env.albums=[new model.TargetRef(model.TargetKind.Album,'opaque:save-test','保存目标')];
      draft=await service.bindAlbum(draft,draft.categories[0].id,env.albums[0]);
      assert.deepEqual(await new Repository({}).load(),original);
      const saved=await service.commit(draft); assert.equal(saved.revision,original.revision+1);
      assert.equal((await new Repository({}).load()).categories[0].album.name,'保存目标');
    } finally { db.close(); }
  });
  await test('stale draft save cannot replace another page committed target', async () => {
    const {db,service,Service}=fixture(); try {
      const original=await service.load(); service.beginEditing();
      const draft=await service.rename(original,original.categories[0].id,'旧草稿');
      await new Service({}).rename(original,original.categories[0].id,'较新');
      await assert.rejects(service.commit(draft),/过期/);
      assert.equal((await service.load()).categories[0].name,'较新');
    } finally { db.close(); }
  });
  console.log(`${passed}/${passed} category checks passed with real host SQLite. Native pickers and targets require device evidence.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
