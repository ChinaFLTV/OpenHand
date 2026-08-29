import type { JSX } from 'preact';
import { useMemo, useState } from 'preact/hooks';
import {
  getResourceUsage,
  type ResourceUsageKind,
  type ResourceUsageLevel,
  type ResourceUsageLevelSnapshot,
  type ResourceUsageEvent,
  type ResourceUsageResourceSnapshot,
  type ResourceUsageSnapshot,
} from '../api/toolbox';
import { useAsyncPolling } from '../hooks/useAsyncPolling';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import { formatLocalDateTimeSecond } from '../shared/util/date_time';
import { describeApiError } from '../utils/api_error';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

const LEVELS: ResourceUsageLevel[] = ['session', 'day', 'week', 'month', 'quarter', 'year'];
const CHART_COLORS = ['#6d5dfc', '#14b8a6', '#f59e0b', '#ec4899', '#38bdf8', '#94a3b8'];
const DONUT_SIZE = 154;
const DONUT_CENTER = DONUT_SIZE / 2;
const DONUT_RADIUS = 62;
const DONUT_CIRCUMFERENCE = 2 * Math.PI * DONUT_RADIUS;
const DONUT_SEGMENT_GAP = 4;
const LIVE_REFRESH_INTERVAL_MS = 2000;
const RESOURCE_USAGE_REQUEST_TIMEOUT_MS = 10000;

interface ResourceUsageDialogProps {
  kind: ResourceUsageKind;
  labels?: Record<string, string>;
  onClose: () => void;
}

function levelLabel(level: ResourceUsageLevel): string {
  return t(`resourceUsage.level.${level}`, {
    session: '会话', day: '天', week: '周', month: '月', quarter: '季度', year: '年',
  }[level]);
}

function kindLabel(kind: ResourceUsageKind): string {
  return t(`resourceUsage.kind.${kind}`, {
    tool: '工具', skill: '技能', hook: 'Hook', knowledge: '知识库', memory: '记忆', mcp: 'MCP',
  }[kind]);
}

function shortBucket(value: string): string {
  if (!value) return '—';
  return value.length <= 14 ? value : `…${value.slice(-12)}`;
}

function sortedEntries(level: ResourceUsageLevelSnapshot): Array<[string, number]> {
  return Object.entries(level.counts ?? {})
    .filter((entry): entry is [string, number] => Number.isFinite(entry[1]) && entry[1] > 0)
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]));
}

function formatDuration(milliseconds: number): string {
  if (!Number.isFinite(milliseconds) || milliseconds < 0) return '—';
  if (milliseconds < 1000) return `${Math.round(milliseconds)} ms`;
  if (milliseconds < 60000) return `${(milliseconds / 1000).toFixed(1)} s`;
  return `${(milliseconds / 60000).toFixed(1)} min`;
}

