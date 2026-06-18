// LogsPage —— 日志查看 + 整包导出。对应后端 /api/logs & /api/logs/export
//
// - 顶部 toolbar：分页 + 日志级别筛选（前端再过滤，因 service 不接受 level 参数）
// - 列表 virtual-scroll 替代物：CSS max-height + overflow（实测 1k 条 OK；
//   service 端硬编码 limit≤2000）
// - 顶部 Tail 模式：只显示最新 N 条，定时拉取最末页
// - 「导出 JSON」直接下载

import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import { LogEntry, exportLogsBundle, listLogs } from '../../../api/logs';
import { t, tTime } from '../../../i18n';
import { MenuSelect } from '../../../components/MenuSelect';
import { showSnackbar } from '../../../components/Snackbar';
import { TopBar } from '../../../components/TopBar';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { describeApiError, isAbortError } from '../../../utils/api_error';

const PAGE_SIZE = 200;
const TAIL_INTERVAL_MS = 3_000;

const LEVEL_COLORS: Record<LogEntry['level'], string> = {
  info: 'var(--m3-on-surface-variant)',
  success: 'var(--m3-primary)',
  warn: '#cc8a00',
  error: 'var(--m3-error)',
  debug: 'var(--m3-outline)',
  telemetry: '#5b6abf',
};

