// 单会话详情页：会话头 / 消息分页 / Composer 发送（Stage 4 接入）。
//
// 设计要点：
// 1. 首屏拿最新一页（offset=0, limit=80）；列表按 created_at 升序展示。
// 2. 「加载更早」按钮：以当前已加载条数为 offset 增量拉一页，append 到顶部。
// 3. 发送：POST /api/sessions/:id/messages 形成 user 消息；service 自身维护流式，
//    前端进入 1.2s 轮询循环刷新最新一页，直到 send_phase == idle。
// 4. 停止：POST /api/sessions/:id/stop（service 内部调用 AiSessionController.stopResponding）。
// 5. 附件：用 FileReader.readAsDataURL 读出 base64，去掉 `data:*;base64,` 前缀后塞入
//    {name, data_base64} 数组；service 端会落到 upload-cache。
//
// 服务端契约：
//   GET   /api/sessions/:id
//   GET   /api/sessions/:id/messages?limit=&offset= → {items, offset, limit, total, has_more, send_phase, last_error}
//   POST  /api/sessions/:id/messages  body {content, mode, model_key, attachments}
//   POST  /api/sessions/:id/stop     body {}

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useLocation, useRoute } from 'preact-iso';
import {
  deleteSession,
  exportSessionDownload,
  getSession,
  listMessages,
  renameSession,
  sendMessage,
  stopMessage,
  type SendMessageAttachment,
  type SessionDetailResponse,
  type SessionMessage,
} from '../api/sessions';
import { ApiError, UnauthorizedError } from '../api/client';
import { subscribeSessionEvents } from '../api/session_events';
import { t } from '../i18n';
import { MenuSelect } from '../components/MenuSelect';
import { useAuth } from '../state/auth';
import type { ApiMetaModel } from '../api/meta';
import { TopBar } from '../components/TopBar';
import { MessageCard } from '../components/MessageCard';
import {
  SessionTopBar,
  type PermissionMode,
} from '../components/SessionTopBar';
import { pushRecentModel } from '../components/ModelPickerDialog';

const PAGE_SIZE = 80;

/// 助手回复期间的轮询间隔。仅作为 SSE 失败时的兜底；正常路径走 SSE 实时推送。
const POLL_INTERVAL_MS = 1500;

/// SSE 连续失败 N 次以上才彻底切到 polling，避免短暂网络抖动造成体验切换。
const SSE_FAIL_THRESHOLD = 3;

/// 单条附件最大字节数（沿用 service singleMessageTokenLimit 的语义留 1 MiB 兜底）；
/// 真正的硬上限以 service 端响应为准。
const ATTACHMENT_MAX_BYTES = 8 * 1024 * 1024;

