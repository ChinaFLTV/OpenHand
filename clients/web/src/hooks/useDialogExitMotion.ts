import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';

export interface DialogExitMotionOptions {
  exitMs?: number;
  closeOnEscape?: boolean;
  onBeforeClose?: () => void;
}

export function useDialogExitMotion(
  onClose: () => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
) {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const closingRef = useRef(false);
  const timeoutRef = useRef<number | null>(null);
  const exitMs =
    typeof optionsOrExitMs === 'number'
      ? optionsOrExitMs
      : optionsOrExitMs?.exitMs;
  const closeOnEscape =
    typeof optionsOrExitMs === 'object'
      ? optionsOrExitMs.closeOnEscape !== false
      : true;
  const onBeforeClose =
    typeof optionsOrExitMs === 'object' ? optionsOrExitMs.onBeforeClose : undefined;

  const requestClose = useCallback(() => {
    if (closingRef.current) return;
    try {
      onBeforeClose?.();
    } catch {
      // Closing should remain best-effort even if caller cleanup fails.
    }
    closingRef.current = true;
    setClosing(true);
    const durationMs = exitMs ?? getDialogExitDurationMs();
    if (reduceMotion || durationMs <= 0 || typeof window === 'undefined') {
      onClose();
      return;
    }
    timeoutRef.current = window.setTimeout(() => {
      timeoutRef.current = null;
      onClose();
    }, durationMs);
  }, [exitMs, onBeforeClose, onClose, reduceMotion]);

  const resetClosing = useCallback(() => {
    if (timeoutRef.current != null) {
      if (typeof window !== 'undefined') {
        window.clearTimeout(timeoutRef.current);
      }
      timeoutRef.current = null;
    }
    closingRef.current = false;
    setClosing(false);
  }, []);

  useEffect(() => {
    return () => {
      if (timeoutRef.current != null) {
        window.clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!closeOnEscape) return undefined;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closeOnEscape, requestClose]);

  return { closing, requestClose, resetClosing };
}
