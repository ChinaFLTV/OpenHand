/** @jsxImportSource preact */
// Web 端 Android 逆向调试面板（只读摘要版）。

import { useMemo, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import type { SessionSummary } from '../api/sessions';
import {
  arrayFromUnknown,
  booleanFromUnknown,
  integerFromUnknown,
  recordFromUnknown,
  stringFromUnknown,
  stringListFromUnknown,
} from '../shared/util/value';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
  createDialogPanelSurfaceStyle,
} from './DialogFrame';

export interface AndroidReverseDashboardDialogProps {
  session: SessionSummary;
  onClose: () => void;
}

type AndroidReverseTab = 'status' | 'artifacts' | 'mcp' | 'config';
type RuntimeTone = 'ok' | 'warn' | 'muted';

interface AndroidReverseSummary {
  stateLabel: string;
  tone: RuntimeTone;
  deviceLabel: string;
  visibleDeviceCount: number;
  processCount: number;
  tabCount: number;
  actionCount: number;
  toolSearchQuery: string;
  relatedServerCount: number;
  relatedToolCount: number;
  pluginInstalledCount: number;
  pluginTotalCount: number;
  artifactRoot: string;
  quickScanDir: string;
  warning: string;
}

const artifactRows = [
  ['root_dir', '根目录'],
  ['logcat_jsonl', 'logcat.jsonl'],
  ['network_jsonl', 'network.jsonl'],
  ['packages_dir', 'APP 报告'],
  ['apks_dir', 'APK 拉取'],
  ['frida_scripts_dir', 'Frida 脚本'],
  ['frida_output_dir', 'Frida 输出'],
  ['decompiled_dir', '静态分析'],
  ['mcp_setup_guide', 'MCP 设置'],
  ['toolchain_setup_commands', '工具链命令'],
  ['certs_dir', '证书签名'],
  ['certs_readme', '证书说明'],
  ['verify_apk_signature_script', 'APK 验签'],
  ['scripts_dir', '复现脚本'],
  ['evidence_bundle_script', '证据包脚本'],
  ['evidence_bundle_glob', '证据包'],
] as const;

function runtimeSummaryFromMetadata(metadata: Record<string, unknown>): AndroidReverseSummary {
  const runtime = recordFromUnknown(metadata['android_reverse_runtime']);
  const config = recordFromUnknown(metadata['android_reverse_config']);
  const localArtifacts = recordFromUnknown(runtime['local_artifacts']);
  const connected = recordFromUnknown(runtime['connected_device']);
  const linkage = recordFromUnknown(runtime['mcp_plugin_linkage']);
  const mcp = recordFromUnknown(linkage['mcp']);
  const plugins = recordFromUnknown(linkage['plugin_runtime_prerequisites']);
  const state = stringFromUnknown(runtime['state']) || 'unknown';
  const running = booleanFromUnknown(runtime['is_running']);
  const visibleDeviceCount = arrayFromUnknown(runtime['visible_devices']).length;
  const connectedSerial = stringFromUnknown(connected['serial']);
  const configuredSerial = stringFromUnknown(runtime['configured_device_serial']) || stringFromUnknown(config['device_serial']);
  const deviceLabel = connectedSerial || configuredSerial || (visibleDeviceCount > 0 ? `${visibleDeviceCount} 台可见设备` : '无在线设备快照');
  const quickScan = recordFromUnknown(runtime['latest_static_quick_scan']);
  const latestQuickScanDir =
    stringFromUnknown(quickScan['dir']) ||
    stringFromUnknown(localArtifacts['latest_quick_scan_dir']);
  const tabCount = stringListFromUnknown(runtime['dashboard_tabs']).length;
  const actionCount = stringListFromUnknown(runtime['dashboard_actions']).length;
  const warning = stringFromUnknown(runtime['last_error']) || stringFromUnknown(mcp['error']) || stringFromUnknown(plugins['error']);

  return {
    stateLabel: running
      ? 'Android 会话运行中'
      : state === 'deviceLost'
        ? '设备已断开'
        : state === 'stopped'
          ? '会话已停止'
          : '等待桌面端运行态',
    tone: running ? 'ok' : state === 'deviceLost' || warning ? 'warn' : 'muted',
    deviceLabel,
    visibleDeviceCount,
    processCount: Math.max(0, integerFromUnknown(runtime['process_count'])),
    tabCount,
    actionCount,
    toolSearchQuery: stringFromUnknown(mcp['tool_search_recommended_query']) || 'select:adb,android,frida,ida,apktool,jadx',
    relatedServerCount: Math.max(0, integerFromUnknown(mcp['related_server_count'])),
    relatedToolCount: Math.max(0, integerFromUnknown(mcp['related_tool_count'])),
    pluginInstalledCount: Math.max(0, integerFromUnknown(plugins['installed_count'])),
    pluginTotalCount: arrayFromUnknown(plugins['plugins']).length,
    artifactRoot: stringFromUnknown(localArtifacts['root_dir']) || stringFromUnknown(runtime['artifacts_root_dir']) || '-',
    quickScanDir: latestQuickScanDir || '-',
    warning,
  };
}

