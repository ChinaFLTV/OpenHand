import { useRef, useState, useEffect, useCallback } from 'preact/hooks';

interface TrendPoint {
  turnIndex: number;
  hitRatio: number;
}

interface CacheHitTrendChartProps {
  points: TrendPoint[];
  averageRatio: number;
  height?: number;
}

/** Tracks which data point is currently hovered, -1 = none. */
function useHoverIndex(
  svgRef: { current: SVGSVGElement | null },
  pointCount: number,
) {
  const [hoverIdx, setHoverIdx] = useState(-1);
  const onMove = useCallback(
    (e: MouseEvent) => {
      const svg = svgRef.current;
      if (!svg || pointCount < 1) return;
      const r = svg.getBoundingClientRect();
      const paddingLeft = 36;
      const paddingRight = 8;
      const chartW = r.width - paddingLeft - paddingRight;
      if (chartW <= 0) return;
      const x = e.clientX - r.left - paddingLeft;
      const stepX = pointCount <= 1 ? chartW : chartW / (pointCount - 1);
      const idx = Math.round(x / stepX);
      setHoverIdx(idx >= 0 && idx < pointCount ? idx : -1);
    },
    [svgRef, pointCount],
  );
  const onLeave = useCallback(() => setHoverIdx(-1), []);
  useEffect(() => {
    const el = svgRef.current;
    if (!el) return;
    el.addEventListener('mousemove', onMove);
    el.addEventListener('mouseleave', onLeave);
    return () => {
      el.removeEventListener('mousemove', onMove);
      el.removeEventListener('mouseleave', onLeave);
    };
  }, [svgRef, onMove, onLeave]);
  return hoverIdx;
}

const PAD_LEFT = 36;
const PAD_RIGHT = 8;
const PAD_TOP = 14;
const PAD_BOTTOM = 24;

export default function CacheHitTrendChart({
  points,
  averageRatio,
  height = 176,
}: CacheHitTrendChartProps) {
  const svgRef = useRef<SVGSVGElement | null>(null);
  const hoverIdx = useHoverIndex(svgRef, points.length);
  const chartW = Math.max(0, 400 - PAD_LEFT - PAD_RIGHT);
  const chartH = height - PAD_TOP - PAD_BOTTOM;

  if (points.length < 2) {
    return (
      <div class="text-xs" style={{ color: 'var(--m3-on-surface-variant)', padding: '8px 0' }}>
        {points.length === 0
          ? '暂无逐轮次缓存命中数据。发送消息后将在此展示缓存命中率走势。'
          : '需至少 2 轮对话方可绘制走势图。'}
      </div>
    );
  }

  const ratios = points.map((p) => p.hitRatio);
  const stepX = points.length <= 1 ? chartW : chartW / (points.length - 1);

  const polylinePoints = ratios
    .map((r, i) => {
      const px = PAD_LEFT + stepX * i;
      const py = PAD_TOP + chartH - chartH * Math.min(1, Math.max(0, r));
      return `${px},${py}`;
    })
    .join(' ');

  const fillPoints = `${PAD_LEFT},${PAD_TOP + chartH} ${polylinePoints} ${PAD_LEFT + stepX * (ratios.length - 1)},${PAD_TOP + chartH}`;

  const avgY = PAD_TOP + chartH - chartH * Math.min(1, Math.max(0, averageRatio));

  const lastPoint = points[points.length - 1];
  const totalW = chartW + PAD_LEFT + PAD_RIGHT;

  return (
    <div class="oh-cache-trend-chart" style={{ marginTop: '8px', width: '100%' }}>
      {/* mode chips — mirror the Flutter app's display mode toggles */}
      <div class="mb-1.5 flex items-center gap-1.5">
        <span class="text-xs font-semibold" style={{ color: 'var(--m3-on-surface-variant)' }}>
          {hoverIdx >= 0
            ? `第 ${points[hoverIdx].turnIndex} 轮 · ${(points[hoverIdx].hitRatio * 100).toFixed(0)}%`
            : `末轮 ${(lastPoint.hitRatio * 100).toFixed(0)}% · 均 ${(averageRatio * 100).toFixed(0)}%`}
        </span>
      </div>
      <svg
        ref={svgRef}
        viewBox={`0 0 ${totalW} ${height}`}
        width="100%"
        height={height}
        style={{ display: 'block', cursor: 'crosshair', overflow: 'visible' }}
      >
        {/* grid lines */}
        {[0, 0.25, 0.5, 0.75, 1].map((frac) => {
          const y = PAD_TOP + chartH - chartH * frac;
          return (
            <g key={`grid-${frac}`}>
              <line
                x1={PAD_LEFT}
                x2={PAD_LEFT + chartW}
                y1={y}
                y2={y}
                stroke="var(--m3-outline-variant)"
                stroke-opacity={frac === 0 || frac === 1 ? 0.35 : 0.18}
                stroke-dasharray={frac === 0 ? 'none' : '3 4'}
                stroke-width={0.8}
              />
              <text
                x={PAD_LEFT - 4}
                y={y + 3}
                text-anchor="end"
                fill="var(--m3-on-surface-variant)"
                font-size="9"
                opacity={0.6}
              >
                {(frac * 100).toFixed(0)}%
              </text>
            </g>
          );
        })}

        {/* average dashed line */}
        <line
          x1={PAD_LEFT}
          x2={PAD_LEFT + chartW}
          y1={avgY}
          y2={avgY}
          stroke="var(--m3-primary)"
          stroke-opacity="0.42"
          stroke-width="1.2"
          stroke-dasharray="5 4"
        />

        {/* fill area under curve and line path */}
        <defs>
          <linearGradient id="cht-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="var(--m3-primary)" stop-opacity="0.18" />
            <stop offset="100%" stop-color="var(--m3-primary)" stop-opacity="0.02" />
          </linearGradient>
        </defs>
        <polygon points={fillPoints} fill="url(#cht-fill)" />
        <polyline
          points={polylinePoints}
          fill="none"
          stroke="var(--m3-primary)"
          stroke-opacity="0.72"
          stroke-width="2"
          stroke-linejoin="round"
        />

        {/* data dots */}
        {points.map((p, i) => {
          const cx = PAD_LEFT + stepX * i;
          const cy = PAD_TOP + chartH - chartH * Math.min(1, Math.max(0, p.hitRatio));
          const isHovered = i === hoverIdx;
          return (
            <circle
              key={`dot-${i}`}
              cx={cx}
              cy={cy}
              r={isHovered ? 5 : 3}
              fill={isHovered ? 'var(--m3-primary)' : 'var(--m3-primary)'}
              fill-opacity={isHovered ? 1 : 0.55}
              stroke={isHovered ? 'var(--m3-surface)' : 'none'}
              stroke-width={isHovered ? 2 : 0}
              style={{ transition: 'r 120ms ease, fill-opacity 120ms ease' }}
            />
          );
        })}

        {/* X-axis labels for first / last round */}
        <text
          x={PAD_LEFT}
          y={PAD_TOP + chartH + 14}
          text-anchor="start"
          fill="var(--m3-on-surface-variant)"
          font-size="9"
          opacity="0.55"
        >
          第 {points[0].turnIndex} 轮
        </text>
        <text
          x={PAD_LEFT + chartW}
          y={PAD_TOP + chartH + 14}
          text-anchor="end"
          fill="var(--m3-on-surface-variant)"
          font-size="9"
          opacity="0.55"
        >
          第 {lastPoint.turnIndex} 轮
        </text>
      </svg>
    </div>
  );
}
