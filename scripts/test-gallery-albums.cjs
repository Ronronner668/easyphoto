const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const src = name => path.resolve(__dirname, '../entry/src/main/ets', name + '.ets');
function fixture() {
  const env = { permission: true, groups: new Map(), calls: [], albumsClosed: 0, photosClosed: 0, released: 0 };
  class Predicates {
    constructor() { this.values = []; }
    equalTo(key, value) { this.values.push([key, value]); return this; }
    orderByDesc() { return this; }
  }
  const assetResult = (references) => ({
    getCount: () => references.length,
    async getFirstObject() { return { uri: references[0] }; },
    async getObjectByPosition(i) { return { uri: references[i] }; },
    close() { env.photosClosed++; }
  });
  const helper = {
    async getAlbums(type, subtype, options) {
      env.calls.push([type, subtype]);
      if (env.failAlbums) throw Error('query failed');
      let values = env.groups.get(`${type}:${subtype}`) || [];
      const ref = options?.predicates.values.find(([key]) => key === 'uri')?.[1];
      if (ref && !env.ignoreFilter) values = values.filter(a => a.albumUri === ref);
      return {
        getCount: () => values.length,
        async getFirstObject() { return values[0]; },
        async getObjectByPosition(i) { return values[i]; },
        close() { env.albumsClosed++; if (env.failAlbumClose) throw Error('album close failed'); }
      };
    },
    async getAssets() { throw Error('scoped album must never read whole library'); },
    async release() { env.released++; }
  };
  const overrides = new Map([[src('platform/media/PhotoPlaceReader'),{PhotoPlaceReader:class{async read(){return{text:'地点未提供',needsPermission:false};}async request(){return false;}}}],
    ['@kit.MediaLibraryKit', { photoAccessHelper: {
      AlbumType: { USER: 0, SYSTEM: 1024, SOURCE: 2048 },
      AlbumSubtype: { IMAGE: 1031, FAVORITE: 1025, SOURCE_GENERIC: 2049, USER_GENERIC: 1 },
      AlbumKeys: { URI: 'uri' }, PhotoKeys: { PHOTO_TYPE: 'type', DATE_ADDED: 'added' }, PhotoType: { IMAGE: 1 },
      getPhotoAccessHelper: () => helper
    } }],
    ['@kit.ArkData', { dataSharePredicates: { DataSharePredicates: Predicates } }],
    ['@kit.AbilityKit', {}], ['@kit.CoreFileKit', {}], ['@kit.ImageKit', {}],
    [src('platform/permissions/PermissionProbe'), { PermissionProbe: class { canReadLibrary() { return env.permission; } } }],
    [src('platform/files/LegacyDocumentAccess'), { LegacyDocumentAccess: class {} }],
    [src('platform/files/ContentHash'), { contentHash: async () => '' }],
    [src('data/repositories/MoveJournal'), { MoveJournal: class {} }]
  ]);
  function album(reference, type = 0, subtype = 1, references = ['photo:first']) {
    return { albumUri: reference, albumName: reference, albumType: type, albumSubtype: subtype,
      async getAssets(options) {
        env.assetOptions = options;
        assert.deepEqual(options.predicates.values, [['type', 1]]);
        if (env.hold) await new Promise(r => { env.resume = r; });
        if (env.failPhotos) throw Error('membership failed');
        return assetResult(references);
      }
    };
  }
  const load = createLoader(overrides);
  return { env, album, source: new (load(src('platform/media/GalleryAlbumSource')).GalleryAlbumSource)({}),
    reader: new (load(src('platform/media/LocalPhotoReviewSource')).LocalPhotoReviewSource)({}) };
}
let passed = 0;
async function test(name, run) { await run(); passed++; console.log('PASS ' + name); }
function modelFixture() {
  const env = { permission: true, calls: 0, requests: 0, settings: 0, values: [{ reference: 'first' }] };
  const overrides = new Map([[src('platform/media/PhotoPlaceReader'),{PhotoPlaceReader:class{async read(){return{text:'地点未提供',needsPermission:false};}async request(){env.placeRequests=(env.placeRequests||0)+1;if(env.holdPlace)await new Promise(r=>env.resumePlace=r);if(env.failPlace)throw Error('metadata denied');return !env.denyPlace;}}}],
    ['@kit.AbilityKit', {}],
    [src('platform/media/GalleryAlbumSource'), { GalleryAlbumSource: class { async list() {
      env.calls++; if (env.fail) throw Error('native failure');
      if (env.hold) return new Promise(resolve => { env.finish = resolve; });
      return env.values;
    } } }],
    [src('platform/permissions/PermissionProbe'), { PermissionProbe: class {
      canReadLibrary() { return env.permission; }
      async requestRead() { env.requests++; env.permission = env.grant; }
      async requestReadOnSettings() { env.settings++; env.permission = env.grant; }
    } }]
  ]);
  const { GalleryAlbumsViewModel } = createLoader(overrides, { Observed: value => value })(src('viewmodels/GalleryAlbumsViewModel'));
  const model = new GalleryAlbumsViewModel(); model.initialize({}); return { env, model };
}
async function main() {
  await test('explicit library authorization never requests photo metadata',async()=>{const{env,model}=modelFixture();env.permission=false;env.grant=true;await model.refresh(true);assert.equal(env.requests,1);assert.equal(env.placeRequests,undefined);assert.equal(model.albums[0].reference,'first');});
  await test('denied library access does not start the metadata request',async()=>{const{env,model}=modelFixture();env.permission=false;env.grant=false;await model.refresh(true);assert.equal(env.placeRequests,undefined);assert.equal(model.authorized,false);assert.equal(model.loading,false);});
  await test('only system image subtype or no album is the total image source',async()=>{
    const{reader}=fixture();assert.equal(reader.isAllPhotos(),true);
    for(const [type,subtype,expected] of [[1024,1031,true],[1024,1025,false],[0,1,false],[2048,2049,false],[0,1031,false]]){reader.setAlbum({reference:'opaque',type,subtype});assert.equal(reader.isAllPhotos(),expected);}
    reader.setAlbum();assert.equal(reader.isAllPhotos(),true);
  });

  await test('home checks permission without prompting until user asks and supports settings retry', async () => {
    const { env, model } = modelFixture(); env.permission = false;
    await model.refresh(); assert.equal(env.requests, 0); assert.equal(env.calls, 0); assert.equal(model.authorized, false);
    await model.refresh(true); assert.equal(env.requests, 1); assert.equal(env.calls, 0);
    env.grant = true; await model.refresh(true, true); assert.equal(env.settings, 1); assert.equal(model.albums.length, 1);
  });
  await test('failed refresh preserves prior album data with explicit error', async () => {
    const { env, model } = modelFixture(); await model.refresh(); const old = model.albums;
    env.fail = true; await model.refresh(); assert.equal(model.albums, old); assert.ok(model.error); assert.equal(model.loading, false);
  });
  await test('permission revocation removes private album cards', async () => {
    const { env, model } = modelFixture(); await model.refresh(); env.permission = false;
    await model.refresh(); assert.equal(model.albums.length, 0); assert.equal(model.authorized, false);
  });
  await test('duplicate refresh does not query twice and disposed result never updates home', async () => {
    const { env, model } = modelFixture(); env.hold = true; const pending = model.refresh();
    await model.refresh(); assert.equal(env.calls, 1); model.close(); env.finish([{ reference: 'late' }]); await pending;
    assert.equal(model.albums.length, 0); assert.equal(model.loading, false);
  });
  await test('hidden-page result cannot overwrite refreshed home after return', async () => {
    const { env, model } = modelFixture(); env.hold = true; const pending = model.refresh(); const late = env.finish;
    model.suspend(); env.hold = false; env.values = [{ reference: 'new' }]; await model.refresh();
    late([{ reference: 'old' }]); await pending; assert.equal(model.albums[0].reference, 'new');
  });
  await test('system/source/user albums use actual image counts and image covers without a 100 album cap', async () => {
    const { env, album, source } = fixture();
    env.groups.set('1024:1031', [album('all', 1024, 1031, ['p1', 'p2'])]);
    env.groups.set('1024:1025', [album('fav', 1024, 1025, [])]);
    env.groups.set('2048:2049', [album('camera', 2048, 2049)]);
    env.groups.set('0:1', Array.from({ length: 105 }, (_, i) => album('user:' + i)));
    const values = await source.list();
    assert.equal(values.length, 107); assert.equal(values[0].name, '图片');
    assert.equal(values[0].count, 2); assert.equal(values[0].cover, 'p1');
    assert.equal(values.some(item => item.reference === 'fav'), false);
    assert.equal(env.photosClosed, 108); assert.equal(env.albumsClosed, 4); assert.equal(env.released, 1);
  });
  await test('duplicate album identities are shown once', async () => {
    const { env, album, source } = fixture(); env.groups.set('0:1', [album('same'), album('same')]);
    assert.equal((await source.list()).length, 1);
  });
  await test('zero-photo albums are omitted without losing later populated albums', async () => {
    const { env, album, source } = fixture(); env.groups.set('0:1', [album('empty',0,1,[]),album('populated')]);
    const values = await source.list();assert.deepEqual(values.map(item => item.reference), ['populated']);
    assert.equal(env.photosClosed,2);assert.equal(env.albumsClosed,4);
  });
  await test('denied permission performs no album query', async () => {
    const { env, source } = fixture(); env.permission = false; await assert.rejects(source.list());
    assert.equal(env.calls.length, 0); assert.equal(env.released, 0);
  });
  await test('membership failure does not become an empty successful gallery and releases resources', async () => {
    const { env, album, source } = fixture(); env.groups.set('0:1', [album('bad')]); env.failPhotos = true;
    await assert.rejects(source.list()); assert.equal(env.albumsClosed, 4); assert.equal(env.released, 1);
  });
  await test('selected album snapshot continues beyond 100 images and never reads other albums', async () => {
    const { env, album, reader } = fixture();
    env.groups.set('0:1', [album('chosen', 0, 1, Array.from({ length: 205 }, (_, i) => 'p' + i)), album('other')]);
    reader.setAlbum({ reference: 'chosen', type: 0, subtype: 1 });
    assert.equal((await reader.library()).length, 100); assert.equal(reader.hasMore(), true);
    assert.equal((await reader.library(true))[0], 'p100'); assert.deepEqual(await reader.library(true), ['p200', 'p201', 'p202', 'p203', 'p204']);
    assert.equal(reader.hasMore(), false); assert.equal(env.calls.length, 1);
    reader.close(); await Promise.resolve(); assert.equal(env.photosClosed, 1); assert.equal(env.released, 1);
  });
  await test('deleted selected album fails without falling back to all images', async () => {
    const { env, reader } = fixture(); reader.setAlbum({ reference: 'gone', type: 0, subtype: 1 });
    await assert.rejects(reader.library(), /所选相册/); assert.equal(env.albumsClosed, 1); assert.equal(env.released, 1);
  });
  await test('native query returning a different album is rejected before reading its photos', async () => {
    const { env, album, reader } = fixture(); env.groups.set('0:1', [album('other')]); env.ignoreFilter = true;
    reader.setAlbum({ reference: 'chosen', type: 0, subtype: 1 });
    await assert.rejects(reader.library(), /相册引用已变化/); assert.equal(env.assetOptions, undefined); assert.equal(env.released, 1);
  });
  await test('asset snapshot is released if closing the selected album query fails', async () => {
    const { env, album, reader } = fixture(); env.groups.set('0:1', [album('chosen')]); env.failAlbumClose = true;
    reader.setAlbum({ reference: 'chosen', type: 0, subtype: 1 });
    await assert.rejects(reader.library(), /album close failed/); assert.equal(env.photosClosed, 1); assert.equal(env.released, 1);
  });
  await test('switching album closes its snapshot and starts the new album', async () => {
    const { env, album, reader } = fixture(); env.groups.set('0:1', [album('a', 0, 1, ['a1']), album('b', 0, 1, ['b1'])]);
    reader.setAlbum({ reference: 'a', type: 0, subtype: 1 }); assert.deepEqual(await reader.library(), ['a1']);
    reader.setAlbum({ reference: 'b', type: 0, subtype: 1 }); assert.deepEqual(await reader.library(), ['b1']);
    assert.equal(env.photosClosed, 1); reader.close();
  });
  await test('late album asset result is rejected after reader disposal', async () => {
    const { env, album, reader } = fixture(); env.groups.set('0:1', [album('a')]); env.hold = true;
    reader.setAlbum({ reference: 'a', type: 0, subtype: 1 }); const pending = reader.library();
    while (!env.resume) await Promise.resolve(); reader.close(); env.resume();
    await assert.rejects(pending, /批次已关闭/); assert.equal(env.photosClosed, 1); assert.equal(env.released, 1);
  });
  await test('empty album is a successful empty scope', async () => {
    const { env, album, reader } = fixture(); env.groups.set('0:1', [album('empty', 0, 1, [])]);
    reader.setAlbum({ reference: 'empty', type: 0, subtype: 1 }); assert.deepEqual(await reader.library(), []);
    assert.equal(reader.hasMore(), false); reader.close();
  });
  console.log(`${passed}/${passed} album boundary checks passed with explicit native substitutes.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
