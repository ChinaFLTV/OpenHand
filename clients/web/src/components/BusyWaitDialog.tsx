import { useControlledDelayedVisibility } from '../hooks/useDelayedVisibility';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_PRIORITY_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
  createDialogPanelSurfaceStyle,
} from './DialogFrame';

export interface BusyWaitDialogProps {
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

  if (!visible) return null;
  return (
    <DialogFrame
      closing={closing}
      closeOnBackdrop={false}
      overlayClassName={DIALOG_OVERLAY_CENTER_CLASS}
      overlayStyle={createDialogOverlayStyle({
        zIndex: DIALOG_OVERLAY_PRIORITY_Z_INDEX,
      })}
      panelClassName="w-full max-w-sm rounded-m3-xl p-5"
      panelStyle={createDialogPanelSurfaceStyle({
        border: '1px solid var(--m3-outline-variant)',
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
