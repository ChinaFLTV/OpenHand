import { useEffect, useState } from 'preact/hooks';

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
        border: '1px solid color-mix(in srgb, var(--m3-secondary) 42%, transparent)',
        color: 'var(--m3-on-secondary-container)',
        background: 'var(--m3-secondary-container)',
      };
    case 'warning':
      return {
        border: '1px solid color-mix(in srgb, var(--m3-tertiary) 46%, transparent)',
        color: 'var(--m3-on-tertiary-container)',
        background: 'var(--m3-tertiary-container)',
      };
    case 'error':
      return {
        border: '1px solid color-mix(in srgb, var(--m3-error) 48%, transparent)',
        color: 'var(--m3-error)',
        background: 'color-mix(in srgb, var(--m3-error) 10%, var(--m3-surface-container))',
      };
    default:
      return {
        border: '1px solid var(--m3-outline)',
        color: 'var(--m3-on-surface)',
        background: 'var(--m3-surface-container)',
      };
  }
}

export function SnackbarHost() {
  const [items, setItems] = useState<SnackbarItem[]>([]);

  useEffect(() => {
    const onItem = (item: SnackbarItem) => {
      setItems((prev) => [...prev.slice(-2), item]);
      window.setTimeout(() => {
        setItems((prev) => prev.filter((cur) => cur.id !== item.id));
      }, item.durationMs);
    };
    listeners.add(onItem);
    return () => {
      listeners.delete(onItem);
    };
  }, []);

  if (items.length === 0) return null;

  return (
    <div
      class="fixed left-1/2 bottom-5 z-[3200] flex w-[min(92vw,520px)] -translate-x-1/2 flex-col items-center gap-2 pointer-events-none"
      aria-live="polite"
    >
      {items.map((item) => (
        <div
          key={item.id}
          class="oh-snackbar-enter rounded-full px-4 py-2 text-sm pointer-events-auto"
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
  );
}
