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

export function textExceedsLength(value: string, maxCharacters: number): boolean {
  return Array.from(value).length > normalizeTextLimit(maxCharacters);
}

export function truncateEndText(
  value: string,
  maxCharacters: number,
  { ellipsis = '…', trimEnd = false }: TruncateEndTextOptions = {},
): string {
  const safeMaxCharacters = normalizeTextLimit(maxCharacters);
  const characters = Array.from(value);
  if (characters.length <= safeMaxCharacters) return value;
  const truncated = characters.slice(0, safeMaxCharacters).join('');
  return `${trimEnd ? truncated.trimEnd() : truncated}${ellipsis}`;
}
