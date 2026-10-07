import { inspectPage } from "./extractor.js";
const $ = id => document.getElementById(id);
let packet = null;
let cancelled = false;
let running = false;
const pause = ms => new Promise(resolve=>setTimeout(resolve,ms));
function render(value) {
  $("articles").replaceChildren();
  for (const post of value.articles) {
    const article = document.createElement("article");
    const heading = document.createElement("h2"); heading.textContent = post.title;
    const info = document.createElement("p"); info.textContent = `${post.publishedDate} · 사진 위치 ${post.photoCount}개`;
    const link = document.createElement("a"); link.href = post.url; link.textContent = "원문 확인"; link.target = "_blank"; link.rel = "noopener";
    const body = document.createElement("pre"); body.textContent = post.body;
    article.append(heading,info,link,body); $("articles").append(article);
  }
  $("warnings").textContent = value.warnings.join("\n");
  $("copy").disabled = value.articles.length === 0;
}
async function read(tabId, mode, expected) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    if (cancelled) throw new Error("수집을 중단했습니다. 이전 결과는 유지됩니다.");
    try {
      const tab = await chrome.tabs.get(tabId);
      if (tab.status === "complete") {
        const frames = await chrome.scripting.executeScript({target:{tabId, allFrames:true}, func:inspectPage, args:[mode,expected]});
        const result = frames.map(f=>f.result).find(Boolean);
        if (result?.error) throw new Error(result.error);
        if (result) return result;
      }
    } catch (error) {
      if (!/frame|Cannot access|No tab|removed/i.test(error.message)) throw error;
      if (/No tab/i.test(error.message)) throw new Error("수집용 탭이 닫혔습니다.");
    }
    await pause(500);
  }
  throw new Error("페이지를 읽지 못했습니다. 로그인·카테고리 설정을 확인하거나 네이버 페이지 구조 변경 여부를 확인하세요.");
}
$("settings").addEventListener("submit", async event => {
  event.preventDefault(); if (running) return;
  const settings = {blogID:$("blogID").value.trim(), categoryNo:$("categoryNo").value.trim(), categoryName:$("categoryName").value.trim()};
  if (!/^[A-Za-z0-9_-]+$/.test(settings.blogID) || !/^\d+$/.test(settings.categoryNo) || !settings.categoryName) return;
  running=true; cancelled=false; $("collect").disabled=true; $("cancel").disabled=false; $("copy").disabled=true;
  let tab;
  try {
    await chrome.storage.local.set({settings});
    const listURL = new URL("https://blog.naver.com/PostList.naver");
    listURL.search = new URLSearchParams({blogId:settings.blogID, categoryNo:settings.categoryNo, currentPage:"1"}).toString();
    $("status").textContent="카테고리의 최근 글 목록을 확인 중…";
    tab=await chrome.tabs.create({url:listURL.href, active:false});
    const list=await read(tab.id,"list",settings);
    if (!list.links.length) throw new Error("이 카테고리에서 읽을 글을 찾지 못했습니다. 이전 결과는 유지됩니다.");
    const articles=[], warnings=[];
    for (const [index,post] of list.links.entries()) {
      if(cancelled) throw new Error("수집을 중단했습니다. 이전 결과는 유지됩니다.");
      $("status").textContent=`본문 확인 중 · ${index+1}/${list.links.length}`;
      const url=new URL("https://blog.naver.com/PostView.naver");
      url.search=new URLSearchParams({blogId:settings.blogID, logNo:post.postID, categoryNo:settings.categoryNo}).toString();
      await chrome.tabs.update(tab.id,{url:url.href});
      try { articles.push(await read(tab.id,"article",{...settings,postID:post.postID})); }
      catch(error) { if(cancelled) throw error; warnings.push(`${post.title}: ${error.message}`); }
    }
    if(cancelled) throw new Error("수집을 중단했습니다. 이전 결과는 유지됩니다.");
    if(!articles.length) throw new Error(warnings.join("\n") || "가져온 본문이 없습니다.");
    articles.sort((a,b)=>b.publishedDate.localeCompare(a.publishedDate) || (BigInt(a.postID)<BigInt(b.postID)?1:-1));
    packet={type:"blog-assistant.references",version:1,...settings,collectedAt:new Date().toISOString(),articles,warnings};
    await chrome.storage.local.set({lastPacket:packet}); render(packet);
    $("status").textContent=`${articles.length}개 글을 가져왔습니다. 내용을 확인하고 복사하세요.${warnings.length?" 일부 글은 수집하지 못했습니다.":""}`;
  } catch(error) { $("status").textContent=error.message; }
  finally {
    if(tab) { try { await chrome.tabs.remove(tab.id); } catch {} }
    running=false; $("collect").disabled=false; $("cancel").disabled=true; $("copy").disabled=!packet;
  }
});
$("cancel").addEventListener("click",()=>{cancelled=true; $("status").textContent="수집 중단 요청 중…";});
$("copy").addEventListener("click",async()=>{
  if(!packet) return;
  try { await navigator.clipboard.writeText(JSON.stringify(packet)); $("status").textContent="복사 완료. Swift 앱에서 ‘참고 글 관리 → 참고 글 붙여넣기’를 누르세요."; }
  catch { $("status").textContent="클립보드 복사에 실패했습니다. 이 탭을 활성화한 뒤 다시 눌러주세요."; }
});
const saved=await chrome.storage.local.get(["settings","lastPacket"]);
if(saved.settings) for(const key of ["blogID","categoryNo","categoryName"]) $(key).value=saved.settings[key];
if(saved.lastPacket) { packet=saved.lastPacket; render(packet); $("status").textContent="이전에 수집한 결과입니다. 새로 가져오거나 내용을 확인한 뒤 복사하세요."; }
