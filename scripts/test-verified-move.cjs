const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const src=file=>path.resolve(__dirname,'../entry/src/main/ets',file+'.ets');
const load=createLoader();
const {AlreadyInTargetError}=load(src('domain/models/Experiment'));
const {executeVerifiedMove,reconcileVerifiedMove}=load(src('domain/usecases/ExecuteVerifiedMove'));
function fixture(){
  const env={calls:[],members:[],active:undefined,sourceExists:true,failPhase:'',binding:true,copyHash:'hash',copyTaken:10};
  const identity=uri=>({uri,name:'sample.png',bytes:100,taken:10,hash:'hash'});
  const port={
    async identify(uri){env.calls.push('read:'+uri);const value=identity(uri);if(uri==='copy'){value.hash=env.copyHash;value.taken=env.copyTaken;}if(uri==='source'&&env.changedSource)value.hash='changed';return value;},
    async members(){return structuredClone(env.members);},
    async copy(){env.calls.push('copy');if(env.failCopy)throw Error('native unknown');env.members.push(identity('copy'));if(env.extra)env.members.push(identity('external'));},
    async trash(){env.calls.push('trash');if(env.failTrash)throw Error('cancelled');env.sourceExists=!!env.cancelTrash;},
    async exists(){return env.sourceExists;}
  };
  const journal={async active(){return env.active;},async save(record){env.calls.push('save:'+record.phase);if(record.phase===env.failPhase)throw Error('journal');env.active=structuredClone(record);if(record.phase==='copied'&&env.changeAfterCopy)env.changedSource=true;if(record.phase==='complete')env.active=undefined;}};
  const record={id:'1',categoryId:'C',revision:1,target:'album',source:{uri:'source'},phase:'copying',before:[]};
  return {env,port,journal,record,run:()=>executeVerifiedMove(record,port,journal,async()=>env.binding,false)};
}
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
async function main(){
  await test('explicit copy policy retains source and never enters recycle queue',async()=>{const {env,record,run}=fixture();record.keepOriginal=true;const result=await run();assert.equal(result.phase,'retained');assert.equal(env.sourceExists,true);assert.ok(!env.calls.includes('trash'));});
  await test('deferred classification saves a durable ready record without any source trash',async()=>{
    const {env,record,port,journal}=fixture();await executeVerifiedMove(record,port,journal,async()=>true,true);
    assert.equal(record.phase,'awaiting_trash');assert.equal(env.active.phase,'awaiting_trash');assert.equal(env.sourceExists,true);assert.ok(!env.calls.includes('trash'));
  });
  await test('unknown destination kind is rejected before native calls',async()=>{
    const {env,record,run}=fixture();record.targetKind='unknown';await assert.rejects(run());assert.equal(env.calls.length,0);
  });
  await test('copy is durably recorded verified then original is trashed and completed',async()=>{const {env,run}=fixture();const result=await run();assert.equal(result.phase,'complete');assert.equal(result.copy.uri,'copy');assert.ok(env.calls.indexOf('save:copying')<env.calls.indexOf('copy'));assert.ok(env.calls.indexOf('save:trashing')<env.calls.indexOf('trash'));assert.equal(env.sourceExists,false);});
  await test('existing unfinished journal blocks all native mutations',async()=>{const {env,run}=fixture();env.active={id:'old'};await assert.rejects(run());assert.equal(env.calls.length,0);});
  await test('stale binding is rejected before copying',async()=>{const {env,run}=fixture();env.binding=false;await assert.rejects(run());assert.equal(env.calls.length,0);});
  await test('same target membership does not duplicate source',async()=>{const {env,run}=fixture();env.members=[{uri:'source',name:'sample.png'}];await assert.rejects(run(),AlreadyInTargetError);assert.ok(!env.calls.includes('copy'));assert.ok(!env.calls.includes('trash'));assert.equal(env.active,undefined);});
  await test('name conflict never overwrites target',async()=>{const {env,run}=fixture();env.members=[{uri:'other',name:'SAMPLE.PNG'}];await assert.rejects(run());assert.ok(!env.calls.includes('copy'));});
  await test('journal failure prevents initial native copy',async()=>{const {env,run}=fixture();env.failPhase='copying';await assert.rejects(run());assert.ok(!env.calls.includes('copy'));});
  await test('unknown native copy result remains pending and cannot be replayed',async()=>{const {env,run}=fixture();env.failCopy=true;await assert.rejects(run());await assert.rejects(run());assert.equal(env.calls.filter(x=>x==='copy').length,1);assert.equal(env.active.phase,'copying');});
  await test('concurrent target addition blocks source trash',async()=>{const {env,run}=fixture();env.extra=true;await assert.rejects(run());assert.ok(!env.calls.includes('trash'));});
  await test('different copy bytes or capture time block source trash',async()=>{for(const key of ['copyHash','copyTaken']){const {env,run}=fixture();env[key]=key==='copyHash'?'changed':99;await assert.rejects(run());assert.ok(!env.calls.includes('trash'));}});
  await test('changed source after copy cannot be sent to trash',async()=>{const {env,run}=fixture();env.changeAfterCopy=true;await assert.rejects(run());assert.ok(!env.calls.includes('trash'));});
  await test('failed pre-trash journal leaves original intact',async()=>{const {env,run}=fixture();env.failPhase='trashing';await assert.rejects(run());assert.ok(!env.calls.includes('trash'));assert.equal(env.active.phase,'copied');});
  await test('system cancellation retains pending record and cannot repeat trash',async()=>{const {env,run}=fixture();env.cancelTrash=true;await assert.rejects(run());await assert.rejects(run());assert.equal(env.calls.filter(x=>x==='trash').length,1);assert.equal(env.active.phase,'trashing');});
  await test('post-action journal failure never reports completed move',async()=>{const {env,run}=fixture();env.failPhase='complete';await assert.rejects(run());assert.equal(env.active.phase,'trashing');assert.equal(env.sourceExists,false);});
  await test('explicit review keeps unchanged original and never repeats native copy or trash',async()=>{
    const {env,run,port,journal}=fixture();env.cancelTrash=true;await assert.rejects(run());
    const before=env.calls.filter(x=>x==='copy'||x==='trash').length;
    await reconcileVerifiedMove(port,journal);assert.equal(env.active.phase,'cancelled');
    assert.equal(env.calls.filter(x=>x==='copy'||x==='trash').length,before);
  });
  await test('review cannot release record when original was modified externally',async()=>{
    const {env,run,port,journal}=fixture();env.cancelTrash=true;await assert.rejects(run());env.changedSource=true;
    await assert.rejects(reconcileVerifiedMove(port,journal));assert.equal(env.active.phase,'trashing');
  });
  await test('review completes an interrupted final save only from verified absent original and intact copy',async()=>{
    const {env,run,port,journal}=fixture();env.failPhase='complete';await assert.rejects(run());env.failPhase='';
    await reconcileVerifiedMove(port,journal);assert.equal(env.active,undefined);
    assert.equal(env.calls.filter(x=>x==='trash').length,1);
  });
  console.log(`${passed}/${passed} verified move state-machine checks passed with explicit native test doubles.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
