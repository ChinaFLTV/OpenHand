export interface NormalizeDurationMsOptions {
  fallback: number;
  min?: number;
  max?: number;
  zeroDisables?: boolean;
}

export interface NormalizeIntegerOptions {
  fallback: number;
  min?: number;
  max?: number;
  zeroDisables?: boolean;
}

export const MAX_BROWSER_TIMEOUT_MS = 2_147_483_647;

export function finiteNumberOr(
  value: number | null | undefined,
  fallback: number,
): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return Number.isFinite(fallback) ? fallback : 0;
}

export function clampNumber(value: number, min: number, max: number): number {
  const safeMin = finiteNumberOr(min, 0);
  const safeMax = finiteNumberOr(max, safeMin);
  const lower = Math.min(safeMin, safeMax);
  const upper = Math.max(safeMin, safeMax);
  return Math.min(Math.max(finiteNumberOr(value, lower), lower), upper);
}

export function normalizeInteger(
  value: number | null | undefined,
  {
    fallback,
    min = Number.MIN_SAFE_INTEGER,
    max = Number.MAX_SAFE_INTEGER,
    zeroDisables = false,
  }: NormalizeIntegerOptions,
): number {
  const rounded = Math.round(finiteNumberOr(value, fallback));
  if (zeroDisables && rounded <= 0) return 0;
  return Math.round(clampNumber(rounded, min, max));
}

export function normalizeDurationMs(
  value: number | null | undefined,
  {
    fallback,
    min = 0,
    max = Number.MAX_SAFE_INTEGER,
    zeroDisables = false,
  }: NormalizeDurationMsOptions,
): number {
  return normalizeInteger(value, { fallback, min, max, zeroDisables });
}
