import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { useReducedMotion } from '../hooks/useReducedMotion';
import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';
import { OverlayPortal } from './OverlayPortal';

export type SnackbarTone = 'default' | 'success' | 'warning' | 'error';

export interface SnackbarOptions {
  tone?: SnackbarTone;
  durationMs?: number;
}

interface SnackbarItem {
  id: number;
  message: string;
  tone: SnackbarTone;
  durationMs: number;
  closing?: boolean;
}

const listeners = new Set<(item: SnackbarItem) => void>();
let nextId = 1;
const MAX_VISIBLE_SNACKBAR_ITEMS = 3;
const DEFAULT_SNACKBAR_DURATION_MS = 2600;
const MAX_SNACKBAR_DURATION_MS = 60_000;
const SNACKBAR_EXIT_DURATION_MS = 180;

function normalizeSnackbarDurationMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: DEFAULT_SNACKBAR_DURATION_MS,
    max: MAX_SNACKBAR_DURATION_MS,
  });
}

export function showSnackbar(message: string, options: SnackbarOptions = {}): void {
  const trimmed = message.trim();
  if (!trimmed) return;
  const item: SnackbarItem = {
    id: nextId++,
    message: trimmed,
    tone: options.tone ?? 'default',
    durationMs: normalizeSnackbarDurationMs(options.durationMs),
  };
  for (const listener of listeners) listener(item);
}

function toneStyle(tone: SnackbarTone) {
  switch (tone) {
    case 'success':
      return {
        border: '1px solid var(--m3-outline-variant, rgba(127,127,127,0.3))',
        color: 'var(--m3-inverse-on-surface, #f1f0f4)',
        background: 'var(--m3-inverse-surface, #2f3033)',
      };
    case 'warning':
      return {
        border: '1px solid var(--m3-outline-variant, rgba(127,127,127,0.3))',
        color: 'var(--m3-on-tertiary-container, #28132e)',
        background: 'var(--m3-tertiary-container, #fad8fd)',
      };
    case 'error':
      return {
        border: '1px solid var(--m3-outline-variant, rgba(127,127,127,0.3))',
        color: 'var(--m3-on-error-container, #410e0b)',
        background: 'var(--m3-error-container, #f9dedc)',
      };
    default:
      return {
        border: '1px solid var(--m3-outline-variant, rgba(127,127,127,0.3))',
        color: 'var(--m3-inverse-on-surface, #f1f0f4)',
        background: 'var(--m3-inverse-surface, #2f3033)',
      };
  }
}

export function SnackbarHost() {
  const [items, setItems] = useState<SnackbarItem[]>([]);
  const reduceMotion = useReducedMotion();
  const timerRefs = useRef<Set<number>>(new Set());

  const clearManagedTimeout = useCallback((timer: number) => {
    if (typeof window !== 'undefined') {
      window.clearTimeout(timer);
    }
    timerRefs.current.delete(timer);
  }, []);

  const setManagedTimeout = useCallback((callback: () => void, delayMs: number) => {
    if (typeof window === 'undefined') return null;
    const timer = window.setTimeout(() => {
      timerRefs.current.delete(timer);
      callback();
    }, normalizeDurationMs(delayMs, {
      fallback: 0,
      max: MAX_BROWSER_TIMEOUT_MS,
    }));
    timerRefs.current.add(timer);
    return timer;
  }, []);

  const dismissItem = useCallback((item: SnackbarItem) => {
    if (reduceMotion) {
      setItems((prev) => prev.filter((cur) => cur.id !== item.id));
      return;
    }
    setItems((prev) => prev.map((cur) => (
      cur.id === item.id ? { ...cur, closing: true } : cur
    )));
    setManagedTimeout(() => {
      setItems((prev) => prev.filter((cur) => cur.id !== item.id));
    }, SNACKBAR_EXIT_DURATION_MS);
  }, [reduceMotion, setManagedTimeout]);

  useEffect(() => {
    const onItem = (item: SnackbarItem) => {
      setItems((prev) => [
        ...prev.slice(-(MAX_VISIBLE_SNACKBAR_ITEMS - 1)),
        item,
      ]);
      setManagedTimeout(() => dismissItem(item), item.durationMs);
    };
    listeners.add(onItem);
    return () => {
      listeners.delete(onItem);
    };
  }, [dismissItem, setManagedTimeout]);

  useEffect(() => {
    return () => {
      for (const timer of timerRefs.current) {
        clearManagedTimeout(timer);
      }
      timerRefs.current.clear();
    };
  }, [clearManagedTimeout]);

  if (items.length === 0) return null;

  return (
    <OverlayPortal>
    <div
      class="fixed left-1/2 bottom-5 z-[3200] flex w-[min(92vw,520px)] -translate-x-1/2 flex-col items-center gap-2 pointer-events-none"
      aria-live="polite"
    >
      {items.map((item) => (
        <div
          key={item.id}
          class={`${item.closing ? 'oh-snackbar-exit' : 'oh-snackbar-enter'} rounded-full px-4 py-2 text-sm pointer-events-auto`}
          style={{
            ...toneStyle(item.tone),
            boxShadow: 'var(--m3-elev-3)',
            maxWidth: '100%',
            wordBreak: 'break-word',
          }}
          role={item.tone === 'error' ? 'alert' : 'status'}
        >
          {item.message}
        </div>
      ))}
    </div>
    </OverlayPortal>
  );
}
