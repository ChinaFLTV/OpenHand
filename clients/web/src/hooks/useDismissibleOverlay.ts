import { useEffect } from 'preact/hooks';

export interface DismissibleOverlayTarget {
  readonly current: HTMLElement | null;
}

export interface UseDismissibleOverlayOptions {
  active: boolean;
  targets: ReadonlyArray<DismissibleOverlayTarget>;
  onDismiss: () => void;
  onEscape?: () => void;
  pointerEventName?: 'mousedown' | 'pointerdown';
}

function targetInsideOverlay(
  target: EventTarget | null,
  targets: ReadonlyArray<DismissibleOverlayTarget>,
): boolean {
  if (!(target instanceof Node)) return false;
  return targets.some((ref) => {
    const element = ref.current;
    return element != null && element.contains(target);
  });
}

function consumeEscape(event: KeyboardEvent): void {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation?.();
}

export function useDismissibleOverlay({
  active,
  targets,
  onDismiss,
  onEscape,
  pointerEventName = 'mousedown',
}: UseDismissibleOverlayOptions): void {
  useEffect(() => {
    if (!active || typeof document === 'undefined') return undefined;

    const handlePointer = (event: MouseEvent | PointerEvent) => {
      if (targetInsideOverlay(event.target, targets)) return;
      onDismiss();
    };
    const handleKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.key !== 'Escape') return;
      consumeEscape(event);
      (onEscape ?? onDismiss)();
    };

    document.addEventListener(pointerEventName, handlePointer);
    document.addEventListener('keydown', handleKey);
    return () => {
      document.removeEventListener(pointerEventName, handlePointer);
      document.removeEventListener('keydown', handleKey);
    };
  }, [active, onDismiss, onEscape, pointerEventName, targets]);
}
