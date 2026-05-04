// OpsPage —— 运行时仪表盘 + 资源清理。对应后端 /api/ops & /api/ops/cleanup*
//
// 一比一对齐 legacy SPA：
// - 顶部状态徽章 + 刷新按钮 + 自动刷新切换（5s）
// - 网格指标：state / uptime / 请求 / 错误 / 字节 / 进程 RSS / 文件句柄 …
// - 清理面板：target=all/logs/uploads + expired_only 复选框 + 历史列表

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useLocation } from 'preact-iso';
import { ApiError } from '../api/client';
import {
  CleanupHistoryEntry,
  OpsRuntimeSnapshot,
  getCleanupHistory,
  getOpsSnapshot,
  runCleanup,
} from '../api/ops';
import { t } from '../i18n';

const REFRESH_INTERVAL_MS = 5_000;

function fmtBytes(n: number | null | undefined): string {
  if (n == null) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function fmtDuration(ms: number): string {
  if (ms < 1000) return `${ms} ms`;
  let secs = Math.floor(ms / 1000);
  const days = Math.floor(secs / 86400);
  secs -= days * 86400;
  const hrs = Math.floor(secs / 3600);
  secs -= hrs * 3600;
  const mins = Math.floor(secs / 60);
  secs -= mins * 60;
  const parts: string[] = [];
  if (days) parts.push(`${days}d`);
  if (hrs) parts.push(`${hrs}h`);
  if (mins) parts.push(`${mins}m`);
  parts.push(`${secs}s`);
  return parts.join(' ');
}

function fmtTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString();
}

function describeApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const body = err.body as { error?: string } | null;
    return `HTTP ${err.status}${body?.error ? ` (${body.error})` : ''}`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
}

