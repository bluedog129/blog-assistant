// Functions injected into the editor must be self-contained.
export function inspectVideoUploader(blogID) {
 const page=new URL(location.href);
 if(page.host!=='blog.naver.com'||page.pathname!=='/PostWriteForm.naver'||page.searchParams.get('blogId')!==blogID)throw new Error('대상 네이버 편집기가 아닙니다.');
 const visible=el=>{if(!el)return false;const r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';};
 const roots=[...document.querySelectorAll('.nvu_wrap')].filter(visible);
 if(roots.length>1)throw new Error('동영상 업로더가 여러 개 열려 있습니다.');
 const root=roots[0];
 if(!root)return {open:false,completeEnabled:false,titleEmpty:false};
 const buttons=[...root.querySelectorAll('button')].filter(visible);
 const complete=buttons.filter(b=>b.textContent.trim()==='완료');
 const titles=[...root.querySelectorAll('input[type=text],input:not([type])')].filter(visible);
 const named=titles.filter(el=>/제목/.test((el.getAttribute('placeholder')||'')+' '+(el.getAttribute('aria-label')||'')));
 const title=named.length===1?named[0]:titles.length===1?titles[0]:null;
 const statuses=[...root.querySelectorAll('.nvu_file_item .nvu_state')];
 const uploadReady=statuses.length===1&&statuses.every(el=>el.textContent.trim()==='업로드 완료');
 const error=[...root.querySelectorAll('[role=alert],.nvu_file_item .nvu_state')].filter(visible).some(el=>/실패|오류|불가|지원하지/.test(el.textContent||''));
 if(error)throw new Error('네이버 동영상 업로더에서 오류를 표시했습니다. 업로더를 직접 확인하세요.');
 return {open:true,hasAdd:buttons.some(b=>b.matches('.nvu_local,.nvu_btn_local')),uploadReady,completeEnabled:uploadReady&&!!title?.value.trim()&&complete.length===1&&!complete[0].disabled&&complete[0].getAttribute('aria-disabled')!=='true',titleEmpty:!!title&&!title.value.trim()};
}

export function videoUploadPoint(blogID,kind) {
 const page=new URL(location.href);
 if(page.host!=='blog.naver.com'||page.pathname!=='/PostWriteForm.naver'||page.searchParams.get('blogId')!==blogID)throw new Error('대상 네이버 편집기가 아닙니다.');
 const visible=el=>{if(!el)return false;const r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';};
 let candidates=[];
 if(kind==='toolbar')candidates=[...document.querySelectorAll('button.se-video-toolbar-button[data-name=video]')];
 else {
  const root=[...document.querySelectorAll('.nvu_wrap')].find(visible);
  if(!root)throw new Error('동영상 업로더를 찾지 못했습니다.');
  if(kind==='add')candidates=[...root.querySelectorAll('button.nvu_local,button.nvu_btn_local')];
  if(kind==='complete')candidates=[...root.querySelectorAll('button')].filter(b=>b.textContent.trim()==='완료');
  if(kind==='title'){
   const inputs=[...root.querySelectorAll('input[type=text],input:not([type])')].filter(visible);
   const named=inputs.filter(el=>/제목/.test((el.getAttribute('placeholder')||'')+' '+(el.getAttribute('aria-label')||'')));
   candidates=named.length===1?named:inputs.length===1?inputs:[];
  }
 }
 candidates=candidates.filter(visible);
 if(candidates.length!==1||candidates[0].disabled)throw new Error('동영상 입력 위치를 하나로 확인하지 못했습니다.');
 const el=candidates[0];el.scrollIntoView({block:'center',behavior:'instant'});
 const r=el.getBoundingClientRect();return{x:r.left+Math.min(r.width/2,30),y:r.top+r.height/2};
}

// Manual export uploads use bounded messages instead of a single large base64 payload.
export function supplyVideoChunk(id,name,total,offset,base64,finish=false) {
 if(!/^[a-f0-9-]{36}$/i.test(id)||!/^\d+_[^/\\]+\.mp4$/i.test(name)||!Number.isInteger(total)||total<1||total>200000000)throw new Error('영상 전달 구성이 올바르지 않습니다.');
 const key='__blogAssistantVideoUpload';
 if(offset===0)globalThis[key]={id,name,total,received:0,chunks:[]};
 const state=globalThis[key];
 if(!state||state.id!==id||state.name!==name||state.total!==total||state.received!==offset)throw new Error('영상 조각의 순서가 맞지 않습니다.');
 const bytes=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));
 if(bytes.length>524288||state.received+bytes.length>total)throw new Error('영상 조각 크기가 맞지 않습니다.');
 state.chunks.push(bytes);state.received+=bytes.length;
 if(finish){
  if(state.received!==total)throw new Error('영상을 모두 받지 못했습니다.');
  const inputs=[...document.querySelectorAll('input[type=file]')].filter(el=>/mp4|video/.test(el.accept)&&!/image\//.test(el.accept));
  if(inputs.length!==1)throw new Error('영상 파일 입력창을 하나로 확인하지 못했습니다.');
  const transfer=new DataTransfer();transfer.items.add(new File(state.chunks,name,{type:'video/mp4'}));
  delete globalThis[key];inputs[0].files=transfer.files;inputs[0].dispatchEvent(new Event('change',{bubbles:true}));
 }
 return offset+bytes.length;
}
export function clearVideoTransfer(){delete globalThis.__blogAssistantVideoUpload;}
