const assert=require('node:assert/strict');const path=require('node:path');const {createLoader}=require('./ets-test-runtime.cjs');
const src=n=>path.resolve(__dirname,'../entry/src/main/ets',n+'.ets');
function fixture(){
 const env={root:'file://docs/storage/Download/app',customRoots:'[]',reads:[],activations:[],symlink:'',badRoot:false};
 class URI{constructor(value){this.value=new URL(value);}get scheme(){return this.value.protocol.slice(0,-1);}get authority(){return this.value.host;}get query(){return this.value.search;}get fragment(){return this.value.hash;}getSegment(){return this.value.pathname.split('/').filter(Boolean).map(decodeURIComponent);}addSegment(part){return new URI(this.value.toString().replace(/\/$/,'')+'/'+encodeURIComponent(part));}toString(){return this.value.toString();}}
 const overrides=new Map([[src('platform/media/PhotoPlaceReader'),{PhotoPlaceReader:class{async read(){return{text:'地点未提供',needsPermission:false};}async request(){return false;}}}],
 ['@kit.ArkTS',{uri:{URI}}],['@kit.ArkData',{preferences:{async getPreferences(){return{async get(key,fallback){if(env.failPreferences)throw Error('unreadable');return key==='root'?env.root:key==='customRoots'?env.customRoots:fallback;},async put(){throw Error('must never write grant records');},async flush(){throw Error('must never flush grant records');}};}}}],
 ['@kit.CoreFileKit',{fileUri:{FileUri:class{constructor(ref){this.path=new URL(ref).pathname;}}},fileIo:{async lstat(file){env.reads.push(file);return{isDirectory:()=>!env.badRoot,isSymbolicLink:()=>file.includes(env.symlink)&&!!env.symlink};}},fileShare:{OperationMode:{READ_MODE:1,WRITE_MODE:2},async activatePermission(policies){env.activations.push(policies);},async persistPermission(){throw Error('must never persist new grants');}}}]
 ]);
 const {LegacyDocumentAccess}=createLoader(overrides)(src('platform/files/LegacyDocumentAccess'));return{env,access:new LegacyDocumentAccess({})};
}
let passed=0;async function test(n,f){await f();passed++;console.log('PASS '+n);}
async function main(){
 await test('managed historical document validates scope and every ancestor without file writes',async()=>{const{env,access}=fixture();assert.equal(await access.validate(env.root+'/拾光整理/old.jpg'),'/storage/Download/app/%E6%8B%BE%E5%85%89%E6%95%B4%E7%90%86/old.jpg');assert.equal(env.reads.length,3);assert.deepEqual(env.activations,[]);});
 await test('historical custom grants are not activated and direct the user to Files',async()=>{const{env,access}=fixture();env.customRoots=JSON.stringify(['file://docs/storage/shared']);await assert.rejects(access.validate('file://docs/storage/shared/old.jpg'),/文件管理器/);assert.deepEqual(env.activations,[]);assert.deepEqual(env.reads,[]);});
 await test('sibling references never inherit a matching string-prefix grant',async()=>{const{env,access}=fixture();env.customRoots=JSON.stringify(['file://docs/storage/shared']);await assert.rejects(access.validate('file://docs/storage/shared-other/old.jpg'));assert.deepEqual(env.reads,[]);assert.deepEqual(env.activations,[]);});
 await test('substituted symlink ancestor blocks historical access',async()=>{const{env,access}=fixture();env.symlink='unsafe';await assert.rejects(access.validate(env.root+'/拾光整理/unsafe/old.jpg'),/符号链接/);assert.equal(env.reads.some(file=>file.endsWith('old.jpg')),false);});
 await test('query fragments and decoded slash segments are rejected before file reads',async()=>{for(const tail of ['/拾光整理/old.jpg?x=1','/拾光整理/old.jpg#x','/拾光整理/A%2FB']){const{env,access}=fixture();await assert.rejects(access.validate(env.root+tail));assert.deepEqual(env.reads,[]);}});
 await test('missing corrupted or unreadable stored grants never create a new authorization',async()=>{for(const mode of ['missing','corrupt','read-failed']){const{env,access}=fixture();if(mode==='missing')env.root='';if(mode==='corrupt')env.customRoots='{';if(mode==='read-failed')env.failPreferences=true;await assert.rejects(access.validate('file://docs/storage/shared/old.jpg'));assert.deepEqual(env.reads,[]);assert.deepEqual(env.activations,[]);}});
 console.log(`${passed}/${passed} legacy document access checks passed with explicit native substitutes; no external files accessed.`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
