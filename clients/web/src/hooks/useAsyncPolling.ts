import { useEffect } from 'preact/hooks';
import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';
import {
  isOperationAbortedError,
  runWithAbortableTimeout,
} from '../utils/timed_abort';
import { useEventCallback } from './useEventCallback';
import { useTimeoutController } from './useTimeoutController';

const MIN_POLL_INTERVAL_MS = 250;
const DEFAULT_TASK_TIMEOUT_MS = 30_000;
const MIN_TASK_TIMEOUT_MS = 1_000;
const MAX_TASK_TIMEOUT_MS = 120_000;

class AsyncPollingTimeoutError extends Error {
  constructor(public readonly timeoutMs: number) {
    super(`Polling task timed out after ${timeoutMs}ms`);
    this.name = 'AsyncPollingTimeoutError';
  }
}

interface AsyncPollingOptions {
  enabled?: boolean;
  immediate?: boolean;
  intervalMs: number;
  taskTimeoutMs?: number;
  onError?: (error: unknown) => void;
}

type AsyncPollingTask = (
  isActive: () => boolean,
  signal: AbortSignal,
) => Promise<void> | void;

function normalizeIntervalMs(value: number): number {
  return normalizeDurationMs(value, {
    fallback: MIN_POLL_INTERVAL_MS,
    min: MIN_POLL_INTERVAL_MS,
    max: MAX_BROWSER_TIMEOUT_MS,
  });
}

function normalizeTaskTimeoutMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: DEFAULT_TASK_TIMEOUT_MS,
    min: MIN_TASK_TIMEOUT_MS,
    max: MAX_TASK_TIMEOUT_MS,
    zeroDisables: true,
  });
}

export function useAsyncPolling(
  task: AsyncPollingTask,
  {
    enabled = true,
    immediate = true,
    intervalMs,
    taskTimeoutMs,
    onError,
  }: AsyncPollingOptions,
): void {
  const runTask = useEventCallback(task);
  const handleError = useEventCallback((error: unknown) => {
    onError?.(error);
  });
  const {
    clearTimer: clearPollTimer,
    scheduleTimer: schedulePollTimer,
  } = useTimeoutController();

  useEffect(() => {
    if (!enabled) return undefined;

    let stopped = false;
    let activeController: AbortController | null = null;
    let activeRunId = 0;
    const delayMs = normalizeIntervalMs(intervalMs);
    const timeoutMs = normalizeTaskTimeoutMs(taskTimeoutMs);

    const schedule = (delay: number) => {
      if (stopped || typeof window === 'undefined') return;
      schedulePollTimer(() => {
        if (stopped) return;
        void run();
      }, delay);
    };

    const run = async () => {
      activeController?.abort();
      const controller = new AbortController();
      activeController = controller;
      const runId = ++activeRunId;
      try {
        await runWithAbortableTimeout(
          (signal) =>
            runTask(
              () =>
                !stopped &&
                activeRunId === runId &&
                !signal.aborted &&
                !controller.signal.aborted,
              signal,
            ),
          {
            timeoutMs,
            signal: controller.signal,
            createTimeoutError: (durationMs) =>
              new AsyncPollingTimeoutError(durationMs),
          },
        );
      } catch (error) {
        if (!stopped && !isOperationAbortedError(error)) handleError(error);
      } finally {
        if (!controller.signal.aborted) {
          controller.abort();
        }
        if (activeController === controller) {
          activeController = null;
        }
        if (!stopped) schedule(delayMs);
      }
    };

    if (typeof window === 'undefined') {
      let immediateController: AbortController | null = null;
      if (immediate) {
        const controller = new AbortController();
        immediateController = controller;
        void runTask(
          () => !stopped && !controller.signal.aborted,
          controller.signal,
        );
      }
      return () => {
        stopped = true;
        immediateController?.abort();
        immediateController = null;
      };
    }

    if (immediate) {
      void run();
    } else {
      schedule(delayMs);
    }

    return () => {
      stopped = true;
      activeController?.abort();
      activeController = null;
      clearPollTimer();
    };
  }, [
    clearPollTimer,
    enabled,
    handleError,
    immediate,
    intervalMs,
    runTask,
    schedulePollTimer,
    taskTimeoutMs,
  ]);
}
