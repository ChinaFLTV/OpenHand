import type { ComponentChildren, JSX } from 'preact';
import { OverlayPortal } from './OverlayPortal';

type DialogPanelAnimation = 'pop' | 'slideUp' | 'none';

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

function panelMotionClass(animation: DialogPanelAnimation, closing: boolean): string {
  switch (animation) {
    case 'slideUp':
      return closing ? 'oh-dialog-slide-down-out' : 'oh-dialog-slide-up-in';
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
  overlayStyle,
  panelStyle,
  panelAnimation = 'pop',
  ariaLabel,
  ariaLabelledBy,
}: DialogFrameProps) {
  const overlayMotionClass = closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in';
  const panelClass = panelMotionClass(panelAnimation, closing);
  const handleBackdropClick = (event: JSX.TargetedMouseEvent<HTMLDivElement>) => {
    if (!closeOnBackdrop || !onRequestClose || event.target !== event.currentTarget) {
      return;
    }
    onRequestClose();
  };

  return (
    <OverlayPortal>
      <div
        class={`${overlayMotionClass} ${overlayClassName}`}
        style={overlayStyle}
        onClick={handleBackdropClick}
      >
        <section
          role="dialog"
          aria-modal="true"
          aria-label={ariaLabel}
          aria-labelledby={ariaLabelledBy}
          class={`${panelClass} ${panelClassName}`}
          style={panelStyle}
          onClick={(event) => event.stopPropagation()}
        >
          {children}
        </section>
      </div>
    </OverlayPortal>
  );
}
