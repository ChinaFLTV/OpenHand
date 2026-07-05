import type { ComponentChildren, JSX } from 'preact';
import { useEffect } from 'preact/hooks';
import { clampNumber, normalizeInteger } from '../shared/util/number';
import { strictStringFromUnknown } from '../shared/util/value';
import { OverlayPortal } from './OverlayPortal';

type DialogPanelAnimation = 'pop' | 'slideUp' | 'none';
export type DialogOverlayTone =
  | 'default'
  | 'soft'
  | 'strong'
  | 'intense'
  | 'inverse'
  | 'scrim';
export type DialogPanelBorder =
  | 'default'
  | 'outline'
  | 'outlineVariant'
  | 'none';

export const DIALOG_OVERLAY_LOW_Z_INDEX = 2400;
const DIALOG_OVERLAY_BASE_Z_INDEX = 2600;
export const DIALOG_OVERLAY_MEDIA_Z_INDEX = 2700;
export const DIALOG_OVERLAY_PRIORITY_Z_INDEX = 2800;
export const DIALOG_OVERLAY_FOCUSED_Z_INDEX = 2900;
export const DIALOG_OVERLAY_TOP_Z_INDEX = 3000;
const DIALOG_OVERLAY_DEFAULT_BACKGROUND = 'rgba(0,0,0,0.38)';
const DIALOG_OVERLAY_SOFT_BACKGROUND = 'rgba(0,0,0,0.36)';
const DIALOG_OVERLAY_STRONG_BACKGROUND = 'rgba(0,0,0,0.40)';
const DIALOG_OVERLAY_INTENSE_BACKGROUND = 'rgba(0,0,0,0.45)';
const DIALOG_OVERLAY_DEFAULT_BLUR_PX = 2;
const DIALOG_OVERLAY_MAX_BLUR_PX = 12;
const DIALOG_OVERLAY_INVERSE_BACKGROUND =
  'color-mix(in srgb, var(--m3-inverse-surface) 44%, transparent)';
const DIALOG_OVERLAY_CENTER_CLASS =
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

const DIALOG_PANEL_DEFAULT_BACKGROUND = 'var(--m3-surface-container)';
const DIALOG_PANEL_DEFAULT_COLOR = 'var(--m3-on-surface)';
const DIALOG_PANEL_DEFAULT_SHADOW = 'var(--m3-elev-3)';
const DIALOG_PANEL_DEFAULT_BORDER = '1px solid var(--m3-outline-variant)';
const DIALOG_PANEL_OUTLINE_BORDER = '1px solid var(--m3-outline)';
const DIALOG_PANEL_OUTLINE_VARIANT_BORDER =
  '1px solid var(--m3-outline-variant)';
const DIALOG_PANEL_BORDERLESS = 'none';
const DIALOG_SCROLL_LOCK_STYLE_VALUE = 'hidden';
const DIALOG_SCROLL_LOCK_DATASET_KEY = 'dialogScrollLocked';
const DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY = 'overscroll-behavior';
const DIALOG_SCROLL_LOCK_OVERSCROLL_VALUE = 'none';

interface DialogPanelSurfaceStyleOptions {
  background?: string;
  color?: string;
  boxShadow?: string;
  border?: string;
  width?: string;
  maxWidth?: string;
  maxHeight?: string;
  overflow?: JSX.CSSProperties['overflow'];
}

interface DialogFrameAppearanceOptions {
  overlayClassName?: string;
  overlay?: DialogOverlayStyleOptions;
  overlayStyle?: JSX.CSSProperties;
  panelClassName?: string;
  panelSurface?: DialogPanelSurfaceStyleOptions;
  panelStyle?: JSX.CSSProperties;
  panelStyleOverrides?: JSX.CSSProperties;
}

