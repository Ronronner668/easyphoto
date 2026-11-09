const assert = require('node:assert/strict');
const path = require('node:path');
const crypto = require('node:crypto');
const { createLoader } = require('./ets-test-runtime.cjs');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = relative => path.join(root, relative + '.ets');
const load = createLoader();
const experimentModels = load(source('domain/models/Experiment'));
const { AlbumExperiment, AlbumPhase, AlbumAction, AlbumCopyEvidence, AssetEvidence, LabAlbum } = experimentModels;
const { albumActionError, sameAssetContent, reconciledAlbumPhase, isAlbumPending } = load(source('domain/usecases/ExperimentRules'));
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS ' + name); }
function evidence(inA = false, inB = false) {
  return Object.assign(new AssetEvidence(), { uri: 'test://generated-photo', sha256: 'a'.repeat(64), bytes: 100,
    dateTaken: 123, ownerAlbum: 'test-owner', inA, inB,
    copyA: inA ? copy('A') : undefined, copyB: inB ? copy('B') : undefined,
    albumACount: inA ? 1 : 0, albumBCount: inB ? 1 : 0 });
}
function copy(key) { return Object.assign(new AlbumCopyEvidence(), {uri: 'test://copy-' + key, sha256:'a'.repeat(64), bytes:100, dateTaken:125}); }
function session(phase = AlbumPhase.Created, inA = false, inB = false) {
  return Object.assign(new AlbumExperiment(), { id: 'unit-fixture', phase, createdByLab: true,
    assetUri: 'test://generated-photo', fixtureHash: 'a'.repeat(64), baseline: evidence(), latest: evidence(inA, inB),
    albumA: new LabAlbum('test://A', 'A'), albumB: new LabAlbum('test://B', 'B'),
    verifiedCopyA: inA ? copy('A') : undefined, verifiedCopyB: inB ? copy('B') : undefined });
}
function fixtureEnvironment() {
  const env = { events: [], current: evidence(), saves: 0, snapshots: 0, nativeCalls: 0,
    failSave: 0, failSnapshot: 0, failNative: false, denyPermission: false };
  class Repository {
    async loadAlbum() { return structuredClone(env.storedAlbum || session()); }
    async saveAlbum(value) { env.events.push('save:' + value.phase); if (++env.saves === env.failSave) throw Error('disk full'); env.storedAlbum = structuredClone(value); }
  }
  class Albums {
    async generateFixture() { env.events.push('private-fixture'); return '/test/private-fixture'; }
    async createAsset() { env.nativeCalls++; env.events.push('native-create'); return env.current.uri; }
    async snapshot() { env.events.push('snapshot'); if (++env.snapshots === env.failSnapshot) throw Error('query failed'); return structuredClone(env.current); }
    async mutate(_, action) {
      env.nativeCalls++; env.events.push('native:' + action);
      if (env.failNative) throw Object.assign(Error('unknown native outcome at private path'), {code: env.nativeErrorCode || 0});
      if (env.noAlbumChange) return;
      if (action === AlbumAction.AddA) { env.current.inA = true; env.current.copyA = copy('A'); env.current.albumACount = 1; }
      if (action === AlbumAction.AddB) { env.current.inB = true; env.current.copyB = copy('B'); env.current.albumBCount = 1; }
      if (action === AlbumAction.RemoveB) { env.current.inB = false; env.current.copyB = undefined; env.current.albumBCount = 0; }
    }
  }
  const overrides = new Map([
    [source('domain/models/Experiment'), experimentModels],
    [source('data/repositories/ExperimentRepository'), { ExperimentRepository: Repository }],
    [source('platform/media/AlbumExperimentAdapter'), { AlbumExperimentAdapter: Albums }],
    [source('platform/files/ContentHash'), { contentHash: async () => 'a'.repeat(64) }],
    [source('platform/permissions/PermissionProbe'), { PermissionProbe: class { canWriteLibrary() { return !env.denyPermission; } } }],
  ]);
  const Service = createLoader(overrides)(source('services/operations/ExperimentService')).ExperimentService;
  return { env, service: new Service({}), Service };
}

