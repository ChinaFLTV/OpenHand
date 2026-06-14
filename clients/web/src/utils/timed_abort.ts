export interface TimedAbortController {
  controller: AbortController;
  timeoutMs: number;
  clear: () => void;
  abort: () => void;
}

const DEFAULT_ABORT_TIMEOUT_MS = 30_000;

function normalizeAbortTimeoutMs(value: number | undefined): number {
  if (value == null || !Number.isFinite(value)) {
    return DEFAULT_ABORT_TIMEOUT_MS;
  }
  return Math.max(0, Math.round(value));
}

export function createTimedAbortController(
  timeoutMs?: number,
): TimedAbortController {
  const controller = new AbortController();
  const effectiveTimeoutMs = normalizeAbortTimeoutMs(timeoutMs);
  let timer: number | null = null;

  const clear = () => {
    if (timer == null || typeof window === 'undefined') return;
    window.clearTimeout(timer);
    timer = null;
  };

  const abort = () => {
    clear();
    controller.abort();
  };

  if (effectiveTimeoutMs > 0 && typeof window !== 'undefined') {
    timer = window.setTimeout(() => {
      timer = null;
      controller.abort();
    }, effectiveTimeoutMs);
  }

  return {
    controller,
    timeoutMs: effectiveTimeoutMs,
    clear,
    abort,
  };
}
