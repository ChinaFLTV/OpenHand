import { useRef, useState, useEffect, useCallback, useMemo } from 'preact/hooks';
import { clampNumber } from '../../../shared/util/number';
import {
  cacheHitDisplayData,
  DEFAULT_CACHE_HIT_DISPLAY_MODE,
  isFirstCacheHitRequest,
  type CacheHitDisplayMode,
  type CacheHitTrendPoint,
} from '../cache_hit_stats';

export type { CacheHitDisplayMode };

interface CacheHitTrendChartProps {
  points: CacheHitTrendPoint[];
  averageRatio: number;
  claudeStyle?: boolean;
  height?: number;
  displayMode?: CacheHitDisplayMode;
  onDisplayModeChange?: (mode: CacheHitDisplayMode) => void;
  t?: (key: string, fallback: string) => string;
}

const PAD_LEFT = 30;
const PAD_RIGHT = 8;
const PAD_TOP = 8;
const PAD_BOTTOM = 22;
const MIN_VISIBLE_POINTS = 6;
const CACHE_LINE_COLOR = 'var(--m3-primary)';
const CACHE_TREND_ENTRANCE_DURATION_MS = 560;
const CACHE_TREND_HOVER_IN_DURATION_MS = 240;
const CACHE_TREND_HOVER_OUT_DURATION_MS = 200;
const CACHE_TOOLTIP_WIDTH_PX = 132;
const CACHE_TOOLTIP_FIRST_WIDTH_PX = 148;
const CACHE_TOOLTIP_HEIGHT_PX = 46;
const CACHE_TOOLTIP_FIRST_HEIGHT_PX = 58;
const CACHE_TOOLTIP_OFFSET_PX = 12;

interface Viewport {
  start: number;
  end: number;
  totalPoints: number;
}

function vpSpan(v: Viewport): number {
  return v.end - v.start;
}

function viewportFull(n: number): Viewport {
  return { start: 0, end: Math.max(0, n - 1), totalPoints: Math.max(1, n) };
}

function viewportIsFullRange(v: Viewport): boolean {
  return v.start <= 0.0001 && Math.abs(v.end - (v.totalPoints - 1)) <= 0.0001;
}

function viewportZoomAround(
  v: Viewport,
  anchor: number,
  scale: number,
): Viewport {
  if (v.totalPoints <= 1) return v;
  const maxSpan = v.totalPoints - 1;
  const minSpan = Math.max(1, Math.min(MIN_VISIBLE_POINTS - 1, v.totalPoints - 1));
  const safeScale = Number.isFinite(scale) && scale > 0 ? scale : 1;
  const span = vpSpan(v);
  const nextSpan = clampNumber(span / safeScale, minSpan, maxSpan);
  const normalizedAnchor =
    span <= 0 ? 0 : clampNumber((anchor - v.start) / span, 0, 1);
  let nextStart = anchor - normalizedAnchor * nextSpan;
  let nextEnd = nextStart + nextSpan;
  if (nextStart < 0) {
    nextEnd -= nextStart;
    nextStart = 0;
  }
  if (nextEnd > maxSpan) {
    const overflow = nextEnd - maxSpan;
    nextStart = clampNumber(nextStart - overflow, 0, Math.max(0, maxSpan - nextSpan));
    nextEnd = maxSpan;
  }
  return { start: nextStart, end: nextEnd, totalPoints: v.totalPoints };
}

function buildSmoothPath(points: { x: number; y: number }[]): string {
  if (points.length === 0) return '';
  if (points.length === 1) return `M ${points[0].x},${points[0].y}`;
  const segs: string[] = [`M ${points[0].x},${points[0].y}`];
  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1];
    const cur = points[i];
    const dx = cur.x - prev.x;
    const cp1x = prev.x + dx * 0.35;
    const cp1y = prev.y;
    const cp2x = cur.x - dx * 0.35;
    const cp2y = cur.y;
    segs.push(`C ${cp1x},${cp1y} ${cp2x},${cp2y} ${cur.x},${cur.y}`);
  }
  return segs.join(' ');
}