async function main() {
  await test('fresh generated sample can be added to A', () => assert.equal(albumActionError(session(), AlbumAction.AddA), ''));
  await test('private or selected external photo is rejected', () => { const value = session(); value.createdByLab = false; assert.notEqual(albumActionError(value, AlbumAction.Trash), ''); });
  for (const phase of [AlbumPhase.Creating, AlbumPhase.AddingA, AlbumPhase.AddingB, AlbumPhase.RemovingB, AlbumPhase.Trashing]) {
    await test('pending ' + phase + ' cannot be replayed', () => { assert.ok(isAlbumPending(phase)); assert.notEqual(albumActionError(session(phase), AlbumAction.Trash), ''); });
  }
  await test('same album target rejected', () => { const value = session(); value.albumB = value.albumA; assert.notEqual(albumActionError(value, AlbumAction.AddA), ''); });
  await test('URI mismatch cannot be rescued by matching content', () => { const after = evidence(); after.uri = 'test://other'; assert.equal(sameAssetContent(evidence(), after), false); });
  for (const field of ['sha256', 'bytes', 'dateTaken']) {
    await test('changed ' + field + ' blocks writes', () => { const value = session(); value.latest[field] = field === 'sha256' ? 'b'.repeat(64) : 999; assert.notEqual(albumActionError(value, AlbumAction.AddA), ''); });
  }
  await test('empty digest is not verification', () => { const value = evidence(); value.sha256 = ''; assert.equal(sameAssetContent(value, value), false); });
  await test('duplicate add A blocked', () => assert.notEqual(albumActionError(session(AlbumPhase.InA, true), AlbumAction.AddA), ''));
  await test('add B requires verified membership A', () => assert.notEqual(albumActionError(session(AlbumPhase.InA, false), AlbumAction.AddB), ''));
  await test('remove B requires this round verified add B', () => assert.notEqual(albumActionError(session(AlbumPhase.Created, false, true), AlbumAction.RemoveB), ''));
  await test('pending add reconciles only after observed target membership', () => {
    assert.equal(reconciledAlbumPhase(AlbumPhase.AddingA, evidence()), AlbumPhase.AddingA);
    assert.equal(reconciledAlbumPhase(AlbumPhase.AddingA, evidence(true)), AlbumPhase.InA);
  });
  await test('pending removal reconciles only after target absent', () => {
    assert.equal(reconciledAlbumPhase(AlbumPhase.RemovingB, evidence(false, true)), AlbumPhase.RemovingB);
    assert.equal(reconciledAlbumPhase(AlbumPhase.RemovingB, evidence()), AlbumPhase.RemovedB);
  });
  await test('readability does not prove a trash or restore operation', () => assert.equal(reconciledAlbumPhase(AlbumPhase.TrashRequested, evidence()), AlbumPhase.TrashRequested));
  await test('unknown stored phase rejected', () => assert.notEqual(albumActionError(session('unknown'), AlbumAction.Trash), ''));
  await test('mismatched recorded operation reference rejected', () => {
    const value = session(); value.assetUri = 'test://other'; assert.notEqual(albumActionError(value, AlbumAction.Trash), '');
  });

  await test('journal flush failure prevents library creation', async () => {
    const { env, service } = fixtureEnvironment(); env.failSave = 1;
    const value = session(AlbumPhase.Empty); env.storedAlbum = value; value.createdByLab = false; value.assetUri = '';
    await assert.rejects(service.createSample(value)); assert.equal(env.nativeCalls, 0);
  });
  await test('revoked write permission prevents creation', async () => {
    const { env, service } = fixtureEnvironment(); env.denyPermission = true;
    await assert.rejects(service.createSample(session(AlbumPhase.Empty))); assert.equal(env.nativeCalls, 0);
  });
  await test('creation preserves minted identity before querying', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(AlbumPhase.Empty); env.storedAlbum = value; value.assetUri = '';
    await service.createSample(value); assert.equal(value.phase, AlbumPhase.Created);
    assert.ok(env.events.indexOf('save:creating') < env.events.indexOf('native-create'));
    assert.equal(env.events.filter(item => item === 'save:creating').length, 2);
  });
  await test('native add occurs only after durable pending intent', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(); await service.mutateAlbum(value, AlbumAction.AddA);
    assert.equal(value.phase, AlbumPhase.InA); assert.ok(env.events.indexOf('save:adding_a') < env.events.indexOf('native:add_a'));
  });
  await test('pending journal failure prevents native add', async () => {
    const { env, service } = fixtureEnvironment(); env.failSave = 1;
    await assert.rejects(service.mutateAlbum(session(), AlbumAction.AddA)); assert.equal(env.nativeCalls, 0);
  });
  await test('unknown native failure remains pending and cannot be replayed', async () => {
    const { env, service } = fixtureEnvironment(); env.failNative = true; const value = session();
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddA)); assert.equal(value.phase, AlbumPhase.AddingA);
    await service.recheckAlbum(value); await assert.rejects(service.mutateAlbum(value, AlbumAction.AddA)); assert.equal(env.nativeCalls, 1);
  });
  await test('postquery failure is reconciled without repeating native add', async () => {
    const { env, service } = fixtureEnvironment(); env.failSnapshot = 2; const value = session();
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddA)); assert.equal(value.phase, AlbumPhase.AddingA);
    await service.recheckAlbum(value); assert.equal(value.phase, AlbumPhase.InA); assert.equal(env.nativeCalls, 1);
  });
  await test('failed B postcondition preserves observed A membership and cannot replay', async () => {
    const { env, service } = fixtureEnvironment(); env.current = evidence(true); env.noAlbumChange = true;
    const value = session(AlbumPhase.InA, true); env.storedAlbum = structuredClone(value);
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddB), /A：包含已核对同内容副本/);
    assert.equal(env.storedAlbum.latest.inA, true); assert.equal(env.storedAlbum.latest.inB, false);
    assert.equal(env.storedAlbum.phase, AlbumPhase.AddingB); assert.equal(env.storedAlbum.lastNativeReturned, true);
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddB)); assert.equal(env.nativeCalls, 1);
  });
  await test('gallery trash errors retain API provenance and code without exposing native messages', async () => {
    const { env, service } = fixtureEnvironment(); env.failNative = true; env.nativeErrorCode = 1014000001;
    const value = session(); await assert.rejects(service.mutateAlbum(value, AlbumAction.Trash), /图库回收站/);
    assert.equal(env.storedAlbum.lastErrorCode, 1014000001); assert.equal(env.storedAlbum.phase, AlbumPhase.Trashing);
    assert.equal(env.storedAlbum.lastError.includes('private path'), false); assert.equal(env.storedAlbum.lastNativeReturned, false);
  });
  await test('legacy membership evidence requires new enumeration before any further native writes', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(); delete value.latest.membershipVersion;
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddA), /旧版/); assert.equal(env.nativeCalls, 0);
  });
  await test('external membership change blocks stale operation', async () => {
    const { env, service } = fixtureEnvironment(); env.current.inA = true;
    await assert.rejects(service.mutateAlbum(session(), AlbumAction.AddA)); assert.equal(env.nativeCalls, 0);
  });
  await test('stale page cannot mutate or overwrite latest journal', async () => {
    const { env, service } = fixtureEnvironment(); env.storedAlbum = session(AlbumPhase.InA, true);
    await assert.rejects(service.mutateAlbum(session(), AlbumAction.AddA)); assert.equal(env.nativeCalls, 0); assert.equal(env.saves, 0);
    await assert.rejects(service.recheckAlbum(session())); assert.equal(env.saves, 0);
  });
  await test('viewmodel failure does not save stale session over durable journal', async () => {
    const { env, Service } = fixtureEnvironment();
    const overrides = new Map([[source('services/operations/ExperimentService'), { ExperimentService: Service }],
      [source('platform/permissions/PermissionProbe'), { PermissionProbe: class {} }]]);
    const vmModule = createLoader(overrides, { Observed: value => value })(source('viewmodels/ExperimentViewModel'));
    const vm = new vmModule.ExperimentViewModel(); await vm.initialize({});
    env.storedAlbum = session(AlbumPhase.InA, true);
    await vm.run(vmModule.LabCommand.AddA, true);
    assert.equal(env.nativeCalls, 0); assert.equal(env.saves, 0); assert.equal(env.storedAlbum.phase, AlbumPhase.InA);
    assert.equal(vm.busy, false); assert.equal(Service.tryAcquire(), true); Service.release();
  });
  await test('a second page cannot enter while another experiment holds the process lease', async () => {
    const { env, Service } = fixtureEnvironment();
    const overrides = new Map([[source('services/operations/ExperimentService'), { ExperimentService: Service }],
      [source('platform/permissions/PermissionProbe'), { PermissionProbe: class {} }]]);
    const vmModule = createLoader(overrides, { Observed: value => value })(source('viewmodels/ExperimentViewModel'));
    const vm = new vmModule.ExperimentViewModel(); await vm.initialize({}); assert.equal(Service.tryAcquire(), true);
    await vm.run(vmModule.LabCommand.AddA, true); assert.equal(env.saves, 0); assert.equal(env.nativeCalls, 0);
    Service.release(); assert.equal(Service.tryAcquire(), true); Service.release();
  });
  await test('add B records another copy while original identity and A copy are preserved', async () => {
    const { env, service } = fixtureEnvironment(); env.current = evidence(true); const value = session(AlbumPhase.InA, true); env.storedAlbum = value;
    await service.mutateAlbum(value, AlbumAction.AddB); assert.equal(value.latest.inA, true); assert.equal(value.latest.inB, true);
    assert.equal(value.assetUri, 'test://generated-photo'); assert.equal(value.verifiedCopyB.uri, 'test://copy-B');
  });
  await test('nonempty target without matching sample cannot be used for copy attribution', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(); value.latest.albumACount = 1;
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddA)); assert.equal(env.nativeCalls, 0);
  });
  await test('matching content on another B URI cannot replace this round verified copy', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(AlbumPhase.InB, true, true);
    value.latest.copyB.uri = 'test://foreign-copy';
    await assert.rejects(service.mutateAlbum(value, AlbumAction.RemoveB)); assert.equal(env.nativeCalls, 0);
  });
  await test('fresh preflight catches changed copy identity despite unchanged original', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(AlbumPhase.InB, true, true);
    env.storedAlbum = structuredClone(value); env.current = evidence(true, true); env.current.copyB.uri = 'test://replacement';
    await assert.rejects(service.mutateAlbum(value, AlbumAction.RemoveB)); assert.equal(env.nativeCalls, 0);
  });
  await test('read-only recheck never grants ownership of a replacement B copy', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(AlbumPhase.InB, true, true);
    env.storedAlbum = structuredClone(value); env.current = evidence(true, true); env.current.copyB.uri = 'test://replacement';
    await service.recheckAlbum(value); assert.equal(value.verifiedCopyB.uri, 'test://copy-B');
    await assert.rejects(service.mutateAlbum(value, AlbumAction.RemoveB)); assert.equal(env.nativeCalls, 0);
  });
  await test('legacy baseline stays read-only even after copy observation is upgraded', async () => {
    const { env, service } = fixtureEnvironment(); const value = session(AlbumPhase.AddingA);
    value.baseline.membershipVersion = 2; env.storedAlbum = structuredClone(value); env.current = evidence(true);
    await service.recheckAlbum(value); assert.equal(value.phase, AlbumPhase.AddingA); assert.equal(value.verifiedCopyA, undefined);
    await assert.rejects(service.mutateAlbum(value, AlbumAction.AddB)); assert.equal(env.nativeCalls, 0);
  });
  function hashAdapter(data, declaredSize = data.length) {
    let offset = 0, closes = 0;
    const overrides = new Map([
      ['@kit.CoreFileKit', { fileIo: { OpenMode: { READ_ONLY: 0 }, open: async () => ({ fd: 1 }), stat: async () => ({ size: declaredSize }),
        read: async (_, target) => { const count = Math.min(target.byteLength, data.length - offset); new Uint8Array(target).set(data.subarray(offset, offset + count)); offset += count; return count; },
        close: async () => { closes++; } } }],
      ['@kit.CryptoArchitectureKit', { cryptoFramework: { createMd: () => {
        const digest = crypto.createHash('sha256'); return { update: async blob => { digest.update(blob.data); }, digest: async () => ({ data: digest.digest() }) };
      } } }],
    ]);
    return { hash: createLoader(overrides)(source('platform/files/ContentHash')).contentHash, closes: () => closes };
  }
  await test('streaming hash covers final partial block', async () => {
    const data = Buffer.alloc(512 * 1024 + 13, 83); const fixture = hashAdapter(data);
    assert.equal(await fixture.hash('test://fixture'), crypto.createHash('sha256').update(data).digest('hex')); assert.equal(fixture.closes(), 1);
  });
  await test('hash refuses oversized file before reading and closes descriptor', async () => {
    const fixture = hashAdapter(Buffer.from('data')); await assert.rejects(fixture.hash('test://fixture', 2)); assert.equal(fixture.closes(), 1);
  });
  await test('hash rejects file changing length during read', async () => {
    const fixture = hashAdapter(Buffer.from('short'), 9); await assert.rejects(fixture.hash('test://fixture')); assert.equal(fixture.closes(), 1);
  });

  function repositoryFixture() {
    const data = new Map();
    const store = { get: async (key, fallback) => data.has(key) ? data.get(key) : fallback,
      put: async (key, value) => { assert.ok(typeof value !== 'string' || value.length <= 8192, 'Preferences per-value limit'); data.set(key, value); },
      delete: async key => { data.delete(key); }, flush: async () => {} };
    const overrides = new Map([['@kit.ArkData', { preferences: { getPreferences: async () => store } }]]);
    const Repository = createLoader(overrides)(source('data/repositories/ExperimentRepository')).ExperimentRepository;
    return { data, repository: new Repository({}) };
  }
  await test('twenty archived rounds fit per-value limits and retain independent records', async () => {
    const { data, repository } = repositoryFixture();
    for (let index = 0; index < 25; index++) {
      const value = session(); value.id = 'round-' + index; value.message = 'x'.repeat(3000);
      await repository.saveAlbum(value); await repository.archiveAlbum(value);
    }
    const index = JSON.parse(data.get('album_archive_index')); assert.equal(index.length, 20);
    assert.equal([...data.keys()].filter(key => key.startsWith('album_archive_') && key !== 'album_archive_index').length, 20);
    assert.equal(JSON.parse(data.get(index[0])).id, 'round-24'); assert.equal((await repository.loadAlbum()).phase, AlbumPhase.Empty);
  });
  await test('stale archive cannot clear a newer active session', async () => {
    const { repository } = repositoryFixture(); const current = session(AlbumPhase.InA, true);
    await repository.saveAlbum(current); await assert.rejects(repository.archiveAlbum(session()));
    assert.equal((await repository.loadAlbum()).phase, AlbumPhase.InA);
  });
  await test('corrupted journal is rejected without overwriting it', async () => {
    const { data, repository } = repositoryFixture(); const raw = JSON.stringify({ phase: 'unknown', assetUri: '', createdByLab: true });
    data.set('album', raw); await assert.rejects(repository.loadAlbum()); assert.equal(data.get('album'), raw);
  });
  console.log(`${passed}/${passed} host experiment tests passed. Native adapters use explicit test doubles; no phone permissions or external resources were changed.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