export function AndroidReverseDashboardDialog({
  session,
  onClose,
}: AndroidReverseDashboardDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const metadata = session.metadata ?? {};
  const [tab, setTab] = useState<AndroidReverseTab>('status');
  const summary = useMemo(() => runtimeSummaryFromMetadata(metadata), [metadata]);

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
      panelClassName="w-full max-w-[820px] rounded-m3-lg overflow-hidden"
      panelStyle={createDialogPanelSurfaceStyle({ border: 'none' })}
      ariaLabel={t('androidReverse.dashboard.title', 'Android 逆向调试面板')}
    >
      <header
        class="px-6 py-4 flex items-center justify-between border-b"
        style={{ borderColor: 'var(--m3-outline-variant)' }}
      >
        <div class="flex items-center gap-3 min-w-0">
          <div
            class="w-10 h-10 rounded-m3-sm flex items-center justify-center shrink-0"
            style={{
              background: 'var(--m3-primary-container)',
              color: 'var(--m3-on-primary-container)',
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M7 8h10v8a3 3 0 0 1-3 3h-4a3 3 0 0 1-3-3z" />
              <path d="M9 8 7.5 5.5M15 8l1.5-2.5M8 12h.01M16 12h.01" />
            </svg>
          </div>
          <div class="min-w-0">
            <h2 class="text-base font-bold truncate" style={{ color: 'var(--m3-on-surface)' }}>
              {t('androidReverse.dashboard.title', 'Android 逆向调试面板')}
            </h2>
            <p class="text-xs mt-1 truncate" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {summary.deviceLabel}
            </p>
          </div>
        </div>
        <button type="button" class="oh-pill-button" onClick={requestClose} aria-label={t('common.close', '关闭')}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
            <path d="M18 6 6 18M6 6l12 12" />
          </svg>
        </button>
      </header>

      <div class="px-6 pt-4 flex flex-wrap gap-2 border-b" style={{ borderColor: 'var(--m3-outline-variant)' }}>
        <TabPill label="运行态" active={tab === 'status'} onClick={() => setTab('status')} />
        <TabPill label="本地工件" active={tab === 'artifacts'} onClick={() => setTab('artifacts')} />
        <TabPill label="MCP/插件" active={tab === 'mcp'} onClick={() => setTab('mcp')} />
        <TabPill label="任务配置" active={tab === 'config'} onClick={() => setTab('config')} />
      </div>

      <div class="px-6 py-5 space-y-4 max-h-[70vh] overflow-auto">
        {tab === 'status' ? <StatusTab summary={summary} metadata={metadata} /> : null}
        {tab === 'artifacts' ? <ArtifactsTab metadata={metadata} summary={summary} /> : null}
        {tab === 'mcp' ? <McpTab metadata={metadata} summary={summary} /> : null}
        {tab === 'config' ? <ConfigTab metadata={metadata} /> : null}
      </div>
    </DialogFrame>
  );
}

function StatusTab({ summary, metadata }: { summary: AndroidReverseSummary; metadata: Record<string, unknown> }) {
  const runtime = recordFromUnknown(metadata['android_reverse_runtime']);
  const devices = arrayFromUnknown(runtime['visible_devices']);
  return (
    <div class="space-y-4">
      <StatusPanel summary={summary} />
      <div class="grid gap-3 sm:grid-cols-4">
        <RuntimeMetric label="设备" value={String(summary.visibleDeviceCount)} />
        <RuntimeMetric label="进程" value={summary.processCount > 0 ? String(summary.processCount) : '-'} />
        <RuntimeMetric label="面板" value={summary.tabCount > 0 ? String(summary.tabCount) : '-'} />
        <RuntimeMetric label="动作" value={summary.actionCount > 0 ? String(summary.actionCount) : '-'} />
      </div>
      {devices.length > 0 ? (
        <Section title="可见设备">
          <div class="space-y-2">
            {devices.slice(0, 8).map((item, index) => {
              const device = recordFromUnknown(item);
              const serial = stringFromUnknown(device['serial']) || `device-${index + 1}`;
              const state = stringFromUnknown(device['state']) || '-';
              const model = stringFromUnknown(device['model']);
              return <Row key={`${serial}-${index}`} label={serial} value={[state, model].filter(Boolean).join(' · ')} mono />;
            })}
          </div>
        </Section>
      ) : null}
      <ReadonlyHint />
    </div>
  );
}

function ArtifactsTab({ metadata, summary }: { metadata: Record<string, unknown>; summary: AndroidReverseSummary }) {
  const runtime = recordFromUnknown(metadata['android_reverse_runtime']);
  const localArtifacts = recordFromUnknown(runtime['local_artifacts']);
  return (
    <div class="space-y-4">
      <Section title="工件索引">
        <div class="space-y-2">
          {artifactRows.map(([key, label]) => (
            <Row key={key} label={label} value={stringFromUnknown(localArtifacts[key]) || '-'} mono />
          ))}
          <Row label="quick_scan" value={summary.quickScanDir} mono />
        </div>
      </Section>
      <Section title="建议读取">
        <ChipList values={stringListFromUnknown(runtime['local_read_hints']).slice(0, 12)} mono />
      </Section>
    </div>
  );
}

function McpTab({ metadata, summary }: { metadata: Record<string, unknown>; summary: AndroidReverseSummary }) {
  const runtime = recordFromUnknown(metadata['android_reverse_runtime']);
  const linkage = recordFromUnknown(runtime['mcp_plugin_linkage']);
  const mcp = recordFromUnknown(linkage['mcp']);
  const plugins = recordFromUnknown(linkage['plugin_runtime_prerequisites']);
  const relatedServers = arrayFromUnknown(mcp['related_servers']);
  const pluginRows = arrayFromUnknown(plugins['plugins']);
  return (
    <div class="space-y-4">
      <div class="grid gap-3 sm:grid-cols-3">
        <RuntimeMetric label="相关 MCP" value={String(summary.relatedServerCount)} />
        <RuntimeMetric label="相关工具" value={String(summary.relatedToolCount)} />
        <RuntimeMetric label="运行时插件" value={`${summary.pluginInstalledCount}/${summary.pluginTotalCount || '-'}`} />
      </div>
      <Section title="ToolSearch 建议">
        <Row label="query" value={summary.toolSearchQuery} mono />
      </Section>
      {relatedServers.length > 0 ? (
        <Section title="相关 Server">
          <div class="space-y-2">
            {relatedServers.slice(0, 8).map((item, index) => {
              const server = recordFromUnknown(item);
              const name = stringFromUnknown(server['name']) || `server-${index + 1}`;
              const health = stringFromUnknown(server['health_status']);
              const catalog = stringFromUnknown(server['tool_catalog_status']);
              const tools = integerFromUnknown(server['android_related_tool_count']);
              return <Row key={`${name}-${index}`} label={name} value={`${health || '-'} · ${catalog || '-'} · Android tools ${tools}`} />;
            })}
          </div>
        </Section>
      ) : null}
      {pluginRows.length > 0 ? (
        <Section title="插件前置条件">
          <ChipList
            values={pluginRows.map((item) => {
              const plugin = recordFromUnknown(item);
              const id = stringFromUnknown(plugin['id']) || 'plugin';
              const status = stringFromUnknown(plugin['status']) || 'unknown';
              const actions = stringListFromUnknown(plugin['available_actions']);
              return `${id}: ${status}${actions.length > 0 ? ` · ${actions.join('/')}` : ''}`;
            })}
          />
        </Section>
      ) : null}
    </div>
  );
}

function ConfigTab({ metadata }: { metadata: Record<string, unknown> }) {
  const config = recordFromUnknown(metadata['android_reverse_config']);
  const keywords = stringListFromUnknown(config['keywords']);
  return (
    <div class="space-y-4">
      {Object.keys(config).length === 0 ? (
        <Section title="任务配置">
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>该会话尚未写入 android_reverse_config。</p>
        </Section>
      ) : (
        <Section title="任务配置">
          <div class="space-y-2">
            <Row label="目标" value={stringFromUnknown(config['objective']) || '-'} />
            <Row label="包名" value={stringFromUnknown(config['package_name']) || '-'} mono />
            <Row label="APK" value={stringFromUnknown(config['apk_path']) || '-'} mono />
            <Row label="设备" value={stringFromUnknown(config['device_serial']) || '自动选择'} mono />
            <Row label="分析模式" value={analysisModeLabel(stringFromUnknown(config['analysis_mode']))} />
            <Row label="授权范围" value={stringFromUnknown(config['authorization_scope']) || '-'} />
            <Row label="ADB MCP" value={booleanFromUnknown(config['adb_mcp_enabled']) ? '启用' : '关闭'} />
            <Row label="Frida MCP" value={booleanFromUnknown(config['frida_mcp_enabled']) ? '启用' : '关闭'} />
            {keywords.length > 0 ? <Row label="关键字" value={keywords.join(', ')} /> : null}
            {stringFromUnknown(config['notes']) ? <Row label="备注" value={stringFromUnknown(config['notes'])} /> : null}
          </div>
        </Section>
      )}
      <ReadonlyHint />
    </div>
  );
}

function analysisModeLabel(value: string): string {
  switch (value) {
    case 'static_first':
      return '静态优先';
    case 'dynamic_first':
      return '动态验证优先';
    case 'balanced':
      return '均衡分析';
    default:
      return value || '-';
  }
}

function StatusPanel({ summary }: { summary: AndroidReverseSummary }) {
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
    <section class="rounded-m3-sm border px-4 py-4" style={{ background: 'var(--m3-surface-container-low)', borderColor: 'var(--m3-outline-variant)' }}>
      <div class="flex flex-wrap items-center gap-2">
        <span class="inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold" style={toneStyle}>
          {summary.stateLabel}
        </span>
        <span class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
          {summary.deviceLabel}
        </span>
      </div>
      {summary.warning ? <div class="mt-3 text-xs leading-relaxed" style={{ color: 'var(--m3-error)' }}>{summary.warning}</div> : null}
    </section>
  );
}

