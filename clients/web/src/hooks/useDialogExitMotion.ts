import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { registerOverlayEscapeLayer } from '../shared/ui/overlay_escape_stack';
import { useEventCallback } from './useEventCallback';
import { normalizeDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';
import { useTimeoutController } from './useTimeoutController';

interface DialogExitMotionOptions {
  exitMs?: number;
  closeOnEscape?: boolean;
  active?: boolean;
  onBeforeClose?: (reason?: string) => void;
}

interface DialogExitMotionController<Reason extends string = string> {
  closing: boolean;
  requestClose: () => void;
  requestCloseWithReason: (reason?: Reason) => void;
  resetClosing: () => void;
}

export function useDialogExitMotion(
  onClose: () => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
): DialogExitMotionController;
export function useDialogExitMotion<Reason extends string>(
  onClose: (reason?: Reason) => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
): DialogExitMotionController<Reason>;
export function useDialogExitMotion<Reason extends string = string>(
  onClose: (reason?: Reason) => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
): DialogExitMotionController<Reason> {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const options =
    typeof optionsOrExitMs === 'object' && optionsOrExitMs != null
      ? optionsOrExitMs
      : undefined;
  const closingRef = useRef(false);
  const closeReasonRef = useRef<Reason | undefined>(undefined);
  const { clearTimer, scheduleTimer } = useTimeoutController();
  const exitMs =
    typeof optionsOrExitMs === 'number' ? optionsOrExitMs : options?.exitMs;
  const closeOnEscape = options?.closeOnEscape !== false;
  const active = options?.active !== false;
  const onBeforeClose = options?.onBeforeClose as
    | ((reason?: Reason) => void)
    | undefined;

  const finishClose = useEventCallback(() => {
    const reason = closeReasonRef.current;
    closeReasonRef.current = undefined;
    onClose(reason);
  });

  const requestCloseWithReason = useEventCallback((reason?: Reason) => {
    if (closingRef.current) return;
    closeReasonRef.current = reason;
    try {
      onBeforeClose?.(reason);
    } finally {
      closingRef.current = true;
      setClosing(true);
      const durationMs = reduceMotion
        ? 0
        : normalizeDialogExitDurationMs(exitMs);
      scheduleTimer(finishClose, durationMs);
    }
  });
  const canCloseOnEscape = useEventCallback(() => closeOnEscape);

  const requestClose = useCallback(() => {
    requestCloseWithReason();
  }, [requestCloseWithReason]);

  const resetClosing = useCallback(() => {
    clearTimer();
    closingRef.current = false;
    closeReasonRef.current = undefined;
    setClosing(false);
  }, [clearTimer]);

  useEffect(() => {
    if (!active || typeof window === 'undefined') return undefined;
    return registerOverlayEscapeLayer({
      canClose: canCloseOnEscape,
      requestClose: () => {
        requestCloseWithReason('escape' as Reason);
      },
    });
  }, [active, canCloseOnEscape, requestCloseWithReason]);

  return { closing, requestClose, requestCloseWithReason, resetClosing };
}
