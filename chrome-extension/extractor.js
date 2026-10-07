// Self-contained: Chrome serializes this function into the page's isolated world.
export function inspectPage(mode, expected) {
  const clean = value => (value || "").replace(/[\u200b\ufeff]/g, "").replace(/\r/g, "").trim();
  const date = value => {
    const match = clean(value).match(/(\d{4})\s*\.\s*(\d{1,2})\s*\.\s*(\d{1,2})/);
    return match ? `${match[1]}-${match[2].padStart(2,"0")}-${match[3].padStart(2,"0")}` : null;
  };
  const pageURL = new URL(location.href);
  if (pageURL.hostname !== "blog.naver.com" || pageURL.searchParams.get("blogId") !== expected.blogID) return null;
  if (mode === "list") {
    if (pageURL.searchParams.get("categoryNo") !== expected.categoryNo) return null;
    const category = clean(document.querySelector("#categoryTitle")?.textContent);
    if (!category) return null;
    if (category !== expected.categoryName) return {error:`카테고리 이름이 '${category}'입니다. 설정을 확인하세요.`};
    const table = document.querySelector(".blog2_list");
    if (!table) {
      if (/0\s*개의 글/.test(document.querySelector("#categoryTitle")?.parentElement?.textContent || "")) return {links:[], categoryName:category};
      const toggle = document.querySelector("a._toggleTopList");
      const wrapper = document.querySelector("#toplistWrapper");
      if (toggle && (!wrapper || getComputedStyle(wrapper).display === "none")) toggle.click();
      return null;
    }
    const links = [];
    for (const row of table.querySelectorAll("tbody tr")) {
      // Skip pinned notices rather than treating them as recent posts.
      if (/notice|noti/i.test(row.className) || row.querySelector(".icon_notice, .ico_notice")) continue;
      const anchor = row.querySelector("td.title a[href*='logNo=']");
      if (!anchor) continue;
      const url = new URL(anchor.href, location.href);
      const postID = url.searchParams.get("logNo");
      if (url.hostname !== "blog.naver.com" || url.searchParams.get("blogId") !== expected.blogID || !/^\d+$/.test(postID || "")) continue;
      const publishedDate = date(row.querySelector("td.date")?.textContent);
      if (!publishedDate) return {error:"목록 작성일을 읽지 못했습니다. 최신순을 확인할 수 없어 수집을 중단합니다."};
      if (!links.some(p => p.postID === postID)) links.push({postID, title:clean(anchor.textContent), publishedDate});
    }
    if (!links.length && !/0\s*개의 글/.test(document.querySelector("#categoryTitle")?.parentElement?.textContent || "")) return null;
    links.sort((a,b) => b.publishedDate.localeCompare(a.publishedDate) || (BigInt(a.postID) < BigInt(b.postID) ? 1 : -1));
    return {links:links.slice(0,5), categoryName:category};
  }
  if (pageURL.searchParams.get("logNo") !== expected.postID) return null;
  const root = document.getElementById(`post-view${expected.postID}`);
  if (!root) return null;
  const categoryLink = root.querySelector(".blog2_series a");
  if (!categoryLink) return {error:"글의 카테고리를 확인하지 못했습니다."};
  const categoryURL = new URL(categoryLink.href, location.href);
  if (categoryURL.searchParams.get("categoryNo") !== expected.categoryNo) return {error:"다른 카테고리의 글이어서 제외했습니다."};
  const title = clean(root.querySelector(".se-title-text")?.textContent);
  const publishedDate = date(root.querySelector(".se_publishDate")?.textContent);
  const bodyRoot = root.querySelector(".se-main-container");
  if (!bodyRoot || !title || !publishedDate) return {error:"지원되는 SmartEditor 본문·제목·게시일을 찾지 못했습니다."};
  const blocks = [];
  let photoCount = 0;
  for (const component of bodyRoot.children) {
    if (!component.classList.contains("se-component")) continue;
    if (component.classList.contains("se-image") || component.classList.contains("se-imageGroup")) {
      const count = Math.max(1, component.querySelectorAll(".se-module-image").length);
      photoCount += count;
      blocks.push(...Array(count).fill("[사진]"));
      const captions = [...component.querySelectorAll(".se-caption")].map(p=>clean(p.textContent)).filter(Boolean);
      blocks.push(...captions);
    } else if (component.classList.contains("se-text") || component.classList.contains("se-quotation") || component.classList.contains("se-table")) {
      const paragraphs = [...component.querySelectorAll(".se-text-paragraph")].map(p=>clean(p.textContent)).filter(Boolean);
      blocks.push(paragraphs.join("\n"));
    } else if (component.classList.contains("se-oglink") || component.classList.contains("se-place")) {
      blocks.push("[장소/링크]");
    } else if (component.classList.contains("se-video")) {
      blocks.push("[동영상]");
    }
  }
  const body = blocks.filter(Boolean).join("\n\n");
  if (!body || !blocks.some(b=>b !== "[사진]" && b !== "[장소/링크]" && b !== "[동영상]")) return {error:"본문 텍스트가 없어 제외했습니다."};
  if (body.length > 100000) return {error:"본문이 너무 길어 제외했습니다."};
  return {postID:expected.postID, title, publishedDate, body, photoCount, url:`https://blog.naver.com/${expected.blogID}/${expected.postID}`};
}
