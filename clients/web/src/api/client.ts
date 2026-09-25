// 通用 fetch 封装：自动注入 OpenHand service 要求的设备头与 Bearer token，
// 当前登录状态的鉴权请求返回 401 时清除凭据；旧会话响应按取消处理。
// JSON 请求 / 响应自动序列化；非 2xx 抛 ApiError(status, body)。

import { captureAuthSession, clearAuthStorage, ensureDeviceId, readToken } from '../state/storage';
import {
  JsonStructureLimitError,
  parseJsonBounded,
  type JsonParseBounds,
} from '../shared/util/bounded_json';
import { isAbortError } from '../shared/util/errors';
import { normalizeDurationMs } from '../shared/util/number';
import { clientEnvironmentHeaders } from '../utils/client_env';
import {
  cancelResponseBodyQuietly,
  readResponseBlobBounded,
  readResponseTextBounded,
} from '../utils/bounded_response';
import { runWithAbortableTimeout } from '../utils/timed_abort';

const DEFAULT_API_REQUEST_TIMEOUT_MS = 120_000;
const MIN_API_REQUEST_TIMEOUT_MS = 1_000;
const MAX_API_REQUEST_TIMEOUT_MS = 60 * 60 * 1_000;
const MAX_API_RESPONSE_BYTES = 64 * 1024 * 1024;
const MAX_API_ERROR_RESPONSE_BYTES = 1024 * 1024;
const API_JSON_BOUNDS: JsonParseBounds = {
  maxCharacters: MAX_API_RESPONSE_BYTES,
  maxDepth: 64,
  maxContainerItems: 100_000,
  maxNodes: 1_000_000,
};
const API_ERROR_JSON_BOUNDS: JsonParseBounds = {
  maxCharacters: MAX_API_ERROR_RESPONSE_BYTES,
  maxDepth: 32,
  maxContainerItems: 10_000,
  maxNodes: 50_000,
};
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
  accept?: string;
  /** 单次请求超时毫秒数；非法值回落默认值。 */
  timeoutMs?: number;
  /// 设为 true 时不带 Authorization 头（用于 /api/login 自身调用）
  anonymous?: boolean;
}

export type ApiRequestSignalOptions = Pick<ApiOptions, 'signal' | 'timeoutMs'>;

interface AuthenticatedBlobResult {
  blob: Blob;
  response: Response;
}

interface ApiHeaderOptions {
  anonymous?: boolean;
  accept?: string;
}

export function createApiRequestHeaders({
  anonymous = false,
  accept,
}: ApiHeaderOptions = {}): Record<string, string> {
  const headers: Record<string, string> = {
    'x-openhand-device-id': ensureDeviceId(),
    ...clientEnvironmentHeaders(),
  };
  if (accept) headers.accept = accept;
  if (!anonymous) {
    const token = readToken();
    if (token) headers.authorization = `Bearer ${token}`;
  }
  return headers;
}

type ApiResponseReader<T> = (
  response: Response,
  signal: AbortSignal,
) => Promise<T>;

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
      return parseJsonBounded(text, API_ERROR_JSON_BOUNDS);
    } catch {
      return text;
    }
  } catch (error) {
    if (signal?.aborted || isAbortError(error)) throw error;
    cancelResponseBodyQuietly(response, error);
    return null;
  }
}

function normalizeApiRequestTimeoutMs(value: number | undefined): number {
  return normalizeDurationMs(value == null || value <= 0 ? undefined : value, {
    fallback: DEFAULT_API_REQUEST_TIMEOUT_MS,
    min: MIN_API_REQUEST_TIMEOUT_MS,
    max: MAX_API_REQUEST_TIMEOUT_MS,
  });
}

async function readAuthenticatedApiResponse<T>(
  path: string,
  opts: ApiOptions,
  readResponse: ApiResponseReader<T>,
): Promise<T> {
  const isCurrentSession = captureAuthSession();
  const checkSession = (signal: AbortSignal) => {
    signal.throwIfAborted();
    if (!opts.anonymous && !isCurrentSession()) {
      throw new DOMException('登录状态已变更，忽略旧请求响应。', 'AbortError');
    }
  };
  const headers = createApiRequestHeaders({
    anonymous: opts.anonymous,
    accept: opts.accept,
  });
  let body: string | undefined;
  if (opts.body !== undefined) {
    headers['content-type'] = 'application/json; charset=utf-8';
    body = JSON.stringify(opts.body);
  }

  return runWithAbortableTimeout(async (signal) => {
    let response: Response | undefined;
    try {
      checkSession(signal);
      response = await fetch(path, {
        method: opts.method ?? 'GET',
        headers,
        body,
        credentials: 'same-origin',
        signal,
      });
      checkSession(signal);
      if (!response.ok) {
        const errorBody = await readApiErrorBody(response, signal);
        checkSession(signal);
        if (response.status === 401) {
          if (!opts.anonymous) clearAuthStorage();
          throw new UnauthorizedError(errorBody);
        }
        throw new ApiError(response.status, errorBody);
      }
      const result = await readResponse(response, signal);
      checkSession(signal);
      return result;
    } catch (error) {
      if (response) cancelResponseBodyQuietly(response, error);
      throw error;
    }
  }, {
    timeoutMs: normalizeApiRequestTimeoutMs(opts.timeoutMs),
    signal: opts.signal,
  });
}

export async function apiRequest<T = unknown>(
  path: string,
  opts: ApiOptions = {},
): Promise<T> {
  return readAuthenticatedApiResponse(path, {
    ...opts,
    accept: opts.accept ?? 'application/json, text/plain;q=0.9, */*;q=0.8',
  }, async (response, signal) => {
    const text = await readResponseTextBounded(response, {
      maxBytes: MAX_API_RESPONSE_BYTES,
      signal,
    });
    if (!text) return null as T;
    try {
      return parseJsonBounded(text, API_JSON_BOUNDS) as T;
    } catch (error) {
      if (error instanceof JsonStructureLimitError) throw error;
      return text as T;
    }
  });
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
  return readAuthenticatedApiResponse(path, {
      method: 'GET',
      accept,
      signal,
      timeoutMs,
    }, async (response, requestSignal) => {
    const blob = await readResponseBlobBounded(response, {
      maxBytes,
      signal: requestSignal,
    });
    return { blob, response };
  });
}
