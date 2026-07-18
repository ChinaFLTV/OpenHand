import { useEffect, useState } from 'preact/hooks';
import { normalizeDurationMs } from '../shared/util/number';
import { useTimeoutController } from './useTimeoutController';

const MAX_DELAYED_FALSE_MS = 5 * 60 * 1000;

// true 立即生效，false 延迟 [delayMs]，用于平滑短暂空闲且统一定时器清理。
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
