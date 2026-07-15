// 通用 fetch 封装：自动注入 OpenHand service 要求的设备头与 Bearer token，
// 401 时清空本地认证态并 throw `UnauthorizedError`，调用方按需跳 /login。
// JSON 请求 / 响应自动序列化；非 2xx 抛 ApiError(status, body)。

import { clearAuthStorage, ensureDeviceId, readToken } from '../state/storage';
import { isAbortError } from '../shared/util/errors';
import { normalizeDurationMs } from '../shared/util/number';
import { clientEnvironmentHeaders } from '../utils/client_env';
import {
  createTimedAbortController,
  OperationTimeoutError,
  type TimedAbortController,
} from '../utils/timed_abort';

const DEFAULT_API_REQUEST_TIMEOUT_MS = 120_000;
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

export interface ApiOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: unknown;
  signal?: AbortSignal;
  /** Per-request timeout in milliseconds. Set 0 to disable timeout. */
  timeoutMs?: number;
  /// 设为 true 时不带 Authorization 头（用于 /api/login 自身调用）
  anonymous?: boolean;
}

export type ApiRequestSignalOptions = Pick<ApiOptions, 'signal' | 'timeoutMs'>;

export async function throwIfApiResponseFailed(response: Response): Promise<void> {
  if (response.status === 401) {
    clearAuthStorage();
    throw new UnauthorizedError(null);
  }
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new ApiError(response.status, text || null);
  }
}

interface ApiAbortSignal {
  signal?: AbortSignal;
  timed?: TimedAbortController;
  cleanup: () => void;
}

function normalizeApiRequestTimeoutMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: DEFAULT_API_REQUEST_TIMEOUT_MS,
    zeroDisables: true,
  });
}

function createApiAbortSignal(opts: ApiOptions): ApiAbortSignal {
  const timeoutMs = normalizeApiRequestTimeoutMs(opts.timeoutMs);
  if (timeoutMs <= 0) {
    return { signal: opts.signal, cleanup: () => {} };
  }
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
    let res: Response;
    try {
      res = await fetch(path, {
        method: opts.method ?? 'GET',
        headers,
        body,
        signal: abortSignal.signal,
      });
    } catch (error) {
      throw timeoutErrorFromAbortSignal(abortSignal, error) ?? error;
    }

    let parsed: unknown = null;
    const text = await res.text();
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = text;
      }
    }

    if (res.status === 401) {
      clearAuthStorage();
      throw new UnauthorizedError(parsed);
    }
    if (!res.ok) {
      throw new ApiError(res.status, parsed);
    }
    return parsed as T;
  } finally {
    abortSignal.cleanup();
  }
}
