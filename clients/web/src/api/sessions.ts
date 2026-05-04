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
