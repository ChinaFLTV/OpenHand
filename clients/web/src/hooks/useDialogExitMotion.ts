import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { useReducedMotion } from './useReducedMotion';

const DEFAULT_EXIT_MS = 180;

export function useDialogExitMotion(onClose: () => void, exitMs = DEFAULT_EXIT_MS) {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const timeoutRef = useRef<number | null>(null);

  const requestClose = useCallback(() => {
    if (closing) return;
    setClosing(true);
    if (reduceMotion || typeof window === 'undefined') {
      onClose();
      return;
    }
    timeoutRef.current = window.setTimeout(() => {
      timeoutRef.current = null;
      onClose();
    }, exitMs);
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