// 时间戳与角色标签现在由 MessageCard 内部处理，本页不再直接使用。

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

  // Composer state
  const [composerText, setComposerText] = useState<string>('');
  const [composerMode, setComposerMode] = useState<string>('normal');
  const [composerModelKey, setComposerModelKey] = useState<string>('');
  const [composerAttachments, setComposerAttachments] =
    useState<SendMessageAttachment[]>([]);
  // 附件预览 (image/* → dataURL); key 与 composerAttachments 同序
  const [attachmentPreviews, setAttachmentPreviews] = useState<
    { mime: string; dataUrl: string; size: number }[]
  >([]);
  const [dragOver, setDragOver] = useState<boolean>(false);
  const [composerSending, setComposerSending] = useState<boolean>(false);
  const [composerError, setComposerError] = useState<string | null>(null);
  const [stopping, setStopping] = useState<boolean>(false);
  const [permissionMode, setPermissionMode] = useState<PermissionMode>('ask');

  const detailAbortRef = useRef<AbortController | null>(null);
  const messagesAbortRef = useRef<AbortController | null>(null);
  const pollTimerRef = useRef<number | null>(null);
  const sseCloseRef = useRef<(() => void) | null>(null);
  const sseFailRef = useRef<number>(0);
  const [sseLive, setSseLive] = useState<boolean>(false);

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
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
      sseCloseRef.current?.();
      sseCloseRef.current = null;
    };
  }, [auth.loading, sessionId]);

  // SSE 实时事件流：用 service 推送替代轮询，覆盖：
  //   1. AI 流式增量（assistant 消息每次 delta 都会触发一次 snapshot）；
  //   2. 跨端口同步（APP 端在同一会话发的消息也会推到 web）；
  //   3. send_phase / last_error 实时更新。
  // 失败 SSE_FAIL_THRESHOLD 次后切换到 polling 兜底。
  useEffect(() => {
    if (auth.loading || !sessionId) return;
    sseCloseRef.current?.();
    sseFailRef.current = 0;
    setSseLive(false);
    const close = subscribeSessionEvents(sessionId, {
      onOpen: () => {
        sseFailRef.current = 0;
        setSseLive(true);
      },
      onSnapshot: (snap) => {
        // 整张快照覆盖：与 service displayMessages 顺序保持一致；offset/分页
        // 「加载更早」的尾巴单独保留——snap.messages 只覆盖最新一页之外的旧消息
        // 也会一并到来（service 端给的是当前 displayMessages 的全部 in-memory），
        // 因此这里直接全量替换，不再拼接旧前缀。
        setMessages([...snap.messages]);
        setTotalKnown(snap.session.message_count ?? snap.messages.length);
        setSendPhase(snap.send_phase);
        setLastError(snap.last_error);
      },
      onError: () => {
        sseFailRef.current += 1;
        if (sseFailRef.current >= SSE_FAIL_THRESHOLD) {
          setSseLive(false);
        }
      },
    });
    sseCloseRef.current = close;
    return () => {
      close();
      sseCloseRef.current = null;
    };
  }, [auth.loading, sessionId]);

  // 模型/模式默认值与 meta 同步：拿到 meta.models 第一项做默认；模式取 meta.conversation_modes
  // 第一项（通常是 normal）作为默认。
  const meta = auth.meta;
  const allowedModels = useMemo<ApiMetaModel[]>(
    () => meta?.models ?? [],
    [meta],
  );
  const allowedModes = useMemo<string[]>(
    () => meta?.conversation_modes ?? ['normal'],
    [meta],
  );
  const allowedMessageTypes = useMemo<string[]>(
    () => meta?.message_types ?? ['text', 'attachment'],
    [meta],
  );
  const attachmentsAllowed = allowedMessageTypes.includes('attachment');
  const textAllowed = allowedMessageTypes.includes('text');

  useEffect(() => {
    if (!composerModelKey && allowedModels.length > 0) {
      setComposerModelKey(allowedModels[0]!.key);
    }
  }, [allowedModels]);

  useEffect(() => {
    if (allowedModes.length > 0 && !allowedModes.includes(composerMode)) {
      setComposerMode(allowedModes[0]!);
    }
  }, [allowedModes]);

  // 轮询：仅作 SSE 兜底——若 SSE 实时通道存活则跳过；否则在助手回复期间
  // 每 1.5s 拉一次最新一页 + send_phase，避免 SSE 故障下用户永远看不到更新。
  // 用 setTimeout 自驱动而非 setInterval，避免漂移与未完成请求叠加。
  useEffect(() => {
    if (auth.loading || !sessionId) return;
    if (sseLive) {
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
      return;
    }
    const isRunning = sendPhase !== 'idle' && sendPhase !== '';
    if (!isRunning) {
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
      return;
    }
    let cancelled = false;
    async function tick(): Promise<void> {
      try {
        const m = await listMessages(sessionId, {
          limit: PAGE_SIZE,
          offset: 0,
        });
        if (cancelled) return;
        // 只覆盖最新一页；不动「加载更早」拉过来的尾巴。
        setMessages((prev) => {
          if (prev.length <= m.items.length) return [...m.items];
          // 已加载更多历史 → 用旧的前缀 + 最新一页
          const tail = prev.slice(0, prev.length - m.items.length);
          return [...tail, ...m.items];
        });
        setTotalKnown(m.total);
        setSendPhase(m.send_phase);
        setLastError(m.last_error);
      } catch (e: unknown) {
        if (cancelled) return;
        if (handleAuthError(e)) return;
        setLastError(e instanceof Error ? e.message : String(e));
      }
      if (!cancelled) {
        pollTimerRef.current = window.setTimeout(tick, POLL_INTERVAL_MS);
      }
    }
    pollTimerRef.current = window.setTimeout(tick, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
  }, [auth.loading, sessionId, sendPhase, sseLive]);

  async function readFileAsAttachment(
    file: File,
  ): Promise<{ att: SendMessageAttachment; mime: string; dataUrl: string }> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result;
        if (typeof result !== 'string') {
          reject(new Error('reader.result not string'));
          return;
        }
        const idx = result.indexOf('base64,');
        const data = idx >= 0 ? result.substring(idx + 'base64,'.length) : '';
        if (!data) {
          reject(new Error('empty base64 payload'));
          return;
        }
        const mime = file.type || (idx > 0
          ? result.substring(5, result.indexOf(';'))
          : 'application/octet-stream');
        resolve({
          att: { name: file.name, data_base64: data },
          mime,
          dataUrl: result,
        });
      };
      reader.onerror = () => reject(reader.error ?? new Error('FileReader failed'));
      reader.readAsDataURL(file);
    });
  }

  // 从 File[] 追加附件。共用与 file input / drag-drop / paste
  async function appendFiles(files: File[]): Promise<void> {
    if (files.length === 0) return;
    setComposerError(null);
    const nextAtt: SendMessageAttachment[] = [...composerAttachments];
    const nextPv: { mime: string; dataUrl: string; size: number }[] = [
      ...attachmentPreviews,
    ];
    for (const file of files) {
      if (file.size > ATTACHMENT_MAX_BYTES) {
        setComposerError(
          t('composer.attachment.tooLarge', '附件超过 ') +
            (ATTACHMENT_MAX_BYTES / (1024 * 1024)).toFixed(0) +
            ' MiB',
        );
        continue;
      }
      try {
        const r = await readFileAsAttachment(file);
        nextAtt.push(r.att);
        nextPv.push({ mime: r.mime, dataUrl: r.dataUrl, size: file.size });
      } catch (e: unknown) {
        setComposerError(
          t('composer.attachment.readFailed', '附件读取失败：') +
            (e instanceof Error ? e.message : String(e)),
        );
      }
    }
    setComposerAttachments(nextAtt);
    setAttachmentPreviews(nextPv);
  }

  async function handleAttachmentInput(ev: Event): Promise<void> {
    const input = ev.currentTarget as HTMLInputElement;
    const files = input.files ? Array.from(input.files) : [];
    input.value = '';
    await appendFiles(files);
  }

  function removeAttachmentAt(idx: number): void {
    setComposerAttachments((prev) => prev.filter((_, i) => i !== idx));
    setAttachmentPreviews((prev) => prev.filter((_, i) => i !== idx));
  }

  async function handleSend(): Promise<void> {
    if (composerSending) return;
    // 单一发送通道：service 仍在跑助手回复时禁止前端再发，避免并发触发同一
    // 会话的 _sessionController.sendMessage（即使 service 自身有兜底，前端也
    // 应在按钮层就拦截，避免 409 与不必要的 round-trip）。
    if (sendPhase !== 'idle' && sendPhase !== '') {
      setComposerError(t('composer.error.busy', '助手正在回复，请等待完成或先停止响应'));
      return;
    }
    const text = composerText.trim();
    if (!text && composerAttachments.length === 0) {
      setComposerError(t('composer.error.empty', '请输入内容或添加附件'));
      return;
    }
    if (text && !textAllowed) {
      setComposerError(t('composer.error.textNotAllowed', '当前 service 禁用了文本消息'));
      return;
    }
    if (composerAttachments.length > 0 && !attachmentsAllowed) {
      setComposerError(t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件'));
      return;
    }
    if (!composerModelKey) {
      setComposerError(t('composer.error.modelMissing', '请选择模型'));
      return;
    }
    setComposerSending(true);
    setComposerError(null);
    try {
      const res = await sendMessage(sessionId, {
        content: text,
        modelKey: composerModelKey,
        mode: composerMode,
        attachments: composerAttachments,
      });
      setComposerText('');
      setComposerAttachments([]);
      setAttachmentPreviews([]);
      setSendPhase(res.send_phase || 'sendingMessage');
      // SSE 通道在 service 端立即推送 user 消息落库；若 SSE 不可用，refresh()
      // 兜底拉一次让 user 消息出现在尾部。
      if (!sseLive) void refresh();
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      if (e instanceof ApiError) {
        const body = e.body as { error?: string } | null;
        setComposerError(
          t('composer.error.send', '发送失败：HTTP ') +
            String(e.status) +
            (body?.error ? ` (${body.error})` : ''),
        );
      } else {
        setComposerError(
          t('composer.error.send', '发送失败：HTTP ') +
            (e instanceof Error ? e.message : String(e)),
        );
      }
    } finally {
      setComposerSending(false);
    }
  }

  async function handleStop(): Promise<void> {
    if (stopping) return;
    setStopping(true);
    try {
      const res = await stopMessage(sessionId);
      setSendPhase(res.send_phase || 'idle');
      // 拉一次让 finalize 后的内容立刻可见
      void refresh();
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      setLastError(e instanceof Error ? e.message : String(e));
    } finally {
      setStopping(false);
    }
  }

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

  const subtitle = session
    ? `${session.template_name || session.template_id} · ${
        session.mode === 'plan'
          ? t('sessions.mode.plan', 'Plan')
          : t('sessions.mode.chat', '对话')
      } · ${totalKnown} ${t('sessions.messageUnit', '条消息')}`
    : t('detail.loading', '加载会话中…');

  return (
    <main class="min-h-screen px-6 py-8" style={{ background: 'var(--m3-surface)' }}>
      <div class="mx-auto max-w-3xl">
        {/* 全局 TopBar (品牌/语言/导航) — 独立于会话操作 */}
        <TopBar compact subtitle="" />
        <SessionTopBar
          title={session?.title || t('sessions.untitled', '未命名会话')}
          subtitle={subtitle}
          onBack={() => location.route('/threads')}
          onRename={async (next) => {
            try {
              const res = await renameSession(sessionId, next);
              setDetail((prev) =>
                prev ? { ...prev, session: res.session } : prev,
              );
            } catch (e) {
              if (handleAuthError(e)) return;
              setLastError(e instanceof Error ? e.message : String(e));
            }
          }}
          modes={allowedModes}
          mode={composerMode}
          onModeChange={setComposerMode}
          models={allowedModels}
          modelKey={composerModelKey}
          onModelChange={(k) => {
            setComposerModelKey(k);
            pushRecentModel(k);
          }}
          permissionMode={permissionMode}
          onPermissionChange={setPermissionMode}
          sendPhase={sendPhase}
          canStop={detail?.runtime.can_stop ?? sendPhase !== 'idle'}
          stopping={stopping}
          onStop={handleStop}
          onDelete={async () => {
            if (!sessionId) return;
            if (!window.confirm(t('topbar.deleteConfirm', '确定删除该会话?此操作不可恢复'))) {
              return;
            }
            try {
              await deleteSession(sessionId);
              location.route('/threads');
            } catch (e) {
              if (handleAuthError(e)) return;
              setLastError(e instanceof Error ? e.message : String(e));
            }
          }}
          onExport={async () => {
            try {
              await exportSessionDownload(
                sessionId,
                session?.title || sessionId,
              );
            } catch (e) {
              if (handleAuthError(e)) return;
              setLastError(e instanceof Error ? e.message : String(e));
            }
          }}
          sessionId={sessionId}
          trailing={
            <button
              type="button"
              onClick={refresh}
              disabled={refreshing || loadingDetail}
              class="oh-tap-press text-xs px-2.5 py-1 rounded-m3-sm disabled:opacity-50"
              style={{
                border: '1px solid var(--m3-outline)',
                color: 'var(--m3-on-surface-variant)',
              }}
              title={t('detail.refresh', '刷新')}
            >
              {refreshing ? '↻…' : '↻'}
            </button>
          }
        />

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
            <span
              class="ml-2 inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
              style={{
                background: sseLive
                  ? 'color-mix(in srgb, #2ecc71 18%, transparent)'
                  : 'color-mix(in srgb, var(--m3-on-surface-variant) 14%, transparent)',
                color: sseLive
                  ? '#1e8e3e'
                  : 'var(--m3-on-surface-variant)',
              }}
              title={sseLive
                ? t('detail.sse.live.hint', '已接入实时事件流，无需轮询')
                : t('detail.sse.fallback.hint', 'SSE 未连通，已退化为轮询')}
            >
              <span aria-hidden>{sseLive ? '●' : '○'}</span>
              <span>{sseLive
                ? t('detail.sse.live', '实时')
                : t('detail.sse.fallback', '轮询')}</span>
            </span>
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
                {sortedMessages.map((m) => (
                  <li key={m.id}>
                    <MessageCard message={m} />
                  </li>
                ))}
              </ul>
            )}
          </>
        )}

        {/* Composer */}
        <section
          class="mt-6 rounded-xl p-4"
          style={{
            background: 'var(--m3-surface-container)',
            boxShadow: 'var(--m3-elev-1)',
          }}
        >
          <div class="flex flex-wrap gap-3 mb-2">
            <label
              class="flex flex-col text-xs gap-1"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {t('composer.model', '模型')}
              <MenuSelect
                value={composerModelKey}
                onChange={setComposerModelKey}
                disabled={composerSending || allowedModels.length === 0}
                minWidth={240}
                options={
                  allowedModels.length === 0
                    ? [{ value: '', label: t('composer.modelEmpty', '主控制台未配置模型') }]
                    : allowedModels.map((m) => ({ value: m.key, label: `${m.provider} · ${m.label}` }))
                }
              />
            </label>
            <label
              class="flex flex-col text-xs gap-1"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {t('composer.mode', '模式')}
              <MenuSelect
                value={composerMode}
                onChange={setComposerMode}
                disabled={composerSending}
                minWidth={160}
                options={allowedModes.map((m) => ({
                  value: m,
                  label: m === 'normal'
                    ? t('composer.mode.normal', '普通')
                    : m === 'plan'
                      ? t('composer.mode.plan', 'Plan')
                      : m === 'image'
                        ? t('composer.mode.image', '图像')
                        : m === 'video'
                          ? t('composer.mode.video', '视频')
                          : m === 'audio'
                            ? t('composer.mode.audio', '音频')
                            : m,
                }))}
              />
            </label>
          </div>

          <div
            class="relative"
            onDragOver={(e) => {
              if (!attachmentsAllowed) return;
              if (Array.from(e.dataTransfer?.types ?? []).includes('Files')) {
                e.preventDefault();
                if (!dragOver) setDragOver(true);
              }
            }}
            onDragLeave={(e) => {
              if (e.currentTarget === e.target) setDragOver(false);
            }}
            onDrop={(e) => {
              if (!attachmentsAllowed) return;
              e.preventDefault();
              setDragOver(false);
              const files = Array.from(e.dataTransfer?.files ?? []);
              if (files.length > 0) void appendFiles(files);
            }}
          >
          <textarea
            value={composerText}
            onInput={(e) =>
              setComposerText((e.currentTarget as HTMLTextAreaElement).value)
            }
            onPaste={(e) => {
              if (!attachmentsAllowed) return;
              const items = e.clipboardData?.items;
              if (!items) return;
              const files: File[] = [];
              for (const it of Array.from(items)) {
                if (it.kind === 'file') {
                  const f = it.getAsFile();
                  if (f) files.push(f);
                }
              }
              if (files.length > 0) {
                e.preventDefault();
                void appendFiles(files);
              }
            }}
            onKeyDown={(e) => {
              // Cmd/Ctrl + Enter 发送
              if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
                e.preventDefault();
                void handleSend();
              }
            }}
            disabled={composerSending}
            rows={4}
            placeholder={t('composer.placeholder', '输入消息（Cmd/Ctrl + Enter 发送）')}
            class="w-full px-3 py-2 rounded-md text-sm"
            style={{
              background: 'var(--m3-surface)',
              color: 'var(--m3-on-surface)',
              border: '1px solid var(--m3-outline)',
              resize: 'vertical',
              fontFamily: 'inherit',
            }}
          />
          {dragOver ? (
            <div
              class="absolute inset-0 rounded-md flex items-center justify-center text-sm pointer-events-none oh-appear-up"
              style={{
                background: 'color-mix(in srgb, var(--m3-primary) 14%, transparent)',
                border: '2px dashed var(--m3-primary)',
                color: 'var(--m3-primary)',
                fontWeight: 600,
              }}
            >
              {t('composer.attachment.drop', '松开即可添加附件')}
            </div>
          ) : null}
          </div>

          {/* 附件 */}
          {attachmentsAllowed ? (
            <div class="mt-2">
              <div class="flex items-center gap-2 mb-1">
                <label
                  class="text-xs px-2 py-1 rounded-md cursor-pointer"
                  style={{
                    border: '1px solid var(--m3-outline)',
                    color: 'var(--m3-on-surface-variant)',
                  }}
                >
                  {t('composer.attachment.add', '添加附件')}
                  <input
                    type="file"
                    multiple
                    onChange={handleAttachmentInput}
                    style={{ display: 'none' }}
                  />
                </label>
                {composerAttachments.length > 0 ? (
                  <span
                    class="text-xs"
                    style={{ color: 'var(--m3-on-surface-variant)' }}
                  >
                    {composerAttachments.length}{' '}
                    {t('composer.attachment.unit', '个附件')}
                  </span>
                ) : null}
              </div>
              {composerAttachments.length > 0 ? (
                <ul class="flex flex-wrap gap-2">
                  {composerAttachments.map((att, i) => {
                    const pv = attachmentPreviews[i];
                    const isImage = (pv?.mime ?? '').startsWith('image/');
                    const sizeKb = pv ? (pv.size / 1024).toFixed(1) : '';
                    return (
                      <li
                        key={`${att.name}-${i}`}
                        class="text-xs rounded-md flex items-center gap-2 overflow-hidden"
                        style={{
                          background: 'var(--m3-surface)',
                          border: '1px solid var(--m3-outline)',
                          color: 'var(--m3-on-surface)',
                          padding: isImage ? '4px 6px 4px 4px' : '4px 8px',
                        }}
                      >
                        {isImage && pv ? (
                          <img
                            src={pv.dataUrl}
                            alt={att.name}
                            decoding="async"
                            loading="lazy"
                            style={{
                              width: '36px',
                              height: '36px',
                              objectFit: 'cover',
                              borderRadius: '4px',
                              flex: 'none',
                            }}
                          />
                        ) : (
                          <span aria-hidden style={{ fontSize: '14px' }}>📎</span>
                        )}
                        <span class="flex flex-col min-w-0">
                          <span class="truncate max-w-[160px]">{att.name}</span>
                          {pv ? (
                            <span
                              class="truncate"
                              style={{
                                color: 'var(--m3-on-surface-variant)',
                                fontSize: '10px',
                              }}
                            >
                              {pv.mime || 'application/octet-stream'} · {sizeKb} KB
                            </span>
                          ) : null}
                        </span>
                        <button
                          type="button"
                          onClick={() => removeAttachmentAt(i)}
                          disabled={composerSending}
                          class="opacity-70 hover:opacity-100 px-1"
                          style={{ color: 'var(--m3-error)' }}
                          aria-label="remove attachment"
                        >
                          ×
                        </button>
                      </li>
                    );
                  })}
                </ul>
              ) : null}
            </div>
          ) : null}

          {composerError ? (
            <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
              {composerError}
            </p>
          ) : null}

          <div class="flex items-center justify-end gap-2 mt-3">
            {sendPhase !== 'idle' && sendPhase !== '' ? (
              <button
                type="button"
                onClick={handleStop}
                disabled={stopping}
                class="text-sm px-4 py-2 rounded-md disabled:opacity-50"
                style={{
                  border: '1px solid var(--m3-error)',
                  color: 'var(--m3-error)',
                }}
              >
                {stopping
                  ? t('composer.stopping', '正在停止…')
                  : t('composer.stop', '停止响应')}
              </button>
            ) : null}
            <button
              type="button"
              onClick={handleSend}
              disabled={
                composerSending ||
                allowedModels.length === 0 ||
                (sendPhase !== 'idle' && sendPhase !== '')
              }
              class="text-sm px-4 py-2 rounded-md font-medium disabled:opacity-50"
              style={{
                background: 'var(--m3-primary)',
                color: 'var(--m3-on-primary)',
              }}
            >
              {composerSending
                ? t('composer.sending', '发送中…')
                : (sendPhase !== 'idle' && sendPhase !== '')
                  ? t('composer.waiting', '等待响应中…')
                  : t('composer.send', '发送')}
            </button>
          </div>
        </section>
      </div>
    </main>
  );
}
