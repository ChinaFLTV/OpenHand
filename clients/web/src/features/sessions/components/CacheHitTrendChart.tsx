import { useRef, useState, useEffect, useCallback, useMemo } from 'preact/hooks';

interface TrendPoint {
  turnIndex: number;
  hitRatio: number;
  starterMessageId?: string | null;
  starterMessageKind?: string | null;
  starterOrigin?: string | null;
  idleGapSeconds?: number | null;
}

export type CacheHitDisplayMode = 'excludeExtremeMisses' | 'includeAll';

interface CacheHitTrendChartProps {
  points: TrendPoint[];
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
const EXTREME_IDLE_GAP_SECONDS = 1800; // 30 min
const EXTREME_HIT_RATIO_THRESHOLD = 0.01; // 1%
const MIN_VISIBLE_POINTS = 6;
const CACHE_LINE_COLOR = '#2E7D32';

function isExtremeIdleExpiryMiss(p: TrendPoint): boolean {
  const gap = p.idleGapSeconds ?? 0;
  if (gap < EXTREME_IDLE_GAP_SECONDS) return false;
  return p.hitRatio < EXTREME_HIT_RATIO_THRESHOLD;
}

function isCleanTrendPoint(p: TrendPoint): boolean {
  return p.turnIndex !== 1 && !isExtremeIdleExpiryMiss(p);
}

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
  const safeScale = scale <= 0 ? 1 : scale;
  const span = vpSpan(v);
  const nextSpan = Math.max(minSpan, Math.min(maxSpan, span / safeScale));
  const normalizedAnchor =
    span <= 0 ? 0 : Math.max(0, Math.min(1, (anchor - v.start) / span));
  let nextStart = anchor - normalizedAnchor * nextSpan;
  let nextEnd = nextStart + nextSpan;
  if (nextStart < 0) {
    nextEnd -= nextStart;
    nextStart = 0;
  }
  if (nextEnd > maxSpan) {
    const overflow = nextEnd - maxSpan;
    nextStart = Math.max(0, Math.min(maxSpan - nextSpan, nextStart - overflow));
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

export default function CacheHitTrendChart({
  points,
  averageRatio,
  height = 168,
  displayMode = 'excludeExtremeMisses',
  onDisplayModeChange,
  t = (_k: string, fallback: string) => fallback,
}: CacheHitTrendChartProps) {
  const t2 = useCallback((k: string, fb: string) => t(k, fb), [t]);

  const filteredPoints = useMemo(() => {
    if (displayMode === 'includeAll') return points;
    return points.filter(isCleanTrendPoint);
  }, [points, displayMode]);

  const excludedCount = points.length - filteredPoints.length;
  const hasEnough = filteredPoints.length >= 2;

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
    const dur = 560;
    let raf = 0;
    const tick = () => {
      const now = performance.now();
      const t = (now - start) / dur;
      const v = Math.max(0, Math.min(1, t));
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
    const dur = target === 1 ? 240 : 200;
    const start = performance.now();
    const from = hoverAnim;
    let raf = 0;
    const tick = () => {
      const now = performance.now();
      const t = Math.max(0, Math.min(1, (now - start) / dur));
      const eased = target === 1 ? easeOutCubic(t) : easeInCubic(t);
      setHoverAnim(from + (target - from) * eased);
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
      x: PAD_LEFT + stepX * i,
      y: PAD_TOP + chartH - chartH * Math.min(1, Math.max(0, p.hitRatio)),
      hitRatio: p.hitRatio,
      turnIndex: p.turnIndex,
    }));
  }, [visiblePoints, chartW, chartH]);

  const easedProgress = easeOutCubic(
    Math.max(0, Math.min(1, animProgress)),
  );
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
      });
    }
    return out;
  }, [layoutPoints, fullCount, partial]);

  const linePath = buildSmoothPath(animatedLayoutPoints);
  const fillPath = buildSmoothFillPath(animatedLayoutPoints, PAD_TOP + chartH);

  const avgY =
    PAD_TOP + chartH - chartH * Math.max(0, Math.min(1, averageRatio));

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
      const idx = Math.max(0, Math.min(visiblePoints.length - 1, raw));
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
      const localDx = Math.max(
        0,
        Math.min(chartW, (e.clientX - r.left) / scaleX - PAD_LEFT),
      );
      const span = vpSpan(viewport);
      const anchor =
        viewport.start + (chartW <= 0 ? 0 : (localDx / chartW) * span);
      const scale = e.deltaY > 0 ? 0.88 : 1.12;
      setViewport((v) => viewportZoomAround(v, anchor, scale));
    },
    [viewport, chartW, totalW],
  );

  if (!hasEnough) {
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
            {Math.round(averageRatio * 100)}%
          </span>
        </div>
        <div
          class="text-xs"
          style={{ color: 'var(--m3-on-surface-variant)' }}
        >
          {filteredPoints.length === 0
            ? t2(
                'tokenPopup.trendNoData',
                '尚无缓存命中率数据，发送消息后将在此展示走势。',
              )
            : t2(
                'tokenPopup.trendNeedMore',
                '需至少 2 轮对话方可绘制走势图。',
              )}
        </div>
      </div>
    );
  }

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
          {Math.round(averageRatio * 100)}%
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
        <div class="flex items-center" style={{ gap: 8 }}>
          {(
            [
              ['excludeExtremeMisses', '排除极端值'],
              ['includeAll', '包括全部'],
            ] as Array<[CacheHitDisplayMode, string]>
          ).map(([key, label]) => {
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
        {excludedCount > 0 ? (
          <span
            class="text-xs"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {t2('tokenPopup.excludedRounds', '已排除 {{n}} 轮').replace(
              '{{n}}',
              String(excludedCount),
            )}
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

          {/* Last point dot */}
          {animatedLayoutPoints.length > 0
            ? (() => {
                const last =
                  animatedLayoutPoints[animatedLayoutPoints.length - 1];
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
            x={PAD_LEFT}
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
        </svg>

        {/* Hover overlay: glowing circle + tooltip */}
        {hoverIdx >= 0 && hoverIdx < layoutPoints.length && hoverAnim > 0.01
          ? (() => {
              const point = layoutPoints[hoverIdx];
              const ratio = point.hitRatio;
              const cy = point.y;
              const cx = point.x;
              const tooltipH = 46;
              const tooltipW = 132;
              const showAbove = cy - tooltipH - 12 >= PAD_TOP;
              const tooltipTop = showAbove
                ? cy - tooltipH - 12
                : Math.min(
                    PAD_TOP + chartH - tooltipH,
                    Math.max(PAD_TOP, cy + 12),
                  );
              const tooltipLeft = Math.max(
                PAD_LEFT,
                Math.min(PAD_LEFT + chartW - tooltipW, cx - tooltipW / 2),
              );
              const tipColor =
                ratio >= 0.95
                  ? CACHE_LINE_COLOR
                  : ratio >= 0.5
                    ? 'var(--m3-primary)'
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
                      background: 'var(--m3-primary)',
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
                      background: 'var(--m3-primary)',
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
                      boxShadow: '0 2px 10px rgba(0,0,0,0.18)',
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
                  </div>
                </>
              );
            })()
          : null}
      </div>
    </div>
  );
}
