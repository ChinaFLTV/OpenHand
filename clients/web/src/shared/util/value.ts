import { normalizeInteger } from './number';

export interface StringFromUnknownOptions {
  coerce?: boolean;
}

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

export function booleanOrNullFromUnknown(value: unknown): boolean | null {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number' && Number.isFinite(value)) return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
      return true;
    }
    if (normalized === 'false' || normalized === '0' || normalized === 'no') {
      return false;
    }
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
