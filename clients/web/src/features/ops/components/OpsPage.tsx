// OpsPage —— 运行时仪表盘 + 资源清理。对应后端 /api/ops & /api/ops/cleanup*
//
// - 顶部状态徽章 + 刷新按钮 + 自动刷新切换（5s）
// - 网格指标：state / uptime / 请求 / 错误 / 字节 / 进程 RSS / 文件句柄 …
// - 清理面板：target=all/logs/uploads + expired_only 复选框 + 历史列表

import { useEffect, useMemo, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import {
  type CleanupHistoryEntry,
  type OpsRuntimeSnapshot,
  getCleanupHistory,
  getOpsSnapshot,
  runCleanup,
} from '../../../api/ops';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { t, tBytes, tDateTime, tDuration, tFmt, tPlural } from '../../../i18n';
import { MenuSelect } from '../../../components/MenuSelect';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import { showSnackbar } from '../../../components/Snackbar';
import { TopBar } from '../../../components/TopBar';
import { describeApiError } from '../../../utils/api_error';
import { clampNumber, normalizeInteger } from '../../../shared/util/number';

const REFRESH_INTERVAL_MS = 5_000;

interface OpsHealthSignal {
  label: string;
  value: string;
  tone: 'ok' | 'warn' | 'error' | 'neutral';
}

interface OpsHealthAlert {
  label: string;
  threshold: string;
  actual: string;
  severity: 'warn' | 'error';
}

interface OpsHealthSummary {
  score: number;
  label: string;
  tone: 'ok' | 'warn' | 'error';
  signals: OpsHealthSignal[];
  alerts: OpsHealthAlert[];
  recommendations: string[];
}

function percent(value: number): string {
  return `${(value * 100).toFixed(value >= 0.1 ? 1 : 2)} %`;
}

function buildOpsHealth(snapshot: OpsRuntimeSnapshot): OpsHealthSummary {
  let score = 100;
  const recommendations: string[] = [];
  const alerts: OpsHealthAlert[] = [];
  const totalRequests = Math.max(snapshot.total_requests, 0);
  const totalErrors = Math.min(Math.max(snapshot.total_errors, 0), totalRequests);
  const blockedRequests = Math.min(
    Math.max(snapshot.blocked_requests ?? 0, 0),
    totalErrors,
  );
  const failedRequests = totalErrors - blockedRequests;
  const errorRate = totalRequests > 0 ? failedRequests / totalRequests : 0;
  const saturation = snapshot.active_request_ratio ?? 0;
  const p95 = snapshot.latency_stats?.p95_ms ?? 0;
  const p99 = snapshot.latency_stats?.p99_ms ?? 0;
  const trafficSeries = snapshot.traffic_series;
  const latestTraffic = trafficSeries && trafficSeries.length > 0
    ? trafficSeries[trafficSeries.length - 1]
    : undefined;
  const failuresPerMinute = latestTraffic?.failed ?? snapshot.errors_per_minute ?? 0;
  const logErrors = snapshot.log_level_breakdown?.error ?? snapshot.log_level_breakdown?.ERROR ?? 0;

  if (snapshot.state === 'crashed') {
    score -= 45;
    alerts.push({ label: t('ops.alert.state', '服务状态'), threshold: 'running', actual: snapshot.state, severity: 'error' });
    recommendations.push(t('ops.health.fixCrashed', '服务处于 crashed，优先查看最近错误和内存日志并重启服务。'));
  } else if (snapshot.state !== 'running') {
    score -= 20;
    alerts.push({ label: t('ops.alert.state', '服务状态'), threshold: 'running', actual: snapshot.state, severity: 'warn' });
    recommendations.push(t('ops.health.fixNotRunning', '服务未处于 running，确认监听端口、鉴权配置和启动日志。'));
  }
  if (errorRate >= 0.05) {
    score -= 25;
    alerts.push({ label: t('ops.alert.errorRate', '错误率'), threshold: '>= 5 %', actual: percent(errorRate), severity: 'error' });
    recommendations.push(t('ops.health.fixErrorRateHigh', '错误率超过 5%，优先按最近错误路径定位 4xx/5xx 来源。'));
  } else if (errorRate >= 0.01) {
    score -= 12;
    alerts.push({ label: t('ops.alert.errorRate', '错误率'), threshold: '>= 1 %', actual: percent(errorRate), severity: 'warn' });
    recommendations.push(t('ops.health.fixErrorRateWarn', '错误率超过 1%，建议核对请求来源、模型服务和文件权限。'));
  }
  if (failuresPerMinute > 0) {
    score -= Math.min(15, 5 + failuresPerMinute * 2);
    alerts.push({ label: t('ops.alert.errorsPerMinute', '失败/min'), threshold: '> 0', actual: failuresPerMinute.toFixed(1), severity: 'warn' });
    recommendations.push(t('ops.health.fixRecentErrors', '最近 1 分钟仍有错误增长，观察错误是否持续并检查对应路由。'));
  }
  if (saturation >= 0.85) {
    score -= 20;
    alerts.push({ label: t('ops.alert.saturation', '并发水位'), threshold: '>= 85 %', actual: percent(saturation), severity: 'error' });
    recommendations.push(t('ops.health.fixSaturationHigh', '并发水位接近上限，建议降低长连接/轮询压力或提高并发限制。'));
  } else if (saturation >= 0.6) {
    score -= 10;
    alerts.push({ label: t('ops.alert.saturation', '并发水位'), threshold: '>= 60 %', actual: percent(saturation), severity: 'warn' });
    recommendations.push(t('ops.health.fixSaturationWarn', '并发水位偏高，继续观察请求排队和 SSE 连接数。'));
  }
  if (p95 >= 3000) {
    score -= 15;
    alerts.push({ label: t('ops.alert.p95', 'P95 延迟'), threshold: '>= 3000 ms', actual: `${p95} ms`, severity: 'error' });
    recommendations.push(t('ops.health.fixLatencyHigh', 'P95 延迟超过 3s，建议检查慢路由、上游模型和文件 IO。'));
  } else if (p95 >= 1000) {
    score -= 8;
    alerts.push({ label: t('ops.alert.p95', 'P95 延迟'), threshold: '>= 1000 ms', actual: `${p95} ms`, severity: 'warn' });
    recommendations.push(t('ops.health.fixLatencyWarn', 'P95 延迟超过 1s，可结合 Top Routes 排查热点路径。'));
  }
  if (snapshot.crash_count > 0 || snapshot.restart_count > 0) {
    score -= Math.min(12, snapshot.crash_count * 6 + snapshot.restart_count * 2);
    alerts.push({ label: t('ops.alert.restart', '崩溃/重启'), threshold: '= 0', actual: `${snapshot.crash_count}/${snapshot.restart_count}`, severity: snapshot.crash_count > 0 ? 'error' : 'warn' });
  }
  if (logErrors > 0) {
    score -= Math.min(10, logErrors);
    alerts.push({ label: t('ops.alert.logError', '错误日志'), threshold: '= 0', actual: String(logErrors), severity: 'warn' });
  }
  if (recommendations.length === 0) {
    recommendations.push(t('ops.health.keepWatch', '当前核心信号平稳，保持自动刷新并关注错误率、P95 延迟和并发水位。'));
  }
  score = Math.round(clampNumber(score, 0, 100));
  const tone: OpsHealthSummary['tone'] = score >= 85 ? 'ok' : score >= 65 ? 'warn' : 'error';
  const label = tone === 'ok'
    ? t('ops.health.good', '健康')
    : tone === 'warn'
      ? t('ops.health.watch', '需关注')
      : t('ops.health.bad', '异常');
  return {
    score,
    label,
    tone,
    recommendations: recommendations.slice(0, 4),
    alerts,
    signals: [
      { label: t('ops.health.signal.errorRate', '错误率'), value: percent(errorRate), tone: errorRate >= 0.05 ? 'error' : errorRate >= 0.01 ? 'warn' : 'ok' },
      { label: t('ops.health.signal.p95', 'P95 延迟'), value: p95 > 0 ? `${p95} ms` : '—', tone: p95 >= 3000 ? 'error' : p95 >= 1000 ? 'warn' : 'ok' },
      { label: t('ops.health.signal.p99', 'P99 延迟'), value: p99 > 0 ? `${p99} ms` : '—', tone: p99 >= 5000 ? 'error' : p99 >= 2000 ? 'warn' : 'ok' },
      { label: t('ops.health.signal.saturation', '并发水位'), value: percent(saturation), tone: saturation >= 0.85 ? 'error' : saturation >= 0.6 ? 'warn' : 'ok' },
      { label: t('ops.health.signal.errorsPerMin', '失败/min'), value: failuresPerMinute.toFixed(1), tone: failuresPerMinute > 0 ? 'warn' : 'ok' },
      { label: t('ops.health.signal.sse', 'SSE'), value: String(snapshot.active_sse_subscriptions ?? 0), tone: 'neutral' },
    ],
  };
}

export function OpsPage() {
  const location = useAnimatedLocation();
  const [snapshot, setSnapshot] = useState<OpsRuntimeSnapshot | null>(null);
  const [snapError, setSnapError] = useState<string | null>(null);
  const [snapLoading, setSnapLoading] = useState(false);
  const [history, setHistory] = useState<CleanupHistoryEntry[]>([]);
  const [historyCapacity, setHistoryCapacity] = useState<number | null>(null);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [cleanupTarget, setCleanupTarget] = useState<'all' | 'logs' | 'uploads'>('all');
  const [expiredOnly, setExpiredOnly] = useState(true);
  const [cleaning, setCleaning] = useState(false);
  const [cleanupConfirmOpen, setCleanupConfirmOpen] = useState(false);
  const [cleanupError, setCleanupError] = useState<string | null>(null);
  const [cleanupOk, setCleanupOk] = useState<string | null>(null);

  const refreshSnapshot = async (
    isActive: () => boolean = () => true,
    signal?: AbortSignal,
  ) => {
    setSnapLoading(true);
    setSnapError(null);
    try {
      const s = await getOpsSnapshot({ signal });
      if (!isActive()) return;
      setSnapshot(s);
    } catch (err) {
      if (isActive()) setSnapError(describeApiError(err));
    } finally {
      if (isActive()) setSnapLoading(false);
    }
  };

  const refreshHistory = async (
    isActive: () => boolean = () => true,
    signal?: AbortSignal,
  ) => {
    setHistoryError(null);
    try {
      const h = await getCleanupHistory({ signal });
      if (!isActive()) return;
      setHistory(h.items);
      setHistoryCapacity(normalizeInteger(h.max_items, {
        fallback: h.items.length,
        min: h.items.length,
        max: 10_000,
      }));
    } catch (err) {
      if (isActive()) setHistoryError(describeApiError(err));
    }
  };

  // 初次加载
  useEffect(() => {
    let stopped = false;
    const controller = new AbortController();
    const isActive = () => !stopped;
    void refreshSnapshot(isActive, controller.signal);
    void refreshHistory(isActive, controller.signal);
    return () => {
      stopped = true;
      controller.abort();
    };
  }, []);

  useAsyncPolling((isActive, signal) => refreshSnapshot(isActive, signal), {
    enabled: autoRefresh,
    immediate: false,
    intervalMs: REFRESH_INTERVAL_MS,
    onError: (err) => {
      setSnapError(describeApiError(err));
      setSnapLoading(false);
    },
  });

  const handleCleanup = async (): Promise<boolean> => {
    if (cleaning) return false;
    setCleaning(true);
    setCleanupError(null);
    setCleanupOk(null);
    try {
      showSnackbar(t('ops.cleanup.started', '正在执行资源清理…'));
      const res = await runCleanup({ target: cleanupTarget, expired_only: expiredOnly });
      // 默认模板使用 tPlural 拼装文件 / 目录单复数，
      // 字节量走 tBytes 以使用当前语言的千分位 / 小数点习惯。
      const resultText = tFmt('ops.cleanup.result', {
        target: res.target,
        files: tPlural('ops.cleanup.files', res.deleted_files),
        dirs: tPlural('ops.cleanup.dirs', res.deleted_directories),
        bytes: tBytes(res.bytes_freed),
      });
      setCleanupOk(resultText);
      showSnackbar(resultText, { tone: 'success' });
      await refreshHistory();
      await refreshSnapshot();
      return true;
    } catch (err) {
      const message = describeApiError(err);
      setCleanupError(message);
      showSnackbar(`${t('ops.cleanup.failed', '资源清理失败')}：${message}`, { tone: 'error' });
      return false;
    } finally {
      setCleaning(false);
    }
  };

  const cleanupTargetLabel =
    cleanupTarget === 'logs'
      ? t('ops.cleanup.target.logs', '仅日志')
      : cleanupTarget === 'uploads'
        ? t('ops.cleanup.target.uploads', '仅上传缓存')
        : t('ops.cleanup.target.all', '全部');

  const stateBadge = useMemo(() => snapshot?.state ?? 'stopped', [snapshot?.state]);
  const health = useMemo(() => snapshot ? buildOpsHealth(snapshot) : null, [snapshot]);
  const totalRequests = Math.max(snapshot?.total_requests ?? 0, 0);
  const totalErrors = Math.min(
    Math.max(snapshot?.total_errors ?? 0, 0),
    totalRequests,
  );
  const blockedRequests = Math.min(
    Math.max(snapshot?.blocked_requests ?? 0, 0),
    totalErrors,
  );
  const failedRequests = totalErrors - blockedRequests;
  const successfulRequests = totalRequests - totalErrors;
  const peerDistribution = snapshot?.peer_distribution
    && Object.keys(snapshot.peer_distribution).length > 0
    ? snapshot.peer_distribution
    : snapshot?.ip_distribution;
  const subtitle = snapshot
    ? `${t('ops.metric.uptime', '运行时长')} ${tDuration(snapshot.uptime_ms)} · ${t('ops.metric.totalReq', '总请求')} ${snapshot.total_requests}`
    : snapLoading
      ? t('common.loading', '加载中…')
      : t('ops.subtitle', '运行时状态、请求指标与资源清理');

  return (
    <main class="oh-ops-page min-h-screen p-4 sm:p-6">
      <div class="max-w-7xl mx-auto">
        <TopBar
          title={t('ops.title', 'Ops 运行时仪表盘')}
          subtitle={subtitle}
          hideNav
          leadingSlot={(
            <button
              type="button"
              onClick={() => location.route('/')}
              class="oh-tap-press oh-topbar-action text-sm rounded-m3-sm px-3 py-1.5"
            >
              ← {t('ops.backHome', '返回首页')}
            </button>
          )}
          actionSlot={(
            <>
              <span class={`oh-ops-state-pill is-${stateBadge}`}>
                <span aria-hidden />
                {stateBadge}
              </span>
              <label class="oh-ops-auto-refresh">
                <input
                  type="checkbox"
                  checked={autoRefresh}
                  onChange={(ev) => setAutoRefresh((ev.target as HTMLInputElement).checked)}
                />
                <span>{t('ops.autoRefresh', '自动刷新 5s')}</span>
              </label>
              <button
                type="button"
                onClick={() => void refreshSnapshot()}
                disabled={snapLoading}
                class="oh-tap-press oh-topbar-action text-sm rounded-m3-sm px-3 py-1.5 disabled:opacity-60"
              >
                {snapLoading ? t('common.loading') : t('common.refresh', '刷新')}
              </button>
            </>
          )}
        />

        {snapError && (
          <p class="oh-admin-status is-error mb-3">
            {snapError}
          </p>
        )}

        {snapshot && (
          <>
            {health && <OpsHealthPanel health={health} />}

            {/* 运行指标 */}
            <section class="oh-appear-up oh-ops-panel oh-ops-metric-grid mb-3">
              <Metric label={t('ops.metric.startedAt', '启动时间')} value={tDateTime(snapshot.started_at)} />
              <Metric label={t('ops.metric.uptime', '运行时长')} value={tDuration(snapshot.uptime_ms)} />
              <Metric label={t('ops.metric.bound', '监听 URL')} value={snapshot.bound_url || '—'} mono />
              <Metric label={t('ops.metric.openSessions', '会话总数')} value={String(snapshot.open_session_count)} />
              {typeof snapshot.current_connections === 'number' && (
                <Metric label={t('ops.metric.connections', '当前连接数')} value={String(snapshot.current_connections)} />
              )}
              <Metric label={t('ops.metric.activeReq', '正在处理')} value={String(snapshot.active_requests)} />
              {typeof snapshot.max_concurrent_requests === 'number' && snapshot.max_concurrent_requests > 0 && (
                <Metric
                  label={t('ops.metric.requestLimit', '并发上限 / 饱和度')}
                  value={`${snapshot.max_concurrent_requests} / ${(((snapshot.active_request_ratio ?? 0) * 100)).toFixed(1)} %`}
                />
              )}
              {typeof snapshot.active_sse_subscriptions === 'number' && (
                <Metric label={t('ops.metric.activeSse', 'SSE 长连接')}
                  value={String(snapshot.active_sse_subscriptions)} />
              )}
              {typeof snapshot.mcp_server_total_count === 'number' && (
                <Metric label={t('ops.metric.mcpServers', 'MCP 启用 / 总数')}
                  value={`${snapshot.mcp_server_enabled_count ?? 0} / ${snapshot.mcp_server_total_count}`} />
              )}
              <Metric label={t('ops.metric.totalReq', '总请求')} value={String(snapshot.total_requests)} />
              <Metric label={t('ops.metric.succeeded', '成功数量')} value={String(successfulRequests)} />
              <Metric label={t('ops.metric.blocked', '拦截数量')} value={String(blockedRequests)} />
              <Metric label={t('ops.metric.failed', '失败数量')} value={String(failedRequests)} />
              {typeof snapshot.file_mutation_count === 'number' && (
                <Metric label={t('ops.metric.fileMutations', '文件变动')} value={String(snapshot.file_mutation_count)} />
              )}
              <Metric label={t('ops.metric.bytesIO', '字节 IN / OUT')}
                value={`${tBytes(snapshot.total_bytes_in)} / ${tBytes(snapshot.total_bytes_out)}`} />
              <Metric label={t('ops.metric.crash', '崩溃 / 重启')} value={`${snapshot.crash_count} / ${snapshot.restart_count}`} />
              <Metric label={t('ops.metric.rss', '当前 / 峰值 RSS')}
                value={`${tBytes(snapshot.process.current_rss_bytes)} / ${tBytes(snapshot.process.max_rss_bytes)}`} />
              <Metric label={t('ops.metric.cpu', 'CPU %')}
                value={snapshot.process.cpu_percent != null ? `${snapshot.process.cpu_percent.toFixed(1)} %` : '—'} />
              <Metric label={t('ops.metric.thread', '线程 / 句柄')}
                value={`${snapshot.process.thread_count ?? '—'} / ${snapshot.process.file_handle_count ?? '—'}`} />
              <Metric label={t('ops.metric.swap', 'Swap')} value={tBytes(snapshot.process.swap_bytes)} />
              <Metric label={t('ops.metric.diskLog', '磁盘日志')} value={tBytes(snapshot.process.disk_log_bytes)} />
              <Metric label={t('ops.metric.platform', '平台')}
                value={`${snapshot.process.platform} (${snapshot.process.platform_version})`} mono />
              <Metric label={t('ops.metric.pid', 'PID')} value={String(snapshot.process.pid)} mono />
              {(snapshot.process.dart_version || snapshot.process.host_name) && (
                <>
                  <Metric label={t('ops.metric.dartVersion', 'Dart 版本')}
                    value={(snapshot.process.dart_version || '—').split(' ')[0]} mono />
                  <Metric label={t('ops.metric.hostName', '主机名')}
                    value={snapshot.process.host_name || '—'} mono />
                </>
              )}
              {typeof snapshot.requests_per_minute === 'number' && (
                <Metric label={t('ops.metric.rpm', '近 1 分钟 RPM')}
                  value={snapshot.requests_per_minute.toFixed(1)} />
              )}
              {typeof snapshot.errors_per_minute === 'number' && (
                <Metric label={t('ops.metric.errPerMin', '近 1 分钟错误')}
                  value={snapshot.errors_per_minute.toFixed(0)} />
              )}
              {(typeof snapshot.bytes_in_per_minute === 'number' || typeof snapshot.bytes_out_per_minute === 'number') && (
                <Metric
                  label={t('ops.metric.bytesPerMin', '近 1 分钟 IN / OUT')}
                  value={`${tBytes(snapshot.bytes_in_per_minute ?? 0)} / ${tBytes(snapshot.bytes_out_per_minute ?? 0)}`}
                />
              )}
              {snapshot.total_requests > 0 && (
                <Metric label={t('ops.metric.errorRate', '失败率')}
                  value={`${((failedRequests / snapshot.total_requests) * 100).toFixed(2)} %`} />
              )}
              {typeof snapshot.allowed_model_count === 'number' && (
                <Metric
                  label={t('ops.metric.models', '模型 / 服务商')}
                  value={`${snapshot.allowed_model_count} / ${snapshot.model_provider_count ?? 0}`}
                />
              )}
              {typeof snapshot.template_count === 'number' && (
                <Metric label={t('ops.metric.templates', '模板')} value={String(snapshot.template_count)} />
              )}
              {typeof snapshot.cron_total_count === 'number' && (
                <Metric
                  label={t('ops.metric.crons', '定时任务启用 / 总数')}
                  value={`${snapshot.cron_enabled_count ?? 0} / ${snapshot.cron_total_count}`}
                />
              )}
              {typeof snapshot.memory_entry_count === 'number' && (
                <Metric label={t('ops.metric.memoryEntries', '记忆条目')} value={String(snapshot.memory_entry_count)} />
              )}
            </section>

            {/* HTTP 状态码 / 方法分布 */}
            {(snapshot.status_code_breakdown || snapshot.method_breakdown) && (
              <section class="oh-appear-up rounded-m3-md p-4 mb-3 grid grid-cols-1 md:grid-cols-2 gap-4"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                {snapshot.status_code_breakdown && (
                  <div>
                    <p class="text-xs mb-2 oh-text-muted">
                      {t('ops.section.statusBreakdown', 'HTTP 状态码分布')}
                    </p>
                    <div class="flex flex-wrap gap-2">
                      {Object.entries(snapshot.status_code_breakdown).map(([k, v]) => {
                        const tone = k === '5xx'
                          ? 'var(--m3-error)'
                          : k === '4xx'
                            ? 'var(--m3-tertiary)'
                            : k === '2xx'
                              ? 'var(--m3-primary)'
                              : 'var(--m3-on-surface-variant)';
                        return (
                          <span
                            key={k}
                            class="text-xs font-mono px-2 py-1 rounded-m3-sm"
                            style={{
                              backgroundColor: 'var(--m3-surface)',
                              color: tone,
                              border: `1px solid ${tone}`,
                            }}
                          >
                            {k} · {v}
                          </span>
                        );
                      })}
                    </div>
                  </div>
                )}
                {snapshot.method_breakdown && (
                  <div>
                    <p class="text-xs mb-2 oh-text-muted">
                      {t('ops.section.methodBreakdown', 'HTTP Method 分布')}
                    </p>
                    <div class="flex flex-wrap gap-2">
                      {Object.entries(snapshot.method_breakdown).map(([k, v]) => (
                        <span
                          key={k}
                          class="text-xs font-mono px-2 py-1 rounded-m3-sm"
                          style={{
                            backgroundColor: 'var(--m3-surface)',
                            color: 'var(--m3-on-surface)',
                            border: '1px solid var(--m3-outline)',
                          }}
                        >
                          {k} · {v}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </section>
            )}

            {(peerDistribution
              || snapshot.client_distribution
              || snapshot.request_distribution
              || snapshot.protocol_distribution) && (
              <section
                class="oh-appear-up rounded-m3-md p-4 mb-3 grid grid-cols-1 md:grid-cols-2 gap-4"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                {peerDistribution && (
                  <BreakdownBlock title={t('ops.section.peerMix', '来源端点（IP:端口）')} data={peerDistribution} />
                )}
                {snapshot.client_distribution && (
                  <BreakdownBlock title={t('ops.section.clientMix', '客户端 UA 分布')} data={snapshot.client_distribution} />
                )}
                {snapshot.request_distribution && (
                  <BreakdownBlock title={t('ops.section.requestMix', '请求分布')} data={snapshot.request_distribution} />
                )}
                {snapshot.protocol_distribution && (
                  <BreakdownBlock title={t('ops.section.protocolMix', '协议分布')} data={snapshot.protocol_distribution} />
                )}
              </section>
            )}

            {/* 延迟分位数 */}
            {snapshot.latency_stats && snapshot.latency_stats.sample_count > 0 && (
              <section class="oh-appear-up rounded-m3-md p-4 mb-3"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                <p class="text-xs mb-2 oh-text-muted">
                  {t('ops.section.latency', '请求延迟分位数')} · {t('ops.latency.sample', '样本')} {snapshot.latency_stats.sample_count}
                </p>
                <div class="grid grid-cols-2 sm:grid-cols-5 gap-2">
                  {([
                    ['avg', snapshot.latency_stats.avg_ms],
                    ['p50', snapshot.latency_stats.p50_ms],
                    ['p95', snapshot.latency_stats.p95_ms],
                    ['p99', snapshot.latency_stats.p99_ms],
                    ['max', snapshot.latency_stats.max_ms],
                  ] as const).map(([k, v]) => (
                    <div
                      key={k}
                      class="px-3 py-2 rounded-m3-sm"
                      style={{
                        backgroundColor: 'var(--m3-surface)',
                        border: '1px solid var(--m3-outline)',
                      }}
                    >
                      <p class="text-[10px] uppercase tracking-wider oh-text-muted">
                        {k}
                      </p>
                      <p class="font-mono text-sm oh-text-body">{v} ms</p>
                    </div>
                  ))}
                </div>
                {snapshot.latency_buckets && Object.values(snapshot.latency_buckets).some((v) => v > 0) ? (
                  <div class="mt-3">
                    <p class="text-xs mb-2 oh-text-muted">
                      {t('ops.section.latencyBuckets', '延迟分布桶')}
                    </p>
                    <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-2">
                      {Object.entries(snapshot.latency_buckets).map(([label, count]) => (
                        <div
                          key={label}
                          class="px-2 py-1.5 rounded-m3-sm"
                          style={{
                            backgroundColor: 'var(--m3-surface)',
                            border: '1px solid var(--m3-outline)',
                          }}
                        >
                          <p class="text-[10px] oh-text-muted">{label}</p>
                          <p class="font-mono text-sm oh-text-body">{count}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}
              </section>
            )}

            {/* 运行阶段 / 日志级别 */}
            {(snapshot.send_phase_breakdown || snapshot.log_level_breakdown) && (
              <section class="oh-appear-up rounded-m3-md p-4 mb-3 grid grid-cols-1 md:grid-cols-2 gap-4"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                {snapshot.send_phase_breakdown && (
                  <BreakdownBlock
                    title={t('ops.section.sendPhaseBreakdown', '会话发送阶段分布')}
                    data={snapshot.send_phase_breakdown}
                  />
                )}
                {snapshot.log_level_breakdown && (
                  <BreakdownBlock
                    title={[
                      `${t('ops.section.logLevelBreakdown', '日志级别分布')} · ${snapshot.memory_log_count ?? 0}`,
                      `${t('ops.fileLogPending', '待写')} ${snapshot.file_log_pending_writes ?? 0}`,
                      `${t('ops.fileLogDropped', '丢弃')} ${snapshot.file_log_dropped_writes ?? 0}`,
                    ].join(' / ')}
                    data={snapshot.log_level_breakdown}
                    dangerKeys={['error', 'warn']}
                  />
                )}
              </section>
            )}

            {/* 热点路由 Top N */}
            {snapshot.top_routes && snapshot.top_routes.length > 0 && (
              <section class="oh-appear-up rounded-m3-md p-4 mb-3"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                <p class="text-xs mb-2 oh-text-muted">
                  {t('ops.section.topRoutes', '热点路由 Top')}
                </p>
                <div class="space-y-1">
                  {(() => {
                    const max = Math.max(...snapshot.top_routes!.map((r) => r.count), 1);
                    return snapshot.top_routes!.map((r) => (
                      <div key={r.path} class="flex items-center gap-2">
                        <span class="font-mono text-xs flex-1 truncate oh-text-body">
                          {r.path}
                        </span>
                        <div
                          class="h-2 rounded"
                          style={{
                            width: `${(r.count / max) * 100}%`,
                            maxWidth: '60%',
                            backgroundColor: 'var(--m3-primary)',
                            opacity: 0.6,
                          }}
                        />
                        <span class="font-mono text-xs w-12 text-right oh-text-muted">
                          {r.count}
                        </span>
                      </div>
                    ));
                  })()}
                </div>
              </section>
            )}

            {/* 近期最慢请求 + 上次错误 */}
            {(snapshot.slowest_recent || snapshot.last_error_at) && (
              <section class="oh-appear-up rounded-m3-md p-4 mb-3 grid grid-cols-1 md:grid-cols-2 gap-4"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                {snapshot.slowest_recent && (
                  <div>
                    <p class="text-xs mb-1 oh-text-muted">
                      {t('ops.section.slowestRecent', '近期最慢请求')}
                    </p>
                    <p class="font-mono text-sm oh-text-body">
                      {snapshot.slowest_recent.method} {snapshot.slowest_recent.path}
                    </p>
                    <p class="text-xs mt-1 oh-text-muted">
                      {snapshot.slowest_recent.duration_ms} ms · HTTP {snapshot.slowest_recent.status_code} · {tDateTime(snapshot.slowest_recent.at)}
                    </p>
                  </div>
                )}
                {snapshot.last_error_at && (
                  <div>
                    <p class="text-xs mb-1 oh-text-muted">
                      {t('ops.section.lastError', '上次错误')}
                    </p>
                    <p class="font-mono text-sm oh-text-error">
                      {snapshot.last_error_path || '—'}
                    </p>
                    <p class="text-xs mt-1 oh-text-muted">
                      {tDateTime(snapshot.last_error_at)}
                    </p>
                  </div>
                )}
              </section>
            )}

            {/* 最近错误环：倒序列出最近 4xx/5xx 请求，便于第一时间发现问题 */}
            {snapshot.recent_errors && snapshot.recent_errors.length > 0 && (
              <section
                class="oh-appear-up rounded-m3-md p-4 mb-3"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                <p class="text-xs mb-2 oh-text-muted">
                  {t('ops.section.recentErrors', '最近错误')} · {snapshot.recent_errors.length}
                </p>
                <ul class="space-y-1.5">
                  {[...snapshot.recent_errors].reverse().map((e, idx) => (
                    <li
                      key={`${e.at}-${idx}`}
                      class="flex flex-wrap gap-x-2 gap-y-0.5 items-baseline text-xs font-mono px-2 py-1.5 rounded-m3-sm"
                      style={{
                        backgroundColor: 'var(--m3-surface)',
                        borderLeft: `3px solid ${e.status >= 500 ? 'var(--m3-error)' : 'color-mix(in srgb, var(--m3-error) 55%, transparent)'}`,
                      }}
                    >
                      <span
                        class="px-1.5 rounded text-[10px] font-bold"
                        style={{
                          backgroundColor: e.status >= 500 ? 'var(--m3-error)' : 'color-mix(in srgb, var(--m3-error) 18%, transparent)',
                          color: e.status >= 500 ? 'var(--m3-on-error)' : 'var(--m3-error)',
                        }}
                      >
                        {e.status}
                      </span>
                      <span class="oh-text-muted">{e.method}</span>
                      <span class="oh-text-body">{e.path}</span>
                      <span class="ml-auto oh-text-muted">
                        {e.duration_ms} ms · {tDateTime(e.at)}
                      </span>
                      {e.message && (
                        <span class="basis-full pl-1 oh-text-error">
                          {e.message}
                        </span>
                      )}
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {snapshot.last_error && (
              <p
                class="text-sm mb-3 px-3 py-2 rounded-m3-sm font-mono"
                style={{
                  backgroundColor: 'var(--m3-surface)',
                  color: 'var(--m3-error)',
                  border: '1px solid var(--m3-error)',
                }}
              >
                last_error: {snapshot.last_error}
              </p>
            )}

            {snapshot.accessible_urls.length > 0 && (
              <section class="oh-appear-up rounded-m3-md p-3 mb-3"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                <p class="text-xs mb-2 oh-text-muted">
                  {t('ops.accessibleUrls', '可访问 URL')}
                </p>
                <div class="flex flex-wrap gap-1">
                  {snapshot.accessible_urls.map((u) => (
                    <span
                      key={u}
                      class="text-xs px-2 py-0.5 rounded-m3-sm font-mono"
                      style={{ backgroundColor: 'var(--m3-surface)', color: 'var(--m3-on-surface)' }}
                    >
                      {u}
                    </span>
                  ))}
                </div>
              </section>
            )}
          </>
        )}

        {/* 清理面板 */}
        <section class="oh-appear-up oh-ops-panel mb-3">
          <h2 class="text-base font-semibold mb-3 oh-text-body">
            {t('ops.cleanup.title', '资源清理')}
          </h2>
          <div class="flex items-center gap-3 flex-wrap mb-3">
            <MenuSelect
              label={`${t('ops.cleanup.target', '目标')}：`}
              value={cleanupTarget}
              onChange={(v) => setCleanupTarget(v as 'all' | 'logs' | 'uploads')}
              options={[
                { value: 'all', label: t('ops.cleanup.target.all', '全部') },
                { value: 'logs', label: t('ops.cleanup.target.logs', '仅日志') },
                { value: 'uploads', label: t('ops.cleanup.target.uploads', '仅上传缓存') },
              ]}
            />
            <label class="text-sm flex items-center gap-1 oh-text-muted">
              <input
                type="checkbox"
                checked={expiredOnly}
                onChange={(ev) => setExpiredOnly((ev.target as HTMLInputElement).checked)}
              />
              {t('ops.cleanup.expiredOnly', '仅清理过期项')}
            </label>
            <button
              type="button"
              onClick={() => setCleanupConfirmOpen(true)}
              disabled={cleaning}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{
                color: 'var(--m3-on-primary)',
                backgroundColor: 'var(--m3-primary)',
                opacity: cleaning ? 0.6 : 1,
              }}
            >
              {cleaning ? t('ops.cleanup.running', '清理中…') : t('ops.cleanup.execute', '立即清理')}
            </button>
          </div>
          {cleanupError && (
            <p class="text-sm oh-text-error">
              {cleanupError}
            </p>
          )}
          {cleanupOk && (
            <p class="text-sm oh-text-primary">
              ✓ {cleanupOk}
            </p>
          )}
        </section>

        {cleanupConfirmOpen ? (
          <ConfirmDialog
            title={t('ops.cleanup.confirmTitle', '执行资源清理?')}
            body={tFmt('ops.cleanup.confirmBody', {
              target: cleanupTargetLabel,
              scope: expiredOnly
                ? t('ops.cleanup.scope.expired', '仅过期项')
                : t('ops.cleanup.scope.all', '全部匹配项'),
            })}
            danger={!expiredOnly || cleanupTarget === 'all'}
            busy={cleaning}
            confirmBeforeClose
            confirmLabel={cleaning ? t('ops.cleanup.running', '清理中…') : t('ops.cleanup.execute', '立即清理')}
            cancelLabel={t('common.cancel', '取消')}
            onCancel={() => setCleanupConfirmOpen(false)}
            onConfirm={handleCleanup}
            onConfirmSuccess={() => setCleanupConfirmOpen(false)}
          />
        ) : null}

        {/* 历史 */}
        <section class="oh-appear-up oh-ops-panel">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-base font-semibold oh-text-body">
              {historyCapacity == null
                ? t('ops.cleanup.historyTitle', '清理历史')
                : tFmt(
                    'ops.cleanup.history',
                    { count: historyCapacity },
                    '清理历史（最多 {count} 条）',
                  )}
            </h2>
            <button
              type="button"
              onClick={() => void refreshHistory()}
              class="text-xs px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              {t('common.refresh', '刷新')}
            </button>
          </div>
          {historyError && (
            <p class="text-sm oh-text-error">
              {historyError}
            </p>
          )}
          {history.length === 0 ? (
            <p class="text-sm oh-text-muted">
              {t('ops.cleanup.empty', '暂无历史记录')}
            </p>
          ) : (
            <div class="overflow-x-auto -mx-4 px-4">
              <table class="w-full text-sm" style={{ minWidth: '640px' }}>
                <thead>
                  <tr class="oh-text-muted">
                    <th class="text-left py-1 px-2">{t('ops.cleanup.col.time', '时间')}</th>
                    <th class="text-left py-1 px-2">{t('ops.cleanup.col.target', '目标')}</th>
                    <th class="text-left py-1 px-2">{t('ops.cleanup.col.expired', '仅过期')}</th>
                    <th class="text-right py-1 px-2">{t('ops.cleanup.col.files', '文件')}</th>
                    <th class="text-right py-1 px-2">{t('ops.cleanup.col.dirs', '目录')}</th>
                    <th class="text-right py-1 px-2">{t('ops.cleanup.col.bytes', '释放')}</th>
                    <th class="text-right py-1 px-2">{t('ops.cleanup.col.memLog', '内存日志')}</th>
                  </tr>
                </thead>
                <tbody>
                  {history.map((h, idx) => (
                    <tr key={idx} class="oh-text-body">
                      <td class="py-1 px-2 font-mono text-xs">{tDateTime(h.timestamp)}</td>
                      <td class="py-1 px-2">{h.target}</td>
                      <td class="py-1 px-2">{h.expired_only ? '✓' : '—'}</td>
                      <td class="py-1 px-2 text-right">{h.deleted_files}</td>
                      <td class="py-1 px-2 text-right">{h.deleted_directories}</td>
                      <td class="py-1 px-2 text-right">{tBytes(h.bytes_freed)}</td>
                      <td class="py-1 px-2 text-right">{h.memory_log_entries_cleared}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </div>
    </main>
  );
}

function healthToneColor(tone: OpsHealthSignal['tone'] | OpsHealthSummary['tone']): string {
  if (tone === 'ok') return '#15803d';
  if (tone === 'warn') return '#b45309';
  if (tone === 'error') return 'var(--m3-error)';
  return 'var(--m3-on-surface-variant)';
}

function OpsHealthPanel({ health }: { health: OpsHealthSummary }) {
  const color = healthToneColor(health.tone);
  return (
    <section
      class="oh-appear-up oh-ops-health-panel mb-3"
      data-tone={health.tone}
      style={{
        border: `1px solid color-mix(in srgb, ${color} 32%, transparent)`,
      }}
    >
      <div class="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <p class="text-xs mb-1 oh-text-muted">
            {t('ops.health.title', '运行健康度')}
          </p>
          <div class="flex items-baseline gap-2">
            <strong class="text-3xl" style={{ color }}>{health.score}</strong>
            <span class="text-sm font-semibold" style={{ color }}>{health.label}</span>
          </div>
        </div>
        <div class="flex flex-wrap gap-2 justify-end">
          {health.signals.map((signal) => {
            const signalColor = healthToneColor(signal.tone);
            return (
              <span
                key={signal.label}
                class="text-xs px-2 py-1 rounded-m3-sm"
                style={{
                  color: signalColor,
                  background: 'var(--m3-surface)',
                  border: `1px solid color-mix(in srgb, ${signalColor} 28%, transparent)`,
                }}
              >
                {signal.label}: <strong>{signal.value}</strong>
              </span>
            );
          })}
        </div>
      </div>
      <div class="mt-3 grid grid-cols-1 md:grid-cols-2 gap-2">
        {health.recommendations.map((item) => (
          <p
            key={item}
            class="text-xs rounded-m3-sm px-3 py-2"
            style={{
              color: 'var(--m3-on-surface)',
              background: 'var(--m3-surface)',
              border: '1px solid var(--m3-outline)',
            }}
          >
            {item}
          </p>
        ))}
      </div>
      <div class="mt-3 rounded-m3-sm p-3" style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline)' }}>
        <p class="text-xs mb-2 oh-text-muted">
          {t('ops.alert.title', '阈值告警')}
        </p>
        {health.alerts.length === 0 ? (
          <p class="text-xs oh-text-muted">
            {t('ops.alert.empty', '暂无触发阈值')}
          </p>
        ) : (
          <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
            {health.alerts.map((alert) => {
              const alertColor = healthToneColor(alert.severity);
              return (
                <div
                  key={`${alert.label}-${alert.threshold}`}
                  class="rounded-m3-sm px-3 py-2 text-xs"
                  style={{
                    color: alertColor,
                    background: 'color-mix(in srgb, currentColor 8%, transparent)',
                    border: `1px solid color-mix(in srgb, ${alertColor} 35%, transparent)`,
                  }}
                >
                  <strong>{alert.label}</strong>
                  <span class="oh-text-muted"> · {alert.threshold}</span>
                  <span> · {alert.actual}</span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </section>
  );
}

function Metric(props: { label: string; value: string; mono?: boolean }) {
  return (
    <div class="oh-ops-metric-card">
      <p class="oh-ops-metric-label">
        {props.label}
      </p>
      <p
        class={`oh-ops-metric-value ${props.mono ? 'font-mono' : 'font-semibold'} truncate`}
        title={props.value}
      >
        {props.value}
      </p>
    </div>
  );
}

function BreakdownBlock({
  title,
  data,
  dangerKeys = [],
}: {
  title: string;
  data: Record<string, number>;
  dangerKeys?: string[];
}) {
  const entries = Object.entries(data).sort((a, b) => b[1] - a[1]).slice(0, 12);
  if (entries.length === 0) {
    return (
      <div>
        <p class="text-xs mb-2 oh-text-muted">{title}</p>
        <p class="text-xs oh-text-muted">—</p>
      </div>
    );
  }
  return (
    <div>
      <p class="text-xs mb-2 oh-text-muted">{title}</p>
      <div class="flex flex-wrap gap-2">
        {entries.map(([key, value]) => {
          const danger = dangerKeys.includes(key);
          return (
            <span
              key={key}
              class="text-xs font-mono px-2 py-1 rounded-m3-sm"
              style={{
                backgroundColor: 'var(--m3-surface)',
                color: danger ? 'var(--m3-error)' : 'var(--m3-on-surface)',
                border: `1px solid ${danger ? 'var(--m3-error)' : 'var(--m3-outline)'}`,
              }}
            >
              {key} · {value}
            </span>
          );
        })}
      </div>
    </div>
  );
}
