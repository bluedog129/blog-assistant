import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {paragraphStyle,validateContent} from '../chrome-extension/post-packet.js';

// Exercise the real input sequence with an editor model. Enter, toolbar clicks,
// inherited styles, an intervening image and split emoji input all affect state.
const source=fs.readFileSync('chrome-extension/posting.js','utf8');
const start=source.indexOf('async function insertBodyText(');
const end=source.indexOf('async function waitFor(',start);
const style={bold:true,size:24,color:'#000000',font:'serif',align:'center',italic:true,underline:true,strikethrough:true};
const components=[];
let popup=null;
const colorRGB=hex=>`rgb(${parseInt(hex.slice(1,3),16)}, ${parseInt(hex.slice(3,5),16)}, ${parseInt(hex.slice(5,7),16)})`;
function paragraph(){
 if(components.at(-1)?.kind!=='text')components.push({kind:'text',paragraphs:[{align:style.align,runs:[]}]});
 return components.at(-1).paragraphs.at(-1);
}
const selected=name=>name==='bold'?style.bold:!!style[name];
const context=vm.createContext({
 packet:{blogID:'bluedog129'},paragraphStyle,formattingControls:()=>{},delay:async()=>{},
 execute:async(fn,[blogID,name,value])=>{
   assert.equal(blogID,'bluedog129');
   if(value!==null)assert.ok(popup===name||(name==='color-option'&&popup==='font-color'));
   return {point:{name,value},selected:selected(name),text:name==='font-size'?String(style.size):undefined,color:name==='font-color'?colorRGB(style.color):undefined};
 },
 click:async({name,value})=>{
   if(value===null){
     if(['bold','italic','underline','strikethrough'].includes(name)){style[name]=!style[name];return;}
     popup=name;return;
   }
   if(name==='font-size')style.size=Number(value.replace('fs',''));
   if(name==='font-family')style.font=value;
   if(name==='align-drop-down-with-justify')style.align=value;
   if(name==='color-option')style.color=value;
   if(name==='line-height')style.lineHeight=Number(value);
   popup=null;
 },
 command:async(method,{text})=>{
   assert.equal(method,'Input.insertText');assert.ok(!text.includes('\n')&&!text.includes('**')&&!text.includes('## '));
   const p=paragraph();p.align=style.align;
   p.runs.push({text,bold:style.bold,size:style.size,color:colorRGB(style.color),font:'se-'+style.font});
 },
 key:async(name)=>{assert.equal(name,'Enter');paragraph();components.at(-1).paragraphs.push({align:style.align,runs:[]});}
});
vm.runInContext(source.slice(start,end),context);
await vm.runInContext('prepareRecordStyle()',context);
assert.equal(style.font,'nanumgothic');assert.equal(style.align,'left');assert.equal(style.lineHeight,180);
assert.ok(!style.italic&&!style.underline&&!style.strikethrough);
const before=[{role:'section',runs:[{text:'방문 전 확인',bold:true}]},{role:'info',runs:[{text:'영업시간',bold:true},{text:': 11:00–21:00',bold:false}]},{role:'body',runs:[]},{role:'menu',runs:[{text:'파스타',bold:true}]},{role:'price',runs:[{text:'가격: 18,000원',bold:false}]}];
const after=[{role:'body',runs:[{text:'첫입은 ',bold:false},{text:'담백한 점',bold:true},{text:'이 좋았어요 😊',bold:false}]}];
await vm.runInContext(`insertStyledText(${JSON.stringify(before)})`,context);
assert.equal(style.bold,false);assert.equal(style.size,16);assert.equal(style.color,'#333333');
components.push({kind:'photo',text:''});
// Simulate the editor inheriting a large bold format after image insertion.
Object.assign(style,{bold:true,size:24,color:'#000000'});
await vm.runInContext(`insertStyledText(${JSON.stringify(after)})`,context);
for(const component of components)if(component.kind==='text')component.text=component.paragraphs.map(p=>p.runs.map(r=>r.text).join('')).join('\n');
const block=paragraphs=>({kind:'text',text:paragraphs.map(p=>p.runs.map(r=>r.text).join('')).join('\n'),paragraphs});
const packet={title:'서식 검증',version:2,template:'record',blocks:[block(before),{kind:'photo',photoNumber:1},block(after)],photos:[{}]};
validateContent({title:packet.title,imageCount:1,components},packet);
assert.equal(style.bold,false);
console.log('Passed real styled-input sequence: inherited style reset, explicit labels, price, blank lines, photo positions, split emoji and inline bold boundaries');
