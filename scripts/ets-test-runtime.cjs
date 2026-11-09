const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const studioRoot = process.env.DEVECO_STUDIO_HOME || 'E:\\DevEcoStudio\\DevEco Studio';
const ts = require(path.join(studioRoot, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

// Test-only loader. Native modules must be explicitly replaced by test doubles.
function createLoader(overrides = new Map(), globals = {}) {
  const cache = new Map();
  function load(filename) {
    filename = path.resolve(filename);
    if (overrides.has(filename)) return overrides.get(filename);
    if (cache.has(filename)) return cache.get(filename).exports;
    const transformed = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
      reportDiagnostics: true,
      fileName: filename.replace(/\.ets$/, '.ts'),
    });
    const errors = (transformed.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
    assert.equal(errors.length, 0, errors.map(item => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));
    const entry = { exports: {} };
    cache.set(filename, entry);
    const localRequire = dependency => {
      if (!dependency.startsWith('.')) {
        assert.ok(overrides.has(dependency), 'Native package requires explicit test double: ' + dependency);
        return overrides.get(dependency);
      }
      return load(path.resolve(path.dirname(filename), dependency + '.ets'));
    };
    new Function('require', 'exports', 'module', ...Object.keys(globals), transformed.outputText)(
      localRequire, entry.exports, entry, ...Object.values(globals));
    return entry.exports;
  }
  return load;
}
module.exports = { createLoader };
