import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from '../hooks/useDialogMotionSettings';
import { useReducedMotion } from '../hooks/useReducedMotion';
import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';
import { OverlayPortal } from './OverlayPortal';

type SnackbarTone = 'default' | 'success' | 'warning' | 'error';

interface SnackbarOptions {
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
const MAX_PENDING_SNACKBAR_ITEMS = 20;
const DEFAULT_SNACKBAR_DURATION_MS = 2600;
const MAX_SNACKBAR_DURATION_MS = 60_000;
const SNACKBAR_BASE_STYLE = {
  border: '1px solid var(--m3-outline-variant, rgba(127,127,127,0.3))',
};
const SNACKBAR_DEFAULT_TONE_STYLE = {
  color: 'var(--m3-inverse-on-surface, #f1f0f4)',
  background: 'var(--m3-inverse-surface, #2f3033)',
};
const SNACKBAR_TONE_STYLES = {
  default: SNACKBAR_DEFAULT_TONE_STYLE,
  success: SNACKBAR_DEFAULT_TONE_STYLE,
  warning: {
    color: 'var(--m3-on-tertiary-container, #28132e)',
    background: 'var(--m3-tertiary-container, #fad8fd)',
  },
  error: {
    color: 'var(--m3-on-error-container, #410e0b)',
    background: 'var(--m3-error-container, #f9dedc)',
  },
} as const;

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

export function SnackbarHost() {
  const [items, setItems] = useState<SnackbarItem[]>([]);
  const reduceMotion = useReducedMotion();
  const timerRefs = useRef<Set<number>>(new Set());
  const autoDismissTimerRefs = useRef<Map<number, number>>(new Map());
  const visibleItemsRef = useRef<SnackbarItem[]>([]);
  const pendingItemsRef = useRef<SnackbarItem[]>([]);
  const reduceMotionRef = useRef(reduceMotion);
  const scheduleAutoDismissRef = useRef<(item: SnackbarItem) => void>(() => {});
  reduceMotionRef.current = reduceMotion;

  const clearManagedTimeout = useCallback((timer: number) => {
    if (typeof window !== 'undefined') {
      window.clearTimeout(timer);
    }
    timerRefs.current.delete(timer);
  }, []);

  const clearAutoDismissTimer = useCallback((id: number) => {
    const timer = autoDismissTimerRefs.current.get(id);
    if (timer == null) return;
    clearManagedTimeout(timer);
    autoDismissTimerRefs.current.delete(id);
  }, [clearManagedTimeout]);

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

  const removeItem = useCallback((id: number) => {
    const remainingItems = visibleItemsRef.current.filter((item) => item.id !== id);
    if (remainingItems.length === visibleItemsRef.current.length) return;
    const nextItem = pendingItemsRef.current.shift();
    const nextItems = nextItem == null
      ? remainingItems
      : [...remainingItems, nextItem];
    visibleItemsRef.current = nextItems;
    setItems(nextItems);
    if (nextItem != null) scheduleAutoDismissRef.current(nextItem);
  }, []);

  const dismissItem = useCallback((item: SnackbarItem) => {
    const currentItem = visibleItemsRef.current.find((current) => current.id === item.id);
    if (currentItem == null || currentItem.closing) return;
    clearAutoDismissTimer(currentItem.id);
    const exitDurationMs = reduceMotionRef.current ? 0 : getDialogExitDurationMs();
    if (exitDurationMs <= 0) {
      removeItem(currentItem.id);
      return;
    }
    const closingItems = visibleItemsRef.current.map((current) => (
      current.id === currentItem.id ? { ...current, closing: true } : current
    ));
    visibleItemsRef.current = closingItems;
    setItems(closingItems);
    setManagedTimeout(() => {
      removeItem(currentItem.id);
    }, exitDurationMs);
  }, [clearAutoDismissTimer, removeItem, setManagedTimeout]);

  const scheduleAutoDismiss = useCallback((item: SnackbarItem) => {
    clearAutoDismissTimer(item.id);
    const timer = setManagedTimeout(() => dismissItem(item), item.durationMs);
    if (timer != null) {
      autoDismissTimerRefs.current.set(item.id, timer);
    }
  }, [clearAutoDismissTimer, dismissItem, setManagedTimeout]);

  useEffect(() => {
    scheduleAutoDismissRef.current = scheduleAutoDismiss;
    return () => {
      scheduleAutoDismissRef.current = () => {};
    };
  }, [scheduleAutoDismiss]);

  useEffect(() => {
    const onItem = (item: SnackbarItem) => {
      if (visibleItemsRef.current.length >= MAX_VISIBLE_SNACKBAR_ITEMS) {
        if (pendingItemsRef.current.length >= MAX_PENDING_SNACKBAR_ITEMS) {
          pendingItemsRef.current.shift();
        }
        pendingItemsRef.current.push(item);
        return;
      }
      const nextItems = [...visibleItemsRef.current, item];
      visibleItemsRef.current = nextItems;
      setItems(nextItems);
      scheduleAutoDismiss(item);
    };
    listeners.add(onItem);
    return () => {
      listeners.delete(onItem);
    };
  }, [scheduleAutoDismiss]);

  useEffect(() => {
    return () => {
      for (const timer of timerRefs.current) {
        clearManagedTimeout(timer);
      }
      timerRefs.current.clear();
      autoDismissTimerRefs.current.clear();
      visibleItemsRef.current = [];
      pendingItemsRef.current = [];
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
              ...SNACKBAR_BASE_STYLE,
              ...SNACKBAR_TONE_STYLES[item.tone],
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
