import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync('chrome-extension/posting.js','utf8');
const guardCode=source.slice(source.indexOf('async function checkActiveJob('),source.indexOf('async function inspect('));
const commandCode=source.slice(source.indexOf('async function command('),source.indexOf('async function click('));
let requests=[], operations=[], fail=false, stopDuringCheck=false;
const context=vm.createContext({
 bridgeClaimed:true, bridgeJob:'current', stopped:false, tabID:42,
 bridgeFetch:async path=>{
   requests.push(path);
   if(fail)throw new Error('404 / disconnected');
   if(stopDuringCheck)context.stopped=true;
 },
 chrome:{
   scripting:{executeScript:async value=>{operations.push(['script',value]);return [{result:'ok'}];}},
   debugger:{sendCommand:async(...args)=>{operations.push(['command',...args]);}}
 }
});
vm.runInContext(`function check(){if(stopped)throw new Error('중단했습니다.');}\n${guardCode}\n${commandCode}`,context);
await vm.runInContext("command('Input.insertText',{text:'본문'})",context);
assert.deepEqual(requests,['/jobs/current/active']);
assert.equal(operations.length,1);
assert.equal(await vm.runInContext('execute(()=>{},[])',context),'ok');
assert.equal(requests.length,2);
assert.equal(operations.length,2);

// Neither a late script nor a late native input may resume an invalid app job.
for(const operation of ["command('Input.insertText',{text:'지연 입력'})",'execute(()=>{},[])']){
 context.stopped=false;fail=true;
 await assert.rejects(vm.runInContext(operation,context),/앱 작업이 중단/);
 assert.equal(context.stopped,true);
 assert.equal(operations.length,2);
}
fail=false;context.stopped=false;stopDuringCheck=true;
await assert.rejects(vm.runInContext("command('Input.insertText',{text:'중단 직후'})",context),/중단했습니다/);
assert.equal(operations.length,2);

// Manual file import does not require an app bridge.
context.stopped=false;context.bridgeClaimed=false;
const before=requests.length;
await vm.runInContext("command('Input.insertText',{text:'수동 입력'})",context);
assert.equal(requests.length,before);
assert.equal(operations.length,3);
console.log('Passed active-job checks before editor scripts/native input, cancellation during checks, lost connection and manual import');
