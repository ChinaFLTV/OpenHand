import { useEffect, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';
import { useControlledDelayedVisibility } from '../hooks/useDelayedVisibility';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { runWithTimeout } from '../utils/timed_abort';
import { ignoreError } from '../shared/util/errors';
import {
  DIALOG_OVERLAY_CENTER_COMPACT_CLASS,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

interface SessionGoneDialogProps {
  open: boolean;
  onBeforeNavigate?: () => Promise<void> | void;
}

const BEFORE_NAVIGATE_TIMEOUT_MS = 2500;

async function runBeforeNavigate(
  onBeforeNavigate?: () => Promise<void> | void,
): Promise<void> {
  if (!onBeforeNavigate || typeof window === 'undefined') return;
  await runWithTimeout(() => Promise.resolve().then(onBeforeNavigate), {
    timeoutMs: BEFORE_NAVIGATE_TIMEOUT_MS,
  }).catch(ignoreError);
}

export function SessionGoneDialog({ open, onBeforeNavigate }: SessionGoneDialogProps) {
  const location = useAnimatedLocation();
  const [navigating, setNavigating] = useState(false);
  const { visible, closing: hiding } = useControlledDelayedVisibility(open);
  const { closing, requestClose, resetClosing } = useDialogExitMotion(
    () => location.route('/threads'),
    {
      active: open,
      onBeforeClose: () => {
        setNavigating(true);
        void runBeforeNavigate(onBeforeNavigate);
      },
    },
  );
  const frameClosing = closing || hiding;

  useEffect(() => {
    if (!open) {
      setNavigating(false);
      resetClosing();
      return undefined;
    }
    if (typeof window === 'undefined') return undefined;
    const id = window.requestAnimationFrame(() => {
      const btn = document.getElementById('oh-session-gone-back-btn');
      btn?.focus();
    });
    return () => window.cancelAnimationFrame(id);
  }, [open, resetClosing]);

  if (!visible) return null;

  const handleBack = () => {
    if (navigating || frameClosing) return;
    requestClose();
  };

  return (
    <DialogFrame
      closing={frameClosing}
      closeOnBackdrop={false}
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_CENTER_COMPACT_CLASS,
        overlayTone: 'intense',
        panelClassName: 'rounded-m3-xl w-full max-w-[420px] flex flex-col',
        panelBorder: 'none',
      })}
      ariaLabel={t('sessionGone.title', '会话已不存在')}
    >
      <header class="px-6 pt-6 pb-2 flex items-center gap-3">
        <span
          class="inline-flex items-center justify-center rounded-full"
          style={{
            width: '36px',
            height: '36px',
            background: 'color-mix(in srgb, var(--m3-error) 14%, transparent)',
            color: 'var(--m3-error)',
            fontSize: '18px',
          }}
          aria-hidden="true"
        >
          !
        </span>
        <h2 class="text-base font-semibold oh-text-body">
          {t('sessionGone.title', '会话已不存在')}
        </h2>
      </header>
      <div class="px-6 pb-4">
        <p class="text-sm leading-relaxed oh-text-muted">
          {t(
            'sessionGone.body',
            '当前会话已被删除或在另一台设备上移除。请返回会话列表选择其它会话或新建一个。',
          )}
        </p>
      </div>
      <footer
        class="px-6 py-4 flex justify-end"
        style={{ borderTop: '1px solid var(--m3-outline)' }}
      >
        <button
          id="oh-session-gone-back-btn"
          type="button"
          onClick={() => void handleBack()}
          disabled={navigating || frameClosing}
          class="oh-tap-press text-sm px-4 py-2 rounded-m3-md"
          style={{
            color: 'var(--m3-on-primary)',
            backgroundColor: 'var(--m3-primary)',
            opacity: navigating || frameClosing ? 0.6 : 1,
            minWidth: '96px',
          }}
        >
          {navigating ? t('sessionGone.navigating', '返回中…') : t('sessionGone.back', '返回')}
        </button>
      </footer>
    </DialogFrame>
  );
}
