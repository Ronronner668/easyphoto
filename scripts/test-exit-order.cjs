const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const src=name=>path.resolve(__dirname,'../entry/src/main/ets',name+'.ets');
const load=createLoader();
const {PendingDiscardOrder}=load(src('domain/usecases/PendingDiscardOrder'));
const {reportSummary,formatEstimatedSpace}=load(src('domain/usecases/ReportSummary'));
let passed=0;async function test(name,action){await action();passed++;console.log('PASS '+name);}
async function main(){
  await test('finalization service removes protected source identities before any delete planning',async()=>{
    const env={records:[{id:'kept',phase:'awaiting_trash',target:'album:target',source:{uri:'media:marked'}},{id:'fresh',phase:'awaiting_trash',target:'album:target',source:{uri:'media:fresh'}}],submitted:[]};
    const overrides=new Map([
      ['@kit.MediaLibraryKit',{photoAccessHelper:{}}],
      [src('data/repositories/MoveJournal'),{MoveJournal:class{async staged(){return env.records;}}}],
      [src('services/operations/CategoryService'),{CategoryService:class{}}],
      [src('platform/media/VerifiedAlbumMoveAdapter'),{VerifiedAlbumMoveAdapter:class{}}],
      [src('platform/permissions/PermissionProbe'),{PermissionProbe:class{canWriteLibrary(){return true;}canReadLibrary(){return true;}}}],
      [src('domain/usecases/FinishStagedMoves'),{finishStagedMoves:async(records)=>{env.submitted=records;return 'test';}}]
    ]);
    const {VerifiedMoveService}=createLoader(overrides)(src('services/operations/VerifiedMoveService'));
    const service=new VerifiedMoveService({});service.currentRecords.add('kept');service.currentRecords.add('fresh');await service.finish(false,['media:marked']);assert.deepEqual(env.submitted.map(r=>r.id),['fresh']);assert.equal(env.records[0].phase,'awaiting_trash');
  });
  await test('marked but undeleted references remain visible after every unorganized page',async()=>{
    const order=new PendingDiscardOrder(['marked-A','marked-B']);
    assert.deepEqual(order.accept(['marked-A','fresh-A','done'],new Set(['done'])),['fresh-A']);
    assert.deepEqual(order.accept(['marked-B','fresh-B'],new Set()),['fresh-B']);
    assert.equal(order.hasPending(),true);assert.deepEqual(order.take(),['marked-A','marked-B']);assert.equal(order.hasPending(),false);
  });
  await test('marked identity overrides organized history without reintroducing other organized copies',async()=>{
    const order=new PendingDiscardOrder(['source']);assert.deepEqual(order.accept(['source','copy'],new Set(['source','copy'])),[]);
    assert.deepEqual(order.take(),['source']);
  });
  await test('duplicate marked references and new source scopes never leak or wrap',async()=>{
    const order=new PendingDiscardOrder(['A']);order.accept(['A','A'],new Set());order.accept(['A'],new Set());
    assert.deepEqual(order.take(),['A']);assert.deepEqual(order.take(),[]);
    const next=new PendingDiscardOrder(['A']);assert.deepEqual(next.take(),[]);
  });
  await test('three-line report estimates confirmed recycling bytes and scales MB to GB',async()=>{
    assert.equal(reportSummary({organized:12,recycled:3,recycledBytes:1048576,unknownBytes:0}), '本次分类12张\n删除图片3张\n预计释放空间1.00MB');
    assert.equal(formatEstimatedSpace(1048576),'1.00MB');assert.equal(formatEstimatedSpace(1073741824),'1.00GB');
    for(const value of [undefined,NaN,-1])assert.equal(formatEstimatedSpace(value),'0.00MB');
  });
  await test('estimates exclude external stale removals and express unknown-byte totals as lower bounds',async()=>{
    assert.equal(reportSummary({organized:0,recycled:0,recycledBytes:0,unknownBytes:0}),'本次分类0张\n删除图片0张\n预计释放空间0.00MB');
    assert.equal(reportSummary({organized:1,recycled:2,recycledBytes:1048576,unknownBytes:1}).split('\n')[2],'预计释放空间≥1.00MB');
    assert.equal(formatEstimatedSpace(1024),'0.0010MB');
  });
  console.log(`${passed}/${passed} deferred discard ordering and compact report checks passed.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
