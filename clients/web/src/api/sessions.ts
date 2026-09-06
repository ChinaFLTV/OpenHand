import {
  apiRequest,
  createApiRequestHeaders,
  fetchAuthenticatedBlob,
  type ApiRequestSignalOptions,
} from './client';
import type { PendingWriteApproval } from './session_events';
import { jsonlExportPickerSuggestedName, normalizeJsonlExportFilename } from '../shared/util/export_filename';
import { filenameFromContentDisposition, saveBlobWithPicker } from '../utils/save_blob';
import { ignoreError, isAbortError } from '../shared/util/errors';

export interface SessionTodoItem {
  id: string;
  content: string;
  status: string;
}

interface SessionPlanRecord {
  id: string;
  created_at: string;
  updated_at: string;
  status: string;
  plan?: string;
  steps?: SessionTodoItem[];
}

export type SessionMode = 'chat' | 'plan' | 'goal' | (string & {});

export const KNOWLEDGE_BASE_MESSAGE_METADATA_KEY = 'knowledge_base';

const GOAL_MODE_BLOCKED_TEMPLATE_IDS = new Set([
  'machine_expert',
  'harness_engineering',
  'web_reverse_expert',
  'android_reverse_expert',
]);

export const GOAL_DEFAULT_MAX_AUTO_TURNS = 12;
export const GOAL_HARD_MAX_AUTO_TURNS = 60;

export function isGoalModeAllowedForTemplate(templateId: string | null | undefined): boolean {
  return !GOAL_MODE_BLOCKED_TEMPLATE_IDS.has((templateId ?? '').trim());
}

type SessionGoalStatus =
  | 'running'
  | 'paused'
  | 'completed'
  | 'terminated'
  | 'failed'
  | 'round_limit_reached'
  | 'token_budget_reached'
  | (string & {});

interface SessionGoalEvaluationRecord {
  id: string;
  created_at: string;
  round_index: number;
  passed: boolean;
  summary: string;
  confidence?: number | null;
  follow_up_prompt?: string | null;
  evidence?: string[];
  missing?: string[];
  raw_response?: string | null;
  provider_config_id?: string | null;
  model_id?: string | null;
  model_label?: string | null;
  usage?: SessionMessageUsage | null;
  error?: string | null;
}

export interface SessionGoalRecord {
  id: string;
  objective: string;
  status: SessionGoalStatus;
  created_at: string;
  updated_at: string;
  evaluator_provider_config_id: string;
  evaluator_model_id: string;
  evaluator_model_label: string;
  max_turns?: number | null;
  token_budget?: number | null;
  turn_count: number;
  tokens_used: number;
  completed_at?: string | null;
  paused_at?: string | null;
  terminated_at?: string | null;
  status_reason?: string | null;
  last_assistant_message_id?: string | null;
  last_auto_user_message_id?: string | null;
  evaluations?: SessionGoalEvaluationRecord[];
}

export interface SessionGoalState {
  schema_version?: number;
  current?: SessionGoalRecord | null;
  history?: SessionGoalRecord[];
}

export interface GoalStartOptions {
  evaluator_provider_config_id: string;
  evaluator_model_id: string;
  evaluator_model_label: string;
  max_turns?: number | null;
  token_budget?: number | null;
}

interface SessionErrorRecord {
  id: string;
  created_at: string;
  stage: string;
  message: string;
  detail?: string | null;
  presented_at?: string | null;
}

export interface SessionSummary {
  id: string;
  title: string;
  template_id: string;
  template_name?: string;
  template_internal_version?: string;
  created_at: string;
  updated_at: string;
  mode: SessionMode;
  full_access_permission?: boolean;
  last_used_model_id?: string | null;
  last_used_model_label?: string | null;
  last_used_model_protocol?: string | null;
  is_title_manually_edited?: boolean;
  auto_title_acquired?: boolean;
  auto_title_retry_count?: number;
  auto_title_generated_at?: string | null;
  auto_title_source_message_id?: string | null;
  latest_compression_checkpoint_message_id?: string | null;
  latest_compression_at?: string | null;
  last_model_key?: string | null;
  input_cache_model_selection_locked?: boolean;
  message_count: number;
  statistics?: SessionStatistics;
  total_tokens?: number | null;
  total_prompt_tokens?: number | null;
  total_completion_tokens?: number | null;
  tool_message_count?: number;
  compression_point_count?: number;
  last_message_preview: string;
  last_message_kind?: string;
  send_phase: string;
  source?: string;
  device_id?: string;
  metadata?: Record<string, unknown>;
  web_context?: Record<string, unknown>;
  environment?: Record<string, unknown>;
  last_prompt_metadata?: Record<string, unknown>;
  plan_history?: SessionPlanRecord[];
  recent_errors?: SessionErrorRecord[];
  latest_compression_point?: SessionMessage | null;
  awaiting_plan_approval?: boolean;
  pending_plan?: string | null;
  todo_items?: SessionTodoItem[];
  goal_state?: SessionGoalState;
}

