import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {inspectEditor,photoUploadComplete,editorPoint} from '../chrome-extension/post-packet.js';
const require=createRequire(import.meta.url);
const {JSDOM}=require(process.env.EXTENSION_TEST_JSDOM||'/tmp/blog-assistant-extension-check/node_modules/jsdom');
const dom=new JSDOM(`<div class="se-components-wrap"><div class="se-component se-image"><img class="se-image-resource" src="blob:https://blog.naver.com/preview"></div></div>
<div class="se-progressbar"></div>
<button data-name="image" class="se-insert-menu-button">hidden menu</button>
<button data-name="image" class="se-image-toolbar-button">toolbar</button>`,{url:'https://blog.naver.com/PostWriteForm.naver?blogId=bluedog129'});
Object.assign(globalThis,{document:dom.window.document,location:dom.window.location,NodeFilter:dom.window.NodeFilter,
  getComputedStyle:dom.window.getComputedStyle.bind(dom.window)});
for(const el of document.querySelectorAll('*')){
 el.getBoundingClientRect=()=>({left:el.classList.contains('se-image-toolbar-button')?200:0,top:0,width:100,height:20});
 el.scrollIntoView=()=>{};
}
const img=document.querySelector('img'),progress=document.querySelector('.se-progressbar');
let complete=false,width=0;
Object.defineProperties(img,{complete:{get:()=>complete},naturalWidth:{get:()=>width}});
let state=inspectEditor('bluedog129');
assert.equal(state.imageCount,1);assert.equal(state.uploadDiagnostics.imageReadyCount,0);
assert.equal(state.uploadDiagnostics.uploadBusy,true);assert.equal(photoUploadComplete(state,0),false);

complete=true;width=100;progress.style.display='none';
state=inspectEditor('bluedog129');
assert.equal(photoUploadComplete(state,0),false,'A loaded blob preview is not an uploaded image');
img.src='https://blogfiles.pstatic.net/uploaded.jpg';
complete=false;state=inspectEditor('bluedog129');
assert.equal(photoUploadComplete(state,0),false,'A remote image must finish loading');
complete=true;width=0;state=inspectEditor('bluedog129');
assert.equal(photoUploadComplete(state,0),false,'A broken image must not count as complete');
width=100;state=inspectEditor('bluedog129');
assert.equal(state.uploadDiagnostics.imageReadyCount,1);
assert.equal(state.uploadDiagnostics.uploadBusy,false);assert.equal(photoUploadComplete(state,0),true);
progress.style.display='block';
assert.equal(photoUploadComplete(inspectEditor('bluedog129'),0),false,'A visible upload progress bar must finish');
assert.equal(photoUploadComplete(state,1),false,'Exactly one new component must be present');
assert.equal(photoUploadComplete({imageCount:1},0),false,'Missing readiness evidence must never be accepted');
assert.equal(editorPoint('bluedog129','photo').x,230,'Choose the toolbar, not the duplicate insert-menu button');
console.log('Passed uploaded-image readiness: placeholders, blob previews, loading/broken images, upload progress, missing evidence and toolbar targeting');
