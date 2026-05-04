// 单会话详情页：仅承担 GET /api/sessions/:id 与 GET messages 的展示。
//
// Stage 3 范围内不实现发送（POST /api/sessions/:id/messages 留给 Stage 4）。
// 设计要点：
// 1. 首屏拿最新一页（offset=0, limit=80）；列表按 created_at 升序展示。
// 2. 「加载更早」按钮：以当前最早 message 的 offset 增量拉一页，append 到顶部。
// 3. send_phase / last_error 顶部栏展示，作为 Stage 4 的占位。
// 4. 不做轮询；用户切回页面或手动「刷新」触发 refetch。
//
// 服务端契约：
//   GET /api/sessions/:id/messages?limit=&offset= → {items, offset, limit, total, has_more, send_phase, last_error}

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useLocation, useRoute } from 'preact-iso';
import {
  getSession,
  listMessages,
  type SessionDetailResponse,
  type SessionMessage,
} from '../api/sessions';
import { UnauthorizedError } from '../api/client';
import { t } from '../i18n';
import { useAuth } from '../state/auth';

const PAGE_SIZE = 80;

function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  } catch {
    return iso;
  }
}

function roleLabel(role: string): string {
  switch (role) {
    case 'user':
      return t('detail.role.user', '用户');
    case 'assistant':
      return t('detail.role.assistant', '助手');
    case 'system':
      return t('detail.role.system', '系统');
    case 'tool':
      return t('detail.role.tool', '工具');
    default:
      return role;
  }
}

function sendPhaseLabel(phase: string): string {
  switch (phase) {
    case 'idle':
      return t('detail.phase.idle', '空闲');
    case 'sending':
      return t('detail.phase.sending', '发送中');
    case 'awaitingResponse':
    case 'awaiting_response':
      return t('detail.phase.awaiting', '等待响应');
    case 'streaming':
      return t('detail.phase.streaming', '流式接收中');
    case 'finalizing':
      return t('detail.phase.finalizing', '收尾中');
    default:
      return phase;
  }
}

interface RouteParams {
  id?: string;
}

