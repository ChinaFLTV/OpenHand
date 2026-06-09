import { useEffect } from 'preact/hooks';
import { useEventCallback } from './useEventCallback';

const MIN_POLL_INTERVAL_MS = 250;

export interface AsyncPollingOptions {
  enabled?: boolean;
  immediate?: boolean;
  intervalMs: number;
  onError?: (error: unknown) => void;
}

type AsyncPollingTask = (isActive: () => boolean) => Promise<void> | void;

function normalizeIntervalMs(value: number): number {
  if (!Number.isFinite(value)) return MIN_POLL_INTERVAL_MS;
  return Math.max(MIN_POLL_INTERVAL_MS, Math.round(value));
}

export function useAsyncPolling(
  task: AsyncPollingTask,
  {
    enabled = true,
    immediate = true,
    intervalMs,
    onError,
  }: AsyncPollingOptions,
): void {
  const runTask = useEventCallback(task);
  const handleError = useEventCallback((error: unknown) => {
    onError?.(error);
  });

  useEffect(() => {
    if (!enabled) return undefined;

    let stopped = false;
    let timer: number | null = null;
    const delayMs = normalizeIntervalMs(intervalMs);
    const isActive = () => !stopped;

    const clearTimer = () => {
      if (timer == null || typeof window === 'undefined') return;
      window.clearTimeout(timer);
      timer = null;
    };

    const schedule = (delay: number) => {
      if (stopped || typeof window === 'undefined') return;
      clearTimer();
      timer = window.setTimeout(() => {
        timer = null;
        void run();
      }, delay);
    };

    const run = async () => {
      try {
        await runTask(isActive);
      } catch (error) {
        if (!stopped) handleError(error);
      } finally {
        if (!stopped) schedule(delayMs);
      }
    };

    if (typeof window === 'undefined') {
      if (immediate) void runTask(isActive);
      return () => {
        stopped = true;
      };
    }

    if (immediate) {
      void run();
    } else {
      schedule(delayMs);
    }

    return () => {
      stopped = true;
      clearTimer();
    };
  }, [enabled, handleError, immediate, intervalMs, runTask]);
}
