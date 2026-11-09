const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const src=name=>path.resolve(__dirname,'../entry/src/main/ets',name+'.ets');
const {RoundProgress}=createLoader()(src('domain/models/OrganizingReport'));
const {ViewerTapGuard}=createLoader()(src('domain/usecases/ViewerTapGuard'));
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
function fixture(){
  const env={favorite:false,changes:0,closed:0,released:0,queries:0};
  class Predicates{equalTo(key,value){env.query=[key,value];return this;}}
  class Request{constructor(asset){env.requestAsset=asset.uri;}setFavorite(value){env.desired=value;}}
  const helper={async getAssets(){env.queries++;if(env.queryFail)throw Error('query');return {getCount:()=>1,async getFirstObject(){return {uri:env.changed?'other':'media:sample',get(){return env.favorite;}};},close(){env.closed++;}};},async applyChanges(){env.changes++;if(env.hold)await new Promise(r=>env.resume=r);if(env.fail)throw Error('denied');if(!env.noEffect)env.favorite=env.desired;},async release(){env.released++;}};
  const overrides=new Map([
    ['@kit.BasicServicesKit',{deviceInfo:{get sdkApiVersion(){return env.api===undefined?26:env.api;}}}],
    ['@kit.MediaLibraryKit',{photoAccessHelper:{PhotoKeys:{URI:'uri',FAVORITE:'favorite'},MediaAssetChangeRequest:Request,getPhotoAccessHelper:()=>helper}}],
    ['@kit.ArkData',{dataSharePredicates:{DataSharePredicates:Predicates}}],
    [src('platform/permissions/PermissionProbe'),{PermissionProbe:class{canReadLibrary(){return !env.denied;}canWriteLibrary(){return !env.denied;}async requestWrite(){env.permissionRequest=true;}}}]
  ]);
  const {GalleryFavorite}=createLoader(overrides)(src('platform/media/GalleryFavorite'));
  return {env,Request,service:new GalleryFavorite({})};
}
async function main(){
  await test('older API and encoded older API are rejected before permissions or gallery access',async()=>{
    for(const api of [23,60100023,NaN]){const {env,service}=fixture();env.api=api;await assert.rejects(service.set('media:sample',true),/API26/);assert.equal(env.queries,0);assert.equal(env.changes,0);assert.equal(env.permissionRequest,undefined);}
    const {env,service}=fixture();env.api=260000026;await service.set('media:sample',true);assert.equal(env.favorite,true);
  });
  await test('pinch and pan retain viewer until both finish and a fresh tap follows',async()=>{
    const gate=new ViewerTapGuard();assert.equal(gate.canClose(0),true);gate.start('pinch');gate.start('pan');
    assert.equal(gate.canClose(1000),false);gate.finish('pan',1000);assert.equal(gate.canClose(1500),false);
    gate.finish('pinch',1500);assert.equal(gate.canClose(1501),false);assert.equal(gate.canClose(1700),true);
    gate.start('pan');gate.finish('pan',2000);assert.equal(gate.canClose(2001),false);assert.equal(gate.canClose(2200),true);
  });
  await test('report counts verified classifications and recycled identities once independently',async()=>{
    const round=new RoundProgress();round.classified('a');round.classified('a');round.classified('b');
    round.removed({uri:'a',bytes:200});round.removed({uri:'a',bytes:200});round.removed({uri:'marked',bytes:300});
    const report=round.snapshot(1);assert.deepEqual([report.organized,report.recycled,report.recycledBytes,report.pending],[2,2,500,1]);
    assert.equal(new RoundProgress().snapshot(0).organized,0);
  });
  await test('unknown size never becomes fictional saved bytes and snapshots do not mutate',async()=>{
    const round=new RoundProgress();round.removed({uri:'unknown',bytes:NaN});const report=round.snapshot(2);
    assert.equal(report.unknownBytes,1);assert.equal(report.recycledBytes,0);round.classified('next');assert.equal(report.organized,0);
  });
  await test('favorite uses native change request and confirms actual gallery readback',async()=>{
    const {env,service}=fixture();await service.set('media:sample',true);assert.equal(env.favorite,true);assert.equal(env.requestAsset,'media:sample');
    assert.deepEqual([env.changes,env.queries,env.closed,env.released],[1,2,2,1]);await service.set('media:sample',false);assert.equal(env.favorite,false);
  });
  await test('file-folder photo never triggers gallery write or permissions',async()=>{
    const {env,service}=fixture();await assert.rejects(service.set('file://docs/synthetic/photo.jpg',true));assert.equal(env.changes,0);assert.equal(env.queries,0);
  });
  await test('older public API reports unsupported instead of fabricating local favorite',async()=>{
    const {env,Request,service}=fixture();delete Request.prototype.setFavorite;await assert.rejects(service.set('media:sample',true),/API26/);
    assert.equal(env.changes,0);assert.equal(env.favorite,false);assert.equal(env.released,1);
  });
  await test('reference mismatch and permission refusal do not modify another resource',async()=>{
    for(const flag of ['changed','denied']){const {env,service}=fixture();env[flag]=true;await assert.rejects(service.set('media:sample',true));assert.equal(env.changes,0);}
  });
  await test('native failure or mismatching readback remains unconfirmed with resources released',async()=>{
    for(const flag of ['fail','noEffect']){const {env,service}=fixture();env[flag]=true;await assert.rejects(service.set('media:sample',true));assert.equal(env.released,1);}
  });
  await test('same resource favorite writes are serialized and unlock after failure',async()=>{
    const {env,service}=fixture();env.hold=true;const pending=service.set('media:sample',true);
    while(!env.resume)await Promise.resolve();await assert.rejects(service.set('media:sample',false),/正在更新/);
    env.resume();await pending;env.hold=false;await service.set('media:sample',false);assert.equal(env.changes,2);
  });
  console.log(`${passed}/${passed} round report and native favorite checks passed with explicit substitutes.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