export function ResourceUsageDialog({ kind, labels = {}, onClose }: ResourceUsageDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [snapshot, setSnapshot] = useState<ResourceUsageSnapshot | null>(null);
  const [levelKey, setLevelKey] = useState<ResourceUsageLevel>('day');
  const [error, setError] = useState('');

  useAsyncPolling(
    async (isActive, signal) => {
      const value = await getResourceUsage(kind, {
        signal,
        timeoutMs: RESOURCE_USAGE_REQUEST_TIMEOUT_MS,
      });
      if (!isActive()) return;
      setSnapshot(value);
      setError('');
    },
    {
      enabled: !closing,
      intervalMs: LIVE_REFRESH_INTERVAL_MS,
      taskTimeoutMs: RESOURCE_USAGE_REQUEST_TIMEOUT_MS,
      onError: (reason) => setError(describeApiError(reason)),
    },
  );

  const level = snapshot?.levels?.[levelKey] ?? null;
  const entries = useMemo(() => level ? sortedEntries(level) : [], [level]);
  const top = entries[0];
  const topShare = top && level?.total ? top[1] / level.total : 0;

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_CENTER_CLASS,
        overlayTone: 'strong',
        overlayBlurPx: 5,
        panelClassName: 'oh-resource-usage-dialog',
        panelBorder: 'outlineVariant',
        panelSurface: {
          width: 'min(1120px, calc(100vw - 28px))',
          maxHeight: 'min(90dvh, 860px)',
          overflow: 'hidden',
        },
      })}
      ariaLabel={`${kindLabel(kind)} ${t('resourceUsage.title', '使用统计')}`}
    >
      <header class="oh-resource-usage-head">
        <span class="oh-resource-usage-head-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24"><path d="M4 19V9m5 10V5m5 14v-7m5 7V3" /></svg>
        </span>
        <div class="min-w-0 flex-1">
          <h2>{kindLabel(kind)} {t('resourceUsage.title', '使用统计')}</h2>
          <p>{t('resourceUsage.subtitle', '细粒度调用、状态、耗时与会话洞察')}</p>
        </div>
        <span class="oh-resource-usage-live"><i />{snapshot ? formatLocalDateTimeSecond(snapshot.generated_at, '—') : t('common.loading', '加载中…')}</span>
        <button type="button" class="oh-resource-usage-close oh-tap-press" onClick={requestClose} aria-label={t('common.close', '关闭')}>
          <svg viewBox="0 0 24 24"><path d="m6 6 12 12M18 6 6 18" /></svg>
        </button>
      </header>

      <div class="oh-resource-usage-scroll">
        <div class="oh-resource-usage-levels" role="tablist" aria-label={t('resourceUsage.levels', '统计周期')}>
          {LEVELS.map((item) => (
            <button
              key={item}
              type="button"
              role="tab"
              aria-selected={levelKey === item}
              class={`oh-tap-press${levelKey === item ? ' is-active' : ''}`}
              onClick={() => setLevelKey(item)}
            >
              {levelLabel(item)}
            </button>
          ))}
        </div>

        {error ? <div class="oh-resource-usage-error">{error}</div> : null}
        {!snapshot && !error ? <div class="oh-resource-usage-loading">{t('common.loading', '加载中…')}</div> : null}
        {level ? (
          <>
            <section class="oh-resource-usage-summary">
              <SummaryCard icon="↗" label={t('resourceUsage.total', '调用总量')} value={String(level.total ?? 0)} />
              <SummaryCard icon="✓" label={t('resourceUsage.success', '成功调用')} value={String(level.successes ?? 0)} detail={level.success_rate == null ? '—' : `${(level.success_rate * 100).toFixed(1)}%`} />
              <SummaryCard icon="!" label={t('resourceUsage.failure', '失败调用')} value={String(level.failures ?? 0)} tone={level.failures > 0 ? 'error' : 'normal'} />
              <SummaryCard icon="◷" label={t('resourceUsage.latency', '平均 / P95 耗时')} value={formatDuration(level.average_duration_ms ?? 0)} detail={formatDuration(level.p95_duration_ms ?? 0)} />
              <SummaryCard icon="◇" label={t('resourceUsage.sessions', '活跃会话 / 资源')} value={String(level.session_count ?? 0)} detail={String(level.resource_count ?? entries.length)} />
              <SummaryCard icon="★" label={t('resourceUsage.top', '首位资源')} value={top ? (labels[top[0]] || top[0]) : '—'} detail={`${(topShare * 100).toFixed(1)}%`} />
            </section>

            <section class="oh-resource-usage-charts">
              <AnalyticsPanel title={t('resourceUsage.trend', '调用趋势')} subtitle={`${levelLabel(levelKey)}${t('resourceUsage.volumeSuffix', '级调用总量变化')}`}>
                <TrendChart level={level} />
              </AnalyticsPanel>
              <AnalyticsPanel title={t('resourceUsage.share', '资源占比')} subtitle={t('resourceUsage.shareSubtitle', '当前周期调用构成')}>
                <Distribution entries={entries} labels={labels} total={level.total ?? 0} />
              </AnalyticsPanel>
            </section>

            <AnalyticsPanel title={t('resourceUsage.map', '资源调用映射')} subtitle={`${levelLabel(levelKey)} · ${level.bucket || '—'}`}>
              <Ranking entries={entries} labels={labels} />
            </AnalyticsPanel>
            <AnalyticsPanel title={t('resourceUsage.details', '资源与子资源明细')} subtitle={kind === 'mcp' ? t('resourceUsage.mcpDetails', '按 MCP 服务展开实际调用的 Tool') : t('resourceUsage.detailsSubtitle', '成功率、耗时、会话与子动作明细')}>
              <ResourceDetails resources={level.resources ?? []} labels={labels} />
            </AnalyticsPanel>
            <AnalyticsPanel title={t('resourceUsage.recent', '最近调用记录')} subtitle={t('resourceUsage.recentSubtitle', '实时更新 · 参数与结果已脱敏并限制长度')}>
              <RecentEvents events={level.recent_events ?? []} />
            </AnalyticsPanel>
          </>
        ) : null}
      </div>
    </DialogFrame>
  );
}

