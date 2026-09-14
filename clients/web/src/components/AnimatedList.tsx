import type { ComponentChildren } from 'preact';
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { useDialogMotionDurations } from '../hooks/useDialogMotionSettings';
import { useReducedMotion } from '../hooks/useReducedMotion';

interface Entry<T> {
  key: string;
  item: T;
  present: boolean;
}

interface AnimatedListProps<T> {
  items: T[];
  itemKey: (item: T) => string;
  renderItem: (item: T) => ComponentChildren;
  empty?: ComponentChildren;
  className?: string;
}

/** 数据立即生效，退场视图按标识保留；快速重新出现时沿原动画反向展开。 */
export function AnimatedList<T>({ items, itemKey, renderItem, empty, className }: AnimatedListProps<T>) {
  const reducedMotion = useReducedMotion();
  const durations = useDialogMotionDurations();
  const enterMs = reducedMotion ? 0 : durations.enterMs;
  const exitMs = reducedMotion ? 0 : durations.exitMs;
  const [entries, setEntries] = useState<Entry<T>[]>(() => items.map((item) => ({
    key: itemKey(item), item, present: true,
  })));
  const timers = useRef(new Map<string, ReturnType<typeof setTimeout>>());
  const root = useRef<HTMLUListElement>(null);
  const positions = useRef(new Map<string, number>());
  const moves = useRef(new Map<string, Animation>());
  const previousExitMs = useRef(exitMs);

  useLayoutEffect(() => {
    const durationChanged = previousExitMs.current !== exitMs;
    previousExitMs.current = exitMs;
    setEntries((previous) => {
      const next = items.map((item) => ({ key: itemKey(item), item, present: true }));
      const keys = new Set(next.map((entry) => entry.key));
      for (const key of keys) {
        clearTimeout(timers.current.get(key));
        timers.current.delete(key);
      }
      if (exitMs > 0) {
        previous.forEach((entry, index) => {
          if (keys.has(entry.key)) return;
          if (durationChanged) {
            clearTimeout(timers.current.get(entry.key));
            timers.current.delete(entry.key);
          }
          next.splice(Math.min(index, next.length), 0, { ...entry, present: false });
        });
      }
      return next;
    });
  }, [items, exitMs]);

  useEffect(() => {
    for (const entry of entries) {
      if (entry.present || timers.current.has(entry.key)) continue;
      timers.current.set(entry.key, setTimeout(() => {
        timers.current.delete(entry.key);
        setEntries((current) => current.filter((row) => row.key !== entry.key || row.present));
      }, exitMs));
    }
    const retained = new Set(entries.map((entry) => entry.key));
    for (const [key, timer] of timers.current) {
      if (retained.has(key)) continue;
      clearTimeout(timer);
      timers.current.delete(key);
    }
  }, [entries, exitMs]);

  useLayoutEffect(() => {
    const rows = Array.from(root.current?.children ?? []) as HTMLElement[];
    const next = new Map<string, number>();
    for (const row of rows) {
      const key = row.dataset.presenceKey!;
      const top = row.offsetTop;
      next.set(key, top);
      const previousTop = positions.current.get(key);
      if (enterMs > 0 && previousTop !== undefined && previousTop !== top) {
        const transform = getComputedStyle(row).transform;
        const remaining = transform === 'none' ? 0 : new DOMMatrixReadOnly(transform).m42;
        moves.current.get(key)?.cancel();
        const move = row.animate([
          { transform: `translateY(${previousTop - top + remaining}px)` },
          { transform: 'translateY(0)' },
        ], { duration: enterMs, easing: 'cubic-bezier(0.22, 1.22, 0.36, 1)' });
        moves.current.set(key, move);
        move.onfinish = () => { moves.current.delete(key); };
      }
    }
    for (const [key, move] of moves.current) {
      if (next.has(key) && enterMs > 0) continue;
      move.cancel();
      moves.current.delete(key);
    }
    positions.current = next;
  }, [entries, enterMs]);

  useLayoutEffect(() => {
    if (!root.current) return;
    // 展开、收起会持续改变布局，重排必须从当前占位开始，不能沿用旧坐标。
    const observer = new ResizeObserver(() => {
      const rows = Array.from(root.current?.children ?? []) as HTMLElement[];
      positions.current = new Map(rows.map((row) => [row.dataset.presenceKey!, row.offsetTop]));
    });
    observer.observe(root.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => () => {
    timers.current.forEach(clearTimeout);
    moves.current.forEach((move) => move.cancel());
    timers.current.clear();
    moves.current.clear();
  }, []);

  return (
    <ul ref={root} class={className} style={{ position: 'relative' }}>
      {entries.map((entry) => (
        <PresenceRow key={entry.key} id={entry.key} present={entry.present} enterMs={enterMs} exitMs={exitMs}>
          {renderItem(entry.item)}
        </PresenceRow>
      ))}
      {empty ? (
        <PresenceRow key="empty" id="empty" present={entries.length === 0} enterMs={enterMs} exitMs={exitMs}>
          {empty}
        </PresenceRow>
      ) : null}
    </ul>
  );
}

function PresenceRow({ id, present, enterMs, exitMs, children }: {
  id: string;
  present: boolean;
  enterMs: number;
  exitMs: number;
  children: ComponentChildren;
}) {
  const [entered, setEntered] = useState(enterMs === 0);
  useLayoutEffect(() => {
    if (enterMs === 0) {
      setEntered(true);
      return;
    }
    let frame = requestAnimationFrame(() => {
      frame = requestAnimationFrame(() => setEntered(true));
    });
    return () => cancelAnimationFrame(frame);
  }, [enterMs]);
  const visible = present && entered;
  return (
    <li
      class="oh-presence-row"
      data-presence-key={id}
      data-visible={visible ? 'true' : 'false'}
      aria-hidden={!present || undefined}
      inert={!present}
      style={{ '--oh-presence-duration': `${present ? enterMs : exitMs}ms` }}
    >
      <div class="oh-presence-clip">
        <div class="oh-presence-content">{children}</div>
      </div>
    </li>
  );
}
