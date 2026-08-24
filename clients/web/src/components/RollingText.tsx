// WEB 端数字滚轮：与 App 端 RollingText 1:1。
// 只翻连续数字位；槽位右对齐；变大向上、变小向下；个位先动。
// 进场：滑入 → 过冲 → 回落；退场走 emphasized。过冲窗口不被裁切。

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

const DIGIT_ROLL_DURATION_MS = 360;
const DIGIT_ROLL_STAGGER_MS = 28;
const DIGIT_ROLL_STAGGER_MAX_SLOTS = 5;

const _segmentCache = new Map<string, Segment[]>();

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
  if (_segmentCache.size > 256) _segmentCache.clear();
  _segmentCache.set(text, out);
  return out;
}

function isDigitChar(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return (
    (code >= 0x30 && code <= 0x39) ||
    code === 0x2c ||
    code === 0x2e
  );
}

function isSeparator(ch: string): boolean {
  return ch === ',' || ch === '.';
}

function charFromRight(value: string, fromRight: number): string {
  const index = value.length - 1 - fromRight;
  if (index < 0 || index >= value.length) return '';
  return value[index]!;
}

function digitRollDirection(from: string, to: string): 1 | -1 {
  const a = Number(from.replace(/,/g, ''));
  const b = Number(to.replace(/,/g, ''));
  if (!Number.isFinite(a) || !Number.isFinite(b) || b === a) return 1;
  return b > a ? 1 : -1;
}

function changingMaxFromRight(from: string, to: string): number {
  const slotCount = Math.max(from.length, to.length);
  let maxFromRight = 0;
  for (let fromRight = 0; fromRight < slotCount; fromRight += 1) {
    if (charFromRight(from, fromRight) !== charFromRight(to, fromRight)) {
      maxFromRight = fromRight;
    }
  }
  return maxFromRight;
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
  const [current, setCurrent] = useState(value);
  const [previous, setPrevious] = useState(value);
  const [tick, setTick] = useState(0);
  const [direction, setDirection] = useState<1 | -1>(1);
  const reducedMotion = useReducedMotion();

  useEffect(() => {
    if (value === current) return;
    if (reducedMotion) {
      setPrevious(value);
      setCurrent(value);
      return;
    }
    setPrevious(current);
    setCurrent(value);
    setDirection(digitRollDirection(current, value));
    setTick((t) => t + 1);
  }, [value, current, reducedMotion]);

  useEffect(() => {
    if (reducedMotion || previous === current) return;
    const extra = Math.min(
      changingMaxFromRight(previous, current),
      DIGIT_ROLL_STAGGER_MAX_SLOTS,
    );
    const id = window.setTimeout(() => {
      setPrevious(current);
    }, DIGIT_ROLL_DURATION_MS + DIGIT_ROLL_STAGGER_MS * extra);
    return () => window.clearTimeout(id);
  }, [previous, current, tick, reducedMotion]);

  const slotCount = Math.max(previous.length, current.length);
  const slots: JSX.Element[] = [];
  for (let fromRight = slotCount - 1; fromRight >= 0; fromRight -= 1) {
    slots.push(
      <RollingDigit
        key={`r${fromRight}`}
        previous={charFromRight(previous, fromRight)}
        current={charFromRight(current, fromRight)}
        direction={direction}
        tick={tick}
        delayMs={
          Math.min(fromRight, DIGIT_ROLL_STAGGER_MAX_SLOTS) *
          DIGIT_ROLL_STAGGER_MS
        }
        reducedMotion={reducedMotion}
      />,
    );
  }

  return (
    <span class="oh-rolling-digit-group" aria-label={current}>
      {slots}
    </span>
  );
}

function RollingDigit({
  previous,
  current,
  direction,
  tick,
  delayMs,
  reducedMotion,
}: {
  previous: string;
  current: string;
  direction: 1 | -1;
  tick: number;
  delayMs: number;
  reducedMotion: boolean;
}) {
  const display = current || previous;
  if (!display) return null;

  const same = previous === current;
  const sep = isSeparator(previous) || isSeparator(current);
  if (reducedMotion || same) {
    return (
      <span class={sep ? 'oh-rolling-digit-sep' : 'oh-rolling-digit'}>
        {display}
      </span>
    );
  }

  const dir = direction > 0 ? 'up' : 'down';
  const delay = { animationDelay: `${delayMs}ms` };
  const fadeOnly = sep;
  return (
    <span class="oh-rolling-digit">
      {previous ? (
        <span
          key={`old-${tick}`}
          class={
            fadeOnly
              ? 'oh-rolling-digit-old oh-rolling-digit-fade-out'
              : `oh-rolling-digit-old oh-rolling-digit-out-${dir}`
          }
          style={delay}
          aria-hidden
        >
          {previous}
        </span>
      ) : null}
      {current ? (
        <span
          key={`cur-${tick}`}
          class={
            fadeOnly
              ? 'oh-rolling-digit-in oh-rolling-digit-fade-in'
              : `oh-rolling-digit-in oh-rolling-digit-in-${dir}`
          }
          style={delay}
        >
          {current}
        </span>
      ) : (
        <span class="oh-rolling-digit-spacer" aria-hidden>
          0
        </span>
      )}
    </span>
  );
}
