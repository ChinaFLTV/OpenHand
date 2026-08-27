import { clampNumber } from '../util/number';

type FloatingHorizontalAlign = 'left' | 'right';
export type FloatingVerticalPlacement = 'auto' | 'above' | 'below';

interface AnchoredMenuPosition {
  top: number;
  left: number;
  width: number;
  maxHeight: number;
  placedAbove: boolean;
}

interface AnchoredMenuPositionOptions {
  anchor: HTMLElement | null;
  preferredWidth?: number;
  minWidth?: number;
  measuredHeight?: number;
  fallbackHeight?: number;
  maxHeight?: number;
  align?: FloatingHorizontalAlign;
  verticalPlacement?: FloatingVerticalPlacement;
  viewportPadding?: number;
  gap?: number;
}

export const DEFAULT_FLOATING_VIEWPORT_PADDING = 8;
export const DEFAULT_FLOATING_ANCHOR_GAP = 4;
const DEFAULT_FLOATING_MIN_WIDTH = 160;
const DEFAULT_FLOATING_FALLBACK_HEIGHT = 160;

function positiveFiniteOr(value: number | undefined, fallback: number): number {
  return value != null && Number.isFinite(value) && value > 0
    ? value
    : fallback;
}

export function computeAnchoredMenuPosition({
  anchor,
  preferredWidth,
  minWidth = DEFAULT_FLOATING_MIN_WIDTH,
  measuredHeight = 0,
  fallbackHeight = DEFAULT_FLOATING_FALLBACK_HEIGHT,
  maxHeight,
  align = 'right',
  verticalPlacement = 'auto',
  viewportPadding = DEFAULT_FLOATING_VIEWPORT_PADDING,
  gap = DEFAULT_FLOATING_ANCHOR_GAP,
}: AnchoredMenuPositionOptions): AnchoredMenuPosition {
  if (typeof window === 'undefined' || !anchor) {
    const safeMinWidth = positiveFiniteOr(minWidth, 1);
    const safeWidth = Math.max(
      safeMinWidth,
      positiveFiniteOr(preferredWidth, safeMinWidth),
    );
    const safeHeight = positiveFiniteOr(
      maxHeight,
      positiveFiniteOr(fallbackHeight, 1),
    );
    const safeViewportPadding = Number.isFinite(viewportPadding)
      ? Math.max(0, viewportPadding)
      : DEFAULT_FLOATING_VIEWPORT_PADDING;
    return {
      top: safeViewportPadding,
      left: safeViewportPadding,
      width: safeWidth,
      maxHeight: safeHeight,
      placedAbove: false,
    };
  }

  const rect = anchor.getBoundingClientRect();
  const safeViewportPadding = clampNumber(
    viewportPadding,
    0,
    Math.max(0, Math.min(window.innerWidth, window.innerHeight) / 2),
  );
  const safeGap = Math.max(0, positiveFiniteOr(gap, 0));
  const usableWidth = Math.max(1, window.innerWidth - safeViewportPadding * 2);
  const safeMinWidth = clampNumber(minWidth, 1, usableWidth);
  const width = clampNumber(
    positiveFiniteOr(preferredWidth, rect.width),
    safeMinWidth,
    usableWidth,
  );
  const minLeft = safeViewportPadding;
  const maxLeft = Math.max(
    minLeft,
    window.innerWidth - width - safeViewportPadding,
  );
  const rawLeft = align === 'right' ? rect.right - width : rect.left;
  const left = clampNumber(rawLeft, minLeft, maxLeft);

  const usableHeight = Math.max(1, window.innerHeight - safeViewportPadding * 2);
  const heightLimit = clampNumber(
    positiveFiniteOr(maxHeight, usableHeight),
    1,
    usableHeight,
  );
  const desiredHeight = clampNumber(
    positiveFiniteOr(measuredHeight, positiveFiniteOr(fallbackHeight, 1)),
    1,
    heightLimit,
  );
  const belowTop = rect.bottom + safeGap;
  const availableBelow = Math.max(
    0,
    window.innerHeight - safeViewportPadding - belowTop,
  );
  const availableAbove = Math.max(
    0,
    rect.top - safeGap - safeViewportPadding,
  );
  const canFitBelow = availableBelow >= desiredHeight;
  const canFitAbove = availableAbove >= desiredHeight;
  const placedAbove = verticalPlacement === 'above'
    ? canFitAbove || (!canFitBelow && availableAbove >= availableBelow)
    : !canFitBelow && (canFitAbove || availableAbove > availableBelow);
  const availableHeight = placedAbove ? availableAbove : availableBelow;
  const resolvedMaxHeight = Math.max(1, Math.min(heightLimit, availableHeight));
  const renderedHeight = Math.min(desiredHeight, resolvedMaxHeight);
  const rawTop = placedAbove
    ? rect.top - safeGap - renderedHeight
    : belowTop;
  const maxTop = Math.max(
    safeViewportPadding,
    window.innerHeight - renderedHeight - safeViewportPadding,
  );
  const top = clampNumber(rawTop, safeViewportPadding, maxTop);

  return {
    top,
    left,
    width,
    maxHeight: resolvedMaxHeight,
    placedAbove,
  };
}
