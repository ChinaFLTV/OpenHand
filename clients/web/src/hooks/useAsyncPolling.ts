import { useEffect, useRef } from 'preact/hooks';
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
    super(`轮询任务在 ${timeoutMs} 毫秒后超时`);
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

  // 跨配置变更保留运行门闩；忽略取消的旧任务结束前不能启动新任务。
  const taskRunningRef = useRef(false);
  const resumePollingRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    if (!enabled) return undefined;

    let stopped = false;
    let immediatePending = immediate;
    let activeController: AbortController | null = null;
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
      if (stopped || taskRunningRef.current) return;
      taskRunningRef.current = true;
      immediatePending = false;
      const controller = new AbortController();
      activeController = controller;
      let taskSettled = true;
      let timeoutSettled = false;
      const release = () => {
        if (!taskSettled || !timeoutSettled) return;
        taskRunningRef.current = false;
        resumePollingRef.current?.();
      };
      try {
        await runWithAbortableTimeout(
          (signal) => {
            taskSettled = false;
            return Promise.resolve().then(() => {
              if (stopped || signal.aborted) return;
              return runTask(() => !stopped && !signal.aborted, signal);
            }).finally(() => {
              taskSettled = true;
              release();
            });
          },
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
        controller.abort();
        if (activeController === controller) activeController = null;
        timeoutSettled = true;
        release();
      }
    };

    resumePollingRef.current = () => schedule(immediatePending ? 0 : delayMs);
    if (immediate) {
      void run();
    } else {
      schedule(delayMs);
    }

    return () => {
      stopped = true;
      resumePollingRef.current = null;
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
