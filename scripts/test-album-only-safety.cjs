const assert=require('node:assert/strict');
const path=require('node:path');const fs=require('node:fs');const {DatabaseSync}=require('node:sqlite');
const {createLoader}=require('./ets-test-runtime.cjs');const src=n=>path.resolve(__dirname,'../entry/src/main/ets',n+'.ets');
function fixture(){
 const db=new DatabaseSync(':memory:');const env={native:[],permissions:0,identifies:[],present:new Map(),members:new Map(),cancel:false};
 const identity=uri=>({uri,name:uri.replace(/[:/]/g,'_')+'.jpg',hash:'full-content-hash',bytes:4096,taken:123,retainOriginal:false});
 const rows=values=>{let i=-1;return{goToFirstRow(){i=0;return !!values.length;},goToNextRow(){return ++i<values.length;},getString(c){return Object.values(values[i])[c];},getLong(c){return Number(Object.values(values[i])[c]);},close(){}};};
 const store={async executeSql(sql,args=[]){db.prepare(sql).run(...args);},async querySql(sql,args=[]){return rows(db.prepare(sql).all(...args));},beginTransaction(){db.exec('BEGIN');},commit(){db.exec('COMMIT');},rollBack(){db.exec('ROLLBACK');}};
 class Adapter{
  async identify(uri){env.identifies.push(uri);if(!env.present.has(uri))throw Error('absent');return structuredClone(env.present.get(uri));}
  async members(target){return (env.members.get(target)||[]).map(uri=>structuredClone(env.present.get(uri)));}
  async copy(source,target){env.native.push(['copy',source,target]);if(env.unknownCopy)throw Error('native copy outcome unknown');const ref='media:new-copy-'+env.native.length;env.present.set(ref,{...identity(ref),name:env.present.get(source).name});env.members.set(target,[...(env.members.get(target)||[]),ref]);}
  async exists(uri){return env.present.has(uri);}
  async trash(uri){throw Error('direct trash must not be used');}
 }
 const overrides=new Map([
 ['@kit.ArkData',{relationalStore:{SecurityLevel:{S1:1},async getRdbStore(){return store;}}}],
 ['@kit.MediaLibraryKit',{photoAccessHelper:{MediaAssetChangeRequest:{async deleteAssets(_context,refs){env.native.push(['trash',...refs]);if(env.cancel)throw Object.assign(Error('cancelled'),{code:201});refs.forEach(uri=>env.present.delete(uri));}}}}],
 [src('platform/media/VerifiedAlbumMoveAdapter'),{VerifiedAlbumMoveAdapter:Adapter}],
 [src('platform/permissions/PermissionProbe'),{PermissionProbe:class{constructor(){env.permissions++;}canWriteLibrary(){return true;}canReadLibrary(){return true;}}}],
 [src('services/operations/AlbumClassificationTargets'),{AlbumClassificationTargets:class{async load(){return{revision:1,categories:[{id:'C',album:{kind:'album',reference:'album:target',name:'Target'}}]};}}}]
 ]);
 const load=createLoader(overrides);const {MoveJournal}=load(src('data/repositories/MoveJournal'));const {VerifiedMoveService}=load(src('services/operations/VerifiedMoveService'));
 const journal=new MoveJournal({});const service=new VerifiedMoveService({});
 function record(id,kind='album',phase='awaiting_trash'){const source=identity('media:'+id),copy=identity('media:copy-'+id);env.present.set(source.uri,source);env.present.set(copy.uri,copy);return{id,target:kind==='album'?'album:legacy':'file://docs/legacy',targetKind:kind,phase,source,copy,destinations:[]};}
 function snapshot(){return db.prepare('SELECT id,phase,payload FROM move_journal ORDER BY id').all();}
 return{db,env,identity,record,journal,service,Service:VerifiedMoveService,snapshot,load};
}
let passed=0;async function test(n,f){await f();passed++;console.log('PASS '+n);}
async function main(){
 await test('retired directory dual-target and document-source calls fail before native access or persistence',async()=>{
  for(const [kind,source]of [['directory','media:new'],['both','media:new'],['album','file://docs/old/photo.jpg']]){const{db,env,service}=fixture();try{await assert.rejects(service.move(source,'C',kind));assert.deepEqual(env.native,[]);assert.equal(env.permissions,0);assert.deepEqual(env.identifies,[]);assert.equal(db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table'").get().n,0);}finally{db.close();}}
 });
 await test('every legacy phase survives service refresh and finish byte-for-byte without permissions or media calls',async()=>{
  const{db,env,record,journal,service,snapshot}=fixture();try{
   for(const kind of ['directory','album'])for(const phase of ['copying','copied','awaiting_trash','batch_trashing','trashing','complete','retained'])await journal.save(record(kind+'-'+phase,kind,phase));
   const dual=record('dual');dual.destinations=[{kind:'album',target:dual.target,copy:dual.copy},{kind:'directory',target:'file://docs/old',copy:{uri:'file://docs/old/copy.jpg'}}];await journal.save(dual);
   const before=snapshot();assert.deepEqual(await service.staged(),[]);await service.classified();await service.finish(false);await service.finish(true);assert.deepEqual(snapshot(),before);assert.deepEqual(env.native,[]);assert.equal(env.permissions,0);assert.deepEqual(env.identifies,[]);
  }finally{db.close();}
 });
 await test('new album classification verifies and finishes only its current source while all legacy records remain unchanged',async()=>{
  const{db,env,record,journal,service,snapshot}=fixture();try{
   const legacy=record('old-directory','directory','batch_trashing');await journal.save(legacy);const old=snapshot()[0];env.present.set('media:new',fixtureIdentity('media:new'));
   const result=await service.move('media:new','C','album',false);assert.equal(result.phase,'awaiting_trash');assert.equal(env.present.has('media:new'),true);assert.equal((await service.staged()).length,1);
   await service.finish(false);assert.equal(env.present.has('media:new'),false);assert.equal((await journal.active('media:new')),undefined);assert.deepEqual(snapshot().find(r=>r.id===legacy.id),old);assert.deepEqual(env.native.map(c=>c[0]),['copy','trash']);assert.deepEqual(env.native[1],['trash','media:new']);
  }finally{db.close();}
 });
 await test('keep setting and protected source never recycle a new album original',async()=>{
  for(const mode of ['keep','protected']){const{db,env,service,identity}=fixture();try{env.present.set('media:new',identity('media:new'));const r=await service.move('media:new','C','album',mode==='keep');await service.finish(false,mode==='protected'?['media:new']:[]);assert.equal(env.present.has('media:new'),true);assert.equal(env.native.filter(c=>c[0]==='trash').length,0);assert.equal(r.phase,mode==='keep'?'retained':'awaiting_trash');}finally{db.close();}}
 });
 await test('restarting a service does not resume a previously staged album operation',async()=>{
  const{db,env,service,Service,identity,snapshot}=fixture();try{env.present.set('media:new',identity('media:new'));await service.move('media:new','C','album');const before=snapshot();const nativeBefore=structuredClone(env.native);await new Service({}).finish(false);assert.deepEqual(snapshot(),before);assert.deepEqual(env.native,nativeBefore);assert.equal(env.present.has('media:new'),true);}finally{db.close();}
 });
 await test('cancelling current-round album recycling keeps source and supports explicit retry',async()=>{
  const{db,env,service,identity,journal}=fixture();try{env.present.set('media:new',identity('media:new'));await service.move('media:new','C','album');env.cancel=true;await service.finish(false);assert.equal((await journal.active('media:new')).phase,'awaiting_trash');assert.equal(env.present.has('media:new'),true);env.cancel=false;await service.finish(false);assert.equal(env.present.has('media:new'),false);}finally{db.close();}
 });
 await test('an old in-flight source cannot be reclassified and its durable intent is not cancelled',async()=>{
  const{db,env,record,journal,service,snapshot}=fixture();try{await journal.save(record('same','directory','copying'));const before=snapshot();await assert.rejects(service.move('media:same','C','album'));assert.deepEqual(snapshot(),before);assert.deepEqual(env.native,[]);}finally{db.close();}
 });
 await test('a pre-copy validation failure permits a later explicit retry without leaving an active record',async()=>{
  const {db,env,service,identity,journal}=fixture();
  try{
   const source=identity('media:new');env.present.set(source.uri,source);
   env.present.set('media:conflict',{...identity('media:conflict'),name:source.name});
   env.members.set('album:target',['media:conflict']);
   await assert.rejects(service.move(source.uri,'C','album'),/同名/);
   assert.equal(await journal.active(source.uri),undefined);assert.deepEqual(env.native,[]);
   env.members.set('album:target',[]);
   assert.equal((await service.move(source.uri,'C','album',true)).phase,'retained');
   assert.equal(env.native.length,1);
  }finally{db.close();}
 });
 await test('unknown copy keeps a durable journal and explicit retry never sends another native copy',async()=>{
  const {db,env,service,identity,journal}=fixture();
  try{
   env.present.set('media:new',identity('media:new'));env.unknownCopy=true;
   await assert.rejects(service.move('media:new','C','album'),/暂不重复复制/);
   assert.equal((await journal.active('media:new')).phase,'copying');
   env.unknownCopy=false;
   await assert.rejects(service.move('media:new','C','album'),/暂时无法继续整理/);
   await service.finish(false);
   assert.deepEqual(env.native,[['copy','media:new','album:target']]);
   assert.equal(env.present.has('media:new'),true);
  }finally{db.close();}
 });
 await test('removed directory routes and native write adapters cannot be loaded from the application',()=>{
  const pages=JSON.parse(fs.readFileSync('entry/src/main/resources/base/profile/main_pages.json','utf8')).src;for(const name of ['FolderSource','DirectoryResearch'])assert.ok(!pages.includes('pages/'+name));
  for(const name of ['pages/FolderSource','pages/DirectoryResearch','platform/media/VerifiedDownloadMoveAdapter','platform/files/ManagedDownloadFolders','platform/files/DocumentExperimentAdapter','platform/files/FileProbe','domain/usecases/ExecuteBoundMove'])assert.equal(fs.existsSync(src(name)),false);
 });
 await test('public directory transfer remains retired; only the private music importer may copy file descriptors',()=>{
  function scan(dir){for(const ent of fs.readdirSync(dir,{withFileTypes:true})){const name=path.join(dir,ent.name);if(ent.isDirectory())scan(name);else if(ent.name.endsWith('.ets')){
   const text=fs.readFileSync(name,'utf8');assert.doesNotMatch(text,/DocumentViewPicker|DocumentSelectMode|DocumentSaveOptions|fileIo\.(mkdir|moveFile)\(/);
   // Audio import is separately exercised in test-slideshow with Picker and private-destination substitutes.
   if(name!==src('platform/files/SlideshowMusicFiles'))assert.doesNotMatch(text,/fileIo\.copyFile\(/);
  }}}
  scan(path.resolve(__dirname,'../entry/src/main/ets'));
 });
 console.log(`${passed}/${passed} album-only safety checks passed with real host SQLite and explicit native substitutes; no device data touched.`);
}
function fixtureIdentity(uri){return{uri,name:uri.replace(/[:/]/g,'_')+'.jpg',hash:'full-content-hash',bytes:4096,taken:123,retainOriginal:false};}
main().catch(e=>{console.error(e);process.exitCode=1;});
