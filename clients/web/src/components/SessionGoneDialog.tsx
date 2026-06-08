import { useEffect, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { createDialogOverlayStyle, DialogFrame } from './DialogFrame';

export interface SessionGoneDialogProps {
  open: boolean;
  onBeforeNavigate?: () => Promise<void> | void;
}

const BEFORE_NAVIGATE_TIMEOUT_MS = 2500;

async function runBeforeNavigate(
  onBeforeNavigate?: () => Promise<void> | void,
): Promise<void> {
  if (!onBeforeNavigate || typeof window === 'undefined') return;
  let timeoutId: number | undefined;
  const task = Promise.resolve()
    .then(onBeforeNavigate)
    .catch(() => undefined);
  const timeout = new Promise<void>((resolve) => {
    timeoutId = window.setTimeout(resolve, BEFORE_NAVIGATE_TIMEOUT_MS);
  });
  try {
    await Promise.race([task, timeout]);
  } finally {
    if (timeoutId != null) {
      window.clearTimeout(timeoutId);
    }
  }
}

export function SessionGoneDialog({ open, onBeforeNavigate }: SessionGoneDialogProps) {
  const location = useAnimatedLocation();
  const [navigating, setNavigating] = useState(false);
  const { closing, requestClose, resetClosing } = useDialogExitMotion(
    () => location.route('/threads'),
    { closeOnEscape: false },
  );

  useEffect(() => {
    if (!open) {
      setNavigating(false);
      resetClosing();
      return undefined;
    }
    const id = window.requestAnimationFrame(() => {
      const btn = document.getElementById('oh-session-gone-back-btn');
      btn?.focus();
    });
    return () => window.cancelAnimationFrame(id);
  }, [open, resetClosing]);

  if (!open) return null;

  const handleBack = async () => {
    if (navigating || closing) return;
    setNavigating(true);
    await runBeforeNavigate(onBeforeNavigate);
    requestClose();
  };

  return (
    <DialogFrame
      closing={closing}
      closeOnBackdrop={false}
      overlayClassName="fixed inset-0 flex items-center justify-center px-4"
      overlayStyle={createDialogOverlayStyle({
        background: 'rgba(0,0,0,0.45)',
        zIndex: 2600,
      })}
      panelClassName="rounded-m3-xl w-full max-w-[420px] flex flex-col"
      panelStyle={{
        background: 'var(--m3-surface-container)',
        color: 'var(--m3-on-surface)',
        boxShadow: 'var(--m3-elev-3)',
      }}
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
        <h2 class="text-base font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
          {t('sessionGone.title', '会话已不存在')}
        </h2>
      </header>
      <div class="px-6 pb-4">
        <p class="text-sm leading-relaxed" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
          disabled={navigating || closing}
          class="oh-tap-press text-sm px-4 py-2 rounded-m3-md"
          style={{
            color: 'var(--m3-on-primary)',
            backgroundColor: 'var(--m3-primary)',
            opacity: navigating || closing ? 0.6 : 1,
            minWidth: '96px',
          }}
        >
          {navigating ? t('sessionGone.navigating', '返回中…') : t('sessionGone.back', '返回')}
        </button>
      </footer>
    </DialogFrame>
  );
}
