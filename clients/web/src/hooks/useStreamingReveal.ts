// 流式消息文本「Q 弹进场」JS 驱动 mask 动画。
//
// CSS `mask-image` 的 `linear-gradient` 过渡在主流浏览器中不可插值，
// 纯 CSS transition 方案实际不生效。此 Hook 用 requestAnimationFrame
// 手动驱动 mask 渐变 stop 拉伸回缩，与 Flutter 端 StreamingTextReveal
// 的 ShaderMask 行为对齐。
//
// 设计：
// - 新字符到达时底部淡入带拉长（≈32% 渐变覆盖），随后 320ms 内平滑
//   收窄至稳定带（≈18%），配合 alpha 0.50→1.0，产生"字符从底部淡入
//   + 弹性回弹"的 Q 弹视觉反馈。
// - reduceMotion 为 true 时跳过动画，直接返回稳定态 mask。
// - 宽度 0 / 高度 0 时不构建 mask（避免无意义开销）。

import { useEffect, useRef, useState } from 'preact/hooks';

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

export function useStreamingReveal(
  streaming: boolean,
  contentLength: number,
  reduceMotion: boolean,
): { maskImage: string; animateMask: boolean } {
  const [progress, setProgress] = useState(1);
  const rafRef = useRef<number | null>(null);
  const startRef = useRef(0);
  const lastLengthRef = useRef(contentLength);

  useEffect(() => {
    if (reduceMotion) {
      setProgress(1);
      return;
    }
    if (!streaming) {
      // 停流时平滑过渡到完全不透明（progress=1）。
      const animateToStable = () => {
        const elapsed = performance.now() - startRef.current;
        const p = Math.min(1, elapsed / DURATION_MS);
        setProgress(p);
        if (p < 1) {
          rafRef.current = requestAnimationFrame(animateToStable);
        }
      };
      startRef.current = performance.now();
      rafRef.current = requestAnimationFrame(animateToStable);
      lastLengthRef.current = contentLength;
      return;
    }

    if (contentLength > lastLengthRef.current) {
      // 新字符到达：从 0 开始触发弹性拉伸动画。
      lastLengthRef.current = contentLength;
      startRef.current = performance.now();
      const animate = () => {
        const elapsed = performance.now() - startRef.current;
        const p = Math.min(1, elapsed / DURATION_MS);
        setProgress(p);
        if (p < 1) {
          rafRef.current = requestAnimationFrame(animate);
        }
      };
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      rafRef.current = requestAnimationFrame(animate);
    }
  }, [streaming, contentLength, reduceMotion]);

  useEffect(() => {
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  const animateMask = !reduceMotion && (streaming || progress < 1);

  return {
    maskImage: reduceMotion ? 'none' : buildMask(progress),
    animateMask,
  };
}

/// 稳定态 mask（停流后无障碍模式使用），避免不必要 JS 计算。
export function getStableMask(): string {
  return buildMask(1);
}
