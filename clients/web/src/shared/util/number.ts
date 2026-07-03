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

const STRICT_POSITIVE_INTEGER_RE = /^[1-9]\d*$/;
const STRICT_POSITIVE_NUMBER_RE = /^(?:[1-9]\d*(?:\.\d+)?|0?\.\d+)$/;

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

export function finiteNumberFromText(value: string): number | null {
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
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

export function strictPositiveIntegerFromText(value: string): number | null {
  const trimmed = value.trim();
  if (!STRICT_POSITIVE_INTEGER_RE.test(trimmed)) return null;
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

export function strictPositiveNumberFromText(value: string): number | null {
  const trimmed = value.trim();
  if (!STRICT_POSITIVE_NUMBER_RE.test(trimmed)) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

export function strictPositiveIntegerFromUnknown(value: unknown): number | null {
  if (typeof value === 'number') {
    return Number.isSafeInteger(value) && value > 0 ? value : null;
  }
  if (typeof value !== 'string') return null;
  return strictPositiveIntegerFromText(value);
}

export function strictPositiveNumberFromUnknown(value: unknown): number | null {
  if (typeof value === 'number') {
    return Number.isFinite(value) && value > 0 ? value : null;
  }
  if (typeof value !== 'string') return null;
  return strictPositiveNumberFromText(value);
}
