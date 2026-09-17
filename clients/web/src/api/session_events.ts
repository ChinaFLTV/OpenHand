// EventSource 不支持自定义请求头，鉴权与客户端信息通过查询参数传递。

import { captureAuthSession, ensureDeviceId, readToken } from '../state/storage';
import type { SessionMessage, SessionSummary } from './sessions';
import { collectClientEnvironment } from '../utils/client_env';
import {
  parseJsonBounded,
  type JsonParseBounds,
} from '../shared/util/bounded_json';
import { runIgnoringErrors } from '../shared/util/errors';
import { recordOrNullFromUnknown } from '../shared/util/value';

const SESSION_EVENT_JSON_BOUNDS: JsonParseBounds = {
  maxCharacters: 16 * 1024 * 1024,
  maxDepth: 64,
  maxContainerItems: 50_000,
  maxNodes: 250_000,
};
const SESSION_MESSAGE_TEXT_FIELDS = ['id', 'kind', 'role', 'content', 'created_at'] as const;

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

function isSessionEventSnapshot(value: unknown): value is SessionEventSnapshot {
  const record = recordOrNullFromUnknown(value);
  if (!record) return false;
  const session = recordOrNullFromUnknown(record['session']);
  return (
    typeof session?.['id'] === 'string' &&
    Array.isArray(record['messages']) &&
    record['messages'].every((message: unknown) => {
      const item = recordOrNullFromUnknown(message);
      return item != null &&
        SESSION_MESSAGE_TEXT_FIELDS.every(
          (key) => typeof item[key] === 'string',
        ) && typeof item['character_count'] === 'number' &&
        Number.isFinite(item['character_count']);
    }) &&
    typeof record['send_phase'] === 'string' &&
    (typeof record['last_error'] === 'string' || record['last_error'] == null) &&
    typeof record['can_stop'] === 'boolean' &&
    typeof record['served_at'] === 'string'
  );
}

function isSessionDeletedEvent(value: unknown): value is SessionDeletedEvent {
  const record = recordOrNullFromUnknown(value);
  if (!record) return false;
  return (
    record['error'] === 'session_deleted_or_not_found' &&
    typeof record['session_id'] === 'string' &&
    typeof record['served_at'] === 'string'
  );
}

function dispatchParsedEvent<T>(
  event: Event,
  validate: (data: unknown) => data is T,
  onParsed: (data: T) => void,
  onError: (err: Event) => void,
): void {
  let data: T;
  try {
    const raw = (event as MessageEvent<unknown>).data;
    if (typeof raw !== 'string') throw new TypeError('SSE 事件数据必须是字符串。');
    const parsed = parseJsonBounded(raw, SESSION_EVENT_JSON_BOUNDS);
    if (!validate(parsed)) throw new TypeError('SSE 事件结构或会话标识无效。');
    data = parsed;
  } catch (error) {
    reportEventError(onError, 'parse_error', error);
    return;
  }
  try {
    onParsed(data);
  } catch (error) {
    reportEventError(onError, 'handler_error', error);
  }
}

function reportEventError(
  onError: (err: Event) => void,
  type: string,
  error: unknown,
): void {
  // 业务回调属于外部代码，异常不能打断 EventSource 的事件分发循环。
  runIgnoringErrors(() => onError(new ErrorEvent(type, { error })));
}

/// 打开 SSE 连接。返回 `close` 句柄；调用方在 unmount/会话切换时务必调用。
export function subscribeSessionEvents(
  sessionId: string,
  handlers: SessionEventsHandlers,
): () => void {
  let closed = false;
  const normalizedSessionId = sessionId.trim();
  if (!normalizedSessionId) {
    queueMicrotask(() => {
      if (!closed) {
        reportEventError(
          handlers.onError,
          'invalid_session_id',
          new TypeError('SSE 会话标识不能为空。'),
        );
      }
    });
    return () => {
      closed = true;
    };
  }
  const params = new URLSearchParams();
  const isCurrentSession = captureAuthSession();
  const env = collectClientEnvironment();
  params.set('device_id', ensureDeviceId());
  params.set('source', env.source);
  const token = readToken();
  if (token) params.set('token', token);
  const url = `/api/sessions/${encodeURIComponent(normalizedSessionId)}/events?${params.toString()}`;
  let es: EventSource;
  try {
    es = new EventSource(url, { withCredentials: false });
  } catch (error) {
    // 不支持 SSE 或构造失败时交给轮询兜底；卸载后不再投递错误。
    queueMicrotask(() => {
      if (!closed && isCurrentSession()) {
        reportEventError(handlers.onError, 'eventsource_unavailable', error);
      }
    });
    return () => { closed = true; };
  }

  const isActive = () => {
    if (closed) return false;
    if (isCurrentSession()) return true;
    close();
    return false;
  };
  const handleSnapshot = (ev: Event) => isActive() && dispatchParsedEvent(
    ev,
    (data): data is SessionEventSnapshot =>
      isSessionEventSnapshot(data) && data.session.id === normalizedSessionId,
    handlers.onSnapshot,
    handlers.onError,
  );
  const handleDeleted = (ev: Event) => isActive() && dispatchParsedEvent(
    ev,
    (data): data is SessionDeletedEvent =>
      isSessionDeletedEvent(data) && data.session_id === normalizedSessionId,
    (data) => handlers.onDeleted?.(data),
    handlers.onError,
  );
  const handleOpen = () => {
    if (!isActive()) return;
    try {
      handlers.onOpen?.();
    } catch (error) {
      reportEventError(handlers.onError, 'handler_error', error);
    }
  };
  const handleError = (ev: Event) => {
    if (isActive()) runIgnoringErrors(() => handlers.onError(ev));
  };

  es.addEventListener('snapshot', handleSnapshot);
  es.addEventListener('session_deleted', handleDeleted);
  es.onopen = handleOpen;
  es.onerror = handleError;
  function close() {
    if (closed) return;
    closed = true;
    es.removeEventListener('snapshot', handleSnapshot);
    es.removeEventListener('session_deleted', handleDeleted);
    es.onopen = null;
    es.onerror = null;
    runIgnoringErrors(() => es.close());
  }
  return close;
}