function buildSmoothFillPath(
  points: { x: number; y: number }[],
  baselineY: number,
): string {
  if (points.length === 0) return '';
  const segs: string[] = [
    `M ${points[0].x},${baselineY}`,
    `L ${points[0].x},${points[0].y}`,
  ];
  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1];
    const cur = points[i];
    const dx = cur.x - prev.x;
    segs.push(
      `C ${prev.x + dx * 0.35},${prev.y} ${cur.x - dx * 0.35},${cur.y} ${cur.x},${cur.y}`,
    );
  }
  segs.push(`L ${points[points.length - 1].x},${baselineY} Z`);
  return segs.join(' ');
}

const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3);
const easeInCubic = (t: number) => t * t * t;

function cacheHitExclusionHint(
  displayData: ReturnType<typeof cacheHitDisplayData>,
  displayMode: CacheHitDisplayMode,
  t: (key: string, fallback: string) => string,
): string {
  if (
    displayMode === 'includeExpiredMisses' ||
    displayData.excludedExpiredMissCount <= 0
  ) {
    return '';
  }
  return t('tokenPopup.excludedRounds', '已排除 {{n}} 轮').replace(
    '{{n}}',
    String(displayData.excludedPointCount),
  );
}

export default function CacheHitTrendChart({
  points,
  averageRatio,
  claudeStyle = false,
  height = 168,
  displayMode = DEFAULT_CACHE_HIT_DISPLAY_MODE,
  onDisplayModeChange,
  t = (_k: string, fallback: string) => fallback,
}: CacheHitTrendChartProps) {
  const t2 = useCallback((k: string, fb: string) => t(k, fb), [t]);

  const displayData = useMemo(
    () =>
      cacheHitDisplayData({
        points,
        displayMode,
        claudeStyle,
        fallbackAverageRatio: averageRatio,
      }),
    [points, displayMode, claudeStyle, averageRatio],
  );
  const filteredPoints = displayData.points;
  const displayedAverageRatio = displayData.averageRatio;
  const hasDrawablePoints = filteredPoints.length >= 1;
  const modeOptions = useMemo(
    () =>
      [
        [
          'excludeExpiredMisses',
          t2('tokenPopup.cacheHitMode.excludeExpired', '不包含过期异常'),
        ],
        [
          'includeExpiredMisses',
          t2('tokenPopup.cacheHitMode.includeExpired', '含过期异常'),
        ],
      ] as Array<[CacheHitDisplayMode, string]>,
    [t2],
  );
  const exclusionHint = cacheHitExclusionHint(displayData, displayMode, t2);

  const [viewport, setViewport] = useState<Viewport>(() =>
    viewportFull(filteredPoints.length),
  );

  useEffect(() => {
    setViewport(viewportFull(filteredPoints.length));
  }, [filteredPoints.length]);

  // Entrance animation
  const [animProgress, setAnimProgress] = useState(0);
  useEffect(() => {
    const start = performance.now();
    let raf = 0;
    const tick = () => {
      const now = performance.now();
      const t = (now - start) / CACHE_TREND_ENTRANCE_DURATION_MS;
      const v = clampNumber(t, 0, 1);
      setAnimProgress(v);
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [filteredPoints.length]);

  // Hover state
  const [hoverIdx, setHoverIdx] = useState(-1);
  const [hoverAnim, setHoverAnim] = useState(0);
  useEffect(() => {
    const target = hoverIdx >= 0 ? 1 : 0;
    const dur = target === 1 ? CACHE_TREND_HOVER_IN_DURATION_MS : CACHE_TREND_HOVER_OUT_DURATION_MS;
    const start = performance.now();
    const from = hoverAnim;
    let raf = 0;
    const tick = () => {
      const now = performance.now();
      const t = clampNumber((now - start) / dur, 0, 1);
      const eased = target === 1 ? easeOutCubic(t) : easeInCubic(t);
      setHoverAnim(from + (target - from) * eased);
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [hoverIdx]);

  const svgRef = useRef<SVGSVGElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [containerW, setContainerW] = useState(360);
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setContainerW(Math.max(1, entry.contentRect.width));
      }
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const chartW = Math.max(1, containerW - PAD_LEFT - PAD_RIGHT);
  const chartH = Math.max(1, height - PAD_TOP - PAD_BOTTOM);
  const totalW = chartW + PAD_LEFT + PAD_RIGHT;

  const visiblePoints = useMemo(() => {
    if (filteredPoints.length === 0) return [];
    const start = Math.max(0, Math.floor(viewport.start));
    const end = Math.min(filteredPoints.length - 1, Math.ceil(viewport.end));
    return filteredPoints.slice(start, end + 1);
  }, [filteredPoints, viewport]);

  const layoutPoints = useMemo(() => {
    if (visiblePoints.length === 0) return [];
    const stepX =
      visiblePoints.length <= 1 ? chartW : chartW / (visiblePoints.length - 1);
    return visiblePoints.map((p, i) => ({
      x: PAD_LEFT + (visiblePoints.length <= 1 ? chartW / 2 : stepX * i),
      y: PAD_TOP + chartH - chartH * clampNumber(p.hitRatio, 0, 1),
      hitRatio: p.hitRatio,
      turnIndex: p.turnIndex,
      firstRequest: isFirstCacheHitRequest(p),
    }));
  }, [visiblePoints, chartW, chartH]);

  const easedProgress = easeOutCubic(clampNumber(animProgress, 0, 1));
  const visibleCount =
    layoutPoints.length <= 1
      ? easedProgress
      : easedProgress * (layoutPoints.length - 1) + 1;
  const fullCount = Math.min(layoutPoints.length, Math.floor(visibleCount));
  const partial = Math.max(0, visibleCount - Math.floor(visibleCount));

  const animatedLayoutPoints = useMemo(() => {
    if (layoutPoints.length === 0) return [];
    if (fullCount >= layoutPoints.length) return layoutPoints;
    const out = layoutPoints.slice(0, fullCount);
    if (partial > 0 && fullCount > 0) {
      const prev = layoutPoints[fullCount - 1];
      const next = layoutPoints[fullCount];
      out.push({
        x: prev.x + (next.x - prev.x) * partial,
        y: prev.y + (next.y - prev.y) * partial,
        hitRatio: prev.hitRatio + (next.hitRatio - prev.hitRatio) * partial,
        turnIndex: prev.turnIndex,
        firstRequest: prev.firstRequest,
      });
    }
    return out;
  }, [layoutPoints, fullCount, partial]);

  const linePath = buildSmoothPath(animatedLayoutPoints);
  const fillPath = buildSmoothFillPath(animatedLayoutPoints, PAD_TOP + chartH);

  const avgY =
    PAD_TOP + chartH - chartH * clampNumber(displayedAverageRatio, 0, 1);

  const showMiddleLabel =
    visiblePoints.length > 2
      ? visiblePoints[Math.floor(visiblePoints.length / 2)].turnIndex !==
          visiblePoints[0].turnIndex &&
        visiblePoints[Math.floor(visiblePoints.length / 2)].turnIndex !==
          visiblePoints[visiblePoints.length - 1].turnIndex
      : false;
  const firstTurn = visiblePoints[0]?.turnIndex ?? 0;
  const lastTurn = visiblePoints[visiblePoints.length - 1]?.turnIndex ?? 0;
  const middleIdx = Math.floor(visiblePoints.length / 2);
  const middleTurn = visiblePoints[middleIdx]?.turnIndex ?? 0;
  const middleX = layoutPoints[middleIdx]?.x ?? 0;
  const firstBadgeText = t2('tokenPopup.firstRequestShort', '首轮不计');

  const onMouseMove = useCallback(
    (e: MouseEvent) => {
      if (visiblePoints.length === 0) return;
      const svg = svgRef.current;
      if (!svg) return;
      const r = svg.getBoundingClientRect();
      const scaleX = r.width / totalW;
      const x = (e.clientX - r.left) / scaleX - PAD_LEFT;
      if (x < 0 || x > chartW) {
        if (hoverIdx >= 0) setHoverIdx(-1);
        return;
      }
      const stepX =
        visiblePoints.length <= 1 ? 0 : chartW / (visiblePoints.length - 1);
      const raw = stepX <= 0 ? 0 : Math.round(x / stepX);
      const idx = Math.round(clampNumber(raw, 0, visiblePoints.length - 1));
      if (idx !== hoverIdx) setHoverIdx(idx);
    },
    [visiblePoints, chartW, hoverIdx, totalW],
  );

  const onMouseLeave = useCallback(() => {
    if (hoverIdx >= 0) setHoverIdx(-1);
  }, [hoverIdx]);

  const onWheel = useCallback(
    (e: WheelEvent) => {
      e.preventDefault();
      const svg = svgRef.current;
      if (!svg) return;
      const r = svg.getBoundingClientRect();
      const scaleX = r.width / totalW;
      const localDx = clampNumber((e.clientX - r.left) / scaleX - PAD_LEFT, 0, chartW);
      const span = vpSpan(viewport);
      const anchor =
        viewport.start + (chartW <= 0 ? 0 : (localDx / chartW) * span);
      const scale = e.deltaY > 0 ? 0.88 : 1.12;
      setViewport((v) => viewportZoomAround(v, anchor, scale));
    },
    [viewport, chartW, totalW],
  );

  if (!hasDrawablePoints) {
    return (
      <div
        ref={containerRef}
        class="rounded-m3-md"
        style={{
          background: 'var(--m3-surface-container-high)',
          border: '1px solid var(--m3-outline-variant)',
          padding: '10px 12px 12px 12px',
        }}
      >
        <div
          class="flex items-center"
          style={{ gap: 8, marginBottom: 8 }}
        >
          <span
            class="text-xs font-bold"
            style={{
              color: 'var(--m3-on-surface-variant)',
              letterSpacing: '0.6px',
              flex: 1,
            }}
          >
            {t2('sessMeta.cacheHitTrend', '缓存命中率趋势')}
          </span>
          <span
            class="text-xs"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {t2('sessMeta.cacheHitAvg', '平均')}:{' '}
            {Math.round(displayedAverageRatio * 100)}%
          </span>
        </div>
        <div
          class="text-xs"
          style={{ color: 'var(--m3-on-surface-variant)', marginBottom: 10 }}
        >
          {points.length <= 0
            ? t2(
                'tokenPopup.trendNoData',
                '尚无缓存命中率数据，发送消息后将在此展示走势。',
              )
            : displayMode === 'excludeExpiredMisses'
              ? t2(
                'tokenPopup.trendOnlyFirstIgnored',
                '首轮请求不参与平均，下一轮正常请求后展示趋势。',
              )
              : t2(
                'tokenPopup.trendFirstReferenceOnly',
                '首轮仅作参考，不参与平均缓存命中率。',
              )}
        </div>
        <div class="flex items-center" style={{ gap: 8 }}>
          <div
            class="flex items-center"
            style={{ gap: 8, flexWrap: 'nowrap', overflowX: 'auto' }}
          >
            {modeOptions.map(([key, label]) => {
              const selected = displayMode === key;
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => {
                    setViewport(viewportFull(points.length));
                    onDisplayModeChange?.(key);
                  }}
                  style={{
                    borderRadius: 999,
                    padding: '5px 10px',
                    fontSize: 11,
                    fontWeight: 700,
                    whiteSpace: 'nowrap',
                    flexShrink: 0,
                    border: selected
                      ? '1px solid color-mix(in srgb, var(--m3-primary) 50%, transparent)'
                      : '1px solid var(--m3-outline-variant)',
                    background: selected
                      ? 'color-mix(in srgb, var(--m3-primary) 12%, transparent)'
                      : 'color-mix(in srgb, var(--m3-surface-container-highest) 50%, transparent)',
                    color: selected
                      ? 'var(--m3-primary)'
                      : 'var(--m3-on-surface-variant)',
                    cursor: 'pointer',
                    transition: 'all 220ms cubic-bezier(0.33, 1, 0.68, 1)',
                  }}
                >
                  {label}
                </button>
              );
            })}
          </div>
          <div style={{ flex: 1 }} />
          {exclusionHint ? (
            <span
              class="text-xs"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {exclusionHint}
            </span>
          ) : null}
        </div>
      </div>
    );
  }

  const singlePoint = visiblePoints.length === 1;
  const notFullRange = !viewportIsFullRange(viewport);

  return (
    <div
      ref={containerRef}
      class="rounded-m3-md"
      style={{
        background: 'var(--m3-surface-container-high)',
        border: '1px solid var(--m3-outline-variant)',
        padding: '10px 12px 12px 12px',
      }}
    >
      {/* Header row */}
      <div
        class="flex items-center"
        style={{ gap: 8, marginBottom: 8 }}
      >
        <span
          class="text-xs font-bold"
          style={{
            color: 'var(--m3-on-surface-variant)',
            letterSpacing: '0.6px',
            flex: 1,
          }}
        >
          {t2('sessMeta.cacheHitTrend', '缓存命中率趋势')}
        </span>
        <span
          class="text-xs"
          style={{
            color: 'var(--m3-on-surface-variant)',
            fontFeatureSettings: '"tnum" 1',
          }}
        >
          {t2('sessMeta.cacheHitAvg', '平均')}:{' '}
          {Math.round(displayedAverageRatio * 100)}%
        </span>
        <button
          type="button"
          class="oh-tap-press"
          style={{
            background: 'transparent',
            border: 'none',
            padding: '4px 6px',
            cursor: 'pointer',
            color: 'var(--m3-primary)',
            fontWeight: 700,
            fontSize: 12,
            borderRadius: 8,
          }}
          onClick={() => {
            const anchor = viewport.start + vpSpan(viewport) / 2;
            setViewport((v) => viewportZoomAround(v, anchor, 1.35));
          }}
        >
          {t2('imageEditor.zoom', '缩放')}
        </button>
        {notFullRange ? (
          <button
            type="button"
            class="oh-tap-press"
            style={{
              background: 'transparent',
              border: 'none',
              padding: '4px 6px',
              cursor: 'pointer',
              color: 'var(--m3-primary)',
              fontWeight: 700,
              fontSize: 12,
              borderRadius: 8,
            }}
            onClick={() => setViewport(viewportFull(filteredPoints.length))}
          >
            {t2('settings.reset', '重置')}
          </button>
        ) : null}
      </div>

      {/* Mode chips row */}
      <div
        class="flex items-center"
        style={{ gap: 8, marginBottom: 10 }}
      >
        <div
          class="flex items-center"
          style={{ gap: 8, flexWrap: 'nowrap', overflowX: 'auto' }}
        >
          {modeOptions.map(([key, label]) => {
            const selected = displayMode === key;
            return (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setViewport(viewportFull(filteredPoints.length));
                  onDisplayModeChange?.(key);
                }}
                style={{
                  borderRadius: 999,
                  padding: '5px 10px',
                  fontSize: 11,
                  fontWeight: 700,
                  whiteSpace: 'nowrap',
                  flexShrink: 0,
                  border: selected
                    ? '1px solid color-mix(in srgb, var(--m3-primary) 50%, transparent)'
                    : '1px solid var(--m3-outline-variant)',
                  background: selected
                    ? 'color-mix(in srgb, var(--m3-primary) 12%, transparent)'
                    : 'color-mix(in srgb, var(--m3-surface-container-highest) 50%, transparent)',
                  color: selected
                    ? 'var(--m3-primary)'
                    : 'var(--m3-on-surface-variant)',
                  cursor: 'pointer',
                  transition: 'all 220ms cubic-bezier(0.33, 1, 0.68, 1)',
                }}
              >
                {label}
              </button>
            );
          })}
        </div>
        <div style={{ flex: 1 }} />
        {exclusionHint ? (
          <span
            class="text-xs"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {exclusionHint}
          </span>
        ) : null}
      </div>

      {/* Chart canvas */}
      <div
        style={{ position: 'relative', height, width: '100%' }}
        onWheel={onWheel as unknown as (e: Event) => void}
        onMouseMove={onMouseMove as unknown as (e: Event) => void}
        onMouseLeave={onMouseLeave}
      >
        <svg
          ref={svgRef}
          viewBox={`0 0 ${totalW} ${height}`}
          width="100%"
          height={height}
          style={{ display: 'block', overflow: 'visible', cursor: 'crosshair' }}
        >
          {/* 5 horizontal grid lines */}
          {[0, 0.25, 0.5, 0.75, 1].map((frac) => {
            const y = PAD_TOP + chartH - chartH * frac;
            return (
              <line
                key={`grid-${frac}`}
                x1={PAD_LEFT}
                x2={PAD_LEFT + chartW}
                y1={y}
                y2={y}
                stroke="var(--m3-outline-variant)"
                stroke-opacity="0.35"
                stroke-width="1"
              />
            );
          })}

          {/* Y axis labels: 0% bottom-left, 100% top-left */}
          <text
            x={PAD_LEFT - 8}
            y={PAD_TOP + chartH + 4}
            text-anchor="end"
            fill="var(--m3-on-surface-variant)"
            font-size="9"
            style={{ fontFeatureSettings: '"tnum" 1' }}
          >
            0%
          </text>
          <text
            x={PAD_LEFT - 8}
            y={PAD_TOP + 6}
            text-anchor="end"
            fill="var(--m3-on-surface-variant)"
            font-size="9"
            style={{ fontFeatureSettings: '"tnum" 1' }}
          >
            100%
          </text>

          {/* Average dashed line */}
          <line
            x1={PAD_LEFT}
            x2={PAD_LEFT + chartW}
            y1={avgY}
            y2={avgY}
            stroke={CACHE_LINE_COLOR}
            stroke-opacity="0.6"
            stroke-width="1.1"
            stroke-dasharray="5 4"
          />

          {/* Fill + line (smooth cubic bezier) */}
          <defs>
            <linearGradient id="cht-fill" x1="0" y1="0" x2="0" y2="1">
              <stop
                offset="0%"
                stop-color={CACHE_LINE_COLOR}
                stop-opacity="0.18"
              />
              <stop
                offset="100%"
                stop-color={CACHE_LINE_COLOR}
                stop-opacity="0.02"
              />
            </linearGradient>
          </defs>
          {fillPath ? <path d={fillPath} fill="url(#cht-fill)" /> : null}
          {linePath ? (
            <path
              d={linePath}
              fill="none"
              stroke={CACHE_LINE_COLOR}
              stroke-opacity="0.72"
              stroke-width="2"
              stroke-linejoin="round"
              stroke-linecap="round"
            />
          ) : null}

          {/* First request marker: visible in "include expired" mode, but excluded from averages. */}
          {layoutPoints
            .filter((point) => point.firstRequest)
            .map((point) => {
              const badgeW = 52;
              const badgeH = 16;
              const badgeX = clampNumber(
                point.x + 8,
                PAD_LEFT,
                PAD_LEFT + chartW - badgeW,
              );
              const badgeY = clampNumber(
                point.y - 10,
                PAD_TOP,
                PAD_TOP + chartH - badgeH,
              );
              return (
                <g key={`first-${point.turnIndex}`}>
                  <circle
                    cx={point.x}
                    cy={point.y}
                    r="4.4"
                    fill="var(--m3-surface)"
                    opacity="0.94"
                  />
                  <circle
                    cx={point.x}
                    cy={point.y}
                    r="4.4"
                    fill="none"
                    stroke="var(--m3-on-surface-variant)"
                    stroke-opacity="0.78"
                    stroke-width="1.4"
                  />
                  <circle
                    cx={point.x}
                    cy={point.y}
                    r="1.7"
                    fill="var(--m3-on-surface-variant)"
                    opacity="0.68"
                  />
                  <rect
                    x={badgeX}
                    y={badgeY}
                    width={badgeW}
                    height={badgeH}
                    rx="4"
                    fill="var(--m3-surface)"
                    opacity="0.94"
                    stroke="var(--m3-outline-variant)"
                    stroke-opacity="0.55"
                  />
                  <text
                    x={badgeX + badgeW / 2}
                    y={badgeY + 11}
                    text-anchor="middle"
                    fill="var(--m3-on-surface-variant)"
                    font-size="9"
                    font-weight="700"
                  >
                    {firstBadgeText}
                  </text>
                </g>
              );
            })}

          {/* Last point dot */}
          {animatedLayoutPoints.length > 0
            ? (() => {
                const last =
                  animatedLayoutPoints[animatedLayoutPoints.length - 1];
                if (last.firstRequest) return null;
                return (
                  <circle
                    cx={last.x}
                    cy={last.y}
                    r="3.6"
                    fill={CACHE_LINE_COLOR}
                  />
                );
              })()
            : null}

          {/* "平均" label floating on right end of avg line */}
          <rect
            x={PAD_LEFT + chartW - 38}
            y={avgY - 9}
            width="34"
            height="18"
            rx="4"
            fill="var(--m3-surface)"
            opacity="0.96"
          />
          <text
            x={PAD_LEFT + chartW - 21}
            y={avgY + 4}
            text-anchor="middle"
            fill={CACHE_LINE_COLOR}
            font-size="10"
            font-weight="700"
            style={{ fontFeatureSettings: '"tnum" 1' }}
          >
            {t2('sessMeta.cacheHitAvg', '平均')}
          </text>

          {/* X axis labels: first, middle (if distinct), last */}
          <text
            x={singlePoint ? PAD_LEFT + chartW / 2 : PAD_LEFT}
            y={PAD_TOP + chartH + 14}
            text-anchor="middle"
            fill="var(--m3-on-surface-variant)"
            font-size="9"
            style={{ fontFeatureSettings: '"tnum" 1' }}
          >
            {firstTurn}
          </text>
          {showMiddleLabel ? (
            <text
              x={middleX}
              y={PAD_TOP + chartH + 14}
              text-anchor="middle"
              fill="var(--m3-on-surface-variant)"
              font-size="9"
              style={{ fontFeatureSettings: '"tnum" 1' }}
            >
              {middleTurn}
            </text>
          ) : null}
          {!singlePoint ? (
            <text
              x={PAD_LEFT + chartW}
              y={PAD_TOP + chartH + 14}
              text-anchor="middle"
              fill="var(--m3-on-surface-variant)"
              font-size="9"
              style={{ fontFeatureSettings: '"tnum" 1' }}
            >
              {lastTurn}
            </text>
          ) : null}
        </svg>

        {/* Hover overlay: glowing circle + tooltip */}
        {hoverIdx >= 0 && hoverIdx < layoutPoints.length && hoverAnim > 0.01
          ? (() => {
              const point = layoutPoints[hoverIdx];
              const ratio = point.hitRatio;
              const cy = point.y;
              const cx = point.x;
              const tooltipH = point.firstRequest
                ? CACHE_TOOLTIP_FIRST_HEIGHT_PX
                : CACHE_TOOLTIP_HEIGHT_PX;
              const tooltipW = point.firstRequest
                ? CACHE_TOOLTIP_FIRST_WIDTH_PX
                : CACHE_TOOLTIP_WIDTH_PX;
              const showAbove = cy - tooltipH - CACHE_TOOLTIP_OFFSET_PX >= PAD_TOP;
              const tooltipTop = showAbove
                ? cy - tooltipH - CACHE_TOOLTIP_OFFSET_PX
                : clampNumber(
                    cy + CACHE_TOOLTIP_OFFSET_PX,
                    PAD_TOP,
                    Math.max(PAD_TOP, PAD_TOP + chartH - tooltipH),
                  );
              const tooltipLeft = clampNumber(
                cx - tooltipW / 2,
                PAD_LEFT,
                Math.max(PAD_LEFT, PAD_LEFT + chartW - tooltipW),
              );
              const tipColor = point.firstRequest
                ? 'var(--m3-on-surface-variant)'
                : ratio >= 0.5
                  ? CACHE_LINE_COLOR
                  : 'var(--m3-on-surface)';
              const scale = hoverAnim;
              return (
                <>
                  <div
                    style={{
                      position: 'absolute',
                      left: cx - 9,
                      top: cy - 9,
                      width: 18,
                      height: 18,
                      borderRadius: '50%',
                      background: point.firstRequest
                        ? 'var(--m3-on-surface-variant)'
                        : 'var(--m3-primary)',
                      opacity: 0.18 * scale,
                      pointerEvents: 'none',
                      transform: `scale(${scale})`,
                    }}
                  />
                  <div
                    style={{
                      position: 'absolute',
                      left: cx - 4,
                      top: cy - 4,
                      width: 8,
                      height: 8,
                      borderRadius: '50%',
                      background: point.firstRequest
                        ? 'var(--m3-on-surface-variant)'
                        : 'var(--m3-primary)',
                      border: '1.4px solid var(--m3-surface)',
                      pointerEvents: 'none',
                      transform: `scale(${scale})`,
                    }}
                  />
                  <div
                    style={{
                      position: 'absolute',
                      left: tooltipLeft,
                      top: tooltipTop,
                      width: tooltipW,
                      height: tooltipH,
                      padding: '6px 10px',
                      background: 'var(--m3-surface-container-high)',
                      border: '1px solid var(--m3-outline-variant)',
                      borderRadius: 8,
                      boxShadow: 'var(--m3-elev-2)',
                      pointerEvents: 'none',
                      transform: `scale(${scale})`,
                      transformOrigin: showAbove
                        ? 'bottom center'
                        : 'top center',
                      display: 'flex',
                      flexDirection: 'column',
                      justifyContent: 'center',
                      zIndex: 10,
                    }}
                  >
                    <div
                      style={{
                        fontSize: 10,
                        color: 'var(--m3-on-surface-variant)',
                        fontWeight: 600,
                        lineHeight: 1.1,
                      }}
                    >
                      {t2(
                        'sessMeta.cacheHitPoint',
                        '第 {{n}} 轮',
                      ).replace('{{n}}', String(point.turnIndex))}
                    </div>
                    <div
                      style={{
                        fontSize: 14,
                        color: tipColor,
                        fontWeight: 800,
                        lineHeight: 1.0,
                        fontFeatureSettings: '"tnum" 1',
                        marginTop: 2,
                      }}
                    >
                      {Math.round(ratio * 100)}%
                    </div>
                    {point.firstRequest ? (
                      <div
                        style={{
                          fontSize: 10,
                          color: 'var(--m3-on-surface-variant)',
                          fontWeight: 700,
                          lineHeight: 1.0,
                          marginTop: 4,
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {t2('tokenPopup.firstRequestNotAveraged', '不参与平均')}
                      </div>
                    ) : null}
                  </div>
                </>
              );
            })()
          : null}
      </div>
    </div>
  );
}