function SummaryCard(props: { icon: string; label: string; value: string; detail?: string; tone?: 'normal' | 'error' }) {
  return (
    <article class={`oh-resource-usage-summary-card${props.tone === 'error' ? ' is-error' : ''}`}>
      <span aria-hidden="true">{props.icon}</span>
      <div>
        <p>{props.label}</p>
        <div><strong title={props.value}>{props.value}</strong>{props.detail ? <em>{props.detail}</em> : null}</div>
      </div>
    </article>
  );
}

function AnalyticsPanel(props: { title: string; subtitle: string; children: JSX.Element }) {
  return (
    <article class="oh-resource-usage-panel">
      <h3>{props.title}</h3>
      <p>{props.subtitle}</p>
      <div class="oh-resource-usage-panel-body">{props.children}</div>
    </article>
  );
}

function EmptyChart({ label }: { label: string }) {
  return <div class="oh-resource-usage-empty"><span>⌁</span><p>{label}</p></div>;
}

function TrendChart({ level }: { level: ResourceUsageLevelSnapshot }) {
  const points = (level.trend ?? []).slice(-16);
  const max = Math.max(1, ...points.map((point) => point.total));
  if (points.length === 0 || points.every((point) => point.total <= 0)) {
    return <EmptyChart label={t('resourceUsage.emptyTrend', '暂无趋势数据')} />;
  }
  const width = 640;
  const height = 210;
  const insetX = 18;
  const insetY = 16;
  const chartHeight = 158;
  const coordinates = points.map((point, index) => {
    const x = points.length === 1 ? width / 2 : insetX + (width - insetX * 2) * index / (points.length - 1);
    const y = insetY + chartHeight * (1 - point.total / max);
    return { x, y, point };
  });
  const line = smoothPath(coordinates);
  const first = coordinates[0];
  const last = coordinates.at(-1) ?? first;
  const area = `${line} L ${last.x} ${insetY + chartHeight} L ${first.x} ${insetY + chartHeight} Z`;
  return (
    <div class="oh-resource-usage-trend">
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" role="img" aria-label={t('resourceUsage.trend', '调用趋势')}>
        {[0, 1, 2, 3, 4].map((row) => <line key={row} x1={insetX} x2={width - insetX} y1={insetY + chartHeight * row / 4} y2={insetY + chartHeight * row / 4} class="oh-resource-usage-gridline" />)}
        <path d={area} class="oh-resource-usage-area" />
        <path d={line} class="oh-resource-usage-line" />
        {coordinates.map(({ x, y, point }) => <circle key={point.bucket} cx={x} cy={y} r="4" class="oh-resource-usage-dot"><title>{point.bucket}: {point.total}</title></circle>)}
      </svg>
      <div><span>{shortBucket(points[0].bucket)}</span><span>{shortBucket(points.at(-1)?.bucket ?? '')}</span></div>
    </div>
  );
}

function smoothPath(points: Array<{ x: number; y: number }>): string {
  if (points.length === 0) return '';
  let path = `M ${points[0].x} ${points[0].y}`;
  for (let index = 0; index < points.length - 1; index++) {
    const previous = points[Math.max(0, index - 1)];
    const current = points[index];
    const next = points[index + 1];
    const afterNext = points[Math.min(points.length - 1, index + 2)];
    const control1X = current.x + (next.x - previous.x) / 6;
    const control1Y = current.y + (next.y - previous.y) / 6;
    const control2X = next.x - (afterNext.x - current.x) / 6;
    const control2Y = next.y - (afterNext.y - current.y) / 6;
    path += ` C ${control1X} ${control1Y}, ${control2X} ${control2Y}, ${next.x} ${next.y}`;
  }
  return path;
}

