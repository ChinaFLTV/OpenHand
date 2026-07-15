import { useCallback, useEffect, useRef } from 'preact/hooks';
import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';

interface TimeoutController {
  clearTimer: () => void;
  scheduleTimer: (callback: () => void, delayMs?: number | null) => void;
}

export function useTimeoutController(): TimeoutController {
  const timerRef = useRef<number | null>(null);
  const tokenRef = useRef(0);

  const clearTimer = useCallback(() => {
    tokenRef.current += 1;
    if (timerRef.current == null) return;
    if (typeof window !== 'undefined') {
      window.clearTimeout(timerRef.current);
    }
    timerRef.current = null;
  }, []);

  const scheduleTimer = useCallback(
    (callback: () => void, delayMs?: number | null) => {
      clearTimer();
      const safeDelayMs = normalizeDurationMs(delayMs, {
        fallback: 0,
        min: 0,
        max: MAX_BROWSER_TIMEOUT_MS,
      });
      if (safeDelayMs <= 0 || typeof window === 'undefined') {
        callback();
        return;
      }

      const token = tokenRef.current;
      timerRef.current = window.setTimeout(() => {
        if (token !== tokenRef.current) return;
        timerRef.current = null;
        callback();
      }, safeDelayMs);
    },
    [clearTimer],
  );

  useEffect(() => () => clearTimer(), [clearTimer]);

  return { clearTimer, scheduleTimer };
}
