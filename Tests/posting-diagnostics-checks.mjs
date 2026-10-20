import assert from 'node:assert/strict';
import {waitForEditor,createPostingDiagnostics,editorSummary} from '../chrome-extension/posting-diagnostics.js';

const state={ready:true,imageCount:7,fileInputCount:0,texts:['PRIVATE POST'],title:'PRIVATE TITLE',
  uploadDiagnostics:{photoButton:{disabled:false,ariaDisabled:null,visible:true},fileInputs:[]}};
async function failedWait(inspect) {
  let now=0;
  const diagnostics=createPostingDiagnostics();diagnostics.start();
  diagnostics.stage({photoNumber:8,photoTotal:10,stage:'사진 입력창 대기'});
  let error;
  try{await waitForEditor({inspect,test:s=>s.fileInputCount>0,message:'사진 선택창을 확인하지 못했습니다.',
    now:()=>now,delay:async ms=>{now+=ms;},record:diagnostics.record});}catch(value){error=value;}
  assert.equal(now,30000);
  assert.match(diagnostics.failureMessage(error),/사진 8\/10.*사진 입력창 대기/);
  assert.ok(diagnostics.snapshot().events.some(e=>e.event==='wait-timeout'));
  return {error,diagnostics};
}
const missing=await failedWait(async()=>state);
assert.match(missing.error.message,/업로드 입력창 0개 · 사진 7장/);
assert.match(missing.error.message,/사진 버튼 활성/);
assert.equal(missing.error.cause,undefined);
assert.equal(missing.diagnostics.snapshot().events.filter(e=>e.event==='wait-state').length,1);

const original=new Error('Cannot access editor frame');
const broken=await failedWait(async()=>{throw original;});
assert.equal(broken.error.cause,original);
assert.match(broken.error.message,/마지막 원래 오류: Cannot access editor frame/);
assert.match(broken.error.message,/조회 실패 75회/);
assert.equal(broken.diagnostics.snapshot().events.filter(e=>e.event==='inspection-error').length,1);
assert.equal(broken.diagnostics.snapshot().events.at(-1).details.inspectionFailures,75);

// A transient failure may recover; a cancellation must stop without another poll.
let attempts=0, clock=0;
const ready=await waitForEditor({inspect:async()=>{if(++attempts===1)throw original;return {...state,fileInputCount:1};},
  test:s=>s.fileInputCount>0,message:'timeout',now:()=>clock,delay:async ms=>{clock+=ms;}});
assert.equal(attempts,2);assert.equal(ready.fileInputCount,1);
await assert.rejects(waitForEditor({inspect:async()=>{throw original;},test:()=>false,message:'timeout',isStopped:()=>true}),e=>e===original);
let polls=0;
await assert.rejects(waitForEditor({check:()=>{throw new Error('cancelled');},inspect:async()=>{polls++;},test:()=>false,message:'timeout'}),/cancelled/);
assert.equal(polls,0);

// Serialized persistence retains the final failure and stays bounded; no article content is stored.
const saved=[];
const journal=createPostingDiagnostics({limit:4,save:async value=>{saved.push(value);}});
journal.start();journal.stage({photoNumber:8,photoTotal:10,stage:'사진 입력창 대기'});
for(let i=0;i<8;i++)journal.record('state',{state:editorSummary(state)});
journal.record('failure',{error:{message:'missing input'}});await journal.flush();
assert.equal(saved.at(-1).events.length,4);
assert.equal(saved.at(-1).events.at(-1).event,'failure');
assert.ok(!JSON.stringify(saved).includes('PRIVATE'));
assert.ok(!JSON.stringify(saved).includes('texts'));
journal.start();await journal.flush();
assert.equal(journal.snapshot().events.length,1);assert.deepEqual(journal.snapshot().context,{});
const unavailable=createPostingDiagnostics({save:async()=>{throw new Error('storage unavailable');}});
unavailable.start();await unavailable.flush();
console.log('Passed missing input vs original inspection error, transient recovery, cancellation, bounded serialized local diagnostics and content exclusion');