// 日志列表使用 24h 时:分:秒 + 毫秒，时间部分走 i18n 本地化，毫秒后缀显式拼接。
function fmtTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${tTime(d)}.${String(d.getMilliseconds()).padStart(3, '0')}`;
}

export function LogsPage() {
  const location = useAnimatedLocation();
  const [items, setItems] = useState<LogEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [hasMore, setHasMore] = useState(false);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tail, setTail] = useState(true);
  const [levelFilter, setLevelFilter] = useState<string>('all');
  const [tagFilter, setTagFilter] = useState('');
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const pageRequestAbortRef = useRef<AbortController | null>(null);

  const loadAt = useCallback(async (newOffset: number) => {
    pageRequestAbortRef.current?.abort();
    const ctrl = new AbortController();
    pageRequestAbortRef.current = ctrl;
    setLoading(true);
    setError(null);
    try {
      const res = await listLogs({ offset: newOffset, limit: PAGE_SIZE, signal: ctrl.signal });
      if (ctrl.signal.aborted) return;
      setItems(res.items);
      setTotal(res.total);
      setHasMore(res.has_more);
      setOffset(res.offset);
    } catch (err) {
      if (ctrl.signal.aborted || isAbortError(err)) return;
      setError(describeApiError(err));
    } finally {
      if (pageRequestAbortRef.current === ctrl) {
        pageRequestAbortRef.current = null;
        if (!ctrl.signal.aborted) setLoading(false);
      }
    }
  }, []);

  // Tail 模式：定时拉最后一页
  const loadTail = useCallback(async (signal: AbortSignal) => {
    try {
      // 先请求 metadata（offset=0,limit=1）拿 total
      const head = await listLogs({ offset: 0, limit: 1, signal });
      if (signal.aborted) return;
      const tailOffset = Math.max(0, head.total - PAGE_SIZE);
      const res = await listLogs({ offset: tailOffset, limit: PAGE_SIZE, signal });
      if (signal.aborted) return;
      setItems(res.items);
      setTotal(res.total);
      setHasMore(res.has_more);
      setOffset(res.offset);
      setError(null);
    } catch (err) {
      if (signal.aborted || isAbortError(err)) return;
      setError(describeApiError(err));
    }
  }, []);

  useEffect(() => () => {
    pageRequestAbortRef.current?.abort();
  }, []);

  useAsyncPolling(async (_isActive, signal) => {
    await loadTail(signal);
  }, {
    enabled: tail,
    intervalMs: TAIL_INTERVAL_MS,
    onError: (err) => setError(describeApiError(err)),
  });

  useEffect(() => {
    if (tail) return;
    void loadAt(offset);
    // 关闭 tail 时仍以当前 offset 为锚
  }, [tail, loadAt]);

  const filtered = useMemo(() => {
    const tag = tagFilter.trim().toLowerCase();
    return items.filter((it) => {
      if (levelFilter !== 'all' && it.level !== levelFilter) return false;
      if (tag && !it.tag.toLowerCase().includes(tag) && !it.message.toLowerCase().includes(tag)) {
        return false;
      }
      return true;
    });
  }, [items, levelFilter, tagFilter]);
  const levelCounts = useMemo(() => {
    const counts = new Map<LogEntry['level'], number>();
    for (const item of items) {
      counts.set(item.level, (counts.get(item.level) ?? 0) + 1);
    }
    return counts;
  }, [items]);
  const activeFilterCount = (levelFilter !== 'all' ? 1 : 0) + (tagFilter.trim() ? 1 : 0);

  const handleExport = async () => {
    setExporting(true);
    setExportError(null);
    try {
      showSnackbar(t('logs.export.started', '正在导出日志…'));
      await exportLogsBundle();
      showSnackbar(t('logs.export.ok', '已开始下载日志 JSON'), { tone: 'success' });
    } catch (err) {
      const message = describeApiError(err);
      setExportError(message);
      showSnackbar(`${t('logs.export.failed', '导出日志失败')}：${message}`, { tone: 'error' });
    } finally {
      setExporting(false);
    }
  };

  return (
    <main class="oh-logs-page min-h-screen p-4 sm:p-6">
      <div class="max-w-7xl mx-auto">
        <TopBar
          title={t('logs.title', '日志')}
          subtitle={tail
            ? t('logs.subtitle.tail', 'Tail 模式正在追踪最新日志')
            : t('logs.subtitle.page', '按页审阅历史日志')}
          hideNav
          leadingSlot={(
            <button
              type="button"
              onClick={() => location.route('/')}
              class="oh-tap-press oh-topbar-action text-sm rounded-m3-sm px-3 py-1.5"
            >
              ← {t('logs.backHome', '返回首页')}
            </button>
          )}
          actionSlot={(
            <button
              type="button"
              onClick={() => void handleExport()}
              disabled={exporting}
              class="oh-tap-press oh-topbar-action oh-logs-export-button text-sm rounded-m3-sm px-3 py-1.5"
            >
              {exporting ? t('logs.exporting', '导出中…') : t('logs.export', '导出 JSON')}
            </button>
          )}
        />

        <section class="oh-logs-summary-grid mb-3" aria-label={t('logs.summary', '日志概览')}>
          <SummaryTile label={t('logs.stat.total', '总计')} value={String(total)} />
          <SummaryTile label={t('logs.stat.shown', '当前页')} value={String(items.length)} />
          <SummaryTile label={t('logs.stat.matched', '筛选命中')} value={String(filtered.length)} />
          <SummaryTile label={t('logs.stat.filters', '已用筛选')} value={String(activeFilterCount)} />
        </section>

        <section class="oh-logs-control-panel mb-3">
          <div class="oh-logs-control-row">
            <label class="oh-logs-tail-toggle">
              <input
                type="checkbox"
                checked={tail}
                onChange={(ev) => setTail((ev.target as HTMLInputElement).checked)}
              />
              <span>{t('logs.tail', 'Tail 模式 3s 自动')}</span>
            </label>
            <MenuSelect
              value={levelFilter}
              onChange={setLevelFilter}
              minWidth={140}
              options={[
                { value: 'all', label: t('logs.level.all', '全部级别') },
                { value: 'info', label: 'info' },
                { value: 'success', label: 'success' },
                { value: 'warn', label: 'warn' },
                { value: 'error', label: 'error' },
                { value: 'debug', label: 'debug' },
                { value: 'telemetry', label: 'telemetry' },
              ]}
            />
            <input
              type="text"
              value={tagFilter}
              onInput={(ev) => setTagFilter((ev.target as HTMLInputElement).value)}
              placeholder={t('logs.tag.placeholder', '按 tag / message 模糊过滤')}
              class="oh-logs-filter-input"
            />
          </div>

          <div class="oh-logs-level-strip" aria-label={t('logs.level.summary', '级别分布')}>
            {(['info', 'success', 'warn', 'error', 'debug', 'telemetry'] as const).map((level) => (
              <span key={level} class="oh-logs-level-chip" data-level={level}>
                <span>{level}</span>
                <strong>{levelCounts.get(level) ?? 0}</strong>
              </span>
            ))}
          </div>
        </section>

        {/* 分页（仅在非 tail 模式可用） */}
        {!tail && (
          <div class="oh-logs-pagination mb-3">
            <button
              type="button"
              onClick={() => void loadAt(Math.max(0, offset - PAGE_SIZE))}
              disabled={loading || offset === 0}
              class="oh-tap-press oh-logs-secondary-button"
            >
              ← {t('logs.prev', '上一页')}
            </button>
            <span class="oh-logs-page-indicator">
              offset {offset} / {total}
            </span>
            <button
              type="button"
              onClick={() => void loadAt(offset + PAGE_SIZE)}
              disabled={loading || !hasMore}
              class="oh-tap-press oh-logs-secondary-button"
            >
              {t('logs.next', '下一页')} →
            </button>
            <button
              type="button"
              onClick={() => void loadAt(offset)}
              disabled={loading}
              class="oh-tap-press oh-logs-secondary-button"
            >
              {t('common.refresh', '刷新')}
            </button>
          </div>
        )}

        {error && (
          <p class="oh-admin-status is-error mb-3">
            {error}
          </p>
        )}
        {exportError && (
          <p class="oh-admin-status is-error mb-3">
            {exportError}
          </p>
        )}

        <section class="oh-appear-up oh-logs-panel">
          {filtered.length === 0 ? (
            <p class="oh-logs-empty-state">
              {loading ? t('common.loading') : t('logs.empty', '没有匹配的日志')}
            </p>
          ) : (
            <ul class="oh-logs-list">
              {filtered.map((it) => (
                <li
                  key={it.id}
                  class="oh-log-row"
                  data-level={it.level}
                >
                  <div class="oh-log-row-main">
                    <span class="oh-log-time">
                      {fmtTime(it.timestamp)}
                    </span>
                    <span class="oh-log-level" style={{ color: LEVEL_COLORS[it.level] }}>
                      {it.level}
                    </span>
                    <span class="oh-log-tag">{it.tag}</span>
                    <span class="oh-log-message">
                      {it.message}
                    </span>
                  </div>
                  {it.data && Object.keys(it.data).length > 0 && (
                    <pre
                      class="oh-log-data"
                    >
                      {JSON.stringify(it.data, null, 2)}
                    </pre>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </main>
  );
}

function SummaryTile({ label, value }: { label: string; value: string }) {
  return (
    <div class="oh-logs-summary-tile">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
