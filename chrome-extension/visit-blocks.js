// Observe the native place picker; all input is sent through trusted mouse/keys.
export function inspectPlaceDialog(blogID) {
 const url=new URL(location.href);
 if(url.host!=='blog.naver.com'||url.pathname!=='/PostWriteForm.naver'||url.searchParams.get('blogId')!==blogID)throw new Error('글쓰기 대상이 바뀌었습니다.');
 const popup=document.querySelector('.se-popup-placesMap');
 const visible=el=>{if(!el)return false;const r=el.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(el).visibility!=='hidden';};
 if(!visible(popup))return {open:false,results:[]};
 const results=[...popup.querySelectorAll('.se-place-map-search-result-item')].map(el=>({
  name:el.querySelector('.se-place-map-search-result-title')?.textContent.trim()||'',
  address:el.querySelector('.se-place-map-search-result-address')?.textContent.trim()||''
 }));
 const confirm=[...popup.querySelectorAll('button')].find(el=>el.textContent.trim()==='확인');
 return {open:true,results,confirmEnabled:!!confirm&&!confirm.disabled};
}

export function placeControlPoint(blogID,kind,index=null,expected=null) {
 const url=new URL(location.href);
 if(url.host!=='blog.naver.com'||url.pathname!=='/PostWriteForm.naver'||url.searchParams.get('blogId')!==blogID)throw new Error('글쓰기 대상이 바뀌었습니다.');
 const popup=document.querySelector('.se-popup-placesMap');
 let el;
 if(kind==='toolbar')el=document.querySelector('button[data-name="map"]');
 if(kind==='search')el=popup?.querySelector('input[placeholder="장소명을 입력하세요."]');
 if(kind==='result'||kind==='add'){
  const rows=[...(popup?.querySelectorAll('.se-place-map-search-result-item')||[])];
  if(!Number.isInteger(index)||index<0||index>=rows.length)throw new Error('장소 검색 결과가 바뀌었습니다.');
  if(expected&&(rows[index].querySelector('.se-place-map-search-result-title')?.textContent.trim()!==expected.name||rows[index].querySelector('.se-place-map-search-result-address')?.textContent.trim()!==expected.address))throw new Error('장소 검색 결과가 바뀌었습니다.');
  el=rows[index].querySelector(kind==='result'?'.se-place-map-search-result-link':'.se-place-add-button');
 }
 if(kind==='confirm')el=[...(popup?.querySelectorAll('button')||[])].find(e=>e.textContent.trim()==='확인');
 if(!el||el.disabled)throw new Error('장소 도구를 확인하지 못했습니다. 편집기의 장소 창을 확인하세요.');
 el.scrollIntoView({block:'center',behavior:'instant'});
 const r=el.getBoundingClientRect();if(!r.width||!r.height)throw new Error('장소 버튼이 표시되지 않았습니다.');
 return {x:r.left+r.width/2,y:r.top+r.height/2};
}

export function matchingPlaceIndex(results,place) {
 const clean=s=>s.normalize('NFC').replace(/\s+/g,'').trim();
 const address=s=>clean(s).replace(/^서울특별시/,'서울').replace(/^부산광역시/,'부산').replace(/^대구광역시/,'대구').replace(/^인천광역시/,'인천').replace(/^광주광역시/,'광주').replace(/^대전광역시/,'대전').replace(/^울산광역시/,'울산').replace(/^경기도/,'경기');
 if(!place.address.trim())return -1;
 const matches=results.map((r,i)=>({r,i})).filter(({r})=>clean(r.name)===clean(place.name)&&address(r.address)===address(place.address));
 return matches.length===1?matches[0].i:-1;
}

export function validatePlace(actual,expected) {
 if(!actual||!actual.name?.trim()||!actual.address?.trim()||actual.ready!==true)throw new Error('장소 지도·주소·약도 로딩을 확인하지 못했습니다. 저장하지 않았습니다.');
 if(actual.name.normalize('NFC').replace(/\s+/g,'')!==expected.name.normalize('NFC').replace(/\s+/g,''))throw new Error('네이버 등록 장소명과 확인한 장소명이 다릅니다. 장소를 다시 확인하세요. 저장하지 않았습니다.');
 if(expected.address.trim()&&matchingPlaceIndex([{name:actual.name,address:actual.address}],expected)!==0)throw new Error('지도 주소가 저장한 매장과 다릅니다. 저장하지 않았습니다.');
}

// A user's short working name is not the canonical Naver place name. Only an
// explicit picker selection may establish that association; automatic matching
// remains exact and the original requested address must still match.
export function confirmedPlaceKey(place) {return JSON.stringify([place.url,place.name,place.address]);}
export function confirmSelectedPlace(actual,original) {
 const target={url:original.url,name:actual?.name,address:actual?.address};
 if(typeof target.name!=='string'||!target.name.trim()||target.name.length>200||typeof target.address!=='string'||!target.address.trim()||target.address.length>500||/[\r\n]/.test(target.name+target.address))throw new Error('선택한 장소의 이름·주소를 확인하지 못했습니다.');
 validatePlace(actual,{...original,name:target.name});
 return target;
}
export function rememberedPlace(records,original) {
 const entry=records?.[confirmedPlaceKey(original)];
 if(!entry||entry.url!==original.url)return null;
 try{return confirmSelectedPlace({...entry,ready:true},original);}catch{return null;}
}

export function infoBlockPoint(blogID,kind) {
 const url=new URL(location.href);
 if(url.host!=='blog.naver.com'||url.pathname!=='/PostWriteForm.naver'||url.searchParams.get('blogId')!==blogID)throw new Error('글쓰기 대상이 바뀌었습니다.');
 let el;
 if(kind==='menu')el=document.querySelector('button[data-name="quotation"][data-type="icon-select"][aria-haspopup="true"]');
 if(kind==='line')el=document.querySelector('button[data-name="quotation"][data-role="option"][data-value="quotation_line"]');
 if(kind==='content')el=[...document.querySelectorAll('.se-component.se-quotation')].at(-1)?.querySelector('.se-quote .se-text-paragraph');
 if(kind==='after')el=[...document.querySelectorAll('button')].find(e=>(e.getAttribute('aria-label')||'')==='본문 추가'||e.textContent.trim()==='본문 추가');
 if(!el)return {error:`방문정보 인용구 도구를 확인하지 못했습니다 (${kind}).`};
 el.scrollIntoView({block:'center',behavior:'instant'});const r=el.getBoundingClientRect();
 if(!r.width||!r.height)return {error:`방문정보 인용구 버튼이 표시되지 않았습니다 (${kind}).`};
 return {x:r.left+Math.min(r.width/2,30),y:r.top+r.height/2};
}
