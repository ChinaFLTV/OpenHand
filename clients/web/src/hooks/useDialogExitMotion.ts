import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';

export function useDialogExitMotion(onClose: () => void, exitMs?: number) {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const timeoutRef = useRef<number | null>(null);

  const requestClose = useCallback(() => {
    if (closing) return;
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
  }, [closing, exitMs, onClose, reduceMotion]);

  useEffect(() => {
    return () => {
      if (timeoutRef.current != null) {
        window.clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return { closing, requestClose };
}