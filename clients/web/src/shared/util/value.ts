import { normalizeInteger } from './number';

export interface StringFromUnknownOptions {
  coerce?: boolean;
}

const BOOLEAN_TRUE_TEXT = new Set(['true', '1', 'yes', 'y', 'on', 'enabled']);
const BOOLEAN_FALSE_TEXT = new Set(['false', '0', 'no', 'n', 'off', 'disabled']);

export function stringFromUnknown(
  value: unknown,
  { coerce = true }: StringFromUnknownOptions = {},
): string {
  if (value == null) return '';
  if (typeof value === 'string') return value.trim();
  return coerce ? String(value).trim() : '';
}

export function strictStringFromUnknown(value: unknown): string {
  return stringFromUnknown(value, { coerce: false });
}

export function nonBlankStringFromUnknown(
  value: unknown,
  options?: StringFromUnknownOptions,
): string | null {
  const text = stringFromUnknown(value, options);
  return text.length > 0 ? text : null;
}

export function booleanOrNullFromUnknown(value: unknown): boolean | null {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number' && Number.isFinite(value)) {
    if (value === 1) return true;
    if (value === 0) return false;
    return null;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (BOOLEAN_TRUE_TEXT.has(normalized)) return true;
    if (BOOLEAN_FALSE_TEXT.has(normalized)) return false;
  }
  return null;
}

export function booleanFromUnknown(value: unknown, fallback = false): boolean {
  return booleanOrNullFromUnknown(value) ?? fallback;
}

export function finiteNumberOrNullFromUnknown(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    const parsed = Number(trimmed);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function finiteNumberFromUnknown(value: unknown, fallback = 0): number {
  return finiteNumberOrNullFromUnknown(value) ?? (Number.isFinite(fallback) ? fallback : 0);
}

export function roundedNonNegativeIntegerOrNullFromUnknown(value: unknown): number | null {
  const parsed = finiteNumberOrNullFromUnknown(value);
  if (parsed == null || parsed < 0) return null;
  return Math.round(parsed);
}

export function roundedNonNegativeIntegerFromUnknown(value: unknown, fallback = 0): number {
  const safeFallback = Number.isFinite(fallback) && fallback >= 0 ? Math.round(fallback) : 0;
  return roundedNonNegativeIntegerOrNullFromUnknown(value) ?? safeFallback;
}

export function nonNegativeIntegerFromUnknown(value: unknown, fallback = 0): number {
  const parsed = finiteNumberOrNullFromUnknown(value);
  const safeFallback = Number.isFinite(fallback) ? fallback : 0;
  return normalizeInteger(parsed, {
    fallback: safeFallback,
    min: 0,
  });
}

export function integerFromUnknown(value: unknown, fallback = 0): number {
  const parsed = finiteNumberOrNullFromUnknown(value);
  const safeFallback = Number.isFinite(fallback) ? fallback : 0;
  return Math.trunc(parsed ?? safeFallback);
}

export function recordFromUnknown(value: unknown): Record<string, unknown> {
  if (value != null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

export function recordOrNullFromUnknown(value: unknown): Record<string, unknown> | null {
  if (value != null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

export function arrayFromUnknown(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function stringListFromUnknown(value: unknown): string[] {
  return arrayFromUnknown(value)
    .map((item) => stringFromUnknown(item))
    .filter(Boolean);
}