export interface SessionListResponse {
  items: SessionSummary[];
  page: number;
  page_size: number;
  total: number;
  has_more: boolean;
  sort: string;
  scope: string;
}

export interface SessionDetailResponse {
  session: SessionSummary;
  runtime: {
    send_phase: string;
    can_stop: boolean;
    last_error: string | null;
  };
}

type MachineTerminalStatus =
  | 'idle'
  | 'starting'
  | 'running'
  | 'stopped'
  | 'failed'
  | (string & {});

export interface MachineTerminalSnapshot {
  session_id: string;
  terminal_id: string;
  identity: string;
  status: MachineTerminalStatus;
  shell: string;
  working_directory: string;
  rows: number;
  columns: number;
  output: string;
  ansi_output?: string;
  output_characters: number;
  history_output?: string;
  history_ansi_output?: string;
  history_output_characters?: number;
  command_count?: number;
  command_history?: MachineTerminalCommandHistoryEntry[];
  attached?: boolean;
  has_user_activity?: boolean;
  started_at: string;
  updated_at: string;
  pid?: number | null;
  exit_code?: number | null;
  error_message?: string | null;
}

interface MachineTerminalCommandHistoryEntry {
  id: string;
  terminal_id: string;
  command: string;
  output: string;
  exit_code?: number | null;
  timed_out: boolean;
  duration_ms: number;
  started_at: string;
  completed_at: string;
  error?: string | null;
}

export interface MachineTerminalWorkspace {
  session_id: string;
  active_terminal_id: string;
  terminals: MachineTerminalSnapshot[];
  active_terminal?: MachineTerminalSnapshot | null;
}

interface MachineTerminalResponse {
  terminal: MachineTerminalWorkspace;
}

type SessionMessageSenderOrigin =
  | 'explicit_user'
  | 'openhand_background'
  | 'ai_model'
  | 'openhand_system'
  | (string & {});

type SessionMessageConversationSide =
  | 'non_ai'
  | 'ai'
  | 'system'
  | (string & {});

export type SessionMessageFeedback = 'liked' | 'needs_improvement';
export const DEFERRED_MESSAGE_TELEMETRY_METADATA_KEY =
  '_openhand_deferred_telemetry';

export interface SessionMessage {
  id: string;
  kind: string;
  role: string;
  content: string;
  created_at: string;
  character_count: number;
  model_id?: string;
  model_label?: string;
  usage?: SessionMessageUsage | null;
  sender_origin?: SessionMessageSenderOrigin;
  conversation_side?: SessionMessageConversationSide;
  starts_conversation_round?: boolean;
  feedback?: SessionMessageFeedback | null;
  metadata?: Record<string, unknown>;
}

interface SessionMessageUsage {
  prompt_tokens?: number | null;
  completion_tokens?: number | null;
  total_tokens?: number | null;
  cache_read_tokens?: number | null;
  cache_creation_tokens?: number | null;
  reasoning_tokens?: number | null;
  audio_input_tokens?: number | null;
  image_input_tokens?: number | null;
  video_input_tokens?: number | null;
  web_search_tool_usage?: number | null;
  web_search_page_usage?: number | null;
}

interface SessionStatistics extends SessionMessageUsage {
  total_message_count?: number;
  user_message_count?: number;
  assistant_message_count?: number;
  tool_message_count?: number;
  mcp_message_count?: number;
  skill_message_count?: number;
  compression_point_count?: number;
  total_input_characters?: number;
  total_output_characters?: number;
  total_prompt_characters?: number;
  prompt_build_count?: number;
  compression_run_count?: number;
  first_prompt_tokens?: number | null;
  // 后端预计算字段：默认剔除首轮冷请求与过期异常，避免 WEB 端独立
  // walk messages 重算导致跨端计算口径漂移。`null` 表示无任何 token 数据。
  cache_hit_ratio?: number | null;
  cache_hit_trend_points?: SessionCacheHitTrendPoint[];
  cache_hit_trend_excluded_count?: number;
}

