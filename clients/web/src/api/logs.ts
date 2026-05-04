// 日志列表 + 导出 API。对应 service：
//   GET /api/logs?offset=&limit= — 分页拉取（service 内存日志环；max 2000 / page）
//   GET /api/logs/export         — 整包 JSON 下载（含 memory + disk 日志）

import { apiRequest } from './client';
import { readToken, ensureDeviceId } from '../state/storage';

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
}

export function listLogs(options: ListLogsOptions = {}): Promise<ListLogsResponse> {
  const params = new URLSearchParams();
  if (options.offset != null) params.set('offset', String(options.offset));
  if (options.limit != null) params.set('limit', String(options.limit));
  const qs = params.toString();
  return apiRequest<ListLogsResponse>(`/api/logs${qs ? `?${qs}` : ''}`);
}

/// 触发浏览器下载——通过 fetch + Blob，避免 <a download> 失去鉴权头。
export async function exportLogsBundle(): Promise<void> {
  const token = readToken();
  const res = await fetch('/api/logs/export', {
    method: 'GET',
    headers: {
      'x-openhand-device-id': ensureDeviceId(),
      'x-openhand-source': 'WEB_PC',
      'x-openhand-device-platform': navigator.platform || 'web',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement('a');
    a.href = url;
    a.download = 'openhand-web-gateway-logs.json';
    document.body.appendChild(a);
    a.click();
    a.remove();
  } finally {
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
}
