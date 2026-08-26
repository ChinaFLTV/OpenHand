import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { classNames } from '../shared/util/class_names';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DialogActionButton,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import { svgIconProps } from '../shared/ui/svg_icon';

type ConfirmCloseReason =
  | 'cancel'
  | 'confirm'
  | 'confirmed'
  | 'dismiss'
  | 'escape';

function ConfirmIcon({ danger }: { danger: boolean }) {
  const common = svgIconProps({ size: 20 });
  return danger
    ? <svg {...common}><path d="M12 3 2.8 20h18.4z" /><path d="M12 9v4M12 17h.01" /></svg>
    : <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
}

interface ConfirmDialogProps {
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
  /** 无外部 busy 状态时默认先播放退场动画，再执行确认回调。 */
  closeOnConfirm?: boolean;
  /** 先执行异步确认，成功后再播放退场动画。返回 false 时保持弹窗。 */
  confirmBeforeClose?: boolean;
  /** 是否允许使用 Esc 关闭弹窗；写命令确认等审批弹窗应显式设为 false。 */
  closeOnEscape?: boolean;
  /** 异步确认成功且退场完成后的收尾回调。 */
  onConfirmSuccess?: () => void;
  onCancel: () => void;
  onConfirm: () => boolean | void | Promise<boolean | void>;
}

export function ConfirmDialog(props: ConfirmDialogProps) {
  const hasExternalBusy = Object.prototype.hasOwnProperty.call(props, 'busy');
  const {
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
    closeOnConfirm = !hasExternalBusy,
    confirmBeforeClose = false,
    closeOnEscape = true,
    onConfirmSuccess,
    onCancel,
    onConfirm,
  } = props;
  const confirmPendingRef = useRef(false);
  const closeRequestedRef = useRef(false);
  const closeFinishedRef = useRef(false);
  const confirmedWhileClosingRef = useRef(false);
  const mountedRef = useRef(true);
  const [confirmPending, setConfirmPending] = useState(false);
  const effectiveBusy = busy || confirmPending;
  const { closing, requestCloseWithReason } = useDialogExitMotion<ConfirmCloseReason>(
    (reason) => {
      closeFinishedRef.current = true;
      if (confirmedWhileClosingRef.current) {
        onConfirmSuccess?.();
        return;
      }
      if (reason === 'confirmed') {
        onConfirmSuccess?.();
        return;
      }
      if (reason === 'confirm') {
        void onConfirm();
        return;
      }
      if (reason === 'escape') {
        (onDismiss ?? onCancel)();
        return;
      }
      onCancel();
    },
    {
      closeOnEscape,
      onBeforeClose: () => {
        closeRequestedRef.current = true;
      },
    },
  );

  useEffect(() => () => {
    mountedRef.current = false;
  }, []);
  const requestCancel = () => requestCloseWithReason('cancel');
  const requestConfirm = () => {
    if (confirmBeforeClose) {
      if (effectiveBusy || closing || confirmPendingRef.current) return;
      confirmPendingRef.current = true;
      setConfirmPending(true);
      void Promise.resolve()
        .then(onConfirm)
        .then((success) => {
          if (success === false) return;
          if (closeRequestedRef.current) {
            confirmedWhileClosingRef.current = true;
            if (closeFinishedRef.current) onConfirmSuccess?.();
          } else {
            requestCloseWithReason('confirmed');
          }
        })
        .finally(() => {
          confirmPendingRef.current = false;
          if (mountedRef.current) setConfirmPending(false);
        });
      return;
    }
    if (closeOnConfirm) {
      requestCloseWithReason('confirm');
      return;
    }
    onConfirm();
  };
  const requestDismiss = () => requestCloseWithReason('dismiss');

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestDismiss}
      closeOnBackdrop={!effectiveBusy && !closing && !disableBackdropClose}
      {...createStandardDialogFrameAppearance({
        overlayClassName: classNames(
          'oh-confirm-dialog-overlay',
          DIALOG_OVERLAY_CENTER_CLASS,
        ),
        panelClassName: classNames(
          'oh-confirm-dialog w-full rounded-m3-xl p-5',
          wide && 'is-wide',
          scrollBody && 'is-scroll-body',
        ),
        panelBorder: 'outline',
        panelSurface: {
          maxWidth: wide
            ? 'min(720px, calc(100vw - 32px))'
            : 'min(448px, calc(100vw - 32px))',
          maxHeight: scrollBody ? 'min(86dvh, 760px)' : undefined,
        },
      })}
      ariaLabel={title}
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
          <h2
            class="oh-confirm-dialog-title text-base font-semibold oh-text-body"
          >
            {title}
          </h2>
          {body ? (
            <div
              class={classNames(
                'oh-confirm-dialog-body mt-2 text-sm leading-relaxed oh-text-muted',
                bodyClassName,
              )}
            >
              {body}
            </div>
          ) : null}
        </div>
      </div>
      <div class="oh-confirm-dialog-actions mt-5 flex items-center justify-end gap-2">
        <DialogActionButton
          className="oh-confirm-dialog-button px-4 py-2"
          tone="secondary"
          disabled={effectiveBusy || closing}
          onClick={requestCancel}
        >
          {cancelLabel}
        </DialogActionButton>
        <DialogActionButton
          className="oh-confirm-dialog-button px-4 py-2"
          tone={danger ? 'danger' : 'primary'}
          disabled={effectiveBusy || closing}
          onClick={requestConfirm}
        >
          {confirmLabel}
        </DialogActionButton>
      </div>
    </DialogFrame>
  );
}
