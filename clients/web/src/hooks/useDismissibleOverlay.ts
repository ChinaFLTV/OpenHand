import { useEffect } from 'preact/hooks';
import { registerOverlayEscapeLayer } from '../shared/ui/overlay_escape_stack';
import { useEventCallback } from './useEventCallback';

interface DismissibleOverlayTarget {
  readonly current: HTMLElement | null;
}

interface UseDismissibleOverlayOptions {
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

export function useDismissibleOverlay({
  active,
  targets,
  onDismiss,
  onEscape,
  pointerEventName = 'mousedown',
}: UseDismissibleOverlayOptions): void {
  const requestDismiss = useEventCallback(onDismiss);
  const requestEscapeClose = useEventCallback(() => {
    (onEscape ?? onDismiss)();
  });

  useEffect(() => {
    if (!active || typeof document === 'undefined') return undefined;

    const handlePointer = (event: MouseEvent | PointerEvent) => {
      if (targetInsideOverlay(event.target, targets)) return;
      requestDismiss();
    };

    document.addEventListener(pointerEventName, handlePointer);
    return () => {
      document.removeEventListener(pointerEventName, handlePointer);
    };
  }, [active, pointerEventName, requestDismiss, targets]);

  useEffect(() => {
    if (!active || typeof window === 'undefined') return undefined;
    return registerOverlayEscapeLayer({
      canClose: () => true,
      requestClose: requestEscapeClose,
    });
  }, [active, requestEscapeClose]);
}