export interface SessionCacheHitTrendPoint {
  turn_index: number;
  hit_ratio: number;
  prompt_tokens: number;
  cache_read_tokens: number;
  cache_write_tokens: number;
  starter_message_id?: string | null;
  starter_message_kind?: string | null;
  starter_origin?: string | null;
  anchor_message_id?: string | null;
  idle_gap_seconds?: number | null;
}

interface SessionMessagesResponse {
  session?: SessionSummary;
  items: SessionMessage[];
  offset: number;
  limit: number;
  total: number;
  has_more: boolean;
  has_older?: boolean;
  has_newer?: boolean;
  window?: 'tail' | 'offset' | string;
  send_phase: string;
  last_error: string | null;
  pending_write_approval?: PendingWriteApproval | null;
  resolved_reveal_message_id?: string | null;
}

interface ListSessionsOptions extends ApiRequestSignalOptions {
  page?: number;
  pageSize?: number;
  source?: string;
  deviceId?: string;
}

function buildSessionListQuery(options: ListSessionsOptions): string {
  const params = new URLSearchParams();
  if (options.page != null) params.set('page', String(options.page));
  if (options.pageSize != null) params.set('page_size', String(options.pageSize));
  if (options.source) params.set('source', options.source);
  if (options.deviceId) params.set('device_id', options.deviceId);
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

export function listSessions(
  options: ListSessionsOptions = {},
): Promise<SessionListResponse> {
  return apiRequest<SessionListResponse>(
    `/api/sessions${buildSessionListQuery(options)}`,
    {
      signal: options.signal,
      timeoutMs: options.timeoutMs,
    },
  );
}

export interface CreateSessionInput {
  templateId?: string;
  mode?: SessionMode;
  title?: string;
  modelKey?: string;
}

export const SESSION_TITLE_MAX_CHARACTERS = 200;

export interface CreateSessionResponse {
  session: SessionSummary;
  warnings?: string[];
}

export function createSession(
  input: CreateSessionInput = {},
): Promise<CreateSessionResponse> {
  return apiRequest<CreateSessionResponse>('/api/sessions', {
    method: 'POST',
    body: {
      template_id: input.templateId ?? 'default',
      mode: input.mode ?? 'chat',
      ...(input.title ? { title: input.title } : {}),
      ...(input.modelKey ? { model_key: input.modelKey } : {}),
    },
  });
}

interface SessionRequestOptions {
  signal?: AbortSignal;
  hydrateCacheStatistics?: boolean;
}

export function getSession(
  id: string,
  options: SessionRequestOptions = {},
): Promise<SessionDetailResponse> {
  const params = new URLSearchParams();
  if (options.hydrateCacheStatistics) {
    params.set('hydrate_cache_statistics', '1');
  }
  const query = params.toString();
  return apiRequest<SessionDetailResponse>(
    `/api/sessions/${encodeURIComponent(id)}${query ? `?${query}` : ''}`,
    { signal: options.signal },
  );
}

export function getMachineTerminal(
  id: string,
  options: SessionRequestOptions & { includeHistory?: boolean; start?: boolean } = {},
): Promise<MachineTerminalResponse> {
  const params = new URLSearchParams();
  if (options.start === false) params.set('start', 'false');
  if (options.includeHistory) params.set('history', 'true');
  const qs = params.toString();
  return apiRequest<MachineTerminalResponse>(
    `/api/sessions/${encodeURIComponent(id)}/terminal${qs ? `?${qs}` : ''}`,
    { signal: options.signal },
  );
}

export function writeMachineTerminal(
  id: string,
  input: {
    data: string;
    terminalId?: string;
    appendNewline?: boolean;
    includeHistory?: boolean;
  },
  options: ApiRequestSignalOptions = {},
): Promise<{ ok: boolean; terminal?: MachineTerminalWorkspace | null }> {
  return apiRequest<{ ok: boolean; terminal?: MachineTerminalWorkspace | null }>(
    `/api/sessions/${encodeURIComponent(id)}/terminal/write`,
    {
      method: 'POST',
      ...options,
      body: {
        data: input.data,
        ...(input.terminalId ? { terminal_id: input.terminalId } : {}),
        ...(input.appendNewline ? { append_newline: true } : {}),
        ...(input.includeHistory ? { include_history: true } : {}),
      },
    },
  );
}

export function controlMachineTerminal(
  id: string,
  input: {
    action: string;
    terminalId?: string;
    workingDirectory?: string;
    columns?: number;
    rows?: number;
    includeHistory?: boolean;
  },
): Promise<MachineTerminalResponse & { ok: boolean }> {
  return apiRequest<MachineTerminalResponse & { ok: boolean }>(
    `/api/sessions/${encodeURIComponent(id)}/terminal/control`,
    {
      method: 'POST',
      body: {
        action: input.action,
        ...(input.terminalId ? { terminal_id: input.terminalId } : {}),
        ...(input.workingDirectory
          ? { working_directory: input.workingDirectory }
          : {}),
        ...(Number.isFinite(input.columns) ? { columns: input.columns } : {}),
        ...(Number.isFinite(input.rows) ? { rows: input.rows } : {}),
        ...(input.includeHistory ? { include_history: true } : {}),
      },
    },
  );
}

export function renameSession(
  id: string,
  title: string,
): Promise<{ ok: boolean; session: SessionSummary }> {
  return apiRequest<{ ok: boolean; session: SessionSummary }>(
    `/api/sessions/${encodeURIComponent(id)}`,
    {
      method: 'PATCH',
      body: { title },
    },
  );
}

export function updateSessionMode(
  id: string,
  mode: SessionMode,
): Promise<{ ok: boolean; session: SessionSummary }> {
  return apiRequest<{ ok: boolean; session: SessionSummary }>(
    `/api/sessions/${encodeURIComponent(id)}`,
    {
      method: 'PATCH',
      body: { mode },
    },
  );
}

export function updateSessionFullAccessPermission(
  id: string,
  fullAccessPermission: boolean,
): Promise<{ ok: boolean; session: SessionSummary }> {
  return apiRequest<{ ok: boolean; session: SessionSummary }>(
    `/api/sessions/${encodeURIComponent(id)}`,
    {
      method: 'PATCH',
      body: { full_access_permission: fullAccessPermission },
    },
  );
}

export function deleteSession(
  id: string,
): Promise<{ ok: boolean; deleted_session_id: string }> {
  return apiRequest<{ ok: boolean; deleted_session_id: string }>(
    `/api/sessions/${encodeURIComponent(id)}`,
    { method: 'DELETE' },
  );
}

interface ListMessagesOptions {
  limit?: number;
  offset?: number;
  tail?: boolean;
  revealMessageId?: string;
  signal?: AbortSignal;
}

export function listMessages(
  sessionId: string,
  options: ListMessagesOptions = {},
): Promise<SessionMessagesResponse> {
  const params = new URLSearchParams();
  if (options.limit != null) params.set('limit', String(options.limit));
  if (options.offset != null) params.set('offset', String(options.offset));
  if (options.tail) params.set('tail', '1');
  if (options.revealMessageId) {
    params.set('reveal_message_id', options.revealMessageId);
  }
  const qs = params.toString();
  return apiRequest<SessionMessagesResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages${qs ? `?${qs}` : ''}`,
    { signal: options.signal },
  );
}

export function getSessionMessage(
  sessionId: string,
  messageId: string,
  options: ApiRequestSignalOptions = {},
): Promise<{ message: SessionMessage }> {
  return apiRequest<{ message: SessionMessage }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}`,
    { signal: options.signal, timeoutMs: options.timeoutMs },
  );
}

