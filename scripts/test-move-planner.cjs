const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const src = file => path.resolve(__dirname, '../entry/src/main/ets', file + '.ets');
const load = createLoader();
const { Category, TargetKind: K, TargetRef } = load(src('domain/models/Category'));
const { MoveSource, TargetObservation, ConflictPolicy: P, PlanItemState: S } = load(src('domain/models/MovePlan'));
const { planMoves } = load(src('domain/usecases/MovePlanner'));
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS ' + name); }
function category() {
  const value = new Category('C', '旅游');
  value.album = new TargetRef(K.Album, 'opaque:A?token=unchanged', 'A');
  value.directory = new TargetRef(K.Directory, 'opaque:D?token=unchanged', 'D');
  return value;
}
function source(id='1',name='photo.jpg') { return new MoveSource(id, 'opaque:photo-'+id, name, true); }
function observation(names=[]) {
  const value = new TargetObservation(); value.available=true; value.writable=true; value.namesComplete=true; value.names=names; return value;
}
function fixture() {
  const env = {refs:['opaque:1','opaque:2'],snapshot:{revision:1,categories:[category()]},reads:[],loads:0};
  class Reader {
    async pick() { if(env.holdPick) await new Promise(resolve=>env.finishPick=resolve); return env.refs; }
    async resolve(reference) {
      env.reads.push(reference);
      if(env.holdRead) await new Promise(resolve=>env.finishRead=resolve);
      if(env.failRead===reference) throw Error('private native error');
      if(env.changeRevision) env.snapshot.revision++;
      return {uri:env.mismatch?'different':reference,name:'photo-'+env.reads.length+'.jpg',width:10,height:10};
    }
  }
  class Categories { async load() {
    env.loads++; if(env.failLoad) throw Error('storage'); return structuredClone(env.snapshot);
  } }
  const loader=createLoader(new Map([[src('services/operations/PhotoReviewService'),{PhotoReviewService:Reader}],
    [src('services/operations/CategoryService'),{CategoryService:Categories}]]),{Observed:value=>value});
  const Vm=loader(src('viewmodels/MovePreviewViewModel')).MovePreviewViewModel;
  const vm=new Vm(); vm.initialize({}); return {vm,env};
}
async function settle() { for(let i=0;i<8;i++) await Promise.resolve(); }
async function main() {
  await test('same inputs produce the same plan without changing source or category',()=>{
    const photo=source(),target=category(),before=JSON.stringify([photo,target]);
    assert.deepEqual(planMoves([photo],target,K.Album,4),planMoves([photo],target,K.Album,4));
    assert.equal(JSON.stringify([photo,target]),before);
  });
  await test('album preview remains read-only despite granted target facts',()=>{
    for(const mode of [K.Album]) {
      const plan=planMoves([source()],category(),mode,1,P.Rename,observation());
      assert.equal(plan.executableCount,0); assert.equal(plan.items[0].state,S.Blocked);
      assert.match(plan.items[0].reasons[0],mode===K.Album?/仅预览/:/移动尚未验证/);
    }
  });
  await test('missing target and revoked read access have explicit reasons',()=>{
    const photo=source(); photo.readable=false;
    assert.match(planMoves([photo],category(),K.Album,1).items[0].reasons[0],/不可读取/);
    assert.match(planMoves([source()],new Category('C','旅游'),K.Album,1).items[0].reasons[0],/尚未绑定系统相册/);
  });
  await test('same location skip requires observed exact target kind and opaque reference',()=>{
    const photo=source(),target=category(); photo.location=new TargetRef(K.Album,target.album.reference,'Renamed');
    assert.equal(planMoves([photo],target,K.Album,1).items[0].state,S.Skipped);
    photo.location.reference+='different'; assert.equal(planMoves([photo],target,K.Album,1).items[0].state,S.Blocked);
    photo.location=new TargetRef(K.Directory,target.album.reference,'same string');
    assert.equal(planMoves([photo],target,K.Album,1).items[0].state,S.Blocked);
  });
  await test('URI text is never parsed to infer target membership or file name',()=>{
    const photo=source(); photo.reference='opaque:A?token=unchanged/photo.jpg'; photo.name='';
    const item=planMoves([photo],category(),K.Album,1).items[0];
    assert.equal(item.state,S.Blocked); assert.equal(item.source.reference,photo.reference); assert.match(item.reasons.join(''),/原文件名称/);
  });
  await test('duplicate logical identities or opaque references reject the entire plan',()=>{
    assert.throws(()=>planMoves([source(),source()],category(),K.Album,1),/重复/);
    const second=source('2'); second.reference=source().reference;
    assert.throws(()=>planMoves([source(),second],category(),K.Album,1),/重复/);
  });
  await test('invalid mode policy oversized selection and mismatched target kinds are rejected',()=>{
    assert.throws(()=>planMoves([source()],category(),'wrong',1));
    assert.throws(()=>planMoves([source()],category(),K.Album,1,'overwrite'));
    assert.throws(()=>planMoves(Array.from({length:101},(_,i)=>source(String(i))),category(),K.Album,1));
    const target=category(); target.album.kind=K.Directory; assert.throws(()=>planMoves([source()],target,K.Album,1));
  });
  await test('default collision policy skips existing names and intra-batch duplicates without overwrite',()=>{
    const first=source('1','Photo.jpg'),second=source('2','photo.JPG'); first.bytes=100; second.bytes=500;
    let plan=planMoves([first,second],category(),K.Album,1,P.Skip,observation());
    assert.equal(plan.items[1].state,S.Skipped); assert.equal(plan.items[1].conflict,true); assert.equal(plan.requiredBytes,100);
    plan=planMoves([first],category(),K.Album,1,P.Skip,observation(['photo.jpg']));
    assert.equal(plan.items[0].state,S.Skipped); assert.equal(plan.requiredBytes,0);
  });
  await test('rename proposals preserve extensions and reserve unique names within the batch',()=>{
    const plan=planMoves([source('1','a.JPG'),source('2','a.JPG')],category(),K.Album,1,P.Rename,observation(['a.jpg','a (1).jpg']));
    assert.equal(plan.items[0].proposedName,'a (2).JPG'); assert.equal(plan.items[1].proposedName,'a (3).JPG');
    assert.equal(plan.items[0].state,S.Conflict); assert.equal(plan.executableCount,0);
  });
  await test('partial target inventory never proves a safe renamed destination',()=>{
    const facts=observation(['a.jpg']); facts.namesComplete=false;
    const item=planMoves([source('1','a.jpg')],category(),K.Album,1,P.Rename,facts).items[0];
    assert.equal(item.proposedName,''); assert.match(item.reasons.join(''),/检查不完整|检查尚未完整/);
  });
  await test('unknown malformed or overflowing sizes remain unknown rather than zero',()=>{
    for(const bytes of [undefined,NaN,-1,0.5,Infinity]) {
      const photo=source(); photo.bytes=bytes; assert.equal(planMoves([photo],category(),K.Album,1).requiredBytes,undefined);
    }
    const a=source('a','a.jpg'),b=source('b','b.jpg'); a.bytes=Number.MAX_SAFE_INTEGER; b.bytes=1;
    assert.equal(planMoves([a,b],category(),K.Album,1).requiredBytes,undefined);
  });
  await test('known copy-stage estimate reports insufficient space without allowing execution',()=>{
    const photo=source(); photo.bytes=1024; const facts=observation(); facts.freeBytes=100;
    const plan=planMoves([photo],category(),K.Album,1,P.Skip,facts);
    assert.equal(plan.requiredBytes,1024); assert.match(plan.items[0].reasons.join(''),/空间不足/); assert.equal(plan.executableCount,0);
  });
  await test('plan owns detached target and source evidence',()=>{
    const photo=source(),target=category(); const plan=planMoves([photo],target,K.Album,1);
    photo.reference='changed'; target.album.reference='changed'; assert.equal(plan.items[0].source.reference,'opaque:photo-1');
    assert.equal(plan.items[0].target.reference,'opaque:A?token=unchanged');
  });
  await test('batch inspection retains unreadable rows and resolves one item at a time',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); env.failRead='opaque:2'; await vm.generate();
    assert.deepEqual(env.reads,['opaque:1','opaque:2']); assert.equal(vm.plan.items.length,2);
    assert.equal(vm.plan.items[1].source.readable,false); assert.match(vm.plan.items[1].reasons[0],/不可读取/);
    assert.equal(vm.plan.executableCount,0);
  });
  await test('selection cancellation preserves prior selection and completed inspection',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); await vm.generate();
    const before=vm.selection,plan=vm.plan; env.refs=[]; await vm.choose(); assert.equal(vm.selection,before); assert.equal(vm.plan,plan);
  });
  await test('mode category or policy change invalidates previously displayed plan',async()=>{
    const {vm}=fixture(); await settle(); await vm.choose(); await vm.generate();
    vm.setPolicy(P.Rename); assert.equal(vm.plan,undefined);
    await vm.generate(); vm.selectCategory(0); assert.equal(vm.plan,undefined);
  });
  await test('deleted category is not planned using an older saved binding',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); env.snapshot.categories=[]; await vm.generate();
    assert.equal(vm.plan,undefined); assert.equal(vm.categoryId,''); assert.equal(env.reads.length,0); assert.match(vm.message,/已被删除/);
  });
  await test('binding changes during asynchronous photo reads invalidate the whole preview',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); env.changeRevision=true; await vm.generate();
    assert.equal(vm.plan,undefined); assert.match(vm.message,/发生变化/);
  });
  await test('unexpected resource identity never becomes readable evidence',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); env.mismatch=true; await vm.generate();
    assert.ok(vm.plan.items.every(item=>!item.source.readable));
  });
  await test('closing page during picker or read cannot assign a late selection or plan',async()=>{
    let {vm,env}=fixture(); await settle(); env.holdPick=true; let pending=vm.choose(); vm.dispose(); env.finishPick(); await pending;
    assert.equal(vm.selection.items.length,0);
    ({vm,env}=fixture()); await settle(); await vm.choose(); env.holdRead=true; pending=vm.generate();
    while(!env.finishRead) await Promise.resolve(); vm.dispose(); env.finishRead(); await pending; assert.equal(vm.plan,undefined); assert.equal(env.reads.length,1);
  });
  await test('rapid repeated generation does not start duplicate reads',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); env.holdRead=true; const pending=vm.generate();
    while(!env.finishRead) await Promise.resolve(); await vm.generate(); await vm.choose(); vm.setPolicy(P.Rename);
    assert.equal(env.reads.length,1);  env.holdRead=false; env.finishRead(); await pending; assert.equal(env.reads.length,2);
  });
  await test('storage failures clear prior plan without leaking platform details',async()=>{
    const {vm,env}=fixture(); await settle(); await vm.choose(); await vm.generate(); env.failLoad=true; await vm.generate();
    assert.equal(vm.plan,undefined); assert.doesNotMatch(vm.message,/storage|opaque:/);
  });
  console.log(`${passed}/${passed} read-only move planning checks passed. No native target inventory, write permission or move was executed.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
