import { useEffect, useRef, useState } from 'preact/hooks';
import type { JSX } from 'preact';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { classNames } from '../shared/util/class_names';
import { useTimeoutController } from '../hooks/useTimeoutController';

const TITLE_TEXT_EXIT_MS = 220;

interface AnimatedTitleTextProps {
  text: string;
  className?: string;
  style?: JSX.CSSProperties;
  title?: string;
}

export function AnimatedTitleText({
  text,
  className,
  style,
  title,
}: AnimatedTitleTextProps) {
  const reducedMotion = useReducedMotion();
  const { clearTimer, scheduleTimer } = useTimeoutController();
  const currentRef = useRef(text);
  const [current, setCurrent] = useState(text);
  const [exiting, setExiting] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (reducedMotion) {
      clearTimer();
      currentRef.current = text;
      setCurrent(text);
      setExiting(null);
      return;
    }
    if (text === currentRef.current) return;
    clearTimer();
    const previous = currentRef.current;
    currentRef.current = text;
    setExiting(previous);
    setCurrent(text);
    setTick((value) => value + 1);
    scheduleTimer(() => {
      setExiting(null);
    }, TITLE_TEXT_EXIT_MS);
  }, [clearTimer, text, reducedMotion, scheduleTimer]);

  const rootClass = classNames('oh-animated-title-text', className);
  const label = (reducedMotion ? text : current).trim() || undefined;

  if (reducedMotion) {
    return (
      <span
        class={rootClass}
        style={style}
        title={title}
        aria-label={label}
      >
        {text}
      </span>
    );
  }

  return (
    <span class={rootClass} style={style} title={title} aria-label={label}>
      {exiting !== null ? (
        <span
          key={`title-exit-${tick}`}
          class="oh-animated-title-text-exit"
          aria-hidden="true"
        >
          {exiting}
        </span>
      ) : null}
      <span
        key={`title-current-${tick}`}
        class={exiting === null
          ? 'oh-animated-title-text-current'
          : 'oh-animated-title-text-current oh-animated-title-text-enter'}
        aria-hidden="true"
      >
        {current}
      </span>
    </span>
  );
}
