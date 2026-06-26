// Ops 仪表盘 + 清理 API。对应 service：
//   GET  /api/ops                       — 实时运行快照（30s TTL，由 service 内部缓存）
//   GET  /api/ops/cleanup/history        — 已成功清理的历史记录（最多 50 条）
//   POST /api/ops/cleanup body {target,expired_only} — 触发清理
//
// 注意：runtime snapshot 字段 process.* 是嵌套对象，前端按 `OpsRuntimeProcess` 解构。

import { apiRequest, type ApiRequestSignalOptions } from './client';

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
  // 后端补充的运行时身份字段，用于在面板上展示当前宿主信息。
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
  max_concurrent_requests?: number;
  active_request_ratio?: number;
  total_requests: number;
  total_errors: number;
  total_bytes_in: number;
  total_bytes_out: number;
  crash_count: number;
  restart_count: number;
  process: OpsRuntimeProcess;
  open_session_count: number;
  last_error: string;
  // 扩展观测面；老服务端缺字段时一律按 undefined 处理。
  status_code_breakdown?: Record<string, number>;
  method_breakdown?: Record<string, number>;
  top_routes?: OpsTopRoute[];
  latency_stats?: OpsLatencyStats;
  latency_buckets?: Record<string, number>;
  requests_per_minute?: number;
  errors_per_minute?: number;
  bytes_in_per_minute?: number;
  bytes_out_per_minute?: number;
  slowest_recent?: OpsRecentSlowRequest | null;
  last_error_at?: string | null;
  last_error_path?: string;
  active_sse_subscriptions?: number;
  recent_errors?: OpsRecentError[];
  log_level_breakdown?: Record<string, number>;
  memory_log_count?: number;
  send_phase_breakdown?: Record<string, number>;
  allowed_model_count?: number;
  model_provider_count?: number;
  template_count?: number;
  cron_enabled_count?: number;
  cron_total_count?: number;
  memory_entry_count?: number;
  mcp_server_enabled_count?: number;
  mcp_server_total_count?: number;
}

export interface OpsRecentError {
  at: string;
  method: string;
  path: string;
  status: number;
  duration_ms: number;
  message?: string;
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

export function getOpsSnapshot(
  options: ApiRequestSignalOptions = {},
): Promise<OpsRuntimeSnapshot> {
  return apiRequest<OpsRuntimeSnapshot>('/api/ops', options);
}

export function getCleanupHistory(
  options: ApiRequestSignalOptions = {},
): Promise<CleanupHistoryResponse> {
  return apiRequest<CleanupHistoryResponse>(
    '/api/ops/cleanup/history',
    options,
  );
}

export function runCleanup(input: RunCleanupInput): Promise<CleanupHistoryEntry> {
  return apiRequest<CleanupHistoryEntry>('/api/ops/cleanup', {
    method: 'POST',
    body: { target: input.target, expired_only: input.expired_only ?? false },
  });
}
