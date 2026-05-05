// 当前打开的会话在服务端被删除时的友好提示弹窗。
//
// 触发场景：
//   - 在 SessionDetailPage 发送消息 / 拉详情 / SSE 期间收到 HTTP 404 + body.error === 'session_deleted_or_not_found'
// 行为：
//   - 模态遮罩 + 居中卡片，仅有一个「返回」按钮
//   - 点击返回 → 先调用 `onBeforeNavigate`（让上层 refresh 线程列表），再 location.route('/threads')
//   - ESC / 点击遮罩外部禁用：避免用户误触绕过流程
//   - 进出场动画沿用全局 `oh-dialog-fade-in` / `oh-dialog-pop-in`，已通过
//     [data-motion='reduced'] 自动尊重 reduceMotion / OS prefers-reduced-motion

import { useEffect, useState } from 'preact/hooks';
import { useLocation } from 'preact-iso';
import { t } from '../i18n';

export interface SessionGoneDialogProps {
  open: boolean;
  /** 在导航到 /threads 前可执行的副作用 (例如 refresh sessions store) */
  onBeforeNavigate?: () => Promise<void> | void;
}

export function SessionGoneDialog({ open, onBeforeNavigate }: SessionGoneDialogProps) {
  const location = useLocation();
  const [navigating, setNavigating] = useState(false);

  // open 状态变更时把焦点尝试丢给主按钮 (a11y + 回车直接确认)
  useEffect(() => {
    if (!open) return;
    const id = window.requestAnimationFrame(() => {
      const btn = document.getElementById('oh-session-gone-back-btn');
      btn?.focus();
    });
    return () => window.cancelAnimationFrame(id);
  }, [open]);

  if (!open) return null;

  const handleBack = async () => {
    if (navigating) return;
    setNavigating(true);
    try {
      if (onBeforeNavigate) await onBeforeNavigate();
    } finally {
      // 即便 refresh 失败也要导航走 — 用户已经被告知会话不存在了
      location.route('/threads');
    }
  };

  return (
    <div
      class="fixed inset-0 z-[60] flex items-center justify-center px-4 oh-dialog-fade-in"
      style={{
        background: 'rgba(0,0,0,0.45)',
        backdropFilter: 'blur(2px)',
      }}
      role="dialog"
      aria-modal="true"
      aria-label={t('sessionGone.title', '会话已不存在')}
    >
      <section
        class="oh-dialog-pop-in rounded-m3-xl w-full max-w-[420px] flex flex-col"
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
        }}
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
            ⚠
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
            disabled={navigating}
            class="oh-tap-press text-sm px-4 py-2 rounded-m3-md"
            style={{
              color: 'var(--m3-on-primary)',
              backgroundColor: 'var(--m3-primary)',
              opacity: navigating ? 0.6 : 1,
              minWidth: '96px',
            }}
          >
            {navigating ? t('sessionGone.navigating', '返回中…') : t('sessionGone.back', '返回')}
          </button>
        </footer>
      </section>
    </div>
  );
}
