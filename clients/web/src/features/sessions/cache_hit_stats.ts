import { clampNumber } from '../../shared/util/number';

export interface CacheHitTrendPoint {
  turnIndex: number;
  hitRatio: number;
  promptTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  starterMessageId?: string | null;
  starterMessageKind?: string | null;
  starterOrigin?: string | null;
  anchorMessageId?: string | null;
  idleGapSeconds?: number | null;
}

export type CacheHitDisplayMode = 'excludeExpiredMisses' | 'includeExpiredMisses';

interface CacheHitDisplayData {
  points: CacheHitTrendPoint[];
  averageRatio: number;
  /** 平均前缀复用率（Σ缓存读取 / Σ上一轮可复用前缀）；无基准轮时为 null。 */
  averagePrefixReuseRatio: number | null;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  uncachedPromptTokens: number;
  excludedPointCount: number;
  excludedFirstRequestCount: number;
  excludedExpiredMissCount: number;
  averagePointCount: number;
}

/** 单轮前缀复用信息：命中率会被本轮新增（必然未缓存）输入稀释，复用率不会。 */
export interface CacheHitPrefixStats {
  /** 本轮相对上一轮新增的输入 token（结构上不可能命中缓存）。 */
  freshInputTokens: number;
  /** 上一轮总输入规模，即本轮理论可复用前缀的上限；首轮为 null。 */
  previousDenominatorTokens: number | null;
  /** 缓存读取 / 上一轮可复用前缀；首轮或缺基准时为 null。 */
  prefixReuseRatio: number | null;
}

/** 复用率达到该阈值即视为已达理论上限（供应商块对齐允许少量抖动）。 */
export const CACHE_HIT_HEALTHY_PREFIX_REUSE_RATIO = 0.95;

export const DEFAULT_CACHE_HIT_DISPLAY_MODE: CacheHitDisplayMode =
  'excludeExpiredMisses';

const CACHE_HIT_EXPIRY_IDLE_GAP_SECONDS = 30 * 60;
const CACHE_HIT_EXPIRY_RATIO_THRESHOLD = 0.03;

export function isFirstCacheHitRequest(point: CacheHitTrendPoint): boolean {
  return point.turnIndex <= 1;
}

function isExpiredCacheMiss(point: CacheHitTrendPoint): boolean {
  const gap = point.idleGapSeconds ?? 0;
  return (
    gap > CACHE_HIT_EXPIRY_IDLE_GAP_SECONDS &&
    point.hitRatio < CACHE_HIT_EXPIRY_RATIO_THRESHOLD
  );
}

function trendPointUncachedPromptTokens(
  point: CacheHitTrendPoint,
  claudeStyle: boolean,
): number {
  const prompt = Math.max(0, Math.round(point.promptTokens ?? 0));
  const read = Math.max(0, Math.round(point.cacheReadTokens ?? 0));
  const write = Math.max(0, Math.round(point.cacheWriteTokens ?? 0));
  if (claudeStyle) return prompt;
  return Math.max(0, prompt - read - write);
}

function trendPointDenominatorTokens(
  point: CacheHitTrendPoint,
  claudeStyle: boolean,
): number {
  const prompt = Math.max(0, Math.round(point.promptTokens ?? 0));
  const read = Math.max(0, Math.round(point.cacheReadTokens ?? 0));
  const write = Math.max(0, Math.round(point.cacheWriteTokens ?? 0));
  if (claudeStyle) return prompt + read + write;
  return Math.max(prompt, read + write);
}

/**
 * 按原始轮次序列（不受展示口径过滤影响）计算每轮的前缀复用信息，
 * 键为 turnIndex。上一轮总输入即"本轮理论可复用前缀"的上限基准。
 */
