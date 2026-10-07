import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {inspectPage} from "../chrome-extension/extractor.js";
const require=createRequire(import.meta.url);
const {JSDOM}=require(process.env.EXTENSION_TEST_JSDOM || "/tmp/blog-assistant-extension-check/node_modules/jsdom");
const settings={blogID:"bluedog129",categoryNo:"65",categoryName:"맛집탐방",postID:"123"};
function page(html,url) {
  const dom=new JSDOM(html,{url});
  globalThis.document=dom.window.document;
  globalThis.location=dom.window.location;
  globalThis.getComputedStyle=dom.window.getComputedStyle.bind(dom.window);
}
function row(id,date,classes="") {
  return `<tr class="${classes}"><td class="title"><a href="/PostView.naver?blogId=bluedog129&logNo=${id}&categoryNo=65">글 ${id}</a></td><td class="date">${date}</td></tr>`;
}
page(`<h4><a id="categoryTitle">맛집탐방</a> 8개의 글</h4><table class="blog2_list"><tbody>${row(999,"2026. 10. 7.","notice")}${row(10,"2026. 9. 1.")}${row(11,"2026. 9. 2.")}${row(12,"2026. 9. 3.")}${row(13,"2026. 9. 4.")}${row(14,"2026. 9. 5.")}${row(15,"2026. 9. 6.")}${row(15,"2026. 9. 6.")}</tbody></table>`,"https://blog.naver.com/PostList.naver?blogId=bluedog129&categoryNo=65");
assert.deepEqual(inspectPage("list",settings).links.map(p=>p.postID),["15","14","13","12","11"]);
assert(inspectPage("list",{...settings,categoryName:"여행"}).error);
assert.equal(inspectPage("list",{...settings,blogID:"someone-else"}),null);
page('<h4><a id="categoryTitle">맛집탐방</a> 0개의 글</h4>',"https://blog.naver.com/PostList.naver?blogId=bluedog129&categoryNo=65");
assert.deepEqual(inspectPage("list",settings).links,[]);
const article=`<div id="post-view123"><div class="blog2_series"><a href="/PostList.naver?blogId=bluedog129&categoryNo=65">맛집탐방</a></div><div class="se-title-text">테스트 식당 후기</div><span class="se_publishDate">2026. 9. 10. 16:34</span><div class="se-main-container"><div class="se-component se-text"><p class="se-text-paragraph">도입</p><p class="se-text-paragraph">\u200b</p></div><div class="se-component se-image"><div class="se-module-image"></div></div><div class="se-component se-text"><p class="se-text-paragraph">메뉴 감상</p></div><div class="se-component se-imageGroup"><div class="se-module-image"></div><div class="se-module-image"></div></div><div class="se-component se-oglink"><script>evil()</script></div></div><div class="comments">댓글은 제외</div></div>`;
page(article,"https://blog.naver.com/PostView.naver?blogId=bluedog129&logNo=123&categoryNo=65");
const extracted=inspectPage("article",settings);
assert.equal(extracted.publishedDate,"2026-09-10");
assert.equal(extracted.photoCount,3);
assert.equal(extracted.body,"도입\n\n[사진]\n\n메뉴 감상\n\n[사진]\n\n[사진]\n\n[장소/링크]");
assert.equal(extracted.url,"https://blog.naver.com/bluedog129/123");
assert(!extracted.body.includes("댓글"));
assert(!extracted.body.includes("evil"));
assert.equal(inspectPage("article",{...settings,postID:"456"}),null);
page(article.replace("categoryNo=65","categoryNo=66"),"https://blog.naver.com/PostView.naver?blogId=bluedog129&logNo=123&categoryNo=65");
assert(inspectPage("article",settings).error);
console.log("Passed extension category validation, latest-five ordering, notice/dedup filtering, body/photo markers and wrong-post checks");
