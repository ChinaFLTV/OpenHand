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

import { apiRequest } from './client';
import { ensureDeviceId, readToken } from '../state/storage';

export interface SessionTodoItem {
  id: string;
  content: string;
  status: string;
}

export interface SessionSummary {
  id: string;
  title: string;
  template_id: string;
  template_name?: string;
  created_at: string;
  updated_at: string;
  mode: 'chat' | 'plan' | string;
  message_count: number;
  last_message_preview: string;
  last_message_kind?: string;
  send_phase: string;
  source?: string;
  device_id?: string;
  metadata?: Record<string, unknown>;
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
  send_phase: string;
  last_error: string | null;
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
}

export function listMessages(
  sessionId: string,
  options: ListMessagesOptions = {},
): Promise<SessionMessagesResponse> {
  const params = new URLSearchParams();
  if (options.limit != null) params.set('limit', String(options.limit));
  if (options.offset != null) params.set('offset', String(options.offset));
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

/// 触发会话 JSON 导出下载。在 service 端附带 Content-Disposition: attachment，
/// 这里直接抓 blob 后用 a[download] 触发浏览器保存对话框；不绕过鉴权（带上 token）。
export async function exportSessionDownload(sessionId: string, fallbackName: string): Promise<void> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'x-openhand-device-id': ensureDeviceId(),
    'x-openhand-source': 'WEB_PC',
  };
  const token = readToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}/export`, {
    method: 'GET',
    headers,
    credentials: 'same-origin',
  });
  if (res.status === 401) {
    throw new Error('UNAUTHORIZED');
  }
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  // 优先用响应里 Content-Disposition 的 filename；缺失时 fallback 到调用方给的名字。
  let filename = `${fallbackName}.json`;
  const cd = res.headers.get('Content-Disposition') ?? '';
  const match = /filename="?([^";]+)"?/i.exec(cd);
  if (match && match[1]) filename = match[1];
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
  } finally {
    // 给浏览器一次机会发起下载，再回收 URL；500ms 经验值足够覆盖 click→保存路径。
    setTimeout(() => URL.revokeObjectURL(url), 500);
  }
}
