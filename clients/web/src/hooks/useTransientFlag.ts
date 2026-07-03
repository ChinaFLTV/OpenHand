import { useCallback, useState } from 'preact/hooks';
import { useTimeoutController } from './useTimeoutController';

export const DEFAULT_TRANSIENT_FEEDBACK_RESET_MS = 1600;

export interface TransientFlagController {
  active: boolean;
  trigger: () => void;
  reset: () => void;
}

export function useTransientFlag(
  resetDelayMs: number = DEFAULT_TRANSIENT_FEEDBACK_RESET_MS,
): TransientFlagController {
  const [active, setActive] = useState(false);
  const { clearTimer, scheduleTimer } = useTimeoutController();

  const reset = useCallback(() => {
    clearTimer();
    setActive(false);
  }, [clearTimer]);

  const trigger = useCallback(() => {
    setActive(true);
    scheduleTimer(() => setActive(false), resetDelayMs);
  }, [resetDelayMs, scheduleTimer]);

  return { active, trigger, reset };
}
