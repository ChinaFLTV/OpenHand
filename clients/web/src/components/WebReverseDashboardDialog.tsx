import { useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  DashboardHeaderIcon,
  DashboardInfoRow,
  DashboardMetric,
  DashboardReadonlyHint,
  DashboardStatusPanel,
  DashboardTabPill,
  type DashboardTone,
} from './ReverseDashboardPrimitives';
import {
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  DialogHeader,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import { t } from '../i18n';
import type { SessionSummary } from '../api/sessions';
import { strictPositiveIntegerFromUnknown } from '../shared/util/number';
import {
  booleanOrNullFromUnknown,
  recordOrNullFromUnknown as asRecord,
  strictStringFromUnknown as stringFromUnknown,
  stringListFromUnknown,
} from '../shared/util/value';

interface WebReverseDashboardDialogProps {
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

interface WebReverseRuntimeSummary {
  browserState: string;
  bridgeState: string;
  port: string;
  toolCount: string;
  route: string;
  nextAction: string;
  artifactRoot: string;
  networkJsonl: string;
  consoleJsonl: string;
  currentToolNames: string[];
  deferredToolNames: string[];
  warning: string;
  tone: DashboardTone;
}

function asConfig(raw: unknown): WebReverseConfig | null {
  return asRecord(raw) as WebReverseConfig | null;
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
  const localArtifacts = asRecord(runtime?.['local_artifacts']);
  const browserAlive =
    booleanOrNullFromUnknown(currentCdpRuntime?.['browser_alive']) ??
    booleanOrNullFromUnknown(bridge?.['browser_alive']) ??
    booleanOrNullFromUnknown(availability?.['browser_runtime_live']);
  const currentToolNames = stringListFromUnknown(
    availability?.['current_turn_callable_names'],
  );
  const deferredToolNames = stringListFromUnknown(
    availability?.['tool_search_deferred_cdp_mcp_names'],
  );
  const toolCount =
    strictPositiveIntegerFromUnknown(bridge?.['tool_count']) ??
    strictPositiveIntegerFromUnknown(
      availability?.['current_turn_callable_count'],
    ) ??
    strictPositiveIntegerFromUnknown(
      availability?.['tool_search_deferred_cdp_mcp_count'],
    );
  const currentCallable =
    booleanOrNullFromUnknown(
      availability?.['live_cdp_actions_current_turn_callable'],
    ) === true ||
    booleanOrNullFromUnknown(availability?.['current_turn_callable']) === true;
  const hasDeferredCdpTools =
    deferredToolNames.length > 0 ||
    (strictPositiveIntegerFromUnknown(
      availability?.['tool_search_deferred_cdp_mcp_count'],
    ) ??
      0) > 0;
  const route =
    currentCallable
      ? 'CDP 工具可直接调用'
      : hasDeferredCdpTools
        ? 'ToolSearch 待加载'
        : browserAlive === true
          ? '等待 CDP MCP'
          : '离线工件模式';
  const rawBridgeStatus = stringFromUnknown(bridge?.['status']);
  const port =
    strictPositiveIntegerFromUnknown(currentCdpRuntime?.['cdp_port']) ??
    strictPositiveIntegerFromUnknown(bridge?.['cdp_port']);
  const bridgeReady =
    booleanOrNullFromUnknown(bridge?.['live_actions_callable']) === true ||
    rawBridgeStatus === 'ready';
  const nextAction =
    stringFromUnknown(availability?.['tool_search_recommended_query']) ||
    (currentCallable
      ? '使用当前工具目录中的 CDP / js-reverse MCP 工具做 Observe。'
      : hasDeferredCdpTools
        ? '先调用 ToolSearch 加载 deferred CDP / js-reverse MCP 工具。'
        : browserAlive === true
          ? '等待桌面端完成 transient chrome-devtools-mcp 准备，或读取本地 jsonl/HAR。'
          : '读取本地 jsonl/HAR，或在桌面端重启 Web 逆向浏览器。');

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
    nextAction,
    artifactRoot: stringFromUnknown(localArtifacts?.['root_dir']) || '-',
    networkJsonl: stringFromUnknown(localArtifacts?.['network_jsonl']) || '-',
    consoleJsonl: stringFromUnknown(localArtifacts?.['console_jsonl']) || '-',
    currentToolNames,
    deferredToolNames,
    warning:
      stringFromUnknown(availability?.['warning']) ||
      stringFromUnknown(runtime?.['cdp_runtime_warning']),
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
      {...createStandardDialogFrameAppearance({
        overlayTone: 'scrim',
        overlayBlurPx: 0,
        overlayZIndex: DIALOG_OVERLAY_TOP_Z_INDEX,
        panelClassName: 'w-full max-w-[760px] rounded-m3-lg overflow-hidden',
        panelBorder: 'none',
      })}
      ariaLabel={t('webReverse.dashboard.title', 'Web 逆向调试面板')}
    >
      <DialogHeader
        title={t('webReverse.dashboard.title', 'Web 逆向调试面板')}
        titleClassName="text-base font-bold"
        onClose={requestClose}
        closeLabel={t('common.close', '关闭')}
        closeClassName="oh-pill-button"
        closeIconSize={14}
        icon={
          <DashboardHeaderIcon>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="6" y="9" width="12" height="10" rx="3" />
              <path d="M9 9V7a3 3 0 0 1 6 0v2" />
            </svg>
          </DashboardHeaderIcon>
        }
      />

        <div
          class="px-6 pt-4 flex gap-2 border-b"
          style={{ borderColor: 'var(--m3-outline-variant)' }}
        >
          <DashboardTabPill
            label={t('webReverse.tab.browser', 'CDP 状态')}
            active={tab === 'browser'}
            onClick={() => setTab('browser')}
          />
          <DashboardTabPill
            label={t('webReverse.tab.overview', '任务配置')}
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

function BrowserTab({ metadata }: { metadata: Record<string, unknown> }) {
  const summary = runtimeSummaryFromMetadata(metadata);

  return (
    <div class="space-y-4">
      <DashboardStatusPanel
        tone={summary.tone}
        label={summary.browserState}
        detail={summary.bridgeState}
        warning={summary.warning}
      />
      <div class="grid gap-3 sm:grid-cols-3">
        <DashboardMetric label={t('webReverse.runtime.port', 'CDP 端口')} value={summary.port} />
        <DashboardMetric label={t('webReverse.runtime.tools', 'CDP 工具')} value={summary.toolCount} />
        <DashboardMetric label={t('webReverse.runtime.route', '调用路径')} value={summary.route} />
      </div>
      <NextActionPanel summary={summary} />
      <ArtifactPanel summary={summary} />
      <DashboardReadonlyHint>
        {t(
          'webReverse.browser.webReadonly',
          'Web 端仅展示只读摘要。目标源取证必须走桌面端 CDP 面板、CDP MCP、本地 jsonl 或 HAR，不使用 WebFetch/WebSearch/Bash/curl 直接抓目标源。',
        )}
      </DashboardReadonlyHint>
    </div>
  );
}

function NextActionPanel({ summary }: { summary: WebReverseRuntimeSummary }) {
  const visibleTools =
    summary.currentToolNames.length > 0
      ? summary.currentToolNames
      : summary.deferredToolNames;
  return (
    <section
      class="rounded-m3-sm border px-4 py-3"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-low)',
      }}
    >
      <div class="text-xs font-semibold oh-text-muted">
        {t('webReverse.runtime.nextAction', '下一步')}
      </div>
      <div class="mt-1 text-sm font-semibold oh-text-body">
        {summary.nextAction}
      </div>
      {visibleTools.length > 0 ? (
        <div class="mt-3 flex flex-wrap gap-1.5">
          {visibleTools.slice(0, 8).map((name) => (
            <span
              key={name}
              class="rounded-full px-2 py-1 text-[11px] font-mono"
              style={{
                background: 'var(--m3-surface-container-high)',
                color: 'var(--m3-on-surface-variant)',
              }}
            >
              {name}
            </span>
          ))}
        </div>
      ) : null}
    </section>
  );
}

