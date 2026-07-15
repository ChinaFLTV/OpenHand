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
  idleGapSeconds?: number | null;
}

export type CacheHitDisplayMode = 'excludeExpiredMisses' | 'includeExpiredMisses';

interface CacheHitDisplayData {
  points: CacheHitTrendPoint[];
  averageRatio: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  uncachedPromptTokens: number;
  excludedPointCount: number;
  excludedFirstRequestCount: number;
  excludedExpiredMissCount: number;
  averagePointCount: number;
}

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
  for (const point of averagePoints) {
    cacheReadTokens += Math.max(0, Math.round(point.cacheReadTokens ?? 0));
    cacheWriteTokens += Math.max(0, Math.round(point.cacheWriteTokens ?? 0));
    uncachedPromptTokens += trendPointUncachedPromptTokens(point, claudeStyle);
  }
  const averageRatio = cacheHitAverageRatio(
    averagePoints,
    claudeStyle,
    fallbackAverageRatio,
  );
  const visibleTurns = new Set(visiblePoints.map((point) => point.turnIndex));
  return {
    points: visiblePoints,
    averageRatio,
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
