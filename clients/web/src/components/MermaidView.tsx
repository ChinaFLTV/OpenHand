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

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { saveBlobWithPicker } from '../utils/save_blob';
import { showSnackbar } from './Snackbar';

interface MermaidViewProps {
  source: string;
}

type MermaidViewportSnapshot = {
  scale: number;
  tx: number;
  ty: number;
  contentWidth: number;
  contentHeight: number;
};

type MermaidRenderResult = {
  svg?: unknown;
  bindFunctions?: unknown;
};

function svgMarkupOf(value: unknown): string | null {
  if (typeof value === 'string') return value;
  if (value instanceof SVGElement) return value.outerHTML;
  if (
    value instanceof Element &&
    value.tagName.toLowerCase() === 'svg'
  ) {
    return value.outerHTML;
  }
  return null;
}

let mermaidLoader: Promise<typeof import('mermaid').default> | null = null;
function loadMermaid(): Promise<typeof import('mermaid').default> {
  if (mermaidLoader != null) return mermaidLoader;
  mermaidLoader = import('mermaid').then((mod) => mod.default);
  return mermaidLoader;
}

function extractMermaidSvg(result: unknown): string | null {
  const directMarkup = svgMarkupOf(result);
  if (directMarkup != null) return directMarkup;
  if (result != null && typeof result === 'object') {
    const renderResult = result as MermaidRenderResult;
    return svgMarkupOf(renderResult.svg);
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
  const svgMarkupRef = useRef('');
  const [error, setError] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [zoomPercent, setZoomPercent] = useState(100);
  const [dragActive, setDragActive] = useState(false);
  const controlsLocked = !isReady || error != null;
  const suggestedBasename = useMemo(() => {
    const head = source
      .split(/\r?\n/, 1)[0]
      ?.replace(/[^\p{L}\p{N}_-]+/gu, '_')
      .replace(/^_+|_+$/g, '')
      .slice(0, 32);
    return head && head.length > 0 ? head : 'mermaid_diagram';
  }, [source]);

  async function copySvgMarkup(): Promise<void> {
    const svg = svgMarkupRef.current.trim();
    if (!svg) return;
    try {
      await navigator.clipboard.writeText(svg);
      showSnackbar('SVG 已复制', { tone: 'success' });
    } catch {
      showSnackbar('复制 SVG 失败，请检查浏览器权限', { tone: 'error' });
    }
  }

  async function copySvgImage(): Promise<void> {
    const svg = svgMarkupRef.current.trim();
    if (!svg) return;
    try {
      if ('ClipboardItem' in window && navigator.clipboard?.write) {
        const blob = new Blob([svg], { type: 'image/svg+xml' });
        await navigator.clipboard.write([new ClipboardItem({ 'image/svg+xml': blob })]);
        showSnackbar('图像已复制', { tone: 'success' });
      } else {
        await navigator.clipboard.writeText(svg);
        showSnackbar('浏览器不支持图像复制，已复制 SVG 文本', { tone: 'success' });
      }
    } catch {
      showSnackbar('复制图像失败，请检查浏览器权限', { tone: 'error' });
    }
  }

  async function downloadSvg(): Promise<void> {
    const svg = svgMarkupRef.current.trim();
    if (!svg) return;
    try {
      const blob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' });
      await saveBlobWithPicker(
        blob,
        `${suggestedBasename}.svg`,
        [{ description: 'SVG Image', accept: { 'image/svg+xml': ['.svg'] } }],
      );
      showSnackbar('SVG 已导出', { tone: 'success' });
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') return;
      showSnackbar('导出 SVG 失败', { tone: 'error' });
    }
  }

  function resetView(): void {
    const stage = stageRef.current;
    const inner = containerRef.current;
    if (!stage || !inner) return;
    const controller = stage as typeof stage & { __openhandMermaid?: { reset?: () => void } };
    controller.__openhandMermaid?.reset?.();
  }

  function fitToView(): void {
    const stage = stageRef.current;
    const inner = containerRef.current;
    if (!stage || !inner) return;
    const controller = stage as typeof stage & { __openhandMermaid?: { fit?: () => void } };
    controller.__openhandMermaid?.fit?.();
  }

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
        svgMarkupRef.current = svg;
        containerRef.current.innerHTML = svg;
        panZoomDisposer = attachPanZoom(
          stageRef.current!,
          containerRef.current!,
          {
            onZoomChanged: (value) => setZoomPercent(Math.round(value * 100)),
            onDragStateChanged: setDragActive,
          },
        );
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
      svgMarkupRef.current = '';
      if (containerRef.current) {
        containerRef.current.innerHTML = '';
      }
    };
  }, [source]);

  return (
    <div class="oh-mermaid-shell">
      <div class="oh-mermaid-toolbar">
        <button type="button" class="oh-code-block-copy" onClick={fitToView} disabled={controlsLocked}>适配</button>
        <button type="button" class="oh-code-block-copy" onClick={resetView} disabled={controlsLocked}>重置</button>
        <button type="button" class="oh-code-block-copy" onClick={() => void copySvgMarkup()} disabled={controlsLocked}>复制 SVG</button>
        <button type="button" class="oh-code-block-copy" onClick={() => void copySvgImage()} disabled={controlsLocked}>复制图像</button>
        <button type="button" class="oh-code-block-copy" onClick={() => void downloadSvg()} disabled={controlsLocked}>导出 SVG</button>
        <span class="oh-mermaid-zoom-chip">{zoomPercent}%</span>
      </div>
      <div class={`oh-mermaid-stage ${dragActive ? 'is-dragging' : ''}`} ref={stageRef}>
        <div class="oh-mermaid-inner" ref={containerRef} />
        {!isReady && error == null && (
          <div class="oh-mermaid-loading">渲染中…</div>
        )}
        {error != null && (
          <pre class="oh-mermaid-error">{error}</pre>
        )}
      </div>
    </div>
  );
}