interface SessionTitleSourceMessagesResponse {
  ok: boolean;
  items: SessionMessage[];
  total: number;
}

export function listSessionTitleSourceMessages(
  sessionId: string,
  options: ApiRequestSignalOptions = {},
): Promise<SessionTitleSourceMessagesResponse> {
  return apiRequest<SessionTitleSourceMessagesResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/title-source-messages`,
    { signal: options.signal, timeoutMs: options.timeoutMs },
  );
}

/// 与 service `_sendMessage` 协议一一对齐：
/// - mode: 与 meta.conversation_modes 之一对齐（normal/plan/image/video/audio）；
/// - model_key: 必须命中 meta.models[*].key；
/// - attachments[]: 浏览器 File API 读出来的 base64（不含 data: 前缀）。
/// - selected_skill: 由 /api/skills 返回的 name + relative_directory_path，
///   service 端会读取 SKILL.md 并走 App 同款隐藏 reminder 注入。
export interface SendMessageInput {
  content: string;
  modelKey: string;
  mode?: string;
  attachments?: SendMessageAttachment[];
  selectedSkill?: SendMessageSelectedSkill | null;
  creationOptions?: Record<string, unknown>;
  /// 本轮临时跳过的用户指令 id 列表（仅作用于本次发送，不持久化）。
  /// 与 App 端 `_skippedInstructionIds` 语义一致：传给后端后，
  /// `AiSessionRuntimeContext.skippedInstructionIds` 会被注入，
  /// prompt builder 仅拼装 enabled 且未跳过的指令。
  skippedInstructionIds?: string[];
  goalOptions?: GoalStartOptions | null;
  allowQueuedGoalInterruption?: boolean;
}

interface SendMessageSelectedSkill {
  name: string;
  relative_directory_path: string;
}

export interface SendMessageAttachment {
  name: string;
  /// base64 字符串，不含 `data:` 前缀。
  data_base64: string;
}

interface SendMessageResponse {
  ok: boolean;
  send_phase: string;
}

export function sendMessage(
  sessionId: string,
  input: SendMessageInput,
): Promise<SendMessageResponse> {
  return apiRequest<SendMessageResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages`,
    {
      method: 'POST',
      body: {
        content: input.content,
        mode: input.mode ?? 'normal',
        model_key: input.modelKey,
        attachments: input.attachments ?? [],
        selected_skill: input.selectedSkill ?? null,
        skipped_instruction_ids: input.skippedInstructionIds ?? [],
        creation_options: input.creationOptions ?? null,
        goal_options: input.goalOptions ?? null,
        allow_queued_goal_interruption: input.allowQueuedGoalInterruption ?? false,
      },
    },
  );
}

