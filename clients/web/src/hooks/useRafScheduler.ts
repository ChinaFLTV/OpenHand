import { useCallback, useEffect, useRef } from 'preact/hooks';

interface RafScheduler {
  schedule: () => void;
  flush: () => void;
  cancel: () => void;
}

export function useRafScheduler(callback: () => void): RafScheduler {
  const callbackRef = useRef(callback);
  const frameRef = useRef<number | null>(null);
  callbackRef.current = callback;

  const cancel = useCallback(() => {
    if (frameRef.current == null || typeof window === 'undefined') return;
    window.cancelAnimationFrame(frameRef.current);
    frameRef.current = null;
  }, []);

  const flush = useCallback(() => {
    cancel();
    callbackRef.current();
  }, [cancel]);

  const schedule = useCallback(() => {
    if (typeof window === 'undefined') {
      callbackRef.current();
      return;
    }
    if (frameRef.current != null) return;
    frameRef.current = window.requestAnimationFrame(() => {
      frameRef.current = null;
      callbackRef.current();
    });
  }, []);

  useEffect(() => cancel, [cancel]);

  return { schedule, flush, cancel };
}
