// Ops 仪表盘 + 清理 API。对应 service：
//   GET  /api/ops                       — 实时运行快照（30s TTL，由 service 内部缓存）
//   GET  /api/ops/cleanup/history        — 已成功清理的历史记录（最多 50 条）
//   POST /api/ops/cleanup body {target,expired_only} — 触发清理
//
// 注意：runtime snapshot 字段 process.* 是嵌套对象，前端按 `OpsRuntimeProcess` 解构。

import { apiRequest } from './client';

export interface OpsRuntimeProcess {
  pid: number;
  current_rss_bytes: number;
  max_rss_bytes: number;
  cpu_percent: number | null;
  thread_count: number | null;
  file_handle_count: number | null;
  swap_bytes: number | null;
  disk_log_bytes: number;
  platform: string;
  platform_version: string;
  // 由后端 Stage 8 起补充：用于在面板上展示运行时身份。
  dart_version?: string;
  host_name?: string;
}

export interface OpsLatencyStats {
  sample_count: number;
  avg_ms: number;
  p50_ms: number;
  p95_ms: number;
  p99_ms: number;
  max_ms: number;
}

export interface OpsTopRoute {
  path: string;
  count: number;
}

export interface OpsRecentSlowRequest {
  path: string;
  method: string;
  status_code: number;
  duration_ms: number;
  at: string | null;
}

export interface OpsRuntimeSnapshot {
  state: 'stopped' | 'starting' | 'running' | 'stopping' | 'crashed';
  started_at: string | null;
  uptime_ms: number;
  bound_url: string;
  accessible_urls: string[];
  active_requests: number;
  total_requests: number;
  total_errors: number;
  total_bytes_in: number;
  total_bytes_out: number;
  crash_count: number;
  restart_count: number;
  process: OpsRuntimeProcess;
  open_session_count: number;
  last_error: string;
  // 扩展观测面（后端 Stage 8 起补充，老服务端缺字段时一律按 undefined 处理）。
  status_code_breakdown?: Record<string, number>;
  method_breakdown?: Record<string, number>;
  top_routes?: OpsTopRoute[];
  latency_stats?: OpsLatencyStats;
  requests_per_minute?: number;
  slowest_recent?: OpsRecentSlowRequest | null;
  last_error_at?: string | null;
  last_error_path?: string;
}

export interface CleanupHistoryEntry {
  timestamp: string;
  target: string;
  expired_only: boolean;
  deleted_files: number;
  deleted_directories: number;
  bytes_freed: number;
  memory_log_entries_cleared: number;
}

export interface CleanupHistoryResponse {
  items: CleanupHistoryEntry[];
  total: number;
  max_items: number;
}

export interface RunCleanupInput {
  target: 'all' | 'logs' | 'uploads';
  expired_only?: boolean;
}

export function getOpsSnapshot(): Promise<OpsRuntimeSnapshot> {
  return apiRequest<OpsRuntimeSnapshot>('/api/ops');
}

export function getCleanupHistory(): Promise<CleanupHistoryResponse> {
  return apiRequest<CleanupHistoryResponse>('/api/ops/cleanup/history');
}

export function runCleanup(input: RunCleanupInput): Promise<CleanupHistoryEntry> {
  return apiRequest<CleanupHistoryEntry>('/api/ops/cleanup', {
    method: 'POST',
    body: { target: input.target, expired_only: input.expired_only ?? false },
  });
}
