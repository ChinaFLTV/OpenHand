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
  const { buildHeightPrefix, resolveVirtualMessageRange } = await server.ssrLoadModule('/src/shared/util/virtual_message_list_math.ts');
  const shortHeights = Array(1000).fill(44);
  const shortPrefix = buildHeightPrefix(shortHeights);
  for (const maxVisibleRows of [2, 8]) {
    const range = resolveVirtualMessageRange({
      messageCount: shortHeights.length, heights: shortHeights, prefix: shortPrefix,
      viewportTop: 5600, viewportBottom: 5800, maxVisibleRows,
    });
    assert.ok(range.start <= 100 && range.end > 100, '短消息的屏外预加载不能挤走视口起始行');
    assert.ok(range.end >= 104, '短消息必须完整覆盖视口，不能因预算较小被隐藏');
    assert.ok(range.end - range.start <= Math.max(maxVisibleRows, 4), '只为视口必需的消息放开预算');
  }
  const tailRange = resolveVirtualMessageRange({
    messageCount: shortHeights.length, heights: shortHeights, prefix: shortPrefix,
    viewportTop: 55488, viewportBottom: 55988, maxVisibleRows: 2,
  });
  assert.deepEqual(tailRange, { start: 991, end: 1000 }, '贴底时须覆盖整个视口并保留最新消息');
  for (const viewportTop of [0, 560, 5600, 55000]) {
    const range = resolveVirtualMessageRange({
      messageCount: shortHeights.length, heights: shortHeights, prefix: shortPrefix,
      viewportTop, viewportBottom: viewportTop + 900, maxVisibleRows: 8,
    });
    for (let index = 0; index < shortHeights.length; index++) {
      const top = index * 56;
      if (top < viewportTop + 900 && top + 44 > viewportTop) {
        assert.ok(index >= range.start && index < range.end, '大视口往返滚动不能遗漏可见短消息');
      }
    }
    assert.ok(range.end - range.start <= 18, '大视口仍只挂载附近消息');
  }
  const mixedHeights = [...shortHeights];
  mixedHeights[100] = 4000;
  const mixedRange = resolveVirtualMessageRange({
    messageCount: mixedHeights.length, heights: mixedHeights, prefix: buildHeightPrefix(mixedHeights),
    viewportTop: 6000, viewportBottom: 6480,
  });
  assert.ok(mixedRange.start <= 100 && mixedRange.end > 100, '高卡片中部滚动必须保留当前卡片');

  const { prependTranscriptHistory } = await server.ssrLoadModule('/src/shared/util/session_transcript_messages.ts');
  const history = Array.from({ length: 600 }, (_, index) => ({ id: `${index}`, content: `历史消息 ${index}` }));
  let loaded = history.slice(-10);
  for (let offset = 590; offset > 0;) {
    const start = Math.max(0, offset - 20);
    loaded = prependTranscriptHistory(loaded, history.slice(start, offset + 1));
    assert.ok(loaded, '连续历史页必须可合并');
    assert.deepEqual(loaded, history.slice(start), '上翻超过旧的 200 条上限仍须保留每条消息和最终回复');
    offset = start;
  }
  const liveBoundary = { ...history[590], content: '实时更新后的完整正文' };
  const liveTail = { id: '600', content: '加载历史期间新增的回复' };
  const live = [liveBoundary, ...history.slice(591), liveTail];
  const mergedHistory = prependTranscriptHistory(live, history.slice(570, 595));
  assert.equal(mergedHistory.at(-1), liveTail, '历史响应不能删除加载期间的新消息');
  assert.equal(mergedHistory[20], liveBoundary, '历史预览不能覆盖实时正文');
  assert.equal(new Set(mergedHistory.map(message => message.id)).size, mergedHistory.length, '分页重叠不能重复消息');
  assert.equal(prependTranscriptHistory(live, history.slice(0, 20)), null, '不相接的分页不能伪装成连续历史');
  assert.equal(prependTranscriptHistory(live, history.slice(590)), live, '重复边界页应复用现有消息');

  const {
    mergeServerWindowResult,
    updateMessageWindowMembership,
  } = await server.ssrLoadModule('/src/shared/util/session_message_window.ts');
  const largeWindow = Array.from({ length: 5000 }, (_, index) => ({
    id: `消息-${index}`,
    role: index % 2 === 0 ? 'user' : 'assistant',
    kind: index % 2 === 0 ? 'user' : 'assistant',
    content: `正文-${index}`,
    metadata: {},
    created_at: new Date(2026, 0, 1, 0, 0, index).toISOString(),
  }));
  const largeIndex = new Map(largeWindow.map((message, index) => [message.id, index]));
  const liveWindow = largeWindow.slice(-20);
  liveWindow[liveWindow.length - 1] = {
    ...liveWindow[liveWindow.length - 1],
    content: '流式更新后的尾消息',
  };
  const mergedWindow = mergeServerWindowResult(
    largeWindow,
    liveWindow,
    0,
    4980,
    { preserveLocalStreamingTail: true },
    largeIndex,
  );
  assert.equal(mergedWindow.items.length, 5000, '尾窗合并不能丢失已加载历史');
  assert.equal(mergedWindow.membershipChanged, false, '只更新尾消息时成员关系必须保持稳定');
  assert.equal(mergedWindow.items[2500], largeWindow[2500], '未变化的历史消息必须保留对象引用');
  assert.equal(mergedWindow.items.at(-1).content, '流式更新后的尾消息');
  const unchangedWindow = mergeServerWindowResult(
    mergedWindow.items,
    liveWindow,
    0,
    4980,
    { preserveLocalStreamingTail: true },
    largeIndex,
  );
  assert.equal(unchangedWindow.items, mergedWindow.items, '重复尾窗快照必须复用原数组');
  const changedMembershipWindow = [...liveWindow];
  changedMembershipWindow[5] = { ...changedMembershipWindow[5], id: '替换的消息' };
  assert.equal(
    mergeServerWindowResult(mergedWindow.items, changedMembershipWindow, 0, 4980, {}, largeIndex).membershipChanged,
    true,
    '尾窗消息标识变化必须使成员关系失效',
  );
  const membershipTracker = {
    revision: 0,
    sessionId: '',
    windowOffset: -1,
    messageIds: [],
    source: null,
  };
  const membershipKey = updateMessageWindowMembership(
    membershipTracker,
    '长会话',
    0,
    largeWindow,
  );
  assert.equal(
    updateMessageWindowMembership(membershipTracker, '长会话', 0, largeWindow),
    membershipKey,
    '同一消息数组重渲染不能重复计算成员版本',
  );
  const { resolveImageGallery, collectImageGallery } = await server.ssrLoadModule('/src/components/image_gallery.ts');
  const galleryEntries = Array.from({ length: 600 }, (_, index) => ({
    item: { path: `/图片/${index % 2}.png`, name: `图片 ${index}`, kind: 'image' },
    url: `https://example.com/${index % 2}.png`,
    messageId: `${index}`,
  }));
  const gallery = resolveImageGallery(galleryEntries, galleryEntries[400], '400');
  assert.equal(gallery.images.length, 256);
  assert.equal(gallery.images[gallery.index].messageId, '400');
  assert.equal(gallery.images[gallery.index - 1].messageId, '399');
  assert.equal(gallery.images[gallery.index + 1].messageId, '401');
  const shortGallery = resolveImageGallery(galleryEntries.slice(0, 200), galleryEntries[190], '190');
  assert.equal(shortGallery.images.length, 200);
  assert.equal(shortGallery.index, 190);
  const cachedGallery = resolveImageGallery(galleryEntries, { ...galleryEntries[400], url: 'blob:缓存' }, '400');
  assert.equal(cachedGallery.images[cachedGallery.index].messageId, '400');
  const domImages = Array.from({ length: 600 }, (_, index) => ({ src: `https://example.com/${index}.png` }));
  const documentGallery = collectImageGallery({ querySelectorAll: () => domImages }, domImages[500]);
  assert.equal(documentGallery.images[documentGallery.index].url, domImages[500].src);
  assert.ok(documentGallery.index > 0);

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
  const { readBrowserJsonStorage } = await server.ssrLoadModule('/src/shared/util/browser_storage.ts');
  const { apiRequest, UnauthorizedError } = await server.ssrLoadModule('/src/api/client.ts');
  const { STORAGE_KEY_TOKEN, STORAGE_KEY_PROFILE } = await server.ssrLoadModule('/src/shared/util/storage_keys.ts');

  entries.set('合法空值', 'null');
  assert.equal(readBrowserJsonStorage('合法空值'), null, '合法 JSON null 必须按空值读取');
  assert.equal(entries.has('合法空值'), true, '合法 JSON null 不能被误删');
  entries.set('损坏值', '{');
  assert.equal(readBrowserJsonStorage('损坏值'), null, '损坏 JSON 必须回落为空值');
  assert.equal(entries.has('损坏值'), false, '损坏 JSON 必须清理');

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
  const { readResponseTextBounded } = await server.ssrLoadModule('/src/utils/bounded_response.ts');
  let cancelCalls = 0;
  const blockedCancellation = new Response(new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array([1, 2])); },
    cancel() { cancelCalls++; return new Promise(() => {}); },
  }));
  await assert.rejects(runWithTimeout(
    () => readResponseTextBounded(blockedCancellation, { maxBytes: 1 }),
    { timeoutMs: 100 },
  ), { name: 'ResponseBodySizeLimitError' }, '底层取消不结束时仍须及时返回容量错误');
  assert.equal(cancelCalls, 1, '失败响应只取消一次');
  assert.equal(blockedCancellation.body.locked, false, '失败后释放响应读取锁');

  const cancelledRead = new AbortController();
  const stalledBody = new Response(new ReadableStream({
    cancel() { return new Promise(() => {}); },
  }));
  const reading = readResponseTextBounded(stalledBody, {
    maxBytes: 1, signal: cancelledRead.signal,
  });
  const readingCheck = assert.rejects(runWithTimeout(reading, { timeoutMs: 100 }), { name: 'AbortError' });
  cancelledRead.abort();
  await readingCheck;
  assert.equal(stalledBody.body.locked, false, '取消挂起读取后释放读取锁');

  await assert.rejects(readResponseTextBounded(new Response(null), {
    maxBytes: 1, signal: cancelledRead.signal,
  }), { name: 'AbortError' }, '空响应也不能吞掉取消信号');
  const timeoutFailure = new Error('模拟超时错误构造失败');
  await assert.rejects(runWithTimeout(new Promise(() => {}), {
    timeoutMs: 1,
    createTimeoutError: () => { throw timeoutFailure; },
  }), (error) => error === timeoutFailure);
  let timedTaskSignal;
  await assert.rejects(runWithAbortableTimeout((signal) => {
    timedTaskSignal = signal;
    return new Promise(() => {});
  }, {
    timeoutMs: 1,
    createTimeoutError: () => { throw timeoutFailure; },
  }), (error) => error === timeoutFailure);
  assert.equal(timedTaskSignal.aborted, true, '超时错误构造失败也必须取消任务');
  assert.equal(timedTaskSignal.reason, timeoutFailure, '任务与调用方保留同一超时原因');
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

  const sharedLayer = new class {
    enabled = true;
    canClose() { return this.enabled; }
    requestClose() { closed++; }
  }();
  const removeFirstRegistration = registerOverlayEscapeLayer(sharedLayer);
  const removeSecondRegistration = registerOverlayEscapeLayer(sharedLayer);
  removeFirstRegistration();
  browser.dispatchEvent(Object.assign(new Event('keydown', { cancelable: true }), { key: 'Escape' }));
  await Promise.resolve();
  assert.equal(closed, 2, '移除同一浮层的旧登记不能误删新登记');
  removeSecondRegistration();

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
  const { BoundedTextCache } = await server.ssrLoadModule('/src/shared/util/bounded_text_cache.ts');
  for (const invalid of [NaN, Infinity, -Infinity, -1, 0.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => new BoundedTextCache(invalid, 12), RangeError, '条目数异常时必须拒绝创建缓存');
    assert.throws(() => new BoundedTextCache(2, invalid), RangeError, '字符预算异常时必须拒绝创建缓存');
  }
  const disabledCache = new BoundedTextCache(0, 0);
  disabledCache.set('', '');
  assert.equal(disabledCache.get(''), undefined, '零容量缓存不能保留条目');
  const textCache = new BoundedTextCache(2, 12);
  textCache.set('甲', '一');
  textCache.set('乙', '二');
  textCache.get('甲');
  textCache.set('丙', '三');
  assert.equal(textCache.get('乙'), undefined, '缓存必须淘汰最久未使用的条目');
  textCache.set('甲', '四'.repeat(10));
  assert.equal(textCache.get('丙'), undefined, '替换条目后仍须遵守总字符预算');
  textCache.set('超限', '五'.repeat(20));
  assert.equal(textCache.get('超限'), undefined, '单条超限内容不得挤占缓存');
  textCache.set('甲', '');
  textCache.set('丁', '六'.repeat(10));
  assert.equal(textCache.get('甲'), '', '空净化结果也必须正确缓存和计费');

  replaceGlobal('document', { documentElement: { getAttribute: () => null } });
  const { RichContentFrameScheduler } = await server.ssrLoadModule('/src/shared/ui/rich_content_frame_scheduler.ts');
  const frames = [];
  const idleCallbacks = [];
  replaceGlobal('requestAnimationFrame', (callback) => { frames.push(callback); return frames.length; });
  replaceGlobal('requestIdleCallback', (callback) => { idleCallbacks.push(callback); return idleCallbacks.length; });
  const scheduler = new RichContentFrameScheduler();
  let renderedCards = 0;
  const cancelledCards = Array.from({ length: 2000 }, () => scheduler.schedule(() => { renderedCards += 1; }));
  for (const cancel of cancelledCards) cancel();
  scheduler.schedule(() => { renderedCards += 1; });
  scheduler.schedule(() => { renderedCards += 1; });
  assert.equal(frames.length, 1, '大量挂载和取消只能保留一个帧调度链');
  frames.shift()();
  assert.equal(renderedCards, 0, '帧开始时应先等待空闲预算');
  idleCallbacks.shift()();
  assert.equal(renderedCards, 1, '两千条失效任务不能阻塞当前可见卡片');
  assert.equal(idleCallbacks.length, 0, '同一空闲周期不能连续升级多张卡片');
  frames.shift()();
  idleCallbacks.shift()();
  assert.equal(renderedCards, 2, '下一张卡片必须在下一帧执行');
  assert.equal(frames.length, 0, '队列清空后必须停止调度');
  scheduler.schedule(() => { throw new Error('模拟渲染失败'); });
  scheduler.schedule(() => { renderedCards += 1; });
  frames.shift()();
  assert.throws(() => idleCallbacks.shift()(), /模拟渲染失败/, '渲染错误不能静默吞掉');
  frames.shift()();
  idleCallbacks.shift()();
  assert.equal(renderedCards, 3, '单条任务失败不能堵塞后续卡片');

  replaceGlobal('document', { documentElement: { getAttribute: () => 'true' } });
  let scheduledTimers = 0;
  replaceGlobal('window', {
    setTimeout() { scheduledTimers++; return scheduledTimers; },
    clearTimeout() {},
  });
  const cancelWhileScrolling = scheduler.schedule(() => { renderedCards += 1; });
  frames.shift()();
  cancelWhileScrolling();
  idleCallbacks.shift()();
  assert.equal(renderedCards, 3, '已排入空闲帧的离屏任务也必须能取消');
  assert.equal(frames.length, 0, '取消最后一个任务后不能继续空转');
  for (let index = 0; index < 3; index++) scheduler.schedule(() => { renderedCards += 1; });
  for (let index = 0; index < 3; index++) {
    assert.equal(frames.length, 1, '持续滚动也只能保留一个调度链');
    frames.shift()();
    assert.equal(idleCallbacks.length, 1, '持续滚动必须直接取得空闲帧预算');
    idleCallbacks.shift()();
    assert.equal(renderedCards, 4 + index, '滚动不能让后续卡片逐张等待数秒');
  }
  assert.equal(scheduledTimers, 0, '正文渲染不能再依赖滚动结束计时器');
  assert.equal(frames.length, 0, '滚动期间队列清空后必须停止调度');

  replaceGlobal('requestIdleCallback', undefined);
  scheduler.schedule(() => { renderedCards += 1; });
  frames.shift()();
  assert.equal(renderedCards, 7, '不支持空闲回调的浏览器仍须逐帧渲染');
  assert.equal(frames.length, 0);

  console.log('[Web 运行时检查] 鉴权隔离、存储兜底、有界响应、取消原因、事件订阅、输入法关闭、富文本帧预算与缓存边界检查通过。');
} finally {
  for (const [name, descriptor] of savedGlobals) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
  await server.close();
}
