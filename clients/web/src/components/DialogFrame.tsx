import type { ComponentChildren, JSX } from 'preact';
import { useEffect } from 'preact/hooks';
import { clampNumber, normalizeInteger } from '../shared/util/number';
import { OverlayPortal } from './OverlayPortal';

type DialogPanelAnimation = 'pop' | 'slideUp' | 'none';

export const DIALOG_OVERLAY_LOW_Z_INDEX = 2400;
export const DIALOG_OVERLAY_BASE_Z_INDEX = 2600;
export const DIALOG_OVERLAY_MEDIA_Z_INDEX = 2700;
export const DIALOG_OVERLAY_PRIORITY_Z_INDEX = 2800;
export const DIALOG_OVERLAY_FOCUSED_Z_INDEX = 2900;
export const DIALOG_OVERLAY_TOP_Z_INDEX = 3000;
export const DIALOG_OVERLAY_DEFAULT_BACKGROUND = 'rgba(0,0,0,0.38)';
export const DIALOG_OVERLAY_SOFT_BACKGROUND = 'rgba(0,0,0,0.36)';
export const DIALOG_OVERLAY_STRONG_BACKGROUND = 'rgba(0,0,0,0.40)';
export const DIALOG_OVERLAY_INTENSE_BACKGROUND = 'rgba(0,0,0,0.45)';
export const DIALOG_OVERLAY_DEFAULT_BLUR_PX = 2;
export const DIALOG_OVERLAY_MAX_BLUR_PX = 12;
export const DIALOG_OVERLAY_INVERSE_BACKGROUND =
  'color-mix(in srgb, var(--m3-inverse-surface) 44%, transparent)';
export const DIALOG_OVERLAY_CENTER_CLASS =
  'fixed inset-0 flex items-center justify-center p-4';
export const DIALOG_OVERLAY_CENTER_FLUSH_CLASS =
  'fixed inset-0 flex items-center justify-center';
export const DIALOG_OVERLAY_CENTER_COMPACT_CLASS =
  'fixed inset-0 flex items-center justify-center px-4';
export const DIALOG_OVERLAY_EDGE_SHEET_CLASS =
  'fixed inset-0 flex items-end justify-center';

export interface DialogOverlayStyleOptions {
  background?: string;
  blurPx?: number;
  zIndex?: number;
}

export const DIALOG_PANEL_DEFAULT_BACKGROUND = 'var(--m3-surface-container)';
export const DIALOG_PANEL_DEFAULT_COLOR = 'var(--m3-on-surface)';
export const DIALOG_PANEL_DEFAULT_SHADOW = 'var(--m3-elev-3)';
export const DIALOG_PANEL_DEFAULT_BORDER = '1px solid var(--m3-outline-variant)';
const DIALOG_SCROLL_LOCK_STYLE_VALUE = 'hidden';

export interface DialogPanelSurfaceStyleOptions {
  background?: string;
  color?: string;
  boxShadow?: string;
  border?: string;
  width?: string;
  maxWidth?: string;
  maxHeight?: string;
  overflow?: JSX.CSSProperties['overflow'];
}

export interface DialogFrameProps {
  children: ComponentChildren;
  closing: boolean;
  onRequestClose?: () => void;
  closeOnBackdrop?: boolean;
  overlayClassName?: string;
  panelClassName?: string;
  overlayStyle?: JSX.CSSProperties;
  panelStyle?: JSX.CSSProperties;
  panelAnimation?: DialogPanelAnimation;
  ariaLabel?: string;
  ariaLabelledBy?: string;
}

export function createDialogOverlayStyle({
  background = DIALOG_OVERLAY_DEFAULT_BACKGROUND,
  blurPx = DIALOG_OVERLAY_DEFAULT_BLUR_PX,
  zIndex = DIALOG_OVERLAY_BASE_Z_INDEX,
}: DialogOverlayStyleOptions = {}): JSX.CSSProperties {
  const resolvedBackground =
    typeof background === 'string' && background.trim()
      ? background
      : DIALOG_OVERLAY_DEFAULT_BACKGROUND;
  const safeBlurPx = clampNumber(blurPx, 0, DIALOG_OVERLAY_MAX_BLUR_PX);
  const safeZIndex = normalizeInteger(zIndex, {
    fallback: DIALOG_OVERLAY_BASE_Z_INDEX,
    min: 1,
  });
  const style: JSX.CSSProperties = { background: resolvedBackground };
  if (safeBlurPx > 0) {
    style.backdropFilter = `blur(${safeBlurPx}px)`;
  }
  style.zIndex = safeZIndex;
  return style;
}

export const DIALOG_OVERLAY_DEFAULT_STYLE = createDialogOverlayStyle();

function stringStyleValueOr(value: string | undefined, fallback: string): string {
  return typeof value === 'string' && value.trim() ? value : fallback;
}

