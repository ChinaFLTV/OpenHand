// 日志列表 + 导出 API。对应 service：
//   GET /api/logs?offset=&limit= — 分页拉取（service 内存日志环；max 2000 / page）
//   GET /api/logs/export         — 整包 JSON 下载（含 memory + disk 日志）

import { apiRequest, throwIfApiResponseFailed } from './client';
import { readToken, ensureDeviceId } from '../state/storage';
import { clientEnvironmentHeaders } from '../utils/client_env';
import { downloadBlobWithAnchor } from '../utils/save_blob';
import {
  OperationTimeoutError,
  createTimedAbortController,
} from '../utils/timed_abort';
import { readResponseBlobBounded } from '../utils/bounded_response';

const EXPORT_LOGS_TIMEOUT_MS = 120_000;
const EXPORT_LOGS_MAX_BYTES = 256 * 1024 * 1024;

export interface LogEntry {
  id: number;
  timestamp: string;
  level: 'info' | 'success' | 'warn' | 'error' | 'debug' | 'telemetry';
  tag: string;
  message: string;
  data?: Record<string, unknown>;
}

export interface ListLogsResponse {
  items: LogEntry[];
  offset: number;
  limit: number;
  total: number;
  has_more: boolean;
}

export interface ListLogsOptions {
  offset?: number;
  limit?: number;
  signal?: AbortSignal;
}

export function listLogs(options: ListLogsOptions = {}): Promise<ListLogsResponse> {
  const params = new URLSearchParams();
  if (options.offset != null) params.set('offset', String(options.offset));
  if (options.limit != null) params.set('limit', String(options.limit));
  const qs = params.toString();
  return apiRequest<ListLogsResponse>(`/api/logs${qs ? `?${qs}` : ''}`, {
    signal: options.signal,
  });
}

/// 触发浏览器下载——通过 fetch + Blob，避免 <a download> 失去鉴权头。
export async function exportLogsBundle(): Promise<void> {
  const token = readToken();
  const timed = createTimedAbortController(EXPORT_LOGS_TIMEOUT_MS);
  let blob: Blob;
  try {
    const res = await fetch('/api/logs/export', {
      method: 'GET',
      headers: {
        'x-openhand-device-id': ensureDeviceId(),
        ...clientEnvironmentHeaders(),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      signal: timed.controller.signal,
    });
    await throwIfApiResponseFailed(res);
    blob = await readResponseBlobBounded(res, {
      maxBytes: EXPORT_LOGS_MAX_BYTES,
      signal: timed.controller.signal,
    });
  } catch (error) {
    if (timed.timedOut) {
      throw new OperationTimeoutError(timed.timeoutMs);
    }
    throw error;
  } finally {
    timed.dispose();
  }
  downloadBlobWithAnchor(blob, 'openhand-web-gateway-logs.json');
}
