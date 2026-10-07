document.getElementById('pairApp').addEventListener('click',async()=>{
 const output=document.getElementById('pairStatus');
 try{
  let token=(await chrome.storage.local.get('appBridgeToken')).appBridgeToken;
  if(!token){
   const bytes=crypto.getRandomValues(new Uint8Array(32));
   token=[...bytes].map(b=>b.toString(16).padStart(2,'0')).join('');
   await chrome.storage.local.set({appBridgeToken:token});
  }
  await navigator.clipboard.writeText(`${chrome.runtime.id}:${token}`);
  output.textContent='연결 코드를 복사했습니다. Swift 앱 상단의 Chrome 연결에 붙여넣고 저장하세요. 이후에는 앱의 네이버 임시저장 버튼만 사용합니다.';
 }catch{output.textContent='연결 코드를 복사하지 못했습니다. 확장 프로그램 화면에서 다시 시도하세요.';}
});

document.getElementById('checkApp').addEventListener('click', async () => {
 const output=document.getElementById('pairStatus');
 output.textContent='앱 연결 확인 중…';
 try { output.textContent=await chrome.runtime.sendMessage({type:'check-app-bridge'}); }
 catch { output.textContent='확장 프로그램을 새로고침하고 이 화면을 다시 열어주세요.'; }
});
