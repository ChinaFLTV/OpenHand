// SSE 实时事件流封装（与服务端 GET /api/sessions/:id/events 对齐）。
//
// 设计：
// - EventSource 浏览器内置，支持自动重连；不允许自定义 header，所以我们用
//   query string 传 token / device_id / source。
// - service 推送 `event: snapshot` + JSON payload，含 messages / send_phase /
//   last_error / can_stop / session 摘要。前端消费方按 message id 增量合并。
// - 暴露 `subscribe(...)` 返回 close 句柄，调用方负责在 unmount 时 close。
// - 失败 / 服务端 500 时退化为 polling（由消费方决定）；这里仅把 onError 透出。

import { ensureDeviceId, readToken } from '../state/storage';
import type { SessionMessage, SessionSummary } from './sessions';
import { collectClientEnvironment } from '../utils/client_env';
import { runIgnoringErrors } from '../shared/util/errors';

export interface PendingWriteApproval {
  id: string;
  session_id: string;
  command: string;
  working_directory: string;
  is_write_command: boolean;
  created_at: string;
  expires_at: string;
}

export interface SessionEventSnapshot {
  session: SessionSummary;
  messages: SessionMessage[];
  message_window?: {
    offset: number;
    limit: number;
    total: number;
    has_older?: boolean;
    has_newer?: boolean;
  };
  send_phase: string;
  last_error: string | null;
  can_stop: boolean;
  pending_write_approval?: PendingWriteApproval | null;
  /// 2026-05-17 — 当前会话生效的字符 / 卡片节流速率。chars_per_second
  /// 或 cards_per_second 为 0 表示对应方向的节流被关闭，前端会在 TopBar
  /// 用灰色标记；has_session_override 为 true 时光标侧附加 "session"
  /// 标识便于用户区分覆盖来源。duration_expired 为 true 时表示当前轮次
  /// 节流时长已耗尽，剩余流式响应正按 AI 真实速率追加。
  effective_stream_throttle?: {
    chars_per_second: number;
    cards_per_second: number;
    has_session_override: boolean;
    duration_expired?: boolean;
    /// 2026-05-19 — 启用态：会话级覆盖 > 全局。前端据此渲染 Switch 与
    /// 灰色胶囊。
    enabled?: boolean;
    /// 2026-05-19 — 会话历史上是否曾节流。胶囊可见性所需。
    was_initially_throttled?: boolean;
    /// 2026-05-24 — 字符吞吐 30s 桶（桶 0 = 当前秒），让 Web 端节流弹窗
    /// 渲染和 App 端一致的柱状图。非流式时回填全 0。
    throughput_buckets?: number[];
  };
  served_at: string;
}

export interface SessionDeletedEvent {
  error: 'session_deleted_or_not_found';
  session_id: string;
  served_at: string;
}

export interface SessionEventsHandlers {
  onSnapshot(snapshot: SessionEventSnapshot): void;
  onDeleted?(event: SessionDeletedEvent): void;
  onError(err: Event): void;
  onOpen?(): void;
}

function dispatchParsedEvent<T>(
  event: Event,
  onParsed: (data: T) => void,
  onError: (err: Event) => void,
): void {
  try {
    const data = JSON.parse((event as MessageEvent).data) as T;
    onParsed(data);
  } catch (error) {
    onError(new ErrorEvent('parse_error', { error }));
  }
}

/// 打开 SSE 连接。返回 `close` 句柄；调用方在 unmount/会话切换时务必调用。
export function subscribeSessionEvents(
  sessionId: string,
  handlers: SessionEventsHandlers,
): () => void {
  if (typeof EventSource === 'undefined') {
    // 极端环境（老浏览器 / 测试 jsdom）兜底：立即报错让上层退化轮询。
    queueMicrotask(() => handlers.onError(new Event('eventsource_unavailable')));
    return () => {};
  }
  const params = new URLSearchParams();
  const env = collectClientEnvironment();
  params.set('device_id', ensureDeviceId());
  params.set('source', env.source);
  const token = readToken();
  if (token) params.set('token', token);
  const url = `/api/sessions/${encodeURIComponent(sessionId)}/events?${params.toString()}`;
  const es = new EventSource(url, { withCredentials: false });
  let closed = false;

  const handleSnapshot = (ev: Event) => dispatchParsedEvent<SessionEventSnapshot>(
    ev,
    handlers.onSnapshot,
    handlers.onError,
  );
  const handleDeleted = (ev: Event) => dispatchParsedEvent<SessionDeletedEvent>(
    ev,
    (data) => handlers.onDeleted?.(data),
    handlers.onError,
  );
  const handleOpen = () => handlers.onOpen?.();
  const handleError = (ev: Event) => handlers.onError(ev);

  es.addEventListener('snapshot', handleSnapshot);
  es.addEventListener('session_deleted', handleDeleted);
  es.onopen = handleOpen;
  es.onerror = handleError;
  return () => {
    if (closed) return;
    closed = true;
    es.removeEventListener('snapshot', handleSnapshot);
    es.removeEventListener('session_deleted', handleDeleted);
    es.onopen = null;
    es.onerror = null;
    runIgnoringErrors(() => es.close());
  };
}
