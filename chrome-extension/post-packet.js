export function validatePacket(value, files) {
  const fail = message => { throw new Error(message); };
  if (value.type !== 'blog-assistant.naver-post' || ![1,2].includes(value.version)) fail('지원되는 임시저장 파일이 아닙니다.');
  if (value.version===2 && value.template!=='record') fail('지원되는 글 양식이 아닙니다.');
  if (value.blogID !== 'bluedog129' || value.categoryNo !== '65') fail('대상은 bluedog129의 맛집탐방 카테고리입니다.');
  if (typeof value.title !== 'string' || !value.title.trim() || value.title.length > 200) fail('제목을 확인하세요.');
  if (!Array.isArray(value.blocks) || !value.blocks.length || value.blocks.length > 1000 || !Array.isArray(value.photos) || value.photos.length > 300) fail('본문·사진 개수를 확인하세요.');
  const names = new Set();
  for (let i=0;i<value.photos.length;i++) {
    const photo = value.photos[i];
    if (photo.number !== i+1 || typeof photo.filename !== 'string' || !/^\d+_[^/\\]+\.jpg$/i.test(photo.filename) || names.has(photo.filename)) fail('사진 파일명 또는 번호가 잘못됐습니다.');
    names.add(photo.filename);
    const file = files.get(photo.filename);
    if (!file || !file.size || file.size > 20_000_000) fail(`사진 파일이 없거나 너무 큽니다: ${photo.filename}`);
  }
  const seen = new Set();
  let textSize=0;
  for (const block of value.blocks) {
    if (block.kind === 'text') {
      if (typeof block.text !== 'string' || !block.text.trim()) fail('본문 텍스트가 비어 있습니다.');
      textSize+=block.text.length;
      if(value.version===2){
        if(!Array.isArray(block.paragraphs)||!block.paragraphs.length||block.paragraphs.length>10000)fail('글 서식의 문단 구성을 확인하세요.');
        for(const paragraph of block.paragraphs){
          if(!['body','menu','section','price','info'].includes(paragraph.role)||!Array.isArray(paragraph.runs)||paragraph.runs.length>1000)fail('지원되지 않는 글 서식입니다.');
          for(const run of paragraph.runs)if(typeof run.text!=='string'||!run.text.length||/[\r\n]/.test(run.text)||typeof run.bold!=='boolean')fail('강조 구절을 확인하세요.');
        }
        if(block.paragraphs.map(p=>p.runs.map(r=>r.text).join('')).join('\n')!==block.text)fail('본문과 서식의 내용이 다릅니다.');
      }else if(block.paragraphs)fail('서식이 있는 글은 새 확장 프로그램에서 전달하세요.');
    } else if (block.kind === 'photo') {
      if (!Number.isInteger(block.photoNumber) || block.photoNumber<1 || block.photoNumber>value.photos.length || seen.has(block.photoNumber)) fail('본문의 사진 번호가 잘못됐거나 중복입니다.');
      seen.add(block.photoNumber);
    } else fail('알 수 없는 본문 구성입니다.');
  }
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
  const image=[...document.querySelectorAll('.se-component.se-image, .se-component.se-imageGroup')];
  const buttons=[...document.querySelectorAll('button')];
  const save=buttons.find(b=>b.textContent.trim()==='저장');
  const photoButton=buttons.find(b=>(b.getAttribute('aria-label')||'')==='사진 추가' || b.getAttribute('data-name')==='image');
  const fileInputs=[...document.querySelectorAll('input[type=file]')];
  const visible=el=>{if(!el)return false;const r=el.getBoundingClientRect();const style=getComputedStyle(el);return r.width>0&&r.height>0&&style.visibility!=='hidden'&&style.display!=='none';};
  const buttonState=el=>el?{disabled:el.disabled,ariaDisabled:el.getAttribute('aria-disabled'),visible:visible(el),className:el.className}:null;
  // Image components appear before the upload finishes; blob/data previews are not uploaded photos.
  const imageReadyCount=image.filter(el=>{
    const resources=[...el.querySelectorAll('img.se-image-resource')];
    return resources.length>0&&resources.every(img=>img.complete&&img.naturalWidth>0&&/^https:\/\//.test(img.currentSrc||img.src));
  }).length;
  const uploadBusy=[...document.querySelectorAll('.se-progressbar')].some(visible);
  const selection=document.getSelection();
  const selectionElement=selection?.anchorNode?.nodeType===1?selection.anchorNode:selection?.anchorNode?.parentElement;
  const selectionComponent=selectionElement?.closest('.se-component');
  const uploadDiagnostics={
    imageReadyCount,uploadBusy,
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
  return {uploadDiagnostics,recoveryPrompt,ready:!!title&&text.length>0,title:clean(title),texts:text.map(clean),imageCount:image.length,
    components:all.filter(el=>!el.classList.contains('se-documentTitle')).map(el=>({kind:el.classList.contains('se-text')?'text':el.classList.contains('se-image')||el.classList.contains('se-imageGroup')?'photo':'other',text:clean(el),paragraphs:el.classList.contains('se-text')?formatting(el):undefined})),
    titlePoint:point(title?.querySelector('.se-text-paragraph')),bodyPoint:point(text.at(-1)?.querySelector('.se-text-paragraph:last-child')),
    photoPoint:point(photoButton),savePoint:point(save),fileInputCount:fileInputs.length,
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
 if(state.imageCount!==packet.photos.length)throw new Error('사진 개수가 원문과 달라 저장을 중단했습니다.');
 const actual=state.components.filter(b=>b.kind==='photo'||(b.kind==='text'&&normalize(b.text)));
 const expected=packet.blocks;
 // Combine adjacent text components, preserving photo positions and all words.
 const compact=blocks=>blocks.reduce((all,b)=>{if(b.kind==='text'&&all.at(-1)?.kind==='text')all.at(-1).text+='\n'+b.text;else all.push({...b});return all;},[]);
 const a=compact(actual),b=compact(expected);
 if(a.length!==b.length) throw new Error('본문·사진 구간 수가 원문과 다릅니다. 저장하지 않았습니다.');
 const mismatch=a.findIndex((item,i)=>item.kind!==b[i].kind||(item.kind==='text'&&normalize(item.text)!==normalize(b[i].text)));
 if(mismatch>=0) throw new Error(`원문과 다른 구간: ${mismatch+1}/${b.length} (${b[mismatch].kind==='photo'?'사진 위치':'본문'}). 저장하지 않았습니다.`);
 if(packet.version===2)validateFormatting(state,packet);
}

export function paragraphStyle(role,bold=false){
 return {size:role==='menu'?19:role==='price'||role==='info'?15:16,
   color:role==='menu'||role==='section'?'#003960':role==='price'?'#777777':'#333333',bold,font:'nanumgothic'};
}

export function validateFormatting(state,packet){
 const expected=packet.blocks.filter(b=>b.kind==='text').flatMap(b=>b.paragraphs).filter(p=>p.runs.some(r=>r.text.trim()));
 const actual=state.components.filter(b=>b.kind==='text').flatMap(b=>b.paragraphs||[]).filter(p=>p.runs.some(r=>r.text.trim()));
 if(expected.length!==actual.length)throw new Error('서식 문단 수가 다릅니다. 저장하지 않았습니다.');
 const rgb=hex=>`rgb(${parseInt(hex.slice(1,3),16)}, ${parseInt(hex.slice(3,5),16)}, ${parseInt(hex.slice(5,7),16)})`;
 const characters=runs=>runs.flatMap(run=>[...run.text.replace(/[\s\u200b\ufeff]/g,'')].map(char=>({...run,char})));
 for(let i=0;i<expected.length;i++){
   const want=characters(expected[i].runs),got=characters(actual[i].runs);
   if(want.length!==got.length||!['left','start'].includes(actual[i].align))throw new Error(`문단 ${i+1}의 내용·정렬 서식을 확인하지 못했습니다. 저장하지 않았습니다.`);
   for(let j=0;j<want.length;j++){
     const style=paragraphStyle(expected[i].role,want[j].bold),run=got[j];
     if(run.char!==want[j].char||run.bold!==style.bold||run.size!==style.size||run.color!==rgb(style.color)||!run.font.includes('nanumgothic'))throw new Error(`문단 ${i+1}의 볼드·크기·색상·글꼴이 양식과 다릅니다. 저장하지 않았습니다.`);
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

export function photoUploadComplete(state, previousCount) {
 return state.imageCount===previousCount+1&&state.uploadDiagnostics?.imageReadyCount===previousCount+1&&state.uploadDiagnostics?.uploadBusy===false;
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
     if (event.target instanceof HTMLInputElement && event.target.type === 'file') event.preventDefault();
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
