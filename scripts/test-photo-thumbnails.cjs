const assert=require('node:assert/strict');
const path=require('node:path');const {createLoader}=require('./ets-test-runtime.cjs');
const src=name=>path.resolve(__dirname,'../entry/src/main/ets',name+'.ets');
function fixture(){
 const env={closed:0,released:0,filesClosed:0,imagesReleased:0,pixelsReleased:0,requested:[],count:1,uri:'media:test'};
 const pixels={async release(){env.pixelsReleased++;}};
 class Predicates {equalTo(key,value){env.requested.push([key,value]);return this;}}
 const source={async getImageInfo(){return {size:{width:100,height:10000}};},async createPixelMap(options){env.decode=options;return pixels;},async release(){env.imagesReleased++;if(env.failImageRelease)throw Error('image release');}};
 const overrides=new Map([
 ['@kit.MediaLibraryKit',{photoAccessHelper:{PhotoKeys:{URI:'uri'},getPhotoAccessHelper(){return {async getAssets(){return {getCount:()=>env.count,async getFirstObject(){return {uri:env.uri,async getThumbnail(size){env.size=size;if(env.fail)throw Error('decode');return pixels;}};},close(){env.closed++;}};},async release(){env.released++;if(env.failHelperRelease)throw Error('helper release');}};}}}],
 ['@kit.ArkData',{dataSharePredicates:{DataSharePredicates:Predicates}}],
 ['@kit.ImageKit',{image:{createImageSource(){return source;}}}],
 ['@kit.CoreFileKit',{fileIo:{OpenMode:{READ_ONLY:0},async open(){env.open=true;return {fd:42};},async close(){env.filesClosed++;}}}],
 [src('platform/files/LegacyDocumentAccess'),{LegacyDocumentAccess:class{async validate(){if(env.denied)throw Error('denied');env.validated=true;}}}]
 ]);
 const {PhotoThumbnailSource}=createLoader(overrides)(src('platform/media/PhotoThumbnailSource'));
 return {env,pixels,reader:new PhotoThumbnailSource({})};
}
let passed=0;async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
async function main(){
 await test('gallery previews use platform thumbnails and release query handles',async()=>{const {env,pixels,reader}=fixture();assert.equal(await reader.load('media:test'),pixels);assert.deepEqual(env.size,{width:256,height:256});assert.deepEqual([env.closed,env.released,env.pixelsReleased],[1,1,0]);});
 await test('native thumbnail decode failure closes fetch result and helper',async()=>{const {env,reader}=fixture();env.fail=true;await assert.rejects(reader.load('media:test'));assert.deepEqual([env.closed,env.released],[1,1]);});
 await test('missing or changed gallery resource never displays another image',async()=>{for(const mode of ['missing','changed']){const {env,reader}=fixture();if(mode==='missing')env.count=0;else env.uri='media:other';await assert.rejects(reader.load('media:test'));assert.equal(env.size,undefined);assert.equal(env.released,1);}});
 await test('long document preview is decoded at bounded dimensions and releases native resources',async()=>{const {env,pixels,reader}=fixture();assert.equal(await reader.load('file://docs/owned/photo.jpg'),pixels);assert.equal(env.validated,true);assert.deepEqual(env.decode.desiredSize,{width:3,height:256});assert.deepEqual([env.filesClosed,env.imagesReleased],[1,1]);});
 await test('revoked document grant cannot open or decode a thumbnail',async()=>{const {env,reader}=fixture();env.denied=true;await assert.rejects(reader.load('file://docs/owned/photo.jpg'));assert.equal(env.open,undefined);});
 await test('a completed thumbnail is released if query helper cleanup fails',async()=>{const {env,reader}=fixture();env.failHelperRelease=true;await assert.rejects(reader.load('media:test'));assert.equal(env.pixelsReleased,1);});
 await test('a completed document thumbnail is released if image-source cleanup fails',async()=>{const {env,reader}=fixture();env.failImageRelease=true;await assert.rejects(reader.load('file://docs/owned/photo.jpg'));assert.equal(env.pixelsReleased,1);assert.equal(env.filesClosed,1);});
 console.log(`${passed}/${passed} native thumbnail boundary and resource checks passed with explicit substitutes.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
