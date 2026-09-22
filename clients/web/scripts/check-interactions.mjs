import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import preact from '@preact/preset-vite';

// 只替换 Hook 生命周期和浏览器出口，直接驱动真实交互与轮询逻辑。
const hooksId = '\0交互检查钩子';
const locationId = '\0交互检查路由';
const noticesId = '\0交互检查通知';
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
    },
    load(id) {
      if (id === locationId) return 'export const routes = []; export function useLocation() { return { route: (...args) => routes.push(args) }; }';
      if (id === noticesId) return 'export const notices = []; export function showSnackbar(message) { notices.push(message); }';
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
  assert.equal(timers.size, 1, '旧任务结束后只恢复一个轮询计时器');
  await tick(750);
  assert.equal(runs.length, 2, '旧任务结束后必须按最新配置恢复轮询');
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
  await tick(900);
  assert.equal(runs.length, 3);
  hooks.unmount();
  runs[2].resolve();
  await settle();
  assert.equal(timers.size, 0, '卸载必须清除计时器且阻止迟到任务重新调度');
  renderPoll();
  hooks.unmount();
  await settle();
  assert.equal(runs.length, 3, '开始前卸载不得启动底层轮询任务');
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
  console.log('[交互检查] 决策草稿、手势、轮询及浮层退场生命周期检查通过。');
} finally {
  for (const [name, descriptor] of saved) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
  await server.close();
}
