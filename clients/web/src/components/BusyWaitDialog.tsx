import { useEffect, useState } from 'preact/hooks';
import { useControlledDelayedVisibility } from '../hooks/useDelayedVisibility';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  DIALOG_OVERLAY_PRIORITY_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

interface BusyWaitDialogProps {
  open: boolean;
  title: string;
  body?: string;
  delayMs?: number;
}

export function BusyWaitDialog({
  open,
  title,
  body,
  delayMs = 650,
}: BusyWaitDialogProps) {
  const { visible, closing } = useControlledDelayedVisibility(open, {
    enterDelayMs: delayMs,
  });
  const [dismissed, setDismissed] = useState(false);
  const { closing: exitClosing, requestClose } = useDialogExitMotion(
    () => setDismissed(true),
  );

  useEffect(() => {
    if (!open) setDismissed(false);
  }, [open]);

  if (!visible || dismissed) return null;
  return (
    <DialogFrame
      closing={closing || exitClosing}
      onRequestClose={requestClose}
      closeOnBackdrop={false}
      {...createStandardDialogFrameAppearance({
        overlayZIndex: DIALOG_OVERLAY_PRIORITY_Z_INDEX,
        panelClassName: 'w-full max-w-sm rounded-m3-xl p-5',
      })}
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
              <p class="mt-1 text-sm leading-relaxed oh-text-muted">
                {body}
              </p>
            ) : null}
          </div>
        </div>
      </div>
    </DialogFrame>
  );
}
