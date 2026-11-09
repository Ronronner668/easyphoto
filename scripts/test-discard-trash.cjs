const assert=require('node:assert/strict');
const path=require('node:path');
const {DatabaseSync}=require('node:sqlite');
const {createLoader}=require('./ets-test-runtime.cjs');
const src=name=>path.resolve(__dirname,'../entry/src/main/ets',name+'.ets');
function fixture(){
  const db=new DatabaseSync(':memory:');const env={marks:['media:A','media:B'].map(reference=>({reference,name:reference})),present:new Set(['media:A','media:B']),calls:[],error:0,failReadback:false};
  const store={async executeSql(sql,args=[]){db.prepare(sql).run(...args);},async querySql(sql,args=[]){const rows=db.prepare(sql).all(...args);return {goToFirstRow:()=>rows.length>0,getString:()=>Object.values(rows[0])[0],close(){}};}};
  class Adapter {async identify(uri){return {uri};}async exists(uri){if(env.failReadback&&env.calls.length){env.failReadback=false;throw Error('readback unavailable');}return env.present.has(uri);}async trash(uri){env.calls.push([uri]);env.present.delete(uri);}}
  const overrides=new Map([
    ['@kit.ArkData',{dataSharePredicates:{DataSharePredicates:class{equalTo(key,ref){this.ref=ref;return this;}}},relationalStore:{SecurityLevel:{S1:1},async getRdbStore(){return store;}}}],
    ['@kit.MediaLibraryKit',{photoAccessHelper:{PhotoKeys:{URI:'uri',PHOTO_TYPE:'media_type'},PhotoType:{IMAGE:1},getPhotoAccessHelper(){return{async getAssets(options){const ref=options.predicates.ref;if(ref===undefined){const refs=[...env.present];return{getCount:()=>refs.length,async getObjectByPosition(i){return{uri:refs[i]};},close(){}};}return{getCount:()=>env.present.has(ref)?1:0,async getFirstObject(){return{uri:env.changed===ref?'media:replacement':ref,get:()=>1};},close(){}};},async release(){}};},MediaAssetChangeRequest:{async deleteAssets(context,uris){env.calls.push(uris);const code=env.batchErrors?.[env.calls.length-1]||env.error;if(code)throw Object.assign(Error('native'),{code});uris.forEach(uri=>env.present.delete(uri));}}}}],
    [src('platform/media/VerifiedAlbumMoveAdapter'),{VerifiedAlbumMoveAdapter:Adapter}],
    [src('platform/permissions/PermissionProbe'),{PermissionProbe:class{canReadLibrary(){return true;}canWriteLibrary(){return true;}}}],
    [src('data/repositories/DiscardQueueRepository'),{DiscardQueueRepository:class{async load(){return env.marks;}async removeMissing(mark){env.marks=env.marks.filter(item=>item.reference!==mark.reference); }async unmark(uri){env.marks=env.marks.filter(mark=>mark.reference!==uri);}}}]
  ]);
  const {DiscardTrashService}=createLoader(overrides)(src('services/operations/DiscardTrashService'));
  return {db,env,service:new DiscardTrashService({})};
}
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
async function main(){
  await test('251 marks recycle in verified batches and cancellation or uncertainty stops later batches',async()=>{
    for(const error of [0,201,999]){
      const {db,env,service}=fixture();
      try{
        const refs=Array.from({length:251},(_,i)=>'media:sample-'+i);
        env.marks=refs.map(reference=>({reference,name:'Sample'}));
        env.present=new Set(refs);
        env.batchErrors=[0,error];
        if(error===999) await assert.rejects(service.trash(refs),/尚未确认/);
        else await service.trash(refs);
        assert.deepEqual(env.calls.map(batch=>batch.length),error?[100,100]:[100,100,51]);
        assert.equal(service.confirmedRemoved.length,error?100:251);
        assert.deepEqual(env.marks.map(mark=>mark.reference),error?refs.slice(100):[]);
        if(error===999){
          await assert.rejects(service.trash(refs.slice(100)),/未重复发送/);
          assert.equal(env.calls.length,2);
        }
      }finally{db.close();}
    }
  });
  await test('report receipts exclude cancelled and already absent photos and include only confirmed current trash',async()=>{
    for(const mode of ['success','cancelled','absent']){const {db,env,service}=fixture();try{
      if(mode==='cancelled')env.error=201;if(mode==='absent')env.present.delete('media:A');
      await service.trash(['media:A']);assert.equal(service.confirmedRemoved.length,mode==='success'?1:0);
      if(mode==='success')assert.equal(service.confirmedRemoved[0].uri,'media:A');
    }finally{db.close();}}
  });
  await test('individual delete affects only selected marked identity',async()=>{const {db,env,service}=fixture();try{await service.trash(['media:A']);assert.deepEqual(env.calls,[['media:A']]);assert.deepEqual(env.marks.map(x=>x.reference),['media:B']);assert.equal(env.present.has('media:B'),true);}finally{db.close();}});
  await test('already recycled marked photo is cleared without another native request',async()=>{const {db,env,service}=fixture();try{env.present.delete('media:A');await service.trash(['media:A']);assert.equal(env.calls.length,0);assert.equal(env.marks.length,1);}finally{db.close();}});
  await test('batch delete uses one request and clears only observed absent originals',async()=>{const {db,env,service}=fixture();try{await service.trash(['media:A','media:B']);assert.equal(env.calls.length,1);assert.equal(env.marks.length,0);}finally{db.close();}});
  await test('system cancellation preserves marks and permits explicit later retry',async()=>{const {db,env,service}=fixture();try{env.error=201;await service.trash(['media:A']);assert.equal(env.marks.length,2);assert.equal(env.present.size,2);env.error=0;await service.trash(['media:A']);assert.equal(env.calls.length,2);}finally{db.close();}});
  await test('unknown deletion result never blindly replays native request',async()=>{const {db,env,service}=fixture();try{env.error=999;await assert.rejects(service.trash(['media:A']));await assert.rejects(service.trash(['media:A']));assert.equal(env.calls.length,1);assert.equal(env.marks.length,2);}finally{db.close();}});
  await test('failed readback reconciles absent references later without repeating deletion',async()=>{const {db,env,service}=fixture();try{env.failReadback=true;await assert.rejects(service.trash(['media:A']));assert.equal(env.calls.length,1);await service.trash(['media:A']);assert.equal(env.calls.length,1);assert.equal(env.marks.length,1);}finally{db.close();}});
  await test('legacy document requests and empty requests never create or alter recycling journals',async()=>{
    const{db,env,service}=fixture();try{const marks=structuredClone(env.marks);await assert.rejects(service.trash(['file://docs/legacy/photo.jpg']));await service.trash([]);assert.deepEqual(env.marks,marks);assert.deepEqual(env.calls,[]);assert.equal(db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name='request'").get().n,0);}finally{db.close();}
  });
  await test('old mixed document request remains byte-identical without unmarking or replaying any source',async()=>{
    const{db,env,service}=fixture();try{db.exec('CREATE TABLE request (id INTEGER PRIMARY KEY,payload TEXT NOT NULL)');const payload=JSON.stringify(['media:A','file://docs/legacy/photo.jpg']);db.prepare('INSERT INTO request VALUES(1,?)').run(payload);const marks=structuredClone(env.marks);await assert.rejects(service.trash(['media:B']),/历史文件/);assert.equal(db.prepare('SELECT payload FROM request WHERE id=1').get().payload,payload);assert.deepEqual(env.marks,marks);assert.deepEqual(env.calls,[]);}finally{db.close();}
  });
  await test('changed reference is skipped while other valid marks recycle without using replacement URI',async()=>{const{db,env,service}=fixture();try{env.changed='media:A';const message=await service.trash(['media:A','media:B']);assert.deepEqual(env.calls,[['media:B']]);assert.deepEqual(env.marks.map(m=>m.reference),['media:A']);assert.match(message,/跳过 1/);}finally{db.close();}});
  console.log(`${passed}/${passed} marked-photo trash checks passed against real host SQLite with explicit native test doubles.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
