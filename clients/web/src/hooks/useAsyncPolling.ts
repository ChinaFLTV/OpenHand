import { useEffect } from 'preact/hooks';
import { useEventCallback } from './useEventCallback';

const MIN_POLL_INTERVAL_MS = 250;
const DEFAULT_TASK_TIMEOUT_MS = 30_000;
const MIN_TASK_TIMEOUT_MS = 1_000;
const MAX_TASK_TIMEOUT_MS = 120_000;

export class AsyncPollingTimeoutError extends Error {
  constructor(public readonly timeoutMs: number) {
    super(`Polling task timed out after ${timeoutMs}ms`);
    this.name = 'AsyncPollingTimeoutError';
  }
}

export interface AsyncPollingOptions {
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
  if (!Number.isFinite(value)) return MIN_POLL_INTERVAL_MS;
  return Math.max(MIN_POLL_INTERVAL_MS, Math.round(value));
}

function normalizeTaskTimeoutMs(value: number | undefined): number {
  if (value == null) return DEFAULT_TASK_TIMEOUT_MS;
  if (!Number.isFinite(value)) return DEFAULT_TASK_TIMEOUT_MS;
  if (value <= 0) return 0;
  return Math.max(
    MIN_TASK_TIMEOUT_MS,
    Math.min(MAX_TASK_TIMEOUT_MS, Math.round(value)),
  );
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

  useEffect(() => {
    if (!enabled) return undefined;

    let stopped = false;
    let timer: number | null = null;
    let activeController: AbortController | null = null;
    let activeRunId = 0;
    const delayMs = normalizeIntervalMs(intervalMs);
    const timeoutMs = normalizeTaskTimeoutMs(taskTimeoutMs);

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
      activeController?.abort();
      const controller = new AbortController();
      activeController = controller;
      const runId = ++activeRunId;
      const isActive = () =>
        !stopped &&
        activeRunId === runId &&
        !controller.signal.aborted;
      let timeout: number | null = null;
      try {
        const runPromise = Promise.resolve(
          runTask(isActive, controller.signal),
        );
        if (timeoutMs > 0 && typeof window !== 'undefined') {
          await Promise.race([
            runPromise,
            new Promise<never>((_, reject) => {
              timeout = window.setTimeout(() => {
                controller.abort();
                reject(new AsyncPollingTimeoutError(timeoutMs));
              }, timeoutMs);
            }),
          ]);
        } else {
          await runPromise;
        }
      } catch (error) {
        if (!stopped) handleError(error);
      } finally {
        if (timeout != null && typeof window !== 'undefined') {
          window.clearTimeout(timeout);
        }
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
      if (immediate) {
        const controller = new AbortController();
        void runTask(() => !stopped && !controller.signal.aborted, controller.signal);
      }
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
      activeController?.abort();
      activeController = null;
      clearTimer();
    };
  }, [enabled, handleError, immediate, intervalMs, runTask, taskTimeoutMs]);
}
