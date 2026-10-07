import {validatePacket,inspectEditor,supplyPhoto,openPhotoUpload,restorePhotoPicker,editorPoint,validateContent} from './post-packet.js';
const $=id=>document.getElementById(id);
let packet=null, files=new Map(), running=false, stopped=false, tabID=null, attached=false;
let bridgeToken=null, bridgeJob=null, bridgeClaimed=false, reportQueue=Promise.resolve();
async function bridgeFetch(path, options={}) {
  const response=await fetch('http://127.0.0.1:48765'+path,{...options,headers:{'X-Blog-Assistant-Token':bridgeToken,...options.headers},signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw new Error(`앱 연결 오류 (${response.status}). 연결 설정 또는 진행 중인 작업을 확인하세요.`);
  return response;
}
function report(state,message){
  if(!bridgeClaimed)return Promise.resolve();
  reportQueue=reportQueue.catch(()=>{}).then(()=>bridgeFetch(`/jobs/${bridgeJob}/status`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({state,message})}));
  return reportQueue;
}
const status=message=>{$('status').textContent=message;if(running)void report('progress',message).catch(()=>{});};
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const normalize=text=>text.replace(/[\u200b\ufeff]/g,'').replace(/\s+/g,' ').trim();
function check(){if(stopped)throw new Error('중단했습니다. 편집기 탭에 입력된 내용은 남아 있습니다.');}
async function execute(func,args){check();const result=await chrome.scripting.executeScript({target:{tabId:tabID},func,args});return result[0]?.result;}
async function inspect(){return execute(inspectEditor,[packet.blogID]);}
async function pointFor(kind){
 await command('Page.bringToFront');
 await execute(editorPoint,[packet.blogID,kind]);
 await delay(300);
 return execute(editorPoint,[packet.blogID,kind]);
}
async function command(method,params={}){check();await chrome.debugger.sendCommand({tabId:tabID},method,params);}
async function click(point){if(!point)throw new Error('편집기 버튼·입력 위치를 확인하지 못했습니다.');await command('Input.dispatchMouseEvent',{type:'mousePressed',x:point.x,y:point.y,button:'left',clickCount:1});await command('Input.dispatchMouseEvent',{type:'mouseReleased',x:point.x,y:point.y,button:'left',clickCount:1});await delay(250);}
async function key(name,code,vk){await command('Input.dispatchKeyEvent',{type:'keyDown',key:name,code,windowsVirtualKeyCode:vk});await command('Input.dispatchKeyEvent',{type:'keyUp',key:name,code,windowsVirtualKeyCode:vk});}
async function insertBodyText(text) {
 const lines=text.replace(/\r\n?/g,'\n').split('\n');
 for(let i=0;i<lines.length;i++) {
   if(i) { await key('Enter','Enter',13); await delay(100); }
   // SmartEditor drops multiline insertText and can truncate after emoji.
   const parts=lines[i].match(/[\u{10000}-\u{10FFFF}]|[^\u{10000}-\u{10FFFF}]+/gu)||[];
   for(const part of parts) { await command('Input.insertText',{text:part}); await delay(100); }
 }
}
async function waitFor(test,message,timeout=30000){const start=Date.now();while(Date.now()-start<timeout){check();try{const state=await inspect();if(test(state))return state;}catch(error){if(stopped)throw error;}await delay(400);}throw new Error(message);}
$('files').addEventListener('change',async()=>{
 packet=null;$('start').disabled=true;$('preview').replaceChildren();
 try{
   const selected=[...$('files').files];files=new Map();
   for(const file of selected){if(files.has(file.name))throw new Error('같은 이름의 파일을 두 개 선택했습니다.');files.set(file.name,file);}
   const json=files.get('naver-post.json');if(!json||json.size>1000000)throw new Error('naver-post.json과 사진 파일들을 함께 선택하세요.');
   packet=validatePacket(JSON.parse(await json.text()),files);
   const title=document.createElement('h2');title.textContent=packet.title;$('preview').append(title);
   for(const block of packet.blocks){const p=document.createElement('p');p.textContent=block.kind==='text'?block.text:`[사진 ${block.photoNumber}] ${packet.photos[block.photoNumber-1].caption}`;$('preview').append(p);}
   status(`bluedog129 / 맛집탐방 · 사진 ${packet.photos.length}장 준비 완료`);$('start').disabled=false;
 }catch(error){status(error.message);}
});
$('stop').addEventListener('click',()=>{stopped=true;status('중단 요청 중…');});
async function runPosting(){
 if(running||!packet)return;
 running=true;stopped=false;$('start').disabled=true;$('files').disabled=true;$('stop').disabled=false;
 try{
   const tab=await chrome.tabs.create({url:`https://blog.naver.com/PostWriteForm.naver?blogId=${encodeURIComponent(packet.blogID)}&Redirect=Write&categoryNo=${packet.categoryNo}`,active:true});tabID=tab.id;
   await waitFor(s=>{
     if(s.recoveryPrompt) { status('이전 작성 글 안내가 열려 있습니다. 기존 글을 보관할지 확인한 뒤 직접 새 글 작성을 선택하세요. 안내가 닫히면 자동으로 계속합니다.'); return false; }
     return s.ready;
   },'이전 작성 글 안내 또는 로그인 화면 때문에 시작하지 못했습니다. 기존 글을 보관한 뒤 빈 새 글에서 다시 시도하세요.',180000);
   await chrome.debugger.attach({tabId:tabID},'1.3');attached=true;
   await command('Page.setInterceptFileChooserDialog',{enabled:true});
   let state=await inspect();
   if(state.title||state.texts.some(t=>t)||state.imageCount)throw new Error('이전 작성 글이 열린 상태입니다. 기존 글을 저장하거나 보관한 뒤 빈 새 글로 다시 시도하세요. 기존 내용을 덮어쓰지 않았습니다.');
   await delay(800);
   status('제목 입력 중…');await click(await pointFor('title'));await command('Input.insertText',{text:packet.title});
   await waitFor(s=>normalize(s.title)===normalize(packet.title),'제목 입력을 확인하지 못했습니다.');
   await key('Enter','Enter',13);await delay(400);
   state=await inspect();await click(await pointFor('body'));
   for(let i=0;i<packet.blocks.length;i++){
     check();const block=packet.blocks[i];status(`본문 입력 ${i+1}/${packet.blocks.length}`);
     if(block.kind==='text'){
       await insertBodyText(block.text);
       await delay(200);await key('Enter','Enter',13);await key('Enter','Enter',13);
     }else{
       state=await inspect();const count=state.imageCount;
       await execute(openPhotoUpload,[packet.blogID]);
       await waitFor(s=>s.fileInputCount>0,'사진 선택창을 확인하지 못했습니다.');
       const file=files.get(packet.photos[block.photoNumber-1].filename);
       const bytes=new Uint8Array(await file.arrayBuffer());
       let binary='';for(let n=0;n<bytes.length;n+=32768)binary+=String.fromCharCode(...bytes.subarray(n,n+32768));
       await execute(supplyPhoto,[file.name,btoa(binary)]);
       await waitFor(s=>s.imageCount===count+1,'사진 업로드가 완료되지 않았습니다. 임시저장은 하지 않았습니다.',90000);
       await key('Escape','Escape',27);await key('ArrowDown','ArrowDown',40);await key('Enter','Enter',13);
       state=await inspect();await click(await pointFor('body'));await key('End','End',35);
     }
   }
   state=await inspect();validateContent(state,packet);
   const oldCount=state.temporaryCount;
   status('제목·본문·사진 순서 확인 완료. 임시저장 중…');
   await click(await pointFor('save'));
   await waitFor(s=>s.saveSignals.some(t=>/저장/.test(t)&&/완료|되었습니다|했/.test(t)) || (s.temporaryCount && s.temporaryCount!==oldCount),'저장 버튼을 눌렀지만 완료를 확인하지 못했습니다. 네이버 편집기에서 임시저장 목록을 확인하세요.',15000);
   await report('success','네이버 임시저장 완료');
   $('status').textContent='네이버 임시저장 완료. 편집기에서 글과 사진을 확인하세요. 발행은 직접 진행합니다.';
 }catch(error){
   const value=`중단: ${error.message} 편집기 탭을 확인하세요. 재시도 전 중복 임시저장 여부를 확인하세요.`;
   $('status').textContent=value;
   try{await report('failure',value);}catch{}
 }
 finally{try{const result=await chrome.scripting.executeScript({target:{tabId:tabID},func:restorePhotoPicker,args:[]});}catch{}if(attached){try{await command('Page.setInterceptFileChooserDialog',{enabled:false});}catch{}attached=false;try{await chrome.debugger.detach({tabId:tabID});}catch{}}running=false;$('files').disabled=false;$('stop').disabled=true;$('start').disabled=!!bridgeJob||!packet;}
}
$('start').addEventListener('click',runPosting);

chrome.debugger.onDetach.addListener(source=>{if(running && attached && source.tabId===tabID){stopped=true;status('편집기 제어가 해제되어 중단했습니다.');}});

async function receiveFromApp(){
 const id=new URL(location.href).searchParams.get('job');
 if(!id)return;
 if(!/^[0-9a-f-]{36}$/i.test(id)){status('작업 ID가 올바르지 않습니다.');return;}
 bridgeJob=id;
 $('files').hidden=true;$('start').disabled=true;
 if($('manualIntro'))$('manualIntro').textContent='앱에서 요청한 글과 사진을 자동으로 받아 새 글에 입력하고 임시저장합니다. 작업이 끝날 때까지 이 화면을 열어두세요.';
 try{
   bridgeToken=(await chrome.storage.local.get('appBridgeToken')).appBridgeToken;
   if(!bridgeToken)throw new Error('확장 프로그램의 앱 연결 코드를 먼저 앱에 저장하세요.');
   status('앱에서 글과 사진을 받는 중…');
   const value=await (await bridgeFetch(`/jobs/${id}/claim`,{method:'POST'})).json();
   bridgeClaimed=true;
   files=new Map();
   for(const photo of value.photos){
     const blob=await (await bridgeFetch(`/jobs/${id}/photos/${photo.number}`)).blob();
     files.set(photo.filename,new File([blob],photo.filename,{type:'image/jpeg'}));
   }
   packet=validatePacket(value,files);
   const heading=document.createElement('h2');heading.textContent=packet.title;$('preview').append(heading);
   await runPosting();
 }catch(error){status(error.message);try{await report('failure',error.message);}catch{}}
}
void receiveFromApp();
