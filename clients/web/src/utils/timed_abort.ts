import { normalizeDurationMs } from '../shared/util/number';

export interface TimedAbortController {
  controller: AbortController;
  timeoutMs: number;
  clear: () => void;
  abort: () => void;
  dispose: () => void;
  readonly timedOut: boolean;
}

const DEFAULT_ABORT_TIMEOUT_MS = 30_000;
const MAX_ABORT_TIMEOUT_MS = 60 * 60 * 1000;

export class OperationTimeoutError extends Error {
  constructor(public readonly timeoutMs: number) {
    super(`Operation timed out after ${timeoutMs}ms`);
    this.name = 'OperationTimeoutError';
  }
}

export interface RunWithTimeoutOptions {
  timeoutMs?: number;
  createTimeoutError?: (timeoutMs: number) => unknown;
}

export interface RunWithAbortableTimeoutOptions extends RunWithTimeoutOptions {
  signal?: AbortSignal;
}

function normalizeAbortTimeoutMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: DEFAULT_ABORT_TIMEOUT_MS,
    max: MAX_ABORT_TIMEOUT_MS,
  });
}

export function createTimedAbortController(
  timeoutMs?: number,
  externalSignal?: AbortSignal,
): TimedAbortController {
  const controller = new AbortController();
  const effectiveTimeoutMs = normalizeAbortTimeoutMs(timeoutMs);
  let timer: number | null = null;
  let timedOut = false;

  const clearExternalAbortListener = () => {
    externalSignal?.removeEventListener('abort', abort);
  };

  const clear = () => {
    if (timer == null || typeof window === 'undefined') return;
    window.clearTimeout(timer);
    timer = null;
  };

  const abort = () => {
    clear();
    clearExternalAbortListener();
    if (!controller.signal.aborted) controller.abort();
  };

  const dispose = () => {
    clear();
    clearExternalAbortListener();
  };

  if (externalSignal?.aborted) {
    abort();
  } else {
    externalSignal?.addEventListener('abort', abort, { once: true });
  }

  if (
    effectiveTimeoutMs > 0 &&
    typeof window !== 'undefined' &&
    !controller.signal.aborted
  ) {
    timer = window.setTimeout(() => {
      timer = null;
      timedOut = true;
      abort();
    }, effectiveTimeoutMs);
  }

  return {
    controller,
    timeoutMs: effectiveTimeoutMs,
    clear,
    abort,
    dispose,
    get timedOut() {
      return timedOut;
    },
  };
}

export function isOperationTimeoutError(
  error: unknown,
): error is OperationTimeoutError {
  return error instanceof OperationTimeoutError;
}

export async function runWithTimeout<T>(
  operation: PromiseLike<T> | (() => PromiseLike<T> | T),
  { timeoutMs, createTimeoutError }: RunWithTimeoutOptions = {},
): Promise<T> {
  const effectiveTimeoutMs = normalizeAbortTimeoutMs(timeoutMs);
  const runOperation = () =>
    typeof operation === 'function'
      ? (operation as () => PromiseLike<T> | T)()
      : operation;
  if (effectiveTimeoutMs <= 0 || typeof window === 'undefined') {
    return Promise.resolve(runOperation());
  }

  let timer: number | null = null;
  try {
    return await Promise.race([
      Promise.resolve(runOperation()),
      new Promise<never>((_, reject) => {
        timer = window.setTimeout(() => {
          timer = null;
          reject(
            createTimeoutError?.(effectiveTimeoutMs) ??
              new OperationTimeoutError(effectiveTimeoutMs),
          );
        }, effectiveTimeoutMs);
      }),
    ]);
  } finally {
    if (timer != null) {
      window.clearTimeout(timer);
    }
  }
}

export async function runWithAbortableTimeout<T>(
  task: (signal: AbortSignal) => PromiseLike<T> | T,
  {
    timeoutMs,
    signal,
    createTimeoutError,
  }: RunWithAbortableTimeoutOptions = {},
): Promise<T> {
  const controller = new AbortController();
  const abort = () => {
    if (!controller.signal.aborted) controller.abort();
  };

  if (signal?.aborted) {
    abort();
  } else {
    signal?.addEventListener('abort', abort, { once: true });
  }

  try {
    return await runWithTimeout(() => task(controller.signal), {
      timeoutMs,
      createTimeoutError: (effectiveTimeoutMs) => {
        abort();
        return (
          createTimeoutError?.(effectiveTimeoutMs) ??
          new OperationTimeoutError(effectiveTimeoutMs)
        );
      },
    });
  } finally {
    signal?.removeEventListener('abort', abort);
    abort();
  }
}
