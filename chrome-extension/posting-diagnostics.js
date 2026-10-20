// Only structural editor state is recorded: never post text, photo bytes or bridge credentials.
export function editorSummary(state) {
  if (!state) return null;
  return {
    ready: state.ready,
    imageCount: state.imageCount,
    fileInputCount: state.fileInputCount,
    recoveryPrompt: state.recoveryPrompt,
    upload: state.uploadDiagnostics
  };
}

export function errorDetails(error) {
  return {
    name: String(error?.name || 'Error'),
    message: String(error?.message || error).slice(0, 1000),
    stack: typeof error?.stack === 'string' ? error.stack.slice(0, 2000) : undefined,
    cause: error?.cause ? String(error.cause.message || error.cause).slice(0, 1000) : undefined
  };
}

export function createPostingDiagnostics({save = async () => {}, render = () => {}, limit = 160} = {}) {
  let context = {}, events = [], startedAt = null, queue = Promise.resolve();
  const snapshot = () => ({version: 1, startedAt, context: {...context}, events: [...events]});
  const record = (event, details = {}) => {
    events.push({time: new Date().toISOString(), event, ...context, details});
    if (events.length > limit) events.splice(0, events.length - limit);
    const value = snapshot();
    render(value);
    // Serialize writes so an earlier progress snapshot cannot overwrite the final error.
    queue = queue.catch(() => {}).then(() => save(value)).catch(() => {});
  };
  return {
    start() { context = {}; events = []; startedAt = new Date().toISOString(); record('start'); },
    stage(value) { context = {...value}; record('stage'); },
    record,
    snapshot,
    flush: () => queue,
    failureMessage(error) {
      const where = [context.photoNumber ? `사진 ${context.photoNumber}/${context.photoTotal}` : '',
        context.blockNumber ? `본문 구간 ${context.blockNumber}/${context.blockTotal}` : '', context.stage].filter(Boolean).join(' · ');
      return `${where ? `[${where}] ` : ''}${String(error?.message || error)}`.slice(0, 2400);
    }
  };
}

export async function waitForEditor({inspect, test, message, timeout = 30000, check = () => {},
  isStopped = () => false, delay = ms => new Promise(resolve => setTimeout(resolve, ms)),
  now = () => Date.now(), record = () => {}}) {
  const start = now();
  let lastState = null, lastError = null, failures = 0, previousState = '', previousError = '';
  record('wait-start', {timeoutMs: timeout});
  while (now() - start < timeout) {
    check();
    try {
      const state = await inspect();
      if (!state || typeof state !== 'object') throw new Error('편집기 조회 결과가 비어 있습니다.');
      lastState = editorSummary(state);
      const signature = JSON.stringify(lastState);
      if (signature !== previousState) { record('wait-state', {state: lastState}); previousState = signature; }
      if (test(state)) { record('wait-ready', {elapsedMs: now() - start, inspectionFailures: failures}); return state; }
    } catch (error) {
      if (isStopped()) throw error;
      failures++;
      lastError = error;
      const signature = String(error?.message || error);
      if (signature !== previousError) { record('inspection-error', {error: errorDetails(error)}); previousError = signature; }
    }
    await delay(400);
  }
  const button = lastState?.upload?.photoButton;
  const details = [`대기 ${Math.round((now() - start) / 1000)}초`,
    lastState ? `업로드 입력창 ${lastState.fileInputCount}개 · 사진 ${lastState.imageCount}장` : '편집기 상태 조회 성공 없음',
    button ? `사진 버튼 ${button.disabled || button.ariaDisabled === 'true' ? '비활성' : button.visible ? '활성' : '숨김'}` : '',
    lastError ? `조회 실패 ${failures}회 · 마지막 원래 오류: ${String(lastError.message || lastError).slice(0, 1000)}` : ''].filter(Boolean);
  record('wait-timeout', {elapsedMs: now() - start, inspectionFailures: failures, state: lastState,
    error: lastError ? errorDetails(lastError) : null});
  throw new Error(`${message} (${details.join(' / ')})`, lastError ? {cause: lastError} : undefined);
}
