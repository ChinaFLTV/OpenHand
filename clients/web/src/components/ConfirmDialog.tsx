import { useEffect } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { OverlayPortal } from './OverlayPortal';

function ConfirmIcon({ danger }: { danger: boolean }) {
  const common = {
    width: 20,
    height: 20,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 2,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    focusable: 'false',
    'aria-hidden': true,
  };
  return danger
    ? <svg {...common}><path d="M12 3 2.8 20h18.4z" /><path d="M12 9v4M12 17h.01" /></svg>
    : <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
}

export interface ConfirmDialogProps {
  title: string;
  body?: ComponentChildren;
  confirmLabel: string;
  cancelLabel?: string;
  danger?: boolean;
  busy?: boolean;
  wide?: boolean;
  scrollBody?: boolean;
  bodyClassName?: string;
  /** 当为 true 时，点击遮罩外部不关闭弹窗（仅可通过按钮 / Esc 关闭）。 */
  disableBackdropClose?: boolean;
  /**
   * Esc 键的独立回调。提供后，按 Esc 触发该回调（替代默认的 onCancel），
   * 用于明确区分"用户按 Esc"vs"用户点击取消按钮"两种意图。
   */
  onDismiss?: () => void;
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
  wide = false,
  scrollBody = false,
  bodyClassName = '',
  disableBackdropClose = false,
  onDismiss,
  onCancel,
  onConfirm,
}: ConfirmDialogProps) {
  // 让 Esc / 按钮取消走不同的 close 路径，但共用同一动效 hook：
  // - 点击「取消」按钮：触发 onCancel
  // - 按 Esc：若提供 onDismiss 则走 onDismiss，否则回退到 onCancel
  const cancelMotion = useDialogExitMotion(onCancel);
  const dismissMotion = useDialogExitMotion(onDismiss ?? onCancel);
  const closing = cancelMotion.closing || dismissMotion.closing;

  useEffect(() => {
    if (busy || closing) return;
    const handleKeyDown = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape') dismissMotion.requestClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [busy, closing, dismissMotion]);

  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} oh-confirm-dialog-overlay fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'rgba(0,0,0,0.38)', backdropFilter: 'blur(2px)', zIndex: 2600 }}
      onClick={busy || closing || disableBackdropClose
        ? undefined
        : cancelMotion.requestClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} oh-confirm-dialog ${wide ? 'is-wide' : ''} ${scrollBody ? 'is-scroll-body' : ''} w-full rounded-m3-xl p-5`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline)',
          maxWidth: wide ? 'min(720px, calc(100vw - 32px))' : 'min(448px, calc(100vw - 32px))',
          maxHeight: scrollBody ? 'min(86dvh, 760px)' : undefined,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div class="oh-confirm-dialog-head flex items-start gap-3">
          <span
            aria-hidden
            class="oh-confirm-dialog-icon inline-flex h-10 w-10 flex-none items-center justify-center rounded-full text-lg"
            style={{
              background: danger
                ? 'color-mix(in srgb, var(--m3-error) 13%, transparent)'
                : 'color-mix(in srgb, var(--m3-primary) 14%, transparent)',
              color: danger ? 'var(--m3-error)' : 'var(--m3-primary)',
            }}
          >
            <ConfirmIcon danger={danger} />
          </span>
          <div class="oh-confirm-dialog-main min-w-0 flex-1">
            <h2 class="oh-confirm-dialog-title text-base font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
              {title}
            </h2>
            {body ? (
              <div class={`oh-confirm-dialog-body mt-2 text-sm leading-relaxed ${bodyClassName}`} style={{ color: 'var(--m3-on-surface-variant)' }}>
                {body}
              </div>
            ) : null}
          </div>
        </div>
        <div class="oh-confirm-dialog-actions mt-5 flex items-center justify-end gap-2">
          <button
            type="button"
            class="oh-tap-press oh-confirm-dialog-button rounded-m3-sm px-4 py-2 text-sm disabled:opacity-60"
            style={{
              color: 'var(--m3-on-surface-variant)',
              border: '1px solid var(--m3-outline)',
              background: 'transparent',
            }}
            disabled={busy || closing}
            onClick={cancelMotion.requestClose}
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            class="oh-tap-press oh-confirm-dialog-button rounded-m3-sm px-4 py-2 text-sm font-medium disabled:opacity-60"
            style={{
              color: 'var(--m3-on-primary)',
              background: danger ? 'var(--m3-error)' : 'var(--m3-primary)',
              border: '1px solid transparent',
            }}
            disabled={busy || closing}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );

  return <OverlayPortal>{node}</OverlayPortal>;
}