function RuntimeMetric({ label, value }: { label: string; value: string }) {
  return (
    <div class="rounded-m3-sm border px-3 py-3" style={{ borderColor: 'var(--m3-outline-variant)', background: 'var(--m3-surface-container-high)' }}>
      <div class="text-xs font-semibold" style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</div>
      <div class="mt-1 text-sm font-bold break-all" style={{ color: 'var(--m3-on-surface)' }}>{value}</div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: ComponentChildren }) {
  return (
    <section class="rounded-m3-sm border px-4 py-3" style={{ borderColor: 'var(--m3-outline-variant)', background: 'var(--m3-surface-container-low)' }}>
      <div class="text-xs font-semibold mb-2.5" style={{ color: 'var(--m3-on-surface-variant)' }}>{title}</div>
      {children}
    </section>
  );
}

function ChipList({ values, mono }: { values: string[]; mono?: boolean }) {
  if (values.length === 0) {
    return <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>暂无数据。</p>;
  }
  return (
    <div class="flex flex-wrap gap-1.5">
      {values.map((value, index) => (
        <span
          key={`${value}-${index}`}
          class={`rounded-full px-2 py-1 text-[11px] ${mono ? 'font-mono' : 'font-semibold'}`}
          style={{ background: 'var(--m3-surface-container-high)', color: 'var(--m3-on-surface-variant)' }}
        >
          {value}
        </span>
      ))}
    </div>
  );
}