export interface StandardDialogFrameAppearanceOptions
  extends DialogFrameAppearanceOptions {
  overlayTone?: DialogOverlayTone;
  overlayZIndex?: number;
  overlayBlurPx?: number;
  panelBorder?: DialogPanelBorder;
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

export type DialogFrameAppearance = Pick<
  DialogFrameProps,
  'overlayClassName' | 'overlayStyle' | 'panelClassName' | 'panelStyle'
>;

function createDialogOverlayStyle({
  background = DIALOG_OVERLAY_DEFAULT_BACKGROUND,
  blurPx = DIALOG_OVERLAY_DEFAULT_BLUR_PX,
  zIndex = DIALOG_OVERLAY_BASE_Z_INDEX,
}: DialogOverlayStyleOptions = {}): JSX.CSSProperties {
  const resolvedBackground =
    strictStringFromUnknown(background) || DIALOG_OVERLAY_DEFAULT_BACKGROUND;
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

const DIALOG_OVERLAY_DEFAULT_STYLE = createDialogOverlayStyle();

function stringStyleValueOr(value: string | undefined, fallback: string): string {
  return strictStringFromUnknown(value) || fallback;
}

function assignStringStyleValue<K extends keyof JSX.CSSProperties>(
  style: JSX.CSSProperties,
  key: K,
  value: string | undefined,
): void {
  const resolved = strictStringFromUnknown(value);
  if (!resolved) return;
  style[key] = resolved as JSX.CSSProperties[K];
}

function createDialogPanelSurfaceStyle({
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

function createDialogFrameAppearance({
  overlayClassName = DIALOG_OVERLAY_CENTER_CLASS,
  overlay,
  overlayStyle,
  panelClassName = '',
  panelSurface,
  panelStyle,
  panelStyleOverrides,
}: DialogFrameAppearanceOptions = {}): DialogFrameAppearance {
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

function dialogOverlayBackground(tone: DialogOverlayTone): string {
  switch (tone) {
    case 'soft':
      return DIALOG_OVERLAY_SOFT_BACKGROUND;
    case 'strong':
      return DIALOG_OVERLAY_STRONG_BACKGROUND;
    case 'intense':
      return DIALOG_OVERLAY_INTENSE_BACKGROUND;
    case 'inverse':
      return DIALOG_OVERLAY_INVERSE_BACKGROUND;
    case 'scrim':
      return 'var(--m3-scrim-bg)';
    case 'default':
    default:
      return DIALOG_OVERLAY_DEFAULT_BACKGROUND;
  }
}

function dialogPanelBorderValue(border: DialogPanelBorder): string {
  switch (border) {
    case 'outline':
      return DIALOG_PANEL_OUTLINE_BORDER;
    case 'outlineVariant':
      return DIALOG_PANEL_OUTLINE_VARIANT_BORDER;
    case 'none':
      return DIALOG_PANEL_BORDERLESS;
    case 'default':
    default:
      return DIALOG_PANEL_DEFAULT_BORDER;
  }
}

export function createStandardDialogFrameAppearance({
  overlayTone,
  overlayZIndex,
  overlayBlurPx,
  overlay,
  panelBorder,
  panelSurface,
  ...rest
}: StandardDialogFrameAppearanceOptions = {}): DialogFrameAppearance {
  const resolvedOverlay =
    overlayTone == null && overlayZIndex == null && overlayBlurPx == null
      ? overlay
      : {
          ...overlay,
          background:
            overlay?.background ??
            dialogOverlayBackground(overlayTone ?? 'default'),
          zIndex: overlay?.zIndex ?? overlayZIndex,
          blurPx: overlay?.blurPx ?? overlayBlurPx,
        };
  const resolvedPanelSurface =
    panelBorder == null
      ? panelSurface
      : {
          ...panelSurface,
          border: panelSurface?.border ?? dialogPanelBorderValue(panelBorder),
        };
  return createDialogFrameAppearance({
    ...rest,
    overlay: resolvedOverlay,
    panelSurface: resolvedPanelSurface,
  });
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

function dialogClassNames(
  ...values: Array<string | null | undefined | false>
): string {
  return values
    .flatMap((value) => (value ? value.trim().split(/\s+/) : []))
    .filter(Boolean)
    .join(' ');
}

function DialogCloseIcon({ size = 16 }: { size?: number }) {
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

interface DialogCloseButtonProps {
  onClick: () => void;
  label?: string;
  disabled?: boolean;
  className?: string;
  style?: JSX.CSSProperties;
  iconSize?: number;
}

function DialogCloseButton({
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

export type DialogActionButtonTone =
  | 'primary'
  | 'secondary'
  | 'ghost'
  | 'danger';

export interface DialogActionButtonProps {
  children: ComponentChildren;
  type?: 'button' | 'submit' | 'reset';
  tone?: DialogActionButtonTone;
  onClick?: JSX.MouseEventHandler<HTMLButtonElement>;
  disabled?: boolean;
  className?: string;
  style?: JSX.CSSProperties;
  title?: string;
  ariaLabel?: string;
}

const DIALOG_ACTION_BUTTON_TONE_STYLES: Record<
  DialogActionButtonTone,
  JSX.CSSProperties
> = {
  primary: {
    color: 'var(--m3-on-primary)',
    background: 'var(--m3-primary)',
    border:
      '1px solid color-mix(in srgb, var(--m3-primary) 70%, transparent)',
  },
  secondary: {
    color: 'var(--m3-on-surface)',
    background: 'var(--m3-surface-container-high)',
    border: '1px solid var(--m3-outline)',
  },
  ghost: {
    color: 'var(--m3-on-surface-variant)',
    background: 'transparent',
    border: '1px solid transparent',
  },
  danger: {
    color: 'var(--m3-on-primary)',
    background: 'var(--m3-error)',
    border: '1px solid transparent',
  },
};

export function DialogActionButton({
  children,
  type = 'button',
  tone = 'secondary',
  onClick,
  disabled = false,
  className,
  style,
  title,
  ariaLabel,
}: DialogActionButtonProps) {
  return (
    <button
      type={type}
      class={dialogClassNames(
        'oh-tap-press oh-dialog-action-button',
        disabled && 'opacity-60',
        className,
      )}
      style={{
        ...DIALOG_ACTION_BUTTON_TONE_STYLES[tone],
        cursor: disabled ? 'not-allowed' : 'pointer',
        ...style,
      }}
      onClick={onClick}
      disabled={disabled}
      title={title}
      aria-label={ariaLabel}
    >
      {children}
    </button>
  );
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
let previousBodyOverscrollBehavior = '';
let previousDocumentOverscrollBehavior = '';

function restoreStyleProperty(
  style: CSSStyleDeclaration,
  property: string,
  value: string,
): void {
  if (value) {
    style.setProperty(property, value);
  } else {
    style.removeProperty(property);
  }
}

function acquireDialogScrollLock(): () => void {
  if (typeof document === 'undefined') return () => {};
  const { body, documentElement } = document;
  if (dialogScrollLockCount === 0) {
    previousBodyOverflow = body.style.overflow;
    previousDocumentOverflow = documentElement.style.overflow;
    previousBodyOverscrollBehavior = body.style.getPropertyValue(
      DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY,
    );
    previousDocumentOverscrollBehavior =
      documentElement.style.getPropertyValue(
        DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY,
      );
    body.style.overflow = DIALOG_SCROLL_LOCK_STYLE_VALUE;
    documentElement.style.overflow = DIALOG_SCROLL_LOCK_STYLE_VALUE;
    body.style.setProperty(
      DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY,
      DIALOG_SCROLL_LOCK_OVERSCROLL_VALUE,
    );
    documentElement.style.setProperty(
      DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY,
      DIALOG_SCROLL_LOCK_OVERSCROLL_VALUE,
    );
    body.dataset[DIALOG_SCROLL_LOCK_DATASET_KEY] = 'true';
    documentElement.dataset[DIALOG_SCROLL_LOCK_DATASET_KEY] = 'true';
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
    restoreStyleProperty(
      body.style,
      DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY,
      previousBodyOverscrollBehavior,
    );
    restoreStyleProperty(
      documentElement.style,
      DIALOG_SCROLL_LOCK_OVERSCROLL_PROPERTY,
      previousDocumentOverscrollBehavior,
    );
    delete body.dataset[DIALOG_SCROLL_LOCK_DATASET_KEY];
    delete documentElement.dataset[DIALOG_SCROLL_LOCK_DATASET_KEY];
    previousBodyOverflow = '';
    previousDocumentOverflow = '';
    previousBodyOverscrollBehavior = '';
    previousDocumentOverscrollBehavior = '';
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
