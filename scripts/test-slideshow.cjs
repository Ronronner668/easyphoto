const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const src = name => path.resolve(__dirname, '../entry/src/main/ets', name + '.ets');
const load = createLoader();
const { SlideshowPhoto, SlideshowRecord, SlideshowSettings } = load(src('domain/models/Slideshow'));
const { SlideshowSession } = load(src('domain/usecases/SlideshowSession'));
const photo = (reference, taken = 0, added = 0) => new SlideshowPhoto(reference, reference, taken, added, 640, 480);
let passed = 0;
async function test(name, run) { await run(); passed++; console.log('PASS ' + name); }
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }

function modelFixture() {
  const env = { photos: [photo('one', 1), photo('two', 2), photo('three', 3)], records: [], saved: [], timers: new Map(), timerId: 0,
    musicLoads: 0, musicCloses: 0, musicStates: [], removed: [] };
  class Music {
    constructor() { env.music = this; }
    async load() { env.musicLoads++; if (env.musicHold) await env.musicHold.promise; if (env.musicFail) { this.failed(); throw Error('audio'); } }
    setPlaying(value) { env.musicStates.push(value); }
    async close() { env.musicCloses++; }
  }
  const overrides = new Map([
    ['@kit.AbilityKit', {}],
    [src('platform/media/SlideshowAlbumSource'), { SlideshowAlbumSource: class {
      async read(_album, cancelled) { if (env.hold) await env.hold.promise; if (env.readFail) throw Error('read'); return cancelled() ? [] : env.photos; }
    } }],
    [src('platform/media/SlideshowMusic'), { SlideshowMusic: Music }],
    [src('platform/files/SlideshowMusicFiles'), { SlideshowMusicFiles: class {
      path(file) { return file; }
      async choose() { return env.chosen; }
      async remove(file) { env.removed.push(file); }
    } }],
    [src('data/repositories/SlideshowRepository'), { SlideshowRepository: class {
      async load() { if (env.loadFail) throw Error('record'); return { albums: env.records }; }
      async save(record) { if (env.saveFail) throw Error('save'); env.saved.push(JSON.parse(JSON.stringify(record))); }
    } }]
  ]);
  const { SlideshowViewModel } = createLoader(overrides, { Observed: value => value,
    setTimeout: (fn, ms) => { const id = ++env.timerId; env.timers.set(id, { fn, ms }); return id; },
    clearTimeout: id => env.timers.delete(id)
  })(src('viewmodels/SlideshowViewModel'));
  const model = new SlideshowViewModel(); model.initialize({}, { reference: 'album', name: 'Family' });
  env.fire = () => { const [id, timer] = env.timers.entries().next().value; env.timers.delete(id); timer.fn(); };
  return { model, env };
}

function repositoryFixture() {
  const env = { raw: '', writes: 0, fail: false };
  const store = {
    async get() { return env.raw; },
    async put(_key, value) { env.writes++; env.raw = value; },
    async flush() { if (env.fail) throw Error('disk'); }
  };
  const { SlideshowRepository } = createLoader(new Map([
    ['@kit.AbilityKit', {}], ['@kit.ArkData', { preferences: { getPreferences: async () => store } }]
  ]))(src('data/repositories/SlideshowRepository'));
  return { env, repository: new SlideshowRepository({}) };
}

function albumFixture() {
  const env = { permission: true, albumCount: 1, reference: 'album', closed: [], released: 0 };
  const assets = {
    getCount: () => 2,
    async getObjectByPosition(index) { if (env.assetFail) throw Error('asset'); return { uri: 'photo' + index, displayName: 'name', get: () => index + 1 }; },
    close() { env.closed.push('assets'); }
  };
  class Predicates { equalTo(key, value) { env[key] = value; return this; } }
  const helper = {
    async getAlbums() { return { getCount: () => env.albumCount,
      async getFirstObject() { return { albumUri: env.reference, async getAssets() { return assets; } }; },
      close() { env.closed.push('albums'); } }; },
    async release() { env.released++; }
  };
  const { SlideshowAlbumSource } = createLoader(new Map([
    ['@kit.AbilityKit', {}], ['@kit.ArkData', { dataSharePredicates: { DataSharePredicates: Predicates } }],
    ['@kit.MediaLibraryKit', { photoAccessHelper: { getPhotoAccessHelper: () => helper, AlbumKeys: { URI: 'albumFilter' },
      PhotoKeys: { PHOTO_TYPE: 'photoFilter', DATE_TAKEN: 'taken', DATE_ADDED: 'added', WIDTH: 'width', HEIGHT: 'height' }, PhotoType: { IMAGE: 1 } } }],
    [src('platform/permissions/PermissionProbe'), { PermissionProbe: class { canReadLibrary() { return env.permission; } } }]
  ]))(src('platform/media/SlideshowAlbumSource'));
  return { env, source: new SlideshowAlbumSource({}), album: { reference: 'album', type: 0, subtype: 1 } };
}

