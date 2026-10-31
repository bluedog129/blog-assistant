import {validatePlace} from './visit-blocks.js';

export function validatePacket(value, files) {
  const fail = message => { throw new Error(message); };
  if (value.type !== 'blog-assistant.naver-post' || ![1,2,3,4].includes(value.version)) fail('지원되는 임시저장 파일이 아닙니다.');
  if (value.version>=3 && value.template!=null && value.template!=='record') fail('지원되는 글 양식이 아닙니다.');
  if (value.version===2 && value.template!=='record') fail('지원되는 글 양식이 아닙니다.');
  if (value.blogID !== 'bluedog129' || value.categoryNo !== '65') fail('대상은 bluedog129의 맛집탐방 카테고리입니다.');
  if (typeof value.title !== 'string' || !value.title.trim() || value.title.length > 200) fail('제목을 확인하세요.');
  if (!Array.isArray(value.blocks) || !value.blocks.length || value.blocks.length > 1000 || !Array.isArray(value.photos) || value.photos.length > 300) fail('본문·사진 개수를 확인하세요.');
  const names = new Set();
  for (let i=0;i<value.photos.length;i++) {
    const photo = value.photos[i];
    const video=photo.mediaType==='video';
    if(photo.mediaType!=null&&!['video','image'].includes(photo.mediaType))fail('미디어 종류를 확인하세요.');
    if(video&&value.version<3)fail('영상은 새 확장 프로그램으로 전달하세요.');
    const filename=video?/^\d+_[^/\\]+\.mp4$/i:/^\d+_[^/\\]+\.jpg$/i;
    if (photo.number !== i+1 || typeof photo.filename !== 'string' || !filename.test(photo.filename) || names.has(photo.filename)) fail('사진 파일명 또는 번호가 잘못됐습니다.');
    names.add(photo.filename);
    const file = files.get(photo.filename);
    if (!file || !file.size || file.size > (video?200_000_000:20_000_000)) fail(`사진 파일이 없거나 너무 큽니다: ${photo.filename}`);
  }
  if(value.photos.filter(p=>p.mediaType==='video').length>10)fail('영상은 한 글에 최대 10개까지 선택하세요.');
  const seen = new Set();
  let textSize=0;
  for (const block of value.blocks) {
    if(block.kind==='map'){
      if(value.version!==4||!block.place||typeof block.place.name!=='string'||!block.place.name.trim()||block.place.name.length>200||typeof block.place.address!=='string'||block.place.address.length>500||/[\r\n]/.test(block.place.name+block.place.address))fail('장소 지도 정보를 확인하세요.');
      if(typeof block.place.url!=='string'||block.place.url.length>2048)fail('장소 지도 링크를 확인하세요.');
      let url;try{url=new URL(block.place.url);}catch{fail('장소 지도 링크를 확인하세요.');}
      if(url.protocol!=='https:'||!['naver.me','map.naver.com','m.place.naver.com','pcmap.place.naver.com'].includes(url.hostname)||url.username||url.password||url.port||url.pathname==='/')fail('장소 지도 링크를 확인하세요.');
      if(block.text!=null||block.photoNumber!=null||block.paragraphs!=null)fail('장소 지도 블록 구성이 잘못됐습니다.');
    }else if (block.kind === 'text'||block.kind==='info') {
      if(block.kind==='info'&&(value.version!==4||value.template!=='record'))fail('방문정보는 새 확장 프로그램의 단정한 기록 양식으로 전달하세요.');
      if (typeof block.text !== 'string' || !block.text.trim()) fail('본문 텍스트가 비어 있습니다.');
      textSize+=block.text.length;
      if(value.version===2||(value.version>=3&&value.template==='record')){
        if(!Array.isArray(block.paragraphs)||!block.paragraphs.length||block.paragraphs.length>10000)fail('글 서식의 문단 구성을 확인하세요.');
        for(const paragraph of block.paragraphs){
          if(!['body','menu','section','price','info'].includes(paragraph.role)||!Array.isArray(paragraph.runs)||paragraph.runs.length>1000||(block.kind==='info'&&paragraph.role!=='info'))fail('지원되지 않는 글 서식입니다.');
          for(const run of paragraph.runs)if(typeof run.text!=='string'||!run.text.length||/[\r\n]/.test(run.text)||typeof run.bold!=='boolean')fail('강조 구절을 확인하세요.');
        }
        if(block.paragraphs.map(p=>p.runs.map(r=>r.text).join('')).join('\n')!==block.text)fail('본문과 서식의 내용이 다릅니다.');
      }else if(block.paragraphs)fail('서식이 있는 글은 새 확장 프로그램에서 전달하세요.');
    } else if (block.kind === 'photo' || block.kind === 'video') {
      if (!Number.isInteger(block.photoNumber) || block.photoNumber<1 || block.photoNumber>value.photos.length || seen.has(block.photoNumber)) fail('본문의 사진 번호가 잘못됐거나 중복입니다.');
      if((block.kind==='video')!==(value.photos[block.photoNumber-1].mediaType==='video'))fail('사진·영상 표시 종류가 파일과 다릅니다.');
      seen.add(block.photoNumber);
    } else fail('알 수 없는 본문 구성입니다.');
  }
  if(value.blocks.filter(b=>b.kind==='map').length>1||value.blocks.filter(b=>b.kind==='info').length>1)fail('장소 지도와 방문정보는 한 번씩만 넣으세요.');
  if (!textSize || textSize>500000 || seen.size!==value.photos.length) fail('본문 크기 또는 누락된 사진 번호를 확인하세요.');
  return value;
}

