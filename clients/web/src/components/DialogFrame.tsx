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

export interface DialogFrameAppearanceOptions {
  overlayClassName?: string;
  overlay?: DialogOverlayStyleOptions;
  overlayStyle?: JSX.CSSProperties;
  panelClassName?: string;
  panelSurface?: DialogPanelSurfaceStyleOptions;
  panelStyle?: JSX.CSSProperties;
  panelStyleOverrides?: JSX.CSSProperties;
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

export function createDialogFrameAppearance({
  overlayClassName = DIALOG_OVERLAY_CENTER_CLASS,
  overlay,
  overlayStyle,
  panelClassName = '',
  panelSurface,
  panelStyle,
  panelStyleOverrides,
}: DialogFrameAppearanceOptions = {}): Pick<
  DialogFrameProps,
  'overlayClassName' | 'overlayStyle' | 'panelClassName' | 'panelStyle'
> {
  const resolvedPanelStyle =
    panelStyle ?? {
      ...createDialogPanelSurfaceStyle(panelSurface),
      ...panelStyleOverrides,
    };
  return {
    overlayClassName,
    overlayStyle: overlayStyle ?? createDialogOverlayStyle(overlay),
    panelClassName,
    panelStyle: resolvedPanelStyle,
  };
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

export function DialogCloseIcon({ size = 16 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  );
}

export interface DialogCloseButtonProps {
  onClick: () => void;
  label?: string;
  disabled?: boolean;
  className?: string;
  style?: JSX.CSSProperties;
  iconSize?: number;
}

export function DialogCloseButton({
  onClick,
  label = 'close',
  disabled = false,
  className,
  style,
  iconSize = 16,
}: DialogCloseButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      class={dialogClassNames(
        className ??
          'oh-tap-press inline-flex h-8 w-8 items-center justify-center rounded-m3-sm',
        disabled && 'opacity-60',
      )}
      style={style ?? { color: 'var(--m3-on-surface-variant)' }}
      aria-label={label}
    >
      <DialogCloseIcon size={iconSize} />
    </button>
  );
}

export interface DialogHeaderProps {
  title: ComponentChildren;
  subtitle?: ComponentChildren;
  icon?: ComponentChildren;
  actions?: ComponentChildren;
  onClose?: () => void;
  closeLabel?: string;
  closeDisabled?: boolean;
  className?: string;
  titleClassName?: string;
  subtitleClassName?: string;
  closeClassName?: string;
  closeStyle?: JSX.CSSProperties;
  closeIconSize?: number;
  borderColor?: string;
}

export function DialogHeader({
  title,
  subtitle,
  icon,
  actions,
  onClose,
  closeLabel,
  closeDisabled = false,
  className = 'px-6 py-4 flex items-center justify-between gap-4',
  titleClassName = 'text-base font-semibold',
  subtitleClassName = 'text-xs mt-1 truncate',
  closeClassName,
  closeStyle,
  closeIconSize,
  borderColor = 'var(--m3-outline-variant)',
}: DialogHeaderProps) {
  return (
    <header class={className} style={{ borderBottom: `1px solid ${borderColor}` }}>
      <div class="flex items-center gap-3 min-w-0">
        {icon ? <div class="shrink-0">{icon}</div> : null}
        <div class="min-w-0">
          <h2
            class={titleClassName}
            style={{ color: 'var(--m3-on-surface)' }}
          >
            {title}
          </h2>
          {subtitle ? (
            <p
              class={subtitleClassName}
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {subtitle}
            </p>
          ) : null}
        </div>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        {actions}
        {onClose ? (
          <DialogCloseButton
            onClick={onClose}
            label={closeLabel}
            disabled={closeDisabled}
            className={closeClassName}
            style={closeStyle}
            iconSize={closeIconSize}
          />
        ) : null}
      </div>
    </header>
  );
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
