// 流式消息文本「Q 弹进场」JS 驱动 mask 动画。
//
// CSS `mask-image` 的 `linear-gradient` 过渡在主流浏览器中不可插值，
// 纯 CSS transition 方案实际不生效。此 Hook 用 requestAnimationFrame
// 直接操作 DOM 元素 style，避免 setState 每帧触发全量 re-render，
// 与 Flutter 端 StreamingTextReveal 的 ShaderMask 行为对齐。
//
// 设计：
// - 新字符到达时底部淡入带拉长（≈32% 渐变覆盖），随后 320ms 内平滑
//   收窄至稳定带（≈18%），配合 alpha 0.50→1.0。
// - reduceMotion 为 true 时跳过动画，直接清空 mask。
// - 动画全程零 state 变更，仅通过 rAF → el.style 直写，避免重渲染。

import { useCallback, useEffect, useRef } from 'preact/hooks';

const DURATION_MS = 320;

const STABLE_STOP2 = 0.82;
const STABLE_STOP3 = 0.94;

const TRIGGER_STOP2 = 0.68;
const TRIGGER_STOP3 = 0.84;

function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

function buildMask(progress: number): string {
  const t = easeOutCubic(progress);
  const stop2 = TRIGGER_STOP2 + (STABLE_STOP2 - TRIGGER_STOP2) * t;
  const stop3 = TRIGGER_STOP3 + (STABLE_STOP3 - TRIGGER_STOP3) * t;
  const tailAlpha = 0.50 + 0.50 * t;
  const tailHeadAlpha = 0.78 + 0.22 * t;
  const s2 = (stop2 * 100).toFixed(1);
  const s3 = (stop3 * 100).toFixed(1);
  const a3 = tailHeadAlpha.toFixed(3);
  const a4 = tailAlpha.toFixed(3);
  return (
    `linear-gradient(` +
    `to bottom, ` +
    `rgba(0,0,0,1) 0%, ` +
    `rgba(0,0,0,1) ${s2}%, ` +
    `rgba(0,0,0,${a3}) ${s3}%, ` +
    `rgba(0,0,0,${a4}) 100%)`
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
): {
  containerRef: (el: HTMLDivElement | null) => void;
  streamingClass: boolean;
} {
  const elRef = useRef<HTMLDivElement | null>(null);
  const rafRef = useRef<number | null>(null);
  const startRef = useRef(0);
  const lastLengthRef = useRef(contentLength);

  const containerRef = useCallback((el: HTMLDivElement | null) => {
    elRef.current = el;
  }, []);

  useEffect(() => {
    const el = elRef.current;
    if (!el) return;

    if (reduceMotion) {
      clearMask(el);
      lastLengthRef.current = contentLength;
      return;
    }

    // 取消上一轮未完成的动画（如果有）
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }

    if (!streaming) {
      // 停流：从当前 mask 平滑过渡到无 mask（全不透明）。
      // 我们不知道"当前"进度，所以简单设 stable mask 然后在一帧后
      // 清除 — 实际已经全不透明时 clear 就是 no-op。
      applyMask(el, buildMask(1));
      const clearTimer = setTimeout(() => clearMask(el), 16);
      lastLengthRef.current = contentLength;
      return () => clearTimeout(clearTimer);
    }

    if (contentLength > lastLengthRef.current) {
      lastLengthRef.current = contentLength;
      startRef.current = performance.now();

      const tick = () => {
        const elapsed = performance.now() - startRef.current;
        const p = Math.min(1, elapsed / DURATION_MS);
        applyMask(el, buildMask(p));
        if (p < 1) {
          rafRef.current = requestAnimationFrame(tick);
        } else {
          rafRef.current = null;
        }
      };
      rafRef.current = requestAnimationFrame(tick);
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
  return buildMask(1);
}
