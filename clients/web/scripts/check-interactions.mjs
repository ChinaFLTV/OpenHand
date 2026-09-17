import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

// 只替换 Hook 生命周期和浏览器出口，直接驱动真实交互与轮询逻辑。
const hooksId = '\0交互检查钩子';
const noticesId = '\0交互检查通知';
const server = await createServer({
  configFile: false,
  root: fileURLToPath(new URL('..', import.meta.url)),
  cacheDir: 'node_modules/.vite-interactions-check',
  optimizeDeps: { noDiscovery: true, include: [] },
  server: { middlewareMode: true, watch: null, ws: false },
  appType: 'custom',
  ssr: { noExternal: ['preact'] },
  plugins: [{
    name: '交互检查环境',
    enforce: 'pre',
    resolveId(source) {
      if (source === 'preact/hooks' || source === hooksId) return hooksId;
      if (source.endsWith('/components/Snackbar') || source === noticesId) return noticesId;
    },
    load(id) {
      if (id === noticesId) return 'export const notices = []; export function showSnackbar(message) { notices.push(message); }';
      if (id !== hooksId) return;
      return `
        const slots = [];
        let index = 0;
        let effects = [];
        function changed(previous, next) { return !previous || next.some((value, i) => !Object.is(value, previous[i])); }
        export function useRef(value) { return slots[index++] ??= { current: value }; }
        export function useState(value) {
          const state = useRef(value);
          return [state.current, next => { state.current = typeof next === 'function' ? next(state.current) : next; }];
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
  console.log('[交互检查] 手势与轮询的取消、重入、配置变更、超时及卸载检查通过。');
} finally {
  for (const [name, descriptor] of saved) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
  await server.close();
}