export function OpsPage() {
  const location = useLocation();
  const [snapshot, setSnapshot] = useState<OpsRuntimeSnapshot | null>(null);
  const [snapError, setSnapError] = useState<string | null>(null);
  const [snapLoading, setSnapLoading] = useState(false);
  const [history, setHistory] = useState<CleanupHistoryEntry[]>([]);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [cleanupTarget, setCleanupTarget] = useState<'all' | 'logs' | 'uploads'>('all');
  const [expiredOnly, setExpiredOnly] = useState(true);
  const [cleaning, setCleaning] = useState(false);
  const [cleanupError, setCleanupError] = useState<string | null>(null);
  const [cleanupOk, setCleanupOk] = useState<string | null>(null);
  const timerRef = useRef<number | null>(null);

  const refreshSnapshot = async () => {
    setSnapLoading(true);
    setSnapError(null);
    try {
      const s = await getOpsSnapshot();
      setSnapshot(s);
    } catch (err) {
      setSnapError(describeApiError(err));
    } finally {
      setSnapLoading(false);
    }
  };

  const refreshHistory = async () => {
    setHistoryError(null);
    try {
      const h = await getCleanupHistory();
      setHistory(h.items);
    } catch (err) {
      setHistoryError(describeApiError(err));
    }
  };

  // 初次加载
  useEffect(() => {
    void refreshSnapshot();
    void refreshHistory();
  }, []);

  // 自动刷新定时器
  useEffect(() => {
    if (!autoRefresh) {
      if (timerRef.current != null) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      return;
    }
    const tick = () => void refreshSnapshot();
    timerRef.current = window.setInterval(tick, REFRESH_INTERVAL_MS);
    return () => {
      if (timerRef.current != null) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [autoRefresh]);

  const handleCleanup = async () => {
    setCleaning(true);
    setCleanupError(null);
    setCleanupOk(null);
    try {
      const res = await runCleanup({ target: cleanupTarget, expired_only: expiredOnly });
      setCleanupOk(
        `${res.target} · 删除 ${res.deleted_files} 个文件 / ${res.deleted_directories} 个目录 · 释放 ${fmtBytes(res.bytes_freed)}`,
      );
      await refreshHistory();
      await refreshSnapshot();
    } catch (err) {
      setCleanupError(describeApiError(err));
    } finally {
      setCleaning(false);
    }
  };

  const stateBadge = useMemo(() => {
    const state = snapshot?.state ?? 'stopped';
    const colorByState: Record<string, string> = {
      running: 'var(--m3-primary)',
      starting: 'var(--m3-on-surface-variant)',
      stopping: 'var(--m3-on-surface-variant)',
      stopped: 'var(--m3-outline)',
      crashed: 'var(--m3-error)',
    };
    return { state, color: colorByState[state] ?? 'var(--m3-outline)' };
  }, [snapshot?.state]);

  return (
    <main class="min-h-screen p-4 sm:p-6">
      <div class="max-w-6xl mx-auto">
        <header class="flex items-center justify-between gap-4 mb-4">
          <div class="flex items-center gap-3">
            <button
              type="button"
              onClick={() => location.route('/')}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              ← {t('ops.backHome', '返回首页')}
            </button>
            <h1 class="text-xl font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
              {t('ops.title', 'Ops 运行时仪表盘')}
            </h1>
            <span
              class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-m3-sm text-xs font-mono"
              style={{
                backgroundColor: stateBadge.color,
                color: 'var(--m3-on-primary)',
              }}
            >
              {stateBadge.state}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <label class="flex items-center gap-1 text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              <input
                type="checkbox"
                checked={autoRefresh}
                onChange={(ev) => setAutoRefresh((ev.target as HTMLInputElement).checked)}
              />
              {t('ops.autoRefresh', '自动刷新 5s')}
            </label>
            <button
              type="button"
              onClick={() => void refreshSnapshot()}
              disabled={snapLoading}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{
                color: 'var(--m3-on-surface-variant)',
                border: '1px solid var(--m3-outline)',
                opacity: snapLoading ? 0.6 : 1,
              }}
            >
              {snapLoading ? t('common.loading') : t('common.refresh', '刷新')}
            </button>
          </div>
        </header>

        {snapError && (
          <p class="text-sm mb-3" style={{ color: 'var(--m3-error)' }}>
            {snapError}
          </p>
        )}

        {snapshot && (
          <>
            {/* 运行指标 */}
            <section
              class="rounded-m3-md p-4 mb-3 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3"
              style={{ backgroundColor: 'var(--m3-surface-container)' }}
            >
              <Metric label={t('ops.metric.startedAt', '启动时间')} value={fmtTime(snapshot.started_at)} />
              <Metric label={t('ops.metric.uptime', '运行时长')} value={fmtDuration(snapshot.uptime_ms)} />
              <Metric label={t('ops.metric.bound', '监听 URL')} value={snapshot.bound_url || '—'} mono />
              <Metric label={t('ops.metric.openSessions', '在线会话')} value={String(snapshot.open_session_count)} />
              <Metric label={t('ops.metric.activeReq', '正在处理')} value={String(snapshot.active_requests)} />
              <Metric label={t('ops.metric.totalReq', '总请求')} value={String(snapshot.total_requests)} />
              <Metric label={t('ops.metric.totalErr', '总错误')} value={String(snapshot.total_errors)} />
              <Metric label={t('ops.metric.bytesIO', '字节 IN / OUT')}
                value={`${fmtBytes(snapshot.total_bytes_in)} / ${fmtBytes(snapshot.total_bytes_out)}`} />
              <Metric label={t('ops.metric.crash', '崩溃 / 重启')} value={`${snapshot.crash_count} / ${snapshot.restart_count}`} />
              <Metric label={t('ops.metric.rss', '当前 / 峰值 RSS')}
                value={`${fmtBytes(snapshot.process.current_rss_bytes)} / ${fmtBytes(snapshot.process.max_rss_bytes)}`} />
              <Metric label={t('ops.metric.cpu', 'CPU %')}
                value={snapshot.process.cpu_percent != null ? `${snapshot.process.cpu_percent.toFixed(1)} %` : '—'} />
              <Metric label={t('ops.metric.thread', '线程 / 句柄')}
                value={`${snapshot.process.thread_count ?? '—'} / ${snapshot.process.file_handle_count ?? '—'}`} />
              <Metric label={t('ops.metric.swap', 'Swap')} value={fmtBytes(snapshot.process.swap_bytes)} />
              <Metric label={t('ops.metric.diskLog', '磁盘日志')} value={fmtBytes(snapshot.process.disk_log_bytes)} />
              <Metric label={t('ops.metric.platform', '平台')}
                value={`${snapshot.process.platform} (${snapshot.process.platform_version})`} mono />
              <Metric label={t('ops.metric.pid', 'PID')} value={String(snapshot.process.pid)} mono />
            </section>

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
              <section
                class="rounded-m3-md p-3 mb-3"
                style={{ backgroundColor: 'var(--m3-surface-container)' }}
              >
                <p class="text-xs mb-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
        <section
          class="rounded-m3-md p-4 mb-3"
          style={{ backgroundColor: 'var(--m3-surface-container)' }}
        >
          <h2 class="text-base font-semibold mb-3" style={{ color: 'var(--m3-on-surface)' }}>
            {t('ops.cleanup.title', '资源清理')}
          </h2>
          <div class="flex items-center gap-3 flex-wrap mb-3">
            <label class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('ops.cleanup.target', '目标')}：
              <select
                value={cleanupTarget}
                onChange={(ev) =>
                  setCleanupTarget((ev.target as HTMLSelectElement).value as 'all' | 'logs' | 'uploads')
                }
                class="ml-1 px-2 py-1 rounded-m3-sm text-sm"
                style={{
                  backgroundColor: 'var(--m3-surface)',
                  color: 'var(--m3-on-surface)',
                  border: '1px solid var(--m3-outline)',
                }}
              >
                <option value="all">{t('ops.cleanup.target.all', '全部')}</option>
                <option value="logs">{t('ops.cleanup.target.logs', '仅日志')}</option>
                <option value="uploads">{t('ops.cleanup.target.uploads', '仅上传缓存')}</option>
              </select>
            </label>
            <label class="text-sm flex items-center gap-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
              <input
                type="checkbox"
                checked={expiredOnly}
                onChange={(ev) => setExpiredOnly((ev.target as HTMLInputElement).checked)}
              />
              {t('ops.cleanup.expiredOnly', '仅清理过期项')}
            </label>
            <button
              type="button"
              onClick={() => void handleCleanup()}
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
            <p class="text-sm" style={{ color: 'var(--m3-error)' }}>
              {cleanupError}
            </p>
          )}
          {cleanupOk && (
            <p class="text-sm" style={{ color: 'var(--m3-primary)' }}>
              ✓ {cleanupOk}
            </p>
          )}
        </section>

        {/* 历史 */}
        <section
          class="rounded-m3-md p-4"
          style={{ backgroundColor: 'var(--m3-surface-container)' }}
        >
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-base font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
              {t('ops.cleanup.history', '清理历史（最近 50 条）')}
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
            <p class="text-sm" style={{ color: 'var(--m3-error)' }}>
              {historyError}
            </p>
          )}
          {history.length === 0 ? (
            <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('ops.cleanup.empty', '暂无历史记录')}
            </p>
          ) : (
            <table class="w-full text-sm">
              <thead>
                <tr style={{ color: 'var(--m3-on-surface-variant)' }}>
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
                  <tr key={idx} style={{ color: 'var(--m3-on-surface)' }}>
                    <td class="py-1 px-2 font-mono text-xs">{fmtTime(h.timestamp)}</td>
                    <td class="py-1 px-2">{h.target}</td>
                    <td class="py-1 px-2">{h.expired_only ? '✓' : '—'}</td>
                    <td class="py-1 px-2 text-right">{h.deleted_files}</td>
                    <td class="py-1 px-2 text-right">{h.deleted_directories}</td>
                    <td class="py-1 px-2 text-right">{fmtBytes(h.bytes_freed)}</td>
                    <td class="py-1 px-2 text-right">{h.memory_log_entries_cleared}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </main>
  );
}

function Metric(props: { label: string; value: string; mono?: boolean }) {
  return (
    <div
      class="rounded-m3-sm p-2"
      style={{ backgroundColor: 'var(--m3-surface)', border: '1px solid var(--m3-outline)' }}
    >
      <p class="text-xs mb-0.5" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {props.label}
      </p>
      <p
        class={`text-sm ${props.mono ? 'font-mono' : 'font-semibold'} truncate`}
        style={{ color: 'var(--m3-on-surface)' }}
        title={props.value}
      >
        {props.value}
      </p>
    </div>
  );
}
