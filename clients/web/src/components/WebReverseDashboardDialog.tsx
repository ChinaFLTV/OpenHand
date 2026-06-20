/** @jsxImportSource preact */
// Web 端 Web 逆向调试面板（只读摘要版）。

import { useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
  createDialogPanelSurfaceStyle,
} from './DialogFrame';
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
  har_path?: string;
}

type WebReverseTab = 'browser' | 'overview';
type RuntimeTone = 'ok' | 'warn' | 'muted';

interface WebReverseRuntimeSummary {
  browserState: string;
  bridgeState: string;
  port: string;
  toolCount: string;
  route: string;
  tone: RuntimeTone;
}

function asRecord(raw: unknown): Record<string, unknown> | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  return raw as Record<string, unknown>;
}

function asConfig(raw: unknown): WebReverseConfig | null {
  return asRecord(raw) as WebReverseConfig | null;
}

function stringFromUnknown(raw: unknown): string {
  return typeof raw === 'string' ? raw.trim() : '';
}

function numberFromUnknown(raw: unknown): number | null {
  if (typeof raw === 'number' && Number.isFinite(raw)) return raw;
  if (typeof raw !== 'string') return null;
  const parsed = Number.parseInt(raw.trim(), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function booleanFromUnknown(raw: unknown): boolean | null {
  if (typeof raw === 'boolean') return raw;
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
    return true;
  }
  if (normalized === 'false' || normalized === '0' || normalized === 'no') {
    return false;
  }
  return null;
}

function runtimeSummaryFromMetadata(
  metadata: Record<string, unknown>,
): WebReverseRuntimeSummary {
  const runtime = asRecord(metadata['web_reverse_runtime']);
  const currentCdpRuntime =
    asRecord(metadata['web_reverse_cdp_runtime']) ??
    asRecord(runtime?.['cdp_runtime']);
  const bridge = asRecord(currentCdpRuntime?.['cdp_mcp_bridge']);
  const availability = asRecord(runtime?.['cdp_mcp_tool_availability']);
  const browserAlive =
    booleanFromUnknown(currentCdpRuntime?.['browser_alive']) ??
    booleanFromUnknown(bridge?.['browser_alive']) ??
    booleanFromUnknown(availability?.['browser_runtime_live']);
  const toolCount =
    numberFromUnknown(bridge?.['tool_count']) ??
    numberFromUnknown(availability?.['current_turn_callable_count']) ??
    numberFromUnknown(availability?.['tool_search_deferred_cdp_mcp_count']);
  const currentCallable =
    booleanFromUnknown(
      availability?.['live_cdp_actions_current_turn_callable'],
    ) === true ||
    booleanFromUnknown(availability?.['current_turn_callable']) === true;
  const route =
    currentCallable
      ? '当前轮可调用'
      : booleanFromUnknown(availability?.['tool_search_available']) === true
        ? 'ToolSearch 延迟加载'
        : '只读摘要';
  const rawBridgeStatus = stringFromUnknown(bridge?.['status']);
  const port =
    numberFromUnknown(currentCdpRuntime?.['cdp_port']) ??
    numberFromUnknown(bridge?.['cdp_port']);
  const bridgeReady =
    booleanFromUnknown(bridge?.['live_actions_callable']) === true ||
    rawBridgeStatus === 'ready';

  return {
    browserState:
      browserAlive === true
        ? 'CDP 浏览器在线'
        : browserAlive === false
          ? 'CDP 浏览器离线'
          : '未收到运行态',
    bridgeState: bridgeReady
      ? 'CDP MCP 已就绪'
      : rawBridgeStatus || '等待桌面端运行态',
    port: port != null && port > 0 ? String(port) : '-',
    toolCount: toolCount != null && toolCount > 0 ? String(toolCount) : '-',
    route,
    tone: browserAlive === true
      ? 'ok'
      : browserAlive === false
        ? 'warn'
        : 'muted',
  };
}

export function WebReverseDashboardDialog({
  session,
  onClose,
}: WebReverseDashboardDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const metadata = session.metadata ?? {};
  const config = asConfig(metadata['web_reverse_config']);
  const [tab, setTab] = useState<WebReverseTab>('overview');

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      overlayClassName={DIALOG_OVERLAY_CENTER_CLASS}
      overlayStyle={createDialogOverlayStyle({
        background: 'var(--m3-scrim-bg)',
        blurPx: 0,
        zIndex: DIALOG_OVERLAY_TOP_Z_INDEX,
      })}
      panelClassName="w-full max-w-[760px] rounded-m3-lg overflow-hidden"
      panelStyle={createDialogPanelSurfaceStyle({
        border: 'none',
      })}
      ariaLabel={t('webReverse.dashboard.title', 'Web 逆向调试面板')}
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
            <BrowserTab metadata={metadata} />
          ) : (
            <OverviewTab config={config} />
          )}
        </div>
    </DialogFrame>
  );
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