export function syncGoalQueueYield(
  sessionId: string,
  hasPending: boolean,
): Promise<{ ok: boolean; has_pending: boolean }> {
  return apiRequest<{ ok: boolean; has_pending: boolean }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/goal/queue-yield`,
    {
      method: 'POST',
      body: {
        has_pending: hasPending,
      },
    },
  );
}

export function pauseGoal(
  sessionId: string,
): Promise<{ ok: boolean; session: SessionSummary }> {
  return apiRequest<{ ok: boolean; session: SessionSummary }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/goal/pause`,
    { method: 'POST', body: {} },
  );
}

export function resumeGoal(
  sessionId: string,
  modelKey?: string,
): Promise<SendMessageResponse> {
  return apiRequest<SendMessageResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/goal/resume`,
    { method: 'POST', body: { model_key: modelKey ?? '' } },
  );
}

export function terminateGoal(
  sessionId: string,
): Promise<{ ok: boolean; session: SessionSummary }> {
  return apiRequest<{ ok: boolean; session: SessionSummary }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/goal/terminate`,
    { method: 'POST', body: {} },
  );
}

interface StopMessageResponse {
  ok: boolean;
  send_phase: string;
  reason?: string;
}

export function stopMessage(sessionId: string): Promise<StopMessageResponse> {
  return apiRequest<StopMessageResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/stop`,
    { method: 'POST', body: {} },
  );
}

interface GenerateSessionTitleResponse {
  title: string;
}

export function generateSessionTitle(
  sessionId: string,
  content: string,
  options: ApiRequestSignalOptions & { modelKey?: string } = {},
): Promise<GenerateSessionTitleResponse> {
  return apiRequest<GenerateSessionTitleResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/generate-title`,
    {
      method: 'POST',
      body: { content, model_key: options.modelKey ?? '' },
      signal: options.signal,
      timeoutMs: options.timeoutMs,
    },
  );
}

export type CompactSessionStatus =
  | 'success'
  | 'not_needed'
  | 'cooldown'
  | 'inflight'
  | 'circuit_breaker'
  | 'session_busy'
  | 'failed'
  | 'no_session';