function Distribution(props: { entries: Array<[string, number]>; labels: Record<string, string>; total: number }) {
  if (props.entries.length === 0 || props.total <= 0) return <EmptyChart label={t('resourceUsage.emptyShare', '暂无占比数据')} />;
  const visible = props.entries.slice(0, 5);
  const other = Math.max(0, props.total - visible.reduce((sum, entry) => sum + entry[1], 0));
  const values = visible.map((entry, index) => ({ value: entry[1], color: CHART_COLORS[index] }));
  if (other > 0) values.push({ value: other, color: CHART_COLORS[5] });
  let cursor = 0;
  const segments = values.map((item) => {
    const ratio = item.value / props.total;
    const offset = cursor;
    cursor += ratio;
    const length = Math.max(0, ratio * DONUT_CIRCUMFERENCE - DONUT_SEGMENT_GAP);
    return { ...item, length, offset: -offset * DONUT_CIRCUMFERENCE };
  });
  return (
    <div class="oh-resource-usage-distribution">
      <div class="oh-resource-usage-donut">
        <svg viewBox={`0 0 ${DONUT_SIZE} ${DONUT_SIZE}`} aria-hidden="true">
          <circle class="oh-resource-usage-donut-track" cx={DONUT_CENTER} cy={DONUT_CENTER} r={DONUT_RADIUS} />
          {segments.map((segment, index) => (
            <circle
              key={`${segment.color}-${index}`}
              class="oh-resource-usage-donut-segment"
              cx={DONUT_CENTER}
              cy={DONUT_CENTER}
              r={DONUT_RADIUS}
              style={{
                stroke: segment.color,
                strokeDasharray: `${segment.length} ${DONUT_CIRCUMFERENCE - segment.length}`,
                strokeDashoffset: String(segment.offset),
              }}
            />
          ))}
        </svg>
        <div><strong>{props.total}</strong><span>{t('resourceUsage.calls', '次调用')}</span></div>
      </div>
      <ul>
        {visible.map((entry, index) => (
          <li key={entry[0]}><i style={{ background: CHART_COLORS[index] }} /><span title={entry[0]}>{props.labels[entry[0]] || entry[0]}</span><strong>{(entry[1] * 100 / props.total).toFixed(1)}%</strong></li>
        ))}
        {other > 0 ? <li><i style={{ background: CHART_COLORS[5] }} /><span>{t('resourceUsage.other', '其他资源')}</span><strong>{(other * 100 / props.total).toFixed(1)}%</strong></li> : null}
      </ul>
    </div>
  );
}

function Ranking(props: { entries: Array<[string, number]>; labels: Record<string, string> }) {
  if (props.entries.length === 0) return <EmptyChart label={t('resourceUsage.emptyMap', '当前周期尚无调用记录')} />;
  const visible = props.entries.slice(0, 20);
  const max = Math.max(1, visible[0][1]);
  return (
    <ol class="oh-resource-usage-ranking">
      {visible.map((entry, index) => (
        <li key={entry[0]}>
          <span>{String(index + 1).padStart(2, '0')}</span>
          <div class="oh-resource-usage-rank-label"><strong title={entry[0]}>{props.labels[entry[0]] || entry[0]}</strong>{props.labels[entry[0]] ? <small>{entry[0]}</small> : null}</div>
          <div class="oh-resource-usage-rank-bar"><i style={{ width: `${entry[1] * 100 / max}%` }} /></div>
          <b>{entry[1]}</b>
        </li>
      ))}
      {props.entries.length > visible.length ? <p>{t('resourceUsage.more', '另有 {count} 项低频资源').replace('{count}', String(props.entries.length - visible.length))}</p> : null}
    </ol>
  );
}

