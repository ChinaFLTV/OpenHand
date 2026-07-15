import { clampNumber } from '../util/number';

type FloatingHorizontalAlign = 'left' | 'right';
export type FloatingVerticalPlacement = 'auto' | 'above' | 'below';

interface AnchoredMenuPosition {
  top: number;
  left: number;
  width: number;
  placedAbove: boolean;
}

interface AnchoredMenuPositionOptions {
  anchor: HTMLElement | null;
  preferredWidth?: number;
  minWidth?: number;
  measuredHeight?: number;
  fallbackHeight?: number;
  align?: FloatingHorizontalAlign;
  verticalPlacement?: FloatingVerticalPlacement;
  viewportPadding?: number;
  gap?: number;
}

export const DEFAULT_FLOATING_VIEWPORT_PADDING = 8;
export const DEFAULT_FLOATING_ANCHOR_GAP = 4;
const DEFAULT_FLOATING_MIN_WIDTH = 160;
const DEFAULT_FLOATING_FALLBACK_HEIGHT = 160;

export function computeAnchoredMenuPosition({
  anchor,
  preferredWidth,
  minWidth = DEFAULT_FLOATING_MIN_WIDTH,
  measuredHeight = 0,
  fallbackHeight = DEFAULT_FLOATING_FALLBACK_HEIGHT,
  align = 'right',
  verticalPlacement = 'auto',
  viewportPadding = DEFAULT_FLOATING_VIEWPORT_PADDING,
  gap = DEFAULT_FLOATING_ANCHOR_GAP,
}: AnchoredMenuPositionOptions): AnchoredMenuPosition {
  if (typeof window === 'undefined' || !anchor) {
    return {
      top: viewportPadding,
      left: viewportPadding,
      width: Math.max(minWidth, preferredWidth ?? minWidth),
      placedAbove: false,
    };
  }

  const rect = anchor.getBoundingClientRect();
  const usableWidth = Math.max(minWidth, window.innerWidth - viewportPadding * 2);
  const width = Math.min(
    Math.max(preferredWidth ?? rect.width, minWidth),
    usableWidth,
  );
  const minLeft = viewportPadding;
  const maxLeft = Math.max(minLeft, window.innerWidth - width - viewportPadding);
  const rawLeft = align === 'right' ? rect.right - width : rect.left;
  const left = clampNumber(rawLeft, minLeft, maxLeft);

  const height = measuredHeight > 0 ? measuredHeight : fallbackHeight;
  const belowTop = rect.bottom + gap;
  const aboveTop = rect.top - height - gap;
  const canFitBelow = belowTop + height <= window.innerHeight - viewportPadding;
  const canFitAbove = aboveTop >= viewportPadding;
  const placedAbove = verticalPlacement === 'above'
    ? canFitAbove || !canFitBelow
    : !canFitBelow && canFitAbove;
  const rawTop = placedAbove ? aboveTop : belowTop;
  const maxTop = Math.max(viewportPadding, window.innerHeight - height - viewportPadding);
  const top = clampNumber(rawTop, viewportPadding, maxTop);

  return { top, left, width, placedAbove };
}