interface CompactSessionResponse {
  ok: boolean;
  status: CompactSessionStatus;
  rejection_reason?: string | null;
  retry_after_ms?: number;
  session?: SessionSummary;
}

/**
 * 用户主动触发的会话历史压缩。后端在 [web_message_platform_service.dart]
 * 的 `_compactSession` 中复用桌面端 [requestManualCompaction]：包含 30s
 * 防抖、占用率过低拒绝、连续失败熔断等保护，因此前端在收到 `cooldown`
 * 等非 `success` 状态时只需做提示，不需要再做客户端节流。
 */
export function compactSession(
  sessionId: string,
  options: { modelKey?: string } = {},
): Promise<CompactSessionResponse> {
  return apiRequest<CompactSessionResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/compact`,
    {
      method: 'POST',
      body: { model_key: options.modelKey ?? '' },
    },
  );
}

type WriteApprovalDecision = 'approved' | 'rejected' | 'dismissed';

export function respondWriteApproval(
  sessionId: string,
  approvalId: string,
  decision: WriteApprovalDecision,
): Promise<{ ok: boolean; decision: WriteApprovalDecision; approved: boolean }> {
  return apiRequest<{ ok: boolean; decision: WriteApprovalDecision; approved: boolean }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/write-approvals/${encodeURIComponent(approvalId)}`,
    {
      method: 'POST',
      // 同时上送 decision（新字段）与 approved（旧字段，向后兼容旧网关）。
      body: { decision, approved: decision === 'approved' },
    },
  );
}

/// 删除单条消息（对齐 APP 端长按菜单）。返回 `{ok}`；ok=false 表示消息已不存在。
export async function deleteMessage(
  sessionId: string,
  messageId: string,
): Promise<{ ok: boolean }> {
  return apiRequest<{ ok: boolean }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}`,
    { method: 'DELETE' },
  );
}

/// 删除该消息及之后所有消息。
export async function deleteMessageCascade(
  sessionId: string,
  messageId: string,
): Promise<{ ok: boolean }> {
  return apiRequest<{ ok: boolean }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}/cascade`,
    { method: 'DELETE' },
  );
}

/// 从指定消息派生新会话：保留该消息及之前的消息，丢弃之后的消息。
export async function forkSessionFromMessage(
  sessionId: string,
  messageId: string,
): Promise<{ ok: boolean; session: SessionSummary }> {
  return apiRequest<{ ok: boolean; session: SessionSummary }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}/fork`,
    { method: 'POST' },
  );
}

export async function setMessageFeedback(
  sessionId: string,
  messageId: string,
  feedback: SessionMessageFeedback | null,
): Promise<{ ok: boolean; feedback?: SessionMessageFeedback | null; message?: SessionMessage }> {
  return apiRequest<{ ok: boolean; feedback?: SessionMessageFeedback | null; message?: SessionMessage }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}/feedback`,
    { method: 'PUT', body: { feedback } },
  );
}

export async function translateMessage(
  sessionId: string,
  messageId: string,
): Promise<{
  ok: boolean;
  text: string;
  provider?: string;
  model_config_id?: string | null;
  model_id?: string | null;
  settings_fingerprint?: string | null;
}> {
  return apiRequest<{
    ok: boolean;
    text: string;
    provider?: string;
    model_config_id?: string | null;
    model_id?: string | null;
    settings_fingerprint?: string | null;
  }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}/translate`,
    { method: 'POST' },
  );
}

export interface MessageTtsPlaybackState {
  playing: boolean;
  message_id?: string | null;
  provider?: string | null;
  error?: string | null;
  failure_id?: string | null;
}

export async function fetchMessageTtsPlayback(
  options: ApiRequestSignalOptions = {},
): Promise<{
  ok: boolean;
  playback: MessageTtsPlaybackState;
}> {
  return apiRequest<{ ok: boolean; playback: MessageTtsPlaybackState }>(
    '/api/tts/playback',
    options,
  );
}

export async function stopMessageTtsPlayback(): Promise<{
  ok: boolean;
  playback: MessageTtsPlaybackState;
}> {
  return apiRequest<{ ok: boolean; playback: MessageTtsPlaybackState }>(
    '/api/tts/stop',
    { method: 'POST' },
  );
}

export function stopMessageTtsPlaybackOnPageExit(): void {
  void fetch('/api/tts/stop', {
    method: 'POST',
    headers: createApiRequestHeaders(),
    credentials: 'same-origin',
    keepalive: true,
  }).catch(ignoreError);
}

export async function toggleMessageTtsPlayback(
  sessionId: string,
  messageId: string,
): Promise<{
  ok: boolean;
  playback: MessageTtsPlaybackState;
}> {
  return apiRequest<{ ok: boolean; playback: MessageTtsPlaybackState }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}/tts/toggle`,
    { method: 'POST' },
  );
}

