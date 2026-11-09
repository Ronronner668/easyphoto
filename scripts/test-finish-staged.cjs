const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const {finishStagedMoves}=createLoader()(path.resolve(__dirname,'../entry/src/main/ets/domain/usecases/FinishStagedMoves.ets'));
function fixture(){
  const identity=uri=>({uri,name:uri+'.png',hash:'hash',bytes:100,taken:12});
  const records=['one','two'].map(id=>({id,target:'album',targetKind:'album',phase:'awaiting_trash',source:identity('media:'+id),copy:identity('copy:'+id),destinations:[]}));
  const env={calls:[],store:new Map(records.map(r=>[r.id,structuredClone(r)])),exists:new Set(records.map(r=>r.source.uri)),hash:'hash',nativeError:0,failBatch:false};
  const adapter={async identify(uri){const result=identity(uri);result.hash=uri.startsWith('copy:')?env.hash:env.sourceHash||'hash';return result;},async members(){return records.map(r=>identity(r.copy.uri));},async exists(uri){return env.exists.has(uri);},async trash(uri){env.calls.push('doc-trash:'+uri);env.exists.delete(uri);}};
  const port={source:()=>adapter,target:()=>adapter,isDocument:uri=>uri.startsWith('doc:'),async trashGallery(uris){env.calls.push(['gallery-trash',...uris]);if(env.nativeError)throw Object.assign(Error('native'),{code:env.nativeError});uris.forEach(uri=>env.exists.delete(uri));}};
  const journal={async active(uri){return [...env.store.values()].find(r=>r.source.uri===uri&&!['complete','cancelled'].includes(r.phase));},async save(record){env.store.set(record.id,structuredClone(record));},async saveBatch(value){env.calls.push('durable-batch');if(env.failBatch)throw Error('database');value.forEach(record=>env.store.set(record.id,structuredClone(record)));}};
  const run=(keep=false,confirmed)=>finishStagedMoves([...env.store.values()].filter(r=>!['complete','retained'].includes(r.phase)).map(r=>structuredClone(r)),port,journal,keep,confirmed);
  return {env,records,port,journal,run};
}
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
async function main(){
  await test('report receipt counts only durable confirmed native recycling, never retained cancelled or previously absent sources',async()=>{
    for(const mode of ['success','retained','cancelled','absent']){const {env,run}=fixture();const receipts=[];
      if(mode==='cancelled')env.nativeError=201;if(mode==='absent')env.exists.clear();
      await run(mode==='retained',identity=>receipts.push(identity));assert.equal(receipts.length,mode==='success'?2:0);
      if(mode==='success')assert.equal(receipts.reduce((sum,i)=>sum+i.bytes,0),200);
    }
  });
  await test('current keep setting retains album queue without native deletion',async()=>{
    const {env,run}=fixture();
    assert.match(await run(true),/保留/);assert.equal(env.exists.size,2);assert.deepEqual(env.calls,[]);
    assert.ok([...env.store.values()].every(r=>r.phase==='retained'&&r.keepOriginal));await run(false);assert.deepEqual(env.calls,[]);
  });
  await test('per-record keep intent remains protected when current setting is off',async()=>{
    const {env,run}=fixture();env.store.get('one').keepOriginal=true;await run(false);
    assert.equal(env.store.get('one').phase,'retained');assert.equal(env.exists.has('media:one'),true);
    assert.deepEqual(env.calls.find(Array.isArray),['gallery-trash','media:two']);
  });
  await test('unknown prior deletion is not relabeled retained or replayed after keep setting changes',async()=>{
    const {env,run}=fixture();env.store.get('one').phase='batch_trashing';await assert.rejects(run(true));
    assert.equal(env.store.get('one').phase,'batch_trashing');assert.equal(env.calls.length,0);assert.equal(env.exists.size,2);
  });
  await test('keep setting cannot claim original retained after it is already absent',async()=>{
    const {env,run}=fixture();env.exists.clear();await run(true);assert.ok([...env.store.values()].every(r=>r.phase==='complete'));assert.equal(env.calls.length,0);
  });
  await test('changed destination still blocks retention completion and preserves queue',async()=>{
    const {env,run}=fixture();env.hash='changed';await assert.rejects(run(true));assert.ok([...env.store.values()].every(r=>r.phase==='awaiting_trash'));assert.equal(env.calls.length,0);
  });
  await test('compound photo classification keeps original and companions out of native trash',async()=>{const {env,run}=fixture();env.store.get('one').source.retainOriginal=true;assert.match(await run(),/保留/);assert.equal(env.store.get('one').phase,'retained');assert.equal(env.exists.has('media:one'),true);assert.deepEqual(env.calls.find(Array.isArray),['gallery-trash','media:two']);});
  await test('two originals use exactly one native gallery request after durable intent',async()=>{const {env,run}=fixture();await run();assert.equal(env.calls.filter(x=>Array.isArray(x)).length,1);assert.deepEqual(env.calls[1],['gallery-trash','media:one','media:two']);assert.equal(env.exists.size,0);assert.ok([...env.store.values()].every(r=>r.phase==='complete'));});
  await test('changed target blocks entire batch before native deletion',async()=>{const {env,run}=fixture();env.hash='modified';await assert.rejects(run());assert.equal(env.calls.length,0);assert.equal(env.exists.size,2);});
  await test('changed original blocks entire batch',async()=>{const {env,run}=fixture();env.sourceHash='modified';await assert.rejects(run());assert.equal(env.calls.length,0);});
  await test('batch journal failure prevents every native request',async()=>{const {env,run}=fixture();env.failBatch=true;await assert.rejects(run());assert.equal(env.calls.filter(x=>Array.isArray(x)).length,0);assert.ok([...env.store.values()].every(r=>r.phase==='awaiting_trash'));});
  await test('cancel keeps all originals and permits only a later explicit finish',async()=>{const {env,run}=fixture();env.nativeError=201;assert.match(await run(),/取消/);assert.equal(env.exists.size,2);assert.ok([...env.store.values()].every(r=>r.phase==='awaiting_trash'));env.nativeError=0;await run();assert.equal(env.calls.filter(x=>Array.isArray(x)).length,2);});
  await test('unknown native outcome cannot be blindly resubmitted',async()=>{const {env,run}=fixture();env.nativeError=13900005;await run();assert.ok([...env.store.values()].every(r=>r.phase==='batch_trashing'));await assert.rejects(run());assert.equal(env.calls.filter(x=>Array.isArray(x)).length,1);});
  await test('interrupted completion with originals absent only observes evidence and never repeats deletion',async()=>{const {env,run}=fixture();for(const r of env.store.values())r.phase='batch_trashing';env.exists.clear();await run();assert.equal(env.calls.length,0);assert.ok([...env.store.values()].every(r=>r.phase==='complete'));});
  await test('dual binding requires second destination still complete before final batch',async()=>{const {env,port,run}=fixture();const r=env.store.get('one');r.target='A';r.destinations=[{target:'A',kind:'album',copy:r.copy},{target:'D',kind:'directory',copy:{uri:'doc:copy',hash:'hash',bytes:100}}];port.target=kind=>kind==='directory'?{async identify(){throw Error('target revoked');}}:port.source();await assert.rejects(run());assert.equal(env.calls.length,0);});
  await test('duplicate original identities never reach native boundary',async()=>{const {env,records,port,journal}=fixture();await assert.rejects(finishStagedMoves([records[0],records[0]],port,journal));assert.equal(env.calls.length,0);});
  await test('gallery cancellation never attempts document source trash',async()=>{const {env,records,port,run}=fixture();const r=env.store.get('two');r.source.uri='doc:two';env.exists.delete('media:two');env.exists.add('doc:two');env.nativeError=201;await run();assert.ok(!env.calls.some(x=>typeof x==='string'&&x.startsWith('doc-trash')));assert.equal(env.exists.size,2);});
  console.log(`${passed}/${passed} batch finalization checks passed with explicit native test doubles.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
