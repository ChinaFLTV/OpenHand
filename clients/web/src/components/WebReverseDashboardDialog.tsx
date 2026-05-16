/** @jsxImportSource preact */
// Web 端 Web 逆向调试面板（精简版）。
//
// 与桌面端的不同：浏览器外部进程由桌面 App 管理；Web 客户端只能看到
// session metadata 中存储的配置摘要，不能控制浏览器或 CDP。本对话框
// 给 Web 用户提供：
//   - 当前会话的 web_reverse_config 摘要
//   - 与官方 DevTools 协同操作的指引
// 提示模型/真实 CDP 数据流仍由桌面 App 端的 dashboard 持有。

import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { OverlayPortal } from './OverlayPortal';
import { t } from '../i18n';
import type { SessionSummary } from '../api/sessions';

export interface WebReverseDashboardDialogProps {
  session: SessionSummary;
  onClose: () => void;
}

interface WebReverseConfig {
  target_url?: string;
  objective?: string;
  cdp_port?: number;
  user_data_dir?: string;
  browser_kind?: string;
  trigger_actions?: string;
  login_mode?: string;
  proxy?: string;
  keywords?: string[];
}

function asConfig(raw: unknown): WebReverseConfig | null {
  if (!raw || typeof raw !== 'object') return null;
  return raw as WebReverseConfig;
}

export function WebReverseDashboardDialog({
  session,
  onClose,
}: WebReverseDashboardDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const config = asConfig((session.metadata ?? {})['web_reverse_config']);

  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'var(--m3-scrim-bg)', zIndex: 3000 }}
      onClick={(ev) => {
        if (ev.target === ev.currentTarget) requestClose();
      }}
    >
      <section
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} w-full max-w-[720px] rounded-m3-lg shadow-xl overflow-hidden`}
        style={{ background: 'var(--m3-surface-container)' }}
      >
        <header
          class="px-6 py-4 flex items-center justify-between border-b"
          style={{ borderColor: 'var(--m3-outline-variant)' }}
        >
          <div class="flex items-center gap-3">
            <div
              class="w-10 h-10 rounded-m3-sm flex items-center justify-center"
              style={{
                background: 'var(--m3-primary-container)',
                color: 'var(--m3-on-primary-container)',
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="6" y="9" width="12" height="10" rx="3" />
                <path d="M9 9V7a3 3 0 0 1 6 0v2" />
              </svg>
            </div>
            <h2 class="text-base font-bold" style={{ color: 'var(--m3-on-surface)' }}>
              {t('webReverse.dashboard.title', 'Web 逆向调试面板')}
            </h2>
          </div>
          <button
            type="button"
            class="oh-pill-button"
            onClick={requestClose}
            aria-label={t('common.close', '关闭')}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </button>
        </header>

        <div class="px-6 py-5 space-y-4 max-h-[70vh] overflow-auto">
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t(
              'webReverse.dashboard.webOnlyHint',
              'Web 端只展示会话配置摘要。完整 CDP 实时数据 / 网络面板 / 控制台请在桌面应用中打开。',
            )}
          </p>

          {config ? (
            <div class="space-y-2 text-sm" style={{ color: 'var(--m3-on-surface)' }}>
              <Row label={t('webReverse.config.targetUrl', '目标 URL')} value={config.target_url ?? '-'} mono />
              <Row label={t('webReverse.config.objective', '逆向目标')} value={config.objective ?? '-'} />
              <Row label={t('webReverse.config.browser', '浏览器')} value={config.browser_kind ?? '-'} />
              <Row label={t('webReverse.config.cdpPort', 'CDP 端口')} value={String(config.cdp_port ?? '-')} mono />
              <Row label={t('webReverse.config.loginMode', '登录态')} value={config.login_mode ?? '-'} />
              {config.proxy ? <Row label={t('webReverse.config.proxy', '代理')} value={config.proxy} mono /> : null}
              {config.keywords && config.keywords.length > 0
                ? <Row label={t('webReverse.config.keywords', '关键关键字')} value={config.keywords.join(', ')} />
                : null}
              {config.trigger_actions
                ? <Row label={t('webReverse.config.triggerActions', '触发动作')} value={config.trigger_actions} />
                : null}
            </div>
          ) : (
            <div
              class="rounded-m3-sm border px-4 py-3 text-sm"
              style={{
                borderColor: 'var(--m3-outline-variant)',
                background: 'var(--m3-surface-container-high)',
                color: 'var(--m3-on-surface-variant)',
              }}
            >
              {t('webReverse.dashboard.noConfig', '该会话尚未写入 web_reverse_config。')}
            </div>
          )}
        </div>
      </section>
    </div>
  );

  return <OverlayPortal>{node}</OverlayPortal>;
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div class="flex items-start gap-3">
      <div
        class="text-xs uppercase tracking-wide pt-0.5 shrink-0 w-24"
        style={{ color: 'var(--m3-on-surface-variant)' }}
      >
        {label}
      </div>
      <div
        class={`text-sm break-all ${mono ? 'font-mono' : ''}`}
        style={{ color: 'var(--m3-on-surface)' }}
      >
        {value}
      </div>
    </div>
  );
}
