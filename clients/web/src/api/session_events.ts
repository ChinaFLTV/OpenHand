// EventSource 不支持自定义请求头，鉴权与客户端信息通过查询参数传递。

import { ensureDeviceId, readToken } from '../state/storage';
import type { SessionMessage, SessionSummary } from './sessions';
import { collectClientEnvironment } from '../utils/client_env';
import {
  parseJsonBounded,
  type JsonParseBounds,
} from '../shared/util/bounded_json';
import { runIgnoringErrors } from '../shared/util/errors';

const SESSION_EVENT_JSON_BOUNDS: JsonParseBounds = {
  maxCharacters: 16 * 1024 * 1024,
  maxDepth: 64,
  maxContainerItems: 50_000,
  maxNodes: 250_000,
};

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
  /// 当前会话生效的字符 / 卡片节流速率。chars_per_second
  /// 或 cards_per_second 为 0 表示对应方向的节流被关闭，前端会在 TopBar
  /// 用灰色标记；has_session_override 为 true 时光标侧附加 "session"
  /// 标识便于用户区分覆盖来源。duration_expired 为 true 时表示当前轮次
  /// 节流时长已耗尽，剩余流式响应正按 AI 真实速率追加。
  effective_stream_throttle?: {
    chars_per_second: number;
    cards_per_second: number;
    has_session_override: boolean;
    duration_expired?: boolean;
    /// 启用态：会话级覆盖优先于全局设置。
    enabled?: boolean;
    /// 会话历史上是否曾启用节流。
    was_initially_throttled?: boolean;
    /// 字符吞吐 30 秒桶，桶 0 为当前秒；非流式时回填 0。
    throughput_buckets?: number[];
  };
  served_at: string;
}

interface SessionDeletedEvent {
  error: 'session_deleted_or_not_found';
  session_id: string;
  served_at: string;
}

interface SessionEventsHandlers {
  onSnapshot(snapshot: SessionEventSnapshot): void;
  onDeleted?(event: SessionDeletedEvent): void;
  onError(err: Event): void;
  onOpen?(): void;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function isSessionEventSnapshot(value: unknown): value is SessionEventSnapshot {
  if (!isRecord(value)) return false;
  return (
    isRecord(value['session']) &&
    Array.isArray(value['messages']) &&
    typeof value['send_phase'] === 'string' &&
    (typeof value['last_error'] === 'string' || value['last_error'] == null) &&
    typeof value['can_stop'] === 'boolean' &&
    typeof value['served_at'] === 'string'
  );
}

function isSessionDeletedEvent(value: unknown): value is SessionDeletedEvent {
  if (!isRecord(value)) return false;
  return (
    value['error'] === 'session_deleted_or_not_found' &&
    typeof value['session_id'] === 'string' &&
    typeof value['served_at'] === 'string'
  );
}

function dispatchParsedEvent<T>(
  event: Event,
  onParsed: (data: T) => void,
  onError: (err: Event) => void,
): void {
  try {
    const raw = (event as MessageEvent<unknown>).data;
    if (typeof raw !== 'string') throw new TypeError('SSE 事件数据必须是字符串。');
    const data = parseJsonBounded(raw, SESSION_EVENT_JSON_BOUNDS) as T;
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

  const handleSnapshot = (ev: Event) => dispatchParsedEvent<unknown>(
    ev,
    (data) => {
      if (!isSessionEventSnapshot(data)) {
        throw new TypeError('SSE 会话快照结构无效。');
      }
      handlers.onSnapshot(data);
    },
    handlers.onError,
  );
  const handleDeleted = (ev: Event) => dispatchParsedEvent<unknown>(
    ev,
    (data) => {
      if (!isSessionDeletedEvent(data) || data.session_id !== sessionId) {
        throw new TypeError('SSE 会话删除事件结构无效。');
      }
      handlers.onDeleted?.(data);
    },
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
