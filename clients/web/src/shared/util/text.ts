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

function characterPrefix(value: string, maxCharacters: number): string {
  let count = 0;
  let end = 0;
  while (end < value.length && count < maxCharacters) {
    end = nextCharacterEnd(value, end);
    count += 1;
  }
  return end >= value.length ? value : value.slice(0, end);
}

function characterCount(value: string): number {
  let count = 0;
  let index = 0;
  while (index < value.length) {
    index = nextCharacterEnd(value, index);
    count += 1;
  }
  return count;
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
  if (!textExceedsLength(value, safeMaxCharacters)) return value;
  if (safeMaxCharacters === 0) return '';
  const safeEllipsis = characterPrefix(ellipsis, safeMaxCharacters);
  const contentLimit = safeMaxCharacters - characterCount(safeEllipsis);
  const content = characterPrefix(value, contentLimit);
  return `${trimEnd ? content.trimEnd() : content}${safeEllipsis}`;
}
