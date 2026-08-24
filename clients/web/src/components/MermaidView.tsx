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
import { copyTextToClipboard, copyBlobToClipboard } from '../utils/clipboard';
import { isAbortError } from '../shared/util/errors';
import { showSnackbar } from './Snackbar';
import { clampNumber, finiteNumberFromText } from '../shared/util/number';
import { strictStringFromUnknown, stringifyJsonSafely } from '../shared/util/value';

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

const MERMAID_VIEW_MIN_SCALE = 0.25;
const MERMAID_VIEW_MAX_SCALE = 8;
const MERMAID_FIT_PADDING_PX = 24;
const MERMAID_INTERACTIVE_TRANSITION_MS = 80;
const MERMAID_TOUCH_DRAG_LONG_PRESS_MS = 280;
const MERMAID_TOUCH_DRAG_CANCEL_DISTANCE_PX = 8;
const MERMAID_WHEEL_ZOOM_SENSITIVITY = 0.0025;

function clampMermaidScale(value: number): number {
  return clampNumber(
    Number.isFinite(value) ? value : 1,
    MERMAID_VIEW_MIN_SCALE,
    MERMAID_VIEW_MAX_SCALE,
  );
}

function mermaidDatasetNumber(value: string | undefined, fallback: number): number {
  const text = strictStringFromUnknown(value);
  if (!text) return fallback;
  return finiteNumberFromText(text) ?? fallback;
}

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
  const errorMessage = strictStringFromUnknown(err instanceof Error ? err.message : null);
  if (errorMessage) return errorMessage;
  if (err != null && typeof err === 'object') {
    const record = err as Record<string, unknown>;
    for (const key of ['str', 'message', 'hash']) {
      const text = strictStringFromUnknown(record[key]);
      if (text) return text;
    }
    const serialized = stringifyJsonSafely(record, 2);
    if (serialized && serialized !== '{}') return serialized;
  }
  return String(err);
}

