import { useLayoutEffect, useRef, useState } from 'preact/hooks';
import type { JSX } from 'preact';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { useDialogMotionDurations } from '../hooks/useDialogMotionSettings';
import { useTimeoutController } from '../hooks/useTimeoutController';
import { classNames } from '../shared/util/class_names';

interface AnimatedTitleTextProps {
  text: string;
  className?: string;
  style?: JSX.CSSProperties;
  title?: string;
  animateOnMount?: boolean;
}

export function AnimatedTitleText({
  text, className, style, title, animateOnMount = false,
}: AnimatedTitleTextProps) {
  const reducedMotion = useReducedMotion();
  const { enterMs, exitMs } = useDialogMotionDurations();
  const duration = reducedMotion ? 0 : Math.max(enterMs, exitMs);
  const latest = useRef(text);
  latest.current = text;
  const [frame, setFrame] = useState({
    current: text,
    exiting: animateOnMount ? '' : null as string | null,
    tick: 0,
  });
  const { clearTimer, scheduleTimer } = useTimeoutController();

  useLayoutEffect(() => {
    if (duration === 0) {
      clearTimer();
      setFrame((previous) => previous.current === text && previous.exiting === null
        ? previous : { current: text, exiting: null, tick: previous.tick });
    } else if (frame.exiting === null && text !== frame.current) {
      setFrame({ current: text, exiting: frame.current, tick: frame.tick + 1 });
    }
  }, [text, duration, frame, clearTimer]);

  useLayoutEffect(() => {
    if (frame.exiting === null || duration === 0) return;
    // 完成当前过渡后只取最新标题；即使元素暂时隐藏，也不会残留旧层。
    scheduleTimer(() => setFrame((previous) => latest.current === previous.current
      ? { ...previous, exiting: null }
      : { current: latest.current, exiting: previous.current, tick: previous.tick + 1 }), duration);
    return clearTimer;
  }, [frame, duration, clearTimer, scheduleTimer]);

  const moving = duration > 0 && frame.exiting !== null;
  return (
    <span
      class={classNames('oh-animated-title-text', className)}
      style={{
        ...style,
        '--oh-title-text-enter-duration': `${reducedMotion ? 0 : enterMs}ms`,
        '--oh-title-text-exit-duration': `${reducedMotion ? 0 : exitMs}ms`,
      }}
      title={title}
      aria-label={text.trim() || undefined}
    >
      {moving && frame.exiting ? (
        <span key={`title-exit-${frame.tick}`} class="oh-animated-title-text-exit" aria-hidden="true">
          {frame.exiting}
        </span>
      ) : null}
      <span
        key={`title-current-${frame.tick}`}
        class={classNames('oh-animated-title-text-current', moving && 'oh-animated-title-text-enter')}
        aria-hidden="true"
      >
        {duration === 0 ? text : frame.current}
      </span>
    </span>
  );
}
