import assert from 'node:assert/strict';
import {validatePacket,validateContent,paragraphStyle,validateFormatting} from '../chrome-extension/post-packet.js';
const packet={type:'blog-assistant.naver-post',version:1,blogID:'bluedog129',categoryNo:'65',title:'식당 후기',blocks:[{kind:'text',text:'첫 문단'},{kind:'photo',photoNumber:1},{kind:'text',text:'메뉴 감상'}],photos:[{number:1,filename:'01_메뉴.jpg',caption:'메뉴'}]};
const files=new Map([['01_메뉴.jpg',{size:1000}]]);
assert.equal(validatePacket(packet,files),packet);
for(const change of [{version:2},{blogID:'other'},{photos:[{number:1,filename:'../secret.jpg'}]},{blocks:[{kind:'photo',photoNumber:2}]},{blocks:[{kind:'text',text:'본문'}]}])assert.throws(()=>validatePacket({...packet,...change},files));
assert.throws(()=>validatePacket(packet,new Map()));
const state={title:packet.title,imageCount:1,components:[{kind:'text',text:'첫 문단'},{kind:'photo',text:''},{kind:'text',text:'메뉴 감상'}]};
assert.doesNotThrow(()=>validateContent(state,packet));
assert.throws(()=>validateContent({...state,title:'다른 제목'},packet));
assert.throws(()=>validateContent({...state,imageCount:0},packet));
assert.throws(()=>validateContent({...state,components:[state.components[1],state.components[0],state.components[2]]},packet));
assert.throws(()=>validateContent({...state,components:[{kind:'text',text:'변경된 문단'},...state.components.slice(1)]},packet));
console.log('Passed posting package validation, missing photo rejection and exact content/photo-order verification');

const paragraphs=[{role:'menu',runs:[{text:'파스타',bold:true}]},{role:'price',runs:[{text:'가격: 18,000원',bold:false}]},{role:'body',runs:[]},{role:'body',runs:[{text:'담백한 점',bold:true},{text:'이 좋았어요.',bold:false}]}];
const styled={...packet,version:2,template:'record',blocks:[{kind:'text',text:paragraphs.map(p=>p.runs.map(r=>r.text).join('')).join('\n'),paragraphs},{kind:'photo',photoNumber:1}]};
assert.equal(validatePacket(styled,files),styled);
for(const change of [{template:'arbitrary'},{blocks:[{...styled.blocks[0],text:'변경된 내용'},styled.blocks[1]]},{blocks:[{...styled.blocks[0],paragraphs:[{role:'html',runs:[]}]}]}])assert.throws(()=>validatePacket({...styled,...change},files));
const rgb=hex=>`rgb(${parseInt(hex.slice(1,3),16)}, ${parseInt(hex.slice(3,5),16)}, ${parseInt(hex.slice(5,7),16)})`;
const styledState={title:styled.title,imageCount:1,components:[{kind:'text',text:styled.blocks[0].text,paragraphs:paragraphs.map(p=>({align:'left',runs:p.runs.map(r=>{const s=paragraphStyle(p.role,r.bold);return {...r,size:s.size,color:rgb(s.color),font:'se-nanumgothic, sans-serif'};})}))},{kind:'photo',text:''}]};
assert.doesNotThrow(()=>validateContent(styledState,styled));
for(const change of [{bold:false},{size:16},{color:'rgb(0, 0, 0)'},{font:'serif'}]){
 const bad=structuredClone(styledState);Object.assign(bad.components[0].paragraphs[0].runs[0],change);assert.throws(()=>validateFormatting(bad,styled));
}
const inherited=structuredClone(styledState);inherited.components[0].paragraphs.at(-1).runs[1].bold=true;
assert.throws(()=>validateContent(inherited,styled));
const merged=structuredClone(styledState);merged.components[0].paragraphs.at(-1).runs=[{...merged.components[0].paragraphs.at(-1).runs[0],text:'담백한 점이 좋았어요.'}];
assert.throws(()=>validateContent(merged,styled));
const wrapped=structuredClone(styledState);const r=wrapped.components[0].paragraphs[0].runs[0];wrapped.components[0].paragraphs[0].runs=[{...r,text:'파'},{...r,text:'스타'}];
assert.doesNotThrow(()=>validateContent(wrapped,styled));
console.log('Passed v2 template validation, marker-free text, split spans and formatting mismatch/save rejection');
