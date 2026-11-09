const assert=require('node:assert/strict');
const path=require('node:path');
const {createLoader}=require('./ets-test-runtime.cjs');
const {DropZone,hitDropTarget}=createLoader()(path.resolve(__dirname,'../entry/src/main/ets/domain/usecases/DropTarget.ets'));
const zones=[new DropZone('A',10,200,80,80),new DropZone('B',100,200,80,80),new DropZone('C',190,200,80,80)];
const tests=[
  ['each folder is selected by its actual bounds',()=>{assert.equal(hitDropTarget(zones,50,240),'A');assert.equal(hitDropTarget(zones,140,240),'B');assert.equal(hitDropTarget(zones,230,240),'C');}],
  ['gaps and releases outside folders never select a category',()=>{for(const [x,y] of [[95,240],[50,190],[50,281],[500,240]])assert.equal(hitDropTarget(zones,x,y),'');}],
  ['shared boundary belongs only to the following folder',()=>{assert.equal(hitDropTarget([new DropZone('A',0,0,50,50),new DropZone('B',50,0,50,50)],50,20),'B');}],
  ['overlapping zones are ambiguous and cannot select a category',()=>{assert.equal(hitDropTarget([...zones,new DropZone('overlap',10,200,80,80)],50,240),'');}],
  ['invalid coordinates and zero-size zones are rejected',()=>{assert.equal(hitDropTarget(zones,NaN,240),'');assert.equal(hitDropTarget([new DropZone('A',0,0,0,10)],0,5),'');}],
  ['layout updates replace old positions without guessing from swipe direction',()=>{assert.equal(hitDropTarget([new DropZone('A',300,400,80,80)],50,240),'');assert.equal(hitDropTarget([new DropZone('A',300,400,80,80)],320,420),'A');}]
];
for(const [name,test] of tests){test();console.log('PASS '+name);}
console.log('6/6 drop hit tests passed. No media operation performed.');