function ArtifactPanel({ summary }: { summary: WebReverseRuntimeSummary }) {
  return (
    <section
      class="rounded-m3-sm border px-4 py-3 text-sm"
      style={{
        borderColor: 'var(--m3-outline-variant)',
        background: 'var(--m3-surface-container-high)',
      }}
    >
      <div class="text-xs font-semibold oh-text-muted">
        {t('webReverse.runtime.artifacts', '本地工件')}
      </div>
      <div class="mt-2 space-y-1.5">
        <DashboardInfoRow label={t('webReverse.runtime.artifactRoot', '目录')} value={summary.artifactRoot} mono />
        <DashboardInfoRow label="network.jsonl" value={summary.networkJsonl} mono />
        <DashboardInfoRow label="console.jsonl" value={summary.consoleJsonl} mono />
      </div>
    </section>
  );
}

function OverviewTab({ config }: { config: WebReverseConfig | null }) {
  return (
    <>
      <p class="text-sm oh-text-muted">
        {t(
          'webReverse.dashboard.webOnlyHint',
          'Web 端只展示会话配置摘要。完整 CDP 实时数据 / 网络面板 / 控制台请在桌面应用中打开。',
        )}
      </p>
      {config ? (
        <div class="space-y-2 text-sm oh-text-body">
          <DashboardInfoRow label={t('webReverse.config.targetUrl', '目标 URL')} value={config.target_url ?? '-'} mono />
          <DashboardInfoRow label={t('webReverse.config.objective', '逆向目标')} value={config.objective ?? '-'} />
          <DashboardInfoRow label={t('webReverse.config.browser', '浏览器')} value={config.browser_kind ?? '-'} />
          <DashboardInfoRow label={t('webReverse.config.cdpPort', 'CDP 端口')} value={String(config.cdp_port ?? '-')} mono />
          <DashboardInfoRow label={t('webReverse.config.loginMode', '登录态')} value={config.login_mode ?? '-'} />
          {config.proxy ? <DashboardInfoRow label={t('webReverse.config.proxy', '代理')} value={config.proxy} mono /> : null}
          {config.keywords && config.keywords.length > 0
            ? <DashboardInfoRow label={t('webReverse.config.keywords', '关键字')} value={config.keywords.join(', ')} />
            : null}
          {config.trigger_actions
            ? <DashboardInfoRow label={t('webReverse.config.triggerActions', '触发动作')} value={config.trigger_actions} />
            : null}
          {config.har_path ? <DashboardInfoRow label="HAR" value={config.har_path} mono /> : null}
          {config.user_data_dir ? <DashboardInfoRow label={t('webReverse.config.profile', 'Profile 目录')} value={config.user_data_dir} mono /> : null}
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
