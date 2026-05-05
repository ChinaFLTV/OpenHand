import { createPortal } from 'preact/compat';

export interface ConfirmDialogProps {
  title: string;
  body?: string;
  confirmLabel: string;
  cancelLabel?: string;
  danger?: boolean;
  busy?: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}

export function ConfirmDialog({
  title,
  body,
  confirmLabel,
  cancelLabel = '取消',
  danger = false,
  busy = false,
  onCancel,
  onConfirm,
}: ConfirmDialogProps) {
  const node = (
    <div
      class="oh-dialog-fade-in fixed inset-0 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.38)', backdropFilter: 'blur(2px)', zIndex: 2600 }}
      onClick={busy ? undefined : onCancel}
    >
      <div
        role="dialog"
        aria-modal="true"
        class="oh-dialog-pop-in w-full max-w-md rounded-m3-xl p-5"
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div class="flex items-start gap-3">
          <span
            aria-hidden
            class="inline-flex h-10 w-10 flex-none items-center justify-center rounded-full text-lg"
            style={{
              background: danger
                ? 'color-mix(in srgb, var(--m3-error) 13%, transparent)'
                : 'color-mix(in srgb, var(--m3-primary) 14%, transparent)',
              color: danger ? 'var(--m3-error)' : 'var(--m3-primary)',
            }}
          >
            {danger ? '!' : '✓'}
          </span>
          <div class="min-w-0 flex-1">
            <h2 class="text-base font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
              {title}
            </h2>
            {body ? (
              <p class="mt-2 text-sm leading-relaxed" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {body}
              </p>
            ) : null}
          </div>
        </div>
        <div class="mt-5 flex items-center justify-end gap-2">
          <button
            type="button"
            class="oh-tap-press rounded-m3-sm px-4 py-2 text-sm disabled:opacity-60"
            style={{
              color: 'var(--m3-on-surface-variant)',
              border: '1px solid var(--m3-outline)',
              background: 'transparent',
            }}
            disabled={busy}
            onClick={onCancel}
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            class="oh-tap-press rounded-m3-sm px-4 py-2 text-sm font-medium disabled:opacity-60"
            style={{
              color: 'var(--m3-on-primary)',
              background: danger ? 'var(--m3-error)' : 'var(--m3-primary)',
              border: '1px solid transparent',
            }}
            disabled={busy}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );

  return typeof document === 'undefined' ? node : createPortal(node, document.body);
}
