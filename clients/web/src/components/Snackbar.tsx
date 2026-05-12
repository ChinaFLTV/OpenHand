import { useEffect, useState } from 'preact/hooks';
import { useReducedMotion } from '../hooks/useReducedMotion';
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

export function showSnackbar(message: string, options: SnackbarOptions = {}): void {
  const trimmed = message.trim();
  if (!trimmed) return;
  const item: SnackbarItem = {
    id: nextId++,
    message: trimmed,
    tone: options.tone ?? 'default',
    durationMs: options.durationMs ?? 2600,
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

  useEffect(() => {
    const onItem = (item: SnackbarItem) => {
      setItems((prev) => [...prev.slice(-2), item]);
      window.setTimeout(() => {
        if (reduceMotion) {
          setItems((prev) => prev.filter((cur) => cur.id !== item.id));
          return;
        }
        setItems((prev) => prev.map((cur) => (
          cur.id === item.id ? { ...cur, closing: true } : cur
        )));
        window.setTimeout(() => {
          setItems((prev) => prev.filter((cur) => cur.id !== item.id));
        }, 180);
      }, item.durationMs);
    };
    listeners.add(onItem);
    return () => {
      listeners.delete(onItem);
    };
  }, [reduceMotion]);

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
