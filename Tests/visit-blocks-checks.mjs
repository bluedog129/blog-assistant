import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {inspectPlaceDialog,placeControlPoint,matchingPlaceIndex,validatePlace,infoBlockPoint,confirmedPlaceKey,confirmSelectedPlace,rememberedPlace} from '../chrome-extension/visit-blocks.js';
import {inspectEditor,validatePacket,validateContent,paragraphStyle} from '../chrome-extension/post-packet.js';
const require=createRequire(import.meta.url);
const {JSDOM}=require(process.env.EXTENSION_TEST_JSDOM||'jsdom');
const place={name:'테스트 가게',address:'서울 예시로 1 1층',url:'https://naver.me/Example1'};
const result={name:place.name,address:'서울특별시 예시로 1 1층'};
assert.equal(matchingPlaceIndex([result],place),0);
for(const results of [[],[result,result],[{...result,name:'다른 지점'}],[{...result,address:'서울특별시 예시로 2 1층'}]])assert.equal(matchingPlaceIndex(results,place),-1);
assert.equal(matchingPlaceIndex([result],{...place,address:''}),-1,'A name alone must never choose a branch automatically');
assert.doesNotThrow(()=>validatePlace({...result,ready:true},place));
for(const actual of [{...result,ready:false},{...result,name:'다른 지점',ready:true},{...result,address:'서울 예시로 2',ready:true}])assert.throws(()=>validatePlace(actual,place));
// Reproduce the reported working-name / registered-name mismatch. A user picker
// confirmation establishes a separate canonical target; ordinary checks stay strict.
const aliasRequest={name:'브리비트 강남',address:'',url:'https://naver.me/ExampleAlias'};
const aliasMap={name:'브리비트 강남역',address:'서울특별시 강남구 예시로 1 1층',ready:true};
assert.throws(()=>validatePlace(aliasMap,aliasRequest));
const confirmedAlias=confirmSelectedPlace(aliasMap,aliasRequest);
assert.doesNotThrow(()=>validatePlace(aliasMap,confirmedAlias));
const aliasPacket={title:'제목',version:4,photos:[],blocks:[{kind:'map',place:confirmedAlias},{kind:'text',text:'후기'}]};
const aliasState={title:'제목',imageCount:0,mapCount:1,components:[{kind:'map',place:aliasMap},{kind:'text',text:'후기'}]};
assert.doesNotThrow(()=>validateContent(aliasState,aliasPacket));
assert.throws(()=>validateContent(aliasState,{...aliasPacket,blocks:[{kind:'map',place:aliasRequest},aliasPacket.blocks[1]]}));
const memories={[confirmedPlaceKey(aliasRequest)]:confirmedAlias};
assert.deepEqual(rememberedPlace(memories,aliasRequest),confirmedAlias);
assert.equal(rememberedPlace(memories,{...aliasRequest,url:'https://naver.me/OtherBranch'}),null);
assert.equal(rememberedPlace(memories,{...aliasRequest,address:'서울 다른길 2'}),null);
assert.throws(()=>confirmSelectedPlace(aliasMap,{...aliasRequest,address:'서울 다른길 2'}));
assert.throws(()=>confirmSelectedPlace({...aliasMap,ready:false},aliasRequest));

