import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';

const DEFAULT_BLOB_READ_TIMEOUT_MS = 30_000;

interface BlobDataUrlReadOptions {
  timeoutMs?: number;
  failureMessage: string;
  timeoutMessage: string;
}

export function base64PayloadFromDataUrl(dataUrl: string): string | null {
  const marker = 'base64,';
  const markerIndex = dataUrl.indexOf(marker);
  if (markerIndex < 0) return null;
  const payload = dataUrl.slice(markerIndex + marker.length);
  return payload.length > 0 ? payload : null;
}

export function readBlobAsDataUrl(
  blob: Blob,
  {
    timeoutMs,
    failureMessage,
    timeoutMessage,
  }: BlobDataUrlReadOptions,
): Promise<string> {
  if (typeof FileReader === 'undefined' || typeof window === 'undefined') {
    return Promise.reject(new Error(failureMessage));
  }
  const effectiveTimeoutMs = normalizeDurationMs(timeoutMs, {
    fallback: DEFAULT_BLOB_READ_TIMEOUT_MS,
    min: 1,
    max: MAX_BROWSER_TIMEOUT_MS,
  });
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    let settled = false;
    let timer: number | null = null;

    const cleanup = () => {
      if (timer != null) {
        window.clearTimeout(timer);
        timer = null;
      }
      reader.onload = null;
      reader.onerror = null;
      reader.onabort = null;
    };
    const fail = (error: Error, abort = false) => {
      if (settled) return;
      settled = true;
      cleanup();
      if (abort && reader.readyState === FileReader.LOADING) {
        try {
          reader.abort();
        } catch {
          // 读取已结束，无需处理。
        }
      }
      reject(error);
    };

    reader.onload = () => {
      const result = reader.result;
      if (typeof result !== 'string') {
        fail(new Error(failureMessage));
        return;
      }
      settled = true;
      cleanup();
      resolve(result);
    };
    reader.onerror = () => fail(reader.error ?? new Error(failureMessage));
    reader.onabort = () => fail(new Error(timeoutMessage));
    timer = window.setTimeout(
      () => fail(new Error(timeoutMessage), true),
      effectiveTimeoutMs,
    );
    try {
      reader.readAsDataURL(blob);
    } catch (error: unknown) {
      fail(error instanceof Error ? error : new Error(failureMessage));
    }
  });
}
