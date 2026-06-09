// 流式消息文本「Q 弹进场」JS 驱动 diff mask 动画。
//
// CSS `mask-image` 的 `linear-gradient` 过渡在主流浏览器中不可插值，
// 纯 CSS transition 方案实际不生效。此 Hook 用 requestAnimationFrame
// 直接操作 DOM 元素 style，避免 setState 每帧触发全量 re-render，
// 与 Flutter 端 StreamingTextReveal 的 ShaderMask 行为对齐。
//
// 设计：
// - 新字符到达时从旧/新文本边界向尾部扫过弹性波前，配合旧内容垫底
//   让新增 diff 淡入，旧文本保持稳定。
// - reduceMotion 为 true 时跳过动画，直接清空 mask。
// - 动画全程零 state 变更，仅通过 rAF → el.style 直写，避免重渲染。

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'preact/hooks';

const DURATION_MS = 520;
const MAX_SEGMENTS = 24;
const STAGED_REVEAL_MAX_CHARS = 32 * 1024;
const SMALL_BACKLOG_CHARS = 24;
const MEDIUM_BACKLOG_CHARS = 120;
const LARGE_BACKLOG_CHARS = 480;
const MAX_CHARS_PER_FRAME = 24;
const FRAME_BUDGET_MS = 16;
const CATCH_UP_FRAME_BUDGET_MS = 8;

