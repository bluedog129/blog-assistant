export function validatePacket(value, files) {
  const fail = message => { throw new Error(message); };
  if (value.type !== 'blog-assistant.naver-post' || value.version !== 1) fail('지원되는 임시저장 파일이 아닙니다.');
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
  const title=document.querySelector('.se-documentTitle');
  const text=[...document.querySelectorAll('.se-component.se-text')];
  const image=[...document.querySelectorAll('.se-component.se-image, .se-component.se-imageGroup')];
  const buttons=[...document.querySelectorAll('button')];
  const save=buttons.find(b=>b.textContent.trim()==='저장');
  const photoButton=buttons.find(b=>(b.getAttribute('aria-label')||'')==='사진 추가' || b.getAttribute('data-name')==='image');
  const fileInputs=[...document.querySelectorAll('input[type=file]')];
  const recoveryPrompt=[...document.querySelectorAll('[role="dialog"], .se-popup, .se-popup-container, .se-layer')].some(el=>{
    const r=el.getBoundingClientRect();
    return r.width>0 && r.height>0 && /작성\s*중인|작성하던|이어서\s*작성|자동\s*저장된|저장된\s*글을.*불러/.test(el.innerText||'');
  });
  return {recoveryPrompt,ready:!!title&&text.length>0,title:clean(title),texts:text.map(clean),imageCount:image.length,
    components:all.filter(el=>!el.classList.contains('se-documentTitle')).map(el=>({kind:el.classList.contains('se-text')?'text':el.classList.contains('se-image')||el.classList.contains('se-imageGroup')?'photo':'other',text:clean(el)})),
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
  if(kind === 'photo') element = document.querySelector('button[data-name="image"]');
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
}

export function openPhotoUpload(blogID) {
 const url = new URL(location.href);
 if (url.host !== 'blog.naver.com' || url.pathname !== '/PostWriteForm.naver' || url.searchParams.get('blogId') !== blogID) throw new Error('글쓰기 대상이 바뀌었습니다.');
 const button = document.querySelector('button[data-name="image"]');
 if (!button || button.disabled) throw new Error('사진 추가 버튼을 사용할 수 없습니다.');
 // Let SmartEditor prepare the upload input, but cancel its native picker.
 // CDP interception alone can leave native chooser requests queued on macOS.
 if (!window.__blogAssistantFileClickGuard) {
   const guard = event => {
     if (event.target instanceof HTMLInputElement && event.target.type === 'file') event.preventDefault();
   };
   window.__blogAssistantFileClickGuard = guard;
   document.addEventListener('click', guard, true);
 }
 button.click();
 return true;
}

export function restorePhotoPicker() {
 const guard=window.__blogAssistantFileClickGuard;
 if (guard) document.removeEventListener('click',guard,true);
 delete window.__blogAssistantFileClickGuard;
}
