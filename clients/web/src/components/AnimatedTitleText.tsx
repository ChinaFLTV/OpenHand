import { useEffect, useRef, useState } from 'preact/hooks';
import type { JSX } from 'preact';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { classNames } from '../shared/util/class_names';

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
  const currentRef = useRef(text);
  const [current, setCurrent] = useState(text);
  const [exiting, setExiting] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (reducedMotion) {
      currentRef.current = text;
      setCurrent(text);
      setExiting(null);
      return;
    }
    if (text === currentRef.current) return;
    const previous = currentRef.current;
    currentRef.current = text;
    setExiting(previous);
    setCurrent(text);
    setTick((value) => value + 1);
  }, [text, reducedMotion]);

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
        onAnimationEnd={(event) => {
          if (event.animationName === 'oh-title-text-enter') {
            setExiting(null);
          }
        }}
      >
        {current}
      </span>
    </span>
  );
}
