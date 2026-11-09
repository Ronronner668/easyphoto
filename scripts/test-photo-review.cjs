const assert = require('node:assert/strict');
const path = require('node:path');
const { createLoader } = require('./ets-test-runtime.cjs');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const src = relative => path.join(root, relative + '.ets');
const { PhotoReviewSession } = createLoader()(src('domain/models/PhotoReview'));
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS ' + name); }
function makeVm(practice = false) {
  const env = { selected: ['reference-A', 'reference-B'], fail: '', holdPick: false, holdResolve: false, calls: [] };
  env.marks = []; env.markCalls = 0;
  env.categories = {revision:0, categories:[]};
  class Queue {
    async load() { if (env.failMarksLoad) throw Error('storage unavailable'); return structuredClone(env.marks); }
    async mark(reference, name) {
      env.markCalls++;
      if (env.holdMark) await new Promise(resolve => { env.finishMark = resolve; });
      if (env.failMark) throw Error('commit failed');
      if (!env.marks.some(item => item.reference === reference)) env.marks.push({ reference, name, markedAt: 1 });
      return this.load();
    }
    async unmark(reference) { if(env.failUnmark)throw Error('unmark failed'); env.marks = env.marks.filter(item => item.reference !== reference); return this.load(); }
  }
  class Source {
    invalidate() {}
    setPlaceEnabled() {}
    close() {}
    async library(next=false) {
      if (env.holdLibrary) await new Promise(resolve => { env.finishLibrary = resolve; });
      if (env.failLibrary) throw Object.assign(new Error('denied'), {code:201});
      if(env.pages){env.page=next?(env.page||0)+1:0;return env.pages[env.page]||[];}
      return env.selected;
    }
    hasMore(){return env.pages ? env.page<env.pages.length-1 : env.selected.length===100;}
    async pick() {
      if (env.holdPick) return new Promise(resolve => { env.finishPick = resolve; });
      return env.selected;
    }
    async availability(reference){if(env.holdAvailability)await new Promise(r=>env.finishAvailability=r);return env.availability?.[reference]||'unavailable';}
    async resolve(reference) {
      env.calls.push(reference);
      if (env.holdResolve) return new Promise(resolve => { env.finishResolve = resolve; });
      if (env.fail === reference || env.failReferences?.includes(reference)) throw Object.assign(new Error('private platform message intentionally ignored'), { code: 201 });
      return { uri: reference, name: reference + '.jpg', width: 10, height: 20, favorite: !!env.favorite };
    }
  }
const overrides = new Map([[src('platform/media/PhotoShareService'),{PhotoShareService:class{async share(ref,name){env.share=[ref,name];if(env.failShare)throw Error('native');}}}],[src('data/repositories/WorkbenchPreferences'),{WorkbenchPreferences:class{async loadTargetAlbums(){return env.targets;}}}],[src('services/operations/DiscardTrashService'),{DiscardTrashService:class {async trash(refs){env.trashRequests=[...(env.trashRequests||[]),refs];if(env.trashFailure)throw Error('trash failed');if(!env.cancelTrash)env.marks=env.marks.filter(mark=>!refs.includes(mark.reference));return 'test';}}}], [src('services/operations/VerifiedMoveService'), { VerifiedMoveService: class { async staged(){if(env.failStagedRead)throw Error('read failed');return env.staged||[];} async classified(){return env.classified||[];} async completedCount(){return 0;}
    get confirmedRecycled(){return env.confirmedRecycled||[];} async finish(keep,protectedSources){env.protectedSources=protectedSources;env.finishCalls=(env.finishCalls||0)+1;env.finishKeep=keep;if(env.holdFinish)await new Promise(r=>env.resumeFinish=r);if(env.afterFinish)env.afterFinish();return 'finish';} async move(reference,id,kind,keepOriginal) {
    env.keepOriginal=keepOriginal;
    env.moveKind=kind;
    env.moveCalls=(env.moveCalls||0)+1;
    env.moveRequests=[...(env.moveRequests||[]),[reference,id]];
    if(env.holdMove) await new Promise(resolve=>env.finishMove=resolve);
    if(env.alreadyInTarget) throw env.alreadyError;
    if(env.moveFailure) throw Object.assign(Error('native'),{code:env.moveFailure});
    if(!env.moveResult) throw Error('not enabled in this fixture');
    return structuredClone({source:{uri:reference},...env.moveResult});
  } } }],
    [src('platform/media/GalleryFavorite'), { GalleryFavorite: class { async set(ref,value){env.favoriteRequest=[ref,value];if(env.holdFavorite)await new Promise(r=>env.resumeFavorite=r);if(env.favoriteFail)throw Error('native');env.favorite=value;} } }],
    [src('services/operations/PhotoReviewService'), { PhotoReviewService: Source }],
    [src('services/operations/DiscardQueueService'), { DiscardQueueService: Queue }],
    [src('services/operations/AlbumClassificationTargets'), { AlbumClassificationTargets: class { async load() {
      if(env.failCategories) throw Error('database unavailable'); return structuredClone(env.categories);
    } } }]]);
  if (practice) {
    for (const [filename, exports] of overrides) {
      overrides.set(filename, Object.fromEntries(Object.keys(exports).map(name => [name, class {
        constructor() { throw Error('Practice constructed live service ' + name); }
      }])));
    }
  }
  const loader = createLoader(overrides, { Observed: value => value });
  env.alreadyError = new (loader(src('domain/models/Experiment')).AlreadyInTargetError)('照片已在目标中，无需移动。');
  const Vm = loader(src('viewmodels/PhotoReviewViewModel')).PhotoReviewViewModel;
  const vm = new Vm();
  const ready = practice ? vm.initializePractice() : vm.initialize({});
  return { env, vm, ready };
}
async function main() {
  await test('practice uses review gestures and classification handlers without live services', async () => {
    const { vm, ready } = makeVm(true);
    await ready;
    const refs = vm.session.items.map(item => item.reference);
    assert.deepEqual(vm.selectedTargets().map(item => item.name), ['动物', '自然', '人像']);
    assert.equal(refs.length, 5);
    await vm.gesture(-59, 0);
    assert.equal(vm.practiceStep, 0);
    await vm.gesture(-60, 0);
    assert.equal(vm.photo.uri, refs[1]);
    await vm.gesture(60, 0);
    await vm.gesture(-60, 0);
    await vm.gesture(0, -80);
    assert.equal(vm.photo.uri, refs[2]);
    assert.equal(vm.marks[0].reference, refs[1]);
    await vm.gesture(60, 0);
    assert.equal(vm.currentMarked(), true);
    await vm.gesture(0, 80);
    assert.equal(vm.currentMarked(), false);
    await vm.gesture(-60, 0);
    await vm.organize('人像');
    assert.equal(vm.photo.uri, refs[2]);
    await vm.organize('人像', true);
    assert.equal(vm.classificationLabel(refs[2]), '待提交分类：人像');
    await vm.organize('动物');
    assert.equal(vm.classificationLabel(refs[2]), '已分类：人像');
    assert.equal(vm.photo.uri, refs[4]);
    await vm.gesture(0, 80);
    assert.equal(vm.photo.uri, refs[4]);
    assert.equal(vm.photo.favorite, true);
    assert.equal(vm.practiceCompletionPending, true);
    await vm.performPracticeHint();
    assert.equal(vm.photo.favorite, true);
    await vm.continueFreePractice();
    assert.equal(vm.photo.uri, refs[0]);
    assert.equal(vm.practiceHint(), undefined);
    await vm.gesture(0, -80);
    assert.equal(vm.canTrashMark(vm.marks[0]), false);
    await vm.trashMarked();
    assert.equal(vm.marks.length, 1);
    assert.equal(await vm.finishRound(), false);
    await vm.unmark(refs[0]);
    await vm.toggleFavorite();
    assert.equal(vm.photo.favorite, true);
    assert.equal(vm.displayedId, vm.session.current().id);
    await vm.selectStart(refs[3]);
    assert.equal(vm.photo.uri, refs[3]);
    assert.equal(vm.canUndoClassification(), true);
    vm.undoClassification();
    assert.equal(vm.classificationLabel(refs[3]), '');
    const { vm: next, ready: nextReady } = makeVm(true);
    await nextReady;
    assert.equal(next.photo.favorite, false);
    assert.equal(next.classificationLabel(refs[2]), '');
    await next.performPracticeHint();
    assert.equal(next.photo.uri, refs[1]);
    await next.skipPracticeGuide();
    assert.equal(next.photo.uri, refs[0]);
    assert.equal(next.practiceHint(), undefined);
  });
  await test('unconfigured targets display ordered samples without native bindings or persisting defaults',async()=>{const{vm,env}=makeVm();await vm.choose();await vm.refreshCategories();while(!vm.targetsReady)await Promise.resolve();assert.deepEqual(vm.selectedTargets().map(c=>c.name),['样例1','样例2','样例3']);assert.ok(vm.selectedTargets().every(c=>c.album===undefined));vm.targetCapacity=4;assert.deepEqual(vm.selectedTargets().map(c=>c.name),['样例1','样例2','样例3','样例4']);assert.equal(env.targets,undefined);});
  await test('sample operations are rejected before any move request and leave browsing and marks unchanged',async()=>{const{vm,env}=makeVm();await vm.choose();const before=JSON.stringify({session:vm.session,marks:vm.marks,report:vm.report()});for(const id of ['sample-target-1','sample-target-4'])await vm.organize(id);assert.equal(env.moveCalls,undefined);assert.equal(JSON.stringify({session:vm.session,marks:vm.marks,report:vm.report()}),before);assert.match(vm.operationFeedback,/占位/);});
  await test('saved real target order replaces samples and returns consistently on later refresh',async()=>{const{vm,env}=makeVm();env.targets=['B','A'];env.categories={revision:0,categories:[{id:'A',name:'First',album:{reference:'A'}},{id:'B',name:'Second',album:{reference:'B'}}]};await vm.choose();await vm.refreshCategories();while(!vm.targetsReady)await Promise.resolve();assert.deepEqual(vm.selectedTargets().map(c=>c.name),['Second','First','样例3']);await vm.refreshCategories();assert.deepEqual(vm.selectedTargets().map(c=>c.id),['B','A','sample-target-3']);});
  await test('one real target fills only first slot and unconfigured slots retain ordinal sample labels in both layouts',async()=>{const{vm,env}=makeVm();env.targets=['A'];env.categories={revision:0,categories:[{id:'A',name:'Actual',album:{reference:'A'}}]};await vm.choose();await vm.refreshCategories();while(!vm.targetsReady)await Promise.resolve();for(const capacity of [3,4]){vm.targetCapacity=capacity;const targets=vm.selectedTargets();assert.equal(targets.length,capacity);assert.equal(targets[0].album.reference,'A');assert.deepEqual(targets.slice(1).map(c=>c.name),Array.from({length:capacity-1},(_,i)=>'样例'+(i+2)));assert.ok(targets.slice(1).every(c=>c.album===undefined));}assert.deepEqual(env.targets,['A']);});
  await test('adding another actual target replaces that ordinal sample without persisting other samples',async()=>{const{vm,env}=makeVm();env.targets=['B'];env.categories={revision:0,categories:[{id:'A',name:'Alpha',album:{reference:'A'}},{id:'B',name:'Beta',album:{reference:'B'}}]};await vm.choose();await vm.refreshCategories();while(!vm.targetsReady)await Promise.resolve();assert.deepEqual(vm.selectedTargets().map(c=>c.name),['Beta','样例2','样例3']);env.targets=['B','A'];await vm.refreshCategories();assert.deepEqual(vm.selectedTargets().map(c=>c.name),['Beta','Alpha','样例3']);assert.deepEqual(env.targets,['B','A']);});
  await test('unreadable target configuration is not presented as an empty unconfigured sample list',async()=>{const{vm,env}=makeVm();await vm.choose();env.failCategories=true;await vm.refreshCategories();await Promise.resolve();assert.deepEqual(vm.selectedTargets(),[]);assert.equal(vm.targetsReady,false);});

  await test('partial state-clear failure retains the remaining mark and supports an explicit retry',async()=>{const{vm,env}=makeVm();await vm.choose();env.marks=[{reference:'reference-A',name:'A',markedAt:1}];env.favorite=true;await vm.refreshMarks();await vm.recheck();env.failUnmark=true;await vm.downward();assert.equal(vm.currentMarked(),true);assert.equal(vm.photo.favorite,false);assert.ok(vm.operationFeedback);env.failUnmark=false;await vm.downward();assert.equal(vm.currentMarked(),false);assert.equal(vm.photo.uri,'reference-A');});
  await test('missing targets retain their ordinal placeholders and over-capacity configuration is not sliced',async()=>{const{vm,env}=makeVm();env.targets=['missing','available'];env.categories={revision:0,categories:[{id:'available',name:'Real',album:{reference:'available'}}]};await vm.refreshCategories();while(!vm.targetsReady)await Promise.resolve();assert.deepEqual(vm.selectedTargets().map(t=>t.id),['missing','available','sample-target-3']);assert.equal(vm.selectedTargets()[0].album,undefined);assert.ok(vm.targetMessage);env.targets=['1','2','3','4'];vm.targetCapacity=3;await vm.refreshCategories();assert.equal(vm.selectedTargetRefs.length,4);assert.deepEqual(vm.selectedTargets(),[]);});

  await test('top favorite flips visually before native completion and rolls back on failure without changing identity',async()=>{const{vm,env}=makeVm();await vm.choose();env.holdFavorite=true;const pending=vm.toggleFavorite();assert.equal(vm.photo.favorite,true);assert.equal(vm.busy,true);assert.equal(vm.photo.uri,'reference-A');env.resumeFavorite();await pending;assert.equal(vm.photo.favorite,true);env.favoriteFail=true;env.holdFavorite=false;await vm.toggleFavorite();assert.equal(vm.photo.favorite,true);assert.ok(vm.operationFeedback);});
  await test('downward on an unmarked unclassified photo toggles system favorite without advancing or marking',async()=>{const{vm,env}=makeVm();await vm.choose();await vm.gesture(0,100);assert.deepEqual(env.favoriteRequest,['reference-A',true]);assert.equal(vm.photo.uri,'reference-A');assert.equal(vm.photo.favorite,true);assert.equal(env.markCalls,0);assert.equal(env.moveCalls,undefined);});
  await test('downward clears pending discard and favorite while keeping classification history and report totals',async()=>{const{vm,env}=makeVm();await vm.choose();env.marks=[{reference:'reference-A',name:'A',markedAt:1}];env.favorite=true;await vm.refreshMarks();await vm.recheck();env.classified=[{id:'old',targetName:'Old',source:{uri:'reference-A'},copy:{uri:'copy-A'},phase:'retained'}];await vm.refreshStaged();const history=JSON.stringify(vm.classified);await vm.downward();assert.equal(vm.currentMarked(),false);assert.equal(vm.photo.favorite,false);assert.equal(vm.photo.uri,'reference-A');assert.equal(JSON.stringify(vm.classified),history);assert.equal(vm.report().recycled,0);assert.equal(env.moveCalls,undefined);});
  await test('native favorite failure keeps the pending discard intent and makes no classification changes',async()=>{const{vm,env}=makeVm();await vm.choose();env.marks=[{reference:'reference-A',name:'A',markedAt:1}];env.favorite=true;await vm.refreshMarks();await vm.recheck();env.favoriteFail=true;await vm.downward();assert.equal(vm.currentMarked(),true);assert.equal(vm.photo.favorite,true);assert.ok(vm.operationFeedback);assert.equal(env.moveCalls,undefined);});
  await test('classified-only downward preserves historical result without adding a favorite or replaying a move',async()=>{const{vm,env}=makeVm();await vm.choose();env.classified=[{id:'old',targetName:'Old',source:{uri:'reference-A'},phase:'retained'}];await vm.refreshStaged();await vm.downward();assert.equal(vm.classified.length,1);assert.equal(env.favoriteRequest,undefined);assert.equal(env.moveCalls,undefined);assert.match(vm.operationFeedback,/分类记录/);});
  await test('undo on the latest photo preserves favorite discard marks and historical classification', async () => {
    const {vm,env}=makeVm(); await vm.choose();
    env.classified=[{id:'old',phase:'retained',targetName:'旧相册',source:{uri:'reference-A'}}];
    env.marks=[{reference:'reference-A',name:'A'}]; env.favorite=true;
    await vm.refreshStaged(); await vm.refreshMarks();
    await vm.organize('C');
    assert.equal(vm.photo.uri,'reference-B'); assert.equal(vm.classificationLabel('reference-A'),'分类待提交');
    assert.equal(vm.canUndoClassification(),false); vm.undoClassification();
    await vm.move(-1); assert.equal(vm.canUndoClassification(),true); vm.undoClassification();
    assert.equal(vm.classificationLabel('reference-A'),'已分类：旧相册');
    assert.equal(vm.photo.favorite,true); assert.equal(env.marks.length,1);
    assert.equal(env.moveCalls,undefined); assert.equal(vm.report().organized,0);
  });
  await test('sharing preserves queue position photo and all local record counts',async()=>{const{vm,env}=makeVm();await vm.choose();const before=JSON.stringify({session:vm.session,marks:vm.marks,report:vm.report()});await vm.shareCurrent();assert.deepEqual(env.share,['reference-A','reference-A.jpg']);assert.equal(JSON.stringify({session:vm.session,marks:vm.marks,report:vm.report()}),before);});

  await test('in-album start choices append without jumping or changing source and selection resumes remaining pages',async()=>{
    const{vm,env}=makeVm();env.pages=[['A','B'],['C','D'],['E']];await vm.loadLibrary();const first=vm.session.current().reference;
    await vm.extendStartChoices();assert.equal(vm.session.current().reference,first);assert.equal(vm.photo.uri,first);assert.deepEqual(vm.session.items.map(p=>p.reference),['A','B','C','D']);
    await vm.selectStart('D');assert.equal(vm.photo.uri,'D');assert.equal(vm.hasMore,true);await vm.move(1);assert.equal(vm.photo.uri,'E');assert.deepEqual(vm.session.items.map(p=>p.reference),['A','B','C','D','E']);
  });
  await test('choosing a starting photo during a pending load cannot replace the displayed identity',async()=>{
    const{vm,env}=makeVm();await vm.loadLibrary();env.holdResolve=true;const pending=vm.selectStart('reference-B');await Promise.resolve();await vm.selectStart('reference-A');assert.equal(vm.session.current().reference,'reference-B');env.finishResolve({uri:'reference-B',name:'B',width:1,height:1});await pending;assert.equal(vm.photo.uri,'reference-B');
  });
  await test('cut classification source recycling is excluded from delete and released-space report totals',async()=>{
    const{vm,env}=makeVm();await vm.choose();env.confirmedRecycled=[{uri:'classified-source',bytes:999}];await vm.finishRound();assert.equal(vm.report().recycled,0);assert.equal(vm.report().recycledBytes,0);
  });

  await test('explicitly keeping pending deletion also protects overlapping classified sources during finalization',async()=>{
    const {vm,env}=makeVm();await vm.choose();env.staged=[{id:'overlap',phase:'awaiting_trash',source:{uri:'reference-A'},copy:{uri:'copy-A'}}];await vm.refreshStaged();
    assert.equal(await vm.finishRound(['reference-A']),true);assert.deepEqual(env.protectedSources,['reference-A']);assert.equal(vm.staged.length,1);assert.equal(vm.photo.uri,'reference-A');
    assert.equal(await vm.finishRound([]),false);
  });
  await test('system favorite updates only after readback and failures retain previous visible state',async()=>{
    const {vm,env}=makeVm();await vm.choose();await vm.toggleFavorite();assert.equal(vm.photo.favorite,true);assert.deepEqual(env.favoriteRequest,['reference-A',true]);
    env.favoriteFail=true;await vm.toggleFavorite();assert.equal(vm.photo.favorite,true);assert.ok(vm.operationFeedback);
  });
  await test('favorite locks navigation and disposed late result cannot replace another image',async()=>{
    const {vm,env}=makeVm();await vm.choose();env.holdFavorite=true;const pending=vm.toggleFavorite();await vm.move(1);assert.equal(vm.session.index,0);
    vm.dispose();env.resumeFavorite();await pending;assert.equal(vm.photo,undefined);
  });
  await test('classification B saves only A and only verified copies count in the report', async () => {
    const {vm,env}=makeVm(); await vm.choose();
    env.moveResult={id:'a',phase:'retained',copy:{uri:'copy-A'}};
    await vm.organize('target-A');
    assert.equal(vm.report().organized,0); assert.equal(env.moveCalls,undefined);
    await vm.organize('target-B');
    assert.deepEqual(env.moveRequests,[['reference-A','target-A']]);
    assert.equal(vm.report().organized,1);
    assert.equal(vm.classificationLabel('reference-B'),'分类待提交');
    await vm.selectStart('reference-A'); assert.equal(vm.canUndoClassification(),false);
    await vm.selectStart('reference-B'); assert.equal(vm.canUndoClassification(),true);
  });
  await test('same-source target membership consumes the intent and permits exit without repeated submission', async () => {
    const {vm,env}=makeVm(); await vm.choose(); await vm.organize('target-A');
    env.alreadyInTarget=true;
    assert.equal(await vm.saveLastClassification(),true);
    assert.equal(vm.hasLastClassification(),false); assert.equal(vm.report().organized,0);
    assert.equal(vm.staged.length,0); assert.equal(vm.marks.length,0);
    assert.equal(await vm.finishRound(),true); assert.equal(env.moveCalls,1);
    assert.equal(vm.operationFeedback,'finish');
  });
  await test('finish copies and verifies the last classification before invoking source finalization', async () => {
    const {vm,env}=makeVm(); await vm.choose(); vm.keepOriginal=true;
    env.moveResult={id:'a',phase:'retained',copy:{uri:'copy-A'}};
    await vm.organize('target-A');
    env.afterFinish=()=>assert.deepEqual(env.moveRequests,[['reference-A','target-A']]);
    assert.equal(await vm.finishRound(),true);
    assert.equal(env.finishKeep,true); assert.equal(env.keepOriginal,true);
    assert.equal(vm.report().organized,1); assert.equal(vm.hasLastClassification(),false);
  });
  await test('retained finalization keeps original identity while completed finalization resolves copy',async()=>{
    for(const phase of ['retained','complete']){const {vm,env}=makeVm();await vm.choose();const id=vm.displayedId;
      const record={id:'old',phase:'awaiting_trash',source:{uri:'reference-A'},copy:{uri:'copy-A'}};env.staged=[record];await vm.refreshStaged();
      env.afterFinish=()=>{env.staged=[];env.classified=[{...record,phase}];};vm.keepOriginal=true;
      assert.equal(await vm.finishRound(),true);assert.equal(env.finishKeep,true);assert.equal(vm.displayedId,id);assert.equal(vm.photo.uri,phase==='retained'?'reference-A':'copy-A');
    }
  });
  await test('cancelled finish and failed queue readback never report completed or lose original',async()=>{
    for(const failRead of [false,true]){const {vm,env}=makeVm();await vm.choose();env.staged=[{id:'old',phase:'awaiting_trash',source:{uri:'reference-A'}}];await vm.refreshStaged();
      if(failRead)env.afterFinish=()=>{env.failStagedRead=true;};assert.equal(await vm.finishRound(),false);assert.equal(vm.photo.uri,'reference-A');assert.equal(vm.staged.length,1);
    }
  });
  await test('rapid finish is single-flight and leaving during finish cannot report navigation success',async()=>{
    const {vm,env}=makeVm();await vm.choose();env.holdFinish=true;const pending=vm.finishRound();assert.equal(await vm.finishRound(),false);assert.equal(env.finishCalls,1);
    vm.dispose();env.resumeFinish();assert.equal(await pending,false);
  });
  await test('browsing skipping marking and replacing the source do not submit a classification', async () => {
    const {vm,env}=makeVm(); env.selected=['reference-A','reference-B','reference-C']; await vm.choose();
    await vm.organize('C'); await vm.markCurrent(); await vm.move(-1); await vm.move(-1);
    await vm.choose(); await vm.loadLibrary();
    assert.equal(vm.photo.uri,'reference-A'); assert.equal(vm.canUndoClassification(),true);
    assert.equal(env.marks[0].reference,'reference-B'); assert.equal(env.moveCalls,undefined);
  });
  await test('reaching a library page end extends the same logical stream automatically',async()=>{
    const {vm,env}=makeVm();env.pages=[['A','B'],['C','D'],['E']];await vm.loadLibrary();const firstId=vm.session.items[0].id;
    for(const expected of ['B','C','D','E']){await vm.move(1);assert.equal(vm.photo.uri,expected);assert.equal(vm.displayedId,vm.session.current().id);}
    assert.equal(vm.session.items.length,5);assert.equal(vm.session.items[0].id,firstId);assert.equal(vm.batchEnded,false);
    await vm.move(1);assert.equal(vm.batchEnded,true);
  });
  await test('failed next page preserves current image and position for retry',async()=>{
    const {vm,env}=makeVm();env.pages=[['A'],['B']];await vm.loadLibrary();env.failLibrary=true;await vm.move(1);
    assert.equal(vm.photo.uri,'A');assert.equal(vm.session.index,0);assert.equal(vm.batchEnded,false);assert.ok(vm.streamError);
    env.failLibrary=false;await vm.retryStream();assert.equal(vm.photo.uri,'B');assert.equal(vm.streamError,'');
  });
  for(const [name,selected,index] of [['first',['A','B','C'],0],['middle',['A','B','C'],1],['last',['A','B','C'],2],['only',['A'],0]]) {
    await test('trash '+name+' item synchronizes session displayed identity and photo',async()=>{
      const {vm,env}=makeVm();env.selected=selected;await vm.choose();for(let i=0;i<index;i++)await vm.move(1);
      env.marks=selected.map(reference=>({reference,name:reference}));await vm.refreshMarks();await vm.trashMarked(selected[index]);
      assert.equal(vm.photo?.uri,vm.session.current()?.reference);assert.equal(vm.displayedId,vm.session.current()?.id||'');assert.equal(vm.busy,false);
      assert.ok(!vm.session.items.some(item=>item.reference===selected[index]));
    });
  }
  await test('bulk confirmation only uses approved references and blocks stale marks',async()=>{
    const {env,vm}=makeVm(); await vm.loadLibrary();
    env.marks=['reference-A','reference-B'].map(reference=>({reference,name:reference})); await vm.refreshMarks();
    await vm.trashMarked(undefined,['reference-A']); assert.deepEqual(env.trashRequests,[['reference-A']]);
    vm.marksReady=false; await vm.trashMarked(undefined,['reference-B']); assert.deepEqual(env.trashRequests,[['reference-A']]);
  });
  await test('cancelled or failed trash retains current photo and does not advance',async()=>{
    for(const mode of ['cancelTrash','trashFailure']){const {vm,env}=makeVm();await vm.choose();env.marks=[{reference:'reference-A',name:'A'}];await vm.refreshMarks();env[mode]=true;
      await vm.trashMarked('reference-A');assert.equal(vm.session.index,0);assert.equal(vm.photo.uri,'reference-A');assert.equal(vm.displayedId,vm.session.current().id);}
  });
  await test('verified staged classification cannot be undone or submitted twice', async () => {
    const {vm,env}=makeVm(); await vm.choose();
    env.moveResult={id:'stage1',phase:'awaiting_trash',source:{uri:'reference-A'},copy:{uri:'copy-A'}};
    await vm.organize('C'); await vm.organize('C'); await vm.selectStart('reference-A');
    assert.equal(vm.staged.length,1); assert.equal(vm.canUndoClassification(),false);
    await vm.organize('C'); assert.equal(env.moveCalls,1);
  });
  await test('same-photo refresh retains visible image while access is rechecked',async()=>{
    const {vm,env}=makeVm();await vm.choose();const before=vm.photo;env.holdResolve=true;
    const pending=vm.recheck();assert.equal(vm.photo,before);env.finishResolve(before);await pending;
    assert.equal(vm.photo.uri,before.uri);
  });
  await test('late image failure from replaced URI cannot hide current copy with same logical identity',async()=>{
    const {vm,env}=makeVm();await vm.choose();const id=vm.session.current().id;
    env.moveResult={phase:'complete',copy:{uri:'new-copy-A'}};await vm.organize('C');await vm.saveLastClassification();await vm.move(-1);
    vm.imageFailed(id,'reference-A');assert.equal(vm.photo.uri,'new-copy-A');vm.imageFailed(id,'new-copy-A');assert.equal(vm.photo,undefined);
  });
  await test('copy failure leaves B selected and permits safe retry without accepting B early', async () => {
    const {vm,env}=makeVm(); await vm.choose(); await vm.organize('A');
    env.moveFailure=201; await vm.organize('B');
    assert.equal(vm.photo.uri,'reference-B'); assert.equal(vm.classificationLabel('reference-B'),'');
    assert.equal(vm.report().organized,0); assert.match(vm.operationFeedback,/201/);
    assert.equal(await vm.finishRound(),false); assert.equal(env.finishCalls,undefined);
    env.moveFailure=0; env.moveResult={id:'a',phase:'retained',copy:{uri:'copy-A'}};
    await vm.organize('B');
    assert.deepEqual(env.moveRequests,[['reference-A','A'],['reference-A','A'],['reference-A','A']]);
    assert.equal(vm.report().organized,1); assert.equal(vm.classificationLabel('reference-B'),'分类待提交');
  });
  await test('rapid classification cannot duplicate a commit or move its selection to another photo', async () => {
    const {vm,env}=makeVm(); await vm.choose(); await vm.organize('A');
    env.holdMove=true; env.moveResult={id:'a',phase:'retained',copy:{uri:'copy-A'}};
    const pending=vm.organize('B'); await vm.organize('C'); await vm.move(-1);
    assert.equal(env.moveCalls,1); assert.equal(vm.photo.uri,'reference-B');
    env.finishMove(); await pending; assert.equal(vm.classificationLabel('reference-B'),'分类待提交');
  });
  await test('closing during an earlier copy does not attach a new intent or report result', async () => {
    const {vm,env}=makeVm(); await vm.choose(); await vm.organize('A');
    env.holdMove=true; env.moveResult={id:'a',phase:'retained',copy:{uri:'copy-A'}};
    const pending=vm.organize('B'); vm.dispose(); env.finishMove(); await pending;
    assert.equal(vm.classificationLabel('reference-B'),''); assert.equal(vm.photo,undefined);
    assert.equal(vm.report().organized,0);
  });
  await test('authorized library loads directly without opening picker and resolves first photo', async () => {
    const {vm,env}=makeVm(); await vm.loadLibrary();
    assert.equal(vm.session.items.length,2); assert.equal(vm.photo.uri,'reference-A');
    assert.deepEqual(env.calls,['reference-A']);
  });
  await test('failed library read preserves existing session rather than treating failure as empty', async () => {
    const {vm,env}=makeVm(); await vm.choose(); const current=vm.session.current().id;
    env.failLibrary=true; await vm.loadLibrary(); assert.equal(vm.session.current().id,current);
    assert.match(vm.message,/201/);
  });
  await test('closing page while library loads rejects late session assignment', async () => {
    const {vm,env}=makeVm(); env.holdLibrary=true; const pending=vm.loadLibrary(); vm.dispose(); env.finishLibrary();
    await pending; assert.equal(vm.session.items.length,0);
  });
  await test('empty session has no current photo or wraparound', () => {
    const value = new PhotoReviewSession([], 'test'); assert.equal(value.current(), undefined); assert.equal(value.navigate(1), false);
  });
  await test('first and last boundaries preserve photo identity', () => {
    const value = new PhotoReviewSession(['A', 'B'], 'test'); const first = value.current().id;
    assert.equal(value.navigate(-1), false); assert.equal(value.current().id, first);
    assert.equal(value.navigate(1), true); const last = value.current().id;
    assert.equal(value.navigate(1), false); assert.equal(value.current().id, last);
    value.navigate(-1); assert.equal(value.current().id, first);
  });
  await test('unsupported jumps and tiny gesture steps have no effect', () => {
    const value = new PhotoReviewSession(['A', 'B'], 'test'); for (const step of [0, 2, -2, 0.5, NaN]) assert.equal(value.navigate(step), false);
    assert.equal(value.index, 0);
  });
  await test('selection deduplicates opaque references without altering them', () => {
    const value = new PhotoReviewSession(['A?token=x', '', 'A?token=x', 'B'], 'test');
    assert.deepEqual(value.items.map(item => item.reference), ['A?token=x', 'B']); assert.notEqual(value.items[0].id, value.items[1].id);
  });
  await test('selection reference count is bounded at 100', () => {
    const value = new PhotoReviewSession(Array.from({ length: 1000 }, (_, index) => 'ref' + index), 'test'); assert.equal(value.items.length, 100);
  });
  await test('separate selections never reuse logical photo identity', () => {
    const first = new PhotoReviewSession(['same-reference']); const second = new PhotoReviewSession(['same-reference']);
    assert.notEqual(first.current().id, second.current().id);
  });
  await test('choose resolves only the current image', async () => {
    const { vm, env } = makeVm(); await vm.choose(); assert.equal(vm.photo.uri, 'reference-A'); assert.deepEqual(env.calls, ['reference-A']);
  });
  await test('browsing changes position through a new observable session', async () => {
    const { vm } = makeVm(); await vm.choose(); const previous = vm.session; await vm.move(1);
    assert.notEqual(vm.session, previous); assert.equal(vm.session.index, 1); assert.equal(vm.photo.uri, 'reference-B');
    await vm.move(-1); assert.equal(vm.photo.uri, 'reference-A');
  });
  await test('cancelled new selection preserves position and displayed image', async () => {
    const { vm, env } = makeVm(); await vm.choose(); await vm.move(1); const previous = vm.session; env.selected = [];
    await vm.choose(); assert.equal(vm.session, previous); assert.equal(vm.photo.uri, 'reference-B');
  });
  await test('unusable returned selection preserves previous session', async () => {
    const { vm, env } = makeVm(); await vm.choose(); const previous = vm.session; env.selected = [''];
    await vm.choose(); assert.equal(vm.session, previous); assert.equal(vm.photo.uri, 'reference-A');
  });
  await test('read failure stays on requested image and does not skip', async () => {
    const { vm, env } = makeVm(); await vm.choose(); env.fail = 'reference-B'; await vm.move(1);
    assert.equal(vm.session.index, 1); assert.equal(vm.photo, undefined); assert.ok(vm.message.includes('201'));
    assert.ok(!vm.message.includes('private platform')); await vm.move(-1); assert.equal(vm.photo.uri, 'reference-A');
  });
  await test('revoked access clears old preview on recheck', async () => {
    const { vm, env } = makeVm(); await vm.choose(); env.fail = 'reference-A'; await vm.recheck();
    assert.equal(vm.photo, undefined); assert.equal(vm.session.index, 0);
  });
  await test('late image error from prior item cannot mark current item failed', async () => {
    const { vm } = makeVm(); await vm.choose(); const previousId = vm.displayedId; await vm.move(1);
    const message = vm.message; vm.imageFailed(previousId); assert.equal(vm.message, message);
    vm.imageFailed(vm.displayedId); assert.notEqual(vm.message, message);
  });
  await test('rapid navigation while resolving does not queue or misbind', async () => {
    const { vm, env } = makeVm(); env.holdResolve = true; const pending = vm.choose();
    while (!env.finishResolve) await Promise.resolve(); await vm.move(1); assert.equal(vm.session.index, 0);
    env.finishResolve({ uri: 'reference-A', name: 'A.jpg', width: 1, height: 1 }); await pending;
    assert.equal(vm.photo.uri, 'reference-A'); assert.equal(vm.session.index, 0);
  });
  await test('closing page cancels assignment from pending picker', async () => {
    const { vm, env } = makeVm(); env.holdPick = true; const pending = vm.choose(); vm.dispose();
    env.finishPick(['reference-A']); await pending; assert.equal(vm.photo, undefined); assert.equal(vm.session.items.length, 0);
  });
  await test('closing page cancels assignment from pending image resolution', async () => {
    const { vm, env } = makeVm(); env.holdResolve = true; const pending = vm.choose();
    while (!env.finishResolve) await Promise.resolve(); vm.dispose();
    env.finishResolve({ uri: 'reference-A', name: 'A.jpg', width: 1, height: 1 }); await pending; assert.equal(vm.photo, undefined);
  });
  await test('mark is durable before advancing and reselected reference keeps its mark', async () => {
    const { vm, env } = makeVm(); await vm.choose(); await vm.markCurrent();
    assert.deepEqual(env.marks.map(item => item.reference), ['reference-A']); assert.equal(vm.session.index, 1);
    await vm.choose(); assert.equal(vm.currentMarked(), true); assert.equal(vm.marks.length, 1);
  });
  await test('failed marker persistence never advances', async () => {
    const { vm, env } = makeVm(); await vm.choose(); env.failMark = true; await vm.markCurrent();
    assert.equal(vm.session.index, 0); assert.equal(env.marks.length, 0); assert.equal(vm.currentMarked(), false);
  });
  await test('committed marker with failed readback is reconciled by refresh without advancing', async () => {
    const { vm, env } = makeVm(); await vm.choose(); env.failMarksLoad = true; await vm.markCurrent();
    assert.equal(env.marks.length, 1); assert.equal(vm.session.index, 0); assert.equal(vm.marks.length, 0);
    env.failMarksLoad = false; await vm.refreshMarks(); assert.equal(vm.currentMarked(), true);
  });
  await test('rapid marking and navigation cannot switch photo while marker is saving', async () => {
    const { vm, env } = makeVm(); await vm.choose(); env.holdMark = true; const pending = vm.markCurrent();
    await vm.move(1); await vm.markCurrent(); assert.equal(env.markCalls, 1); assert.equal(vm.session.index, 0);
    env.finishMark(); await pending; assert.equal(vm.session.index, 1); assert.equal(env.marks[0].reference, 'reference-A');
  });
  await test('marking final photo opens batch choices without wrapping and supports undo', async () => {
    const { vm, env } = makeVm(); await vm.choose(); await vm.move(1); await vm.markCurrent();
    assert.equal(vm.session.index, 1); assert.equal(vm.batchEnded, true); assert.equal(vm.showSummary, false); assert.equal(env.marks[0].reference, 'reference-B');
    await vm.unmark('reference-B'); assert.equal(env.marks.length, 0); assert.equal(vm.currentMarked(), false);
  });
  await test('swiping back to marked photo then down preserves it without changing position',async()=>{
    const {vm,env}=makeVm();await vm.choose();await vm.gesture(0,-100);await vm.move(-1);
    assert.equal(vm.currentMarked(),true);await vm.gesture(0,100);assert.equal(vm.session.index,0);assert.equal(vm.currentMarked(),false);assert.equal(env.marks.length,0);
  });
  await test('reclassification clears deletion mark only after destination has been saved',async()=>{
    const {vm,env}=makeVm();await vm.choose();await vm.markCurrent();await vm.move(-1);
    env.moveResult={id:'new',phase:'awaiting_trash',targetName:'旅行',source:{uri:'reference-A'},copy:{uri:'copy-A'}};
    await vm.organize('C');assert.equal(env.marks.length,1);await vm.saveLastClassification();assert.equal(env.marks.length,0);assert.equal(vm.classificationLabel('reference-A'),'已分类：旅行');
  });
  await test('ambiguous diagonals short movement and downward gestures never mark', async () => {
    const { vm, env } = makeVm(); await vm.choose();
    for (const [x, y] of [[0,-79], [80,-80], [0,100], [59,0], [NaN,-100]]) await vm.gesture(x, y);
    assert.equal(vm.session.index, 0); assert.equal(env.markCalls, 0);
    await vm.gesture(-80, 10); assert.equal(vm.session.index, 1); assert.equal(env.markCalls, 0);
    await vm.gesture(0, -100); assert.equal(env.markCalls, 1); assert.equal(env.marks[0].reference, 'reference-B');
  });
  await test('unreadable or failed-preview photo cannot be marked', async () => {
    const { vm, env } = makeVm(); await vm.choose(); vm.imageFailed(vm.displayedId); await vm.markCurrent();
    assert.equal(env.markCalls, 0); env.fail = 'reference-A'; await vm.recheck(); await vm.markCurrent(); assert.equal(env.markCalls, 0);
  });
  await test('closing page during marker save does not assign a new photo or cancel committed marker', async () => {
    const { vm, env } = makeVm(); await vm.choose(); env.holdMark = true; const pending = vm.markCurrent();
    vm.dispose(); env.finishMark(); await pending; assert.equal(vm.photo, undefined); assert.equal(vm.session.index, 0);
    assert.equal(env.marks[0].reference, 'reference-A');
  });
  await test('clicking bound target does not claim move success advance or mark the image', async () => {
    const {vm,env}=makeVm(); await vm.choose(); env.categories.categories=[{id:'C',name:'旅游',album:{kind:'album',reference:'opaque:A',name:'A'}}];
    await vm.refreshCategories(); const id=vm.session.current().id; vm.checkCategory('C');
    assert.equal(vm.session.current().id,id); assert.equal(vm.session.index,0); assert.equal(env.markCalls,0);
    assert.match(vm.message,/仅预览/);
  });
  await test('missing album binding and unreadable photos stay blocked without advancing', async () => {
    const {vm,env}=makeVm(); await vm.choose(); env.categories.categories=[{id:'C',name:'旅游'}];
    await vm.refreshCategories();  vm.checkCategory('C'); assert.match(vm.message,/尚未绑定系统相册/);
    vm.imageFailed(vm.displayedId); vm.checkCategory('C'); assert.match(vm.message,/不可读取/); assert.equal(vm.session.index,0);
  });
  await test('category storage failure does not block independent photo browsing', async () => {
    const {vm,env}=makeVm(); await vm.choose(); env.failCategories=true; await vm.refreshCategories();
    assert.equal(vm.categoriesReady,false); await vm.move(1); assert.equal(vm.session.index,1); assert.equal(vm.photo.uri,'reference-B');
  });
  await test('bulk gallery trash preserves historical document marks and never forwards their references',async()=>{
    const {vm,env}=makeVm();await vm.choose();env.marks=[{reference:'reference-A',name:'A'},{reference:'file://docs/legacy/old.jpg',name:'legacy'}];await vm.refreshMarks();
    await vm.trashMarked();assert.deepEqual(env.trashRequests,[['reference-A']]);assert.deepEqual(vm.marks.map(item=>item.reference),['file://docs/legacy/old.jpg']);
  });
  await test('confirmed missing or changed current photo is skipped without substituting its URI',async()=>{
    for(const state of ['missing','changed','not_image']){const {vm,env}=makeVm();env.fail='reference-A';env.availability={'reference-A':state};await vm.choose();assert.equal(vm.photo.uri,'reference-B');assert.equal(vm.session.items.some(item=>item.reference==='reference-A'),false);}
  });
  await test('lost access and normal preview decode failures keep the current logical photo instead of assuming deletion',async()=>{
    const {vm,env}=makeVm();env.fail='reference-A';await vm.choose();assert.equal(vm.session.current().reference,'reference-A');assert.equal(vm.photo,undefined);
    env.fail='';env.availability={'reference-A':'ready'};await vm.recheck();const id=vm.displayedId;vm.imageFailed(id,'reference-A');await new Promise(r=>setImmediate(r));assert.equal(vm.session.current().id,id);assert.equal(vm.photo,undefined);
  });
  await test('late invalid-reference result cannot skip the next photo after navigation',async()=>{
    const {vm,env}=makeVm();await vm.choose();env.holdAvailability=true;env.availability={'reference-A':'missing'};vm.imageFailed(vm.displayedId,'reference-A');while(!env.finishAvailability)await Promise.resolve();await vm.move(1);env.finishAvailability();await new Promise(r=>setImmediate(r));assert.equal(vm.photo.uri,'reference-B');assert.equal(vm.session.current().reference,'reference-B');
  });
  await test('an entirely deleted gallery page automatically continues to its next available page',async()=>{
    const {vm,env}=makeVm();env.pages=[['A','B'],['C']];env.failReferences=['A','B'];env.availability={A:'missing',B:'missing'};await vm.loadLibrary();assert.equal(vm.photo.uri,'C');assert.equal(vm.hasMore,false);assert.equal(vm.busy,false);
  });
  await test('invalid last photo continues to the next page rather than re-showing the previous photo',async()=>{
    const {vm,env}=makeVm();env.pages=[['A','B'],['C']];env.fail='B';env.availability={B:'missing'};await vm.loadLibrary();await vm.move(1);assert.equal(vm.photo.uri,'C');assert.deepEqual(env.calls,['A','B','C']);
  });
  await test('invalid final photo ends browsing without looping and explicit return can review prior valid photos',async()=>{
    const {vm,env}=makeVm();env.selected=['reference-A','reference-B'];env.fail='reference-B';env.availability={'reference-B':'missing'};await vm.choose();await vm.move(1);assert.equal(vm.batchEnded,true);assert.equal(vm.photo,undefined);assert.deepEqual(env.calls,['reference-A','reference-B']);await vm.returnToBatch();assert.equal(vm.photo.uri,'reference-A');assert.equal(vm.batchEnded,false);
  });
  console.log(`${passed}/${passed} host photo browsing and marker tests passed. Native selection, persistence and gestures still require device validation.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
