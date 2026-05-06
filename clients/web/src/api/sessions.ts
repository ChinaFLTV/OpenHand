// 会话与消息相关接口的封装层。
// 严格按服务端 `web_message_platform_service.dart` 的契约编码：
//   GET    /api/sessions?page=&page_size=&source=&device_id=
//   POST   /api/sessions {template_id, mode, title?}                  → 201
//   GET    /api/sessions/:id
//   PATCH  /api/sessions/:id {title}
//   DELETE /api/sessions/:id
//   GET    /api/sessions/:id/messages?limit=&offset=
//
// 任何接口的 401 都会被 apiRequest 自动转成 UnauthorizedError + 清理本地 token。

import { ApiError, UnauthorizedError, apiRequest } from './client';
import { clearAuthStorage, ensureDeviceId, readToken } from '../state/storage';
import type { PendingWriteApproval } from './session_events';
import { clientEnvironmentHeaders } from '../utils/client_env';
import { saveBlobWithPicker } from '../utils/save_blob';

export interface SessionTodoItem {
  id: string;
  content: string;
  status: string;
}

export interface SessionPlanRecord {
  id: string;
  created_at: string;
  updated_at: string;
  status: string;
  plan?: string;
  steps?: SessionTodoItem[];
}

export interface SessionErrorRecord {
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
  template_internal_version?: number;
  created_at: string;
  updated_at: string;
  mode: 'chat' | 'plan' | string;
  full_access_permission?: boolean;
  last_used_model_id?: string | null;
  last_used_model_label?: string | null;
  is_title_manually_edited?: boolean;
  auto_title_generated_at?: string | null;
  auto_title_source_message_id?: string | null;
  latest_compression_checkpoint_message_id?: string | null;
  latest_compression_at?: string | null;
  last_model_key?: string | null;
  message_count: number;
  statistics?: Record<string, unknown>;
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

export interface SessionMessage {
  id: string;
  kind: string;
  role: string;
  content: string;
  created_at: string;
  character_count: number;
  model_id?: string;
  model_label?: string;
  metadata?: Record<string, unknown>;
}

export interface SessionMessagesResponse {
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
}

export interface ListSessionsOptions {
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
  );
}

export interface CreateSessionInput {
  templateId?: string;
  mode?: 'chat' | 'plan';
  title?: string;
  modelKey?: string;
}

export function createSession(
  input: CreateSessionInput = {},
): Promise<{ session: SessionSummary }> {
  return apiRequest<{ session: SessionSummary }>('/api/sessions', {
    method: 'POST',
    body: {
      template_id: input.templateId ?? 'default',
      mode: input.mode ?? 'chat',
      ...(input.title ? { title: input.title } : {}),
      ...(input.modelKey ? { model_key: input.modelKey } : {}),
    },
  });
}

export function getSession(id: string): Promise<SessionDetailResponse> {
  return apiRequest<SessionDetailResponse>(
    `/api/sessions/${encodeURIComponent(id)}`,
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
  mode: 'chat' | 'plan',
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

export interface ListMessagesOptions {
  limit?: number;
  offset?: number;
  tail?: boolean;
}

export function listMessages(
  sessionId: string,
  options: ListMessagesOptions = {},
): Promise<SessionMessagesResponse> {
  const params = new URLSearchParams();
  if (options.limit != null) params.set('limit', String(options.limit));
  if (options.offset != null) params.set('offset', String(options.offset));
  if (options.tail) params.set('tail', '1');
  const qs = params.toString();
  return apiRequest<SessionMessagesResponse>(
    `/api/sessions/${encodeURIComponent(sessionId)}/messages${qs ? `?${qs}` : ''}`,
  );
}

/// 与 service `_sendMessage` 协议一一对齐：
/// - mode: 与 meta.conversation_modes 之一对齐（normal/plan/image/video/audio）；
/// - model_key: 必须命中 meta.models[*].key；
/// - attachments[]: 浏览器 File API 读出来的 base64（不含 data: 前缀）。
export interface SendMessageInput {
  content: string;
  modelKey: string;
  mode?: string;
  attachments?: SendMessageAttachment[];
}

export interface SendMessageAttachment {
  name: string;
  /// base64 字符串，不含 `data:` 前缀。
  data_base64: string;
}

export interface SendMessageResponse {
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
      },
    },
  );
}

export interface StopMessageResponse {
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

export function respondWriteApproval(
  sessionId: string,
  approvalId: string,
  approved: boolean,
): Promise<{ ok: boolean; approved: boolean }> {
  return apiRequest<{ ok: boolean; approved: boolean }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/write-approvals/${encodeURIComponent(approvalId)}`,
    { method: 'POST', body: { approved } },
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

/// 触发会话 JSON 导出保存。在 service 端附带 Content-Disposition: attachment，
/// 这里抓 blob 后优先打开系统保存面板；不绕过鉴权（带上 token）。
export interface ExportDownloadResult {
  filename: string;
}

export const EXPORT_SESSION_TIMEOUT_ERROR = 'EXPORT_SESSION_TIMEOUT';
const EXPORT_SESSION_TIMEOUT_MS = 15_000;

function filenameFromContentDisposition(value: string | null): string | null {
  if (!value) return null;
  const encoded = /filename\*=UTF-8''([^;]+)/i.exec(value);
  if (encoded?.[1]) {
    try {
      return decodeURIComponent(encoded[1]);
    } catch {
      return encoded[1];
    }
  }
  const quoted = /filename="([^"]+)"/i.exec(value);
  if (quoted?.[1]) return quoted[1];
  const plain = /filename=([^;]+)/i.exec(value);
  return plain?.[1]?.trim() ?? null;
}

export async function exportSessionDownload(
  sessionId: string,
  fallbackName: string,
): Promise<ExportDownloadResult> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'x-openhand-device-id': ensureDeviceId(),
    ...clientEnvironmentHeaders(),
  };
  const token = readToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), EXPORT_SESSION_TIMEOUT_MS);
  let res: Response;
  try {
    res = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}/export`, {
      method: 'GET',
      headers,
      credentials: 'same-origin',
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new Error(EXPORT_SESSION_TIMEOUT_ERROR);
    }
    throw error;
  } finally {
    window.clearTimeout(timeout);
  }
  if (res.status === 401) {
    clearAuthStorage();
    throw new UnauthorizedError(null);
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new ApiError(res.status, text || null);
  }
  // 优先用响应里 Content-Disposition 的 filename；缺失时 fallback 到调用方给的名字。
  let filename = `${fallbackName}.json`;
  const parsedFilename = filenameFromContentDisposition(res.headers.get('Content-Disposition'));
  if (parsedFilename) filename = parsedFilename;
  const blob = await res.blob();
  await saveBlobWithPicker(blob, filename, [
    { description: 'JSON', accept: { 'application/json': ['.json'] } },
  ]);
  return { filename };
}
