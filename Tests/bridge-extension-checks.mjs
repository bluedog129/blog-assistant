import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {File} from 'node:buffer';
const require=createRequire(import.meta.url);
const {JSDOM}=require(process.env.EXTENSION_TEST_JSDOM||'/tmp/blog-assistant-extension-check/node_modules/jsdom');
const id='11111111-1111-1111-1111-111111111111';
const dom=new JSDOM('<input id="files"><button id="start"></button><button id="stop"></button><p id="status"></p><section id="preview"></section>',{url:`chrome-extension://${'a'.repeat(32)}/posting.html?job=${id}`});
globalThis.document=dom.window.document;globalThis.location=dom.window.location;globalThis.File=File;
const packet={type:'blog-assistant.naver-post',version:1,blogID:'bluedog129',categoryNo:'65',title:'테스트 글',blocks:[{kind:'text',text:'첫 문단'},{kind:'photo',photoNumber:1},{kind:'text',text:'감상'}],photos:[{number:1,filename:'01_사진.jpg',caption:'사진'}]};
const token='a'.repeat(64);
const reports=[];let claims=0, focus=null, detached=null, inspections=0;
const state={ready:true,title:'',texts:[''],imageCount:0,components:[],fileInputCount:1,saveSignals:[],temporaryCount:'0'};
globalThis.fetch=async(url,options={})=>{
 assert.ok(url.startsWith(`http://127.0.0.1:48765/jobs/${id}/`));
 assert.equal(options.headers['X-Blog-Assistant-Token'],token);
 if(url.endsWith('/claim')){claims++;return new Response(JSON.stringify(packet));}
 if(url.endsWith('/photos/1'))return new Response(new Uint8Array([1,2,3]),{headers:{'Content-Type':'image/jpeg'}});
 if(url.endsWith('/status')){reports.push(JSON.parse(options.body));return new Response('ok');}
 throw new Error('Unexpected endpoint');
};
globalThis.chrome={
 storage:{local:{get:async()=>({appBridgeToken:token})}},
 tabs:{create:async({url})=>{assert.ok(url.includes('blogId=bluedog129'));return{id:123};}},
 scripting:{executeScript:async({func,args})=>{
   if(func.name==='inspectEditor'){inspections++;return[{result:{...structuredClone(state),recoveryPrompt:inspections<=2}}];}
   if(func.name==='editorPoint'){focus=args[1];return[{result:{x:10,y:10}}];}
   if(func.name==='restorePhotoPicker')return[{result:true}];
   if(func.name==='openPhotoUpload'){state.fileInputCount=1;return[{result:true}];}
   if(func.name==='supplyPhoto'){state.fileInputCount=0;state.imageCount++;state.components.push({kind:'photo',text:''});return[{result:true}];}
   throw new Error('Unexpected injected function');
 }},
 debugger:{attach:async()=>{},detach:async()=>{detached?.({tabId:123});},onDetach:{addListener:fn=>{detached=fn;}},sendCommand:async(target,method,params)=>{
   if(method==='Input.insertText'){
     if(focus==='title')state.title=params.text;
     else {state.texts.push(params.text);state.components.push({kind:'text',text:params.text});}
   }
   if(method==='Input.dispatchMouseEvent'&&params.type==='mouseReleased'&&focus==='save')state.saveSignals=['임시저장 완료'];
 }}
};
await import('../chrome-extension/posting.js');
for(let i=0;i<500&&!reports.some(r=>r.state==='success');i++)await new Promise(r=>setTimeout(r,20));
assert.equal(claims,1);
assert.ok(reports.some(r=>r.message.includes('이전 작성 글 안내')));
assert.ok(reports.some(r=>r.state==='success'));
await new Promise(r=>setTimeout(r,20));
assert.ok(document.getElementById('status').textContent.includes('네이버 임시저장 완료'));
assert.equal(document.getElementById('files').hidden,true);
assert.equal(document.getElementById('start').disabled,true);
console.log('Passed automatic app job receive, image fetch, editor sequencing, result callback, clean detach and duplicate-start prevention');
