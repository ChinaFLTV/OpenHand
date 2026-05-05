// LogsPage —— 日志查看 + 整包导出。对应后端 /api/logs & /api/logs/export
//
// 一比一对齐 legacy SPA：
// - 顶部 toolbar：分页 + 日志级别筛选（前端再过滤，因 service 不接受 level 参数）
// - 列表 virtual-scroll 替代物：CSS max-height + overflow（实测 1k 条 OK；
//   service 端硬编码 limit≤2000）
// - 顶部 Tail 模式：只显示最新 N 条，定时拉取最末页
// - 「导出 JSON」直接下载

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';
import { ApiError } from '../api/client';
import { LogEntry, exportLogsBundle, listLogs } from '../api/logs';
import { t, tTime } from '../i18n';
import { MenuSelect } from '../components/MenuSelect';
import { showSnackbar } from '../components/Snackbar';

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

function describeApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const body = err.body as { error?: string } | null;
    return `HTTP ${err.status}${body?.error ? ` (${body.error})` : ''}`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
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
  const tailTimerRef = useRef<number | null>(null);

  const loadAt = async (newOffset: number) => {
    setLoading(true);
    setError(null);
    try {
      const res = await listLogs({ offset: newOffset, limit: PAGE_SIZE });
      setItems(res.items);
      setTotal(res.total);
      setHasMore(res.has_more);
      setOffset(res.offset);
    } catch (err) {
      setError(describeApiError(err));
    } finally {
      setLoading(false);
    }
  };

  // Tail 模式：定时拉最后一页
  const loadTail = async () => {
    try {
      // 先请求 metadata（offset=0,limit=1）拿 total
      const head = await listLogs({ offset: 0, limit: 1 });
      const tailOffset = Math.max(0, head.total - PAGE_SIZE);
      const res = await listLogs({ offset: tailOffset, limit: PAGE_SIZE });
      setItems(res.items);
      setTotal(res.total);
      setHasMore(res.has_more);
      setOffset(res.offset);
      setError(null);
    } catch (err) {
      setError(describeApiError(err));
    }
  };

  useEffect(() => {
    if (tail) {
      void loadTail();
      tailTimerRef.current = window.setInterval(() => {
        void loadTail();
      }, TAIL_INTERVAL_MS);
      return () => {
        if (tailTimerRef.current != null) {
          clearInterval(tailTimerRef.current);
          tailTimerRef.current = null;
        }
      };
    }
    if (tailTimerRef.current != null) {
      clearInterval(tailTimerRef.current);
      tailTimerRef.current = null;
    }
    void loadAt(offset);
    // 关闭 tail 时仍以当前 offset 为锚
  }, [tail]);

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
    <main class="min-h-screen p-4 sm:p-6">
      <div class="max-w-6xl mx-auto">
        <header class="flex items-center justify-between gap-4 mb-3 flex-wrap">
          <div class="flex items-center gap-3">
            <button
              type="button"
              onClick={() => location.route('/')}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              ← {t('logs.backHome', '返回首页')}
            </button>
            <h1 class="text-xl font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
              {t('logs.title', '日志')}
            </h1>
            <span class="text-xs font-mono" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('logs.stat.total', '总：')}
              {total} · {t('logs.stat.shown', '当前页：')}
              {items.length}
            </span>
          </div>
          <div class="flex items-center gap-2 flex-wrap">
            <label class="flex items-center gap-1 text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              <input
                type="checkbox"
                checked={tail}
                onChange={(ev) => setTail((ev.target as HTMLInputElement).checked)}
              />
              {t('logs.tail', 'Tail 模式 3s 自动')}
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
              class="text-sm px-2 py-1 rounded-m3-sm"
              style={{
                backgroundColor: 'var(--m3-surface)',
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-outline)',
                minWidth: '180px',
              }}
            />
            <button
              type="button"
              onClick={() => void handleExport()}
              disabled={exporting}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{
                color: 'var(--m3-on-primary)',
                backgroundColor: 'var(--m3-primary)',
                opacity: exporting ? 0.6 : 1,
              }}
            >
              {exporting ? t('logs.exporting', '导出中…') : t('logs.export', '导出 JSON')}
            </button>
          </div>
        </header>

        {/* 分页（仅在非 tail 模式可用） */}
        {!tail && (
          <div class="flex items-center gap-2 mb-3">
            <button
              type="button"
              onClick={() => void loadAt(Math.max(0, offset - PAGE_SIZE))}
              disabled={loading || offset === 0}
              class="text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              ← {t('logs.prev', '上一页')}
            </button>
            <span class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              offset {offset} / {total}
            </span>
            <button
              type="button"
              onClick={() => void loadAt(offset + PAGE_SIZE)}
              disabled={loading || !hasMore}
              class="text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              {t('logs.next', '下一页')} →
            </button>
            <button
              type="button"
              onClick={() => void loadAt(offset)}
              disabled={loading}
              class="text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              {t('common.refresh', '刷新')}
            </button>
          </div>
        )}

        {error && (
          <p class="text-sm mb-3" style={{ color: 'var(--m3-error)' }}>
            {error}
          </p>
        )}
        {exportError && (
          <p class="text-sm mb-3" style={{ color: 'var(--m3-error)' }}>
            {exportError}
          </p>
        )}

        <section class="oh-appear-up rounded-m3-md p-2"
          style={{
            backgroundColor: 'var(--m3-surface-container)',
            maxHeight: '70vh',
            overflowY: 'auto',
          }}
        >
          {filtered.length === 0 ? (
            <p class="text-sm py-4 text-center" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {loading ? t('common.loading') : t('logs.empty', '没有匹配的日志')}
            </p>
          ) : (
            <ul class="flex flex-col gap-0.5">
              {filtered.map((it) => (
                <li
                  key={it.id}
                  class="px-2 py-1 rounded-m3-sm font-mono text-xs"
                  style={{ backgroundColor: 'var(--m3-surface)', color: 'var(--m3-on-surface)' }}
                >
                  <div class="flex items-baseline gap-2">
                    <span style={{ color: 'var(--m3-on-surface-variant)', minWidth: '90px' }}>
                      {fmtTime(it.timestamp)}
                    </span>
                    <span
                      class="uppercase"
                      style={{ color: LEVEL_COLORS[it.level], minWidth: '64px' }}
                    >
                      {it.level}
                    </span>
                    <span style={{ color: 'var(--m3-primary)', minWidth: '120px' }}>{it.tag}</span>
                    <span class="flex-1" style={{ wordBreak: 'break-word' }}>
                      {it.message}
                    </span>
                  </div>
                  {it.data && Object.keys(it.data).length > 0 && (
                    <pre
                      class="mt-1 px-2 py-1 rounded-m3-sm overflow-x-auto"
                      style={{
                        backgroundColor: 'var(--m3-surface-container)',
                        color: 'var(--m3-on-surface-variant)',
                      }}
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
