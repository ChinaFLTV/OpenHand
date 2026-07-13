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

type HarnessOrchestratorStatus =
  | 'idle'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

interface HarnessChangedFile {
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
