// Mermaid 流程图渲染组件。
//
// 仅在用户主动切到「视图」时挂载,默认由父组件展示代码文本,降低
// 长 mermaid 块对主线程 / WebView 内存的持续占用;卸载时 dispose
// mermaid 句柄并解除事件 listener,避免残留。
//
// 特性:
// - mermaid.js (npm) async import + 进程级单例 Promise 缓存,
//   同一页面多个 mermaid 块共享一份网络/解析成本。
// - 双指 pinch 放缩 (Pointer Events, 范围 0.25x ~ 8x)
// - 鼠标滚轮 + Ctrl/Cmd 放缩(以光标为锚点)
// - 拖动平移,双击重置
// - mermaid 原生 interaction: true 保留节点点击 / tooltip

import { useEffect, useRef, useState } from 'preact/hooks';

interface MermaidViewProps {
  source: string;
}

type MermaidRenderResult = {
  svg?: unknown;
  bindFunctions?: unknown;
};

let mermaidLoader: Promise<typeof import('mermaid').default> | null = null;
function loadMermaid(): Promise<typeof import('mermaid').default> {
  if (mermaidLoader != null) return mermaidLoader;
  mermaidLoader = import('mermaid').then((mod) => mod.default);
  return mermaidLoader;
}

function extractMermaidSvg(result: unknown): string | null {
  if (typeof result === 'string') return result;
  if (result != null && typeof result === 'object') {
    const renderResult = result as MermaidRenderResult;
    if (typeof renderResult.svg === 'string') {
      return renderResult.svg;
    }
  }
  return null;
}

function formatMermaidError(err: unknown): string {
  if (err instanceof Error && err.message.trim().length > 0) {
    return err.message.trim();
  }
  if (err != null && typeof err === 'object') {
    const record = err as Record<string, unknown>;
    for (const key of ['str', 'message', 'hash']) {
      const value = record[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
    try {
      const serialized = JSON.stringify(record, null, 2);
      if (serialized && serialized !== '{}') return serialized;
    } catch {}
  }
  return String(err);
}

const isDarkTheme = (): boolean => {
  if (typeof document === 'undefined') return false;
  const root = document.documentElement;
  const attr = root.getAttribute('data-theme');
  if (attr === 'dark') return true;
  if (attr === 'light') return false;
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
};

export function MermaidView({ source }: MermaidViewProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (containerRef.current == null) return;
    let disposed = false;
    let panZoomDisposer: (() => void) | null = null;

    setError(null);
    setIsReady(false);

    const renderId = `mermaid-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

    void (async () => {
      try {
        const mermaid = await loadMermaid();
        if (disposed || containerRef.current == null) return;
        mermaid.initialize({
          startOnLoad: false,
          theme: isDarkTheme() ? 'dark' : 'default',
          securityLevel: 'loose',
          flowchart: { useMaxWidth: false, htmlLabels: true, curve: 'basis' },
          sequence: { useMaxWidth: false, showSequenceNumbers: true },
          gantt: { useMaxWidth: false },
          fontSize: 13,
        });
        const result = await mermaid.render(renderId, source);
        if (disposed || containerRef.current == null) return;
        const svg = extractMermaidSvg(result);
        if (svg == null || !svg.includes('<svg')) {
          throw new Error(formatMermaidError(result));
        }
        containerRef.current.innerHTML = svg;
        panZoomDisposer = attachPanZoom(stageRef.current!, containerRef.current!);
        setIsReady(true);
      } catch (err) {
        if (disposed) return;
        setError(formatMermaidError(err));
        setIsReady(true);
      }
    })();

    return () => {
      disposed = true;
      panZoomDisposer?.();
      if (containerRef.current) {
        containerRef.current.innerHTML = '';
      }
    };
  }, [source]);

  return (
    <div class="oh-mermaid-stage" ref={stageRef}>
      <div class="oh-mermaid-inner" ref={containerRef} />
      {!isReady && error == null && (
        <div class="oh-mermaid-loading">渲染中…</div>
      )}
      {error != null && (
        <pre class="oh-mermaid-error">{error}</pre>
      )}
    </div>
  );
}

function attachPanZoom(stage: HTMLElement, inner: HTMLElement): () => void {
  let scale = 1;
  let tx = 0;
  let ty = 0;
  const pointers = new Map<number, { x: number; y: number }>();
  let pinchStartDist = 0;
  let pinchStartScale = 1;
  const apply = (): void => {
    inner.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
  };
  inner.style.transformOrigin = '0 0';
  inner.style.transition = 'transform 80ms ease-out';
  apply();

  const onWheel = (e: WheelEvent): void => {
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault();
    const delta = -e.deltaY * 0.0025;
    const newScale = Math.min(8, Math.max(0.25, scale * (1 + delta)));
    const rect = stage.getBoundingClientRect();
    const cx = e.clientX - rect.left;
    const cy = e.clientY - rect.top;
    tx = cx - (cx - tx) * (newScale / scale);
    ty = cy - (cy - ty) * (newScale / scale);
    scale = newScale;
    apply();
  };

  const onPointerDown = (e: PointerEvent): void => {
    stage.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2) {
      const pts = Array.from(pointers.values());
      pinchStartDist = Math.hypot(pts[0]!.x - pts[1]!.x, pts[0]!.y - pts[1]!.y);
      pinchStartScale = scale;
    } else if (pointers.size === 1) {
      stage.dataset.dragX = String(e.clientX);
      stage.dataset.dragY = String(e.clientY);
      stage.dataset.dragTx = String(tx);
      stage.dataset.dragTy = String(ty);
    }
  };

  const onPointerMove = (e: PointerEvent): void => {
    if (!pointers.has(e.pointerId)) return;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2) {
      const pts = Array.from(pointers.values());
      const dist = Math.hypot(pts[0]!.x - pts[1]!.x, pts[0]!.y - pts[1]!.y);
      if (pinchStartDist > 0) {
        const newScale = Math.min(
          8,
          Math.max(0.25, pinchStartScale * (dist / pinchStartDist)),
        );
        scale = newScale;
        apply();
      }
    } else if (pointers.size === 1 && stage.dataset.dragX) {
      const dx = e.clientX - parseFloat(stage.dataset.dragX ?? '0');
      const dy = e.clientY - parseFloat(stage.dataset.dragY ?? '0');
      tx = parseFloat(stage.dataset.dragTx ?? '0') + dx;
      ty = parseFloat(stage.dataset.dragTy ?? '0') + dy;
      apply();
    }
  };

  const endPointer = (e: PointerEvent): void => {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) pinchStartDist = 0;
    if (pointers.size === 0) {
      delete stage.dataset.dragX;
      delete stage.dataset.dragY;
      delete stage.dataset.dragTx;
      delete stage.dataset.dragTy;
    }
  };

  const onDblClick = (): void => {
    scale = 1;
    tx = 0;
    ty = 0;
    apply();
  };

  stage.addEventListener('wheel', onWheel, { passive: false });
  stage.addEventListener('pointerdown', onPointerDown);
  stage.addEventListener('pointermove', onPointerMove);
  stage.addEventListener('pointerup', endPointer);
  stage.addEventListener('pointercancel', endPointer);
  stage.addEventListener('dblclick', onDblClick);

  return () => {
    stage.removeEventListener('wheel', onWheel);
    stage.removeEventListener('pointerdown', onPointerDown);
    stage.removeEventListener('pointermove', onPointerMove);
    stage.removeEventListener('pointerup', endPointer);
    stage.removeEventListener('pointercancel', endPointer);
    stage.removeEventListener('dblclick', onDblClick);
  };
}