const dom=new JSDOM(`<button data-name="map">장소 추가</button><button data-name="quotation" data-type="icon-select">인용구 선택</button><button data-name="quotation" data-role="option" data-value="quotation_line">인용구 2</button>
<div class="se-popup-placesMap"><input placeholder="장소명을 입력하세요."><ul><li class="se-place-map-search-result-item"><a class="se-place-map-search-result-link"><strong class="se-place-map-search-result-title">${result.name}</strong><span class="se-place-map-search-result-address">${result.address}</span></a><button class="se-place-add-button">추가</button></li></ul><button>확인</button></div>
<article><div class="se-components-wrap"><div class="se-component se-documentTitle"><p class="se-text-paragraph"><span class="__se-node">샘플 제목</span></p></div>
<div class="se-component se-placesMap"><div class="se-module-map-image"><img class="se-map-image" src="https://simg.pstatic.net/static.map/test.png"></div><strong class="se-map-title">${result.name}</strong><p class="se-map-address">${result.address}</p></div>
<div class="se-component se-quotation se-l-quotation_line"><div class="se-quote"><p class="se-text-paragraph"><span class="__se-node">⏰ 영업시간: 매일 10:00–21:30</span></p></div><div class="se-cite"><p class="se-text-paragraph"><span class="__se-node">출처 아님</span></p></div></div>
<div class="se-component se-text"><p class="se-text-paragraph"><span class="__se-node">메뉴 감상</span></p></div></div></article><button>본문 추가</button>`,{url:'https://blog.naver.com/PostWriteForm.naver?blogId=bluedog129'});
Object.assign(globalThis,{window:dom.window,document:dom.window.document,location:dom.window.location,NodeFilter:dom.window.NodeFilter,getComputedStyle:dom.window.getComputedStyle});
dom.window.HTMLElement.prototype.getBoundingClientRect=function(){return {x:0,y:0,left:0,top:0,width:100,height:20};};
dom.window.HTMLElement.prototype.scrollIntoView=function(){};
const image=document.querySelector('.se-map-image');Object.defineProperties(image,{complete:{value:true},naturalWidth:{value:700}});
// Captured Naver toolbar: both Add and Select share data-type=icon-select.
const quoteMenu=document.querySelector('button[data-name="quotation"][data-type="icon-select"]');
quoteMenu.setAttribute('aria-haspopup','true');
quoteMenu.getBoundingClientRect=()=>({left:50,top:47,width:11,height:34});
quoteMenu.insertAdjacentHTML('beforebegin','<button data-name="quotation" data-type="icon-select" data-value="default" aria-haspopup="false">인용구 추가</button>');
assert.deepEqual(infoBlockPoint('bluedog129','menu'),{x:55.5,y:64},'Open the Select dropdown, not the adjacent Add button');
const lineOption=document.querySelector('button[data-name="quotation"][data-role="option"]');
lineOption.remove();
assert.match(infoBlockPoint('bluedog129','line').error,/인용구.*line/);
document.body.append(lineOption);
assert.deepEqual(inspectPlaceDialog('bluedog129').results,[result]);
assert.ok(placeControlPoint('bluedog129','toolbar'));
for(const kind of ['result','add'])assert.ok(placeControlPoint('bluedog129',kind,0,result));
assert.throws(()=>placeControlPoint('bluedog129','add',0,{...result,address:'다른 주소'}));
for(const kind of ['menu','line','content','after'])assert.ok(infoBlockPoint('bluedog129',kind));
const inspected=inspectEditor('bluedog129');
assert.equal(inspected.imageCount,0,'The map must not count as a photo');
assert.equal(inspected.mapCount,1);assert.equal(inspected.components[0].kind,'map');assert.equal(inspected.components[0].place.ready,true);
assert.equal(inspected.components[1].kind,'info');assert.equal(inspected.components[1].infoStyle,'line');assert.ok(!inspected.components[1].text.includes('출처'));
const paragraphs=[{role:'info',runs:[{text:'⏰ ',bold:false},{text:'영업시간:',bold:true},{text:' 매일 10:00–21:30',bold:false}]}];
const info={kind:'info',text:paragraphs.map(p=>p.runs.map(r=>r.text).join('')).join('\n'),paragraphs};
const body={kind:'text',text:'감상',paragraphs:[{role:'body',runs:[{text:'감상',bold:false}]}]};
const packet={type:'blog-assistant.naver-post',version:4,template:'record',blogID:'bluedog129',categoryNo:'65',title:'샘플 제목',blocks:[{kind:'map',place},info,body],photos:[]};
assert.equal(validatePacket(packet,new Map()),packet);
for(const change of [{version:3},{blocks:[{kind:'map',place:{...place,url:'https://evil.example/x'}},info]},{blocks:[packet.blocks[0],packet.blocks[0],info]},{blocks:[info,info]},{template:null}])assert.throws(()=>validatePacket({...packet,...change},new Map()));
const style=(p,quote)=>({align:'left',runs:p.runs.map(r=>{const s=paragraphStyle(p.role,r.bold);return {...r,size:s.size,color:`rgb(${parseInt(s.color.slice(1,3),16)}, ${parseInt(s.color.slice(3,5),16)}, ${parseInt(s.color.slice(5,7),16)})`,font:quote?'se-nanumbarungothic':'se-nanumgothic'};})});
const state={title:packet.title,mapCount:1,imageCount:0,components:[{kind:'map',place:{...result,ready:true}},{...info,infoStyle:'line',paragraphs:paragraphs.map(p=>style(p,true))},{...body,paragraphs:body.paragraphs.map(p=>style(p,false))}]};
assert.doesNotThrow(()=>validateContent(state,packet));
for(const mutation of [s=>s.mapCount=0,s=>s.components[0].place.ready=false,s=>s.components[0].place.address='다른 주소',s=>s.components[1].infoStyle='bubble',s=>s.components.reverse(),s=>s.components[1].paragraphs[0].runs[1].bold=false]){const bad=structuredClone(state);mutation(bad);assert.throws(()=>validateContent(bad,packet));}

