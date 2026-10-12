import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {inspectEditor,formattingControls,validateFormatting} from '../chrome-extension/post-packet.js';
const require=createRequire(import.meta.url);
const {JSDOM}=require(process.env.EXTENSION_TEST_JSDOM||'/tmp/blog-assistant-extension-check/node_modules/jsdom');
const dom=new JSDOM(`<article><div class="se-components-wrap">
<div class="se-component se-documentTitle"><p class="se-text-paragraph"><span class="__se-node">제목</span></p></div>
<div class="se-component se-text"><p class="se-text-paragraph" style="text-align:left"><span class="__se-node" style="font-size:16px;font-family:se-nanumgothic;color:#333333;font-weight:400"><b style="font-size:16px;font-family:se-nanumgothic;color:#333333;font-weight:700">담백한 점</b>이 좋았어요.</span></p></div>
</div></article>
<button data-name="bold" class="se-is-selected">굵기 해제</button>
<button data-name="bold" style="display:none">숨겨진 도구</button>
<button data-name="font-size"><span class="se-toolbar-label">16</span></button>
<button data-name="font-size" data-role="option" data-value="fs19">19</button>
<div class="se-property-color-picker-container" data-name="font-color">
<button data-name="font-color"><span data-role="color" style="background-color:#003960"></span></button>
<div class="se-color-swatches-used">
<button data-color="#333333">#333333</button><button data-color="#777777">#777777</button><button data-color="#003960">#003960</button>
</div>
<div class="se-color-swatches-preset">
<button data-color="#333333">#333333</button><button data-color="#777777">#777777</button><button data-color="#003960">#003960</button>
</div></div>
<div class="se-property-color-picker-container" data-name="background-color"><div class="se-color-swatches-preset"><button data-color="#003960">배경색</button></div></div>`,{url:'https://blog.naver.com/PostWriteForm.naver?blogId=bluedog129'});
Object.assign(globalThis,{document:dom.window.document,location:dom.window.location,NodeFilter:dom.window.NodeFilter,getComputedStyle:dom.window.getComputedStyle.bind(dom.window)});
for(const el of document.querySelectorAll('*'))el.getBoundingClientRect=()=>({x:0,y:0,left:el.closest('.se-color-swatches-preset')?200:0,top:0,width:el.style.display==='none'?0:100,height:el.style.display==='none'?0:20});
const state=inspectEditor('bluedog129');
assert.equal(state.title,'제목');
assert.equal(state.components[0].text,'담백한 점이 좋았어요.');
assert.deepEqual(state.components[0].paragraphs[0].runs.map(r=>[r.text,r.bold]),[['담백한 점',true],['이 좋았어요.',false]]);
validateFormatting(state,{blocks:[{kind:'text',paragraphs:[{role:'body',runs:[{text:'담백한 점',bold:true},{text:'이 좋았어요.',bold:false}]}]}]});
assert.equal(formattingControls('bluedog129','bold',null).selected,true);
assert.equal(formattingControls('bluedog129','font-size',null).text,'16');
assert.ok(formattingControls('bluedog129','font-size','fs19').point);
assert.equal(formattingControls('bluedog129','font-color',null).color,'rgb(0, 57, 96)');
for(const color of ['#333333','#777777','#003960']){
  assert.deepEqual(formattingControls('bluedog129','color-option',color).point,{x:250,y:10});
}
const palette=document.querySelector('[data-name="font-color"] .se-color-swatches-preset');
palette.remove();
assert.deepEqual(formattingControls('bluedog129','color-option','#003960').point,{x:50,y:10});
document.querySelector('[data-name="font-color"] .se-color-swatches-used').remove();
assert.throws(()=>formattingControls('bluedog129','color-option','#003960'),/서식 도구/);
assert.throws(()=>formattingControls('other','bold',null));
document.querySelector('button[data-name=bold]').remove();
assert.throws(()=>formattingControls('bluedog129','bold',null));
console.log('Passed nested bold/plain DOM inspection, hidden toolbar exclusion, native size/color options, duplicate recent/preset colors, background-color exclusion and wrong-target rejection');
