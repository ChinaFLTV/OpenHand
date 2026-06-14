import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';

export interface DialogExitMotionOptions {
  exitMs?: number;
  closeOnEscape?: boolean;
  onBeforeClose?: (reason?: string) => void;
}

export interface DialogExitMotionController<Reason extends string = string> {
  closing: boolean;
  requestClose: () => void;
  requestCloseWithReason: (reason?: Reason) => void;
  resetClosing: () => void;
}

function normalizeExitDurationMs(value: number | undefined): number {
  if (value == null) return getDialogExitDurationMs();
  if (!Number.isFinite(value)) return getDialogExitDurationMs();
  return Math.max(0, Math.round(value));
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
  const onCloseRef = useRef(onClose);
  const onBeforeCloseRef = useRef<((reason?: Reason) => void) | undefined>(
    options?.onBeforeClose as ((reason?: Reason) => void) | undefined,
  );
  const closingRef = useRef(false);
  const timeoutRef = useRef<number | null>(null);
  const closeReasonRef = useRef<Reason | undefined>(undefined);
  const exitMs =
    typeof optionsOrExitMs === 'number' ? optionsOrExitMs : options?.exitMs;
  const closeOnEscape = options?.closeOnEscape !== false;
  const onBeforeClose = options?.onBeforeClose as
    | ((reason?: Reason) => void)
    | undefined;

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    onBeforeCloseRef.current = onBeforeClose;
  }, [onBeforeClose]);

  const finishClose = useCallback(() => {
    const reason = closeReasonRef.current;
    closeReasonRef.current = undefined;
    onCloseRef.current(reason);
  }, []);

  const clearCloseTimer = useCallback(() => {
    if (timeoutRef.current == null) return;
    if (typeof window !== 'undefined') {
      window.clearTimeout(timeoutRef.current);
    }
    timeoutRef.current = null;
  }, []);

  const requestCloseWithReason = useCallback((reason?: Reason) => {
    if (closingRef.current) return;
    closeReasonRef.current = reason;
    try {
      onBeforeCloseRef.current?.(reason);
    } catch {
      // Closing should remain best-effort even if caller cleanup fails.
    }
    closingRef.current = true;
    setClosing(true);
    const durationMs = normalizeExitDurationMs(exitMs);
    if (reduceMotion || durationMs <= 0 || typeof window === 'undefined') {
      finishClose();
      return;
    }
    timeoutRef.current = window.setTimeout(() => {
      timeoutRef.current = null;
      finishClose();
    }, durationMs);
  }, [exitMs, finishClose, reduceMotion]);

  const requestClose = useCallback(() => {
    requestCloseWithReason();
  }, [requestCloseWithReason]);

  const resetClosing = useCallback(() => {
    clearCloseTimer();
    closingRef.current = false;
    closeReasonRef.current = undefined;
    setClosing(false);
  }, [clearCloseTimer]);

  useEffect(() => {
    return () => {
      clearCloseTimer();
    };
  }, [clearCloseTimer]);

  useEffect(() => {
    if (!closeOnEscape || typeof window === 'undefined') return undefined;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        requestCloseWithReason('escape' as Reason);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closeOnEscape, requestCloseWithReason]);

  return { closing, requestClose, requestCloseWithReason, resetClosing };
}