function ReadonlyHint() {
  return (
    <div class="rounded-m3-sm border px-4 py-3 text-sm leading-relaxed" style={{ borderColor: 'var(--m3-outline-variant)', background: 'var(--m3-surface-container-high)', color: 'var(--m3-on-surface-variant)' }}>
      Web 端仅展示只读摘要。设备管理、ADB Shell、Frida 注入、抓包、证书安装和 APK 签名操作请在桌面端 Android 逆向调试面板执行。
    </div>
  );
}

function TabPill({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      class="px-3 py-1.5 rounded-full text-sm font-semibold transition-colors"
      onClick={onClick}
      style={{
        background: active ? 'var(--m3-primary-container)' : 'transparent',
        color: active ? 'var(--m3-on-primary-container)' : 'var(--m3-on-surface-variant)',
        border: active ? '1px solid var(--m3-primary)' : '1px solid var(--m3-outline-variant)',
      }}
    >
      {label}
    </button>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div class="flex items-start gap-3">
      <div class="text-xs uppercase tracking-wide pt-0.5 shrink-0 w-24" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {label}
      </div>
      <div class={`text-sm break-all ${mono ? 'font-mono' : ''}`} style={{ color: 'var(--m3-on-surface)' }}>
        {value}
      </div>
    </div>
  );
}
