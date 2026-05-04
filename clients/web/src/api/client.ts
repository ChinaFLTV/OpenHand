// 通用 fetch 封装：自动注入 OpenHand service 要求的设备头与 Bearer token，
// 401 时清空本地认证态并 throw `UnauthorizedError`，调用方按需跳 /login。
// JSON 请求 / 响应自动序列化；非 2xx 抛 ApiError(status, body)。

import { clearAuthStorage, ensureDeviceId, readToken } from '../state/storage';

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
  /// 设为 true 时不带 Authorization 头（用于 /api/login 自身调用）
  anonymous?: boolean;
}

export async function apiRequest<T = unknown>(
  path: string,
  opts: ApiOptions = {},
): Promise<T> {
  const headers: Record<string, string> = {
    'x-openhand-device-id': ensureDeviceId(),
    'x-openhand-source': 'WEB_PC',
    'x-openhand-device-name': 'OpenHand Web',
    'x-openhand-device-platform': navigator.platform || 'web',
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

  const res = await fetch(path, {
    method: opts.method ?? 'GET',
    headers,
    body,
    signal: opts.signal,
  });

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
}
