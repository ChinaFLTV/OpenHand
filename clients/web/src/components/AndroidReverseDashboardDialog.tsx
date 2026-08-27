import { useMemo, useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import type { SessionSummary } from '../api/sessions';
import {
  arrayFromUnknown,
  booleanFromUnknown,
  nonNegativeIntegerFromUnknown,
  recordFromUnknown,
  stringFromUnknown,
  stringListFromUnknown,
} from '../shared/util/value';
import {
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  DialogHeader,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import {
  DashboardChipList,
  DashboardHeaderIcon,
  DashboardInfoRow,
  DashboardMetric,
  DashboardReadonlyHint,
  DashboardSection,
  DashboardStatusPanel,
  DashboardTabPill,
  type DashboardTone,
} from './ReverseDashboardPrimitives';

interface AndroidReverseDashboardDialogProps {
  session: SessionSummary;
  onClose: () => void;
}

type AndroidReverseTab = 'status' | 'artifacts' | 'mcp' | 'config';

interface AndroidReverseSummary {
  stateLabel: string;
  tone: DashboardTone;
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
    processCount: nonNegativeIntegerFromUnknown(runtime['process_count']),
    tabCount,
    actionCount,
    toolSearchQuery: stringFromUnknown(mcp['tool_search_recommended_query']) || 'select:adb,android,frida,ida,apktool,jadx',
    relatedServerCount: nonNegativeIntegerFromUnknown(mcp['related_server_count']),
    relatedToolCount: nonNegativeIntegerFromUnknown(mcp['related_tool_count']),
    pluginInstalledCount: nonNegativeIntegerFromUnknown(plugins['installed_count']),
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
      {...createStandardDialogFrameAppearance({
        overlayTone: 'scrim',
        overlayBlurPx: 0,
        overlayZIndex: DIALOG_OVERLAY_TOP_Z_INDEX,
        panelClassName: 'w-full max-w-[820px] rounded-m3-lg overflow-hidden',
        panelBorder: 'none',
      })}
      ariaLabel={t('androidReverse.dashboard.title', 'Android 逆向调试面板')}
    >
      <DialogHeader
        title={t('androidReverse.dashboard.title', 'Android 逆向调试面板')}
        subtitle={summary.deviceLabel}
        titleClassName="text-base font-bold truncate"
        onClose={requestClose}
        closeLabel={t('common.close', '关闭')}
        closeClassName="oh-pill-button"
        closeIconSize={14}
        icon={
          <DashboardHeaderIcon>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M7 8h10v8a3 3 0 0 1-3 3h-4a3 3 0 0 1-3-3z" />
              <path d="M9 8 7.5 5.5M15 8l1.5-2.5M8 12h.01M16 12h.01" />
            </svg>
          </DashboardHeaderIcon>
        }
      />

      <div class="px-6 pt-4 flex flex-wrap gap-2 border-b" style={{ borderColor: 'var(--m3-outline-variant)' }}>
        <DashboardTabPill label="运行态" active={tab === 'status'} onClick={() => setTab('status')} />
        <DashboardTabPill label="本地工件" active={tab === 'artifacts'} onClick={() => setTab('artifacts')} />
        <DashboardTabPill label="MCP/插件" active={tab === 'mcp'} onClick={() => setTab('mcp')} />
        <DashboardTabPill label="任务配置" active={tab === 'config'} onClick={() => setTab('config')} />
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
      <DashboardStatusPanel
        tone={summary.tone}
        label={summary.stateLabel}
        detail={summary.deviceLabel}
        warning={summary.warning}
      />
      <div class="grid gap-3 sm:grid-cols-4">
        <DashboardMetric label="设备" value={String(summary.visibleDeviceCount)} />
        <DashboardMetric label="进程" value={summary.processCount > 0 ? String(summary.processCount) : '-'} />
        <DashboardMetric label="面板" value={summary.tabCount > 0 ? String(summary.tabCount) : '-'} />
        <DashboardMetric label="动作" value={summary.actionCount > 0 ? String(summary.actionCount) : '-'} />
      </div>
      {devices.length > 0 ? (
        <DashboardSection title="可见设备">
          <div class="space-y-2">
            {devices.slice(0, 8).map((item, index) => {
              const device = recordFromUnknown(item);
              const serial = stringFromUnknown(device['serial']) || `device-${index + 1}`;
              const state = stringFromUnknown(device['state']) || '-';
              const model = stringFromUnknown(device['model']);
              return <DashboardInfoRow key={`${serial}-${index}`} label={serial} value={[state, model].filter(Boolean).join(' · ')} mono />;
            })}
          </div>
        </DashboardSection>
      ) : null}
      <DashboardReadonlyHint>
        Web 端仅展示只读摘要。设备管理、ADB Shell、Frida 注入、抓包、证书安装和 APK 签名操作请在桌面端 Android 逆向调试面板执行。
      </DashboardReadonlyHint>
    </div>
  );
}

function ArtifactsTab({ metadata, summary }: { metadata: Record<string, unknown>; summary: AndroidReverseSummary }) {
  const runtime = recordFromUnknown(metadata['android_reverse_runtime']);
  const localArtifacts = recordFromUnknown(runtime['local_artifacts']);
  return (
    <div class="space-y-4">
      <DashboardSection title="工件索引">
        <div class="space-y-2">
          {artifactRows.map(([key, label]) => (
            <DashboardInfoRow key={key} label={label} value={stringFromUnknown(localArtifacts[key]) || '-'} mono />
          ))}
          <DashboardInfoRow label="quick_scan" value={summary.quickScanDir} mono />
        </div>
      </DashboardSection>
      <DashboardSection title="建议读取">
        <DashboardChipList values={stringListFromUnknown(runtime['local_read_hints']).slice(0, 12)} mono />
      </DashboardSection>
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
        <DashboardMetric label="相关 MCP" value={String(summary.relatedServerCount)} />
        <DashboardMetric label="相关工具" value={String(summary.relatedToolCount)} />
        <DashboardMetric label="运行时插件" value={`${summary.pluginInstalledCount}/${summary.pluginTotalCount || '-'}`} />
      </div>
      <DashboardSection title="ToolSearch 建议">
        <DashboardInfoRow label="query" value={summary.toolSearchQuery} mono />
      </DashboardSection>
      {relatedServers.length > 0 ? (
        <DashboardSection title="相关 Server">
          <div class="space-y-2">
            {relatedServers.slice(0, 8).map((item, index) => {
              const server = recordFromUnknown(item);
              const name = stringFromUnknown(server['name']) || `server-${index + 1}`;
              const health = stringFromUnknown(server['health_status']);
              const catalog = stringFromUnknown(server['tool_catalog_status']);
              const tools = nonNegativeIntegerFromUnknown(server['android_related_tool_count']);
              return <DashboardInfoRow key={`${name}-${index}`} label={name} value={`${health || '-'} · ${catalog || '-'} · Android tools ${tools}`} />;
            })}
          </div>
        </DashboardSection>
      ) : null}
      {pluginRows.length > 0 ? (
        <DashboardSection title="插件前置条件">
          <DashboardChipList
            values={pluginRows.map((item) => {
              const plugin = recordFromUnknown(item);
              const id = stringFromUnknown(plugin['id']) || 'plugin';
              const status = stringFromUnknown(plugin['status']) || 'unknown';
              const actions = stringListFromUnknown(plugin['available_actions']);
              return `${id}: ${status}${actions.length > 0 ? ` · ${actions.join('/')}` : ''}`;
            })}
          />
        </DashboardSection>
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
        <DashboardSection title="任务配置">
          <p class="text-sm oh-text-muted">该会话尚未写入 android_reverse_config。</p>
        </DashboardSection>
      ) : (
        <DashboardSection title="任务配置">
          <div class="space-y-2">
            <DashboardInfoRow label="目标" value={stringFromUnknown(config['objective']) || '-'} />
            <DashboardInfoRow label="包名" value={stringFromUnknown(config['package_name']) || '-'} mono />
            <DashboardInfoRow label="APK" value={stringFromUnknown(config['apk_path']) || '-'} mono />
            <DashboardInfoRow label="设备" value={stringFromUnknown(config['device_serial']) || '自动选择'} mono />
            <DashboardInfoRow label="分析模式" value={analysisModeLabel(stringFromUnknown(config['analysis_mode']))} />
            <DashboardInfoRow label="授权范围" value={stringFromUnknown(config['authorization_scope']) || '-'} />
            <DashboardInfoRow label="ADB MCP" value={booleanFromUnknown(config['adb_mcp_enabled']) ? '启用' : '关闭'} />
            <DashboardInfoRow label="Frida MCP" value={booleanFromUnknown(config['frida_mcp_enabled']) ? '启用' : '关闭'} />
            {keywords.length > 0 ? <DashboardInfoRow label="关键字" value={keywords.join(', ')} /> : null}
            {stringFromUnknown(config['notes']) ? <DashboardInfoRow label="备注" value={stringFromUnknown(config['notes'])} /> : null}
          </div>
        </DashboardSection>
      )}
      <DashboardReadonlyHint>
        Web 端仅展示只读摘要。设备管理、ADB Shell、Frida 注入、抓包、证书安装和 APK 签名操作请在桌面端 Android 逆向调试面板执行。
      </DashboardReadonlyHint>
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
