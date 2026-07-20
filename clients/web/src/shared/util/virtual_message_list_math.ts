/**
 * Pure virtual-list math for the Web session transcript.
 * Kept free of Preact/DOM so large-N windowing can be unit-tested.
 */

export const MESSAGE_LIST_DEFAULT_PAGE_SIZE = 20;
export const MESSAGE_LIST_DEFAULT_INITIAL_PAGE_SIZE = 10;
export const MESSAGE_LIST_MAX_LOADED_MESSAGES = 200;
export const MESSAGE_LIST_VIRTUALIZATION_THRESHOLD = 24;
export const MESSAGE_LIST_VIRTUALIZATION_OVERSCAN_PX = 560;
export const MESSAGE_LIST_ESTIMATED_ROW_HEIGHT_PX = 188;
const MESSAGE_LIST_MIN_ROW_HEIGHT_PX = 44;
const MESSAGE_LIST_MAX_ROW_HEIGHT_PX = 1400;
export const MESSAGE_LIST_GAP_PX = 12;
/** Open/scroll first range: ~viewport rows + overscan, always from the tail. */
const MESSAGE_LIST_INITIAL_VISIBLE_ROWS = 8;
const MESSAGE_LIST_INITIAL_OVERSCAN_ROWS = 4;

export interface VirtualMessageRange {
  start: number;
  end: number;
}

export function boundLiveMessageWindow<T>(
  messages: T[],
  windowOffset: number,
  maxMessages = MESSAGE_LIST_MAX_LOADED_MESSAGES,
): { items: T[]; offset: number } {
  const limit = Math.max(1, Math.floor(maxMessages));
  const safeOffset = Math.max(0, Math.floor(windowOffset));
  if (messages.length <= limit) {
    return { items: messages, offset: safeOffset };
  }
  const dropped = messages.length - limit;
  return {
    items: messages.slice(dropped),
    offset: safeOffset + dropped,
  };
}

export function remainingNewerMessageCount(
  total: number,
  windowOffset: number,
  loadedCount: number,
): number {
  const safeTotal = Math.max(0, Math.floor(total));
  const safeOffset = Math.max(0, Math.floor(windowOffset));
  const safeLoadedCount = Math.max(0, Math.floor(loadedCount));
  return Math.max(0, safeTotal - safeOffset - safeLoadedCount);
}

export function clampMessageRowHeight(
  value: number,
  {
    estimated = MESSAGE_LIST_ESTIMATED_ROW_HEIGHT_PX,
    min = MESSAGE_LIST_MIN_ROW_HEIGHT_PX,
    max = MESSAGE_LIST_MAX_ROW_HEIGHT_PX,
  }: { estimated?: number; min?: number; max?: number } = {},
): number {
  if (!Number.isFinite(value) || value <= 0) {
    return estimated;
  }
  const lo = Math.min(min, max);
  const hi = Math.max(min, max);
  return Math.round(Math.min(hi, Math.max(lo, value)));
}

export function buildHeightPrefix(heights: number[]): number[] {
  const prefix = new Array<number>(heights.length + 1);
  prefix[0] = 0;
  for (let index = 0; index < heights.length; index += 1) {
    prefix[index + 1] = prefix[index]! + heights[index]!;
  }
  return prefix;
}

export function virtualMessageTop(
  prefix: number[],
  index: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  return prefix[index]! + index * gapPx;
}

function virtualMessageBottom(
  prefix: number[],
  heights: number[],
  index: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  return virtualMessageTop(prefix, index, gapPx) + heights[index]!;
}

export function virtualMessageTotalHeight(
  prefix: number[],
  count: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  return prefix[count]! + Math.max(0, count - 1) * gapPx;
}

function firstVirtualMessageIntersecting(
  prefix: number[],
  heights: number[],
  targetY: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  let lo = 0;
  let hi = heights.length;
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (virtualMessageBottom(prefix, heights, mid, gapPx) < targetY) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return Math.min(lo, heights.length);
}

function firstVirtualMessageAfter(
  prefix: number[],
  heights: number[],
  targetY: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  let lo = 0;
  let hi = heights.length;
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (virtualMessageTop(prefix, mid, gapPx) <= targetY) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return Math.min(lo, heights.length);
}

/**
 * First-paint range for chat lists: prefer the latest tail so open stays
 * near stick-to-bottom without mounting the entire history.
 */
export function initialVirtualMessageRange(
  messageCount: number,
  {
    estimatedVisibleRows = MESSAGE_LIST_INITIAL_VISIBLE_ROWS,
    overscanRows = MESSAGE_LIST_INITIAL_OVERSCAN_ROWS,
    virtualizationThreshold = MESSAGE_LIST_VIRTUALIZATION_THRESHOLD,
  }: {
    estimatedVisibleRows?: number;
    overscanRows?: number;
    virtualizationThreshold?: number;
  } = {},
): VirtualMessageRange {
  const count = Math.max(0, Math.floor(messageCount));
  if (count <= 0) {
    return { start: 0, end: 0 };
  }
  if (count <= virtualizationThreshold) {
    return { start: 0, end: count };
  }
  const windowSize = Math.max(
    1,
    Math.floor(estimatedVisibleRows) + Math.max(0, Math.floor(overscanRows)) * 2,
  );
  if (count <= windowSize) {
    return { start: 0, end: count };
  }
  return { start: count - windowSize, end: count };
}

export function virtualMessageRangeAroundIndex(
  messageCount: number,
  targetIndex: number,
  windowSize: number,
): VirtualMessageRange {
  const count = Math.max(0, Math.floor(messageCount));
  if (count === 0) return { start: 0, end: 0 };
  const size = Math.max(1, Math.min(count, Math.floor(windowSize)));
  const index = Math.max(0, Math.min(count - 1, Math.floor(targetIndex)));
  const start = Math.max(
    0,
    Math.min(count - size, index - Math.floor(size / 2)),
  );
  return { start, end: start + size };
}

export function resolveVirtualMessageRange(params: {
  messageCount: number;
  prefix: number[];
  heights: number[];
  viewportTop: number;
  viewportBottom: number;
  overscanPx?: number;
  virtualized?: boolean;
}): VirtualMessageRange {
  const count = Math.max(0, Math.floor(params.messageCount));
  if (count <= 0) {
    return { start: 0, end: 0 };
  }
  if (params.virtualized === false) {
    return { start: 0, end: count };
  }
  const overscan = params.overscanPx ?? MESSAGE_LIST_VIRTUALIZATION_OVERSCAN_PX;
  const top = Math.max(0, params.viewportTop - overscan);
  const bottom = params.viewportBottom + overscan;
  const nextStart = Math.max(
    0,
    Math.min(
      count - 1,
      firstVirtualMessageIntersecting(params.prefix, params.heights, top),
    ),
  );
  const nextEnd = Math.max(
    nextStart + 1,
    Math.min(
      count,
      firstVirtualMessageAfter(params.prefix, params.heights, bottom) + 1,
    ),
  );
  return { start: nextStart, end: nextEnd };
}

export function shouldVirtualizeMessageList(
  messageCount: number,
  threshold = MESSAGE_LIST_VIRTUALIZATION_THRESHOLD,
): boolean {
  return messageCount > threshold;
}