function musicFixture() {
  const env = { handlers: {}, released: 0, closed: 0, played: 0, paused: 0 };
  const player = {
    state: 'idle',
    on(name, callback) { env.handlers[name] = callback; },
    set fdSrc(value) { env.fd = value.fd; this.state = 'initialized'; env.handlers.stateChange('initialized'); },
    async prepare() { if (env.hold) return; this.state = 'prepared'; env.handlers.stateChange('prepared'); },
    setVolume(value) { env.volume = value; },
    async play() { env.played++; this.state = 'playing'; },
    async pause() { env.paused++; this.state = 'paused'; },
    async release() { env.released++; this.state = 'released'; env.handlers.stateChange?.('released'); }
  };
  const { SlideshowMusic } = createLoader(new Map([
    ['@kit.MediaKit', { media: { createAVPlayer: async () => { if (env.createFail) throw Error('native player'); return player; } } }],
    ['@kit.AudioKit', { audio: { StreamUsage: { STREAM_USAGE_MUSIC: 1 }, InterruptHint: { INTERRUPT_HINT_RESUME: 0 },
      AudioStreamDeviceChangeReason: { REASON_OLD_DEVICE_UNAVAILABLE: 2 } } }],
    ['@kit.CoreFileKit', { fileIo: { OpenMode: { READ_ONLY: 0 }, open: async () => ({ fd: 7 }), close: async () => { env.closed++; } } }],
    ['@kit.PerformanceAnalysisKit', { hilog: { warn() {} } }]
  ]))(src('platform/media/SlideshowMusic'));
  return { env, music: new SlideshowMusic() };
}

function musicFilesFixture() {
  const env = { selected: ['audio:sample'], opened: [], copied: [], removed: [], dirs: [], closed: [], size: 1024 };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 2 },
    async open(name, mode) { env.opened.push([name, mode]); return { fd: mode === 0 ? 1 : 2 }; },
    async stat() { return { size: env.size }; },
    async mkdtemp(prefix) { assert.equal(prefix, '/private/memory_XXXXXX'); return '/private/memory_ABC123'; },
    async copyFile(from, to) { env.copied.push([from, to]); if (env.copyFail) throw Error('copy'); },
    async fsync() {}, async close(fd) { env.closed.push(fd); },
    async unlink(name) { env.removed.push(name); }, async rmdir(name) { env.dirs.push(name); }
  };
  const { SlideshowMusicFiles } = createLoader(new Map([
    ['@kit.AbilityKit', {}], ['@kit.PerformanceAnalysisKit', { hilog: { warn() {} } }],
    ['@kit.CoreFileKit', { fileIo, picker: { AudioSelectOptions: class {}, AudioViewPicker: class { async select() { return env.selected; } } } }]
  ]))(src('platform/files/SlideshowMusicFiles'));
  return { env, files: new SlideshowMusicFiles({ filesDir: '/private' }) };
}

