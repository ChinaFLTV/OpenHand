import { useEffect } from 'preact/hooks';
import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';
import { useEventCallback } from './useEventCallback';

const MIN_UI_INTERVAL_MS = 16;

interface IntervalOptions {
  enabled?: boolean;
}

export function useInterval(
  callback: () => void,
  intervalMs: number,
  { enabled = true }: IntervalOptions = {},
): void {
  const run = useEventCallback(callback);

  useEffect(() => {
    if (!enabled || typeof window === 'undefined') return undefined;
    const safeIntervalMs = normalizeDurationMs(intervalMs, {
      fallback: MIN_UI_INTERVAL_MS,
      min: MIN_UI_INTERVAL_MS,
      max: MAX_BROWSER_TIMEOUT_MS,
    });
    const timer = window.setInterval(run, safeIntervalMs);
    return () => window.clearInterval(timer);
  }, [enabled, intervalMs, run]);
}