type PanZoomOptions = {
  onZoomChanged?: (scale: number) => void;
  onDragStateChanged?: (active: boolean) => void;
};

function attachPanZoom(stage: HTMLElement, inner: HTMLElement, options: PanZoomOptions = {}): () => void {
  let scale = 1;
  let tx = 0;
  let ty = 0;
  const pointers = new Map<number, { x: number; y: number }>();
  let pinchStartDist = 0;
  let pinchStartScale = 1;
  let longPressTimer: number | null = null;
  let dragReady = false;
  let longPressPointerId: number | null = null;
  const stageController = stage as typeof stage & {
    __openhandMermaid?: {
      reset: () => void;
      fit: () => void;
      getSnapshot: () => MermaidViewportSnapshot;
    };
  };
  const emitDragState = (active: boolean): void => {
    options.onDragStateChanged?.(active);
  };
  const apply = (): void => {
    inner.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
    options.onZoomChanged?.(scale);
  };
  const clearLongPress = (): void => {
    if (longPressTimer != null) {
      window.clearTimeout(longPressTimer);
      longPressTimer = null;
    }
  };
  const reset = (): void => {
    clearLongPress();
    dragReady = false;
    longPressPointerId = null;
    tx = 0;
    ty = 0;
    scale = 1;
    emitDragState(false);
    apply();
  };
  const fit = (): void => {
    clearLongPress();
    dragReady = false;
    longPressPointerId = null;
    const svg = inner.querySelector('svg');
    if (!(svg instanceof SVGGraphicsElement)) {
      reset();
      return;
    }
    const stageRect = stage.getBoundingClientRect();
    const svgBox = svg.getBBox();
    if (svgBox.width <= 0 || svgBox.height <= 0 || stageRect.width <= 0 || stageRect.height <= 0) {
      reset();
      return;
    }
    const padding = 24;
    const fitScale = Math.min(
      8,
      Math.max(
        0.25,
        Math.min(
          (stageRect.width - padding * 2) / svgBox.width,
          (stageRect.height - padding * 2) / svgBox.height,
        ),
      ),
    );
    scale = fitScale;
    tx = padding - svgBox.x * fitScale + Math.max(0, (stageRect.width - svgBox.width * fitScale - padding * 2) / 2);
    ty = padding - svgBox.y * fitScale + Math.max(0, (stageRect.height - svgBox.height * fitScale - padding * 2) / 2);
    emitDragState(false);
    apply();
  };
  stageController.__openhandMermaid = {
    reset,
    fit,
    getSnapshot: () => ({
      scale,
      tx,
      ty,
      contentWidth: inner.scrollWidth,
      contentHeight: inner.scrollHeight,
    }),
  };
  inner.style.transformOrigin = '0 0';
  inner.style.transition = 'transform 80ms ease-out';
  fit();

  const onWheel = (e: WheelEvent): void => {
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault();
    clearLongPress();
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
      clearLongPress();
      dragReady = false;
      emitDragState(false);
      const pts = Array.from(pointers.values());
      pinchStartDist = Math.hypot(pts[0]!.x - pts[1]!.x, pts[0]!.y - pts[1]!.y);
      pinchStartScale = scale;
      return;
    }
    if (pointers.size !== 1) return;
    dragReady = false;
    emitDragState(false);
    longPressPointerId = e.pointerId;
    stage.dataset.dragX = String(e.clientX);
    stage.dataset.dragY = String(e.clientY);
    stage.dataset.dragTx = String(tx);
    stage.dataset.dragTy = String(ty);
    clearLongPress();
    longPressTimer = window.setTimeout(() => {
      if (pointers.size === 1 && longPressPointerId === e.pointerId) {
        dragReady = true;
        emitDragState(true);
      }
    }, 280);
  };

  const onPointerMove = (e: PointerEvent): void => {
    if (!pointers.has(e.pointerId)) return;
    const previous = pointers.get(e.pointerId)!;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2) {
      clearLongPress();
      dragReady = false;
      emitDragState(false);
      const pts = Array.from(pointers.values());
      const dist = Math.hypot(pts[0]!.x - pts[1]!.x, pts[0]!.y - pts[1]!.y);
      if (pinchStartDist > 0) {
        const newScale = Math.min(8, Math.max(0.25, pinchStartScale * (dist / pinchStartDist)));
        scale = newScale;
        apply();
      }
      return;
    }
    if (pointers.size === 1) {
      const moved = Math.hypot(e.clientX - previous.x, e.clientY - previous.y);
      if (!dragReady && moved > 8) {
        clearLongPress();
      }
      if (dragReady && stage.dataset.dragX) {
        const dx = e.clientX - parseFloat(stage.dataset.dragX ?? '0');
        const dy = e.clientY - parseFloat(stage.dataset.dragY ?? '0');
        tx = parseFloat(stage.dataset.dragTx ?? '0') + dx;
        ty = parseFloat(stage.dataset.dragTy ?? '0') + dy;
        apply();
      }
    }
  };

  const endPointer = (e: PointerEvent): void => {
    pointers.delete(e.pointerId);
    clearLongPress();
    if (pointers.size < 2) pinchStartDist = 0;
    if (pointers.size === 0) {
      dragReady = false;
      longPressPointerId = null;
      emitDragState(false);
      delete stage.dataset.dragX;
      delete stage.dataset.dragY;
      delete stage.dataset.dragTx;
      delete stage.dataset.dragTy;
    }
  };

  const onDblClick = (): void => {
    reset();
  };

  stage.addEventListener('wheel', onWheel, { passive: false });
  stage.addEventListener('pointerdown', onPointerDown);
  stage.addEventListener('pointermove', onPointerMove);
  stage.addEventListener('pointerup', endPointer);
  stage.addEventListener('pointercancel', endPointer);
  stage.addEventListener('dblclick', onDblClick);

  return () => {
    clearLongPress();
    emitDragState(false);
    delete stageController.__openhandMermaid;
    stage.removeEventListener('wheel', onWheel);
    stage.removeEventListener('pointerdown', onPointerDown);
    stage.removeEventListener('pointermove', onPointerMove);
    stage.removeEventListener('pointerup', endPointer);
    stage.removeEventListener('pointercancel', endPointer);
    stage.removeEventListener('dblclick', onDblClick);
  };
}
