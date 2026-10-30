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

// Previously uploaded photos can return to SVG placeholders during editor redraw.
// A pending new photo must still block, but an old placeholder must not block it.
const previousIDs=['uploaded-1','uploaded-2'];
const redraw={imageCount:3,uploadDiagnostics:{imageReadyCount:2,uploadBusy:false,imageStates:[
 {id:'uploaded-1',ready:true},{id:'uploaded-2',ready:false},{id:'new-3',ready:true}
]}};
assert.equal(photoUploadComplete(redraw,2,previousIDs),true,'Only the newly inserted photo needs fresh readiness evidence');
const pending=structuredClone(redraw);pending.uploadDiagnostics.imageStates[2].ready=false;
assert.equal(photoUploadComplete(pending,2,previousIDs),false,'Never accept a pending new photo because older ones loaded');
const replaced=structuredClone(redraw);replaced.uploadDiagnostics.imageStates[0].id='replacement-1';
assert.equal(photoUploadComplete(replaced,2,previousIDs),false,'Existing photo identities must be preserved');
const duplicate=structuredClone(redraw);duplicate.uploadDiagnostics.imageStates[2].id='uploaded-1';
assert.equal(photoUploadComplete(duplicate,2,previousIDs),false,'Duplicate component identities are not completion evidence');
const reordered=structuredClone(redraw);reordered.uploadDiagnostics.imageStates.reverse();
assert.equal(photoUploadComplete(reordered,2,previousIDs),false,'The existing photo order must remain unchanged');
const noIdentity=structuredClone(redraw);noIdentity.uploadDiagnostics.imageStates[2].id=null;
assert.equal(photoUploadComplete(noIdentity,2,previousIDs),false);
assert.equal(photoUploadComplete({...redraw,uploadDiagnostics:{...redraw.uploadDiagnostics,uploadBusy:true}},2,previousIDs),false);
console.log('Passed per-photo completion across old-image placeholder redraws, pending-new-photo blocking and identity preservation');

// Exercise the real DOM observer, not only a hand-written readiness summary.
progress.style.display='none';
const older=document.querySelector('.se-component.se-image');older.setAttribute('data-compid','older');
img.src='data:image/svg+xml,placeholder';
const newer=document.createElement('div');newer.className='se-component se-image';newer.setAttribute('data-compid','newer');
newer.innerHTML='<img class="se-image-resource" src="https://blogfiles.pstatic.net/new.jpg">';
Object.defineProperties(newer.querySelector('img'),{complete:{value:true},naturalWidth:{value:100}});
document.querySelector('.se-components-wrap').append(newer);
const observed=inspectEditor('bluedog129');
assert.deepEqual(observed.uploadDiagnostics.imageStates,[{id:'older',ready:false},{id:'newer',ready:true}]);
assert.equal(observed.uploadDiagnostics.imageReadyCount,1);
assert.equal(photoUploadComplete(observed,1,['older']),true);
newer.querySelector('img').src='blob:pending';
assert.equal(photoUploadComplete(inspectEditor('bluedog129'),1,['older']),false);
console.log('Passed live-shaped DOM component IDs and new-photo-only readiness with a prior SVG placeholder');
