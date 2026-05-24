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

import { useCallback, useEffect, useLayoutEffect, useRef } from 'preact/hooks';

const DURATION_MS = 420;

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function easeOutBack(t: number): number {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
}

function buildMask(progress: number, oldFraction: number): string {
  const springT = easeOutBack(progress);
  const alphaT = clamp01(springT);
  const oldStop = clamp01(oldFraction);
  const waveFront = Math.max(
    oldStop,
    clamp01(oldStop + (1 - oldStop) * springT),
  );
  const tailAlpha = 0.28 + 0.72 * alphaT;
  const waveAlpha = 0.58 + 0.42 * alphaT;
  const sOld = (oldStop * 100).toFixed(1);
  const sWave = (waveFront * 100).toFixed(1);
  const aWave = waveAlpha.toFixed(3);
  const aTail = tailAlpha.toFixed(3);
  return (
    `linear-gradient(` +
    `to bottom, ` +
    `rgba(0,0,0,1) 0%, ` +
    `rgba(0,0,0,1) ${sOld}%, ` +
    `rgba(0,0,0,${aWave}) ${sWave}%, ` +
    `rgba(0,0,0,${aTail}) 100%)`
  );
}

function applyMask(el: HTMLElement, mask: string) {
  el.style.webkitMaskImage = mask;
  el.style.maskImage = mask;
}

function clearMask(el: HTMLElement) {
  el.style.webkitMaskImage = '';
  el.style.maskImage = '';
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
  reduceMotion: boolean,
  onRest?: () => void,
): {
  containerRef: (el: HTMLDivElement | null) => void;
  streamingClass: boolean;
} {
  const elRef = useRef<HTMLDivElement | null>(null);
  const rafRef = useRef<number | null>(null);
  const startRef = useRef(0);
  const lastLengthRef = useRef(contentLength);
  const oldFractionRef = useRef(0);
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

    if (reduceMotion) {
      clearMask(el);
      lastLengthRef.current = contentLength;
      onRestRef.current?.();
      return;
    }

    // 取消上一轮未完成的动画（如果有）
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }

    if (!streaming) {
      clearMask(el);
      lastLengthRef.current = contentLength;
      onRestRef.current?.();
      return;
    }

    if (contentLength > lastLengthRef.current) {
      const previousLength = lastLengthRef.current;
      oldFractionRef.current = previousLength > 0 && contentLength > 0
        ? previousLength / contentLength
        : 0;
      lastLengthRef.current = contentLength;
      startRef.current = performance.now();

      const tick = () => {
        const elapsed = performance.now() - startRef.current;
        const p = Math.min(1, elapsed / DURATION_MS);
        applyMask(el, buildMask(p, oldFractionRef.current));
        if (p < 1) {
          rafRef.current = requestAnimationFrame(tick);
        } else {
          rafRef.current = null;
          onRestRef.current?.();
        }
      };
      rafRef.current = requestAnimationFrame(tick);
      return;
    }

    if (contentLength < lastLengthRef.current) {
      clearMask(el);
      lastLengthRef.current = contentLength;
      onRestRef.current?.();
    }
  }, [streaming, contentLength, reduceMotion]);

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
  return buildMask(1, 0);
}
