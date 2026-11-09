const assert = require('node:assert/strict');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { createLoader } = require('./ets-test-runtime.cjs');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const src = relative => path.join(root, relative + '.ets');
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS ' + name); }
function fixture() {
  const db = new DatabaseSync(':memory:');
  const env = { closed: 0, failWrite: false, statements: [], holdWrite: false };
  const store = {
    async executeSql(sql, args = []) {
      env.statements.push([sql, args]);
      if (sql.startsWith('INSERT') && env.holdWrite) await new Promise(resolve => { env.resume = resolve; });
      if (env.failWrite && sql.startsWith('INSERT')) throw Error('disk full');
      db.prepare(sql).run(...args);
    },
    async querySql(sql) {
      const rows = db.prepare(sql).all(); let index = -1;
      return { rowCount: rows.length, goToNextRow: () => ++index < rows.length,
        getString: column => rows[index][['reference', 'name'][column]], getLong: () => rows[index].marked_at,
        close: () => { env.closed++; } };
    },
  };
  const load = createLoader(new Map([[src('platform/media/GalleryReferenceInspector'),{GalleryReferenceInspector:class{async inspect(refs){return refs.map(reference=>({reference,state:'ready'}));}}}],['@kit.ArkData', { relationalStore: {
    SecurityLevel: { S1: 1 }, getRdbStore: async () => store,
  } }]]));
  const Repository = load(src('data/repositories/DiscardQueueRepository')).DiscardQueueRepository;
  const Service = load(src('services/operations/DiscardQueueService')).DiscardQueueService;
  return { env, db, Repository, Service, repository: new Repository({}) };
}
async function main() {
  await test('real SQLite statements preserve opaque references and names through a new repository instance', async () => {
    const { db, repository, Repository, env } = fixture();
    try {
      const ref = "opaque://photo?'引号&token=" + 'x'.repeat(3000);
      await repository.mark(ref, "照片'); DROP TABLE discard_marks;--.jpg");
      const restored = await new Repository({}).load(); assert.equal(restored[0].reference, ref);
      assert.equal(restored[0].name, "照片'); DROP TABLE discard_marks;--.jpg"); assert.equal(restored.length, 1);
      assert.equal(env.statements.find(([sql]) => sql.startsWith('INSERT'))[0].includes(ref), false);
      assert.equal(env.closed, 2);
    } finally { db.close(); }
  });
  await test('same reference marks once and undo only deletes that marker', async () => {
    const { db, repository } = fixture();
    try {
      await repository.mark('opaque:A', 'A'); await repository.mark('opaque:A', 'new name');
      await repository.mark('opaque:B', 'B'); await repository.unmark('opaque:A');
      assert.deepEqual((await repository.load()).map(item => item.reference), ['opaque:B']);
    } finally { db.close(); }
  });
  await test('more than one hundred long references fit independent database rows', async () => {
    const { db, repository } = fixture();
    try {
      for (let index = 0; index < 100; index++) await repository.mark('opaque:' + index + 'x'.repeat(3000), 'photo');
      await repository.mark('opaque:overflow', 'photo'); assert.equal((await repository.load()).length, 101);
    } finally { db.close(); }
  });
  await test('failed database write leaves existing markers intact', async () => {
    const { db, repository, env } = fixture();
    try {
      await repository.mark('opaque:A', 'A'); env.failWrite = true;
      await assert.rejects(repository.mark('opaque:B', 'B')); assert.equal((await repository.load()).length, 1);
    } finally { db.close(); }
  });
  await test('empty and oversized identities are rejected before SQL insertion', async () => {
    const { db, repository } = fixture();
    try {
      for (const [ref, name] of [['', 'A'], ['x'.repeat(4097), 'A'], ['opaque:A', ''], ['opaque:A', 'x'.repeat(257)]])
        await assert.rejects(repository.mark(ref, name));
      assert.equal((await repository.load()).length, 0);
    } finally { db.close(); }
  });
  await test('another page cannot race queue writes and a failed write releases the process lease', async () => {
    const { db, env, Service } = fixture();
    try {
      env.holdWrite = true; env.failWrite = true;
      const first = new Service({}); const second = new Service({});
      const pending = first.mark('opaque:A', 'A');
      while (!env.resume) await Promise.resolve();
      await assert.rejects(second.mark('opaque:B', 'B'), /另一页/);
      env.resume(); await assert.rejects(pending); env.holdWrite = false; env.failWrite = false;
      assert.equal((await second.mark('opaque:B', 'B')).length, 1);
    } finally { db.close(); }
  });
  console.log(`${passed}/${passed} discard queue tests passed using host SQLite. HarmonyOS storage still needs device validation.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
