import assert from 'node:assert/strict';
import {File} from 'node:buffer';
import {webcrypto} from 'node:crypto';
globalThis.crypto??=webcrypto;
for(const scenario of ['success','photo-guard-video','bad-range','stuck-video','processing-upload','missing-body']){
 const elements=new Map();const element=()=>({textContent:'',disabled:false,hidden:false,append(){},replaceChildren(){},addEventListener(){}});
 for(const id of ['files','start','stop','status','preview','manualIntro','diagnosticLog'])elements.set(id,element());
 globalThis.document={getElementById:id=>elements.get(id),createElement:element};globalThis.File=File;
 const job='11111111-1111-1111-1111-111111111111';globalThis.location=new URL(`chrome-extension://${'a'.repeat(32)}/posting.html?job=${job}`);
 const packet={type:'blog-assistant.naver-post',version:3,blogID:'bluedog129',categoryNo:'65',title:'PRIVATE TITLE',blocks:[{kind:'text',text:'BEFORE'},{kind:'photo',photoNumber:1},{kind:'text',text:'BETWEEN'},{kind:'video',photoNumber:2},{kind:'text',text:'AFTER VIDEO'},{kind:'photo',photoNumber:3}],photos:[{number:1,filename:'01_private.jpg',caption:'PRIVATE CAPTION'},{number:2,filename:'02_private.mp4',caption:'PRIVATE VIDEO',mediaType:'video',byteCount:3},{number:3,filename:'03_private.jpg',caption:'PRIVATE CAPTION'}]};
 const state={ready:true,title:'',texts:[''],imageCount:0,videoCount:0,videoReadyCount:0,components:[],fileInputCount:0,saveSignals:[],temporaryCount:'0',uploadDiagnostics:{imageReadyCount:0,uploadBusy:false}};
 const uploader={open:false,hasAdd:false,completeEnabled:false,titleEmpty:false,uploadReady:false};
 const reports=[],events=new Set(),chunks=[];let focus,saveClicks=0,detached=false,chooserOpened=false,photoGuardActive=false;
 globalThis.fetch=async(url,options={})=>{
  if(url.endsWith('/claim'))return new Response(JSON.stringify(packet));
  if(url.endsWith('/active'))return new Response('active');
  if(url.endsWith('/photos/2')){
   assert.equal(chooserOpened,true,'No video bytes should be loaded until the input is ready');
   assert.equal(options.headers.Range,'bytes=0-2');
   return new Response(new Uint8Array([1,2,3]),{status:scenario==='bad-range'?200:206,headers:{'Content-Range':'bytes 0-2/3'}});
  }
  if(url.includes('/photos/'))return new Response(new Uint8Array([4,5,6]));
  if(url.endsWith('/status')){reports.push(JSON.parse(options.body));return new Response('ok');}
  throw new Error('Unexpected endpoint');
 };
 globalThis.chrome={storage:{local:{get:async()=>({appBridgeToken:'PRIVATE TOKEN'}),set:async()=>{}}},tabs:{create:async()=>({id:123})},scripting:{executeScript:async({func,args})=>{
  if(func.name==='inspectEditor')return[{result:structuredClone(state)}];
  if(func.name==='inspectVideoUploader')return[{result:{...uploader}}];
  if(func.name==='videoUploadPoint'){focus='video-'+args[1];return[{result:{x:1,y:1}}];}
  if(func.name==='editorPoint'){focus=args[1];return[{result:{x:1,y:1}}];}
  if(func.name==='preparePhotoUpload'){photoGuardActive=true;return[{result:{}}];}
  if(func.name==='supplyPhoto'){state.fileInputCount=0;state.imageCount++;state.uploadDiagnostics.imageReadyCount=state.imageCount;state.components.push({kind:'photo',text:''});return[{result:true}];}
  if(func.name==='supplyVideoChunk'){chunks.push(args);uploader.completeEnabled=scenario!=='processing-upload';uploader.uploadReady=scenario!=='processing-upload';return[{result:3}];}
  if(func.name==='restorePhotoPicker'){photoGuardActive=false;return[{result:true}];}
  if(func.name==='clearVideoTransfer')return[{result:true}];
  throw new Error(`Unexpected function ${func.name}`);
 }},debugger:{attach:async()=>{},detach:async()=>{detached=true;},onDetach:{addListener(){}},onEvent:{addListener:fn=>events.add(fn),removeListener:fn=>events.delete(fn)},sendCommand:async(_target,method,params)=>{
  if(method==='Input.insertText'){
   if(focus==='title')state.title=params.text;
   else{state.texts.push(params.text);state.components.push({kind:'text',text:params.text});}
  }
  if(method==='Input.dispatchMouseEvent'&&params.type==='mouseReleased'){
   if(focus==='photo')state.fileInputCount=1;
   if(focus==='video-toolbar'){uploader.open=true;uploader.hasAdd=true;}
   if(focus==='video-add'&&!(scenario==='photo-guard-video'&&photoGuardActive)){chooserOpened=true;for(const listener of events)listener({tabId:123},'Page.fileChooserOpened',{backendNodeId:7});}
   if(focus==='video-complete'){uploader.open=false;state.videoCount=1;state.videoReadyCount=scenario==='stuck-video'?0:1;state.components.push({kind:'video',text:''});if(scenario!=='missing-body'){state.components.push({kind:'text',text:''});state.bodyPoint={x:1,y:2};}}
   if(focus==='save'){saveClicks++;state.saveSignals=['저장 완료'];}
  }
 }}};
 const originalTimeout=globalThis.setTimeout,originalNow=Date.now;let now=0;
 globalThis.setTimeout=(callback,ms)=>{if(ms===15000)return originalTimeout(callback,100);now+=ms;queueMicrotask(callback);return 0;};Date.now=()=>now;
 try{
  await import(`../chrome-extension/posting.js?video=${scenario}`);
  for(let i=0;i<100&&!detached;i++)await new Promise(resolve=>scenario==='photo-guard-video'?originalTimeout(resolve,5):setImmediate(resolve));
  const result=reports.find(r=>['success','failure'].includes(r.state));assert.ok(result,scenario);assert.equal(events.size,0);
  if(scenario==='success'||scenario==='photo-guard-video'){
   assert.equal(result.state,'success',`${scenario}: ${result.message}`);assert.equal(chunks.length,1);assert.equal(chunks[0][3],0);assert.equal(chunks[0][5],true);assert.equal(saveClicks,1);
   assert.deepEqual(state.components.filter(x=>['photo','video'].includes(x.kind)).map(x=>x.kind),['photo','video','photo']);
  }else{
   assert.equal(result.state,'failure');assert.equal(saveClicks,0);assert.ok(!state.components.some(x=>x.text==='AFTER VIDEO'));
   assert.match(result.message,scenario==='bad-range'?/전달 범위/:scenario==='processing-upload'?/영상 업로드가 완료/:scenario==='missing-body'?/영상 뒤의 빈 본문/:/영상 첨부 결과/);
  }
 }finally{globalThis.setTimeout=originalTimeout;Date.now=originalNow;}
}
console.log('Passed actual mixed-media posting flow, deferred bounded video transfer, exact ordering, incomplete-video and corrupt-range save prevention');
