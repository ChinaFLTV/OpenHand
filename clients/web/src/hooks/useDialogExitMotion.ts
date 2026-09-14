import { useCallback, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { useEventCallback } from './useEventCallback';
import { normalizeDialogExitDurationMs, useDialogMotionDurations } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';
import { useTimeoutController } from './useTimeoutController';

interface DialogExitMotionOptions {
  exitMs?: number;
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
  const { exitMs: settingsExitMs } = useDialogMotionDurations();
  const [closing, setClosing] = useState(false);
  const options =
    typeof optionsOrExitMs === 'object' && optionsOrExitMs != null
      ? optionsOrExitMs
      : undefined;
  const closingRef = useRef(false);
  const finishedRef = useRef(false);
  const startedAtRef = useRef(0);
  const closeReasonRef = useRef<Reason | undefined>(undefined);
  const { clearTimer, scheduleTimer } = useTimeoutController();
  const exitMs =
    typeof optionsOrExitMs === 'number' ? optionsOrExitMs : options?.exitMs;
  const durationMs = reduceMotion ? 0 : normalizeDialogExitDurationMs(exitMs ?? settingsExitMs);
  const onBeforeClose = options?.onBeforeClose as
    | ((reason?: Reason) => void)
    | undefined;

  const finishClose = useEventCallback(() => {
    if (!closingRef.current || finishedRef.current) return;
    finishedRef.current = true;
    const reason = closeReasonRef.current;
    closeReasonRef.current = undefined;
    onClose(reason);
  });

  const requestCloseWithReason = useEventCallback((reason?: Reason) => {
    if (closingRef.current) return;
    closingRef.current = true;
    startedAtRef.current = performance.now();
    closeReasonRef.current = reason;
    try {
      onBeforeClose?.(reason);
    } finally {
      setClosing(true);
      scheduleTimer(finishClose, durationMs);
    }
  });

  useLayoutEffect(() => {
    if (!closing || finishedRef.current) return;
    // 按已播放时间重算剩余退场时长，禁用动效时立即释放遮罩。
    scheduleTimer(finishClose, Math.max(0, durationMs - (performance.now() - startedAtRef.current)));
    return clearTimer;
  }, [closing, durationMs, finishClose, scheduleTimer, clearTimer]);
  const requestClose = useCallback(() => {
    requestCloseWithReason();
  }, [requestCloseWithReason]);

  const resetClosing = useCallback(() => {
    clearTimer();
    closingRef.current = false;
    finishedRef.current = false;
    closeReasonRef.current = undefined;
    setClosing(false);
  }, [clearTimer]);

  return { closing, requestClose, requestCloseWithReason, resetClosing };
}