export function cacheHitPrefixStatsByTurn(
  points: CacheHitTrendPoint[],
  claudeStyle: boolean,
): Map<number, CacheHitPrefixStats> {
  const stats = new Map<number, CacheHitPrefixStats>();
  let previousDenominator: number | null = null;
  for (const point of points) {
    const denominator = trendPointDenominatorTokens(point, claudeStyle);
    if (denominator <= 0) continue;
    const read = Math.max(0, Math.round(point.cacheReadTokens ?? 0));
    stats.set(point.turnIndex, {
      freshInputTokens:
        previousDenominator == null
          ? 0
          : Math.max(0, denominator - previousDenominator),
      previousDenominatorTokens: previousDenominator,
      prefixReuseRatio:
        previousDenominator == null || previousDenominator <= 0
          ? null
          : clampNumber(read / previousDenominator, 0, 1),
    });
    previousDenominator = denominator;
  }
  return stats;
}

function cacheHitAverageRatio(
  points: CacheHitTrendPoint[],
  claudeStyle: boolean,
  fallback = 0,
): number {
  let readTotal = 0;
  let writeTotal = 0;
  let uncachedTotal = 0;
  for (const point of points) {
    readTotal += Math.max(0, Math.round(point.cacheReadTokens ?? 0));
    writeTotal += Math.max(0, Math.round(point.cacheWriteTokens ?? 0));
    uncachedTotal += trendPointUncachedPromptTokens(point, claudeStyle);
  }
  const denominator = readTotal + writeTotal + uncachedTotal;
  if (denominator <= 0) {
    return points.length === 0 ? clampNumber(fallback, 0, 1) : 0;
  }
  return clampNumber(readTotal / denominator, 0, 1);
}

export function cacheHitDisplayData({
  points,
  displayMode,
  claudeStyle,
  fallbackAverageRatio = 0,
}: {
  points: CacheHitTrendPoint[];
  displayMode: CacheHitDisplayMode;
  claudeStyle: boolean;
  fallbackAverageRatio?: number;
}): CacheHitDisplayData {
  const visiblePoints =
    displayMode === 'includeExpiredMisses'
      ? points
      : points.filter(
          (point) => !isFirstCacheHitRequest(point) && !isExpiredCacheMiss(point),
        );
  const averagePoints = points.filter(
    (point) =>
      !isFirstCacheHitRequest(point) &&
      (displayMode === 'includeExpiredMisses' || !isExpiredCacheMiss(point)),
  );
  let cacheReadTokens = 0;
  let cacheWriteTokens = 0;
  let uncachedPromptTokens = 0;
  let reusableCacheReadTokens = 0;
  let reusablePrefixTokens = 0;
  const prefixStats = cacheHitPrefixStatsByTurn(points, claudeStyle);
  for (const point of averagePoints) {
    cacheReadTokens += Math.max(0, Math.round(point.cacheReadTokens ?? 0));
    cacheWriteTokens += Math.max(0, Math.round(point.cacheWriteTokens ?? 0));
    uncachedPromptTokens += trendPointUncachedPromptTokens(point, claudeStyle);
    const prefix = prefixStats.get(point.turnIndex);
    if (
      prefix &&
      prefix.previousDenominatorTokens != null &&
      prefix.previousDenominatorTokens > 0
    ) {
      reusableCacheReadTokens += Math.max(
        0,
        Math.round(point.cacheReadTokens ?? 0),
      );
      reusablePrefixTokens += prefix.previousDenominatorTokens;
    }
  }
  const averageRatio = cacheHitAverageRatio(
    averagePoints,
    claudeStyle,
    fallbackAverageRatio,
  );
  const averagePrefixReuseRatio =
    reusablePrefixTokens > 0
      ? clampNumber(reusableCacheReadTokens / reusablePrefixTokens, 0, 1)
      : null;
  const visibleTurns = new Set(visiblePoints.map((point) => point.turnIndex));
  return {
    points: visiblePoints,
    averageRatio,
    averagePrefixReuseRatio,
    cacheReadTokens,
    cacheWriteTokens,
    uncachedPromptTokens,
    excludedPointCount: points.length - visiblePoints.length,
    excludedFirstRequestCount: points.filter(
      (point) =>
        isFirstCacheHitRequest(point) && !visibleTurns.has(point.turnIndex),
    ).length,
    excludedExpiredMissCount: points.filter(
      (point) =>
        !isFirstCacheHitRequest(point) &&
        isExpiredCacheMiss(point) &&
        !visibleTurns.has(point.turnIndex),
    ).length,
    averagePointCount: averagePoints.length,
  };
}
