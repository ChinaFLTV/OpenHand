import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import preact from '@preact/preset-vite';

// 只替换 Hook 生命周期和浏览器出口，直接驱动真实交互与轮询逻辑。
const hooksId = '\0交互检查钩子';
const locationId = '\0交互检查路由';
const noticesId = '\0交互检查通知';
const workspaceId = '\0交互检查工作区';
const pluginsId = '\0交互检查插件';
const preferencesId = '\0交互检查偏好';
const server = await createServer({
  configFile: false,
  root: fileURLToPath(new URL('..', import.meta.url)),
  cacheDir: 'node_modules/.vite-interactions-check',
  optimizeDeps: { noDiscovery: true, include: [] },
  server: { middlewareMode: true, watch: null, ws: false },
  appType: 'custom',
  ssr: { noExternal: ['preact', 'preact-iso'] },
  plugins: [preact(), {
    name: '交互检查环境',
    enforce: 'pre',
    resolveId(source) {
      if (source === 'preact-iso' || source === locationId) return locationId;
      if (source === 'preact/hooks' || source === hooksId) return hooksId;
      if (source.endsWith('/components/Snackbar') || source === noticesId) return noticesId;
      if (source.endsWith('/api/workspace') || source === workspaceId) return workspaceId;
      if (source.endsWith('/api/plugins') || source === pluginsId) return pluginsId;
      if (source.endsWith('/api/preferences') || source === preferencesId) return preferencesId;
    },
    load(id) {
      if (id === locationId) return 'export const routes = []; export function useLocation() { return { route: (...args) => routes.push(args) }; }';
      if (id === noticesId) return 'export const notices = []; export function showSnackbar(message) { notices.push(message); }';
      if (id === preferencesId) return `
        export const requests = [];
        function request(kind, args) {
          return new Promise((resolve, reject) => requests.push({ kind, args, resolve, reject }));
        }
        export const fetchPreferences = (...args) => request('load', args);
        export const updatePreferences = (...args) => request('save', args);
      `;
      if (id === pluginsId) return `
        export const requests = [];
        function request(kind, args) {
          return new Promise((resolve, reject) => requests.push({ kind, args, resolve, reject }));
        }
        export const listPlugins = (...args) => request('list', args);
        export const performPluginAction = (...args) => request('action', args);
        export const rescanPlugins = (...args) => request('rescan', args);
        export const checkPluginUpdate = (...args) => request('check', args);
        export const pluginDiagnostics = plugin => plugin.diagnostics ?? [];
      `;
      if (id === workspaceId) return `
        export const requests = [];
        function request(kind, args) {
          return new Promise((resolve, reject) => requests.push({ kind, args, resolve, reject }));
        }
        export const listWorkspaceFiles = (...args) => request('list', args);
        export const readWorkspaceFile = (...args) => request('read', args);
        export const writeWorkspaceFile = (...args) => request('write', args);
        export const createWorkspaceDirectory = (...args) => request('create', args);
        export const deleteWorkspaceFile = (...args) => request('delete', args);
      `;
      if (id !== hooksId) return;
      return `
        const slots = [];
        let index = 0;
        let effects = [];
        function changed(previous, next) { return !previous || next.some((value, i) => !Object.is(value, previous[i])); }
        export function useRef(value) { return slots[index++] ??= { current: value }; }
        export function useState(value) {
          const state = useRef();
          if (!state.initialized) {
            state.current = typeof value === 'function' ? value() : value;
            state.initialized = true;
          }
          return [state.current, next => { state.current = typeof next === 'function' ? next(state.current) : next; }];
        }
        export function useMemo(factory, deps) {
          const state = useRef();
          if (!state.current || changed(state.current.deps, deps)) state.current = { value: factory(), deps };
          return state.current.value;
        }
        export function useCallback(callback, deps) {
          const state = useRef();
          if (!state.current || changed(state.current.deps, deps)) state.current = { callback, deps };
          return state.current.callback;
        }
        export function useLayoutEffect(effect, deps) {
          const state = useRef();
          if (!state.current || changed(state.current.deps, deps)) {
            effects.push(() => {
              state.current?.cleanup?.();
              state.current = { deps, cleanup: effect() };
            });
          }
        }
        export const useEffect = useLayoutEffect;
        export function render(callback) {
          index = 0;
          const result = callback();
          const pending = effects;
          effects = [];
          pending.forEach(effect => effect());
          return result;
        }
        export function unmount() {
          slots.forEach(state => state.current?.cleanup?.());
          slots.length = 0;
        }
      `;
    },
  }],
});
const saved = new Map();
function replace(name, value) {
  if (!saved.has(name)) saved.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
  Object.defineProperty(globalThis, name, { configurable: true, writable: true, value });
}
class Surface extends EventTarget {
  scrollHeight = 200;
  clientHeight = 100;
  scrollTop = 0;
  captured = new Set();
  closest() { return null; }
  contains(target) { return target === this; }
  setPointerCapture(id) { this.captured.add(id); }
  hasPointerCapture(id) { return this.captured.has(id); }
  releasePointerCapture(id) { this.captured.delete(id); }
}
try {
  replace('Element', Surface);
  replace('window', { scrollY: 0 });
  replace('document', { scrollingElement: null });
  const hooks = await server.ssrLoadModule(hooksId);
  const { DecisionComposerForm } = await server.ssrLoadModule('/src/components/DecisionComposerForm.tsx');
  const { initialDecisionDraft } = await server.ssrLoadModule('/src/shared/util/decision.ts');
  let draftText = JSON.stringify({ state: '待评估内容', questions: { 决策: { type: 'choice', instructions: '选择最合适的候选项', criteria: Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`候选 ${i}`, null])) } } });
  let publishes = 0;
  const onDraftChange = (value) => { draftText = value; publishes++; };
  let form;
  function renderDecision() {
    for (let i = 0; i < 4; i++) form = hooks.render(() => DecisionComposerForm({ initialText: draftText, onChange: onDraftChange }));
  }
  function nodes(node, predicate) {
    if (!node || typeof node !== 'object') return [];
    if (Array.isArray(node)) return node.flatMap(child => nodes(child, predicate));
    if (node.props?.className === 'oh-decision-criteria-list') return nodes(node.props.items.map(node.props.renderItem), predicate);
    return [...(predicate(node) ? [node] : []), ...nodes(node.props?.children, predicate)];
  }
  const fields = () => nodes(form, node => node.type === 'input' && node.props.placeholder);
  const selectType = (label) => {
    nodes(form, node => node.type === 'button' && node.props.class?.split(' ').includes('oh-decision-type'))[['判断', '选择', '评分'].indexOf(label)].props.onClick();
    renderDecision();
  };
  const addCriterion = () => {
    nodes(form, node => node.props?.class?.split(' ').includes('oh-decision-add'))[0].props.onClick();
    renderDecision();
  };
  const editCriterion = (index, value) => {
    fields()[index].props.onInput({ currentTarget: { value } });
    renderDecision();
  };
  renderDecision();
  assert.equal(publishes, 0, '挂载决策表单不能自动回写草稿');
  assert.equal(fields().length, 30);
  addCriterion();
  assert.equal(fields().length, 31, '草稿回传不能删除新建空白行');
  selectType('评分');
  assert.deepEqual(fields().map(node => node.props.value), ['', ''], '候选项不能复用为评分等级');
  editCriterion(0, '低');
  editCriterion(1, '高');
  assert.equal(initialDecisionDraft(draftText).criteria, '低\n高');
  const moveButtons = () => nodes(form, node => node.type === 'button' && node.props.children === '⌄');
  assert.equal(moveButtons()[1].props.disabled, true, '末项不能下移');
  moveButtons()[0].props.onClick();
  renderDecision();
  assert.deepEqual(fields().map(node => node.props.value), ['高', '低']);
  assert.equal(initialDecisionDraft(draftText).criteria, '高\n低', '排序立即同步请求顺序');
  nodes(form, node => node.type === 'button' && node.props.children === '⌃')[1].props.onClick();
  renderDecision();
  assert.deepEqual(fields().map(node => node.props.value), ['低', '高']);
  addCriterion();
  selectType('判断');
  assert.equal(fields().length, 0);
  assert.equal(initialDecisionDraft(draftText).criteria, '');
  selectType('选择');
  assert.equal(fields().length, 31);
  assert.equal(fields()[0].props.value, '候选 0');
  assert.equal(fields()[30].props.value, '');
  editCriterion(0, '修改后的候选');
  nodes(form, node => node.props?.class?.split(' ').includes('oh-decision-remove'))[1].props.onClick();
  renderDecision();
  selectType('评分');
  assert.deepEqual(fields().map(node => node.props.value), ['低', '高', '']);
  assert.equal(initialDecisionDraft(draftText).criteria, '低\n高');
  for (let i = 0; i < 7; i++) addCriterion();
  assert.equal(fields().length, 10);
  assert.equal(nodes(form, node => node.props?.class?.split(' ').includes('oh-decision-add'))[0].props.disabled, true);
  const settledPublishes = publishes;
  renderDecision();
  assert.equal(publishes, settledPublishes, '草稿回传不能形成重复更新');
  draftText = JSON.stringify({ state: '新草稿', questions: { 决策: { type: 'score', instructions: '评分', criteria: ['一级', '二级'] } } });
  renderDecision();
  assert.deepEqual(fields().map(node => node.props.value), ['一级', '二级']);
  selectType('选择');
  assert.deepEqual(fields().map(node => node.props.value), [''], '外部替换草稿应清除旧草稿的暂存字段');
  draftText = '';
  renderDecision();
  assert.equal(draftText, '', '发送清空后不能重新生成空请求');
  assert.equal(nodes(form, node => node.type === 'textarea')[0].props.value, '');
  selectType('评分');
  assert.deepEqual(fields().map(node => node.props.value), ['', '']);
  hooks.unmount();
  draftText = '';
  const beforeEmptyMount = publishes;
  renderDecision();
  assert.equal(draftText, '');
  assert.equal(publishes, beforeEmptyMount, '重新挂载空会话不能复活旧正文');
  const editedContent = '尚未发送的内容：`代码`\n```\n正文\n```';
  const contentInput = nodes(form, node => node.type === 'textarea')[0];
  const questionInput = nodes(form, node => node.type === 'input' && node.props.placeholder === undefined)[0];
  contentInput.props.onInput({ currentTarget: { value: editedContent } });
  questionInput.props.onInput({ currentTarget: { value: '用户自定义问题' } });
  renderDecision();
  assert.equal(initialDecisionDraft(draftText).state, editedContent, '同帧连续编辑不能覆盖前一个字段');
  assert.equal(initialDecisionDraft(draftText).question, '用户自定义问题');
  assert.equal(draftText.split('```').length, 3, '真实表单编码必须转义正文反引号，不能提前关闭围栏');
  draftText = '';
  renderDecision();
  const beforeParentRerender = publishes;
  for (let i = 0; i < 3; i++) {
    hooks.render(() => DecisionComposerForm({ initialText: draftText, onChange: text => onDraftChange(text) }));
  }
  assert.equal(draftText, '', '父组件回调变更不能回填已发送正文');
  assert.equal(publishes, beforeParentRerender);
  selectType('评分');
  editCriterion(0, '未完成的评分等级');
  const unfinishedDraft = draftText;
  hooks.unmount();
  renderDecision();
  assert.equal(draftText, unfinishedDraft, '未完成草稿往返恢复不应再嵌套代码块');
  assert.equal(nodes(form, node => node.type === 'textarea')[0].props.value, '');
  assert.deepEqual(fields().map(node => node.props.value), ['未完成的评分等级', '']);
  hooks.unmount();
  const { notices } = await server.ssrLoadModule(noticesId);
  const { usePullToRefresh } = await server.ssrLoadModule('/src/hooks/usePullToRefresh.ts');
  const surface = new Surface();
  const ref = { current: surface };
  let refreshes = 0;
  let complete;
  let enabled = true;
  let fail = false;
  const render = () => hooks.render(() => usePullToRefresh(ref, {
    enabled,
    onRefresh: () => {
      refreshes++;
      if (fail) throw new Error('模拟刷新失败');
      return new Promise(resolve => { complete = resolve; });
    },
  }));
  const dispatch = (type, props) => surface.dispatchEvent(Object.assign(new Event(type), props));
  const pointer = (type, id = 1, y = 0) => dispatch(type, {
    pointerType: 'pen', pointerId: id, isPrimary: true, button: 0, clientY: y,
  });
  const touch = (type, touches, changedTouches = touches) => dispatch(type, { touches, changedTouches });
  const startPen = () => { pointer('pointerdown'); pointer('pointermove', 1, 300); };
  render();
  startPen();
  pointer('pointerup', 2);
  assert.equal(refreshes, 0, '无关指针结束不能提交当前手势');
  pointer('pointercancel');
  assert.equal(refreshes, 0, '取消手势不能刷新');
  assert.equal(surface.captured.size, 0, '取消后必须释放指针捕获');
  assert.equal(render().pulled, 0);

  startPen();
  render();
  pointer('pointerup');
  startPen();
  pointer('pointerup');
  assert.equal(refreshes, 1, '重新渲染不能丢失手势，刷新期间不能重复提交');
  complete();
  await Promise.resolve();
  assert.equal(render().refreshing, false);

  const first = { identifier: 1, clientY: 0 };
  const moved = { ...first, clientY: 300 };
  touch('touchstart', [first]);
  touch('touchmove', [moved]);
  touch('touchcancel', [], [moved]);
  assert.equal(refreshes, 1, '触摸取消不能刷新');
  touch('touchstart', [first]);
  touch('touchmove', [moved]);
  touch('touchstart', [moved, { identifier: 2, clientY: 100 }]);
  touch('touchend', [], [moved]);
  assert.equal(refreshes, 1, '多指手势必须取消下拉');
  touch('touchstart', [first]);
  touch('touchmove', []);
  touch('touchend', [], [first]);
  assert.equal(refreshes, 1, '空触点移动必须安全取消');

  startPen();
  pointer('lostpointercapture');
  pointer('pointerup');
  assert.equal(refreshes, 1, '失去指针捕获必须取消手势');

  startPen();
  enabled = false;
  render();
  pointer('pointerup');
  assert.equal(refreshes, 1, '禁用时必须取消未完成手势');
  assert.equal(surface.captured.size, 0);
  enabled = true;
  render();
  fail = true;
  startPen();
  pointer('pointerup');
  assert.deepEqual(notices, ['模拟刷新失败'], '刷新异常必须通知用户');
  assert.equal(render().refreshing, false, '刷新失败必须释放忙碌状态');
  fail = false;
  touch('touchstart', [first]);
  touch('touchmove', [moved]);
  touch('touchend', [], [{ identifier: 2, clientY: 300 }]);
  assert.equal(refreshes, 2, '无关触点结束不能提交当前手势');
  touch('touchend', [], [moved]);
  assert.equal(refreshes, 3, '所属触点正常松开后必须刷新');
  hooks.unmount();
  complete();
  await Promise.resolve();
  const before = refreshes;
  startPen();
  pointer('pointerup');
  assert.equal(refreshes, before, '卸载后必须移除手势监听器');

  const timers = new Map();
  let timerId = 0;
  replace('window', {
    setTimeout(callback, delay) {
      const id = ++timerId;
      timers.set(id, { callback, delay });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
  });
  const settle = async () => {
    for (let turn = 0; turn < 24; turn++) await Promise.resolve();
  };
  const tick = async (delay) => {
    const entry = [...timers].find(([, timer]) => timer.delay === delay);
    assert.ok(entry, `缺少 ${delay} 毫秒的预期计时器`);
    timers.delete(entry[0]);
    entry[1].callback();
    await settle();
  };
  const { useAsyncPolling } = await server.ssrLoadModule('/src/hooks/useAsyncPolling.ts');
  const runs = [];
  const pollingErrors = [];
  let options = { enabled: true, intervalMs: 500, taskTimeoutMs: 1000 };
  const renderPoll = () => hooks.render(() => useAsyncPolling((isActive, signal) => {
    let resolve;
    const promise = new Promise(done => { resolve = done; });
    runs.push({ isActive, signal, resolve });
    return promise;
  }, { ...options, onError: error => pollingErrors.push(error) }));
  renderPoll();
  await settle();
  assert.equal(runs.length, 1);
  for (let round = 0; round < 5; round++) {
    options = { ...options, enabled: false };
    renderPoll();
    options = { ...options, enabled: true, intervalMs: 750 };
    renderPoll();
    await settle();
  }
  assert.equal(runs.length, 1, '反复启停或修改间隔不能叠加忽略取消的旧任务');
  assert.equal(runs[0].signal.aborted, true, '配置变更必须中止旧请求');
  assert.equal(runs[0].isActive(), false, '旧任务不能更新新配置的页面');
  runs[0].resolve();
  await settle();
  assert.equal(timers.size, 1, '旧任务结束后只能保留新任务的超时计时器');
  assert.equal(runs.length, 2, '旧任务结束后必须补执行尚未启动的立即刷新');
  await tick(1000);
  assert.equal(pollingErrors.length, 1, '任务超时必须报告一次');
  assert.equal(runs[1].signal.aborted, true);
  assert.equal(timers.size, 0, '忽略超时取消的任务结束前不得继续调度');
  options = { ...options, intervalMs: 900 };
  renderPoll();
  await settle();
  assert.equal(runs.length, 2, '超时后改配置仍不能绕过运行门闩');
  runs[1].resolve();
  await settle();
  assert.equal(runs.length, 3, '超时旧任务退出后不能把待执行的立即刷新推迟到下一周期');
  runs[2].resolve();
  await settle();
  assert.equal(runs.length, 3, '完成立即刷新后必须恢复正常间隔，不能形成无延迟轮询');
  await tick(900);
  assert.equal(runs.length, 4);
  hooks.unmount();
  runs[3].resolve();
  await settle();
  assert.equal(timers.size, 0, '卸载必须清除计时器且阻止迟到任务重新调度');
  renderPoll();
  hooks.unmount();
  await settle();
  assert.equal(runs.length, 4, '开始前卸载不得启动底层轮询任务');
  const { routes } = await server.ssrLoadModule(locationId);
  const { useAnimatedLocation } = await server.ssrLoadModule('/src/hooks/useAnimatedLocation.ts');
  const transitionRoot = { dataset: {}, removeAttribute() {} };
  replace('document', { documentElement: transitionRoot });
  let completeTransition;
  let delayedUpdate;
  document.startViewTransition = (update) => {
    delayedUpdate = update;
    return { finished: new Promise(resolve => { completeTransition = resolve; }) };
  };
  const location = hooks.render(useAnimatedLocation);
  location.route('/sessions', true);
  assert.equal(routes.length, 0, '导航应等待过渡更新回调');
  await tick(720);
  assert.deepEqual(routes, [['/sessions', true]], '过渡停滞不能让导航永久丢失');
  delayedUpdate();
  completeTransition();
  await settle();
  assert.equal(routes.length, 1, '迟到过渡不得重复提交导航');
  assert.equal(transitionRoot.dataset.routeTransition, undefined);
  location.route('/old');
  const staleUpdate = delayedUpdate;
  const staleCompletion = completeTransition;
  location.route('/latest');
  const latestUpdate = delayedUpdate;
  staleUpdate();
  staleCompletion();
  await settle();
  assert.equal(routes.length, 1, '旧过渡不能覆盖新导航');
  latestUpdate();
  completeTransition();
  await settle();
  assert.deepEqual(routes.at(-1), ['/latest', undefined]);
  document.startViewTransition = () => ({ finished: Promise.reject(new Error('过渡不可用')) });
  location.route('/fallback');
  await settle();
  assert.deepEqual(routes.at(-1), ['/fallback', undefined], '过渡失败仍必须完成导航');
  assert.equal(timers.size, 0, '过渡结束必须清除所有兜底计时器');
  hooks.unmount();
  const browser = new EventTarget();
  const documentSurface = new Surface();
  replace('window', browser);
  replace('document', documentSurface);
  replace('Node', Surface);
  const { useDismissibleOverlay } = await server.ssrLoadModule('/src/hooks/useDismissibleOverlay.ts');
  const { registerOverlayEscapeLayer } = await server.ssrLoadModule('/src/shared/ui/overlay_escape_stack.ts');
  let parentCloses = 0;
  let menuCloses = 0;
  const removeParent = registerOverlayEscapeLayer({
    canClose: () => true, requestClose: () => parentCloses++,
  });
  let menuClosing = false;
  const target = new Surface();
  const targets = [{ current: target }];
  const renderMenu = () => hooks.render(() => useDismissibleOverlay({
    active: true, closing: menuClosing, targets, onDismiss: () => menuCloses++,
  }));
  const escape = async () => {
    browser.dispatchEvent(Object.assign(new Event('keydown', { cancelable: true }), { key: 'Escape' }));
    await Promise.resolve();
  };
  renderMenu();
  await escape();
  assert.equal(menuCloses, 1, 'Escape 只关闭顶层菜单');
  menuClosing = true;
  renderMenu();
  await escape();
  documentSurface.dispatchEvent(new Event('mousedown'));
  assert.equal(menuCloses, 1, '退场中的菜单不应重复执行关闭');
  assert.equal(parentCloses, 0, '退场结束前 Escape 不得穿透到下层弹窗');
  menuClosing = false;
  renderMenu();
  await escape();
  assert.equal(menuCloses, 2, '取消退场后仍可关闭菜单');
  hooks.unmount();
  await escape();
  assert.equal(parentCloses, 1, '菜单卸载后恢复下层弹窗的 Escape');
  removeParent();

  const frames = new Map();
  let frameId = 0;
  browser.requestAnimationFrame = (callback) => {
    const id = ++frameId;
    frames.set(id, callback);
    return id;
  };
  browser.cancelAnimationFrame = (id) => frames.delete(id);
  browser.visualViewport = new EventTarget();
  const { useViewportChange } = await server.ssrLoadModule('/src/hooks/useViewportChange.ts');
  let measuring = true;
  let measurements = 0;
  let latestMeasurements = 0;
  let measure = () => measurements++;
  const renderTracking = () => hooks.render(() => useViewportChange(measuring, measure));
  renderTracking();
  for (let i = 0; i < 20; i++) {
    browser.dispatchEvent(new Event('scroll'));
    browser.dispatchEvent(new Event('resize'));
    browser.visualViewport.dispatchEvent(new Event('resize'));
  }
  assert.equal(frames.size, 1, '密集滚动和视口缩放只能安排一次布局测量');
  measure = () => latestMeasurements++;
  renderTracking();
  const [frame, callback] = [...frames][0];
  frames.delete(frame);
  callback();
  assert.equal(measurements, 0, '待执行测量不得使用旧渲染的回调');
  assert.equal(latestMeasurements, 1);
  browser.visualViewport.dispatchEvent(new Event('scroll'));
  assert.equal(frames.size, 1);
  measuring = false;
  renderTracking();
  assert.equal(frames.size, 0, '隐藏浮层必须取消待执行测量');
  browser.dispatchEvent(new Event('resize'));
  browser.visualViewport.dispatchEvent(new Event('scroll'));
  assert.equal(frames.size, 0, '隐藏浮层必须解除所有视口监听');
  measuring = true;
  renderTracking();
  hooks.unmount();
  browser.dispatchEvent(new Event('scroll'));
  browser.visualViewport.dispatchEvent(new Event('resize'));
  assert.equal(frames.size, 0, '卸载后不得留下动画帧和视口监听');
  browser.setTimeout = globalThis.setTimeout;
  browser.clearTimeout = globalThis.clearTimeout;
  browser.matchMedia = query => Object.assign(new EventTarget(), { matches: query.includes('min-width') });
  documentSurface.documentElement = { setAttribute() {}, removeAttribute() {} };
  const { FilesPage } = await server.ssrLoadModule('/src/features/files/components/FilesPage.tsx');
  const { syncLangFromAppPreferences } = await server.ssrLoadModule('/src/i18n/index.ts');
  syncLangFromAppPreferences('zh_Hans');
  const { requests: workspaceRequests } = await server.ssrLoadModule(workspaceId);
  let filesPage;
  const renderFiles = () => { filesPage = hooks.render(FilesPage); };
  const fileNodes = predicate => nodes(filesPage, predicate);
  const searchFiles = value => {
    const input = fileNodes(node => node.type === 'input' && node.props.value !== undefined && node.props.class.includes('flex-1'))[0];
    input.props.oninput({ target: { value } });
    renderFiles();
  };
  const latestRequest = kind => workspaceRequests.findLast(request => request.kind === kind);
  const fileItem = name => ({ name, path: name, type: 'file', editable: true, size: 1, modified_at: '' });
  const fileA = fileItem('甲.txt');
  const fileB = fileItem('乙.txt');
  const listResult = items => ({ root: '/', path: '', items, query: '', type: 'all', write_enabled: true, max_file_bytes: 1024, allowed_extensions: [] });
  const fileRows = () => fileNodes(node => node.type === 'button' && node.props.class?.split(' ').includes('oh-files-row'));
  const openFile = path => {
    fileRows().find(node => node.props.title === path).props.onClick();
    renderFiles();
  };
  const editor = () => fileNodes(node => node.props.filename != null && node.props.onChange)[0];
  const saveButton = () => fileNodes(node => node.type === 'button' && ['保存', '保存中…'].includes(node.props.children))[0];
  const savedBadge = () => fileNodes(node => node.props.class === 'oh-files-status is-saved');
  const dirtyBadge = () => fileNodes(node => node.props.class === 'oh-files-status is-dirty');
  const editFile = text => { editor().props.onChange(text); renderFiles(); };
  const completeRead = async content => {
    latestRequest('read').resolve({ content, size: content.length, modified_at: '' });
    await settle();
    renderFiles();
  };
  renderFiles();
  const staleList = latestRequest('list');
  searchFiles('新');
  const currentList = latestRequest('list');
  assert.equal(staleList.args[0].signal.aborted, true, '筛选变更必须中止旧列表请求');
  currentList.resolve(listResult([fileA, fileB]));
  await settle();
  staleList.resolve(listResult([fileItem('过期.txt')]));
  await settle();
  renderFiles();
  assert.deepEqual(fileRows().map(node => node.props.title), [fileA.path, fileB.path], '忽略取消的旧响应也不能覆盖最新文件列表');
  searchFiles('旧失败');
  const staleFailure = latestRequest('list');
  searchFiles('当前');
  latestRequest('list').resolve(listResult([fileA, fileB]));
  await settle();
  staleFailure.reject(new Error('过期列表失败'));
  await settle();
  renderFiles();
  assert.equal(fileRows().length, 2, '旧请求失败不能清空已成功加载的新列表');

  openFile(fileA.path);
  const staleRead = latestRequest('read');
  openFile(fileB.path);
  assert.equal(staleRead.args[1].signal.aborted, true, '切换文件必须取消旧内容读取');
  await completeRead('乙正文');
  staleRead.resolve({ content: '过期甲正文', size: 6, modified_at: '' });
  await settle();
  renderFiles();
  assert.equal(editor().props.value, '乙正文');
  editFile('乙第一次修改');
  const saveClick = saveButton().props.onClick;
  saveClick();
  saveClick();
  assert.equal(workspaceRequests.filter(request => request.kind === 'write').length, 1, '同帧重复保存只能提交一次');
  editFile('乙保存期间的新修改');
  latestRequest('write').resolve({ size: 8, modified_at: '' });
  await settle();
  renderFiles();
  assert.equal(dirtyBadge().length, 1, '保存期间的新修改必须继续标记为未保存');
  assert.equal(savedBadge().length, 0, '旧版本保存成功不能显示当前内容已保存');
  assert.equal(saveButton().props.disabled, false);

  saveButton().props.onClick();
  latestRequest('write').resolve({ size: 12, modified_at: '' });
  await settle();
  renderFiles();
  assert.equal(dirtyBadge().length, 0, '未继续编辑时保存成功应清除未保存状态');
  assert.equal(savedBadge().length, 1, '当前版本保存成功应显示成功状态');
  editFile('乙再次修改');
  saveButton().props.onClick();
  const oldSave = latestRequest('write');
  openFile(fileA.path);
  await completeRead('甲正文');
  editFile('甲未保存修改');
  oldSave.resolve({ size: 888, modified_at: '' });
  await settle();
  renderFiles();
  assert.equal(editor().props.value, '甲未保存修改');
  assert.equal(dirtyBadge().length, 1, '其他文件的保存响应不能清除当前文件未保存状态');
  assert.equal(savedBadge().length, 0);
  assert.ok(!JSON.stringify(fileNodes(node => node.props.class === 'oh-files-detail-meta')[0].props.children).includes('888'), '其他文件的保存响应不能覆盖当前文件元信息');

  saveButton().props.onClick();
  const pendingSave = latestRequest('write');
  openFile(fileB.path);
  const pendingRead = latestRequest('read');
  searchFiles('卸载');
  const pendingList = latestRequest('list');
  const noticesBeforeUnmount = notices.length;
  hooks.unmount();
  assert.equal(pendingSave.args[2].signal.aborted, true, '卸载必须取消文件保存等待');
  assert.equal(pendingRead.args[1].signal.aborted, true, '卸载必须取消文件读取');
  assert.equal(pendingList.args[0].signal.aborted, true, '卸载必须取消列表请求');
  pendingSave.resolve({ size: 999, modified_at: '' });
  pendingRead.resolve({ content: '迟到内容', size: 4, modified_at: '' });
  pendingList.resolve(listResult([]));
  await settle();
  assert.equal(notices.length, noticesBeforeUnmount, '卸载后的迟到保存响应不得再显示成功通知');

  renderFiles();
  latestRequest('list').resolve(listResult([fileA, fileB]));
  await settle();
  renderFiles();
  const deleteFile = path => {
    const row = fileNodes(node => node.type === 'li' && node.key === path)[0];
    nodes(row, node => node.props.class?.includes('oh-files-delete-button'))[0].props.onClick();
    renderFiles();
    return fileNodes(node => node.props.confirmBeforeClose)[0];
  };
  openFile(fileA.path);
  await completeRead('甲正文');
  const deleteDialog = deleteFile(fileA.path);
  const deletion = deleteDialog.props.onConfirm();
  const staleDelete = latestRequest('delete');
  assert.equal(await deleteDialog.props.onConfirm(), false, '删除等待期间必须阻止同帧重复提交');
  assert.equal(workspaceRequests.filter(request => request.kind === 'delete').length, 1);
  openFile(fileB.path);
  await completeRead('乙正文');
  editFile('乙仍未保存');
  staleDelete.resolve({ ok: true });
  await settle();
  latestRequest('list').resolve(listResult([fileB]));
  assert.equal(await deletion, true);
  deleteDialog.props.onConfirmSuccess();
  renderFiles();
  assert.equal(editor().props.filename, fileB.path, '删除旧文件不能清空后来选择的文件');
  assert.equal(editor().props.value, '乙仍未保存');
  assert.equal(dirtyBadge().length, 1);

  const currentDeleteDialog = deleteFile(fileB.path);
  const currentDeletion = currentDeleteDialog.props.onConfirm();
  latestRequest('delete').resolve({ ok: true });
  await settle();
  renderFiles();
  assert.equal(editor(), undefined, '删除当前选中的文件必须清空详情');
  const deleteRefresh = latestRequest('list');
  hooks.unmount();
  deleteRefresh.resolve(listResult([]));
  assert.equal(await currentDeletion, false, '删除后刷新期间卸载不能继续执行弹窗成功收尾');

  for (const createKind of ['file', 'directory']) {
    renderFiles();
    latestRequest('list').resolve(listResult([fileA]));
    await settle();
    renderFiles();
    const createButtons = fileNodes(node => node.type === 'button' && node.props.class?.includes('oh-files-secondary-button'));
    createButtons[createKind === 'file' ? 0 : 1].props.onClick();
    renderFiles();
    fileNodes(node => node.type === 'input' && node.props.autoFocus)[0].props.oninput({ target: { value: '新项目' } });
    renderFiles();
    const createForm = fileNodes(node => node.type === 'form' && node.props.class?.includes('min-w-'))[0];
    const requestCount = workspaceRequests.length;
    createForm.props.onSubmit({ preventDefault() {} });
    createForm.props.onSubmit({ preventDefault() {} });
    assert.equal(workspaceRequests.length, requestCount + 1, '创建文件或目录不能重复提交');
    const pendingCreate = latestRequest(createKind === 'file' ? 'write' : 'create');
    renderFiles();
    assert.equal(fileNodes(node => node.type === 'input' && node.props.autoFocus)[0].props.disabled, true, '创建期间不能修改即将被清空的名称');
    const pendingDeleteDialog = deleteFile(fileA.path);
    const pendingDeletion = pendingDeleteDialog.props.onConfirm();
    const pendingDelete = latestRequest('delete');
    const mutationNotices = notices.length;
    const mutationRequests = workspaceRequests.length;
    hooks.unmount();
    assert.equal(pendingCreate.args[createKind === 'file' ? 2 : 1].signal.aborted, true, '卸载必须取消创建请求');
    assert.equal(pendingDelete.args[1].signal.aborted, true, '卸载必须取消删除请求');
    if (createKind === 'file') {
      pendingCreate.resolve({ ok: true });
      pendingDelete.resolve({ ok: true });
    } else {
      pendingCreate.reject(new Error('迟到创建失败'));
      pendingDelete.reject(new Error('迟到删除失败'));
    }
    assert.equal(await pendingDeletion, false);
    await settle();
    assert.equal(notices.length, mutationNotices, '卸载后的创建或删除结果不得继续显示通知');
    assert.equal(workspaceRequests.length, mutationRequests, '卸载后的创建或删除不得重新请求列表');
  }
  browser.setTimeout = (callback, delay) => {
    const id = ++timerId;
    timers.set(id, { callback, delay });
    return id;
  };
  browser.clearTimeout = id => timers.delete(id);
  const { PluginsPage } = await server.ssrLoadModule('/src/features/plugins/components/PluginsPage.tsx');
  const { requests: pluginRequests } = await server.ssrLoadModule(pluginsId);
  let pluginsPage;
  const renderPlugins = () => { pluginsPage = hooks.render(PluginsPage); };
  const pluginNodes = predicate => nodes(pluginsPage, predicate);
  const pluginButton = label => pluginNodes(node => node.type === 'button' && (
    node.props.children === label || Array.isArray(node.props.children) && node.props.children.includes(label)
  ))[0];
  const latestPluginRequest = kind => pluginRequests.findLast(request => request.kind === kind);
  const plugin = {
    id: 'python', name: 'Python', description: '', status: 'installed', enabled: true,
    installed_version: '3.12', latest_version: null, dependencies: [], dependents: [],
    supports_uninstall: true, has_update: false, template_associations: [],
  };
  const pluginVersions = () => pluginNodes(node => node.type === 'code').map(node => node.props.children);
  renderPlugins();
  await settle();
  latestPluginRequest('list').resolve({ items: [plugin] });
  await settle();
  renderPlugins();
  await tick(5000);
  const stalePluginPoll = latestPluginRequest('list');
  const checkUpdate = pluginButton('检查更新').props.onClick;
  checkUpdate();
  checkUpdate();
  assert.equal(pluginRequests.filter(request => request.kind === 'check').length, 1, '插件检查更新必须阻止同帧重复提交');
  stalePluginPoll.resolve({ items: [{ ...plugin, installed_version: '旧版本' }] });
  await settle();
  renderPlugins();
  assert.ok(!pluginVersions().includes('旧版本'), '开始插件操作后不能接受尚未取消的旧轮询快照');
  assert.equal(pluginButton('重新扫描').props.disabled, true, '检查更新期间不能并发扫描共享插件状态');
  latestPluginRequest('check').resolve({ success: false, item: plugin, message: '检查更新失败' });
  await settle();
  renderPlugins();
  assert.equal(notices.at(-1), '检查更新失败', '服务端检查更新失败不得显示未发现新版本');
  await settle();
  latestPluginRequest('list').resolve({ items: [plugin] });
  await settle();
  renderPlugins();

  for (const kind of ['rescan', 'check']) {
    pluginButton(kind === 'rescan' ? '重新扫描' : '检查更新').props.onClick();
    renderPlugins();
    await tick(5000);
    const pollDuringOperation = latestPluginRequest('list');
    const updatedPlugin = { ...plugin, installed_version: '操作新版本' };
    latestPluginRequest(kind).resolve(kind === 'rescan'
      ? { items: [updatedPlugin] }
      : { success: true, item: updatedPlugin });
    await settle();
    renderPlugins();
    await settle();
    assert.equal(latestPluginRequest('list'), pollDuringOperation, '立即刷新必须等待忽略取消的旧轮询释放门闩');
    pollDuringOperation.resolve({ items: [{ ...plugin, installed_version: '操作期间旧版本' }] });
    await settle();
    renderPlugins();
    assert.ok(pluginVersions().includes('操作新版本'), '操作完成后必须屏蔽此前发起的轮询快照');
    await settle();
    assert.notEqual(latestPluginRequest('list'), pollDuringOperation, '操作结束必须立即重新读取最终状态');
    latestPluginRequest('list').resolve({ items: [plugin] });
    await settle();
    renderPlugins();
  }

  pluginButton('卸载').props.onClick();
  renderPlugins();
  pluginNodes(node => node.props.confirmLabel === '确认卸载')[0].props.onConfirm();
  renderPlugins();
  await tick(5000);
  latestPluginRequest('list').resolve({ items: [{ ...plugin, status: 'uninstalling' }] });
  await settle();
  renderPlugins();
  assert.ok(pluginNodes(node => node.type === 'span' && node.props.children === '卸载中…').length > 0, '长操作期间仍需轮询并展示真实进度');
  const progressRequest = latestPluginRequest('list');
  latestPluginRequest('action').resolve({ success: true });
  await settle();
  renderPlugins();
  await settle();
  assert.notEqual(latestPluginRequest('list'), progressRequest, '插件变更结束后必须立即刷新最终状态');
  latestPluginRequest('list').resolve({ items: [plugin] });
  await settle();
  renderPlugins();

  for (const kind of ['rescan', 'action', 'check']) {
    const operationsBefore = pluginRequests.filter(request => request.kind === kind).length;
    if (kind === 'rescan') {
      const rescan = pluginButton('重新扫描').props.onClick;
      rescan();
      rescan();
    } else if (kind === 'action') {
      pluginButton('卸载').props.onClick();
      renderPlugins();
      const confirmation = pluginNodes(node => node.props.confirmLabel === '确认卸载')[0];
      confirmation.props.onConfirm();
      confirmation.props.onConfirm();
    } else {
      pluginButton('检查更新').props.onClick();
    }
    const pendingOperation = latestPluginRequest(kind);
    assert.ok(pendingOperation);
    assert.equal(pluginRequests.filter(request => request.kind === kind).length, operationsBefore + 1, '插件操作不能同帧重复提交');
    renderPlugins();
    const signal = pendingOperation.args[kind === 'rescan' ? 0 : kind === 'action' ? 2 : 1].signal;
    const noticesBeforePluginUnmount = notices.length;
    const requestsBeforePluginUnmount = pluginRequests.length;
    hooks.unmount();
    assert.equal(signal.aborted, true, '卸载插件页必须取消所有用户操作请求');
    pendingOperation.resolve(kind === 'rescan' ? { items: [plugin] } : kind === 'check'
      ? { success: true, item: { ...plugin, has_update: true, latest_version: '3.14' } }
      : { success: true, message: '迟到成功' });
    await settle();
    assert.equal(notices.length, noticesBeforePluginUnmount, '插件页卸载后不得显示迟到操作通知');
    assert.equal(pluginRequests.length, requestsBeforePluginUnmount, '插件页卸载后不得重新发起刷新请求');
    assert.equal(timers.size, 0, '插件页卸载后必须释放轮询计时器');
    if (kind !== 'check') {
      renderPlugins();
      await settle();
      latestPluginRequest('list').resolve({ items: [plugin] });
      await settle();
      renderPlugins();
    }
  }
  documentSurface.documentElement.dataset = {};
  documentSurface.documentElement.style = { setProperty() {} };
  const { SettingsPage } = await server.ssrLoadModule('/src/features/settings/components/SettingsPage.tsx');
  const { requests: preferenceRequests } = await server.ssrLoadModule(preferencesId);
  const { isReducedMotion } = await server.ssrLoadModule('/src/hooks/useReducedMotion.ts');
  const { getDialogEnterDurationMs } = await server.ssrLoadModule('/src/hooks/useDialogMotionSettings.ts');
  let settingsPage;
  const renderSettings = () => { settingsPage = hooks.render(SettingsPage); };
  const settingsNodes = predicate => nodes(settingsPage, predicate);
  const refreshSettings = () => settingsNodes(node => node.props.actionSlot)[0].props.actionSlot;
  const motionInput = () => settingsNodes(node => node.type === 'input' && node.props.type === 'checkbox')[0];
  const languageMenu = () => settingsNodes(node => node.props.ariaLabel === '界面语言')[0];
  const preferences = {
    reduce_motion: false, locale: 'zh', language_storage_value: 'zh_Hans',
    memory_enabled: true, ai_message_compression_threshold_chars: 10000,
    dialog_animation_settings: { duration_ms: 360 },
    limits: { ai_message_compression_threshold_chars_min: 2000, ai_message_compression_threshold_chars_max: 1000000 },
    language_options: ['zh_Hans', 'en'],
  };
  renderSettings();
  preferenceRequests.at(-1).reject(new Error('初次加载失败'));
  await settle();
  renderSettings();
  assert.equal(refreshSettings().props.disabled, false, '偏好加载失败后必须允许刷新重试');
  const refresh = refreshSettings().props.onClick;
  refresh();
  refresh();
  assert.equal(preferenceRequests.length, 2, '偏好刷新必须阻止同帧重复提交');
  preferenceRequests.at(-1).resolve(preferences);
  await settle();
  renderSettings();
  assert.equal(motionInput().props.checked, false);
  const changeMotion = motionInput().props.onChange;
  const changeLanguage = languageMenu().props.onChange;
  changeMotion({ currentTarget: { checked: true } });
  changeMotion({ currentTarget: { checked: true } });
  changeLanguage('en');
  assert.equal(preferenceRequests.length, 3, '偏好保存必须串行执行，避免不同字段响应互相覆盖');
  renderSettings();
  assert.equal(languageMenu().props.disabled, true, '保存期间必须禁用其他远程偏好输入');
  assert.equal(refreshSettings().props.disabled, true, '保存期间不能并发刷新全量设置');
  preferenceRequests.at(-1).resolve({ ...preferences, reduce_motion: true });
  await settle();
  renderSettings();
  assert.equal(isReducedMotion(), true, '有效保存必须同步全局动效状态');
  assert.equal(motionInput().props.checked, true);
  assert.equal(languageMenu().props.disabled, false, '保存结束后必须恢复其他设置输入');

  for (const operation of ['refresh', 'load', 'save']) {
    if (operation === 'load') renderSettings();
    else if (operation === 'refresh') refreshSettings().props.onClick();
    else {
      renderSettings();
      preferenceRequests.at(-1).resolve({ ...preferences, reduce_motion: true });
      await settle();
      renderSettings();
      motionInput().props.onChange({ currentTarget: { checked: false } });
    }
    const request = preferenceRequests.at(-1);
    const signal = request.args[operation === 'save' ? 1 : 0].signal;
    const noticesBeforeSettingsUnmount = notices.length;
    hooks.unmount();
    assert.equal(signal.aborted, true, '设置页卸载必须中止加载、刷新及保存请求');
    if (operation === 'save') request.reject(new Error('迟到保存失败'));
    else request.resolve({ ...preferences, reduce_motion: false, dialog_animation_settings: { duration_ms: 900 } });
    await settle();
    assert.equal(isReducedMotion(), true, '卸载后的旧设置响应不能覆盖全局动效开关');
    assert.equal(getDialogEnterDurationMs(), 360, '卸载后的旧设置响应不能覆盖弹窗动效时长');
    assert.equal(notices.length, noticesBeforeSettingsUnmount, '卸载后的设置请求不得显示迟到通知');
    assert.equal(timers.size, 0, '设置页卸载必须清除保存反馈计时器');
  }
  const requestsBeforeStaleSettingsClick = preferenceRequests.length;
  changeMotion({ currentTarget: { checked: false } });
  assert.equal(preferenceRequests.length, requestsBeforeStaleSettingsClick, '卸载后的旧设置回调不能重新发送请求');
  console.log('[交互检查] 决策草稿、手势、轮询、浮层退场及文件、插件、设置并发状态检查通过。');
} finally {
  for (const [name, descriptor] of saved) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
  await server.close();
}
