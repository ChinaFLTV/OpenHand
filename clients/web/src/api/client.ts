// 通用 fetch 封装：自动注入 OpenHand service 要求的设备头与 Bearer token，
// 401 时清空本地认证态并 throw `UnauthorizedError`，调用方按需跳 /login。
// JSON 请求 / 响应自动序列化；非 2xx 抛 ApiError(status, body)。

import { clearAuthStorage, ensureDeviceId, readToken } from '../state/storage';
import { isAbortError } from '../shared/util/errors';
import { normalizeDurationMs } from '../shared/util/number';
import { clientEnvironmentHeaders } from '../utils/client_env';
import {
  cancelResponseBodyQuietly,
  readResponseBlobBounded,
  readResponseTextBounded,
} from '../utils/bounded_response';
import {
  createTimedAbortController,
  OperationTimeoutError,
  type TimedAbortController,
} from '../utils/timed_abort';

const DEFAULT_API_REQUEST_TIMEOUT_MS = 120_000;
const MIN_API_REQUEST_TIMEOUT_MS = 1_000;
const MAX_API_REQUEST_TIMEOUT_MS = 60 * 60 * 1_000;
const MAX_API_RESPONSE_BYTES = 64 * 1024 * 1024;
const MAX_API_ERROR_RESPONSE_BYTES = 1024 * 1024;
export const LONG_API_REQUEST_TIMEOUT_MS = 300_000;

export class ApiError extends Error {
  constructor(public readonly status: number, public readonly body: unknown) {
    super(`API ${status}`);
  }
}

export class UnauthorizedError extends ApiError {
  constructor(body: unknown) {
    super(401, body);
  }
}

interface ApiOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: unknown;
  signal?: AbortSignal;
  /** 单次请求超时毫秒数；非法值回落默认值。 */
  timeoutMs?: number;
  /// 设为 true 时不带 Authorization 头（用于 /api/login 自身调用）
  anonymous?: boolean;
}

export type ApiRequestSignalOptions = Pick<ApiOptions, 'signal' | 'timeoutMs'>;

export interface AuthenticatedBlobResult {
  blob: Blob;
  response: Response;
}

export async function throwIfApiResponseFailed(
  response: Response,
  signal?: AbortSignal,
): Promise<void> {
  if (response.status === 401) {
    clearAuthStorage();
    throw new UnauthorizedError(await readApiErrorBody(response, signal));
  }
  if (!response.ok) {
    throw new ApiError(
      response.status,
      await readApiErrorBody(response, signal),
    );
  }
}

async function readApiErrorBody(
  response: Response,
  signal?: AbortSignal,
): Promise<unknown> {
  try {
    const text = await readResponseTextBounded(response, {
      maxBytes: MAX_API_ERROR_RESPONSE_BYTES,
      signal,
    });
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  } catch (error) {
    if (signal?.aborted || isAbortError(error)) throw error;
    cancelResponseBodyQuietly(response, error);
    return null;
  }
}

interface ApiAbortSignal {
  signal?: AbortSignal;
  timed?: TimedAbortController;
  cleanup: () => void;
}

function normalizeApiRequestTimeoutMs(value: number | undefined): number {
  return normalizeDurationMs(value == null || value <= 0 ? undefined : value, {
    fallback: DEFAULT_API_REQUEST_TIMEOUT_MS,
    min: MIN_API_REQUEST_TIMEOUT_MS,
    max: MAX_API_REQUEST_TIMEOUT_MS,
  });
}

function createApiAbortSignal(opts: ApiOptions): ApiAbortSignal {
  const timeoutMs = normalizeApiRequestTimeoutMs(opts.timeoutMs);
  const timed = createTimedAbortController(timeoutMs, opts.signal);
  return {
    signal: timed.controller.signal,
    timed,
    cleanup: timed.dispose,
  };
}

function timeoutErrorFromAbortSignal(
  abortSignal: ApiAbortSignal,
  error: unknown,
): OperationTimeoutError | null {
  if (!isAbortError(error)) return null;
  const reason = abortSignal.signal?.reason;
  if (reason instanceof OperationTimeoutError) return reason;
  if (abortSignal.timed?.timedOut) {
    return new OperationTimeoutError(abortSignal.timed.timeoutMs);
  }
  return null;
}

export async function apiRequest<T = unknown>(
  path: string,
  opts: ApiOptions = {},
): Promise<T> {
  const headers: Record<string, string> = {
    'x-openhand-device-id': ensureDeviceId(),
    ...clientEnvironmentHeaders(),
  };

  if (!opts.anonymous) {
    const token = readToken();
    if (token) headers['authorization'] = `Bearer ${token}`;
  }

  let body: BodyInit | undefined;
  if (opts.body !== undefined) {
    headers['content-type'] = 'application/json; charset=utf-8';
    body = JSON.stringify(opts.body);
  }

  const abortSignal = createApiAbortSignal(opts);
  try {
    const res = await fetch(path, {
      method: opts.method ?? 'GET',
      headers,
      body,
      signal: abortSignal.signal,
    });

    if (res.status === 401) {
      clearAuthStorage();
      throw new UnauthorizedError(
        await readApiErrorBody(res, abortSignal.signal),
      );
    }
    if (!res.ok) {
      throw new ApiError(
        res.status,
        await readApiErrorBody(res, abortSignal.signal),
      );
    }
    const text = await readResponseTextBounded(res, {
      maxBytes: MAX_API_RESPONSE_BYTES,
      signal: abortSignal.signal,
    });
    if (!text) return null as T;
    try {
      return JSON.parse(text) as T;
    } catch {
      return text as T;
    }
  } catch (error) {
    throw timeoutErrorFromAbortSignal(abortSignal, error) ?? error;
  } finally {
    abortSignal.cleanup();
  }
}

/** 使用统一鉴权头下载受大小和总时限约束的二进制响应。 */
export async function fetchAuthenticatedBlob(
  path: string,
  {
    accept,
    maxBytes,
    signal,
    timeoutMs,
  }: {
    accept?: string;
    maxBytes: number;
    signal?: AbortSignal;
    timeoutMs?: number;
  },
): Promise<AuthenticatedBlobResult> {
  const headers: Record<string, string> = {
    'x-openhand-device-id': ensureDeviceId(),
    ...clientEnvironmentHeaders(),
  };
  if (accept) headers.accept = accept;
  const token = readToken();
  if (token) headers.authorization = `Bearer ${token}`;

  const abortSignal = createApiAbortSignal({ signal, timeoutMs });
  try {
    const response = await fetch(path, {
      method: 'GET',
      headers,
      credentials: 'same-origin',
      signal: abortSignal.signal,
    });
    await throwIfApiResponseFailed(response, abortSignal.signal);
    const blob = await readResponseBlobBounded(response, {
      maxBytes,
      signal: abortSignal.signal,
    });
    return { blob, response };
  } catch (error) {
    throw timeoutErrorFromAbortSignal(abortSignal, error) ?? error;
  } finally {
    abortSignal.cleanup();
  }
}
