chrome.action.onClicked.addListener(() => {
  chrome.tabs.create({ url: chrome.runtime.getURL("collector.html") });
});

// Chrome opens its own extension pages; macOS only opens a regular HTTPS URL.
let checking = false;
let openedJob = null;
async function checkPendingJob() {
  if (checking) return "연결 확인 중입니다. 잠시 후 다시 확인하세요.";
  checking = true;
  try {
    const { appBridgeToken } = await chrome.storage.local.get('appBridgeToken');
    if (!appBridgeToken) return "저장된 연결 코드가 없습니다. 앱 연결 코드를 복사해 앱에 저장하세요.";
    const response = await fetch('http://127.0.0.1:48765/pending', {
      headers: { 'X-Blog-Assistant-Token': appBridgeToken },
      signal: AbortSignal.timeout(4000)
    });
    if (!response.ok) return response.status === 403 ? "연결 코드가 앱과 일치하지 않습니다. 앱 연결 코드를 다시 복사해 앱의 Chrome 연결에 저장하세요." : `앱 응답 오류: HTTP ${response.status}`;
    const { jobID } = await response.json();
    if (!jobID) return "앱 연결 정상 · 대기 작업이 없습니다. 앱에서 네이버 임시저장을 누르세요.";
    if (!/^[0-9a-f-]{36}$/i.test(jobID)) return "앱 작업 번호 형식 오류";
    if (openedJob === jobID) return "이미 작업 화면을 열었습니다. Chrome의 네이버 임시저장 진행 탭을 확인하세요.";
    const url = chrome.runtime.getURL(`posting.html?job=${encodeURIComponent(jobID)}`);
    const existing = await chrome.tabs.query({});
    if (!existing.some(tab => tab.url === url)) await chrome.tabs.create({ url });
    openedJob = jobID;
    return "작업을 받아 네이버 임시저장 진행 화면을 열었습니다.";
  } catch {
    return "앱에 연결할 수 없습니다. 앱 실행 여부와 확장 프로그램의 127.0.0.1 접근 권한을 확인하세요.";
  } finally { checking = false; }
}
async function startBridgePolling() {
  await chrome.alarms.create('blog-assistant-bridge', { periodInMinutes: 0.5 });
  await checkPendingJob();
}
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === 'blog-assistant-bridge') void checkPendingJob();
});
chrome.runtime.onInstalled.addListener(() => void startBridgePolling());
chrome.runtime.onStartup.addListener(() => void startBridgePolling());
chrome.tabs.onUpdated.addListener((_id, change) => {
  if (change.url?.startsWith('https://blog.naver.com/')) void checkPendingJob();
});
void startBridgePolling();

chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message?.type !== 'check-app-bridge') return;
  checkPendingJob().then(reply);
  return true;
});