// This function only observes the editor; trusted input is sent with chrome.debugger.
export function inspectEditor(blogID) {
  const url=new URL(location.href);
  if (url.host!=='blog.naver.com' || url.pathname!=='/PostWriteForm.naver' || url.searchParams.get('blogId')!==blogID) throw new Error('대상 네이버 글쓰기 페이지가 아닙니다.');
  const components=[...document.querySelectorAll('.se-components-wrap > .se-component')];
  const fallback=[...document.querySelectorAll('article .se-component')];
  const all=components.length?components:fallback;
  const point=el=>{
    if(!el) return null;
    const r=el.getBoundingClientRect();
    return {x:r.left+Math.min(r.width/2,30),y:r.top+r.height/2};
  };
  const clean=el=>[...(el?.querySelectorAll('.se-text-paragraph')||[])].map(p=>[...p.querySelectorAll('span.__se-node')].map(s=>s.textContent).join('')).join('\n').replace(/[\u200b\ufeff]/g,'').trim();
  const formatting=el=>[...el.querySelectorAll('.se-text-paragraph')].map(p=>{
    const runs=[];
    for(const span of p.querySelectorAll('span.__se-node')){
      const walker=document.createTreeWalker(span,NodeFilter.SHOW_TEXT);
      while(walker.nextNode()){
        const node=walker.currentNode,text=node.textContent.replace(/[\u200b\ufeff]/g,'');
        if(!text)continue;
        const style=getComputedStyle(node.parentElement);
        runs.push({text,bold:Number(style.fontWeight)>=600,size:parseFloat(style.fontSize),color:style.color,font:style.fontFamily});
      }
    }
    return {runs,align:getComputedStyle(p).textAlign};
  });
  const title=document.querySelector('.se-documentTitle');
  const text=[...document.querySelectorAll('.se-component.se-text')];
  const maps=[...document.querySelectorAll('.se-component.se-placesMap')];
  const place=el=>{
    const img=el.querySelector('.se-module-map-image img.se-map-image');
    return {name:el.querySelector('.se-map-title')?.textContent.trim()||'',address:el.querySelector('.se-map-address')?.textContent.trim()||'',ready:el.querySelectorAll('.se-map-title').length===1&&el.querySelectorAll('.se-map-address').length===1&&!!img&&img.complete&&img.naturalWidth>0&&/^https:\/\//.test(img.currentSrc||img.src)};
  };
  const image=[...document.querySelectorAll('.se-component.se-image, .se-component.se-imageGroup')];
  const videos=[...document.querySelectorAll('.se-component.se-video')];
  const videoReadyCount=videos.filter(el=>{
    // The editing canvas renders a thumbnail and duration without a data-module ID.
    const thumbnail=el.querySelector('.se-module-video .se-video-thumbnail');
    const duration=el.querySelector('.se-video-time')?.textContent.trim();
    const uploadedPoster=thumbnail&&/^url\(["']?https:\/\//.test(getComputedStyle(thumbnail).backgroundImage);
    const renderedVideo=uploadedPoster&&/^(?:\d+:)?\d{1,2}:\d{2}$/.test(duration||'');
    if(renderedVideo)return true;
    const nodes=[el,...el.querySelectorAll('[data-module]')];
    return nodes.some(node=>{try{
      const data=JSON.parse(node.getAttribute('data-module')||'null');
      const hasID=value=>value&&typeof value==='object'&&Object.entries(value).some(([key,item])=>((key==='vid'||key.toLowerCase()==='videoid')&&typeof item==='string'&&item.length>0)||hasID(item));
      return hasID(data);
    }catch{return false;}})||[...el.querySelectorAll('iframe')].some(frame=>/^https:\/\//.test(frame.getAttribute('src')||''));
  }).length;
  const buttons=[...document.querySelectorAll('button')];
  const save=buttons.find(b=>b.textContent.trim()==='저장');
  const photoButton=buttons.find(b=>(b.getAttribute('aria-label')||'')==='사진 추가' || b.getAttribute('data-name')==='image');
  const fileInputs=[...document.querySelectorAll('input[type=file]')];
  const visible=el=>{if(!el)return false;const r=el.getBoundingClientRect();const style=getComputedStyle(el);return r.width>0&&r.height>0&&style.visibility!=='hidden'&&style.display!=='none';};
  const buttonState=el=>el?{disabled:el.disabled,ariaDisabled:el.getAttribute('aria-disabled'),visible:visible(el),className:el.className}:null;
  // Image components appear before the upload finishes; blob/data previews are not uploaded photos.
  const imageStates=image.map(el=>{
    const resources=[...el.querySelectorAll('img.se-image-resource')];
    const ready=resources.length>0&&resources.every(img=>img.complete&&img.naturalWidth>0&&/^https:\/\//.test(img.currentSrc||img.src));
    return {id:el.getAttribute('data-compid')||el.id||null,ready};
  });
  const imageReadyCount=imageStates.filter(item=>item.ready).length;
  const uploadBusy=[...document.querySelectorAll('.se-progressbar')].some(visible);
  const selection=document.getSelection();
  const selectionElement=selection?.anchorNode?.nodeType===1?selection.anchorNode:selection?.anchorNode?.parentElement;
  const selectionComponent=selectionElement?.closest('.se-component');
  const uploadDiagnostics={
    imageReadyCount,uploadBusy,imageStates,
    documentReady:document.readyState,hasFocus:document.hasFocus(),
    photoButton:buttonState(photoButton),
    fileInputs:fileInputs.slice(0,16).map(el=>({accept:el.accept,multiple:el.multiple,disabled:el.disabled,visible:visible(el),connected:el.isConnected})),
    iframeCount:document.querySelectorAll('iframe').length,
    selectionComponent:selectionComponent?.className||null,
    activeElement:document.activeElement?{tag:document.activeElement.tagName,className:document.activeElement.className}:null
  };
  const recoveryPrompt=[...document.querySelectorAll('[role="dialog"], .se-popup, .se-popup-container, .se-layer')].some(el=>{
    const r=el.getBoundingClientRect();
    return r.width>0 && r.height>0 && /작성\s*중인|작성하던|이어서\s*작성|자동\s*저장된|저장된\s*글을.*불러/.test(el.innerText||'');
  });
  return {uploadDiagnostics,recoveryPrompt,ready:!!title&&text.length>0,title:clean(title),texts:text.map(clean),imageCount:image.length,videoCount:videos.length,videoReadyCount,mapCount:maps.length,
    components:all.filter(el=>!el.classList.contains('se-documentTitle')).map(el=>{
      const info=el.classList.contains('se-quotation');const content=info?el.querySelector('.se-quote'):el;
      return {kind:el.classList.contains('se-placesMap')?'map':info?'info':el.classList.contains('se-text')?'text':el.classList.contains('se-image')||el.classList.contains('se-imageGroup')?'photo':el.classList.contains('se-video')?'video':'other',text:clean(content),paragraphs:el.classList.contains('se-text')||info?formatting(content):undefined,place:el.classList.contains('se-placesMap')?place(el):undefined,infoStyle:info&&el.classList.contains('se-l-quotation_line')?'line':undefined};
    }),
    titlePoint:point(title?.querySelector('.se-text-paragraph')),bodyPoint:point(text.at(-1)?.querySelector('.se-text-paragraph:last-child')),
    photoPoint:point(photoButton),savePoint:point(save),fileInputCount:fileInputs.filter(el=>!el.accept||/image|jpg|jpeg|png/i.test(el.accept)).length,
    saveSignals:[...document.querySelectorAll('[role=status], [role=alert], [class*=toast]')].map(e=>e.textContent.trim()).filter(Boolean),
    temporaryCount:buttons.find(b=>/임시저장된 글 보기/.test(b.getAttribute('aria-label')||''))?.getAttribute('aria-label')};
}

export function supplyPhoto(name, base64) {
  const inputs=[...document.querySelectorAll('input[type=file]')].filter(e=>!e.accept || /image|jpg|jpeg|png/.test(e.accept));
  if(inputs.length!==1) throw new Error('사진 업로드 입력창을 하나로 확인하지 못했습니다.');
  const bytes=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));
  const transfer=new DataTransfer();
  transfer.items.add(new File([bytes],name,{type:'image/jpeg'}));
  inputs[0].files=transfer.files;
  inputs[0].dispatchEvent(new Event('change',{bubbles:true}));
  return true;
}

export function editorPoint(blogID, kind) {
  const url = new URL(location.href);
  if(url.host !== 'blog.naver.com' || url.pathname !== '/PostWriteForm.naver' || url.searchParams.get('blogId') !== blogID) throw new Error('글쓰기 대상이 바뀌었습니다.');
  let element;
  if(kind === 'title') element = document.querySelector('.se-documentTitle .se-text-paragraph');
  if(kind === 'body') element = [...document.querySelectorAll('.se-component.se-text')].at(-1)?.querySelector('.se-text-paragraph:last-child');
  if(kind === 'photo') element = document.querySelector('button.se-image-toolbar-button[data-name="image"]')||document.querySelector('button[data-name="image"]');
  if(kind === 'save') element = [...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='저장');
  if(!element) throw new Error('입력 위치를 확인하지 못했습니다.');
  element.scrollIntoView({block:'center',behavior:'instant'});
  const rect=element.getBoundingClientRect();
  return {x:rect.left+Math.min(rect.width/2,30),y:rect.top+rect.height/2};
}

export function validateContent(state, packet){
 const normalize=text=>text.replace(/[\u200b\ufeff]/g,'').replace(/\s+/g,' ').trim();
 if(normalize(state.title)!==normalize(packet.title))throw new Error('제목이 원문과 달라 저장을 중단했습니다.');
 if(state.imageCount!==packet.photos.filter(p=>p.mediaType!=='video').length)throw new Error('사진 개수가 원문과 달라 저장을 중단했습니다.');
 if(Number(state.videoCount||0)!==packet.photos.filter(p=>p.mediaType==='video').length)throw new Error('영상 개수가 원문과 달라 저장을 중단했습니다.');
 if(Number(state.mapCount||0)!==packet.blocks.filter(b=>b.kind==='map').length)throw new Error('장소 지도 개수가 다릅니다. 저장하지 않았습니다.');
 if(packet.photos.some(p=>p.mediaType==='video')&&state.videoReadyCount!==state.videoCount)throw new Error('영상 업로드 완료를 확인하지 못해 저장을 중단했습니다.');
 const actual=state.components.filter(b=>['photo','video','map','info'].includes(b.kind)||(b.kind==='text'&&normalize(b.text)));
 const expected=packet.blocks;
 // Combine adjacent text components, preserving photo positions and all words.
 const compact=blocks=>blocks.reduce((all,b)=>{if(b.kind==='text'&&all.at(-1)?.kind==='text')all.at(-1).text+='\n'+b.text;else all.push({...b});return all;},[]);
 const a=compact(actual),b=compact(expected);
 if(a.length!==b.length) throw new Error('본문·사진 구간 수가 원문과 다릅니다. 저장하지 않았습니다.');
 const mismatch=a.findIndex((item,i)=>item.kind!==b[i].kind||(['text','info'].includes(item.kind)&&normalize(item.text)!==normalize(b[i].text)));
 if(mismatch>=0) throw new Error(`원문과 다른 구간: ${mismatch+1}/${b.length} (${b[mismatch].kind==='photo'?'사진 위치':'본문'}). 저장하지 않았습니다.`);
 a.forEach((item,i)=>{if(item.kind==='map')validatePlace(item.place,b[i].place);if(item.kind==='info'&&item.infoStyle!=='line')throw new Error('방문정보의 왼쪽 선 양식을 확인하지 못했습니다. 저장하지 않았습니다.');});
 if(packet.version===2||(packet.version>=3&&packet.template==='record'))validateFormatting(state,packet);
}

export function paragraphStyle(role,bold=false){
 return {size:role==='menu'?19:role==='price'||role==='info'?15:16,
   color:role==='price'?'#777777':'#333333',bold,font:'nanumgothic'};
}

export function validateFormatting(state,packet){
 const expected=packet.blocks.filter(b=>b.kind==='text'||b.kind==='info').flatMap(b=>b.paragraphs.map(p=>({...p,quote:b.kind==='info'}))).filter(p=>p.runs.some(r=>r.text.trim()));
 const actual=state.components.filter(b=>b.kind==='text'||b.kind==='info').flatMap(b=>b.paragraphs||[]).filter(p=>p.runs.some(r=>r.text.trim()));
 if(expected.length!==actual.length)throw new Error('서식 문단 수가 다릅니다. 저장하지 않았습니다.');
 const rgb=hex=>`rgb(${parseInt(hex.slice(1,3),16)}, ${parseInt(hex.slice(3,5),16)}, ${parseInt(hex.slice(5,7),16)})`;
 const characters=runs=>runs.flatMap(run=>[...run.text.replace(/[\s\u200b\ufeff]/g,'')].map(char=>({...run,char})));
 for(let i=0;i<expected.length;i++){
   const want=characters(expected[i].runs),got=characters(actual[i].runs);
   if(want.length!==got.length||!['left','start'].includes(actual[i].align))throw new Error(`문단 ${i+1}의 내용·정렬 서식을 확인하지 못했습니다. 저장하지 않았습니다.`);
   for(let j=0;j<want.length;j++){
     const style=paragraphStyle(expected[i].role,want[j].bold),run=got[j];
     if(run.char!==want[j].char||run.bold!==style.bold||run.size!==style.size||run.color!==rgb(style.color)||!run.font.includes(expected[i].quote?'nanumbarungothic':'nanumgothic'))throw new Error(`문단 ${i+1}의 볼드·크기·색상·글꼴이 양식과 다릅니다. 저장하지 않았습니다.`);
   }
 }
}

// Read visible toolbar controls only. Input remains trusted CDP mouse/keyboard input.
export function formattingControls(blogID,name,value){
 const url=new URL(location.href);
 if(url.host!=='blog.naver.com'||url.pathname!=='/PostWriteForm.naver'||url.searchParams.get('blogId')!==blogID)throw new Error('글쓰기 대상이 바뀌었습니다.');
 const visible=el=>{const r=el.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(el).visibility!=='hidden';};
 const buttons=[...document.querySelectorAll('button')];
 let candidates;
 if(name==='color-option'){
   candidates=buttons.filter(b=>b.getAttribute('data-color')===value&&b.closest('.se-property-color-picker-container')?.getAttribute('data-name')==='font-color').filter(visible);
   // SmartEditor repeats recently used colors above the preset palette.
   // Prefer the preset swatch, keeping the choice inside the font-color picker.
   const preset=candidates.filter(b=>b.closest('.se-color-swatches-preset'));
   if(preset.length)candidates=preset;
 }
 else candidates=buttons.filter(b=>b.getAttribute('data-name')===name&&(value===null?b.getAttribute('data-role')!=='option':b.getAttribute('data-role')==='option'&&b.getAttribute('data-value')===value));
 candidates=candidates.filter(visible);
 if(candidates.length!==1)throw new Error(`서식 도구를 확인하지 못했습니다: ${name}. 확장 프로그램을 다시 로드하거나 편집기를 확인하세요.`);
 const el=candidates[0],r=el.getBoundingClientRect();
 return {point:{x:r.left+r.width/2,y:r.top+r.height/2},selected:el.classList.contains('se-is-selected'),text:el.querySelector('.se-toolbar-label')?.textContent.trim(),color:el.querySelector('[data-role="color"]')?.style.backgroundColor};
}

export function photoUploadComplete(state, previousCount, previousIDs) {
 if(state.imageCount!==previousCount+1||state.uploadDiagnostics?.uploadBusy!==false)return false;
 // The editor redraws old uploaded photos as SVG placeholders. Validate the new
 // component itself instead of requiring every old thumbnail to load again.
 if(previousIDs!==undefined){
  const images=state.uploadDiagnostics?.imageStates;
  if(!Array.isArray(previousIDs)||previousIDs.length!==previousCount||new Set(previousIDs).size!==previousCount||previousIDs.some(id=>typeof id!=='string'||!id))return false;
  if(!Array.isArray(images)||images.length!==state.imageCount||images.some(item=>typeof item.id!=='string'||!item.id)||new Set(images.map(item=>item.id)).size!==images.length)return false;
  if(previousIDs.some(id=>!images.some(item=>item.id===id)))return false;
  if(images.filter(item=>previousIDs.includes(item.id)).some((item,index)=>item.id!==previousIDs[index]))return false;
  const added=images.filter(item=>!previousIDs.includes(item.id));
  return added.length===1&&added[0].ready===true;
 }
 // Retain the count-only API for earlier callers without component identities.
 return state.uploadDiagnostics?.imageReadyCount===previousCount+1;
}

export function preparePhotoUpload(blogID) {
 const url = new URL(location.href);
 if (url.host !== 'blog.naver.com' || url.pathname !== '/PostWriteForm.naver' || url.searchParams.get('blogId') !== blogID) throw new Error('글쓰기 대상이 바뀌었습니다.');
 const button = document.querySelector('button.se-image-toolbar-button[data-name="image"]')||document.querySelector('button[data-name="image"]');
 if (!button || button.disabled || button.getAttribute('aria-disabled')==='true') throw new Error('사진 추가 버튼을 사용할 수 없습니다.');
 // Install the guard before the trusted CDP mouse click, without activating the button here.
 // CDP interception alone can leave native chooser requests queued on macOS.
 if (!window.__blogAssistantFileClickGuard) {
   const guard = event => {
     const input=event.target;
     if (!(input instanceof HTMLInputElement) || input.type !== 'file') return;
     const accept=input.getAttribute('accept')||'';
     // The video uploader needs its own chooser event. Never cancel video-only inputs.
     if (!accept || /image|jpg|jpeg|png/i.test(accept)) event.preventDefault();
   };
   window.__blogAssistantFileClickGuard = guard;
   document.addEventListener('click', guard, true);
 }
 return {fileInputCountBefore:document.querySelectorAll('input[type=file]').length,
   disabled:button.disabled,ariaDisabled:button.getAttribute('aria-disabled')};
}

export function restorePhotoPicker() {
 const guard=window.__blogAssistantFileClickGuard;
 if (guard) document.removeEventListener('click',guard,true);
 delete window.__blogAssistantFileClickGuard;
}