export function SessionDetailPage() {
  const auth = useAuth();
  const location = useLocation();
  const routeMatch = useRoute() as { params?: RouteParams } | undefined;
  const sessionId = routeMatch?.params?.id ?? '';

  const [detail, setDetail] = useState<SessionDetailResponse | null>(null);
  const [messages, setMessages] = useState<SessionMessage[]>([]);
  // total - 已加载条数 = 还能往「更早」加载多少条
  const [totalKnown, setTotalKnown] = useState(0);
  const [loadingDetail, setLoadingDetail] = useState(true);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sendPhase, setSendPhase] = useState<string>('idle');
  const [lastError, setLastError] = useState<string | null>(null);

  const detailAbortRef = useRef<AbortController | null>(null);
  const messagesAbortRef = useRef<AbortController | null>(null);

  function handleAuthError(e: unknown): boolean {
    if (e instanceof UnauthorizedError) {
      location.route('/login', true);
      return true;
    }
    return false;
  }

  function loadDetail(): void {
    if (!sessionId) return;
    detailAbortRef.current?.abort();
    const ctrl = new AbortController();
    detailAbortRef.current = ctrl;
    setLoadingDetail(true);
    setError(null);
    Promise.all([
      getSession(sessionId),
      listMessages(sessionId, { limit: PAGE_SIZE, offset: 0 }),
    ])
      .then(([d, m]) => {
        if (ctrl.signal.aborted) return;
        setDetail(d);
        setMessages([...m.items]);
        setTotalKnown(m.total);
        setSendPhase(m.send_phase || d.runtime.send_phase || 'idle');
        setLastError(m.last_error ?? d.runtime.last_error ?? null);
        setLoadingDetail(false);
      })
      .catch((e: unknown) => {
        if (ctrl.signal.aborted) return;
        if (handleAuthError(e)) return;
        setError(e instanceof Error ? e.message : String(e));
        setLoadingDetail(false);
      });
  }

  async function refresh(): Promise<void> {
    if (!sessionId || refreshing) return;
    setRefreshing(true);
    try {
      const m = await listMessages(sessionId, { limit: PAGE_SIZE, offset: 0 });
      setMessages([...m.items]);
      setTotalKnown(m.total);
      setSendPhase(m.send_phase);
      setLastError(m.last_error);
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRefreshing(false);
    }
  }

  async function loadOlder(): Promise<void> {
    if (loadingOlder) return;
    if (messages.length >= totalKnown) return;
    setLoadingOlder(true);
    try {
      const m = await listMessages(sessionId, {
        limit: PAGE_SIZE,
        offset: messages.length,
      });
      setMessages((prev) => [...m.items, ...prev]);
      setTotalKnown(m.total);
      setSendPhase(m.send_phase);
      setLastError(m.last_error);
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoadingOlder(false);
    }
  }

  useEffect(() => {
    if (auth.loading) return;
    if (!sessionId) return;
    loadDetail();
    return () => {
      detailAbortRef.current?.abort();
      messagesAbortRef.current?.abort();
    };
  }, [auth.loading, sessionId]);

  const session = detail?.session;
  const remainingOlder = Math.max(0, totalKnown - messages.length);

  // 注意：服务端按 created_at 升序返回（store loadMessages 默认升序），
  // 直接渲染即是「上旧下新」。如果出现倒序问题，这里做一次按 created_at 排序兜底。
  const sortedMessages = useMemo(() => {
    return [...messages].sort((a, b) => {
      const ta = new Date(a.created_at).getTime();
      const tb = new Date(b.created_at).getTime();
      if (Number.isNaN(ta) || Number.isNaN(tb)) return 0;
      return ta - tb;
    });
  }, [messages]);

  if (!sessionId) {
    return (
      <main class="min-h-screen flex items-center justify-center">
        <p class="text-sm" style={{ color: 'var(--m3-error)' }}>
          {t('detail.missingId', '缺少会话 ID')}
        </p>
      </main>
    );
  }

  return (
    <main class="min-h-screen px-6 py-8" style={{ background: 'var(--m3-surface)' }}>
      <div class="mx-auto max-w-3xl">
        {/* 顶部条 */}
        <div class="flex items-start justify-between mb-4 gap-3">
          <div class="flex-1 min-w-0">
            <button
              type="button"
              onClick={() => location.route('/threads')}
              class="text-xs underline mb-2"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              ← {t('detail.backToList', '返回会话列表')}
            </button>
            <h1
              class="text-xl font-semibold truncate"
              style={{ color: 'var(--m3-on-surface)' }}
            >
              {session?.title || t('sessions.untitled', '未命名会话')}
            </h1>
            {session ? (
              <p
                class="text-xs mt-1"
                style={{ color: 'var(--m3-on-surface-variant)' }}
              >
                {session.template_name || session.template_id} ·{' '}
                {session.mode === 'plan'
                  ? t('sessions.mode.plan', 'Plan')
                  : t('sessions.mode.chat', '对话')}{' '}
                · {totalKnown} {t('sessions.messageUnit', '条消息')}
              </p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={refresh}
            disabled={refreshing || loadingDetail}
            class="text-xs px-3 py-1.5 rounded-md disabled:opacity-50"
            style={{
              border: '1px solid var(--m3-outline)',
              color: 'var(--m3-on-surface)',
            }}
          >
            {refreshing ? t('detail.refreshing', '刷新中…') : t('detail.refresh', '刷新')}
          </button>
        </div>

        {/* 状态条 */}
        <div
          class="rounded-md px-3 py-2 mb-4 text-xs flex items-center justify-between"
          style={{
            background: 'var(--m3-surface-container)',
            color: 'var(--m3-on-surface-variant)',
          }}
        >
          <span>
            {t('detail.phase.label', '当前状态：')}
            <strong style={{ color: 'var(--m3-on-surface)' }}>
              {sendPhaseLabel(sendPhase)}
            </strong>
          </span>
          {lastError ? (
            <span style={{ color: 'var(--m3-error)' }}>
              {t('detail.lastError', '最近错误：')}
              {lastError}
            </span>
          ) : null}
        </div>

        {/* 主区 */}
        {loadingDetail ? (
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t('detail.loading', '加载会话中…')}
          </p>
        ) : error ? (
          <div
            class="rounded-md p-4 text-sm"
            style={{
              background: 'var(--m3-surface-container)',
              color: 'var(--m3-error)',
            }}
          >
            {error}
            <button
              type="button"
              onClick={loadDetail}
              class="ml-3 underline"
            >
              {t('sessions.retry', '重试')}
            </button>
          </div>
        ) : (
          <>
            {/* 加载更早 */}
            {remainingOlder > 0 ? (
              <div class="text-center mb-3">
                <button
                  type="button"
                  onClick={loadOlder}
                  disabled={loadingOlder}
                  class="text-xs px-3 py-1.5 rounded-md disabled:opacity-50"
                  style={{
                    border: '1px solid var(--m3-outline)',
                    color: 'var(--m3-on-surface-variant)',
                  }}
                >
                  {loadingOlder
                    ? t('detail.loadingOlder', '加载中…')
                    : t('detail.loadOlder', '加载更早 ') +
                      `(${remainingOlder})`}
                </button>
              </div>
            ) : null}

            {sortedMessages.length === 0 ? (
              <p
                class="text-center py-12 text-sm"
                style={{ color: 'var(--m3-on-surface-variant)' }}
              >
                {t('detail.empty', '该会话尚无消息。')}
              </p>
            ) : (
              <ul class="flex flex-col gap-3">
                {sortedMessages.map((m) => {
                  const isUser = m.role === 'user';
                  return (
                    <li
                      key={m.id}
                      class="rounded-xl p-4"
                      style={{
                        background: isUser
                          ? 'var(--m3-primary)'
                          : 'var(--m3-surface-container)',
                        color: isUser
                          ? 'var(--m3-on-primary)'
                          : 'var(--m3-on-surface)',
                        boxShadow: 'var(--m3-elev-1)',
                      }}
                    >
                      <div class="flex items-center justify-between text-xs mb-2 opacity-80">
                        <span>
                          {roleLabel(m.role)}
                          {m.kind && m.kind !== 'text'
                            ? ` · ${m.kind}`
                            : ''}
                          {m.model_label ? ` · ${m.model_label}` : ''}
                        </span>
                        <span>{formatTimestamp(m.created_at)}</span>
                      </div>
                      <pre
                        class="whitespace-pre-wrap break-words text-sm font-sans"
                        style={{ margin: 0 }}
                      >
                        {m.content}
                      </pre>
                    </li>
                  );
                })}
              </ul>
            )}
          </>
        )}

        {/* Stage 4 占位 */}
        <div
          class="mt-6 rounded-md p-3 text-xs text-center"
          style={{
            background: 'var(--m3-surface-container)',
            color: 'var(--m3-on-surface-variant)',
          }}
        >
          {t('detail.stage4Placeholder', 'Stage 4 即将上线：消息发送（多类型 + 流式）。')}
        </div>
      </div>
    </main>
  );
}
