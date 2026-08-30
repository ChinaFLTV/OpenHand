interface OverlayEscapeLayer {
  canClose: () => boolean;
  requestClose: () => void;
}

let layers: OverlayEscapeLayer[] = [];
let listenerAttached = false;

function isEscapeEvent(event: KeyboardEvent): boolean {
  return event.key === 'Escape'
    || event.key === 'Esc'
    || event.code === 'Escape';
}

function handleEscape(event: KeyboardEvent): void {
  if (!isEscapeEvent(event)) return;
  const target = layers[layers.length - 1];
  if (!target) return;
  // 捕获阶段先钉住当前顶层。输入框 preventDefault 不再误伤弹窗关闭；
  // 若冒泡阶段已有登记浮层自行关闭，微任务发现目标已不在栈顶则不再关外层。
  event.preventDefault();
  queueMicrotask(() => {
    if (layers[layers.length - 1] !== target) return;
    if (!layers.includes(target)) return;
    if (target.canClose()) target.requestClose();
  });
}

function attachListener(): void {
  if (listenerAttached || typeof window === 'undefined') return;
  window.addEventListener('keydown', handleEscape, true);
  listenerAttached = true;
}

function detachListenerIfIdle(): void {
  if (!listenerAttached || layers.length > 0 || typeof window === 'undefined') {
    return;
  }
  window.removeEventListener('keydown', handleEscape, true);
  listenerAttached = false;
}

/// 按展示顺序登记浮层；Escape 始终只交给登记时的最顶层。
export function registerOverlayEscapeLayer(
  layer: OverlayEscapeLayer,
): () => void {
  layers.push(layer);
  attachListener();
  let registered = true;
  return () => {
    if (!registered) return;
    registered = false;
    layers = layers.filter((item) => item !== layer);
    detachListenerIfIdle();
  };
}