async function main() {
  await test('native playback button feedback preserves adaptive ink and restores pressed state on older runtimes', () => {
    for (const native of [true, false]) {
      class Effect { constructor() { this.value = {}; } pressShadow(value) { this.value.press = value; return this; }
        pointLight(value) { this.value.point = value; return this; } buildEffect() { return this.value; } }
      const disabled = { empty: true };
      const { PlaybackButtonMaterial } = createLoader(new Map([
        ['@kit.ArkUI', { uiMaterial: native ? { isImmersiveMaterialSupported: () => true,
          Material: { empty: disabled }, ImmersiveStyle: { ULTRA_THIN: 0 }, ImmersiveMaterial: class { constructor(options) { this.options = options; } } } : {} }],
        ['@kit.UIDesignKit', { hdsEffect: { HdsEffectBuilder: Effect, PressShadowType: { NONE: 0, BLEND_WHITE: 1 },
          PointLightSourceType: { NONE: 0, SOFT: 1 }, PointLightIlluminatedType: { NONE: 0, BORDER_CONTENT: 3 } } }],
        ['@kit.PerformanceAnalysisKit', { hilog: { info() {} } }]
      ]), { Color: { Transparent: 0 }, BlurStyle: { COMPONENT_ULTRA_THIN: 1 }, $r: name => name })(src('common/PlaybackChromeMaterial'));
      const calls = []; const attrs = {};
      for (const name of ['backgroundColor','systemMaterial','backgroundBlurStyle','border','visualEffect','borderWidth','stateEffect']) {
        attrs[name] = value => { calls.push({ name, value }); return attrs; };
      }
      const button = new PlaybackButtonMaterial(); button.initialize(); button.applyNormalAttribute(attrs);
      button.applyPressedAttribute(attrs); button.applyNormalAttribute(attrs);
      if (native) {
        const material = calls.filter(c => c.name === 'systemMaterial');
        assert.equal(material.length, 3); assert.ok(material.every(c => c.value === disabled));
      } else {
        assert.equal(calls.some(c => c.name === 'systemMaterial'), false);
        assert.deepEqual(calls.filter(c => c.name === 'visualEffect').map(c => c.value.press), [0, 0, 0]);
      }
      assert.ok(calls.some(c => c.name === 'stateEffect' && c.value === false));
      assert.ok(calls.some(c => c.name === 'borderWidth' && c.value === 0));
      assert.equal(calls.some(c => c.name === 'fontColor' || c.name === 'fillColor'), false);
    }
  });
  await test('local contrast chooses each control independently rather than using the whole photograph average', () => {
    const { ContrastGrid, ChromeRegion, contrastInk } = load(src('domain/usecases/SlideshowContrast'));
    const grid = new ContrastGrid(2, 2, 400, 400, [1, 0, 1, 0]);
    assert.equal(contrastInk(grid, new ChromeRegion('left', 0, 0, 100, 100), 400, 400, 1, 0, 0, false), true);
    assert.equal(contrastInk(grid, new ChromeRegion('right', 300, 0, 100, 100), 400, 400, 1, 0, 0, true), false);
  });
  await test('contain-fit black margins stay light-ink while the photograph underneath changes with zoom and pan', () => {
    const { ContrastGrid, ChromeRegion, contrastInk } = load(src('domain/usecases/SlideshowContrast'));
    const grid = new ContrastGrid(2, 2, 800, 400, [1, 1, 1, 1]);
    const bottom = new ChromeRegion('button', 100, 710, 80, 50);
    assert.equal(contrastInk(grid, bottom, 400, 800, 1, 0, 0, false), false);
    assert.equal(contrastInk(grid, bottom, 400, 800, 4, 0, 0, false), true);
    assert.equal(contrastInk(grid, bottom, 400, 800, 4, 2000, 0, true), false);
    assert.equal(contrastInk(grid, bottom, 800, 400, 1, 0, 0, true), false);
  });
  await test('contrast uses separate thresholds to avoid color flicker near the crossover', () => {
    const { ContrastGrid, ChromeRegion, contrastInk } = load(src('domain/usecases/SlideshowContrast'));
    const grid = new ContrastGrid(1, 1, 100, 100, [0.18]); const area = new ChromeRegion('text', 0, 0, 100, 100);
    assert.equal(contrastInk(grid, area, 100, 100, 1, 0, 0, false), false);
    assert.equal(contrastInk(grid, area, 100, 100, 1, 0, 0, true), true);
    grid.luminance[0] = 0.22; assert.equal(contrastInk(grid, area, 100, 100, 1, 0, 0, false), true);
    grid.luminance[0] = 0.14; assert.equal(contrastInk(grid, area, 100, 100, 1, 0, 0, true), false);
  });
  await test('contrast thumbnail sampling is bounded, interprets BGRA, and closes all native resources on failure', async () => {
    const events = []; let fail = false;
    const pixels = { getImageInfo: async () => ({ size: { width: 2, height: 1 }, alphaType: 1 }),
      readPixels: async area => { events.push('read'); if (fail) throw Error('unreadable');
        new Uint8Array(area.pixels).set([0,0,255,255, 255,0,0,255]); }, release: async () => events.push('pixels') };
    const { SlideshowContrastSource } = createLoader(new Map([
      ['@kit.CoreFileKit', { fileIo: { OpenMode: { READ_ONLY: 0 }, open: async () => ({ fd: 4 }), close: async () => events.push('file') } }],
      ['@kit.ImageKit', { image: { PixelMapFormat: { BGRA_8888: 4 }, AlphaType: { PREMUL: 1 }, createImageSource: () => ({
        getImageInfo: async () => ({ size: { width: 12000, height: 6000 } }),
        createPixelMap: async options => { assert.equal(options.desiredSize.width, 64); assert.equal(options.desiredSize.height, 32); return pixels; },
        release: async () => events.push('source') }) } }]
    ]))(src('platform/media/SlideshowContrastSource'));
    const grid = await new SlideshowContrastSource().load('sample');
    assert.deepEqual(Array.from(grid.luminance), [0.2126, 0.0722]); assert.deepEqual(events, ['read', 'pixels', 'source', 'file']);
    events.length = 0; fail = true; await assert.rejects(new SlideshowContrastSource().load('sample'));
    assert.deepEqual(events, ['read', 'pixels', 'source', 'file']);
  });
  await test('inline zoom requires visible controls and ignores further scale updates after the gesture', () => {
    const { SlideshowViewport } = load(src('domain/usecases/SlideshowViewport'));
    const view = new SlideshowViewport();
    assert.equal(view.beginPinch(false), false); view.pinch(3); assert.equal(view.scale, 1);
    assert.equal(view.beginPinch(true), true); view.pinch(2); assert.equal(view.scale, 2);
    view.endPinch(); view.pinch(4); assert.equal(view.scale, 2);
    view.beginPinch(true); view.pinch(100); assert.equal(view.scale, 12);
    view.pinch(0.01); assert.equal(view.scale, 1);
  });
  await test('zoom pans are bounded by the fitted photo, rotation reclamps, and replay resets the viewport', () => {
    const { SlideshowViewport } = load(src('domain/usecases/SlideshowViewport'));
    const view = new SlideshowViewport(); view.beginPinch(true); view.pinch(2); view.endPinch();
    view.beginPan(); view.pan(1000, -1000); view.clamp(400, 800, 800, 400);
    assert.equal(view.x, 200); assert.equal(view.y, 0);
    view.clamp(800, 400, 800, 400); assert.equal(view.x, 200);
    view.beginPan(); view.pan(-10000, 10000); view.clamp(800, 400, 800, 400);
    assert.equal(view.x, -400); assert.equal(view.y, 200);
    view.reset(); assert.deepEqual([view.scale, view.x, view.y], [1, 0, 0]);
  });
  await test('new albums default to chronological order and five seconds, while saved choices survive reload', async () => {
    const settings = new SlideshowSettings(); assert.equal(settings.order, 'oldest'); assert.equal(settings.interval, 5);
    const { model, env } = modelFixture(); const saved = new SlideshowRecord(); saved.reference = 'album';
    saved.settings.order = 'newest'; saved.settings.interval = 8; env.records = [saved]; await model.load();
    assert.equal(model.settings.order, 'newest'); assert.equal(model.settings.interval, 8);
  });
  await test('stable chronological ordering uses added date only when taken is absent and deduplicates identities', () => {
    const session = new SlideshowSession(); session.configure([photo('b', 2), photo('a', 0, 1), photo('b', 2), photo('c', 2)], 'oldest');
    assert.deepEqual(session.photos.map(p => p.reference), ['a', 'b', 'c']);
    session.configure(session.photos, 'newest'); assert.deepEqual(session.photos.map(p => p.reference), ['c', 'b', 'a']);
  });
  await test('random resume keeps saved order, drops absent identities and appends new photos once', () => {
    const session = new SlideshowSession(); session.configure([photo('a'), photo('b'), photo('c')], 'random', ['b', 'gone', 'a', 'b'], 'a');
    assert.deepEqual(session.photos.map(p => p.reference), ['b', 'a', 'c']); assert.equal(session.index, 1);
  });
  await test('empty and single-photo sessions have bounded movement and explicit completion', () => {
    const session = new SlideshowSession(); session.configure([], 'oldest'); assert.equal(session.move(1, true), false);
    session.configure([photo('one')], 'oldest'); session.playing = true;
    assert.equal(session.move(-1, false), false); assert.equal(session.index, 0);
    assert.equal(session.move(1, false), false); assert.equal(session.ended, true); assert.equal(session.playing, false);
    assert.equal(session.move(1, true), true); assert.equal(session.index, 0);
  });
  await test('timer starts only after current photo loads and ignores stale completions', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start();
    assert.equal(env.timers.size, 0); model.imageLoaded('wrong'); assert.equal(env.timers.size, 0);
    model.imageLoaded('one'); assert.equal(env.timers.size, 1); env.fire(); assert.equal(model.current.reference, 'two');
    assert.equal(env.timers.size, 0); model.imageLoaded('one'); assert.equal(env.timers.size, 0);
    model.imageLoaded('two'); model.pause(); assert.equal(env.timers.size, 0); assert.equal(model.playing, false);
  });
  await test('manual navigation resets photo duration and last photo completes without wrapping', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start(); model.imageLoaded('one');
    model.move(1); assert.equal(env.timers.size, 0); model.imageLoaded('two'); env.fire(); model.imageLoaded('three'); env.fire();
    assert.equal(model.current.reference, 'three'); assert.equal(model.ended, true); assert.equal(model.playing, false);
  });
  await test('single-photo replay can complete again without waiting for a second image callback', async () => {
    const { model, env } = modelFixture(); env.photos = [photo('one')]; await model.load(); await model.start(); model.imageLoaded('one'); env.fire();
    await model.play(); assert.equal(env.timers.size, 1); env.fire(); assert.equal(model.ended, true);
  });
  await test('swiping holds the timer, including late image readiness, and advances exactly once without pausing music', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start(); model.imageLoaded('one');
    const musicStates = env.musicStates.length;
    model.beginSwipe(); assert.equal(env.timers.size, 0); model.imageLoaded('one');
    assert.equal(env.timers.size, 0); assert.equal(model.playing, true); assert.equal(env.musicStates.length, musicStates);
    model.endSwipe(1); assert.equal(model.current.reference, 'two'); assert.equal(model.playing, true);
    assert.equal(env.timers.size, 0); model.imageLoaded('two'); assert.equal(env.timers.size, 1);
    model.endSwipe(1); assert.equal(model.current.reference, 'two');
  });
  await test('already queued timer callbacks cannot skip a second photo after a swipe or resume', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start(); model.imageLoaded('one');
    const stale = env.timers.values().next().value.fn;
    model.beginSwipe(); model.endSwipe(1); model.imageLoaded('two');
    stale(); assert.equal(model.current.reference, 'two'); assert.equal(env.timers.size, 1);
    const beforePause = env.timers.values().next().value.fn;
    await model.toggle(); await model.toggle(); beforePause();
    assert.equal(model.current.reference, 'two'); assert.equal(env.timers.size, 1);
  });
  await test('cancelled swipe restarts the current photo duration without changing its identity', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start(); model.imageLoaded('one');
    model.beginSwipe(); model.endSwipe(0); assert.equal(model.current.reference, 'one'); assert.equal(env.timers.size, 1);
    env.fire(); assert.equal(model.current.reference, 'two');
  });
  await test('paused swipes remain paused and picture tap can resume the same photo', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start(); await model.toggle();
    model.beginSwipe(); model.endSwipe(1); model.imageLoaded('two');
    assert.equal(model.playing, false); assert.equal(env.timers.size, 0);
    await model.toggle(); assert.equal(model.playing, true); assert.equal(model.current.reference, 'two'); assert.equal(env.timers.size, 1);
  });
  await test('backgrounding or image failure cancels in-flight navigation without a late jump', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start(); model.imageLoaded('one');
    model.beginSwipe(); model.suspend(); model.endSwipe(1);
    assert.equal(model.current.reference, 'one'); assert.equal(model.playing, false); assert.equal(env.timers.size, 0);
    await model.play(); model.beginSwipe(); model.imageFailed('one'); model.endSwipe(1);
    assert.equal(model.current.reference, 'one'); assert.equal(model.playing, false); assert.equal(env.timers.size, 0);
  });
  await test('failed images skip on a delay and stop after three consecutive failures', async () => {
    const { model, env } = modelFixture(); await model.load(); await model.start();
    model.imageFailed('one'); env.fire(); model.imageFailed('two'); env.fire(); model.imageFailed('three');
    assert.equal(model.playing, false); assert.equal(env.timers.size, 0); assert.ok(model.notice);
  });
  await test('unreadable persistence cannot become empty history or be overwritten', async () => {
    const { model, env } = modelFixture(); env.loadFail = true; await model.load(); model.updateSettings();
    assert.equal(model.ready, false); assert.ok(model.error); assert.equal(env.saved.length, 0);
  });
  await test('failed refresh preserves visible photo data but disables playback', async () => {
    const { model, env } = modelFixture(); await model.load(); env.readFail = true; await model.load();
    assert.equal(model.photos.length, 3); assert.equal(model.ready, false); await model.start(); assert.equal(model.presenting, false);
  });
  await test('close cancels delayed photo loading', async () => {
    const { model, env } = modelFixture(); env.hold = deferred(); const pending = model.load(); await tick(); model.close();
    env.hold.resolve(); await pending; assert.equal(model.photos.length, 0); assert.equal(model.playing, false);
  });
  await test('rapid play requests prepare music once and suspension rejects delayed playback', async () => {
    const { model, env } = modelFixture(); await model.load(); model.settings.music = 'music'; env.musicHold = deferred();
    const first = model.start(); await tick(); await model.play(); assert.equal(env.musicLoads, 1);
    model.suspend(); env.musicHold.resolve(); await first; assert.equal(model.playing, false); assert.equal(env.timers.size, 0);
  });
  await test('audio failure permits silent viewing and interruption pauses the slideshow', async () => {
    const { model, env } = modelFixture(); await model.load(); model.settings.music = 'music'; env.musicFail = true;
    await model.start(); assert.equal(model.playing, true); assert.ok(model.notice);
    env.music.interrupted(); assert.equal(model.playing, false);
  });
  await test('a native runtime music error can resume silently without repeatedly preparing a broken track', async () => {
    const { model, env } = modelFixture(); await model.load(); model.settings.music = 'music'; await model.start();
    env.music.failed(); assert.equal(model.playing, false); await model.play();
    assert.equal(model.playing, true); assert.equal(env.musicLoads, 1);
    const closes = env.musicCloses; model.stop();
    assert.equal(model.presenting, false); assert.equal(model.playing, false); assert.equal(env.musicCloses, closes + 1);
  });
  await test('failed save is explicit and a successful retry clears it', async () => {
    const { model, env } = modelFixture(); await model.load(); env.saveFail = true; assert.equal(await model.save(), false);
    assert.ok(model.saveError); env.saveFail = false; assert.equal(await model.save(), true); assert.equal(model.saveError, '');
  });
  await test('cancelled music selection preserves the existing file and preference', async () => {
    const { model, env } = modelFixture(); await model.load(); model.settings.music = 'old'; await model.chooseMusic();
    assert.equal(model.settings.music, 'old'); assert.deepEqual(env.removed, []);
  });
  await test('unknown save outcome preserves both imported music and previous cache', async () => {
    const { model, env } = modelFixture(); await model.load(); model.settings.music = 'old'; env.chosen = { file: 'new', name: 'new' }; env.saveFail = true;
    await model.chooseMusic(); assert.deepEqual(env.removed, []); assert.equal(model.settings.music, 'old'); assert.ok(model.saveError);
  });
  await test('successful replacement removes only the previous music after persistence', async () => {
    const { model, env } = modelFixture(); await model.load(); model.settings.music = 'old'; env.chosen = { file: 'new', name: 'new' };
    await model.chooseMusic(); assert.equal(model.settings.music, 'new'); assert.deepEqual(env.removed, ['old']);
    assert.equal(env.saved.at(-1).settings.music, 'new');
  });
  await test('repository serializes concurrent saves and captures each caller snapshot', async () => {
    const { repository, env } = repositoryFixture(); const first = new SlideshowRecord(); first.reference = 'one';
    const second = new SlideshowRecord(); second.reference = 'two'; const p = repository.save(first); first.name = 'changed';
    await Promise.all([p, repository.save(second)]); const data = JSON.parse(env.raw);
    assert.equal(data.albums.length, 2); assert.equal(data.albums[0].name, '');
  });
  await test('future or corrupt repository schemas never write defaults over original data', async () => {
    const { repository, env } = repositoryFixture(); const record = new SlideshowRecord(); record.reference = 'one';
    for (const raw of ['{', '{"version":2,"albums":[]}', '{"version":1,"albums":[null]}']) {
      env.raw = raw; await assert.rejects(repository.save(record)); assert.equal(env.raw, raw); assert.equal(env.writes, 0);
    }
    env.raw = ''; await repository.save(record); assert.equal(env.writes, 1);
  });
  await test('repository rejects imported music paths escaping its private directory', async () => {
    const { repository, env } = repositoryFixture(); const record = new SlideshowRecord(); record.reference = 'one'; record.settings.music = '../other';
    env.raw = JSON.stringify({ version: 1, albums: [record] }); await assert.rejects(repository.load());
  });
  await test('invalid new preferences are rejected before any repository write', async () => {
    const { repository, env } = repositoryFixture(); const record = new SlideshowRecord(); record.reference = 'one';
    record.settings.interval = 0; await assert.rejects(repository.save(record)); assert.equal(env.writes, 0); assert.equal(env.raw, '');
  });
  await test('album reads exact membership and closes all native resources', async () => {
    const { source, env, album } = albumFixture(); const photos = await source.read(album, () => false);
    assert.equal(photos.length, 2); assert.equal(env.albumFilter, 'album'); assert.equal(env.photoFilter, 1);
    assert.deepEqual(env.closed, ['assets', 'albums']); assert.equal(env.released, 1);
  });
  await test('mismatched album identity fails instead of falling back to all photos', async () => {
    const { source, env, album } = albumFixture(); env.reference = 'other'; await assert.rejects(source.read(album, () => false));
    assert.deepEqual(env.closed, ['albums']); assert.equal(env.released, 1);
  });
  await test('asset read failure and cancellation release every opened native result', async () => {
    const { source, env, album } = albumFixture(); env.assetFail = true; await assert.rejects(source.read(album, () => false));
    assert.deepEqual(env.closed, ['assets', 'albums']); assert.equal(env.released, 1);
    const fixture = albumFixture(); let calls = 0; const result = await fixture.source.read(fixture.album, () => ++calls > 2);
    assert.deepEqual(result, []); assert.equal(fixture.env.released, 1);
  });
  await test('native music playback follows AVPlayer state and releases player before closing descriptor', async () => {
    const { env, music } = musicFixture(); await music.load('private.audio', 0.25); music.setPlaying(true); await tick();
    assert.equal(env.played, 1); assert.equal(env.volume, 0.25); music.setPlaying(false); await tick(); assert.equal(env.paused, 1);
    await music.close(); assert.equal(env.released, 1); assert.equal(env.closed, 1);
  });
  await test('closing during preparation releases native music resources exactly once', async () => {
    const { env, music } = musicFixture(); env.hold = true; const pending = music.load('private.audio', 0.4); await tick();
    const rejected = assert.rejects(pending); await music.close(); await rejected;
    assert.equal(env.released, 1); assert.equal(env.closed, 1);
  });
  await test('failed native player creation still closes the selected music descriptor', async () => {
    const { env, music } = musicFixture(); env.createFail = true; await assert.rejects(music.load('private.audio', 0.4));
    assert.equal(env.released, 0); assert.equal(env.closed, 1);
  });
  await test('native audio interruption and output disconnection reach the playback pause handler', async () => {
    const { env, music } = musicFixture(); let interrupted = 0; music.interrupted = () => interrupted++;
    await music.load('private.audio', 0.4); env.handlers.audioInterrupt({ hintType: 0 }); assert.equal(interrupted, 0);
    env.handlers.audioInterrupt({ hintType: 1 }); env.handlers.audioOutputDeviceChangeWithInfo({ changeReason: 2 }); assert.equal(interrupted, 2);
    await music.close();
  });
  await test('music import copies only selected audio descriptors into a uniquely created private directory', async () => {
    const { env, files } = musicFilesFixture(); const selected = await files.choose();
    assert.equal(selected.file, 'memory_ABC123/track.audio'); assert.deepEqual(env.copied, [[1, 2]]);
    assert.equal(env.opened[1][0], '/private/memory_ABC123/track.audio'); assert.deepEqual(env.closed, [2, 1]);
    assert.deepEqual(env.removed, []); assert.throws(() => files.path('../private'));
  });
  await test('failed import cleans only the new private target and always closes both descriptors', async () => {
    const { env, files } = musicFilesFixture(); env.copyFail = true; await assert.rejects(files.choose());
    assert.deepEqual(env.removed, ['/private/memory_ABC123/track.audio']); assert.deepEqual(env.dirs, ['/private/memory_ABC123']);
    assert.deepEqual(env.closed, [2, 1]);
  });
  await test('cancelled or oversized audio imports do not create a target', async () => {
    const { env, files } = musicFilesFixture(); env.selected = []; assert.equal(await files.choose(), undefined); assert.equal(env.opened.length, 0);
    env.selected = ['audio:sample']; env.size = 51 * 1024 * 1024; await assert.rejects(files.choose());
    assert.equal(env.opened.length, 1); assert.deepEqual(env.copied, []); assert.deepEqual(env.closed, [1]);
  });
  await test('image decode is display-sized and releases pixels when a later resource cleanup fails', async () => {
    const env = { options: undefined, released: 0, closed: 0, fail: false };
    const pixels = { async release() { env.released++; } };
    const { SlideshowImageSource } = createLoader(new Map([
      ['@kit.CoreFileKit', { fileIo: { OpenMode: { READ_ONLY: 0 }, open: async () => ({ fd: 1 }), close: async () => { env.closed++; } } }],
      ['@kit.ImageKit', { image: { createImageSource: () => ({ getImageInfo: async () => ({ size: { width: 8000, height: 4000 } }),
        async createPixelMap(options) { env.options = options; return pixels; }, async release() { if (env.fail) throw Error('release'); } }) } }]
    ]))(src('platform/media/SlideshowImageSource'));
    const source = new SlideshowImageSource(); await source.load('photo:sample', 1920, 1080);
    assert.deepEqual(env.options.desiredSize, { width: 1920, height: 960 }); assert.equal(env.closed, 1);
    env.fail = true; await assert.rejects(source.load('photo:sample', 9000, 9000));
    assert.equal(env.options.desiredSize.width, 3840); assert.equal(env.released, 1); assert.equal(env.closed, 2);
  });
  await test('playback window restores original screen and immersive settings and serializes full-screen recovery', async () => {
    const env = { keep: [], immersive: [], orientation: [], bars: [], events: new Map(), maximized: 0, recovered: 0 };
    const target = {
      getWindowProperties: () => ({ isKeepScreenOn: false }), getImmersiveModeEnabledState: () => false,
      getPreferredOrientation: () => { if (env.failCapture) throw Error('window query'); return 0; },
      async setPreferredOrientation(value) { env.orientation.push(value); },
      getWindowSystemBarProperties: () => ({ statusBarContentColor: 'original' }),
      async setWindowSystemBarProperties(value) { env.bars.push(value); },
      on(name, callback) { env.events.set(name, callback); }, off(name) { env.events.delete(name); },
      setImmersiveModeEnabledState(value) { env.immersive.push(value); },
      async setWindowKeepScreenOn(value) { env.keep.push(value); }, getWindowStatus: () => 1,
      async maximize() { env.maximized++; }, async recover() { env.recovered++; }
    };
    const { SlideshowWindow } = createLoader(new Map([
      ['@kit.AbilityKit', {}], ['@kit.PerformanceAnalysisKit', { hilog: { warn() {} } }],
      ['@kit.ArkUI', { window: { getLastWindow: async () => target, Orientation: { AUTO_ROTATION: 5 }, WindowStatusType: { FLOATING: 1 },
        MaximizePresentation: { ENTER_IMMERSIVE: 2, EXIT_IMMERSIVE: 1 } } }]
    ]))(src('platform/media/SlideshowWindow'));
    let paused = 0; const playback = new SlideshowWindow({}, () => paused++, true, '#FFFFFFFF', '#FF101114'); await playback.open();
    playback.update(true, true); await tick(); assert.equal(env.keep.at(-1), true);
    assert.equal(env.immersive.at(-1), false); assert.equal(env.orientation.at(-1), 5);
    assert.equal(env.bars.at(-1).statusBarContentColor, '#FFFFFFFF');
    env.events.get('windowVisibilityChange')(false); assert.equal(paused, 1);
    await playback.toggleFullscreen(); playback.close(); await tick();
    assert.equal(env.maximized, 1); assert.equal(env.recovered, 1); assert.equal(env.keep.at(-1), false);
    assert.equal(env.immersive.at(-1), false); assert.equal(env.events.size, 0);
    assert.equal(env.orientation.at(-1), 0); assert.equal(env.bars.at(-1).statusBarContentColor, 'original');
    const writes = env.keep.length; env.failCapture = true;
    const failed = new SlideshowWindow({}, () => {}, true);
    await assert.rejects(failed.open()); failed.update(true, true); failed.close(); await tick();
    assert.equal(env.keep.length, writes);
  });
  console.log(`${passed}/${passed} slideshow checks passed. Native APIs use explicit host substitutes.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
