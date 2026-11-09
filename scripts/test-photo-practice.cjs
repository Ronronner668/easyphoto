const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');

const { PhotoPracticeSession } = createLoader()(
  path.resolve(__dirname, '../entry/src/main/ets/domain/usecases/PhotoPracticeSession.ets')
);

async function main() {
  const session = new PhotoPracticeSession();
  const fresh = new PhotoPracticeSession();
  const refs = await session.pick();
  assert.equal(refs.length, 5);
  assert.equal(new Set(refs).size, 5);
  assert.deepEqual(await Promise.all(refs.map(async ref => (await session.resolve(ref)).name)),
    ['建筑照片一', '建筑照片二', '人像照片', '动物照片', '自然照片']);
  const ref = refs[1];
  await assert.rejects(session.resolve('real-gallery-reference'));
  await assert.rejects(session.mark('real-gallery-reference', 'unknown'));
  assert.equal((await session.mark(ref, '建筑照片二')).length, 1);
  assert.equal((await session.mark(ref, '建筑照片二')).length, 1);
  assert.deepEqual(await fresh.load(), []);
  await session.setFavorite(ref, true);
  assert.equal((await session.resolve(ref)).favorite, true);
  assert.equal((await fresh.resolve(ref)).favorite, false);
  assert.deepEqual(await session.unmark(ref), []);
  await session.setFavorite(ref, false);
  assert.equal((await session.resolve(ref)).favorite, false);
  assert.deepEqual(await session.pick(), refs);
  console.log('PASS bundled sources, mark/favorite isolation and unknown references');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