function assignStringStyleValue<K extends keyof JSX.CSSProperties>(
  style: JSX.CSSProperties,
  key: K,
  value: string | undefined,
): void {
  if (typeof value !== 'string' || !value.trim()) return;
  style[key] = value as JSX.CSSProperties[K];
}

export function createDialogPanelSurfaceStyle({
  background,
  color,
  boxShadow,
  border,
  width,
  maxWidth,
  maxHeight,
  overflow,
}: DialogPanelSurfaceStyleOptions = {}): JSX.CSSProperties {
  const style: JSX.CSSProperties = {
    background: stringStyleValueOr(background, DIALOG_PANEL_DEFAULT_BACKGROUND),
    color: stringStyleValueOr(color, DIALOG_PANEL_DEFAULT_COLOR),
    boxShadow: stringStyleValueOr(boxShadow, DIALOG_PANEL_DEFAULT_SHADOW),
    border: stringStyleValueOr(border, DIALOG_PANEL_DEFAULT_BORDER),
  };
  assignStringStyleValue(style, 'width', width);
  assignStringStyleValue(style, 'maxWidth', maxWidth);
  assignStringStyleValue(style, 'maxHeight', maxHeight);
  if (overflow != null) style.overflow = overflow;
  return style;
}

function panelMotionClass(animation: DialogPanelAnimation, closing: boolean): string {
  switch (animation) {
    case 'slideUp':
      return closing ? 'oh-dialog-sheet-out' : 'oh-dialog-sheet-in';
    case 'none':
      return '';
    case 'pop':
    default:
      return closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in';
  }
}

export function dialogClassNames(...values: Array<string | undefined | false>): string {
  return values
    .flatMap((value) => (value ? value.trim().split(/\s+/) : []))
    .filter(Boolean)
    .join(' ');
}

function dialogPanelStyle(
  style: JSX.CSSProperties | undefined,
  closing: boolean,
): JSX.CSSProperties | undefined {
  if (!closing) return style;
  return {
    ...style,
    pointerEvents: 'none',
  };
}

let dialogScrollLockCount = 0;
let previousBodyOverflow = '';
let previousDocumentOverflow = '';

function acquireDialogScrollLock(): () => void {
  if (typeof document === 'undefined') return () => {};
  const { body, documentElement } = document;
  if (dialogScrollLockCount === 0) {
    previousBodyOverflow = body.style.overflow;
    previousDocumentOverflow = documentElement.style.overflow;
    body.style.overflow = DIALOG_SCROLL_LOCK_STYLE_VALUE;
    documentElement.style.overflow = DIALOG_SCROLL_LOCK_STYLE_VALUE;
  }
  dialogScrollLockCount += 1;

  let released = false;
  return () => {
    if (released) return;
    released = true;
    dialogScrollLockCount = Math.max(0, dialogScrollLockCount - 1);
    if (dialogScrollLockCount > 0) return;
    body.style.overflow = previousBodyOverflow;
    documentElement.style.overflow = previousDocumentOverflow;
    previousBodyOverflow = '';
    previousDocumentOverflow = '';
  };
}

export function DialogFrame({
  children,
  closing,
  onRequestClose,
  closeOnBackdrop = true,
  overlayClassName = DIALOG_OVERLAY_CENTER_CLASS,
  panelClassName = '',
  overlayStyle = DIALOG_OVERLAY_DEFAULT_STYLE,
  panelStyle,
  panelAnimation = 'pop',
  ariaLabel,
  ariaLabelledBy,
}: DialogFrameProps) {
  useEffect(() => acquireDialogScrollLock(), []);

  const overlayMotionClass = closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in';
  const panelClass = panelMotionClass(panelAnimation, closing);
  const overlayClass = dialogClassNames(overlayMotionClass, overlayClassName);
  const sectionClass = dialogClassNames(
    'oh-dialog-panel',
    panelClass,
    panelClassName,
  );
  const allowBackdropClose = !closing && closeOnBackdrop && onRequestClose != null;
  const handleBackdropClick = (event: JSX.TargetedMouseEvent<HTMLDivElement>) => {
    if (!allowBackdropClose || event.target !== event.currentTarget) {
      return;
    }
    onRequestClose();
  };

  return (
    <OverlayPortal>
      <div
        class={overlayClass}
        style={overlayStyle}
        onClick={handleBackdropClick}
        data-closing={closing ? 'true' : undefined}
      >
        <section
          role="dialog"
          aria-modal="true"
          aria-label={ariaLabel}
          aria-labelledby={ariaLabelledBy}
          class={sectionClass}
          style={dialogPanelStyle(panelStyle, closing)}
          onClick={(event) => event.stopPropagation()}
          data-closing={closing ? 'true' : undefined}
        >
          {children}
        </section>
      </div>
    </OverlayPortal>
  );
}