export async function regenerateMessage(
  sessionId: string,
  messageId: string,
  input: { modelKey?: string } = {},
): Promise<{ ok: boolean; send_phase?: string }> {
  return apiRequest<{ ok: boolean; send_phase?: string }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages/${encodeURIComponent(messageId)}/regenerate`,
    { method: 'POST', body: { model_key: input.modelKey ?? '' } },
  );
}

/// 设置或更新会话级节流覆盖。覆盖会写入会话 metadata，重启后继续生效；
/// `charsPerSecond` / `cardsPerSecond` 为 null 表示清除对应方向覆盖；
/// 为 0 表示对应方向关闭节流。
export async function setSessionThrottle(
  sessionId: string,
  patch: {
    charsPerSecond?: number | null;
    cardsPerSecond?: number | null;
    /// 2026-05-19 — 会话级启用开关：null = 清除覆盖回退到全局；
    /// false = 强制关闭节流；true = 强制开启。
    enabled?: boolean | null;
  },
): Promise<{
  ok: boolean;
  chars_per_second?: number | null;
  cards_per_second?: number | null;
  enabled?: boolean | null;
}> {
  const body: Record<string, unknown> = {};
  if (patch.charsPerSecond !== undefined) body['chars_per_second'] = patch.charsPerSecond;
  if (patch.cardsPerSecond !== undefined) body['cards_per_second'] = patch.cardsPerSecond;
  if (patch.enabled !== undefined) body['enabled'] = patch.enabled;
  return apiRequest<{
    ok: boolean;
    chars_per_second?: number | null;
    cards_per_second?: number | null;
    enabled?: boolean | null;
  }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/throttle`,
    { method: 'PUT', body },
  );
}

/// 清除指定会话的全部节流覆盖，恢复到全局节流设置。
export async function clearSessionThrottle(
  sessionId: string,
): Promise<{ ok: boolean }> {
  return apiRequest<{ ok: boolean }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/throttle`,
    { method: 'DELETE' },
  );
}

/// 触发会话 JSON 导出保存。在 service 端附带 Content-Disposition: attachment，
/// 这里抓 blob 后优先打开系统保存面板；不绕过鉴权（带上 token）。
interface ExportDownloadResult {
  filename: string;
}

export const EXPORT_SESSION_TIMEOUT_ERROR = 'EXPORT_SESSION_TIMEOUT';
const EXPORT_SESSION_TIMEOUT_MS = 120_000;
const EXPORT_SESSION_MAX_BYTES = 256 * 1024 * 1024;

export async function exportSessionDownload(
  sessionId: string,
  fallbackName: string,
): Promise<ExportDownloadResult> {
  let filename = normalizeJsonlExportFilename(`${fallbackName}.jsonl`);
  let blob: Blob;
  try {
    const result = await fetchAuthenticatedBlob(
      `/api/sessions/${encodeURIComponent(sessionId)}/export`,
      {
        accept: 'application/x-ndjson',
        maxBytes: EXPORT_SESSION_MAX_BYTES,
        timeoutMs: EXPORT_SESSION_TIMEOUT_MS,
      },
    );
    const parsedFilename = filenameFromContentDisposition(
      result.response.headers.get('Content-Disposition'),
    );
    if (parsedFilename) {
      filename = normalizeJsonlExportFilename(parsedFilename);
    }
    blob = result.blob;
  } catch (error) {
    if (
      (error instanceof Error && error.name === 'OperationTimeoutError') ||
      isAbortError(error)
    ) {
      throw new Error(EXPORT_SESSION_TIMEOUT_ERROR);
    }
    throw error;
  }
  const saved = await saveBlobWithPicker(
    blob,
    filename,
    [{ description: 'JSONL', accept: { 'application/x-ndjson': ['.jsonl'] } }],
    jsonlExportPickerSuggestedName(filename),
  );
  return { filename: saved.filename };
}
