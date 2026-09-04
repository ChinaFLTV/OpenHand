/** Web 会话记录的纯虚拟列表计算，不依赖 Preact 或 DOM。 */

export const MESSAGE_LIST_DEFAULT_PAGE_SIZE = 20;
export const MESSAGE_LIST_DEFAULT_INITIAL_PAGE_SIZE = 10;
export const MESSAGE_LIST_MAX_LOADED_MESSAGES = 200;
export const MESSAGE_LIST_VIRTUALIZATION_THRESHOLD = 6;
export const MESSAGE_LIST_VIRTUALIZATION_OVERSCAN_PX = 480;
export const MESSAGE_LIST_MAX_VISIBLE_ROWS = 8;
export const MESSAGE_LIST_ESTIMATED_ROW_HEIGHT_PX = 188;
const MESSAGE_LIST_MIN_ROW_HEIGHT_PX = 44;
/// 仅用于拦截异常值，不截断真实行高：工具卡片带长输出时几千像素是常态，
/// 一旦截断，锚点补偿每次都会算出非零 delta 并写 scrollTop，列表永远抖动。
const MESSAGE_LIST_MAX_ROW_HEIGHT_PX = 40_000;
const MESSAGE_LIST_GAP_PX = 12;
/** 首次打开或滚动的范围约为视口行数加预渲染行数，并始终从尾部开始。 */
const MESSAGE_LIST_INITIAL_VISIBLE_ROWS = 4;
const MESSAGE_LIST_INITIAL_OVERSCAN_ROWS = 1;

export interface VirtualMessageRange {
  start: number;
  end: number;
}

/**
 * 消息窗口前插、裁剪或换窗后，按仍存活的消息标识重定位当前渲染范围。
 * 返回 null 表示新旧窗口没有交集，调用方应回退到默认尾部范围。
 */
export function rebaseVirtualMessageRange<T>(
  previousIds: readonly T[],
  nextIds: readonly T[],
  current: VirtualMessageRange,
): VirtualMessageRange | null {
  if (previousIds.length === 0 || nextIds.length === 0) return null;
  const previousStart = Math.max(
    0,
    Math.min(previousIds.length, Math.floor(current.start)),
  );
  const previousEnd = Math.max(
    previousStart,
    Math.min(previousIds.length, Math.floor(current.end)),
  );
  const span = previousEnd - previousStart;
  if (span <= 0) return null;

  const nextIndexById = new Map<T, number>();
  for (let index = 0; index < nextIds.length; index += 1) {
    nextIndexById.set(nextIds[index]!, index);
  }
  for (let index = previousStart; index < previousEnd; index += 1) {
    const nextAnchorIndex = nextIndexById.get(previousIds[index]!);
    if (nextAnchorIndex == null) continue;
    const maxStart = Math.max(0, nextIds.length - Math.min(span, nextIds.length));
    const start = Math.max(
      0,
      Math.min(maxStart, nextAnchorIndex - (index - previousStart)),
    );
    return { start, end: Math.min(nextIds.length, start + span) };
  }
  return null;
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

/// 前缀和长度与消息数可能在同一帧内短暂不一致（成员变化与高度提交分属两条
/// 更新路径）。这里统一夹取索引，避免读到 undefined 后把 NaN 写进 style。
function boundedPrefixIndex(prefix: number[], index: number): number {
  if (!Number.isFinite(index)) return 0;
  return Math.max(0, Math.min(Math.floor(index), prefix.length - 1));
}

export function virtualMessageTop(
  prefix: number[],
  index: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  const safeIndex = boundedPrefixIndex(prefix, index);
  return prefix[safeIndex]! + safeIndex * gapPx;
}

function virtualMessageBottom(
  prefix: number[],
  heights: number[],
  index: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  return virtualMessageTop(prefix, index, gapPx) + heights[index]!;
}

function firstIndexMatching(length: number, matches: (index: number) => boolean): number {
  let low = 0;
  let high = length;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (matches(middle)) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

export function virtualMessageTotalHeight(
  prefix: number[],
  count: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  const safeCount = boundedPrefixIndex(prefix, count);
  return prefix[safeCount]! + Math.max(0, safeCount - 1) * gapPx;
}

function firstVirtualMessageIntersecting(
  prefix: number[],
  heights: number[],
  targetY: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  return firstIndexMatching(
    heights.length,
    (index) => virtualMessageBottom(prefix, heights, index, gapPx) >= targetY,
  );
}

function firstVirtualMessageAfter(
  prefix: number[],
  heights: number[],
  targetY: number,
  gapPx = MESSAGE_LIST_GAP_PX,
): number {
  return firstIndexMatching(
    heights.length,
    (index) => virtualMessageTop(prefix, index, gapPx) > targetY,
  );
}

export function clampVirtualMessageRange(
  range: VirtualMessageRange,
  messageCount: number,
  maxVisibleRows = MESSAGE_LIST_MAX_VISIBLE_ROWS,
): VirtualMessageRange {
  const count = Math.max(0, Math.floor(messageCount));
  if (count <= 0) {
    return { start: 0, end: 0 };
  }
  const start = Math.max(0, Math.min(count, Math.floor(range.start)));
  const end = Math.max(start, Math.min(count, Math.floor(range.end)));
  const maxRows = Math.max(1, Math.floor(maxVisibleRows));
  if (end - start <= maxRows) {
    return { start, end };
  }
  if (end >= count) {
    return { start: Math.max(0, count - maxRows), end: count };
  }
  return { start, end: Math.min(count, start + maxRows) };
}

/** 首帧优先展示最新尾部，使会话贴近底部且无需挂载全部历史。 */
export function initialVirtualMessageRange(
  messageCount: number,
  {
    estimatedVisibleRows = MESSAGE_LIST_INITIAL_VISIBLE_ROWS,
    overscanRows = MESSAGE_LIST_INITIAL_OVERSCAN_ROWS,
    virtualizationThreshold = MESSAGE_LIST_VIRTUALIZATION_THRESHOLD,
    maxVisibleRows = MESSAGE_LIST_MAX_VISIBLE_ROWS,
  }: {
    estimatedVisibleRows?: number;
    overscanRows?: number;
    virtualizationThreshold?: number;
    maxVisibleRows?: number;
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
    Math.min(
      Math.max(1, Math.floor(maxVisibleRows)),
      Math.floor(estimatedVisibleRows) + Math.max(0, Math.floor(overscanRows)) * 2,
    ),
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
  maxVisibleRows = MESSAGE_LIST_MAX_VISIBLE_ROWS,
): VirtualMessageRange {
  const count = Math.max(0, Math.floor(messageCount));
  if (count === 0) return { start: 0, end: 0 };
  const size = Math.max(
    1,
    Math.min(count, Math.min(Math.floor(windowSize), Math.max(1, Math.floor(maxVisibleRows)))),
  );
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
  maxVisibleRows?: number;
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
  return clampVirtualMessageRange(
    { start: nextStart, end: nextEnd },
    count,
    params.maxVisibleRows ?? MESSAGE_LIST_MAX_VISIBLE_ROWS,
  );
}

export function shouldVirtualizeMessageList(
  messageCount: number,
  threshold = MESSAGE_LIST_VIRTUALIZATION_THRESHOLD,
): boolean {
  return messageCount > threshold;
}
