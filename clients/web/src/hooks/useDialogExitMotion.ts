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
  const options =
    typeof optionsOrExitMs === 'object' && optionsOrExitMs != null
      ? optionsOrExitMs
      : undefined;
  const onCloseRef = useRef(onClose);
  const onBeforeCloseRef = useRef<(() => void) | undefined>(options?.onBeforeClose);
  const closingRef = useRef(false);
  const timeoutRef = useRef<number | null>(null);
  const exitMs =
    typeof optionsOrExitMs === 'number' ? optionsOrExitMs : options?.exitMs;
  const closeOnEscape = options?.closeOnEscape !== false;
  const onBeforeClose = options?.onBeforeClose;

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    onBeforeCloseRef.current = onBeforeClose;
  }, [onBeforeClose]);

  const requestClose = useCallback(() => {
    if (closingRef.current) return;
    try {
      onBeforeCloseRef.current?.();
    } catch {
      // Closing should remain best-effort even if caller cleanup fails.
    }
    closingRef.current = true;
    setClosing(true);
    const durationMs = exitMs ?? getDialogExitDurationMs();
    if (reduceMotion || durationMs <= 0 || typeof window === 'undefined') {
      onCloseRef.current();
      return;
    }
    timeoutRef.current = window.setTimeout(() => {
      timeoutRef.current = null;
      onCloseRef.current();
    }, durationMs);
  }, [exitMs, reduceMotion]);

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
    if (!closeOnEscape || typeof window === 'undefined') return undefined;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closeOnEscape, requestClose]);

  return { closing, requestClose, resetClosing };
}
