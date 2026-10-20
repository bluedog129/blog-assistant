import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {inspectEditor,preparePhotoUpload,restorePhotoPicker} from '../chrome-extension/post-packet.js';
import {editorSummary} from '../chrome-extension/posting-diagnostics.js';
const require=createRequire(import.meta.url);
const {JSDOM}=require(process.env.EXTENSION_TEST_JSDOM||'/tmp/blog-assistant-extension-check/node_modules/jsdom');
const dom=new JSDOM(`<div class="se-components-wrap">
  <div class="se-component se-documentTitle"><p class="se-text-paragraph"><span class="__se-node">PRIVATE TITLE</span></p></div>
  <div class="se-component se-text"><p class="se-text-paragraph"><span class="__se-node">PRIVATE ARTICLE</span></p></div>
  ${'<div class="se-component se-image"></div>'.repeat(7)}
  </div><button data-name="image" aria-label="사진 추가" aria-disabled="true" disabled>사진</button>
  <input type="file" accept="image/jpeg" multiple disabled style="display:none"><iframe></iframe>`,
  {url:'https://blog.naver.com/PostWriteForm.naver?blogId=bluedog129'});
Object.assign(globalThis,{document:dom.window.document,window:dom.window,location:dom.window.location,
  HTMLInputElement:dom.window.HTMLInputElement,NodeFilter:dom.window.NodeFilter,getComputedStyle:dom.window.getComputedStyle.bind(dom.window)});
for(const el of document.querySelectorAll('*'))el.getBoundingClientRect=()=>({left:0,top:0,width:100,height:20});
const selection=document.getSelection(),range=document.createRange();
range.selectNodeContents(document.querySelector('.se-text .__se-node'));selection.addRange(range);
const before=inspectEditor('bluedog129');
assert.equal(before.imageCount,7);assert.equal(before.fileInputCount,1);
assert.equal(before.uploadDiagnostics.photoButton.disabled,true);
assert.equal(before.uploadDiagnostics.photoButton.ariaDisabled,'true');
assert.equal(before.uploadDiagnostics.iframeCount,1);
assert.match(before.uploadDiagnostics.selectionComponent,/se-text/);
assert.deepEqual(before.uploadDiagnostics.fileInputs,[{accept:'image/jpeg',multiple:true,disabled:true,visible:false,connected:true}]);
assert.ok(!JSON.stringify(editorSummary(before)).includes('PRIVATE'));
assert.throws(()=>preparePhotoUpload('bluedog129'),/사진 추가 버튼/);

const button=document.querySelector('button');button.disabled=false;button.removeAttribute('aria-disabled');
document.querySelector('input').remove();
button.onclick=()=>{const input=document.createElement('input');input.type='file';document.body.append(input);input.click();};
assert.deepEqual(preparePhotoUpload('bluedog129'),{fileInputCountBefore:0,disabled:false,ariaDisabled:null});
assert.equal(document.querySelectorAll('input[type=file]').length,0);
button.click();
assert.equal(inspectEditor('bluedog129').fileInputCount,1);
restorePhotoPicker();
assert.equal(window.__blogAssistantFileClickGuard,undefined);
console.log('Passed upload DOM diagnostics: photo count, hidden/disabled input, button state, selection, iframe count and input creation after click');
