import { useEffect, useState } from 'preact/hooks';
import { normalizeDurationMs } from '../shared/util/number';
import { useTimeoutController } from './useTimeoutController';

const MAX_DELAYED_FALSE_MS = 5 * 60 * 1000;

// True edges apply immediately; false edges wait for [delayMs].
// Useful for smoothing short idle gaps without duplicating timer cleanup code.
export function useDelayedFalse(value: boolean, delayMs: number): boolean {
  const [stableValue, setStableValue] = useState(value);
  const { clearTimer, scheduleTimer } = useTimeoutController();

  useEffect(() => {
    clearTimer();
    if (value) {
      setStableValue(true);
      return;
    }
    const safeDelayMs = normalizeDurationMs(delayMs, {
      fallback: 0,
      min: 0,
      max: MAX_DELAYED_FALSE_MS,
    });
    scheduleTimer(() => setStableValue(false), safeDelayMs);
  }, [clearTimer, delayMs, scheduleTimer, value]);

  return stableValue;
}