interface FadeSegment {
  boundary: number;
  startedAt: number;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function easeOutBack(t: number): number {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
}

function segmentAlpha(now: number, segment: FadeSegment): number {
  const progress = clamp01((now - segment.startedAt) / DURATION_MS);
  return clamp01(easeOutBack(progress));
}

function buildMask(
  total: number,
  stableLength: number,
  segments: readonly FadeSegment[],
  now: number,
): string {
  const stops: string[] = ['rgba(0,0,0,1) 0%'];
  let previousFraction = clamp01(stableLength / Math.max(1, total));
  let previousAlpha = 1;
  if (previousFraction > 0) {
    stops.push(`rgba(0,0,0,1) ${(previousFraction * 100).toFixed(1)}%`);
  }
  for (const segment of segments) {
    const fraction = clamp01(segment.boundary / Math.max(1, total));
    const alpha = segmentAlpha(now, segment);
    if (fraction <= previousFraction + 0.0001) {
      previousAlpha = alpha;
      continue;
    }
    stops.push(`rgba(0,0,0,${alpha.toFixed(3)}) ${(fraction * 100).toFixed(1)}%`);
    previousFraction = fraction;
    previousAlpha = alpha;
  }
  if (previousFraction < 0.9999) {
    stops.push(`rgba(0,0,0,${previousAlpha.toFixed(3)}) 100%`);
  }
  return `linear-gradient(to bottom, ${stops.join(', ')})`;
}

function applyMask(el: HTMLElement, mask: string) {
  el.style.webkitMaskImage = mask;
  el.style.maskImage = mask;
}

function clearMask(el: HTMLElement) {
  el.style.webkitMaskImage = '';
  el.style.maskImage = '';
}

function codePointEnds(text: string): number[] {
  const ends: number[] = [];
  let offset = 0;
  for (const point of text) {
    offset += point.length;
    ends.push(offset);
  }
  return ends;
}

function stepForBacklog(backlog: number): number {
  if (backlog <= SMALL_BACKLOG_CHARS) return 1;
  if (backlog <= MEDIUM_BACKLOG_CHARS) return 2;
  if (backlog <= LARGE_BACKLOG_CHARS) return 6;
  return MAX_CHARS_PER_FRAME;
}

export function useStreamingStagedText(
  content: string,
  streaming: boolean,
  reduceMotion: boolean,
): {
  visibleContent: string;
  staging: boolean;
} {
  const revealAllowed = content.length <= STAGED_REVEAL_MAX_CHARS;
  const ends = useMemo(() => (
    revealAllowed ? codePointEnds(content) : []
  ), [content, revealAllowed]);
  const targetUnits = ends.length;
  const shouldStage = streaming && !reduceMotion && revealAllowed;
  const [visibleUnits, setVisibleUnits] = useState(() => (
    shouldStage ? 0 : targetUnits
  ));
  const visibleUnitsRef = useRef(visibleUnits);
  const targetUnitsRef = useRef(targetUnits);
  const previousContentRef = useRef(content);
  const rafRef = useRef<number | null>(null);
  const lastFrameRef = useRef(0);

  const stop = useCallback(() => {
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
    lastFrameRef.current = 0;
  }, []);

  const tick = useCallback((now: number) => {
    const backlog = targetUnitsRef.current - visibleUnitsRef.current;
    if (backlog <= 0) {
      stop();
      return;
    }
    const frameBudget = backlog > LARGE_BACKLOG_CHARS
      ? CATCH_UP_FRAME_BUDGET_MS
      : FRAME_BUDGET_MS;
    if (now - lastFrameRef.current >= frameBudget) {
      lastFrameRef.current = now;
      const next = Math.min(
        targetUnitsRef.current,
        visibleUnitsRef.current + stepForBacklog(backlog),
      );
      visibleUnitsRef.current = next;
      setVisibleUnits(next);
    }
    rafRef.current = requestAnimationFrame(tick);
  }, [stop]);

  const start = useCallback(() => {
    if (rafRef.current != null) return;
    lastFrameRef.current = 0;
    rafRef.current = requestAnimationFrame(tick);
  }, [tick]);

  useEffect(() => {
    targetUnitsRef.current = targetUnits;
    if (!shouldStage) {
      stop();
      visibleUnitsRef.current = targetUnits;
      setVisibleUnits(targetUnits);
      previousContentRef.current = content;
      return;
    }

    const previous = previousContentRef.current;
    if (content.length < previous.length) {
      const next = Math.min(visibleUnitsRef.current, targetUnits);
      visibleUnitsRef.current = next;
      setVisibleUnits(next);
    } else if (!content.startsWith(previous)) {
      visibleUnitsRef.current = 0;
      setVisibleUnits(0);
    }
    previousContentRef.current = content;
    if (visibleUnitsRef.current < targetUnits) start();
  }, [content, shouldStage, start, stop, targetUnits]);

  useEffect(() => () => stop(), [stop]);

  const visibleContent = useMemo(() => {
    if (!shouldStage || visibleUnits >= targetUnits) return content;
    if (visibleUnits <= 0) return '';
    return content.slice(0, ends[visibleUnits - 1] ?? 0);
  }, [content, ends, shouldStage, targetUnits, visibleUnits]);

  return {
    visibleContent,
    staging: shouldStage && visibleUnits < targetUnits,
  };
}

/**
 * 流式文本弹性 mask 动画 Hook。
 *
 * 返回 `containerRef`（挂到包裹 Markdown 的 div 上）和 `streamingClass`
 *（是否附加 `.oh-streaming-reveal` CSS class）。动画通过 rAF 直接写 DOM
 * style，不触发 Preact re-render。
 */
export function useStreamingReveal(
  streaming: boolean,
  contentLength: number,
  contentKey: string,
  reduceMotion: boolean,
  onRest?: () => void,
): {
  containerRef: (el: HTMLDivElement | null) => void;
  streamingClass: boolean;
} {
  const elRef = useRef<HTMLDivElement | null>(null);
  const rafRef = useRef<number | null>(null);
  const lastLengthRef = useRef(contentLength);
  const lastContentKeyRef = useRef(contentKey);
  const stableLengthRef = useRef(contentLength);
  const segmentsRef = useRef<FadeSegment[]>([]);
  const onRestRef = useRef(onRest);

  useEffect(() => {
    onRestRef.current = onRest;
  }, [onRest]);

  const containerRef = useCallback((el: HTMLDivElement | null) => {
    elRef.current = el;
  }, []);

  useLayoutEffect(() => {
    const el = elRef.current;
    if (!el) return;

    const stopAnimation = (notify = true) => {
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      segmentsRef.current = [];
      clearMask(el);
      if (notify) onRestRef.current?.();
    };

    const tick = () => {
      const now = performance.now();
      const segments = segmentsRef.current;
      while (segments.length > 0 && now - segments[0]!.startedAt >= DURATION_MS) {
        stableLengthRef.current = segments[0]!.boundary;
        segments.shift();
      }
      if (segments.length === 0) {
        rafRef.current = null;
        clearMask(el);
        onRestRef.current?.();
        return;
      }
      applyMask(el, buildMask(lastLengthRef.current, stableLengthRef.current, segments, now));
      rafRef.current = requestAnimationFrame(tick);
    };

    if (reduceMotion) {
      stopAnimation();
      lastLengthRef.current = contentLength;
      stableLengthRef.current = contentLength;
      lastContentKeyRef.current = contentKey;
      return;
    }

    if (!streaming) {
      stopAnimation();
      lastLengthRef.current = contentLength;
      stableLengthRef.current = contentLength;
      lastContentKeyRef.current = contentKey;
      return;
    }

    if (contentLength > lastLengthRef.current) {
      const previousLength = lastLengthRef.current;
      lastLengthRef.current = contentLength;
      lastContentKeyRef.current = contentKey;
      if (segmentsRef.current.length === 0) {
        stableLengthRef.current = previousLength;
      }
      segmentsRef.current.push({ boundary: contentLength, startedAt: performance.now() });
      while (segmentsRef.current.length > MAX_SEGMENTS) {
        stableLengthRef.current = segmentsRef.current[0]!.boundary;
        segmentsRef.current.shift();
      }
      if (rafRef.current == null) rafRef.current = requestAnimationFrame(tick);
      return;
    }

    if (contentLength < lastLengthRef.current || contentKey !== lastContentKeyRef.current) {
      stopAnimation();
      lastLengthRef.current = contentLength;
      stableLengthRef.current = contentLength;
      lastContentKeyRef.current = contentKey;
      return;
    }
  }, [streaming, contentLength, contentKey, reduceMotion]);

  // 组件卸载时取消 rAF
  useEffect(() => {
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  const streamingClass = !reduceMotion && streaming;

  return { containerRef, streamingClass };
}

/// 稳定态 mask（停流后无障碍模式使用）。
export function getStableMask(): string {
  return 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 100%)';
}
