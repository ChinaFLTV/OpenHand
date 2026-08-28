import { apiRequest, fetchAuthenticatedBlob } from './client';
import { downloadBlobWithAnchor } from '../utils/save_blob';

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

interface ListLogsResponse {
  items: LogEntry[];
  offset: number;
  limit: number;
  total: number;
  has_more: boolean;
}

interface ListLogsOptions {
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
  const { blob } = await fetchAuthenticatedBlob('/api/logs/export', {
    maxBytes: EXPORT_LOGS_MAX_BYTES,
    timeoutMs: EXPORT_LOGS_TIMEOUT_MS,
  });
  downloadBlobWithAnchor(blob, 'openhand-web-gateway-logs.json');
}