// Exercise the actual controller functions: trusted search/add/confirm, manual
// branch selection, delayed map readiness and quote exit before further body input.
const source=fs.readFileSync('chrome-extension/posting.js','utf8');
const clickContext=vm.createContext({command:async()=>{throw new Error('Unexpected input');},delay:async()=>{}});
vm.runInContext(source.slice(source.indexOf('async function click('),source.indexOf('async function key(')),clickContext);
await assert.rejects(()=>vm.runInContext(`click({error:'방문정보 인용구 목록이 없습니다 (line).'})`,clickContext),/방문정보 인용구 목록.*line/);
let confirmedRecords={};
for(const scenario of ['automatic','manual-no-address','manual-ambiguous','wrong-place','map-never-ready','manual-alias','remembered-alias','manual-wrong-address']){
 let now=0,focus,closed=false,mapAdded=false,polls=0;
 const actions=[];
 const editor={mapCount:0,components:[],bodyPoint:{x:1,y:1}};
 const observed=scenario.includes('alias')?{...result,name:'테스트 가게역'}:scenario==='manual-wrong-address'?{...result,address:'서울 다른길 2'}:result;
 const dialog={open:true,results:scenario==='manual-ambiguous'?[observed,observed]:[observed],confirmEnabled:false};
 const addMap=()=>{closed=true;mapAdded=true;editor.mapCount=1;editor.components=[{kind:'map',place:{...observed,name:scenario==='wrong-place'?'다른 매장':observed.name,ready:scenario!=='map-never-ready'}},{kind:'text'}];};
 const context=vm.createContext({packet:{blogID:'bluedog129'},inspectPlaceDialog,placeControlPoint,matchingPlaceIndex,validatePlace,infoBlockPoint,confirmedPlaceKey,confirmSelectedPlace,rememberedPlace,
  diagnostics:{record(){}},chrome:{storage:{local:{get:async()=>({confirmedPlacesV1:structuredClone(confirmedRecords)}),set:async value=>{confirmedRecords=value.confirmedPlacesV1;}}}},Date:{now:()=>now},check(){},status:msg=>{actions.push('manual');addMap();},delay:async ms=>{now+=ms;},
  inspect:async()=>structuredClone(editor),
  execute:async(fn,args)=>{
   if(fn===inspectPlaceDialog)return {...dialog,open:!closed};
   focus=args[1];return {kind:args[1]};
  },
  click:async p=>{actions.push(p.kind);if(p.kind==='add')dialog.confirmEnabled=true;if(p.kind==='confirm')addMap();if(p.kind==='line')editor.components.push({kind:'info',infoStyle:'line'});if(p.kind==='after')editor.components.push({kind:'text'});},
  command:async(method,args)=>actions.push(method==='Input.insertText'?args.text:method),key:async name=>actions.push(name),pointFor:async kind=>({kind}),
  waitFor:async(test,msg)=>{for(let i=0;i<5;i++){if(test(editor))return editor;}throw new Error(msg);},chooseStyle:async()=>{},styleControl:async()=>({selected:false}),insertStyledText:async()=>actions.push('info-text')
 });
 vm.runInContext(source.slice(source.indexOf('async function insertPlace('),source.indexOf("$('files').addEventListener('change'")),context);
 context.target={...place,address:scenario==='manual-no-address'||scenario.includes('alias')?'':place.address};
 if(['wrong-place','map-never-ready','manual-wrong-address'].includes(scenario))await assert.rejects(()=>vm.runInContext('insertPlace(target)',context));
 else{
  const canonical=await vm.runInContext('insertPlace(target)',context);
  assert.doesNotThrow(()=>validatePlace(editor.components.find(b=>b.kind==='map').place,canonical));
  if(scenario.includes('alias'))assert.equal(canonical.name,'테스트 가게역');
  assert.ok(mapAdded);assert.equal(actions.includes('manual'),scenario.startsWith('manual'));
  if(scenario==='automatic')assert.ok(actions.indexOf('result')<actions.indexOf('add')&&actions.indexOf('add')<actions.indexOf('confirm'));
  await vm.runInContext(`insertInfo(${JSON.stringify(paragraphs)})`,context);
  assert.equal(editor.components.at(-1).kind,'text');assert.ok(actions.indexOf('info-text')<actions.lastIndexOf('after'));
 }
}
console.log('Passed v4 native map/info packets, exact branch matching, DOM inspection, quote style/order rejection, automatic/manual selection, failed-map stop and quote exit');
