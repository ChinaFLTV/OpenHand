import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';
import { isAbortError } from '../shared/util/errors';

export interface TimedAbortController {
  controller: AbortController;
  timeoutMs: number;
  abort: () => void;
  dispose: () => void;
  readonly timedOut: boolean;
}

const DEFAULT_ABORT_TIMEOUT_MS = 30_000;
const MIN_ABORT_TIMEOUT_MS = 1;
const MAX_ABORT_TIMEOUT_MS = 60 * 60 * 1000;
const MAX_ABORTABLE_DELAY_MS = Math.min(
  MAX_ABORT_TIMEOUT_MS,
  MAX_BROWSER_TIMEOUT_MS,
);

export class OperationTimeoutError extends Error {
  constructor(public readonly timeoutMs: number) {
    super(`操作在 ${timeoutMs} 毫秒后超时`);
    this.name = 'OperationTimeoutError';
  }
}

class OperationAbortedError extends Error {
  constructor() {
    super('操作已取消');
    this.name = 'OperationAbortedError';
  }
}

interface RunWithTimeoutOptions {
  timeoutMs?: number;
  createTimeoutError?: (timeoutMs: number) => unknown;
}

interface RunWithAbortableTimeoutOptions extends RunWithTimeoutOptions {
  signal?: AbortSignal;
}

function abortController(controller: AbortController, reason?: unknown): void {
  if (controller.signal.aborted) return;
  try {
    controller.abort(reason);
  } catch {
    controller.abort();
  }
}

function normalizeAbortTimeoutMs(value: number | undefined): number {
  return normalizeDurationMs(value == null || value <= 0 ? undefined : value, {
    fallback: DEFAULT_ABORT_TIMEOUT_MS,
    min: MIN_ABORT_TIMEOUT_MS,
    max: MAX_ABORT_TIMEOUT_MS,
  });
}

function normalizeAbortableDelayMs(value: number): number {
  return normalizeDurationMs(value, {
    fallback: 0,
    min: 0,
    max: MAX_ABORTABLE_DELAY_MS,
  });
}

export function createTimedAbortController(
  timeoutMs?: number,
  externalSignal?: AbortSignal,
): TimedAbortController {
  const controller = new AbortController();
  const effectiveTimeoutMs = normalizeAbortTimeoutMs(timeoutMs);
  const timers = typeof window === 'undefined' ? globalThis : window;
  let timer: ReturnType<typeof timers.setTimeout> | null = null;
  let timedOut = false;

  const clearExternalAbortListener = () => {
    externalSignal?.removeEventListener('abort', abortFromExternalSignal);
  };

  const clear = () => {
    if (timer == null) return;
    timers.clearTimeout(timer);
    timer = null;
  };

  const abortWithReason = (reason?: unknown) => {
    clear();
    clearExternalAbortListener();
    abortController(controller, reason);
  };

  const abortFromExternalSignal = () => {
    abortWithReason(abortReasonFromSignal(externalSignal));
  };

  const abort = () => abortWithReason();

  const dispose = () => {
    clear();
    clearExternalAbortListener();
  };

  if (externalSignal?.aborted) {
    abortFromExternalSignal();
  } else {
    externalSignal?.addEventListener('abort', abortFromExternalSignal, {
      once: true,
    });
  }

  if (!controller.signal.aborted) {
    timer = timers.setTimeout(() => {
      timer = null;
      timedOut = true;
      abortWithReason(new OperationTimeoutError(effectiveTimeoutMs));
    }, effectiveTimeoutMs);
  }

  return {
    controller,
    timeoutMs: effectiveTimeoutMs,
    abort,
    dispose,
    get timedOut() {
      return timedOut;
    },
  };
}

export function isOperationAbortedError(
  error: unknown,
): error is OperationAbortedError {
  return error instanceof OperationAbortedError || isAbortError(error);
}

function abortReasonFromSignal(signal?: AbortSignal): unknown {
  return signal?.reason ?? new OperationAbortedError();
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

  const timers = typeof window === 'undefined' ? globalThis : window;
  let timer: ReturnType<typeof timers.setTimeout> | null = null;
  try {
    return await Promise.race([
      Promise.resolve(runOperation()),
      new Promise<never>((_, reject) => {
        timer = timers.setTimeout(() => {
          timer = null;
          try {
            reject(
              createTimeoutError?.(effectiveTimeoutMs) ??
                new OperationTimeoutError(effectiveTimeoutMs),
            );
          } catch (error) {
            reject(error);
          }
        }, effectiveTimeoutMs);
      }),
    ]);
  } finally {
    if (timer != null) {
      timers.clearTimeout(timer);
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
  const abort = (reason?: unknown) => abortController(controller, reason);
  if (signal?.aborted) {
    const reason = abortReasonFromSignal(signal);
    abort(reason);
    throw reason;
  }

  let abortReject: ((reason: unknown) => void) | null = null;
  const abortPromise = new Promise<never>((_, reject) => {
    abortReject = reject;
  });
  const abortAndReject = () => {
    const reason = abortReasonFromSignal(signal);
    abort(reason);
    abortReject?.(reason);
  };
  signal?.addEventListener('abort', abortAndReject, { once: true });

  try {
    return await runWithTimeout(
      () => Promise.race([
        Promise.resolve().then(() => {
          if (controller.signal.aborted) throw abortReasonFromSignal(controller.signal);
          return task(controller.signal);
        }),
        abortPromise,
      ]),
      {
        timeoutMs,
        createTimeoutError: (effectiveTimeoutMs) => {
          let reason: unknown;
          try {
            reason = createTimeoutError?.(effectiveTimeoutMs) ??
              new OperationTimeoutError(effectiveTimeoutMs);
          } catch (error) {
            reason = error;
          }
          abort(reason);
          return reason;
        },
      },
    );
  } finally {
    signal?.removeEventListener('abort', abortAndReject);
    abortReject = null;
    abort(new OperationAbortedError());
  }
}

export function waitForDelayOrAbort(
  delayMs: number,
  signal: AbortSignal,
): Promise<void> {
  const safeDelayMs = normalizeAbortableDelayMs(delayMs);
  if (safeDelayMs <= 0 || signal.aborted) {
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    const timers = typeof window === 'undefined' ? globalThis : window;
    let timer: ReturnType<typeof timers.setTimeout> | null = null;
    const finish = () => {
      if (timer != null) {
        timers.clearTimeout(timer);
        timer = null;
      }
      signal.removeEventListener('abort', finish);
      resolve();
    };
    timer = timers.setTimeout(finish, safeDelayMs);
    signal.addEventListener('abort', finish, { once: true });
  });
}
