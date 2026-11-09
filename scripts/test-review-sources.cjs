const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const src = name => path.resolve(__dirname, '../entry/src/main/ets', name + '.ets');
function fixture() {
  const env = { calls: [], categories: 0, members: { first: [{uri:'a',name:'a.jpg'}], second: [{uri:'b',name:'b.png'}] }, staged: [] };
  const overrides = new Map([[src('platform/media/PhotoPlaceReader'),{PhotoPlaceReader:class{async read(){return{text:'地点未提供',needsPermission:false};}async request(){return false;}}}],[src('platform/media/GalleryAlbumLocation'),{GalleryAlbumLocation:class{}}],[src('platform/media/GalleryReferenceInspector'),{GalleryReferenceInspector:class{}}],
    [src('platform/media/LocalPhotoReviewSource'), { LocalPhotoReviewSource: class {isAllPhotos(){return !env.album||(env.album.type===1024&&env.album.subtype===1031);}async pick(){return env.selected||[];}setPlaceEnabled(enabled){env.placeEnabled=enabled;}async resolve(reference,readPlace=env.placeEnabled!==false){env.placeReads=[...(env.placeReads||[]),readPlace];return{uri:reference};}setAlbum(album){env.album=album;}async library(next){env.page=next?(env.page||0)+1:0;return env.pages[env.page]||[];}hasMore(){return env.page<env.pages.length-1;}} }],
    [src('data/repositories/DiscardQueueRepository'), { DiscardQueueRepository: class { async load(){if(env.failMarks)throw Error('marks unreadable');return env.marks||[];} } }],
    [src('data/repositories/MoveJournal'), { MoveJournal: class { async excludedReferences(refs) {if(env.failJournal)throw Error('journal unavailable');const excluded=new Set();for(const record of [...env.staged,...(env.classified||[])]){[record.source?.uri,record.copy?.uri,...(record.destinations||[]).map(d=>d.copy?.uri)].filter(Boolean).forEach(ref=>{if(refs.includes(ref))excluded.add(ref);});}return excluded;} } }]
  ]);
  const {PhotoReviewService} = createLoader(overrides)(src('services/operations/PhotoReviewService'));
  return {env, service:new PhotoReviewService({})};
}
let passed = 0;
async function test(name, action) { await action(); passed++; console.log('PASS '+name); }
async function main() {
  await test('normal photo reads retain the configured metadata policy without opening permission dialogs',async()=>{const{env,service}=fixture();service.setPlaceEnabled(false);await service.resolve('A');service.setPlaceEnabled(true);await service.resolve('B');assert.deepEqual(env.placeReads,[false,true]);});

  await test('ordinary album retains completed sources and destination members with marked photos at tail',async()=>{
    const{env,service}=fixture();service.setAlbum({reference:'album',type:0,subtype:1});env.pages=[['copy','old','marked','fresh'],['copy']];env.classified=[{source:{uri:'old'},copy:{uri:'copy'}}];env.marks=[{reference:'marked'}];env.failJournal=true;
    assert.deepEqual(await service.library(),['copy','old','fresh']);assert.deepEqual(await service.library(true),['marked']);assert.equal(service.hasMore(),false);
  });
  await test('system image album still excludes organized photos but favorites does not',async()=>{
    const{env,service}=fixture();env.pages=[['copy','fresh']];env.classified=[{copy:{uri:'copy'}}];service.setAlbum({reference:'all',type:1024,subtype:1031});assert.deepEqual(await service.library(),['fresh']);
    service.setAlbum({reference:'favorite',type:1024,subtype:1025});assert.deepEqual(await service.library(),['copy','fresh']);
    service.setAlbum();assert.deepEqual(await service.library(),['fresh']);
  });
  await test('explicit picks in ordinary albums retain organized members without altering journal',async()=>{
    const{env,service}=fixture();env.selected=['copy','fresh'];env.classified=[{copy:{uri:'copy'}}];service.setAlbum({reference:'album',type:0,subtype:1});assert.deepEqual(await service.pick(),['copy','fresh']);service.setAlbum();assert.deepEqual(await service.pick(),['fresh']);assert.deepEqual(env.classified,[{copy:{uri:'copy'}}]);
  });
  await test('gallery traverses later unmarked pages before marked items and exposes marked tail through hasMore',async()=>{
    const {env,service}=fixture();env.marks=[{reference:'marked'}];env.pages=[['marked'],['fresh'],['done']];env.classified=[{source:{uri:'done'}}];
    assert.deepEqual(await service.library(),['fresh']);assert.equal(service.hasMore(),true);
    assert.deepEqual(await service.library(true),['marked']);assert.equal(service.hasMore(),false);
  });
  await test('unreadable markers fail before gallery query and retry does not consume its first page',async()=>{
    const {env,service}=fixture();env.pages=[['first']];env.failMarks=true;await assert.rejects(service.library());assert.equal(env.page,undefined);
    env.failMarks=false;assert.deepEqual(await service.library(),['first']);
  });
  await test('a new round excludes completed source retained source and both verified destination copies',async()=>{
    const {env,service}=fixture();env.classified=[{source:{uri:'old'},copy:{uri:'album-copy'},destinations:[{copy:{uri:'folder-copy'}}]},{source:{uri:'kept'},copy:{uri:'kept-copy'}}];
    env.pages=[['old','kept','album-copy','folder-copy','kept-copy','new']];assert.deepEqual(await service.library(),['new']);
  });
  await test('album selection forwards its exact reference and resets delivered identities',async()=>{
    const {env,service}=fixture();env.pages=[['A']];assert.deepEqual(await service.library(),['A']);
    const album={reference:'selected-album',type:0,subtype:1};service.setAlbum(album);assert.equal(env.album,album);
    assert.deepEqual(await service.library(),['A']);
  });
  await test('repeated references across gallery pages never re-enter the stream',async()=>{
    const {env,service}=fixture();env.pages=[['A','B'],['B','A'],['B','C']];
    assert.deepEqual(await service.library(),['A','B']);assert.deepEqual(await service.library(true),['C']);assert.equal(service.hasMore(),false);
  });
  await test('failed exclusion read retries the same native gallery page without losing references',async()=>{
    const {env,service}=fixture();env.pages=[['A'],['B']];assert.deepEqual(await service.library(),['A']);env.failJournal=true;
    await assert.rejects(service.library(true));assert.equal(service.hasMore(),true);env.failJournal=false;
    assert.deepEqual(await service.library(true),['B']);assert.equal(service.hasMore(),false);
  });
  console.log(`${passed}/${passed} review source checks passed with explicit native substitutes.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
