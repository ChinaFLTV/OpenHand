import { normalizeInteger } from './number';

interface TruncateEndTextOptions {
  ellipsis?: string;
  trimEnd?: boolean;
}

function normalizeTextLimit(value: number): number {
  return normalizeInteger(value, {
    fallback: 0,
    min: 0,
  });
}

function nextCharacterEnd(value: string, index: number): number {
  const first = value.charCodeAt(index);
  return first >= 0xD800 &&
    first <= 0xDBFF &&
    index + 1 < value.length &&
    value.charCodeAt(index + 1) >= 0xDC00 &&
    value.charCodeAt(index + 1) <= 0xDFFF
    ? index + 2
    : index + 1;
}

export function textExceedsLength(value: string, maxCharacters: number): boolean {
  const limit = normalizeTextLimit(maxCharacters);
  let count = 0;
  let index = 0;
  while (index < value.length) {
    index = nextCharacterEnd(value, index);
    count += 1;
    if (count > limit) return true;
  }
  return false;
}

export function truncateEndText(
  value: string,
  maxCharacters: number,
  { ellipsis = '…', trimEnd = false }: TruncateEndTextOptions = {},
): string {
  const safeMaxCharacters = normalizeTextLimit(maxCharacters);
  let count = 0;
  let end = 0;
  while (end < value.length) {
    if (count >= safeMaxCharacters) {
      const truncated = value.slice(0, end);
      return `${trimEnd ? truncated.trimEnd() : truncated}${ellipsis}`;
    }
    count += 1;
    end = nextCharacterEnd(value, end);
  }
  return value;
}
