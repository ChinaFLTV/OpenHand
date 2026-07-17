import type { JSX } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';
import {
  getResourceUsage,
  type ResourceUsageKind,
  type ResourceUsageLevel,
  type ResourceUsageLevelSnapshot,
  type ResourceUsageSnapshot,
} from '../api/toolbox';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import { describeApiError } from '../utils/api_error';
import {
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

const LEVELS: ResourceUsageLevel[] = ['session', 'day', 'week', 'month', 'quarter', 'year'];
const CHART_COLORS = ['#6d5dfc', '#14b8a6', '#f59e0b', '#ec4899', '#38bdf8', '#94a3b8'];

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
    tool: '工具', skill: '技能', hook: 'Hook', knowledge: '知识库', agent: '智能体', memory: '记忆', mcp: 'MCP',
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

export function ResourceUsageDialog({ kind, labels = {}, onClose }: ResourceUsageDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [snapshot, setSnapshot] = useState<ResourceUsageSnapshot | null>(null);
  const [levelKey, setLevelKey] = useState<ResourceUsageLevel>('day');
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();
    void getResourceUsage(kind, { signal: controller.signal })
      .then((value) => {
        if (!controller.signal.aborted) setSnapshot(value);
      })
      .catch((reason) => {
        if (!controller.signal.aborted) setError(describeApiError(reason));
      });
    return () => controller.abort();
  }, [kind]);

  const level = snapshot?.levels?.[levelKey] ?? null;
  const entries = useMemo(() => level ? sortedEntries(level) : [], [level]);
  const top = entries[0];
  const topShare = top && level?.total ? top[1] / level.total : 0;

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayClassName: 'fixed inset-0 flex items-center justify-center p-4',
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
          <p>{t('resourceUsage.subtitle', '从会话到年度，洞察调用结构、占比与变化趋势')}</p>
        </div>
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
              <SummaryCard icon="◇" label={t('resourceUsage.active', '活跃资源')} value={String(level.resource_count ?? entries.length)} />
              <SummaryCard icon="★" label={t('resourceUsage.top', '首位资源')} value={top ? (labels[top[0]] || top[0]) : '—'} detail={`${(topShare * 100).toFixed(1)}%`} />
              <SummaryCard icon="▣" label={t('resourceUsage.bucket', '当前周期')} value={shortBucket(level.bucket)} />
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
          </>
        ) : null}
      </div>
    </DialogFrame>
  );
}

function SummaryCard(props: { icon: string; label: string; value: string; detail?: string }) {
  return (
    <article class="oh-resource-usage-summary-card">
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
  const line = coordinates.map((point) => `${point.x},${point.y}`).join(' ');
  const area = `${insetX},${insetY + chartHeight} ${line} ${coordinates.at(-1)?.x ?? insetX},${insetY + chartHeight}`;
  return (
    <div class="oh-resource-usage-trend">
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" role="img" aria-label={t('resourceUsage.trend', '调用趋势')}>
        <defs><linearGradient id="oh-usage-area" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--m3-primary)" stop-opacity=".28"/><stop offset="1" stop-color="var(--m3-primary)" stop-opacity="0"/></linearGradient></defs>
        {[0, 1, 2, 3, 4].map((row) => <line key={row} x1={insetX} x2={width - insetX} y1={insetY + chartHeight * row / 4} y2={insetY + chartHeight * row / 4} class="oh-resource-usage-gridline" />)}
        <polygon points={area} fill="url(#oh-usage-area)" />
        <polyline points={line} class="oh-resource-usage-line" />
        {coordinates.map(({ x, y, point }) => <circle key={point.bucket} cx={x} cy={y} r="4" class="oh-resource-usage-dot"><title>{point.bucket}: {point.total}</title></circle>)}
      </svg>
      <div><span>{shortBucket(points[0].bucket)}</span><span>{shortBucket(points.at(-1)?.bucket ?? '')}</span></div>
    </div>
  );
}

function Distribution(props: { entries: Array<[string, number]>; labels: Record<string, string>; total: number }) {
  if (props.entries.length === 0 || props.total <= 0) return <EmptyChart label={t('resourceUsage.emptyShare', '暂无占比数据')} />;
  const visible = props.entries.slice(0, 5);
  const other = Math.max(0, props.total - visible.reduce((sum, entry) => sum + entry[1], 0));
  let cursor = 0;
  const segments = visible.map((entry, index) => {
    const start = cursor;
    cursor += entry[1] / props.total * 100;
    return `${CHART_COLORS[index]} ${start}% ${cursor}%`;
  });
  if (other > 0) segments.push(`${CHART_COLORS[5]} ${cursor}% 100%`);
  return (
    <div class="oh-resource-usage-distribution">
      <div class="oh-resource-usage-donut" style={{ background: `conic-gradient(${segments.join(',')})` }}>
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
