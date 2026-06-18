import { useEffect, useRef, useState } from 'preact/hooks';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { getDialogExitDurationMs } from '../hooks/useDialogMotionSettings';
import { normalizeDurationMs } from '../shared/util/number';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_PRIORITY_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
} from './DialogFrame';

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
  const reduceMotion = useReducedMotion();
  const [phase, setPhase] = useState<BusyDialogPhase>('hidden');
  const phaseRef = useRef<BusyDialogPhase>('hidden');
  const effectiveDelayMs = normalizeDurationMs(delayMs, { fallback: 0 });

  useEffect(() => {
    phaseRef.current = phase;
  }, [phase]);

  useEffect(() => {
    let timer: number | undefined;
    if (open) {
      if (phaseRef.current === 'hidden') {
        timer = window.setTimeout(
          () => setPhase('visible'),
          reduceMotion ? 0 : effectiveDelayMs,
        );
      } else {
        setPhase('visible');
      }
    } else if (phaseRef.current !== 'hidden') {
      setPhase('closing');
      timer = window.setTimeout(
        () => setPhase('hidden'),
        reduceMotion ? 0 : getDialogExitDurationMs(),
      );
    }
    return () => {
      if (timer != null) window.clearTimeout(timer);
    };
  }, [open, effectiveDelayMs, reduceMotion]);

  if (phase === 'hidden') return null;
  const closing = phase === 'closing';
  return (
    <DialogFrame
      closing={closing}
      closeOnBackdrop={false}
      overlayClassName={DIALOG_OVERLAY_CENTER_CLASS}
      overlayStyle={createDialogOverlayStyle({
        zIndex: DIALOG_OVERLAY_PRIORITY_Z_INDEX,
      })}
      panelClassName="w-full max-w-sm rounded-m3-xl p-5"
      panelStyle={{
        background: 'var(--m3-surface-container)',
        color: 'var(--m3-on-surface)',
        boxShadow: 'var(--m3-elev-3)',
        border: '1px solid var(--m3-outline-variant)',
      }}
      ariaLabel={title}
    >
      <div
        aria-live="polite"
        aria-busy="true"
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
    </DialogFrame>
  );
}
