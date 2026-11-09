const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const source = name => path.resolve(__dirname, '../entry/src/main/ets', name + '.ets');

function fixture() {
  const env = {
    granted: true, calls: 0, opens: 0, closes: 0, releases: 0,
    metadata: { latitude: '22,30,0', north: 'N', longitude: '113,15,0', east: 'E' },
    addresses: [{ administrativeArea: '示例省', locality: '示例市' }], saved: new Map()
  };
  const store = {
    async get(key, fallback) {
      if (env.failCacheRead) throw Error('cache read');
      return env.saved.has(key) ? env.saved.get(key) : fallback;
    },
    async put(key, value) {
      if (env.failCacheWrite) throw Error('cache write');
      env.saved.set(key, value);
    },
    async flush() {}
  };
  const overrides = new Map([
    ['@kit.AbilityKit', {
      abilityAccessCtrl: {
        GrantStatus: { PERMISSION_GRANTED: 0 },
        createAtManager: () => ({ checkAccessTokenSync: () => env.granted ? 0 : -1 })
      },
      bundleManager: {
        BundleFlag: { GET_BUNDLE_INFO_WITH_APPLICATION: 1 },
        getBundleInfoForSelfSync: () => ({ appInfo: { accessTokenId: 1 } })
      }
    }],
    ['@kit.LocationKit', { geoLocationManager: {
      async getAddressesFromLocation() {
        env.calls++;
        if (env.revokeDuringGeocode) env.granted = false;
        if (env.pendingGeocode) return new Promise(() => {});
        if (env.failGeocode) throw Error('geocode');
        return env.addresses;
      }
    } }],
    ['@kit.ImageKit', { image: {
      PropertyKey: { GPS_LATITUDE: 'latitude', GPS_LATITUDE_REF: 'north', GPS_LONGITUDE: 'longitude', GPS_LONGITUDE_REF: 'east' },
      createImageSource: () => ({
        async getImageProperty(key) { if (env.metadataError) throw { code: env.metadataError }; return env.metadata[key]; },
        async release() { env.releases++; }
      })
    } }],
    ['@kit.CoreFileKit', { fileIo: {
      OpenMode: { READ_ONLY: 0 },
      async open() { env.opens++; return { fd: 1 }; },
      async close() { env.closes++; }
    } }],
    ['@kit.ArkData', { preferences: { async getPreferences() { return store; } } }],
    ['@kit.PerformanceAnalysisKit', { hilog: { warn() {} } }]
  ]);
  const load = createLoader(overrides, { setTimeout, clearTimeout });
  const Reader = load(source('platform/media/PhotoPlaceReader')).PhotoPlaceReader;
  return { env, Reader, read: () => new Reader({}).read('test-photo') };
}

let passed = 0;
async function test(name, run) {
  await run();
  passed++;
  console.log('PASS ' + name);
}

async function main() {
  await test('online always uses system geocoder and stores a result for a new reader', async () => {
    const { env, read } = fixture();
    assert.equal((await read()).text, '示例省·示例市');
    assert.equal(env.saved.size, 1);
    env.addresses = [{ administrativeArea: '更新省', locality: '更新市' }];
    assert.equal((await read()).text, '更新省·更新市');
    assert.equal(env.calls, 2);
    env.failGeocode = true;
    assert.equal((await read()).text, '更新省·更新市');
    assert.equal(env.calls, 3);
  });
  await test('failed system lookup without cache displays coordinates', async () => {
    const { env, read } = fixture(); env.failGeocode = true;
    assert.equal((await read()).text, '22.50000°N · 113.25000°E');
    assert.equal(env.calls, 1);
  });
  await test('missing and malformed GPS show no location without reading cache or network', async () => {
    const { env, read } = fixture();
    env.metadata.latitude = '';
    assert.equal((await read()).text, '无地理位置信息');
    env.metadata.latitude = '95';
    assert.equal((await read()).text, '无地理位置信息');
    assert.equal(env.calls, 0);
    assert.equal(env.opens, env.closes);
    assert.equal(env.opens, env.releases);
  });
  await test('EXIF unsupported is no location while file decode errors propagate and release resources', async () => {
    const { env, read } = fixture(); env.metadataError = 62980123;
    assert.equal((await read()).text, '无地理位置信息');
    env.metadataError = 62980116;
    await assert.rejects(read());
    assert.equal(env.opens, env.closes);
    assert.equal(env.opens, env.releases);
  });
  await test('temporary online geocoding failure and empty results fall back to cache', async () => {
    const { env, read } = fixture(); await read();
    env.failGeocode = true;
    assert.equal((await read()).text, '示例省·示例市');
    env.failGeocode = false; env.addresses = [];
    assert.equal((await read()).text, '示例省·示例市');
  });
  await test('a stalled system lookup times out and uses persistent cache', async () => {
    const { env, read } = fixture(); await read(); env.pendingGeocode = true;
    assert.equal((await read()).text, '示例省·示例市');
    assert.equal(env.calls, 2);
  });
  await test('cache write failure preserves online result and cache read failure uses coordinates', async () => {
    const { env, read } = fixture(); env.failCacheWrite = true;
    assert.equal((await read()).text, '示例省·示例市');
    env.failGeocode = true; env.failCacheRead = true;
    assert.equal((await read()).text, '22.50000°N · 113.25000°E');
  });
  await test('coordinates from a different photo cannot reuse another location', async () => {
    const { env, read } = fixture(); await read(); env.failGeocode = true; env.metadata.latitude = '23';
    assert.equal((await read()).text, '23.00000°N · 113.25000°E');
  });
  await test('revoked permission blocks metadata and cached results', async () => {
    const { env, read } = fixture(); await read(); env.granted = false;
    assert.equal((await read()).needsPermission, true);
    assert.equal(env.opens, 1);
  });
  await test('revocation during geocoding does not cache or display the resolved location', async () => {
    const { env, read } = fixture(); env.revokeDuringGeocode = true;
    assert.equal((await read()).needsPermission, true);
    assert.equal(env.saved.size, 0);
  });
  console.log(passed + '/' + passed + ' photo location checks passed with explicit native substitutes.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
