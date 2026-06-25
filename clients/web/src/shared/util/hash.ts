const FNV1A_32_OFFSET = 0x811c9dc5;
const FNV1A_32_PRIME = 0x01000193;
const FNV1A_BOUNDED_SEPARATOR = 0x9e3779b9;
const DEFAULT_BOUNDED_HASH_EDGE_CHARS = 4096;
const ROLLING_HASH_31_MULTIPLIER = 31;

function fnv1aStep(hash: number, value: number): number {
  return Math.imul(hash ^ value, FNV1A_32_PRIME);
}

function hashToBase36(hash: number): string {
  return (hash >>> 0).toString(36);
}

export function fnv1aHashBase36(value: string): string {
  let hash = FNV1A_32_OFFSET;
  for (let index = 0; index < value.length; index += 1) {
    hash = fnv1aStep(hash, value.charCodeAt(index));
  }
  return hashToBase36(hash);
}

export function boundedFnv1aHashBase36(
  value: string,
  edgeChars = DEFAULT_BOUNDED_HASH_EDGE_CHARS,
): string {
  let hash = FNV1A_32_OFFSET;
  const boundedEdgeChars = Math.max(1, Math.floor(edgeChars));
  const headEnd = Math.min(value.length, boundedEdgeChars);
  const tailStart =
    value.length > boundedEdgeChars * 2
      ? value.length - boundedEdgeChars
      : headEnd;

  for (let index = 0; index < headEnd; index += 1) {
    hash = fnv1aStep(hash, value.charCodeAt(index));
  }
  if (tailStart < value.length) {
    hash = fnv1aStep(hash, FNV1A_BOUNDED_SEPARATOR);
    for (let index = tailStart; index < value.length; index += 1) {
      hash = fnv1aStep(hash, value.charCodeAt(index));
    }
  }
  if (value.length > headEnd) {
    hash = fnv1aStep(hash, value.length);
  }
  return hashToBase36(hash);
}

export function rollingHash31Base36(value: string): string {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash =
      (Math.imul(hash, ROLLING_HASH_31_MULTIPLIER) +
        value.charCodeAt(index)) |
      0;
  }
  return hashToBase36(hash);
}
