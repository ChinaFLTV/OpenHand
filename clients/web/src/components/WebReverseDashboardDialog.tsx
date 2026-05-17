/** @jsxImportSource preact */
// Web 端 Web 逆向调试面板（精简版）。
//
// 与桌面端的不同：浏览器进程、CDP 通道、screencast 输入桥都跑在桌面 App 上；
// Web 客户端无法复用同一条 CDP（需要本地端口转发 / 鉴权，超出本端能力）。
// 本对话框给 Web 用户提供：
//   - 顶部胶囊行：浏览器（提示需桌面端）/ 概览（配置摘要）
//   - 默认展示概览；点击「浏览器」胶囊提示需到桌面端使用
//   - 与官方 DevTools 协同操作的指引
// 提示模型 / 真实 CDP 数据流仍由桌面 App 端的 dashboard 持有。

import { useState } from 'preact/hooks';
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

type WebReverseTab = 'browser' | 'overview';

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
  const [tab, setTab] = useState<WebReverseTab>('overview');

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

        <div
          class="px-6 pt-4 flex gap-2 border-b"
          style={{ borderColor: 'var(--m3-outline-variant)' }}
        >
          <TabPill
            label={t('webReverse.tab.browser', '浏览器')}
            active={tab === 'browser'}
            onClick={() => setTab('browser')}
          />
          <TabPill
            label={t('webReverse.tab.overview', '概览')}
            active={tab === 'overview'}
            onClick={() => setTab('overview')}
          />
        </div>

        <div class="px-6 py-5 space-y-4 max-h-[70vh] overflow-auto">
          {tab === 'browser' ? (
            <BrowserTab />
          ) : (
            <OverviewTab config={config} />
          )}
        </div>
      </section>
    </div>
  );

  return <OverlayPortal>{node}</OverlayPortal>;
}

function TabPill({
  label,
  active,
  onClick,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      class="px-3 py-1.5 rounded-full text-sm font-semibold transition-colors"
      onClick={onClick}
      style={{
        background: active
          ? 'var(--m3-primary-container)'
          : 'transparent',
        color: active
          ? 'var(--m3-on-primary-container)'
          : 'var(--m3-on-surface-variant)',
        border: active
          ? '1px solid var(--m3-primary)'
          : '1px solid var(--m3-outline-variant)',
      }}
    >
      {label}
    </button>
  );
}

function BrowserTab() {
  return (
    <div
      class="rounded-m3-sm border px-4 py-5 text-sm leading-relaxed"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-high)',
        color: 'var(--m3-on-surface)',
      }}
    >
      <div class="font-semibold mb-2">
        {t('webReverse.browser.heading', '内嵌浏览器需在桌面端使用')}
      </div>
      <p style={{ color: 'var(--m3-on-surface-variant)' }}>
        {t(
          'webReverse.browser.body',
          '内嵌浏览器面板基于 CDP screencast + Input 桥实时画面与键鼠 IME 输入，需要桌面应用直连本机 Chrome 进程。请在 OpenHand 桌面应用中打开本会话切到「浏览器」tab 操作。',
        )}
      </p>
      <ul
        class="mt-3 list-disc pl-5 space-y-1"
        style={{ color: 'var(--m3-on-surface-variant)' }}
      >
        <li>
          {t(
            'webReverse.browser.bulletTabs',
            'Tab strip 支持多 page target 切换 / 长按拖动重排 / 关闭 / 新建，顺序与最后 URL 写入 session metadata 跨重启复原。',
          )}
        </li>
        <li>
          {t(
            'webReverse.browser.bulletControl',
            '地址栏：左侧 prefix 历史下拉（最近 30 条）；右侧常驻「缩放 / 分辨率 / 设备模拟 / 保存当前帧 / 聚焦 / 重启 / 停止」按钮。自适应帧率（30fps@大视窗 / 60fps@常规）。',
          )}
        </li>
        <li>
          {t(
            'webReverse.browser.bulletShortcuts',
            '键盘热键：Cmd/Ctrl + T/W/R/Shift+R/L/F/Esc/+/-/0 实现新建 / 关闭 / 刷新 / 强刷 / 聚焦地址栏 / 查找 / 关查找 / 缩放档位 / 复位。',
          )}
        </li>
        <li>
          {t(
            'webReverse.browser.bulletRecover',
            '浏览器进程异常退出会自动切到「重启浏览器」占位，2 秒一次的存活探针主动兜底；重启后自动复原 tab 与 URL。',
          )}
        </li>
        <li>
          {t(
            'webReverse.browser.bulletContextMenu',
            '右键菜单：复制 / 粘贴 / 全选 / 刷新 / 检查元素 / 外部打开 / 保存当前帧 / 框选导出局部帧。',
          )}
        </li>
        <li>
          {t(
            'webReverse.browser.bulletExtra',
            '应用 tab 可编辑 Cookies / LocalStorage / SessionStorage；记录器 tab 一键导出 puppeteer / playwright；高级菜单新增「网络拦截规则」（URL 通配 → block / 重写 / 注入 header）。',
          )}
        </li>
        <li>
          {t(
            'webReverse.browser.bulletPersistence',
            'Sources 断点 + Console REPL 历史按会话持久化；Network 单条请求支持「编辑后重放」改写 URL / Headers 后再 replay；Performance 面板一键导出 FPS + Long task CSV；Shift+? 弹快捷键速查面板。',
          )}
        </li>
      </ul>
    </div>
  );
}

function OverviewTab({ config }: { config: WebReverseConfig | null }) {
  return (
    <>
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
    </>
  );
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
