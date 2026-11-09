const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const src=name=>path.resolve(__dirname,'../entry/src/main/ets',name+'.ets');
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
const {photoInfoRows}=createLoader()(src('domain/models/PhotoInfoSettings'));
const {photoCardHeight,photoCardWidth,isLongPhoto}=createLoader()(src('domain/usecases/PhotoGeometry'));
function sourceFixture(){
  const env={closed:0,released:0,queries:0,hold:false};
  const result=()=>({getCount:()=>205,async getObjectByPosition(index){return {uri:'media:'+index};},close(){env.closed++;}});
  class Predicates {equalTo(){return this;}orderByDesc(){return this;}}
  const overrides=new Map([[src('platform/media/PhotoPlaceReader'),{PhotoPlaceReader:class{async read(){return{text:'地点未提供',needsPermission:false};}async request(){return false;}}}],
    ['@kit.MediaLibraryKit',{photoAccessHelper:{PhotoKeys:{PHOTO_TYPE:'type',DATE_ADDED:'date'},PhotoType:{IMAGE:1},getPhotoAccessHelper(){return {async getAssets(){env.queries++;if(env.hold)await new Promise(r=>env.resolve=r);return result();},async release(){env.released++;}};}}}],
    ['@kit.ArkData',{dataSharePredicates:{DataSharePredicates:Predicates}}],['@kit.CoreFileKit',{}],['@kit.ImageKit',{}],
    [src('platform/files/LegacyDocumentAccess'),{LegacyDocumentAccess:class{}}],
    [src('platform/files/ContentHash'),{contentHash:async()=>''}],
    [src('data/repositories/MoveJournal'),{MoveJournal:class{}}],
    [src('platform/permissions/PermissionProbe'),{PermissionProbe:class{canReadLibrary(){return true;}}}]
  ]);
  const {LocalPhotoReviewSource}=createLoader(overrides)(src('platform/media/LocalPhotoReviewSource'));
  return {env,reader:new LocalPhotoReviewSource({})};
}
function mediaFixture(subtype,name,photoType=1,propertyType=photoType){
  let closed=0,released=0;
  class Predicates {equalTo(){return this;}}
  const asset={uri:'media:photo',displayName:name,photoType:propertyType,get:key=>({size:1000,date_taken:10,subtype,media_type:photoType})[key]};
  const overrides=new Map([[src('platform/media/PhotoPlaceReader'),{PhotoPlaceReader:class{async read(){return{text:'地点未提供',needsPermission:false};}async request(){return false;}}}],
    ['@kit.MediaLibraryKit',{photoAccessHelper:{PhotoKeys:{PHOTO_TYPE:'media_type',URI:'uri',SIZE:'size',DATE_TAKEN:'date_taken',PHOTO_SUBTYPE:'subtype'},PhotoType:{IMAGE:1},PhotoSubtype:{MOVING_PHOTO:3,BURST:4},getPhotoAccessHelper(){return {async getAssets(){return {getCount:()=>1,getFirstObject:async()=>asset,close(){closed++;}};},async release(){released++;}};}}}],
    ['@kit.ArkData',{dataSharePredicates:{DataSharePredicates:Predicates}}],
    ['@kit.CoreFileKit',{fileIo:{OpenMode:{READ_ONLY:0},async open(){return {fd:1};},async stat(){return {size:40};},async close(){}}}],
    [src('platform/files/ContentHash'),{contentHash:async()=>'hash'}]
  ]);
  const {VerifiedAlbumMoveAdapter}=createLoader(overrides)(src('platform/media/VerifiedAlbumMoveAdapter'));
  return {adapter:new VerifiedAlbumMoveAdapter({}),handles:()=>[closed,released]};
}
async function main(){
  await test('very long image is bounded inside photo area while normal landscape retains aspect ratio',async()=>{assert.equal(photoCardHeight(300,500,100,8000,.88),500);assert.equal(photoCardHeight(300,500,4000,1000,.88),66);assert.ok(photoCardHeight(300,500,1,100000,.88)<=500);assert.equal(photoCardHeight(0,500,100,100,.88),1);});
  await test('ordinary portrait and landscape cards fit both dimensions without cropping',async()=>{
    for(const [w,h] of [[4000,1000],[1000,2500],[1800,1800]]) {
      const width=photoCardWidth(300,500,w,h,.88),height=photoCardHeight(300,500,w,h,.88);
      assert.ok(width<=264 && height<=500);assert.ok(Math.abs(width/height-w/h)<1e-9);
    }
    assert.equal(photoCardWidth(300,500,1000,2500,.88),200);
  });
  await test('normal photos fill one viewport edge while preserving complete content and aspect ratio',async()=>{
    for(const [w,h] of [[4000,3000],[3000,4000],[1080,2400],[1800,1800],[4000,1000]]) {
      assert.equal(isLongPhoto(w,h),false);
      const width=photoCardWidth(300,500,w,h,1),height=photoCardHeight(300,500,w,h,1);
      assert.ok(width<=300 && height<=500);assert.ok(Math.abs(width/height-w/h)<1e-9);
      assert.ok(Math.abs(width-300)<1e-9 || Math.abs(height-500)<1e-9);
    }
  });
  await test('long screenshot threshold retains readable card width and bounded crop height',async()=>{
    assert.equal(isLongPhoto(1000,2999),false);assert.equal(isLongPhoto(1000,3000),true);
    assert.equal(photoCardWidth(300,500,100,8000,.88),264);
    assert.equal(photoCardHeight(300,500,100,8000,.88),500);
    for(const bad of [0,-1,NaN,Infinity]) { assert.equal(isLongPhoto(bad,3000),false);assert.equal(photoCardWidth(300,500,bad,3000,.88),1); }
  });
  await test('screenshot subtype is accepted instead of being rejected as nondefault JPEG',async()=>{const {adapter}=mediaFixture(1,'截图.png');const result=await adapter.identify('media:photo');assert.equal(result.subtype,1);assert.equal(result.retainOriginal,false);});
  await test('authorized image media is not artificially restricted by filename suffix',async()=>{for(const name of ['photo.heic','image.gif','image.webp','image.avif']){const {adapter}=mediaFixture(0,name);assert.equal((await adapter.identify('media:photo')).name,name);}});
  await test('compound images retain original attachments and compare real streamed cover size',async()=>{for(const subtype of [3,4]){const {adapter}=mediaFixture(subtype,'image.heic');const result=await adapter.identify('media:photo');assert.equal(result.retainOriginal,true);assert.equal(result.bytes,40);}});
  await test('non-image media remains blocked and native query handles are released',async()=>{const {adapter,handles}=mediaFixture(0,'video.mp4',2);await assert.rejects(adapter.identify('media:photo'));assert.deepEqual(handles(),[1,1]);});
  await test('canonical media_type is checked even if a wrapper photoType property is inconsistent',async()=>{
    const {adapter}=mediaFixture(0,'sample.jpg',1,2);assert.equal((await adapter.identify('media:photo')).uri,'media:photo');
    const video=mediaFixture(0,'video.mp4',2,1);await assert.rejects(video.adapter.identify('media:photo'),/不是图片/);
  });
  await test('a different returned resource never passes identity validation',async()=>{
    const {adapter,handles}=mediaFixture(0,'sample.jpg');await assert.rejects(adapter.identify('media:other'),/引用已变化/);assert.deepEqual(handles(),[1,1]);
  });
  const photo={name:'test.png',taken:new Date(2026,0,2).getTime()/1000,width:2160,height:1440,bytes:2097152,place:'杭州'};
  await test('header contains date then time only',async()=>{assert.deepEqual(photoInfoRows(photo),['2026年1月2日','00:00']);});
  await test('header preserves local hours and minutes without place name dimensions or size',async()=>{assert.deepEqual(photoInfoRows({...photo,taken:new Date(2026,10,4,22,34).getTime()/1000}),['2026年11月4日','22:34']);});
  await test('missing metadata is explicit and invalid timestamps do not invent a date',async()=>{for(const taken of [0,-1,NaN])assert.deepEqual(photoInfoRows({...photo,taken,place:''}),['日期未提供','时间未提供']);});
  await test('205 photos continue as 100 100 5 without re-querying or skipping snapshot references',async()=>{const {env,reader}=sourceFixture();const a=await reader.library();assert.equal(reader.hasMore(),true);const b=await reader.library(true);const c=await reader.library(true);assert.deepEqual([a.length,b.length,c.length],[100,100,5]);assert.equal(new Set([...a,...b,...c]).size,205);assert.equal(c[4],'media:204');assert.equal(reader.hasMore(),false);assert.equal(env.queries,1);reader.close();assert.equal(env.closed,1);assert.equal(env.released,1);});
  await test('refresh opens a new snapshot while disposing old handles',async()=>{const {env,reader}=sourceFixture();await reader.library();await reader.library();assert.equal(env.closed,1);assert.equal(env.released,1);assert.equal(env.queries,2);reader.close();});
  await test('closing during native snapshot query releases late native resources',async()=>{const {env,reader}=sourceFixture();env.hold=true;const pending=reader.library();while(!env.resolve)await Promise.resolve();reader.close();env.resolve();await assert.rejects(pending);assert.equal(env.closed,1);assert.equal(env.released,1);});
  console.log(`${passed}/${passed} photo information and snapshot paging checks passed with explicit native test doubles.`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
