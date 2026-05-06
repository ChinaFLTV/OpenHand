import { createPortal } from 'preact/compat';
import { useEffect, useRef, useState } from 'preact/hooks';

export interface BusyWaitDialogProps {
  open: boolean;
  title: string;
  body?: string;
  delayMs?: number;
}

type BusyDialogPhase = 'hidden' | 'visible' | 'closing';

export function BusyWaitDialog({
  open,
  title,
  body,
  delayMs = 650,
}: BusyWaitDialogProps) {
  const [phase, setPhase] = useState<BusyDialogPhase>('hidden');
  const phaseRef = useRef<BusyDialogPhase>('hidden');

  useEffect(() => {
    phaseRef.current = phase;
  }, [phase]);

  useEffect(() => {
    let timer: number | undefined;
    if (open) {
      if (phaseRef.current === 'hidden') {
        timer = window.setTimeout(() => setPhase('visible'), delayMs);
      } else {
        setPhase('visible');
      }
    } else if (phaseRef.current !== 'hidden') {
      setPhase('closing');
      timer = window.setTimeout(() => setPhase('hidden'), 180);
    }
    return () => {
      if (timer != null) window.clearTimeout(timer);
    };
  }, [open, delayMs]);

  if (phase === 'hidden') return null;
  const closing = phase === 'closing';
  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'rgba(0,0,0,0.38)', backdropFilter: 'blur(2px)', zIndex: 2800 }}
      aria-live="polite"
      aria-busy="true"
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} w-full max-w-sm rounded-m3-xl p-5`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline-variant)',
        }}
      >
        <div class="flex items-center gap-4">
          <span
            aria-hidden
            class="oh-spin inline-flex h-11 w-11 flex-none items-center justify-center rounded-full"
            style={{
              border: '3px solid color-mix(in srgb, var(--m3-primary) 20%, transparent)',
              borderTopColor: 'var(--m3-primary)',
            }}
          />
          <div class="min-w-0 flex-1">
            <h2 class="text-base font-semibold">{title}</h2>
            {body ? (
              <p class="mt-1 text-sm leading-relaxed" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {body}
              </p>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
  return typeof document === 'undefined' ? node : createPortal(node, document.body);
}