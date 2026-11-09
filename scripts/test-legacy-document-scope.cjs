const assert=require('node:assert/strict');
const path=require('node:path');const {createLoader}=require('./ets-test-runtime.cjs');
const {withinDownloadScope}=createLoader()(path.resolve(__dirname,'../entry/src/main/ets/domain/usecases/LegacyDocumentScope.ets'));
let passed=0;function test(name,body){body();passed++;console.log('PASS '+name);}
const root=['storage','Download','app'];const valid=[...root,'拾光整理','old.jpg'];
test('historical document stays within exact original scope',()=>assert.equal(withinDownloadScope('docs',root,'docs',valid),true));
test('sibling prefix cannot grant read access',()=>assert.equal(withinDownloadScope('docs',root,'docs',['storage','Download','app-other','拾光整理','old.jpg']),false));
test('root and unmanaged paths are rejected',()=>{assert.equal(withinDownloadScope('docs',root,'docs',root),false);assert.equal(withinDownloadScope('docs',root,'docs',[...root,'other','old.jpg']),false);});
test('authority mismatch is rejected',()=>assert.equal(withinDownloadScope('docs',root,'media',valid),false));
test('decoded traversal slash and control characters are rejected',()=>{for(const segment of ['..','.','A/B','A\\B','','A\u0000B'])assert.equal(withinDownloadScope('docs',root,'docs',[...root,'拾光整理',segment]),false);});
test('empty historical grant gives no read access',()=>assert.equal(withinDownloadScope('docs',[],'docs',valid),false));
console.log(`${passed}/${passed} legacy read-only document scope checks passed.`);
