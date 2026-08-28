interface OverlayEscapeLayer {
  canClose: () => boolean;
  requestClose: () => void;
}

let layers: OverlayEscapeLayer[] = [];
let listenerAttached = false;

function handleEscape(event: KeyboardEvent): void {
  if (event.defaultPrevented || event.key !== 'Escape') return;
  const layer = layers[layers.length - 1];
  if (!layer) return;
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation();
  if (layer.canClose()) layer.requestClose();
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

/// 按展示顺序登记浮层；Escape 始终只交给最后登记的活动浮层。
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