function BrowserTab({ metadata }: { metadata: Record<string, unknown> }) {
  const summary = runtimeSummaryFromMetadata(metadata);

  return (
    <div class="space-y-4">
      <StatusPanel summary={summary} />
      <div class="grid gap-3 sm:grid-cols-3">
        <RuntimeMetric label={t('webReverse.runtime.port', 'CDP 端口')} value={summary.port} />
        <RuntimeMetric label={t('webReverse.runtime.tools', 'CDP 工具')} value={summary.toolCount} />
        <RuntimeMetric label={t('webReverse.runtime.route', '调用路径')} value={summary.route} />
      </div>
      <div
        class="rounded-m3-sm border px-4 py-3 text-sm leading-relaxed"
        style={{
          borderColor: 'var(--m3-outline-variant)',
          background: 'var(--m3-surface-container-high)',
          color: 'var(--m3-on-surface-variant)',
        }}
      >
        {t(
          'webReverse.browser.webReadonly',
          'Web 端仅展示只读摘要。目标源取证必须走桌面端 CDP 面板、CDP MCP、本地 jsonl 或 HAR，不使用 WebFetch/WebSearch/Bash/curl 直接抓目标源。',
        )}
      </div>
    </div>
  );
}

function StatusPanel({ summary }: { summary: WebReverseRuntimeSummary }) {
  const toneStyle =
    summary.tone === 'ok'
      ? {
          background: 'color-mix(in srgb, var(--m3-primary) 12%, transparent)',
          color: 'var(--m3-primary)',
          borderColor: 'color-mix(in srgb, var(--m3-primary) 34%, transparent)',
        }
      : summary.tone === 'warn'
        ? {
            background: 'color-mix(in srgb, var(--m3-error) 12%, transparent)',
            color: 'var(--m3-error)',
            borderColor: 'color-mix(in srgb, var(--m3-error) 34%, transparent)',
          }
        : {
            background: 'var(--m3-surface-container-high)',
            color: 'var(--m3-on-surface-variant)',
            borderColor: 'var(--m3-outline-variant)',
          };

  return (
    <section
      class="rounded-m3-sm border px-4 py-4"
      style={{
        background: 'var(--m3-surface-container-low)',
        borderColor: 'var(--m3-outline-variant)',
      }}
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold"
          style={toneStyle}
        >
          {summary.browserState}
        </span>
        <span
          class="text-sm"
          style={{ color: 'var(--m3-on-surface-variant)' }}
        >
          {summary.bridgeState}
        </span>
      </div>
    </section>
  );
}

function RuntimeMetric({ label, value }: { label: string; value: string }) {
  return (
    <div
      class="rounded-m3-sm border px-3 py-3"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-high)',
      }}
    >
      <div class="text-xs font-semibold" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {label}
      </div>
      <div class="mt-1 text-sm font-bold break-all" style={{ color: 'var(--m3-on-surface)' }}>
        {value}
      </div>
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
            ? <Row label={t('webReverse.config.keywords', '关键字')} value={config.keywords.join(', ')} />
            : null}
          {config.trigger_actions
            ? <Row label={t('webReverse.config.triggerActions', '触发动作')} value={config.trigger_actions} />
            : null}
          {config.har_path ? <Row label="HAR" value={config.har_path} mono /> : null}
          {config.user_data_dir ? <Row label={t('webReverse.config.profile', 'Profile 目录')} value={config.user_data_dir} mono /> : null}
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
