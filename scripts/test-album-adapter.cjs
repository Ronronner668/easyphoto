const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const src = relative => path.join(root, relative + '.ets');
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS ' + name); }
function setup() {
  const env = { closed: 0, released: 0, target: '', membersA: ['opaque:sample'], membersB: [], countA: 1,
    countB: 0, filteredQueries: 0, failRead: false, operationUri: '' };
  class Predicates { equalTo(key, value) { this.key = key; this.value = value; return this; } }
  const member = uri => ({ uri, get: key => ({ size: 100, date_taken: 125, owner_album_id: 'owner', subtype: 0 })[key] });
  const asset = member('opaque:sample');
  const fetch = items => ({ getCount: () => items.length, getObjectByPosition: async index => {
    if (env.failRead) throw Error('query interrupted'); return items[index];
  }, getFirstObject: async () => items[0], close: () => env.closed++ });
  const album = key => ({ albumUri: 'opaque:' + key, albumName: key, get count() { return env['count' + key]; },
    getAssets: async options => {
      if (options.predicates.key) { env.filteredQueries++; return fetch([]); }
      return fetch(env['members' + key].map(member));
    } });
  const helper = { getAlbums: async () => fetch([album('A'), album('B')]), // Deliberately ignore album predicates.
    getAssets: async options => fetch([options.predicates.value === asset.uri ? asset : member(options.predicates.value)]),
    applyChanges: async request => { env.target = request.target.albumUri; env.operationUri = request.operationUri; },
    release: async () => { env.released++; } };
  const kit = { getPhotoAccessHelper: () => helper, AlbumType: { USER: 0 }, AlbumSubtype: { USER_GENERIC: 0 },
    PhotoKeys: { URI: 'uri', SIZE: 'size', DATE_TAKEN: 'date_taken', OWNER_ALBUM_ID: 'owner_album_id', PHOTO_SUBTYPE: 'subtype' },
    PhotoSubtype: { DEFAULT: 0 }, MediaAlbumChangeRequest: class {
      constructor(target) { this.target = target; }
      addAssets(values) { assert.equal(values[0], asset); this.operationUri = values[0].uri; }
      removeAssets(values) { this.operationUri = values[0].uri; }
    } };
  const overrides = new Map([['@kit.MediaLibraryKit', { photoAccessHelper: kit }],
    ['@kit.ArkData', { dataSharePredicates: { DataSharePredicates: Predicates } }],
    ['@kit.CoreFileKit', {}], ['@kit.ImageKit', {}],
    [src('platform/files/ContentHash'), { contentHash: async uri => (uri.includes('modified') ? 'b' : 'a').repeat(64) }]]);
  const load = createLoader(overrides);
  const { AlbumExperiment, LabAlbum, AlbumAction } = load(src('domain/models/Experiment'));
  const session = Object.assign(new AlbumExperiment(), { createdByLab: true, assetUri: asset.uri,
    albumA: new LabAlbum('opaque:A', 'A'), albumB: new LabAlbum('opaque:B', 'B') });
  return { env, session, AlbumAction, adapter: new (load(src('platform/media/AlbumExperimentAdapter')).AlbumExperimentAdapter)({}) };
}
async function main() {
  await test('unfiltered enumeration finds A even when URI-filtered album queries would return empty', async () => {
    const { env, session, adapter } = setup(); const value = await adapter.snapshot(session);
    assert.equal(value.inA, true); assert.equal(value.inB, false); assert.equal(value.membershipVersion, 3);
    assert.equal(value.originalInA, true); assert.equal(value.copyA, undefined);
    assert.equal(env.filteredQueries, 0); assert.equal(env.released, 1); assert.equal(env.closed, 5);
  });
  await test('B mutation resolves exact opaque B reference independently of returned album order', async () => {
    const { env, session, adapter, AlbumAction } = setup(); await adapter.mutate(session, AlbumAction.AddB);
    assert.equal(env.target, 'opaque:B'); assert.equal(env.released, 1);
  });
  await test('missing selected album never falls back to first album', async () => {
    const { env, session, adapter, AlbumAction } = setup(); session.albumB.uri = 'opaque:missing';
    await assert.rejects(adapter.mutate(session, AlbumAction.AddB)); assert.equal(env.target, '');
  });
  await test('partial visibility cannot be reported as absence', async () => {
    const { session, env, adapter } = setup(); env.countB = 1;
    await assert.rejects(adapter.snapshot(session), /数量/); assert.equal(env.released, 1);
  });
  await test('bounded enumeration refuses negative conclusion about oversized albums', async () => {
    const { session, env, adapter } = setup(); env.membersB = Array.from({length: 1001}, (_, i) => 'opaque:' + i); env.countB = 1001;
    await assert.rejects(adapter.snapshot(session), /20/); assert.equal(env.released, 1);
  });
  await test('enumeration failure closes results and releases helper', async () => {
    const { session, env, adapter } = setup(); env.failRead = true;
    await assert.rejects(adapter.snapshot(session)); assert.equal(env.released, 1); assert.equal(env.closed, 2);
  });
  await test('copy with a new URI is reported separately and never replaces the original identity', async () => {
    const { env, session, adapter } = setup(); env.membersA = ['opaque:copy-A'];
    const value = await adapter.snapshot(session); assert.equal(value.inA, true); assert.equal(value.originalInA, false);
    assert.equal(value.copyA.uri, 'opaque:copy-A'); assert.equal(value.uri, 'opaque:sample');
    assert.equal(session.assetUri, 'opaque:sample'); assert.equal(value.copyA.sha256, value.sha256);
  });
  await test('same byte length with changed content is not a verified copy', async () => {
    const { env, session, adapter } = setup(); env.membersA = ['opaque:modified'];
    const value = await adapter.snapshot(session); assert.equal(value.inA, false); assert.equal(value.copyA, undefined);
  });
  await test('multiple identical copies are ambiguous rather than selecting the first', async () => {
    const { env, session, adapter } = setup(); env.membersA = ['opaque:copy-1', 'opaque:copy-2']; env.countA = 2;
    await assert.rejects(adapter.snapshot(session), /多个/);
  });
  await test('remove B targets the recorded B copy rather than the original URI', async () => {
    const { env, session, adapter, AlbumAction } = setup(); session.verifiedCopyB = {uri:'opaque:copy-B'};
    await adapter.mutate(session, AlbumAction.RemoveB); assert.equal(env.operationUri, 'opaque:copy-B'); assert.equal(env.target, 'opaque:B');
  });
  await test('missing B-copy proof and original masquerading as B copy are rejected before native changes', async () => {
    const { env, session, adapter, AlbumAction } = setup();
    await assert.rejects(adapter.mutate(session, AlbumAction.RemoveB));
    session.verifiedCopyB = {uri:session.assetUri}; await assert.rejects(adapter.mutate(session, AlbumAction.RemoveB));
    assert.equal(env.target, '');
  });
  console.log(`${passed}/${passed} album adapter tests passed. Native queries are explicit test doubles.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
