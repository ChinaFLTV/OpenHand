import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

const server = await createServer({
  configFile: false,
  root: fileURLToPath(new URL('..', import.meta.url)),
  cacheDir: 'node_modules/.vite-runtime-check',
  optimizeDeps: { noDiscovery: true, include: [] },
  server: { middlewareMode: true, watch: null, ws: false },
  appType: 'custom',
});
const savedGlobals = new Map();
function replaceGlobal(name, value) {
  if (!savedGlobals.has(name)) savedGlobals.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
  Object.defineProperty(globalThis, name, { configurable: true, writable: true, value });
}
function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

try {
  const entries = new Map();
  let readFails = false;
  let writeFails = false;
  const storage = {
    getItem(key) {
      if (readFails) throw new Error('模拟存储读取失败');
      return entries.get(key) ?? null;
    },
    setItem(key, value) {
      if (writeFails) throw new Error('模拟存储写入失败');
      entries.set(key, value);
    },
    removeItem(key) {
      if (writeFails) throw new Error('模拟存储删除失败');
      entries.delete(key);
    },
  };
  const browser = Object.assign(new EventTarget(), {
    localStorage: storage,
    setTimeout,
    clearTimeout,
  });
  replaceGlobal('window', browser);
  replaceGlobal('ErrorEvent', class extends Event {
    constructor(type, options) { super(type); this.error = options?.error; }
  });
  const auth = await server.ssrLoadModule('/src/state/storage.ts');
  const { apiRequest, UnauthorizedError } = await server.ssrLoadModule('/src/api/client.ts');
  const { STORAGE_KEY_TOKEN, STORAGE_KEY_PROFILE } = await server.ssrLoadModule('/src/shared/util/storage_keys.ts');

  auth.writeToken('旧凭据', { username: '旧用户' });
  const firstSession = auth.captureAuthSession();
  auth.writeToken('新凭据', { username: '新用户' });
  assert.equal(firstSession(), false, '登录变更必须使旧请求失效');
  entries.delete(STORAGE_KEY_TOKEN);
  entries.delete(STORAGE_KEY_PROFILE);
  assert.equal(auth.readToken(), null, '跨标签页注销不能复活内存凭据');
  assert.equal(auth.readProfile(), null, '跨标签页注销不能保留旧用户资料');

  auth.writeToken('有效凭据', { username: '当前用户' });
  readFails = true;
  assert.equal(auth.readToken(), '有效凭据', '存储读取失败时保留有效内存凭据');
  assert.equal(auth.readProfile().username, '当前用户');
  readFails = false;
  writeFails = true;
  const deviceId = auth.ensureDeviceId();
  assert.equal(auth.ensureDeviceId(), deviceId, '存储写入失败时设备身份仍须稳定');
  auth.writeToken('内存凭据', { username: '内存用户' });
  assert.equal(auth.readToken(), '内存凭据', '写入失败时不能重新读取旧凭据');
  assert.equal(auth.readProfile().username, '内存用户');
  auth.clearAuthStorage();
  assert.equal(auth.readToken(), null, '删除失败时仍须保持注销状态');
  assert.equal(auth.readProfile(), null);
  writeFails = false;
  auth.clearAuthStorage();

  const staleResponse = deferred();
  auth.writeToken('请求凭据', null);
  replaceGlobal('fetch', () => staleResponse.promise);
  const staleRequest = apiRequest('/api/check');
  const staleCheck = assert.rejects(staleRequest, { name: 'AbortError' });
  auth.writeToken('重新登录凭据', null);
  let staleBodyCancelled = false;
  staleResponse.resolve(new Response(new ReadableStream({
    cancel() { staleBodyCancelled = true; },
  }), { status: 401 }));
  await staleCheck;
  assert.equal(auth.readToken(), '重新登录凭据', '迟到的 401 不能注销新会话');
  assert.equal(staleBodyCancelled, true, '丢弃迟到响应时必须取消响应体');

  const bodyStarted = deferred();
  let bodyController;
  replaceGlobal('fetch', async () => new Response(new ReadableStream({
    start(controller) { bodyController = controller; bodyStarted.resolve(); },
  }), { status: 401 }));
  const delayedBody = apiRequest('/api/check');
  const delayedBodyCheck = assert.rejects(delayedBody, { name: 'AbortError' });
  await bodyStarted.promise;
  auth.writeToken('读取期间登录凭据', null);
  bodyController.enqueue(new TextEncoder().encode('{}'));
  bodyController.close();
  await delayedBodyCheck;
  assert.equal(auth.readToken(), '读取期间登录凭据', '读取错误正文期间切换登录也必须受保护');

  replaceGlobal('fetch', async () => new Response('{}', { status: 401 }));
  await assert.rejects(apiRequest('/api/login', { anonymous: true }), UnauthorizedError);
  assert.equal(auth.readToken(), '读取期间登录凭据', '匿名认证失败不能清除已有凭据');
  await assert.rejects(apiRequest('/api/check'), UnauthorizedError);
  assert.equal(auth.readToken(), null, '当前会话认证失败应清除凭据');

  const { runWithTimeout, runWithAbortableTimeout } = await server.ssrLoadModule('/src/utils/timed_abort.ts');
  const timeoutFailure = new Error('模拟超时错误构造失败');
  await assert.rejects(runWithTimeout(new Promise(() => {}), {
    timeoutMs: 1,
    createTimeoutError: () => { throw timeoutFailure; },
  }), (error) => error === timeoutFailure);
  const externalAbort = new AbortController();
  const taskFailure = new Error('模拟同步任务失败');
  await assert.rejects(runWithAbortableTimeout(() => {
    externalAbort.abort();
    throw taskFailure;
  }, { signal: externalAbort.signal }), { name: 'AbortError' });
  await new Promise((resolve) => setTimeout(resolve, 0));

  const { registerOverlayEscapeLayer } = await server.ssrLoadModule('/src/shared/ui/overlay_escape_stack.ts');
  let closed = 0;
  const removeLayer = registerOverlayEscapeLayer({ canClose: () => true, requestClose: () => closed++ });
  const composingEscape = Object.assign(new Event('keydown', { cancelable: true }), { key: 'Escape', isComposing: true });
  browser.dispatchEvent(composingEscape);
  await Promise.resolve();
  assert.equal(closed, 0, '输入法取消候选词时不能关闭弹窗');
  assert.equal(composingEscape.defaultPrevented, false);
  browser.dispatchEvent(Object.assign(new Event('keydown', { cancelable: true }), { key: 'Escape' }));
  await Promise.resolve();
  assert.equal(closed, 1);
  removeLayer();
  removeLayer();

  const { subscribeSessionEvents } = await server.ssrLoadModule('/src/api/session_events.ts');
  let eventSource;
  replaceGlobal('EventSource', class extends EventTarget {
    constructor() { super(); eventSource = this; }
    close() { this.closed = true; }
  });
  const snapshots = [];
  const errors = [];
  const stop = subscribeSessionEvents('当前会话', {
    onSnapshot: (snapshot) => snapshots.push(snapshot),
    onError: (error) => errors.push(error),
  });
  const snapshot = {
    session: { id: '当前会话' }, messages: [], send_phase: 'idle',
    last_error: null, can_stop: false, served_at: '2026-09-14',
  };
  const send = (data) => eventSource.dispatchEvent(new MessageEvent('snapshot', { data: JSON.stringify(data) }));
  send(snapshot);
  send({ ...snapshot, session: { id: '其他会话' } });
  send({ ...snapshot, messages: [null] });
  assert.equal(snapshots.length, 1, '仅接收结构有效且属于当前会话的快照');
  assert.equal(errors.length, 2);
  stop();
  stop();
  send(snapshot);
  assert.equal(snapshots.length, 1, '取消订阅后不能继续通知页面');
  assert.equal(eventSource.closed, true);

  replaceGlobal('EventSource', undefined);
  const cancelUnavailable = subscribeSessionEvents('当前会话', {
    onSnapshot: () => assert.fail('无 SSE 时不能生成快照'),
    onError: (error) => errors.push(error),
  });
  cancelUnavailable();
  await Promise.resolve();
  assert.equal(errors.length, 2, '卸载后不能投递 SSE 初始化错误');

  replaceGlobal('window', undefined);
  replaceGlobal('document', {
    documentElement: {
      style: { setProperty() {} }, dataset: {},
      setAttribute() {}, removeAttribute() {},
    },
  });
  const { refreshMeta, markLoggedIn } = await server.ssrLoadModule('/src/state/auth.ts');
  const { getDialogExitDurationMs } = await server.ssrLoadModule('/src/hooks/useDialogMotionSettings.ts');
  const metaRequests = [];
  replaceGlobal('fetch', (_path, options) => {
    const request = { ...deferred(), signal: options.signal };
    metaRequests.push(request);
    return request.promise;
  });
  const oldRefresh = refreshMeta();
  auth.writeToken('元数据新凭据', { username: '新用户' });
  markLoggedIn({ username: '新用户' });
  assert.equal(metaRequests.length, 2, '登录切换必须发起独立元数据刷新');
  assert.equal(metaRequests[0].signal.aborted, true, '登录切换必须取消旧元数据请求');
  const newRefresh = refreshMeta();
  const metaResponse = (duration) => Response.json({
    service: { auth_enabled: true },
    preferences: { dialog_animation_settings: { duration_ms: duration } },
  });
  metaRequests[1].resolve(metaResponse(120));
  await newRefresh;
  metaRequests[0].resolve(metaResponse(600));
  await oldRefresh;
  assert.equal(getDialogExitDurationMs(), 120, '旧元数据不能覆盖新会话的设置');
  console.log('[Web 运行时检查] 鉴权隔离、存储兜底、事件订阅与输入法关闭行为通过。');
} finally {
  for (const [name, descriptor] of savedGlobals) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
  await server.close();
}
