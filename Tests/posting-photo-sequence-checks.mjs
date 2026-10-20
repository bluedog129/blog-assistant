import assert from 'node:assert/strict';
import {File} from 'node:buffer';

// Run the actual posting module with ten photos. No browser, network or DOM package is needed.
for(const scenario of ['slow-upload-success','stuck-upload','missing-input-8','inspection-error-8','success']) {
  const elements=new Map();
  const element=()=>({textContent:'',disabled:false,hidden:false,append(){},replaceChildren(){},addEventListener(){}});
  for(const id of ['files','start','stop','status','preview','manualIntro','diagnosticLog'])elements.set(id,element());
  globalThis.document={getElementById:id=>elements.get(id),createElement:element};
  const job='11111111-1111-1111-1111-111111111111';
  globalThis.location=new URL(`chrome-extension://${'a'.repeat(32)}/posting.html?job=${job}`);
  globalThis.File=File;
  const blocks=[{kind:'text',text:'PRIVATE ARTICLE'},...Array.from({length:10},(_,i)=>({kind:'photo',photoNumber:i+1})),{kind:'text',text:'AFTER PHOTOS'}];
  const packet={type:'blog-assistant.naver-post',version:1,blogID:'bluedog129',categoryNo:'65',title:'PRIVATE TITLE',blocks,
    photos:Array.from({length:10},(_,i)=>({number:i+1,filename:`${String(i+1).padStart(2,'0')}_private.jpg`,caption:'PRIVATE CAPTION'}))};
  const state={ready:true,title:'',texts:[''],imageCount:0,components:[],fileInputCount:0,saveSignals:[],temporaryCount:'0',
    uploadDiagnostics:{photoButton:{disabled:false,visible:true},fileInputs:[],imageReadyCount:0,uploadBusy:false}};
  const reports=[],uploads=[],saved=[];let focus=null,opened=0,saveClicks=0,detached=false,pendingPolls=0;
  globalThis.fetch=async(url,options={})=>{
    if(url.endsWith('/claim'))return new Response(JSON.stringify(packet));
    if(url.endsWith('/active'))return new Response('active');
    if(url.includes('/photos/'))return new Response(new Uint8Array([1,2,3]));
    if(url.endsWith('/status')){reports.push(JSON.parse(options.body));return new Response('ok');}
    throw new Error('Unexpected endpoint');
  };
  globalThis.chrome={storage:{local:{get:async()=>({appBridgeToken:'PRIVATE TOKEN'}),set:async value=>saved.push(value)}},
    tabs:{create:async()=>({id:123})},
    scripting:{executeScript:async({func,args})=>{
      if(func.name==='inspectEditor'){
        if(pendingPolls>0&&scenario!=='stuck-upload'&&--pendingPolls===0){state.uploadDiagnostics.imageReadyCount=state.imageCount;state.uploadDiagnostics.uploadBusy=false;}
        if(opened===8&&scenario==='inspection-error-8')throw new Error('Editor frame unavailable');
        return [{result:structuredClone(state)}];
      }
      if(func.name==='editorPoint'){focus=args[1];return [{result:{x:1,y:1}}];}
      if(func.name==='preparePhotoUpload')return [{result:{fileInputCountBefore:state.fileInputCount}}];
      if(func.name==='supplyPhoto'){
        uploads.push(args[0]);state.fileInputCount=0;state.imageCount++;
        if(scenario==='slow-upload-success'||scenario==='stuck-upload'){pendingPolls=8;state.uploadDiagnostics.uploadBusy=true;}
        else state.uploadDiagnostics.imageReadyCount=state.imageCount;
        state.components.push({kind:'photo',text:''});return [{result:true}];
      }
      if(func.name==='restorePhotoPicker')return [{result:true}];
      throw new Error(`Unexpected script: ${func.name}`);
    }},
    debugger:{attach:async()=>{},detach:async()=>{detached=true;},onDetach:{addListener(){}},sendCommand:async(_target,method,params)=>{
      if(method==='Input.insertText'){
        if(focus==='title')state.title=params.text;
        else{state.texts.push(params.text);state.components.push({kind:'text',text:params.text});}
      }
      if(method==='Input.dispatchMouseEvent'&&params.type==='mouseReleased'&&focus==='save'){saveClicks++;state.saveSignals=['저장 완료'];}
      if(method==='Input.dispatchMouseEvent'&&params.type==='mouseReleased'&&focus==='photo'){
        opened++;
        assert.equal(state.uploadDiagnostics.uploadBusy,false,'The next photo must wait for the previous upload to finish');
        state.fileInputCount=opened===8&&scenario==='missing-input-8'?0:1;
      }
    }}
  };
  const originalTimeout=globalThis.setTimeout,originalNow=Date.now;let now=0;
  globalThis.setTimeout=(callback,ms)=>{now+=ms;queueMicrotask(callback);return 0;};Date.now=()=>now;
  try {
    await import(`../chrome-extension/posting.js?photo-sequence=${scenario}`);
    for(let n=0;n<30&&(!detached||!saved.at(-1)?.lastPostingDiagnostics.events.some(e=>e.event==='success'||e.event==='failure'));n++)await new Promise(resolve=>setImmediate(resolve));
    const terminal=reports.find(r=>r.state==='failure'||r.state==='success');assert.ok(terminal,scenario);
    assert.equal(detached,true);
    if(scenario==='success'||scenario==='slow-upload-success'){
      assert.equal(terminal.state,'success');assert.equal(uploads.length,10);assert.equal(saveClicks,1);
    }else if(scenario==='stuck-upload'){
      assert.equal(terminal.state,'failure');assert.match(terminal.message,/사진 1\/10.*사진 업로드 완료 대기/);
      assert.equal(uploads.length,1);assert.equal(opened,1);assert.equal(saveClicks,0);
    }else{
      assert.equal(terminal.state,'failure');assert.match(terminal.message,/사진 8\/10.*사진 입력창 대기/);
      assert.equal(uploads.length,7);assert.equal(saveClicks,0);
      if(scenario==='inspection-error-8')assert.match(terminal.message,/Editor frame unavailable/);
      else assert.match(terminal.message,/업로드 입력창 0개 · 사진 7장/);
      assert.ok(!state.components.some(b=>b.text==='AFTER PHOTOS'));
    }
    assert.equal(elements.get('start').disabled,true); // An app job cannot be started twice.
    const log=JSON.stringify(saved);
    for(const secret of ['PRIVATE ARTICLE','PRIVATE TITLE','PRIVATE CAPTION','PRIVATE TOKEN','private.jpg'])assert.ok(!log.includes(secret),secret);
    assert.ok(elements.get('diagnosticLog').textContent.includes(terminal.state));
    console.log(`Passed ten-photo posting: ${scenario}; uploads=${uploads.length}, saveClicks=${saveClicks}`);
  } finally {globalThis.setTimeout=originalTimeout;Date.now=originalNow;}
}
