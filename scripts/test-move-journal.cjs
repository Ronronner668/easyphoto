const assert=require('node:assert/strict');
const path=require('node:path');
const {DatabaseSync}=require('node:sqlite');
const {createLoader}=require('./ets-test-runtime.cjs');
const db=new DatabaseSync(':memory:');
const rows=items=>{let index=-1;return {goToFirstRow(){index=0;return !!items.length;},goToNextRow(){return ++index<items.length;},getString(column){return Object.values(items[index])[column];},getLong(column){return Number(Object.values(items[index])[column]);},close(){}};};
const store={beginTransaction(){db.exec('BEGIN');},commit(){db.exec('COMMIT');},rollBack(){db.exec('ROLLBACK');},async executeSql(sql,args=[]){db.prepare(sql).run(...args);},async querySql(sql,args=[]){return rows(db.prepare(sql).all(...args));}};
const load=createLoader(new Map([['@kit.ArkData',{relationalStore:{SecurityLevel:{S1:1},async getRdbStore(){return store;}}}]]));
const {MoveJournal}=load(path.resolve(__dirname,'../entry/src/main/ets/data/repositories/MoveJournal.ets'));
const journal=new MoveJournal({});
const fixture=(id,phase='complete')=>({id,phase,targetKind:'directory',target:'file://docs/owned/拾光整理/A',source:{uri:'media:'+id,taken:123,hash:'hash',bytes:100},copy:{uri:'file://docs/owned/拾光整理/A/item-'+id+'/照片%23.png',hash:'hash',bytes:100,taken:0}});
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
async function main(){
  await test('old organized identities beyond the UI history cap remain excluded after reopening repository',async()=>{
    const old=fixture('filter-old');await journal.save(old);
    db.exec('BEGIN');for(let i=0;i<3010;i++){const r=fixture('new-filter-'+i);db.prepare('INSERT INTO move_journal(id,phase,payload) VALUES(?,?,?)').run(r.id,r.phase,JSON.stringify(r));}db.exec('COMMIT');
    assert.equal((await new MoveJournal({}).excludedReferences([old.source.uri])).has(old.source.uri),true);
    db.prepare("DELETE FROM move_journal WHERE id=? OR id LIKE 'new-filter-%'").run(old.id);
  });
  await test('cross-round filtering reads completed retained and staged source and all target identities exactly',async()=>{
    const complete=fixture('filter-complete'),retained=fixture('filter-retained','retained'),pending=fixture('filter-pending','awaiting_trash');
    retained.destinations=[{kind:'album',target:'album',copy:{uri:'other-copy'}},{kind:'directory',target:retained.target,copy:retained.copy}];
    await journal.save(complete);await journal.save(retained);await journal.save(pending);
    const refs=[complete.source.uri,complete.copy.uri,retained.source.uri,'other-copy',pending.source.uri,'media:filter','untouched'];
    assert.deepEqual([...(await journal.excludedReferences(refs))].sort(),refs.slice(0,5).sort());
    for(const record of [complete,retained,pending])db.prepare('DELETE FROM move_journal WHERE id=?').run(record.id);
  });
  await test('completion count includes completed rows only',async()=>{await journal.save(fixture('1'));await journal.save(fixture('2','cancelled'));assert.equal(await journal.completedCount(),1);});
  await test('recorded time comes from original snapshot only for exact completed target and digest',async()=>{const r=fixture('1');assert.equal(await journal.recordedTime(r.copy.uri,'hash'),123);assert.equal(await journal.recordedTime(r.copy.uri+'-sibling','hash'),0);assert.equal(await journal.recordedTime(r.copy.uri,'changed'),0);});
  await test('cancelled copy is never treated as a verified completed export',async()=>assert.equal(await journal.recordedTime(fixture('2').copy.uri,'hash'),0));
  await test('forwarded document retains explicitly recorded time without fabricating native taken',async()=>{const r=fixture('3');r.source.taken=0;r.source.recordedTaken=123;await journal.save(r);assert.equal(await journal.recordedTime(r.copy.uri,'hash'),123);assert.equal((await journal.latestComplete()).source.taken,0);});
  await test('pending durable intent remains available across repository instances',async()=>{await journal.save(fixture('4','trashing'));assert.equal((await new MoveJournal({}).active()).id,'4');assert.equal(await journal.completedCount(),2);});
  await test('updating same operation does not double count completion',async()=>{await journal.save(fixture('4'));await journal.save(fixture('4'));assert.equal(await journal.completedCount(),3);assert.equal(await journal.active(),undefined);});
  await test('legacy album completion has no document time claim',async()=>{const r=fixture('5');delete r.targetKind;await journal.save(r);assert.equal(await journal.recordedTime(r.copy.uri,'hash'),0);});
  await test('dual binding document inherits original recorded time from its own exact target identity',async()=>{const r=fixture('6');r.targetKind='album';r.destinations=[{kind:'album',target:'A',copy:{uri:'media:new',hash:'hash'}},{kind:'directory',target:'D',copy:r.copy}];r.copy={uri:'media:new',hash:'hash'};await journal.save(r);assert.equal(await journal.recordedTime(r.destinations[1].copy.uri,'hash'),123);});
  await test('pending lookup isolates exact source rather than blocking unrelated photos or URI prefixes',async()=>{await journal.save(fixture('70','copying'));await journal.save(fixture('71','copying'));assert.equal((await journal.active('media:71')).id,'71');assert.equal(await journal.active('media:7'),undefined);assert.equal(await journal.active('media:none'),undefined);});
  await test('classified queue survives new repository instance without claiming completed move',async()=>{await journal.save(fixture('80','awaiting_trash'));await journal.save(fixture('81','awaiting_trash'));const values=await new MoveJournal({}).staged();assert.deepEqual(values.map(r=>r.id),['80','81']);});
  await test('all batch intents commit together and a failed final commit rolls back every row',async()=>{
    const pending=await journal.staged();pending.forEach(r=>r.phase='batch_trashing');await journal.saveBatch(pending);
    db.exec("CREATE TRIGGER reject_second BEFORE INSERT ON move_journal WHEN NEW.id='81' AND NEW.phase='complete' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    pending.forEach(r=>r.phase='complete');await assert.rejects(journal.saveBatch(pending));assert.ok((await journal.staged()).every(r=>r.phase==='batch_trashing'));
    db.exec('DROP TRIGGER reject_second');
  });
  await test('ready document copy can show original recorded time before source is recycled',async()=>{const record=fixture('82','awaiting_trash');await journal.save(record);assert.equal(await journal.recordedTime(record.copy.uri,'hash'),123);});
  console.log(`${passed}/${passed} move journal checks passed against real host SQLite; no device database changed.`);
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>db.close());
