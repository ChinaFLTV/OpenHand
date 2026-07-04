// Harness 持久化会话 API: 拉取本机最近一次 Harness Engineering 会话的快照。
// App 同时只跑一个会话, 故服务端简单返回 `{record: HarnessRecord | null}`。

import { apiRequest, type ApiRequestSignalOptions } from './client';

export type HarnessPhaseValue =
  | 'meta_collection'
  | 'reading'
  | 'planning'
  | 'implementing'
  | 'reviewing';

export type HarnessPhaseStatus =
  | 'pending'
  | 'running'
  | 'completed'
  | 'failed'
  | 'skipped';

export type HarnessOrchestratorStatus =
  | 'idle'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface HarnessChangedFile {
  relative_path: string;
  absolute_path: string;
  change_type: 'added' | 'modified' | 'deleted';
}

export interface HarnessPhaseLogSnapshot {
  phase: HarnessPhaseValue;
  status: HarnessPhaseStatus;
  lines: string[];
  exit_code: number | null;
  saved_log_path: string | null;
  changed_files: HarnessChangedFile[];
  review_verdict_fail: boolean;
}

export interface HarnessRoleConfig {
  cli_executable?: string;
  model_id?: string;
  // 还有更多字段, 这里只暴露常用的, 完整 raw JSON 通过 record.config 透传。
}

export interface HarnessSessionRecord {
  id: string;
  title: string;
  config: Record<string, unknown>;
  status: HarnessOrchestratorStatus;
  created_at: string;
  updated_at: string;
  phase_logs: HarnessPhaseLogSnapshot[];
  error_message: string | null;
  current_phase: string | null;
  manual_phase_input_requested: boolean;
  queued_manual_phase_input: string | null;
  queued_manual_phase_input_phase: string | null;
}

export function fetchHarnessSession(
  options: ApiRequestSignalOptions = {},
): Promise<{ record: HarnessSessionRecord | null }> {
  return apiRequest<{ record: HarnessSessionRecord | null }>(
    '/api/harness/session',
    options,
  );
}
