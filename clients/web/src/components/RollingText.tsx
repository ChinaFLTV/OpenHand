// WEB 端老虎机式字符翻牌：识别字符串中"连续数字 + 千位分隔符"片段，
// 对每个数字位独立做"上滚出 / 下滚入"Q 弹动画；其他字符（"tokens"、
// "字符"、" 项运行时 Notice" 等）保持静态。
//
// 设计动机：与 App 端 `RollingText`（lib/shared/ui/rolling_text.dart）
// 1:1 对齐，让 Web 与桌面端在 Token 胶囊、消息卡字符数等动态数字位
// 的视觉反馈完全一致。
//
// 实现要点：
// - 每个数字位 (`<RollingDigit>`) 维护 `current + previous` 两个 state，
//   char 变化时 setPrevious(current) + setCurrent(new)，通过 CSS
//   keyframes 让旧数字向上滑出 (easeInCubic) + 新数字从下方滑入
//   (easeOutBack, 带轻微 overshoot)，曲线与 App 端一致。
// - 槽位用 `inline-block + position: relative` 固定宽度，避免数字翻
//   牌时整段文本左右抖动。
// - `useReducedMotion()` 命中时直接渲染静态字符，跳过动画。
// - 字符串切分用 LRU 缓存（_segmentText 内部 Map），避免每次 render
//   都重新跑一遍正则。

import { useEffect, useState } from 'preact/hooks';
import type { JSX } from 'preact';
import { useReducedMotion } from '../hooks/useReducedMotion';

interface RollingTextProps {
  text: string;
  className?: string;
  style?: JSX.CSSProperties;
}

interface Segment {
  kind: 'static' | 'digits';
  value: string;
}

const _segmentCache = new Map<string, Segment[]>();

/// 把字符串切成静态段 + 数字段：
/// "17,075 tokens" → [digits "17,075", static " tokens"]
/// "0%"           → [digits "0",   static "%"]
/// "12.3 MB"      → [digits "12.3", static " MB"]   (小数字也认)
function _segmentText(text: string): Segment[] {
  const cached = _segmentCache.get(text);
  if (cached) return cached;
  const out: Segment[] = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i]!;
    if (isDigitChar(ch)) {
      let j = i;
      while (j < text.length && isDigitChar(text[j]!)) j += 1;
      out.push({ kind: 'digits', value: text.slice(i, j) });
      i = j;
    } else {
      let j = i;
      while (j < text.length && !isDigitChar(text[j]!)) j += 1;
      out.push({ kind: 'static', value: text.slice(i, j) });
      i = j;
    }
  }
  if (_segmentCache.size > 256) {
    // LRU: 简单起见直接清空——长会话 token 数字变化频繁，但缓存只
    // 用来跳过同字符串的重复切分，命中率才是关键，容量不是瓶颈。
    _segmentCache.clear();
  }
  _segmentCache.set(text, out);
  return out;
}

function isDigitChar(ch: string): boolean {
  const code = ch.charCodeAt(0);
  // 0-9, ',', '.'
  return (
    (code >= 0x30 && code <= 0x39) ||
    code === 0x2c /* , */ ||
    code === 0x2e /* . */
  );
}

export function RollingText({ text, className, style }: RollingTextProps) {
  const segments = _segmentText(text);
  return (
    <span class={className} style={style}>
      {segments.map((seg, idx) =>
        seg.kind === 'static' ? (
          <span key={idx}>{seg.value}</span>
        ) : (
          <RollingDigitGroup key={idx} value={seg.value} />
        ),
      )}
    </span>
  );
}

function RollingDigitGroup({ value }: { value: string }) {
  return (
    <span class="oh-rolling-digit-group" aria-label={value}>
      {value.split('').map((ch, idx) =>
        ch === ',' || ch === '.' ? (
          <span key={idx} class="oh-rolling-digit-sep">
            {ch}
          </span>
        ) : (
          <RollingDigit key={idx} char={ch} />
        ),
      )}
    </span>
  );
}

function RollingDigit({ char }: { char: string }) {
  const [current, setCurrent] = useState(char);
  const [previous, setPrevious] = useState(char);
  const [tick, setTick] = useState(0);
  const reducedMotion = useReducedMotion();

  useEffect(() => {
    if (char === current) return;
    setPrevious(current);
    setCurrent(char);
    setTick((t) => t + 1);
  }, [char, current]);

  // reduced-motion：直接静态显示当前值，不跑动画。
  if (reducedMotion) {
    return <span class="oh-rolling-digit">{current}</span>;
  }

  const showOld = previous !== current;
  return (
    <span class="oh-rolling-digit">
      {showOld && (
        <span
          key={`old-${tick}`}
          class="oh-rolling-digit-old"
          aria-hidden
        >
          {previous}
        </span>
      )}
      <span
        key={`cur-${tick}`}
        class={showOld ? 'oh-rolling-digit-in' : undefined}
      >
        {current}
      </span>
    </span>
  );
}
