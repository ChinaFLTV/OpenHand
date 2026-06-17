import type { ComponentChildren, JSX } from 'preact';
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
export const DIALOG_OVERLAY_INVERSE_BACKGROUND =
  'color-mix(in srgb, var(--m3-inverse-surface) 44%, transparent)';

export interface DialogOverlayStyleOptions {
  background?: string;
  blurPx?: number;
  zIndex?: number;
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
  blurPx = 2,
  zIndex = DIALOG_OVERLAY_BASE_Z_INDEX,
}: DialogOverlayStyleOptions = {}): JSX.CSSProperties {
  const style: JSX.CSSProperties = { background };
  if (blurPx > 0) {
    style.backdropFilter = `blur(${blurPx}px)`;
  }
  if (zIndex != null) {
    style.zIndex = zIndex;
  }
  return style;
}

export const DIALOG_OVERLAY_DEFAULT_STYLE = createDialogOverlayStyle();

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

export function DialogFrame({
  children,
  closing,
  onRequestClose,
  closeOnBackdrop = true,
  overlayClassName = 'fixed inset-0 flex items-center justify-center p-4',
  panelClassName = '',
  overlayStyle = DIALOG_OVERLAY_DEFAULT_STYLE,
  panelStyle,
  panelAnimation = 'pop',
  ariaLabel,
  ariaLabelledBy,
}: DialogFrameProps) {
  const overlayMotionClass = closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in';
  const panelClass = panelMotionClass(panelAnimation, closing);
  const overlayClass = `${overlayMotionClass} ${overlayClassName}`.trim();
  const sectionClass = `${panelClass} ${panelClassName}`.trim();
  const handleBackdropClick = (event: JSX.TargetedMouseEvent<HTMLDivElement>) => {
    if (closing || !closeOnBackdrop || !onRequestClose || event.target !== event.currentTarget) {
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
      >
        <section
          role="dialog"
          aria-modal="true"
          aria-label={ariaLabel}
          aria-labelledby={ariaLabelledBy}
          class={sectionClass}
          style={panelStyle}
          onClick={(event) => event.stopPropagation()}
        >
          {children}
        </section>
      </div>
    </OverlayPortal>
  );
}