function ResourceDetails(props: { resources: ResourceUsageResourceSnapshot[]; labels: Record<string, string> }) {
  if (props.resources.length === 0) return <EmptyChart label={t('resourceUsage.emptyDetails', '当前周期暂无资源明细')} />;
  return (
    <div class="oh-resource-usage-details">
      {props.resources.slice(0, 30).map((resource) => {
        const label = props.labels[resource.resource_id] || resource.resource_id;
        return (
          <article key={resource.resource_id} class="oh-resource-usage-detail-card">
            <header>
              <span aria-hidden="true">{resource.sub_resources.length > 0 ? '⌘' : '◇'}</span>
              <div><strong title={label}>{label}</strong>{label !== resource.resource_id ? <small>{resource.resource_id}</small> : null}</div>
              <b>{resource.total}</b>
            </header>
            <div class="oh-resource-usage-detail-metrics">
              <MetricPill label={`✓ ${resource.successes} · ${resource.success_rate == null ? '—' : `${(resource.success_rate * 100).toFixed(1)}%`}`} />
              <MetricPill label={`! ${resource.failures}`} error={resource.failures > 0} />
              <MetricPill label={`◷ ${formatDuration(resource.average_duration_ms)}`} />
              <MetricPill label={`◇ ${resource.session_count}`} />
              {resource.last_called_at ? <MetricPill label={`◴ ${formatLocalDateTimeSecond(resource.last_called_at, '—')}`} /> : null}
            </div>
            {resource.sub_resources.length > 0 ? (
              <div class="oh-resource-usage-subresources">
                {resource.sub_resources.slice(0, 16).map((subResource) => (
                  <div key={subResource.resource_id}>
                    <span title={subResource.resource_id}>↳ {subResource.resource_id}</span>
                    <small>{subResource.successes} / {subResource.failures}</small>
                    <em>{formatDuration(subResource.average_duration_ms)}</em>
                    <b>{subResource.total}</b>
                  </div>
                ))}
              </div>
            ) : null}
          </article>
        );
      })}
    </div>
  );
}

function MetricPill({ label, error = false }: { label: string; error?: boolean }) {
  return <span class={`oh-resource-usage-metric${error ? ' is-error' : ''}`}>{label}</span>;
}

function RecentEvents({ events }: { events: ResourceUsageEvent[] }) {
  if (events.length === 0) return <EmptyChart label={t('resourceUsage.emptyRecent', '当前周期暂无详细调用记录')} />;
  return (
    <div class="oh-resource-usage-events">
      {events.map((event) => (
        <article key={event.event_id} class={`oh-resource-usage-event${event.succeeded ? '' : ' is-error'}`}>
          <header>
            <i />
            <strong title={`${event.resource_id}/${event.sub_resource_id}`}>{event.resource_id}{event.sub_resource_id ? ` / ${event.sub_resource_id}` : ''}</strong>
            <b>{statusLabel(event.status)}</b>
          </header>
          <div class="oh-resource-usage-event-meta">
            <span>◴ {formatLocalDateTimeSecond(event.occurred_at, '—')}</span>
            <span>◷ {formatDuration(event.duration_ms)}</span>
            <span title={event.session_id}>◇ {shortBucket(event.session_id)}</span>
            {event.source ? <span>↗ {event.source}</span> : null}
          </div>
          {event.arguments_summary ? <EventSummary label={t('resourceUsage.arguments', '参数')} value={event.arguments_summary} /> : null}
          {event.error_summary
            ? <EventSummary label={t('resourceUsage.error', '错误')} value={event.error_summary} error />
            : event.result_summary
              ? <EventSummary label={t('resourceUsage.result', '结果')} value={event.result_summary} />
              : null}
        </article>
      ))}
    </div>
  );
}

function EventSummary({ label, value, error = false }: { label: string; value: string; error?: boolean }) {
  return <p class={`oh-resource-usage-event-summary${error ? ' is-error' : ''}`}><b>{label}</b><span>{value}</span></p>;
}

function statusLabel(status: string): string {
  if (status === 'success') return t('resourceUsage.statusSuccess', '成功');
  if (status === 'cancelled') return t('resourceUsage.statusCancelled', '已取消');
  if (status === 'timed_out') return t('resourceUsage.statusTimedOut', '超时');
  if (status === 'denied' || status === 'rejected') return t('resourceUsage.statusDenied', '已拒绝');
  return t('resourceUsage.statusFailed', '失败');
}
