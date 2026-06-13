// Harness 持久化会话 API: 拉取本机最近一次 Harness Engineering 会话的快照。
// App 同时只跑一个会话, 故服务端简单返回 `{record: HardnessRecord | null}`。

import { apiRequest, type ApiRequestSignalOptions } from './client';

export type HardnessPhaseValue =
  | 'meta_collection'
  | 'reading'
  | 'planning'
  | 'implementing'
  | 'reviewing';

export type HardnessPhaseStatus =
  | 'pending'
  | 'running'
  | 'completed'
  | 'failed'
  | 'skipped';

export type HardnessOrchestratorStatus =
  | 'idle'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface HardnessChangedFile {
  relative_path: string;
  absolute_path: string;
  change_type: 'added' | 'modified' | 'deleted';
}

export interface HardnessPhaseLogSnapshot {
  phase: HardnessPhaseValue;
  status: HardnessPhaseStatus;
  lines: string[];
  exit_code: number | null;
  saved_log_path: string | null;
  changed_files: HardnessChangedFile[];
  review_verdict_fail: boolean;
}

export interface HardnessRoleConfig {
  cli_executable?: string;
  model_id?: string;
  // 还有更多字段, 这里只暴露常用的, 完整 raw JSON 通过 record.config 透传。
}

export interface HardnessSessionRecord {
  id: string;
  title: string;
  config: Record<string, unknown>;
  status: HardnessOrchestratorStatus;
  created_at: string;
  updated_at: string;
  phase_logs: HardnessPhaseLogSnapshot[];
  error_message: string | null;
  current_phase: string | null;
  manual_phase_input_requested: boolean;
  queued_manual_phase_input: string | null;
  queued_manual_phase_input_phase: string | null;
}

export function fetchHardnessSession(
  options: ApiRequestSignalOptions = {},
): Promise<{ record: HardnessSessionRecord | null }> {
  return apiRequest<{ record: HardnessSessionRecord | null }>(
    '/api/harness/session',
    options,
  );
}