async function renderPngBlobFromSvg(
  svg: string,
  options: { background?: string; scale?: number } = {},
): Promise<Blob> {
  const scale = options.scale ?? 2;
  if (typeof document === 'undefined') {
    throw new Error('png_conversion_requires_browser');
  }
  if (typeof Image === 'undefined' || typeof HTMLCanvasElement === 'undefined') {
    throw new Error('png_conversion_unsupported_in_this_runtime');
  }
  // 1. 规范化 SVG：补 xmlns / width / height，避免 Mermaid 输出偶发缺属性
  //    导致 Image.naturalWidth/Height = 0 而画到 1x1 canvas 上。
  const parser = new DOMParser();
  const parsed = parser.parseFromString(svg, 'image/svg+xml');
  const parserError = parsed.querySelector('parsererror');
  if (parserError) {
    throw new Error('svg_parse_failed');
  }
  const svgElement = parsed.documentElement;
  if (svgElement == null || svgElement.tagName.toLowerCase() !== 'svg') {
    throw new Error('svg_root_missing');
  }
  if (!svgElement.getAttribute('xmlns')) {
    svgElement.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  }
  if (!svgElement.getAttribute('xmlns:xlink')) {
    svgElement.setAttribute('xmlns:xlink', 'http://www.w3.org/1999/xlink');
  }
  const viewBox = (svgElement.getAttribute('viewBox') ?? '').split(/[\s,]+/).map(Number);
  const fallbackWidth = Number.isFinite(viewBox[2]) && viewBox[2]! > 0 ? viewBox[2]! : 800;
  const fallbackHeight = Number.isFinite(viewBox[3]) && viewBox[3]! > 0 ? viewBox[3]! : 600;
  const widthAttr = parseFloat(svgElement.getAttribute('width') ?? '');
  const heightAttr = parseFloat(svgElement.getAttribute('height') ?? '');
  const intrinsicWidth = Number.isFinite(widthAttr) && widthAttr > 0 ? widthAttr : fallbackWidth;
  const intrinsicHeight = Number.isFinite(heightAttr) && heightAttr > 0 ? heightAttr : fallbackHeight;
  svgElement.setAttribute('width', String(intrinsicWidth));
  svgElement.setAttribute('height', String(intrinsicHeight));
  const serialized = new XMLSerializer().serializeToString(svgElement);

  // 2. data URL 而非 Blob URL：避免 Chromium 把 Blob URL 视作跨源，
  //    drawImage 之后 canvas 被污染，canvas.toBlob 抛 SecurityError。
  const base64 = (() => {
    try {
      return btoa(unescape(encodeURIComponent(serialized)));
    } catch {
      // 极端退路：直接用 unencoded data URL（部分旧浏览器会兜底解析）。
      return null;
    }
  })();
  const dataUrl = base64 != null
    ? `data:image/svg+xml;base64,${base64}`
    : `data:image/svg+xml;charset=utf-8,${encodeURIComponent(serialized)}`;

  // 3. 加载图片：Mermaid 自带 webfont (Inter / 其它) 在 Image 内不会等待，
  //    必须 await document.fonts.ready 后再 drawImage，否则导出图会出现
  //    “画好但文字没填上”的半成品。
  const image = new Image();
  image.decoding = 'async';
  const loaded = await new Promise<HTMLImageElement>((resolve, reject) => {
    const cleanup = () => {
      image.onload = null;
      image.onerror = null;
    };
    image.onload = () => {
      cleanup();
      resolve(image);
    };
    image.onerror = () => {
      cleanup();
      reject(new Error('failed_to_load_svg_image'));
    };
    image.src = dataUrl;
  });

  const fontsReady = (document as Document & { fonts?: { ready?: Promise<unknown> } }).fonts?.ready;
  if (fontsReady) {
    try {
      await fontsReady;
    } catch {
      // 字体加载失败不阻塞 PNG 导出，走默认字体回退。
    }
  }

  // 4. 画到高分辨率 canvas（默认 2x 让导出的 PNG 在视网膜屏不糊）。
  const targetWidth = Math.max(1, Math.round(intrinsicWidth * scale));
  const targetHeight = Math.max(1, Math.round(intrinsicHeight * scale));
  const canvas = document.createElement('canvas');
  canvas.width = targetWidth;
  canvas.height = targetHeight;
  const ctx = canvas.getContext('2d');
  if (ctx == null) {
    throw new Error('missing_canvas_context');
  }
  if (options.background) {
    ctx.fillStyle = options.background;
    ctx.fillRect(0, 0, targetWidth, targetHeight);
  }
  ctx.drawImage(loaded, 0, 0, targetWidth, targetHeight);

  // 5. toBlob 在高 canvas 上偶尔会回传 null（OOM / 驱动不支持），
  //    退路走 toDataURL + fetch 重建 blob。
  const pngBlob = await new Promise<Blob | null>((resolve) => {
    canvas.toBlob((blob) => resolve(blob), 'image/png');
  });
  if (pngBlob != null) return pngBlob;
  const dataUrlFallback = canvas.toDataURL('image/png');
  const match = /^data:image\/png;base64,(.+)$/.exec(dataUrlFallback);
  if (match == null) {
    throw new Error('failed_to_encode_png');
  }
  const binary = atob(match[1]!);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new Blob([bytes], { type: 'image/png' });
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
    if (!svg) {
      return;
    }
    // 关键：用户期望"粘贴成图片"（贴到图形编辑器直接看到图像），
    // 因此优先以 image/svg+xml Blob 写入剪贴板；写不进再降级纯文本。
    const svgBlob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' });
    let ok = await copyBlobToClipboard(svgBlob);
    if (!ok) {
      const textOk = await copyTextToClipboard(svg);
      ok = textOk;
    }
    showSnackbar(
      ok ? 'SVG 已复制（可粘贴到图形编辑器）' : '复制 SVG 失败，请检查浏览器权限',
      { tone: ok ? 'success' : 'error' },
    );
  }

  async function copySvgImage(): Promise<void> {
    const svg = svgMarkupRef.current.trim();
    if (!svg) {
      return;
    }
    try {
      const png = await renderPngBlobFromSvg(svg, { scale: 2 });
      const ok = await copyBlobToClipboard(png);
      if (ok) {
        showSnackbar('图像已复制', { tone: 'success' });
        return;
      }
      // 旧浏览器/无 image/png 写入权限 → 退而写 SVG blob，再退到 SVG 文本。
      const svgBlob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' });
      const svgOk = await copyBlobToClipboard(svgBlob);
      if (svgOk) {
        showSnackbar('当前浏览器不支持图像复制，已复制 SVG 图像', { tone: 'success' });
        return;
      }
      const textOk = await copyTextToClipboard(svg);
      showSnackbar(
        textOk ? '当前浏览器不支持图像复制，已复制 SVG 文本' : '复制图像失败，请检查浏览器权限',
        { tone: textOk ? 'success' : 'error' },
      );
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
      if (isAbortError(err)) return;
      showSnackbar('导出 SVG 失败', { tone: 'error' });
    }
  }

  async function downloadPng(): Promise<void> {
    const svg = svgMarkupRef.current.trim();
    if (!svg) return;
    try {
      const blob = await renderPngBlobFromSvg(svg, { scale: 2 });
      await saveBlobWithPicker(
        blob,
        `${suggestedBasename}.png`,
        [{ description: 'PNG Image', accept: { 'image/png': ['.png'] } }],
      );
      showSnackbar('PNG 已导出', { tone: 'success' });
    } catch (err) {
      if (isAbortError(err)) return;
      const message = err instanceof Error ? err.message : String(err);
      showSnackbar(`导出 PNG 失败 (${message})`, { tone: 'error' });
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
          securityLevel: 'strict',
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
        <button type="button" class="oh-code-block-copy" onClick={() => void downloadPng()} disabled={controlsLocked}>导出 PNG</button>
        <button type="button" class="oh-code-block-copy oh-mermaid-zoom-chip" onClick={resetView} disabled={controlsLocked}>{zoomPercent}%</button>
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
  let manualViewport = false;
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
  const setInteractiveTransition = (enabled: boolean): void => {
    inner.style.transition = enabled
      ? `transform ${MERMAID_INTERACTIVE_TRANSITION_MS}ms ease-out`
      : 'none';
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
    manualViewport = true;
    emitDragState(false);
    apply();
  };
  const fit = (): void => {
    setInteractiveTransition(true);
    clearLongPress();
    dragReady = false;
    longPressPointerId = null;
    manualViewport = false;
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
    const fitScale = clampMermaidScale(
      Math.min(
        (stageRect.width - MERMAID_FIT_PADDING_PX * 2) / svgBox.width,
        (stageRect.height - MERMAID_FIT_PADDING_PX * 2) / svgBox.height,
      ),
    );
    scale = fitScale;
    tx = MERMAID_FIT_PADDING_PX - svgBox.x * fitScale +
      Math.max(0, (stageRect.width - svgBox.width * fitScale - MERMAID_FIT_PADDING_PX * 2) / 2);
    ty = MERMAID_FIT_PADDING_PX - svgBox.y * fitScale +
      Math.max(0, (stageRect.height - svgBox.height * fitScale - MERMAID_FIT_PADDING_PX * 2) / 2);
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
  setInteractiveTransition(true);
  fit();

  const onWheel = (e: WheelEvent): void => {
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault();
    clearLongPress();
    setInteractiveTransition(false);
    const delta = -e.deltaY * MERMAID_WHEEL_ZOOM_SENSITIVITY;
    const newScale = clampMermaidScale(scale * (1 + delta));
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
      setInteractiveTransition(false);
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
    if (e.pointerType === 'mouse') {
      dragReady = true;
      emitDragState(true);
      setInteractiveTransition(false);
      return;
    }
    longPressTimer = window.setTimeout(() => {
      if (pointers.size === 1 && longPressPointerId === e.pointerId) {
        dragReady = true;
        emitDragState(true);
        setInteractiveTransition(false);
      }
    }, MERMAID_TOUCH_DRAG_LONG_PRESS_MS);
  };

  const onPointerMove = (e: PointerEvent): void => {
    if (!pointers.has(e.pointerId)) return;
    const previous = pointers.get(e.pointerId)!;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2) {
      clearLongPress();
      dragReady = false;
      emitDragState(false);
      setInteractiveTransition(false);
      const pts = Array.from(pointers.values());
      const dist = Math.hypot(pts[0]!.x - pts[1]!.x, pts[0]!.y - pts[1]!.y);
      if (pinchStartDist > 0) {
        const rect = stage.getBoundingClientRect();
        const centerX = (pts[0]!.x + pts[1]!.x) / 2 - rect.left;
        const centerY = (pts[0]!.y + pts[1]!.y) / 2 - rect.top;
        const newScale = clampMermaidScale(pinchStartScale * (dist / pinchStartDist));
        tx = centerX - (centerX - tx) * (newScale / scale);
        ty = centerY - (centerY - ty) * (newScale / scale);
        scale = newScale;
        manualViewport = true;
        apply();
      }
      return;
    }
    if (pointers.size === 1) {
      const moved = Math.hypot(e.clientX - previous.x, e.clientY - previous.y);
      if (!dragReady && moved > MERMAID_TOUCH_DRAG_CANCEL_DISTANCE_PX) {
        clearLongPress();
      }
      if (dragReady && stage.dataset.dragX) {
        const dragX = mermaidDatasetNumber(stage.dataset.dragX, e.clientX);
        const dragY = mermaidDatasetNumber(stage.dataset.dragY, e.clientY);
        const dragTx = mermaidDatasetNumber(stage.dataset.dragTx, tx);
        const dragTy = mermaidDatasetNumber(stage.dataset.dragTy, ty);
        tx = dragTx + e.clientX - dragX;
        ty = dragTy + e.clientY - dragY;
        manualViewport = true;
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
      setInteractiveTransition(true);
      delete stage.dataset.dragX;
      delete stage.dataset.dragY;
      delete stage.dataset.dragTx;
      delete stage.dataset.dragTy;
    }
  };

  const onDblClick = (): void => {
    reset();
  };

  const resizeObserver = typeof ResizeObserver !== 'undefined'
    ? new ResizeObserver(() => {
        if (!manualViewport) {
          fit();
        }
      })
    : null;
  resizeObserver?.observe(stage);

  stage.addEventListener('wheel', onWheel, { passive: false });
  stage.addEventListener('pointerdown', onPointerDown);
  stage.addEventListener('pointermove', onPointerMove);
  stage.addEventListener('pointerup', endPointer);
  stage.addEventListener('pointercancel', endPointer);
  stage.addEventListener('dblclick', onDblClick);

  return () => {
    clearLongPress();
    emitDragState(false);
    resizeObserver?.disconnect();
    delete stageController.__openhandMermaid;
    stage.removeEventListener('wheel', onWheel);
    stage.removeEventListener('pointerdown', onPointerDown);
    stage.removeEventListener('pointermove', onPointerMove);
    stage.removeEventListener('pointerup', endPointer);
    stage.removeEventListener('pointercancel', endPointer);
    stage.removeEventListener('dblclick', onDblClick);
  };
}
