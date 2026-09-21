import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer, transformWithOxc } from 'vite';
import preact from '@preact/preset-vite';

const server = await createServer({
  configFile: false,
  plugins: [preact()],
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
  // 直接执行消息卡片的真实事件入口，验证内容区与外层留白的点击边界。
  const messageCardSource = await readFile(new URL('../src/components/MessageCard.tsx', import.meta.url), 'utf8');
  const selectorStart = messageCardSource.indexOf('const MESSAGE_CARD_INTERACTIVE_TARGET_SELECTOR =');
  const selectorEnd = messageCardSource.indexOf("].join(',');", selectorStart) + "].join(',');".length;
  function cardHandler(name) {
    const marker = `            ${name}={`;
    const start = messageCardSource.indexOf(marker) + marker.length;
    const end = messageCardSource.indexOf('}}\n', start);
    assert.ok(start >= marker.length && end > start, '必须执行真实消息点击入口');
    return messageCardSource.slice(start, end + 1);
  }
  assert.ok(selectorStart >= 0 && selectorEnd > selectorStart);
  const { code: cardEventCode } = await transformWithOxc(
    `${messageCardSource.slice(selectorStart, selectorEnd)}\nconst handlers = { down: ${cardHandler('onPointerDown')}, click: ${cardHandler('onClick')} };`,
    'message-card-events.ts',
  );
  for (const active of [false, true]) {
    const changes = [];
    const pointer = { current: null };
    const bindings = {
      hasAnyAction: true, active, cardPointerDownRef: pointer,
      message: { id: '决策卡片' }, onActiveChange: (_message, value) => changes.push(value),
      window: { getSelection: () => null },
      MESSAGE_CARD_TAP_MAX_MS: 350, MESSAGE_CARD_TAP_MAX_DISTANCE_PX: 8,
    };
    const handlers = new Function(...Object.keys(bindings), `${cardEventCode}\nreturn handlers;`)(...Object.values(bindings));
    for (const ancestors of [['.oh-decision-card'], ['button', '.oh-decision-card'], ['path', 'svg', 'button', '.oh-decision-card']]) {
      const event = { button: 0, clientX: 10, clientY: 10,
        target: { closest: selectors => selectors.split(',').some(selector => ancestors.includes(selector)) ? {} : null },
      };
      handlers.down(event);
      handlers.click(event);
      assert.equal(changes.length, 0, '决策正文、展开按钮及其图标不改变消息选中状态');
    }
    const marginEvent = { button: 0, clientX: 10, clientY: 10,
      target: { tagName: 'ARTICLE', closest: () => null },
    };
    handlers.down({ ...marginEvent, target: { closest: () => ({}) } });
    handlers.click(marginEvent);
    assert.equal(changes.length, 0, '内容区按下后在边缘释放也不能切换选中');
    handlers.down(marginEvent);
    handlers.click(marginEvent);
    assert.deepEqual(changes, [!active], '外层留白仍可切换消息选中状态');
  }

  const { syncLangFromAppPreferences } = await server.ssrLoadModule('/src/i18n/index.ts');
  syncLangFromAppPreferences('zh_Hans');
  const { isStructuredDecisionMessage } = await server.ssrLoadModule('/src/shared/util/decision.ts');
  for (const type of ['noul', 'choice', 'score']) {
    const content = '```openhand-decision\n' + JSON.stringify({ answers: { 决策: { type } } }) + '\n```';
    assert.equal(isStructuredDecisionMessage({ role: 'assistant', content }), true);
    assert.equal(isStructuredDecisionMessage({ role: 'user', content }), false);
    const request = content.replace('openhand-decision', 'openhand-decision-request');
    assert.equal(isStructuredDecisionMessage({ role: 'user', content: request }), true);
    assert.equal(isStructuredDecisionMessage({ role: 'assistant', content: request }), false);
  }
  assert.equal(isStructuredDecisionMessage({ role: 'assistant', content: '说明\n  ~~~openhand-decision\r\n{}\r\n~~~' }), true);
  assert.equal(isStructuredDecisionMessage({ role: 'user', content: '说明\n  ~~~openhand-decision-request\r\n{}\r\n~~~' }), true);
  for (const content of ['普通用户消息提到 openhand-decision-request', '```openhand-decision-request-extra\n{}\n```']) {
    assert.equal(isStructuredDecisionMessage({ role: 'user', content }), false);
  }
  for (const content of ['普通回复提到 openhand-decision', '```openhand-decision-request\n{}\n```', '```openhand-decision-extra\n{}\n```']) {
    assert.equal(isStructuredDecisionMessage({ role: 'assistant', content }), false);
  }
  const { decisionRequestToMarkdown } = await server.ssrLoadModule('/src/shared/util/decision_request_markdown.ts');
  const requestPayload = { state: '待评估 <script>内容</script>', questions: {
    判断: { type: 'noul', instructions: '是否成立？', criteria: { 真: '有证据', 假: '无证据' } },
    选择: { type: 'choice', instructions: '选哪个？', criteria: { '甲*': null, '乙|': '详细描述' } },
    评分: { type: 'score', instructions: { 问题: '评几级？' }, criteria: ['低', '高'] },
  } };
  const requestSource = '前文\n```openhand-decision-request\r\n' + JSON.stringify(requestPayload) + '\r\n```\n后文';
  const renderedRequest = decisionRequestToMarkdown(requestSource);
  assert.ok(renderedRequest.includes('### 结构化决策'));
  assert.ok(renderedRequest.includes('#### 判断 · 判断'));
  assert.ok(renderedRequest.includes('1. 甲\\*'));
  assert.ok(renderedRequest.includes('2. 乙\\|：详细描述'));
  assert.ok(renderedRequest.includes('1. 低\n2. 高'));
  assert.ok(renderedRequest.includes('```json\n'));
  assert.ok(renderedRequest.includes('\\<script\\>'));
  assert.ok(renderedRequest.startsWith('前文') && renderedRequest.endsWith('后文'));
  for (const source of ['普通用户消息', JSON.stringify(requestPayload), '```openhand-decision-request\n损坏\n```', '```openhand-decision-request\n{}', requestSource + '\n```openhand-decision-request\n{}\n```']) {
    assert.equal(decisionRequestToMarkdown(source), null, '普通消息或不完整请求保留原文');
  }
  const { DEFAULT_DECISION_QUESTIONS, decisionQuestionForType, decisionDraft, initialDecisionDraft } = await server.ssrLoadModule('/src/shared/util/decision.ts');
  assert.equal(new Set(Object.values(DEFAULT_DECISION_QUESTIONS)).size, 3);
  for (const type of Object.keys(DEFAULT_DECISION_QUESTIONS)) {
    for (const current of ['', '  ', ...Object.values(DEFAULT_DECISION_QUESTIONS)]) {
      assert.equal(decisionQuestionForType(type, current), DEFAULT_DECISION_QUESTIONS[type]);
    }
    const custom = '  哪个团队负责售后？  ';
    assert.equal(decisionQuestionForType(type, custom), custom);
    const draft = decisionDraft('待评估内容', decisionQuestionForType(type), type, '低\n高');
    assert.equal(initialDecisionDraft(draft).question, DEFAULT_DECISION_QUESTIONS[type]);
  }
  const { parseDecisionRequest, parseDecisionResult } = await server.ssrLoadModule('/src/shared/util/decision.ts');
  for (const type of ['noul', 'choice', 'score']) {
    const request = { state: '内容含 ``` 和 ~~~', questions: { 决策: {
      type, instructions: '评估',
      ...(type === 'choice' ? { criteria: { 甲: null, 乙: null } } : type === 'score' ? { criteria: ['低', '高'] } : {}),
    } } };
    for (const fence of ['```', '````', '~~~', '~~~~']) {
      for (const newline of ['\n', '\r\n']) {
        const text = `  ${fence}openhand-decision-request \t${newline}${JSON.stringify(request)}${newline}  ${fence}`;
        assert.deepEqual(parseDecisionRequest(text), request, '围栏样式不得改变决策类型');
        assert.equal(initialDecisionDraft(text).type, type, '重新编辑保持原类型');
        assert.equal(parseDecisionRequest(text.slice(0, -fence.length)), null, '未闭合配置拒绝解析');
        assert.ok(initialDecisionDraft(text.slice(0, -fence.length)).advanced, '损坏配置进入原文编辑');
      }
    }
    const answer = type === 'noul' ? { type, noul: .8 }
      : type === 'choice' ? { type, choice: '甲', probabilities: { 甲: .8, 乙: .2 } }
      : { type, score: .4, probabilities: { 0: .6, 1: .4 } };
    assert.ok(parseDecisionResult(JSON.stringify({ questions: request.questions, answers: { 决策: answer } })));
    for (const answers of [{ 决策: { ...answer, type: type === 'noul' ? 'choice' : 'noul' } },
      { 旧问题: answer }, { 决策: answer, 旧问题: answer }]) {
      assert.equal(parseDecisionResult(JSON.stringify({ questions: request.questions, answers })), null,
        '错误类型、缺失和多余答案不得显示成成功结果');
    }
  }
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

  const { collectGalleryMedia } = await server.ssrLoadModule('/src/components/MessageMedia.tsx');
  const quotedImages = collectGalleryMedia({ content: '> ![引用图片](/tmp/quoted.png)\n\n![重复图片](/tmp/quoted.png)' });
  assert.equal(quotedImages.length, 1, '本地引用图片须进入图库且同消息去重');
  assert.equal(quotedImages[0].path, '/tmp/quoted.png');
  assert.equal(quotedImages[0].isDirectUrl, false);
  const referencedGallery = [galleryEntries[0],
    { item: quotedImages[0], url: '/quoted.png', messageId: '引用' }, galleryEntries[2]];
  const referenced = resolveImageGallery(referencedGallery, referencedGallery[1], '引用');
  assert.equal(referenced.index, 1, '引用图片必须保留会话中的前后导航');
  assert.equal(referenced.images.length, 3);

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

  assert.throws(() => auth.writeToken('  ', null), TypeError, '空令牌不能进入登录态');

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

  // 从真实页面提取分页入口，仅替换界面状态与请求出口。
  const historyPageSource = await readFile(new URL('../src/features/sessions/components/SessionDetailPage.tsx', import.meta.url), 'utf8');
  const scrollStart = historyPageSource.indexOf("    const upwardScrollKeys = new Set(");
  const scrollEnd = historyPageSource.indexOf('    recalc();', scrollStart);
  const intentStart = historyPageSource.indexOf('  const markUserScrollIntent = useCallback(() => {');
  const intentEnd = historyPageSource.indexOf('  }, []);', intentStart);
  assert.ok(scrollStart >= 0 && scrollEnd > scrollStart && intentStart >= 0 && intentEnd > intentStart);
  const { code: scrollCode } = await transformWithOxc(
    `${historyPageSource.slice(intentStart, intentEnd + '  }, []);'.length)}\n${historyPageSource.slice(scrollStart, scrollEnd)}\nconst controls = { handleWheel, handleKeyDown, recalc };`,
    'transcript-scroll.ts',
  );
  const scroller = { scrollTop: 1000, scrollHeight: 1600, clientHeight: 600 };
  const follow = { current: true };
  const paused = { current: false };
  const lastIntent = { current: 0 };
  const programmatic = { current: Date.now() + 10000 };
  let cancellations = 0;
  const scrollBindings = {
    useCallback: callback => callback, mainRef: { current: scroller },
    composerLayoutPinnedRef: { current: true }, lastUserScrollIntentAtRef: lastIntent,
    programmaticScrollUntilRef: programmatic, lastScrollTopRef: { current: 1000 },
    autoFollowRef: follow, autoFollowPausedRef: paused, isNearBottomRef: { current: true },
    setAutoFollowPausedValue: value => { paused.current = value; },
    setAutoFollowEnabled: value => { follow.current = value; },
    hasRecentUserScrollIntent: () => Date.now() - lastIntent.current <= 1200,
    markTranscriptScrollActivity() {}, cancelFollowSettle() {},
    cancelAutoFollowMotion() { cancellations++; }, isEditableShortcutTarget: () => false,
    AUTO_FOLLOW_USER_SCROLL_INTENT_MS: 1200, AUTO_FOLLOW_WHEEL_INTENT_EPSILON_PX: 0,
    AUTO_FOLLOW_NEAR_BOTTOM_PX: 64, AUTO_FOLLOW_RESUME_BOTTOM_PX: 1,
  };
  const scroll = new Function(...Object.keys(scrollBindings), `${scrollCode}\nreturn controls;`)(...Object.values(scrollBindings));
  scroll.handleWheel({ deltaY: -.01 });
  assert.equal(paused.current, true, '亚像素上滑立即暂停追底');
  assert.equal(programmatic.current, 0, '用户输入撤销旧程序滚动窗口');
  assert.equal(cancellations, 1);
  scroller.scrollTop -= .01;
  scroll.recalc();
  lastIntent.current = Date.now() - 2000;
  scroll.recalc();
  assert.equal(paused.current, true, '停在底部附近不能因保护窗口结束重新追底');
  scroller.scrollTop = 970;
  scroll.recalc();
  scroll.handleWheel({ deltaY: 1 });
  assert.ok(Date.now() - lastIntent.current < 100, '向下慢速滚轮也保护视口');
  scroller.scrollTop = 980;
  scroll.recalc();
  assert.equal(paused.current, true, '接近底部仍由用户控制滚动');
  scroller.scrollTop = 1000;
  scroll.recalc();
  assert.equal(paused.current, false, '主动滚回底部才恢复追底');
  scroll.handleKeyDown({ key: 'ArrowUp', defaultPrevented: false });
  assert.equal(paused.current, true);
  paused.current = false;
  lastIntent.current = Date.now();
  scroller.scrollTop -= .01;
  scroll.recalc();
  assert.equal(paused.current, true, '触摸和滚动条的微小上移也暂停跟随');

  const initialStart = historyPageSource.indexOf('    if (initialLayoutSettledRef.current) return undefined;');
  const initialEnd = historyPageSource.indexOf('  }, [membershipKey, onInitialLayoutSettled, scrollContainerRef]);', initialStart);
  assert.ok(initialStart >= 0 && initialEnd > initialStart);
  const { code: initialCode } = await transformWithOxc(
    `const prepare = () => {${historyPageSource.slice(initialStart, initialEnd)}};`, 'initial-layout.ts',
  );
  for (const scenario of ['stable', 'timeout', 'pending']) {
    const frames = new Map();
    let nextFrame = 0;
    let revealed = false;
    const initialScroller = { scrollTop: 120, scrollHeight: 2400, clientHeight: 600 };
    const initialBindings = {
      initialLayoutSettledRef: { current: false },
      initialLayoutStartedAtRef: { current: scenario === 'timeout' ? 0 : Date.now() },
      scrollContainerRef: { current: initialScroller },
      heightCommitPendingRef: { current: scenario === 'pending' }, heightCommitFrameRef: { current: null },
      TRANSCRIPT_INITIAL_SETTLE_MAX_FRAMES: 24, TRANSCRIPT_INITIAL_SETTLE_MAX_MS: 480,
      TRANSCRIPT_INITIAL_SETTLE_MIN_FRAMES: 2, TRANSCRIPT_INITIAL_SETTLE_STABLE_FRAMES: 2,
      TRANSCRIPT_INITIAL_SETTLE_EPSILON_PX: .75,
      window: {
        requestAnimationFrame(callback) { frames.set(++nextFrame, callback); return nextFrame; },
        cancelAnimationFrame(id) { frames.delete(id); },
      },
      onInitialLayoutSettled() {
        assert.equal(initialScroller.scrollTop, initialScroller.scrollHeight - initialScroller.clientHeight,
          '正常与超时揭示均须先完成尾部定位');
        revealed = true;
      },
    };
    const prepare = new Function(...Object.keys(initialBindings), `${initialCode}\nreturn prepare;`)(...Object.values(initialBindings));
    const cleanup = prepare();
    for (let frame = 0; frame < 24 && !revealed; frame++) {
      if (frame === 1) initialScroller.scrollHeight += 700;
      for (const [id, callback] of [...frames]) { frames.delete(id); callback(); }
    }
    assert.equal(revealed, true, '首屏等待必须有界');
    cleanup();
    assert.equal(frames.size, 0, '离开列表必须释放首屏任务');
  }

  const resizeStart = historyPageSource.indexOf('    const target = messagesContentRef.current;');
  const resizeEnd = historyPageSource.indexOf('  }, [autoFollow, autoFollowPaused, hasRecentUserScrollIntent]);', resizeStart);
  assert.ok(resizeStart >= 0 && resizeEnd > resizeStart);
  const { code: resizeCode } = await transformWithOxc(
    `const observe = () => {${historyPageSource.slice(resizeStart, resizeEnd)}};`, 'layout-follow.ts',
  );
  let onResize;
  let disconnected = false;
  let userReading = false;
  let composerMoving = false;
  const layoutFollow = { current: true };
  const layoutPaused = { current: false };
  const layoutScroller = { scrollTop: 0, scrollHeight: 2400, clientHeight: 600 };
  const resizeBindings = {
    messagesContentRef: { current: {} }, mainRef: { current: layoutScroller },
    autoFollowRef: layoutFollow, autoFollowPausedRef: layoutPaused,
    hasRecentUserScrollIntent: () => userReading,
    isComposerLayoutTransitioning: () => composerMoving,
    ResizeObserver: class {
      constructor(callback) { onResize = callback; }
      observe() {}
      disconnect() { disconnected = true; }
    },
    scrollMessagesToBottom() { layoutScroller.scrollTop = layoutScroller.scrollHeight - layoutScroller.clientHeight; },
  };
  const observe = new Function(...Object.keys(resizeBindings), `${resizeCode}\nreturn observe;`)(...Object.values(resizeBindings));
  const stopObserving = observe();
  onResize();
  assert.equal(layoutScroller.scrollTop, 1800, '测高回调必须在当前绘制前贴底');
  for (const guard of ['user', 'paused', 'disabled', 'composer']) {
    userReading = guard === 'user';
    layoutPaused.current = guard === 'paused';
    layoutFollow.current = guard !== 'disabled';
    composerMoving = guard === 'composer';
    layoutScroller.scrollHeight += 100;
    onResize();
    assert.equal(layoutScroller.scrollTop, 1800, '用户阅读和输入区动画保护不能被测高绕过');
  }
  stopObserving();
  assert.equal(disconnected, true);

  const heightStart = historyPageSource.indexOf('  const scheduleHeightCommit = useCallback(');
  const heightEnd = historyPageSource.indexOf('  const handleHeightChange =', heightStart);
  assert.ok(heightStart >= 0 && heightEnd > heightStart);
  const { code: heightCode } = await transformWithOxc(historyPageSource.slice(heightStart, heightEnd), 'height-commit.ts');
  let scrolling = false;
  let heightCommits = 0;
  const heightFrames = [];
  const pendingHeight = { current: false };
  const heightBindings = {
    followBottomRef: { current: false },
    useCallback: callback => callback, isTranscriptScrollActive: () => scrolling,
    initialLayoutSettledRef: { current: true },
    heightCommitPendingRef: pendingHeight, heightCommitFrameRef: { current: null },
    scrollContainerRef: { current: null }, listRef: { current: null },
    window: { requestAnimationFrame: callback => { heightFrames.push(callback); return heightFrames.length; } },
    setHeightRevision: () => { heightCommits++; },
  };
  const commitHeight = new Function(...Object.keys(heightBindings), `${heightCode}\nreturn scheduleHeightCommit;`)(...Object.values(heightBindings));
  commitHeight();
  scrolling = true;
  heightFrames.shift()();
  assert.equal(heightCommits, 0, '排队后才开始滚动，也不能提交旧测高任务');
  assert.equal(pendingHeight.current, true);
  scrolling = false;
  commitHeight();
  heightFrames.shift()();
  assert.equal(heightCommits, 1, '停止后合并提交测高');
  heightBindings.initialLayoutSettledRef.current = false;
  scrolling = true;
  commitHeight();
  heightFrames.shift()();
  assert.equal(heightCommits, 2, '隐藏首屏的程序定位不能延迟真实测高');
  scrolling = false;


  const restoreStart = historyPageSource.indexOf('    const anchor = heightAnchorRef.current;');
  const restoreEnd = historyPageSource.indexOf('  }, [heightRevision, scrollContainerRef]);', restoreStart);
  assert.ok(restoreStart >= 0 && restoreEnd > restoreStart);
  const { code: restoreCode } = await transformWithOxc(
    `const restoreHeightAnchor = () => {${historyPageSource.slice(restoreStart, restoreEnd)}};`, 'height-anchor.ts',
  );
  const heightAnchor = { current: null };
  const heightScroller = { scrollTop: 100, getBoundingClientRect: () => ({ top: 0 }) };
  const restoreBindings = {
    followBottomRef: { current: false },
    heightAnchorRef: heightAnchor, isTranscriptScrollActive: () => scrolling,
    scrollContainerRef: { current: heightScroller },
    listRef: { current: { querySelectorAll: () => [{
      dataset: { messageId: '阅读中的消息' }, getBoundingClientRect: () => ({ top: 30 }),
    }] } },
  };
  const restoreHeight = new Function(...Object.keys(restoreBindings), `${restoreCode}\nreturn restoreHeightAnchor;`)(...Object.values(restoreBindings));
  const savedAnchor = { messageId: '阅读中的消息', viewportOffset: 10, scrollTop: 100 };
  heightAnchor.current = savedAnchor;
  scrolling = true;
  restoreHeight();
  assert.equal(heightScroller.scrollTop, 100, '恢复锚点前开始滚动必须放弃旧修正');
  scrolling = false;
  heightScroller.scrollTop = 105;
  heightAnchor.current = savedAnchor;
  restoreHeight();
  assert.equal(heightScroller.scrollTop, 105, '浏览器已经修正坐标时不能再次补偿');
  heightScroller.scrollTop = 100;
  heightAnchor.current = savedAnchor;
  restoreHeight();
  assert.equal(heightScroller.scrollTop, 120, '空闲时仍须补偿正文测高造成的位移');
  restoreBindings.followBottomRef.current = true;
  heightScroller.scrollTop = 100;
  heightAnchor.current = savedAnchor;
  restoreHeight();
  assert.equal(heightScroller.scrollTop, 100, '自动贴底时不能同时恢复阅读锚点');

  const scrollHandlerStart = historyPageSource.indexOf('    const handleScroll = () => {');
  const scrollHandlerEnd = historyPageSource.indexOf("    el?.addEventListener('scroll'", scrollHandlerStart);
  assert.ok(scrollHandlerStart >= 0 && scrollHandlerEnd > scrollHandlerStart);
  let userScrollIntent = false;
  let scrollFreezeCount = 0;
  let scrollRecalcs = 0;
  const handleScroll = new Function('hasRecentUserScrollIntent', 'markTranscriptScrollActivity', 'recalc',
    `${historyPageSource.slice(scrollHandlerStart, scrollHandlerEnd)}\nreturn handleScroll;`)(
      () => userScrollIntent, () => { scrollFreezeCount++; }, () => { scrollRecalcs++; });
  for (let frame = 0; frame < 45; frame++) handleScroll();
  assert.equal(scrollFreezeCount, 0, '流式输出的程序贴底不能持续冻结测高');
  assert.equal(scrollRecalcs, 45);
  userScrollIntent = true;
  handleScroll();
  assert.equal(scrollFreezeCount, 1, '用户主动滚动时仍保护阅读位置');

  const historyStart = historyPageSource.indexOf('  async function loadOlder(');
  const historyEnd = historyPageSource.indexOf('  const locateImageMessage =', historyStart);
  assert.ok(historyStart >= 0 && historyEnd > historyStart, '必须检查真实历史分页入口');
  const { code: historyCode } = await transformWithOxc(
    historyPageSource.slice(historyStart, historyEnd), 'history.ts',
  );
  function historyHarness() {
    const state = { loading: false, notices: [], requests: [], applied: 0 };
    const bindings = {
      loadingOlder: false, olderRenderSettlingRef: { current: false },
      olderMessagesAbortRef: { current: null }, messagesAbortRef: { current: null },
      windowOffsetRef: { current: 20 }, messagesRef: { current: history.slice(20, 30) },
      sessionId: '历史回归', mainRef: { current: null }, messagesContentRef: { current: null },
      lastUserScrollIntentAtRef: { current: 0 }, totalKnownRef: { current: 30 },
      PAGE_SIZE: 12, LOAD_OLDER_TIMEOUT_MS: 20,
      setLoadingOlder(value) { state.loading = value; },
      setAutoFollowPausedValue() {}, cancelAutoFollowMotion() {},
      listMessages(_id, options) {
        const request = { ...deferred(), signal: options.signal };
        state.requests.push(request);
        return request.promise;
      },
      runWithAbortableTimeout, prependTranscriptHistory,
      ownsSessionAsyncResult: () => true, t: (_key, fallback) => fallback,
      markMessagesAsAppeared() {}, setOlderRenderSettlingValue() {},
      restoreMessageWindow(messages, offset) {
        state.applied++;
        bindings.messagesRef.current = messages;
        bindings.windowOffsetRef.current = offset;
      },
      updateTotalKnown() {}, schedulePostRenderFrame() {}, renderedMessageRow: () => null,
      handleAuthError: () => false, handleSessionGoneError: () => false,
      showSnackbar(message) { state.notices.push(message); },
    };
    const load = new Function(...Object.keys(bindings), historyCode + '\nreturn loadOlder;')(...Object.values(bindings));
    return { state, bindings, load };
  }
  const stalledHistory = historyHarness();
  const stalledLoad = stalledHistory.load();
  await Promise.resolve();
  await stalledHistory.load();
  assert.equal(stalledHistory.state.requests.length, 1, '重复点击必须合并历史请求');
  assert.equal(stalledHistory.state.loading, true);
  await stalledLoad;
  assert.equal(stalledHistory.state.loading, false, '不响应取消的请求也必须结束加载');
  assert.equal(stalledHistory.state.requests[0].signal.aborted, true, '超时必须取消网络读取');
  assert.equal(stalledHistory.bindings.olderMessagesAbortRef.current, null);
  assert.equal(stalledHistory.state.notices.length, 1);
  const historyRetry = stalledHistory.load();
  await Promise.resolve();
  stalledHistory.state.requests[0].resolve({ items: history.slice(0, 21), offset: 0, total: 30 });
  await Promise.resolve();
  assert.equal(stalledHistory.state.applied, 0, '迟到响应不能更新列表');
  assert.equal(stalledHistory.state.loading, true, '迟到响应不能清除重试状态');
  stalledHistory.state.requests[1].resolve({ items: history.slice(8, 21), offset: 8, total: 30 });
  await historyRetry;
  assert.equal(stalledHistory.state.applied, 1);
  assert.deepEqual(stalledHistory.bindings.messagesRef.current, history.slice(8, 30));
  assert.equal(stalledHistory.state.loading, false);

  for (const offset of [20, 21]) {
    const noProgress = historyHarness();
    const pending = noProgress.load();
    await Promise.resolve();
    noProgress.state.requests[0].resolve({ items: history.slice(20, 30), offset, total: 30 });
    await pending;
    assert.equal(noProgress.state.applied, 0, '无进展页不能继续推进');
    assert.equal(noProgress.state.loading, false);
    assert.equal(noProgress.state.notices.length, 1, '无进展必须给出可重试提示');
  }
  const cancelledHistory = historyHarness();
  const cancelledLoad = cancelledHistory.load();
  await Promise.resolve();
  cancelledHistory.bindings.olderMessagesAbortRef.current.abort();
  await cancelledLoad;
  assert.equal(cancelledHistory.state.loading, false);
  assert.equal(cancelledHistory.state.notices.length, 0, '会话切换取消不能提示请求失败');
  const layoutFailure = historyHarness();
  layoutFailure.bindings.mainRef.current = { getBoundingClientRect() { throw new Error('模拟布局读取失败'); } };
  await layoutFailure.load();
  assert.equal(layoutFailure.state.loading, false, '布局准备异常也必须释放忙碌状态');
  assert.equal(layoutFailure.bindings.olderMessagesAbortRef.current, null);

  replaceGlobal('window', undefined);
  const { createTimedAbortController, waitForDelayOrAbort } = await server.ssrLoadModule('/src/utils/timed_abort.ts');
  await assert.rejects(runWithTimeout(new Promise(() => {}), { timeoutMs: 1 }),
    { name: 'OperationTimeoutError' }, '无窗口环境也必须遵守总时限');
  const backgroundTimer = createTimedAbortController(1);
  await new Promise(resolve => backgroundTimer.controller.signal.addEventListener('abort', resolve, { once: true }));
  assert.equal(backgroundTimer.timedOut, true, '后台请求必须触发超时取消');
  backgroundTimer.dispose();
  const backgroundAbort = new AbortController();
  let delayFinished = false;
  const backgroundDelay = waitForDelayOrAbort(1000, backgroundAbort.signal).then(() => { delayFinished = true; });
  await Promise.resolve();
  assert.equal(delayFinished, false, '无窗口环境不能跳过重试间隔');
  backgroundAbort.abort();
  await backgroundDelay;
  replaceGlobal('window', browser);

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
  const handlerErrors = [];
  const stopHandlerFailure = subscribeSessionEvents('当前会话', {
    onSnapshot: () => { throw new Error('模拟快照回调失败'); },
    onError: (error) => handlerErrors.push(error),
  });
  send(snapshot);
  assert.equal(handlerErrors.length, 1, '业务回调异常必须转交错误处理');
  stopHandlerFailure();

  const invalidSessionErrors = [];
  const stopInvalidSession = subscribeSessionEvents('  ', {
    onSnapshot: () => assert.fail('空会话标识不能创建订阅'),
    onError: (error) => invalidSessionErrors.push(error),
  });
  await Promise.resolve();
  assert.equal(invalidSessionErrors.length, 1, '空会话标识必须异步报告错误');
  stopInvalidSession();

  stop();
  stop();
  send(snapshot);
  assert.equal(snapshots.length, 1, '取消订阅后不能继续通知页面');
  assert.equal(eventSource.closed, true);

  const staleSnapshots = [];
  const stopStale = subscribeSessionEvents('当前会话', {
    onSnapshot: value => staleSnapshots.push(value),
    onError: () => assert.fail('旧登录态的事件不能通知新页面'),
  });
  auth.writeToken('事件订阅后的新凭据', null);
  send(snapshot);
  assert.equal(staleSnapshots.length, 0, '登录态切换后必须丢弃旧连接快照');
  assert.equal(eventSource.closed, true, '旧登录态的连接必须关闭以停止自动重连');
  stopStale();

  replaceGlobal('EventSource', undefined);
  const cancelUnavailable = subscribeSessionEvents('当前会话', {
    onSnapshot: () => assert.fail('无 SSE 时不能生成快照'),
    onError: (error) => errors.push(error),
  });
  cancelUnavailable();
  await Promise.resolve();
  assert.equal(errors.length, 2, '卸载后不能投递 SSE 初始化错误');
  const stopUnavailable = subscribeSessionEvents('当前会话', {
    onSnapshot() {},
    onError: () => { throw new Error('模拟 SSE 初始化错误回调失败'); },
  });
  await Promise.resolve();
  stopUnavailable();

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

  const scrollActivity = await server.ssrLoadModule('/src/shared/ui/transcript_scroll_activity.ts');
  const savedScrollWindow = globalThis.window;
  const savedScrollDocument = globalThis.document;
  const scrollAttributes = new Map();
  replaceGlobal('document', { documentElement: {
    setAttribute: (name, value) => scrollAttributes.set(name, value),
    removeAttribute: name => scrollAttributes.delete(name),
    getAttribute: name => scrollAttributes.get(name) ?? null,
  } });
  let settleDelay = 0;
  replaceGlobal('window', {
    setTimeout: (_callback, delay) => { settleDelay = delay; return 1; },
    clearTimeout() {},
  });
  scrollActivity.markTranscriptScrollActivity(1200);
  scrollActivity.markTranscriptScrollActivity(120);
  assert.ok(settleDelay > 1000, '普通滚动通知不能缩短手势保护窗口');
  assert.equal(scrollActivity.isTranscriptScrollActive(), true);
  scrollActivity.clearTranscriptScrollActivity();
  assert.equal(scrollActivity.isTranscriptScrollActive(), false);
  replaceGlobal('window', savedScrollWindow);
  replaceGlobal('document', savedScrollDocument);

  console.log('[Web 运行时检查] 鉴权隔离、存储兜底、有界响应、取消原因、事件订阅、输入法关闭、慢速滚动保护、富文本帧预算与缓存边界检查通过。');
} finally {
  for (const [name, descriptor] of savedGlobals) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
  await server.close();
}
