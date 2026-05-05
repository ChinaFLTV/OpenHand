// 单会话详情页：会话头 / 消息分页 / Composer 发送（Stage 4 接入）。
//
// 设计要点：
// 1. 首屏拿最新一页（tail=1, limit=80）；列表按 created_at 升序展示。
// 2. 「加载更早」按钮 / 下拉：按当前已加载窗口 offset 拉取更早一页，prepend 到顶部。
// 3. 发送：POST /api/sessions/:id/messages 形成 user 消息；service 自身维护流式，
//    前端进入 1.2s 轮询循环刷新最新一页，直到 send_phase == idle。
// 4. 停止：POST /api/sessions/:id/stop（service 内部调用 AiSessionController.stopResponding）。
// 5. 附件：用 FileReader.readAsDataURL 读出 base64，去掉 `data:*;base64,` 前缀后塞入
//    {name, data_base64} 数组；service 端会落到 upload-cache。
//
// 服务端契约：
//   GET   /api/sessions/:id
//   GET   /api/sessions/:id/messages?limit=&offset=&tail= → {items, offset, limit, total, has_more, send_phase, last_error}
//   POST  /api/sessions/:id/messages  body {content, mode, model_key, attachments}
//   POST  /api/sessions/:id/stop     body {}

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useRoute } from 'preact-iso';
import { createPortal } from 'preact/compat';
import {
  deleteMessage,
  deleteMessageCascade,
  deleteSession,
  EXPORT_SESSION_TIMEOUT_ERROR,
  exportSessionDownload,
  getSession,
  listMessages,
  renameSession,
  respondWriteApproval,
  sendMessage,
  stopMessage,
  updateSessionFullAccessPermission,
  updateSessionMode,
  type SendMessageAttachment,
  type SessionDetailResponse,
  type SessionMessage,
} from '../api/sessions';
import { ApiError, UnauthorizedError } from '../api/client';
import { subscribeSessionEvents, type PendingWriteApproval } from '../api/session_events';
import { listSessions } from '../api/sessions';
import { SessionGoneDialog } from '../components/SessionGoneDialog';
import { t } from '../i18n';
import { useAuth } from '../state/auth';
import type { ApiMetaModel } from '../api/meta';
import { MessageCard } from '../components/MessageCard';
import { PlanTimeline } from '../components/PlanTimeline';
import { notifyIfHidden } from '../services/pwa';
import {
  SessionTopBar,
  type SessionToolbarCapsule,
} from '../components/SessionTopBar';
import { ModelPickerDialog, pushRecentModel } from '../components/ModelPickerDialog';
import { PullIndicator } from '../components/PullIndicator';
import { usePullToRefresh } from '../hooks/usePullToRefresh';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { showSnackbar } from '../components/Snackbar';
import { copyTextToClipboard } from '../utils/clipboard';

const PAGE_SIZE = 80;

/// 助手回复期间的轮询间隔。仅作为 SSE 失败时的兜底；正常路径走 SSE 实时推送。
const POLL_INTERVAL_MS = 1500;

/// SSE 正常时仍保留一个低频 phase guard，专门兜底最后一次 idle 状态丢失。
const SSE_PHASE_GUARD_INTERVAL_MS = 2500;

/// SSE 连续失败 N 次以上才彻底切到 polling，避免短暂网络抖动造成体验切换。
const SSE_FAIL_THRESHOLD = 3;

/// 单条附件最大字节数（沿用 service singleMessageTokenLimit 的语义留 1 MiB 兜底）；
/// 真正的硬上限以 service 端响应为准。
const ATTACHMENT_MAX_BYTES = 8 * 1024 * 1024;

async function copyJsonWithFeedback(json: string): Promise<void> {
  const ok = await copyTextToClipboard(json);
  showSnackbar(ok
    ? t('common.copied', '已复制')
    : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
}

// 时间戳与角色标签现在由 MessageCard 内部处理，本页不再直接使用。

/// 流式增量合并：保留与上一次 snapshot 相同的对象引用，仅替换发生变化的尾巴消息。
/// 使 `<MessageCard memo>` 在 SSE 80ms 推流期间跳过不变前缀的重新 diff，
/// 让流式更新感觉真正像"逐字增长"而不是"全帧重排"。
function mergeStream(
  prev: SessionMessage[],
  next: SessionMessage[],
): SessionMessage[] {
  if (prev === next) return prev;
  if (prev.length === 0 || next.length === 0) return next;
  // 长度变化或前缀 id 不一致 → 走完整替换；其他场景按 id+content+metadata 比较保留引用。
  const out: SessionMessage[] = new Array(next.length);
  let identical = prev.length === next.length;
  for (let i = 0; i < next.length; i += 1) {
    const a = i < prev.length ? prev[i] : undefined;
    const b = next[i];
    if (
      a &&
      a.id === b.id &&
      a.content.length === b.content.length &&
      a.kind === b.kind &&
      a.role === b.role &&
      a.character_count === b.character_count &&
      a.created_at === b.created_at &&
      sameMetadata(a.metadata, b.metadata)
    ) {
      out[i] = a;
    } else {
      out[i] = b;
      identical = false;
    }
  }
  return identical ? prev : out;
}

function mergeLatestWindow(
  prev: SessionMessage[],
  latest: SessionMessage[],
): SessionMessage[] {
  if (prev.length === 0) return latest;
  if (latest.length === 0) return prev;
  const firstIndex = prev.findIndex((item) => item.id === latest[0]!.id);
  if (firstIndex >= 0) {
    const prefix = prev.slice(0, firstIndex);
    return [...prefix, ...mergeStream(prev.slice(firstIndex), latest)];
  }
  const latestIds = new Set(latest.map((item) => item.id));
  const retained = prev.filter((item) => !latestIds.has(item.id));
  return [...retained, ...latest];
}

function sameMetadata(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a == null || b == null) return false;
  // metadata 是浅扁平 JSON 对象；用 JSON.stringify 比较即可，键顺序由 JSONparse 保留。
  try {
    return JSON.stringify(a) === JSON.stringify(b);
  } catch {
    return false;
  }
}

function sendPhaseLabel(phase: string): string {
  switch (phase) {
    case 'idle':
      return t('detail.phase.idle', '空闲');
    case 'sendingMessage':
    case 'sending':
      return t('detail.phase.sending', '发送中');
    case 'responding':
      return t('detail.phase.streaming', '流式接收中');
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

function modelSupportsMode(model: ApiMetaModel | undefined, mode: string): boolean {
  if (!model) return mode === 'normal' || mode === 'deep_research';
  switch (mode) {
    case 'normal':
    case 'deep_research':
      return true;
    case 'image':
      return model.supports_image_generation !== false;
    case 'video':
      return model.supports_video_generation !== false;
    case 'audio':
      return model.supports_audio_generation !== false;
    default:
      return true;
  }
}

interface RouteParams {
  id?: string;
}

export function SessionDetailPage() {
  const auth = useAuth();
  const location = useAnimatedLocation();
  const reduceMotion = useReducedMotion();
  const routeMatch = useRoute() as { params?: RouteParams } | undefined;
  const sessionId = routeMatch?.params?.id ?? '';
  const mainRef = useRef<HTMLElement | null>(null);
  const messagesRef = useRef<SessionMessage[]>([]);

  const [detail, setDetail] = useState<SessionDetailResponse | null>(null);
  const [messages, setMessages] = useState<SessionMessage[]>([]);
  // 当前本地 messages[0] 在服务端 oldest-first 序列里的 offset；0 表示历史已加载到头。
  const [windowOffset, setWindowOffset] = useState(0);
  const [totalKnown, setTotalKnown] = useState(0);
  const [loadingDetail, setLoadingDetail] = useState(true);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sendPhase, setSendPhase] = useState<string>('idle');
  const [lastError, setLastError] = useState<string | null>(null);
  // 服务端返回会话被删 (404 + body.error === 'session_deleted_or_not_found') 时拍起弹窗
  const [sessionGone, setSessionGone] = useState(false);

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
  const [composerCollapsed, setComposerCollapsed] = useState(false);
  const [autoFollow, setAutoFollow] = useState(true);
  const [autoFollowPaused, setAutoFollowPaused] = useState(false);
  const [showComposerModelPicker, setShowComposerModelPicker] = useState(false);
  const [permissionSaving, setPermissionSaving] = useState(false);
  const [pendingFullAccess, setPendingFullAccess] = useState<boolean | null>(null);
  const [pendingWriteApproval, setPendingWriteApproval] = useState<PendingWriteApproval | null>(null);
  const [writeApprovalBusy, setWriteApprovalBusy] = useState(false);

  const detailAbortRef = useRef<AbortController | null>(null);
  const messagesAbortRef = useRef<AbortController | null>(null);
  const pollTimerRef = useRef<number | null>(null);
  const sseCloseRef = useRef<(() => void) | null>(null);

  // 跨客户端协同: 自动跟随到底 + 远端发送冲突警告
  // ---------------------------------------------------------------------
  // 1) 自动跟随: 用户离底 ≤64px 视为「贴底」, 新消息追加时直接 scrollTo bottom;
  //    否则在右下角浮一个「↓ N 条新消息」pill, 点击回到底部并清零。
  // 2) 冲突警告: 本地 handleSend 触发会写 lastLocalSendAtRef. 当 sendPhase 转入
  //    运行态且距离最近一次本地 send > 4s, 视为「另一处客户端在生成」,
  //    若此时 composerText 非空 → 顶部黄色 banner 提示, 防止用户误以为自己刚发了。
  const isNearBottomRef = useRef<boolean>(true);
  const lastTailIdRef = useRef<string | null>(null);
  const lastTailContentLengthRef = useRef<number>(0);
  const lastLocalSendAtRef = useRef<number>(0);
  const [unreadCount, setUnreadCount] = useState<number>(0);
  const [remoteRunning, setRemoteRunning] = useState<boolean>(false);

  // 消息操作栏：审计弹窗 + 删除确认。
  const [auditMessage, setAuditMessage] = useState<SessionMessage | null>(null);
  const [sessionAuditOpen, setSessionAuditOpen] = useState(false);
  const [pendingDeleteAction, setPendingDeleteAction] = useState<{
    message: SessionMessage;
    cascade: boolean;
  } | null>(null);
  const [activeMessageId, setActiveMessageId] = useState<string | null>(null);
  const [sessionMetadataOpen, setSessionMetadataOpen] = useState(false);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [pendingSessionDelete, setPendingSessionDelete] = useState(false);
  const [sessionDeleteBusy, setSessionDeleteBusy] = useState(false);

  const scrollMessagesToBottom = (behavior: ScrollBehavior = 'auto') => {
    const el = mainRef.current;
    if (!el) return;
    el.scrollTo({ top: el.scrollHeight, behavior });
  };

  const handleCopyMessage = async (m: SessionMessage) => {
    const text = m.content ?? '';
    const ok = await copyTextToClipboard(text);
    showSnackbar(ok
      ? t('detail.copy.ok', '已复制消息内容')
      : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
        tone: ok ? 'success' : 'error',
      });
  };
  const handleDeleteMessage = (m: SessionMessage) => {
    setPendingDeleteAction({ message: m, cascade: false });
  };
  const handleDeleteMessageCascade = (m: SessionMessage) => {
    setPendingDeleteAction({ message: m, cascade: true });
  };
  const confirmDeleteMessage = async () => {
    if (!sessionId || !pendingDeleteAction || deleteBusy) return;
    setDeleteBusy(true);
    const { message, cascade } = pendingDeleteAction;
    try {
      if (cascade) {
        await deleteMessageCascade(sessionId, message.id);
      } else {
        await deleteMessage(sessionId, message.id);
      }
      setPendingDeleteAction(null);
      showSnackbar(cascade
        ? t('detail.deleteAfter.ok', '已删除此条及后续消息')
        : t('detail.delete.ok', '已删除消息'), { tone: 'success' });
    } catch (e) {
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
      showSnackbar(t('detail.delete.failed', '删除消息失败'), { tone: 'error' });
    } finally {
      setDeleteBusy(false);
    }
  };

  const confirmDeleteSession = async () => {
    if (!sessionId || sessionDeleteBusy) return;
    setSessionDeleteBusy(true);
    try {
      await deleteSession(sessionId);
      showSnackbar(t('topbar.delete.ok', '已删除会话'), { tone: 'success' });
      location.route('/threads');
    } catch (e) {
      if (handleAuthError(e)) return;
      if (e instanceof ApiError && e.status === 404) {
        showSnackbar(t('topbar.delete.ok', '已删除会话'), { tone: 'success' });
        location.route('/threads');
        return;
      }
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.delete.failed', '删除会话失败')}：${message}`, { tone: 'error' });
    } finally {
      setSessionDeleteBusy(false);
      setPendingSessionDelete(false);
    }
  };

  const applyFullAccessPermission = async (next: boolean) => {
    if (permissionSaving) return;
    setPermissionSaving(true);
    try {
      const res = await updateSessionFullAccessPermission(sessionId, next);
      setDetail((prev) => prev ? { ...prev, session: res.session } : prev);
      showSnackbar(t('topbar.perm.ok', '已更新权限设置'), { tone: 'success' });
    } catch (e) {
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.perm.failed', '更新权限设置失败')}：${message}`, { tone: 'error' });
    } finally {
      setPermissionSaving(false);
      setPendingFullAccess(null);
    }
  };

  const requestFullAccessPermissionChange = (next: boolean) => {
    if (permissionSaving) return;
    if (next && detail?.session.full_access_permission !== true) {
      setPendingFullAccess(true);
      return;
    }
    void applyFullAccessPermission(next);
  };

  const handleWriteApproval = async (approved: boolean) => {
    if (!pendingWriteApproval || writeApprovalBusy) return;
    setWriteApprovalBusy(true);
    try {
      await respondWriteApproval(sessionId, pendingWriteApproval.id, approved);
      setPendingWriteApproval(null);
      showSnackbar(
        approved
          ? t('detail.writeApproval.approved', '已批准写操作')
          : t('detail.writeApproval.rejected', '已拒绝写操作'),
        { tone: approved ? 'success' : undefined },
      );
      void refresh();
    } catch (e) {
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('detail.writeApproval.failed', '处理写操作确认失败')}：${message}`, { tone: 'error' });
    } finally {
      setWriteApprovalBusy(false);
    }
  };
  const handleEditMessage = (m: SessionMessage) => {
    if (m.role !== 'user') return;
    setComposerText((cur) => (cur ? `${cur}\n${m.content ?? ''}` : (m.content ?? '')));
    requestAnimationFrame(() => scrollMessagesToBottom(reduceMotion ? 'auto' : 'smooth'));
  };
  const handleAuditMessage = (m: SessionMessage) => {
    setAuditMessage(m);
  };

  useEffect(() => {
    function recalc() {
      const el = mainRef.current;
      if (!el) return;
      const dist = el.scrollHeight - (el.scrollTop + el.clientHeight);
      isNearBottomRef.current = dist <= 64;
      if (!autoFollow) {
        if (autoFollowPaused) setAutoFollowPaused(false);
        return;
      }
      if (isNearBottomRef.current) {
        if (unreadCount !== 0) setUnreadCount(0);
        if (autoFollowPaused) setAutoFollowPaused(false);
      } else if (!autoFollowPaused) {
        setAutoFollowPaused(true);
      }
    }
    recalc();
    const el = mainRef.current;
    el?.addEventListener('scroll', recalc, { passive: true });
    window.addEventListener('resize', recalc);
    return () => {
      el?.removeEventListener('scroll', recalc);
      window.removeEventListener('resize', recalc);
    };
  }, [autoFollow, autoFollowPaused, unreadCount]);

  useEffect(() => {
    messagesRef.current = messages;
  }, [messages]);

  useEffect(() => {
    if (activeMessageId == null) return;
    if (messages.some((item) => item.id === activeMessageId)) return;
    setActiveMessageId(null);
  }, [messages, activeMessageId]);

  // messages 变化 → 自动跟随 / 累计未读
  useEffect(() => {
    if (messages.length === 0) {
      lastTailIdRef.current = null;
      lastTailContentLengthRef.current = 0;
      return;
    }
    const tail = messages[messages.length - 1];
    const tailContentLength = tail.content?.length ?? tail.character_count ?? 0;
    if (lastTailIdRef.current === null) {
      // 首次进入会话：直接滚到底部，对齐 APP 端进入 Hardness Session 的体验。
      // 不走 smooth，避免冷启动时长列表"飞一段"；用 instant + 双 RAF 等渲染稳定。
      lastTailIdRef.current = tail.id;
      lastTailContentLengthRef.current = tailContentLength;
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          scrollMessagesToBottom('auto');
          isNearBottomRef.current = true;
          setAutoFollowPaused(false);
          setUnreadCount(0);
        });
      });
      return;
    }
    const tailChanged = tail.id !== lastTailIdRef.current;
    const tailContentChanged = tailContentLength !== lastTailContentLengthRef.current;
    if (!tailChanged && !tailContentChanged) return;
    lastTailIdRef.current = tail.id;
    lastTailContentLengthRef.current = tailContentLength;
    if (autoFollow && (isNearBottomRef.current || !autoFollowPaused)) {
      // defer 一帧, 等 DOM 把新卡片画上
      requestAnimationFrame(() => {
        scrollMessagesToBottom(reduceMotion ? 'auto' : 'smooth');
        isNearBottomRef.current = true;
        setAutoFollowPaused(false);
        setUnreadCount(0);
      });
    } else {
      if (autoFollow) setAutoFollowPaused(true);
      setUnreadCount((n) => (tailChanged ? n + 1 : Math.max(1, n)));
    }
  }, [messages, autoFollow, autoFollowPaused, reduceMotion]);

  // sendPhase 变化 → 远端冲突探测
  useEffect(() => {
    const running = sendPhase !== 'idle' && sendPhase !== '';
    if (!running) {
      if (remoteRunning) setRemoteRunning(false);
      return;
    }
    const sinceLocal = Date.now() - lastLocalSendAtRef.current;
    // > 4s 视为非本地触发的运行态
    if (sinceLocal > 4000 && !remoteRunning) {
      setRemoteRunning(true);
    }
  }, [sendPhase, remoteRunning]);

  const sseFailRef = useRef<number>(0);
  const [sseLive, setSseLive] = useState<boolean>(false);

  function handleAuthError(e: unknown): boolean {
    if (e instanceof UnauthorizedError) {
      location.route('/login', true);
      return true;
    }
    return false;
  }

  // 当 API 返回 404 + body.error === 'session_deleted_or_not_found' 时，
  // 切换到 SessionGoneDialog 流程；返回 true 让调用方跳过常规错误展示。
  function handleSessionGoneError(e: unknown): boolean {
    if (e instanceof ApiError && e.status === 404) {
      const body = e.body as { error?: string; message?: string } | string | null;
      const marker = typeof body === 'string'
        ? body
        : `${body?.error ?? ''} ${body?.message ?? ''}`;
      if (marker.includes('session_deleted_or_not_found')) {
        // 主动断开 SSE / 终止轮询，避免后续噪声错误覆盖弹窗
        sseCloseRef.current?.();
        sseCloseRef.current = null;
        if (pollTimerRef.current != null) {
          window.clearTimeout(pollTimerRef.current);
          pollTimerRef.current = null;
        }
        setSessionGone(true);
        return true;
      }
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
    setMessages([]);
    setWindowOffset(0);
    setTotalKnown(0);
    setActiveMessageId(null);
    setComposerModelKey('');
    setComposerMode('normal');
    lastTailIdRef.current = null;
    lastTailContentLengthRef.current = 0;
    Promise.all([
      getSession(sessionId),
      listMessages(sessionId, { limit: PAGE_SIZE, tail: true }),
    ])
      .then(([d, m]) => {
        if (ctrl.signal.aborted) return;
        setDetail(d);
        setMessages([...m.items]);
        setWindowOffset(m.offset);
        setTotalKnown(m.total);
        setSendPhase(m.send_phase || d.runtime.send_phase || 'idle');
        setLastError(m.last_error ?? d.runtime.last_error ?? null);
        setPendingWriteApproval(m.pending_write_approval ?? null);
        setLoadingDetail(false);
      })
      .catch((e: unknown) => {
        if (ctrl.signal.aborted) return;
        if (handleAuthError(e)) return;
        if (handleSessionGoneError(e)) {
          setLoadingDetail(false);
          return;
        }
        setError(e instanceof Error ? e.message : String(e));
        setLoadingDetail(false);
      });
  }

  async function refresh(): Promise<void> {
    if (!sessionId || refreshing) return;
    setRefreshing(true);
    try {
      const m = await listMessages(sessionId, { limit: PAGE_SIZE, tail: true });
      setMessages((prev) => mergeLatestWindow(prev, m.items));
      setWindowOffset((prev) => (
        messagesRef.current.length === 0 ? m.offset : Math.min(prev, m.offset)
      ));
      setTotalKnown(m.total);
      setSendPhase(m.send_phase);
      setLastError(m.last_error);
      setPendingWriteApproval(m.pending_write_approval ?? null);
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setRefreshing(false);
    }
  }

  async function loadOlder(): Promise<void> {
    if (loadingOlder) return;
    if (windowOffset <= 0) return;
    setLoadingOlder(true);
    const scroller = mainRef.current;
    const beforeHeight = scroller?.scrollHeight ?? 0;
    const beforeY = scroller?.scrollTop ?? 0;
    try {
      const offset = Math.max(0, windowOffset - PAGE_SIZE);
      const m = await listMessages(sessionId, {
        limit: Math.max(1, windowOffset - offset),
        offset,
      });
      setMessages((prev) => {
        const existing = new Set(prev.map((item) => item.id));
        const incoming = m.items.filter((item) => !existing.has(item.id));
        return [...incoming, ...prev];
      });
      setWindowOffset(m.offset);
      setTotalKnown(m.total);
      setSendPhase(m.send_phase);
      setLastError(m.last_error);
      setPendingWriteApproval(m.pending_write_approval ?? null);
      requestAnimationFrame(() => {
        const el = mainRef.current;
        if (!el) return;
        const delta = el.scrollHeight - beforeHeight;
        el.scrollTo({ top: beforeY + delta, behavior: 'auto' });
      });
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
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
        // 增量合并：当 snapshot 与本地 messages 的尾巴 N-1 条 id+content.length 完全一致，
        // 仅末尾消息的 content 变长（流式 token），就只复用前缀对象 + 重建末尾对象，
        // 让 Preact 的 keyed reconciliation 跳过前缀，每帧仅 patch 一个气泡。
        // 这是 #9 "感觉不像流式" 的关键修复：之前 setMessages([...snap.messages]) 把
        // 整个数组的 reference 全换了，所有 MessageCard 重建一遍 markdown / 高亮，
        // 80ms 一次的 SSE snapshot 就形成肉眼可见的"分段抖动"。
        const snapOffset = snap.message_window?.offset ?? Math.max(
          0,
          (snap.session.message_count ?? snap.messages.length) - snap.messages.length,
        );
        setMessages((prev) => mergeLatestWindow(prev, snap.messages));
        setWindowOffset((prev) => (
          messagesRef.current.length === 0 ? snapOffset : Math.min(prev, snapOffset)
        ));
        setTotalKnown(snap.session.message_count ?? snap.messages.length);
        setDetail((prev) => {
          const runtime = {
            send_phase: snap.send_phase,
            can_stop: snap.can_stop,
            last_error: snap.last_error,
          };
          return prev
            ? { ...prev, session: snap.session, runtime }
            : { session: snap.session, runtime };
        });
        setSendPhase(snap.send_phase);
        setLastError(snap.last_error);
        setPendingWriteApproval(snap.pending_write_approval ?? null);
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
  const selectedModel = useMemo(
    () => allowedModels.find((model) => model.key === composerModelKey),
    [allowedModels, composerModelKey],
  );
  const modelAllowedModes = useMemo(() => {
    const filtered = allowedModes.filter((mode) => modelSupportsMode(selectedModel, mode));
    return filtered.length > 0 ? filtered : ['normal'];
  }, [allowedModes, selectedModel]);
  const allowedMessageTypes = useMemo<string[]>(
    () => meta?.message_types ?? ['text', 'attachment'],
    [meta],
  );
  const sessionModeOptions = useMemo<string[]>(
    () => (meta?.service?.plan_mode_enabled ? ['chat', 'plan'] : ['chat']),
    [meta?.service?.plan_mode_enabled],
  );
  const attachmentsAllowed =
    allowedMessageTypes.includes('attachment') && selectedModel?.supports_attachments !== false;
  const textAllowed = allowedMessageTypes.includes('text');

  useEffect(() => {
    if (allowedModels.length === 0) return;
    const sessionModelKey = detail?.session.last_model_key ?? '';
    const sessionModelAllowed = sessionModelKey
      ? allowedModels.some((model) => model.key === sessionModelKey)
      : false;
    setComposerModelKey((current) => {
      const currentAllowed = current
        ? allowedModels.some((model) => model.key === current)
        : false;
      if (sessionModelAllowed && (!currentAllowed || current === allowedModels[0]?.key)) {
        return sessionModelKey;
      }
      if (!currentAllowed) return allowedModels[0]!.key;
      return current;
    });
  }, [allowedModels, detail?.session.id, detail?.session.last_model_key]);

  useEffect(() => {
    if (modelAllowedModes.length > 0 && !modelAllowedModes.includes(composerMode)) {
      setComposerMode(modelAllowedModes[0]!);
    }
  }, [modelAllowedModes, composerMode]);

  // 轮询：SSE 故障时 1.5s 拉一次；SSE 存活时也保留低频 phase guard，
  // 兜底最后一帧 idle 丢失导致按钮一直停在「等待响应中」。
  // 用 setTimeout 自驱动而非 setInterval，避免漂移与未完成请求叠加。
  useEffect(() => {
    if (auth.loading || !sessionId) return;
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
          tail: true,
        });
        if (cancelled) return;
        const offset = m.offset ?? Math.max(0, m.total - m.items.length);
        // 只合并最新窗口；不动「加载更早」拉过来的历史前缀。
        setMessages((prev) => mergeLatestWindow(prev, m.items));
        setWindowOffset((prev) => (
          messagesRef.current.length === 0 ? offset : Math.min(prev, offset)
        ));
        setTotalKnown(m.total);
        setSendPhase(m.send_phase);
        setLastError(m.last_error);
        setPendingWriteApproval(m.pending_write_approval ?? null);
      } catch (e: unknown) {
        if (cancelled) return;
        if (handleAuthError(e)) return;
        if (handleSessionGoneError(e)) return;
        setLastError(e instanceof Error ? e.message : String(e));
      }
      if (!cancelled) {
        pollTimerRef.current = window.setTimeout(
          tick,
          sseLive ? SSE_PHASE_GUARD_INTERVAL_MS : POLL_INTERVAL_MS,
        );
      }
    }
    pollTimerRef.current = window.setTimeout(
      tick,
      sseLive ? SSE_PHASE_GUARD_INTERVAL_MS : POLL_INTERVAL_MS,
    );
    return () => {
      cancelled = true;
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
  }, [auth.loading, sessionId, sendPhase, sseLive]);

  // 桌面通知: 当窗口隐藏时, 若收到新的 assistant 消息 (id 与上次不同),
  // 通过 Service Worker / Notification API 弹一个通知。
  // lastNotifiedAssistantIdRef 防止同一条多次重弹 (轮询 + SSE 双源刷新)。
  const lastNotifiedAssistantIdRef = useRef<string | null>(null);
  useEffect(() => {
    if (messages.length === 0) return;
    // 找最后一条 assistant 消息
    let assistant: SessionMessage | null = null;
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === 'assistant') {
        assistant = messages[i];
        break;
      }
    }
    if (!assistant) return;
    if (lastNotifiedAssistantIdRef.current === assistant.id) return;
    // 首屏加载时不要弹 (用户可能刚打开页面). 用 ref 初始化为 sentinel.
    if (lastNotifiedAssistantIdRef.current === null) {
      lastNotifiedAssistantIdRef.current = assistant.id;
      return;
    }
    lastNotifiedAssistantIdRef.current = assistant.id;
    const preview = assistant.content
      .replace(/```[\s\S]*?```/g, '[code]')
      .replace(/<[^>]+>/g, '')
      .trim()
      .slice(0, 140);
    const title = detail?.session.title || t('home.untitledSession', '未命名会话');
    notifyIfHidden({
      title,
      body: preview,
      sessionId,
    }).catch(() => undefined);
  }, [messages, sessionId, detail?.session.title]);

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
    if (!modelSupportsMode(selectedModel, composerMode)) {
      setComposerError(
        t('composer.error.modeUnsupported', '当前模型不支持所选模式，请切换模型或模式后再发送'),
      );
      return;
    }
    setComposerSending(true);
    setComposerError(null);
    // 标记「这是本地刚刚发起的 send」, 抑制后续 sendPhase running 触发远端冲突 banner
    lastLocalSendAtRef.current = Date.now();
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
      if (handleSessionGoneError(e)) return;
      if (e instanceof ApiError) {
        const body = e.body as { error?: string; message?: string } | null;
        setComposerError(
          body?.message ||
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
      if (handleSessionGoneError(e)) return;
      setLastError(e instanceof Error ? e.message : String(e));
    } finally {
      setStopping(false);
    }
  }

  const session = detail?.session;
  async function applySessionMode(next: 'chat' | 'plan'): Promise<void> {
    if (!sessionId) return;
    try {
      const res = await updateSessionMode(sessionId, next);
      setDetail((prev) => prev ? { ...prev, session: res.session } : prev);
      showSnackbar(t('topbar.mode.ok', '已更新会话模式'), { tone: 'success' });
    } catch (e: unknown) {
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.mode.failed', '更新会话模式失败')}：${message}`, { tone: 'error' });
    }
  }
  const remainingOlder = windowOffset;
  const sessionCapsules = useMemo<SessionToolbarCapsule[]>(() => {
    if (!session) return [];
    const running = sendPhase !== 'idle' && sendPhase !== '';
    const templateLabel = session.template_name || session.template_id;
    const templateVersion = session.template_internal_version != null
      ? ` · v${session.template_internal_version}`
      : '';
    const tokens = session.total_tokens != null
      ? `${session.total_tokens.toLocaleString()} tokens`
      : t('topbar.tokens.empty', 'Token 暂无');
    const modelLabel = selectedModel?.model_id || selectedModel?.label || composerModelKey || t('composer.model', '模型');
    const fullAccess = session.full_access_permission === true;
    return [
      {
        key: 'mode',
        icon: t('topbar.capsule.modeIcon', '模式'),
        label: session.mode === 'plan'
          ? t('sessions.mode.plan', '计划模式')
          : t('sessions.mode.chat', '聊天模式'),
        tone: session.mode === 'plan' ? 'primary' : 'neutral',
        onClick: () => {
          const next = session.mode === 'plan' ? 'chat' : 'plan';
          if (!sessionModeOptions.includes(next)) return;
          void applySessionMode(next);
        },
      },
      {
        key: 'runtime',
        icon: t('topbar.capsule.runtimeIcon', '运行'),
        label: `${sendPhaseLabel(sendPhase)} · ${sseLive ? t('detail.sse.live', '实时') : t('detail.sse.fallback', '轮询')}`,
        tone: running ? 'primary' : 'success',
      },
      {
        key: 'model',
        icon: t('topbar.capsule.modelIcon', '模型'),
        label: modelLabel,
        title: t('topbar.model.title', '点击选择模型'),
        onClick: () => setShowComposerModelPicker(true),
      },
      {
        key: 'permission',
        icon: t('topbar.capsule.permissionIcon', '权限'),
        label: fullAccess
          ? t('topbar.perm.full', '完全访问权限')
          : t('topbar.perm.default', '默认权限'),
        tone: fullAccess ? 'warning' : 'neutral',
        onClick: () => requestFullAccessPermissionChange(!fullAccess),
      },
      {
        key: 'template',
        icon: t('topbar.capsule.templateIcon', '模板'),
        label: `${templateLabel}${templateVersion}`,
        title: `${t('sessions.template.label', '模板：')}${templateLabel}${templateVersion}`,
      },
      {
        key: 'files',
        icon: t('topbar.capsule.filesIcon', '文件'),
        label: t('topbar.files', '项目文件'),
        title: t('topbar.files.title', '打开项目文件'),
        onClick: () => location.route('/files'),
      },
      {
        key: 'metadata',
        icon: t('topbar.capsule.metadataIcon', '元'),
        label: `${totalKnown} ${t('sessions.messageUnit', '条消息')} · ${session.tool_message_count ?? 0} tool`,
        onClick: () => setSessionMetadataOpen(true),
      },
      {
        key: 'audit',
        icon: t('topbar.capsule.auditIcon', '审计'),
        label: t('topbar.audit', '会话审计'),
        tone: 'primary',
        onClick: () => setSessionAuditOpen(true),
      },
      {
        key: 'tokens',
        icon: t('topbar.capsule.tokenIcon', 'Token'),
        label: tokens,
        title: `${t('topbar.tokens', 'Token 统计')} · prompt ${session.total_prompt_tokens ?? 0} / completion ${session.total_completion_tokens ?? 0}`,
        onClick: () => setSessionMetadataOpen(true),
      },
    ];
  }, [session, sendPhase, sseLive, totalKnown, selectedModel, composerModelKey, sessionModeOptions, sessionId]);
  const pull = usePullToRefresh(mainRef, {
    enabled: !loadingDetail && !loadingOlder,
    onRefresh: async () => {
      if (remainingOlder > 0) {
        await loadOlder();
      } else {
        await refresh();
      }
    },
    activationDistance: 84,
  });

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

  const resumeToLatest = () => {
    setAutoFollow(true);
    setAutoFollowPaused(false);
    setUnreadCount(0);
    isNearBottomRef.current = true;
    requestAnimationFrame(() => {
      scrollMessagesToBottom(reduceMotion ? 'auto' : 'smooth');
    });
  };

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
    ? [
        session.template_name || session.template_id,
        session.mode === 'plan'
          ? t('sessions.mode.plan', 'Plan')
          : t('sessions.mode.chat', '对话'),
        `${totalKnown} ${t('sessions.messageUnit', '条消息')}`,
        session.total_tokens != null ? `${session.total_tokens.toLocaleString()} tokens` : '',
        session.tool_message_count ? `${session.tool_message_count} tool` : '',
        session.compression_point_count ? `${session.compression_point_count} compress` : '',
      ].filter(Boolean).join(' · ')
    : t('detail.loading', '加载会话中…');

  return (
    <main class="h-screen overflow-hidden px-3 sm:px-6 py-4 sm:py-6 flex flex-col" style={{ background: 'var(--m3-surface)' }}>
      <PullIndicator
        pulled={pull.pulled}
        refreshing={pull.refreshing}
        willRelease={pull.willRelease}
        activationDistance={84}
      />
      <div class="mx-auto max-w-3xl w-full flex-1 min-h-0 flex flex-col gap-3">
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
              showSnackbar(t('topbar.rename.ok', '已重命名会话'), { tone: 'success' });
            } catch (e) {
              if (handleAuthError(e)) return;
              if (handleSessionGoneError(e)) return;
              const message = e instanceof Error ? e.message : String(e);
              setLastError(message);
              showSnackbar(`${t('topbar.rename.failed', '重命名失败')}：${message}`, { tone: 'error' });
              throw e;
            }
          }}
          modes={sessionModeOptions}
          mode={session?.mode ?? 'chat'}
          onModeChange={async (next) => {
            if (next !== 'chat' && next !== 'plan') return;
            await applySessionMode(next);
          }}
          models={allowedModels}
          modelKey={composerModelKey}
          onModelChange={(k) => {
            setComposerModelKey(k);
            pushRecentModel(k);
          }}
          fullAccessPermission={session?.full_access_permission === true}
          onFullAccessPermissionChange={requestFullAccessPermissionChange}
          sendPhase={sendPhase}
          canStop={detail?.runtime.can_stop ?? sendPhase !== 'idle'}
          stopping={stopping}
          onStop={handleStop}
          onDelete={async () => {
            setPendingSessionDelete(true);
          }}
          onExport={async () => {
            try {
              showSnackbar(t('topbar.export.started', '正在导出会话数据…'));
              const result = await exportSessionDownload(
                sessionId,
                session?.title || sessionId,
              );
              showSnackbar(`${t('topbar.export.ok', '已开始下载')}：${result.filename}`, { tone: 'success' });
            } catch (e) {
              if (handleAuthError(e)) return;
              if (handleSessionGoneError(e)) return;
              const message = e instanceof Error && e.message === EXPORT_SESSION_TIMEOUT_ERROR
                ? t('topbar.export.timeout', '导出会话超时，请稍后重试')
                : e instanceof Error
                  ? e.message
                  : String(e);
              setLastError(message);
              showSnackbar(`${t('topbar.export.failed', '导出会话失败')}：${message}`, { tone: 'error' });
            }
          }}
          sessionId={sessionId}
          capsules={sessionCapsules}
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

        {lastError ? (
          <ErrorBanner message={lastError} onRetry={() => void refresh()} onDismiss={() => setLastError(null)} />
        ) : null}

        {remoteRunning ? (
          <div
            class="rounded-md px-3 py-2 mb-4 text-xs flex items-start gap-2"
            style={{
              background: 'var(--m3-tertiary-container)',
              color: 'var(--m3-on-tertiary-container)',
              border: '1px solid color-mix(in srgb, var(--m3-tertiary) 36%, transparent)',
            }}
          >
            <span>
              {t(
                'detail.remoteRunning',
                '另一处客户端正在生成回复。如本端正在编辑草稿, 建议等远端结束后再发送, 避免顺序混乱。',
              )}
            </span>
          </div>
        ) : null}

        {/* 主区：只有这块滚动，顶部 TopBar / 底部 Composer 固定在视口内。 */}
        <section ref={mainRef} class="relative flex-1 min-h-0 overflow-y-auto pr-1 pb-3">
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
              <>
                {detail?.session ? (
                  <PlanTimeline session={detail.session} modelKey={composerModelKey} />
                ) : null}
                <ul class="flex flex-col gap-3">
                  {sortedMessages.map((m) => (
                    <li key={m.id}>
                      <MessageCard
                        message={m}
                        active={activeMessageId === m.id}
                        sessionId={sessionId}
                        onActiveChange={(message, active) => {
                          setActiveMessageId(active ? message.id : null);
                        }}
                        onCopy={handleCopyMessage}
                        onDelete={handleDeleteMessage}
                        onDeleteAfter={handleDeleteMessageCascade}
                        onEdit={m.role === 'user' ? handleEditMessage : undefined}
                        onAudit={handleAuditMessage}
                      />
                    </li>
                  ))}
                </ul>
              </>
            )}
          </>
        )}
        </section>

        {/* Composer */}
        <section
          class="rounded-xl p-4 flex-none"
          style={{
            background: 'var(--m3-surface-container)',
            boxShadow: 'var(--m3-elev-1)',
          }}
        >
          <div class="flex flex-wrap items-center gap-2 mb-3">
            {sessionModeOptions.length > 1 ? (
              <div
                class="flex items-center gap-1 rounded-m3-sm p-0.5"
                style={{
                  background: 'var(--m3-surface)',
                  border: '1px solid var(--m3-outline-variant)',
                }}
                aria-label={t('composer.sessionMode', '会话模式')}
              >
                {sessionModeOptions.map((item) => {
                  const active = (session?.mode ?? 'chat') === item;
                  const label = item === 'plan'
                    ? t('sessions.mode.plan', '计划模式')
                    : t('sessions.mode.chat', '聊天模式');
                  return (
                    <button
                      key={item}
                      type="button"
                      onClick={() => void applySessionMode(item as 'chat' | 'plan')}
                      disabled={composerSending || active}
                      class="oh-tap-press text-xs px-2.5 py-1 rounded-m3-sm disabled:opacity-90"
                      style={{
                        background: active ? 'var(--m3-primary-container)' : 'transparent',
                        color: active ? 'var(--m3-on-primary-container)' : 'var(--m3-on-surface-variant)',
                        fontWeight: active ? 700 : 500,
                      }}
                      title={label}
                    >
                      {label}
                    </button>
                  );
                })}
              </div>
            ) : null}

            <button
              type="button"
              onClick={() => setShowComposerModelPicker(true)}
              disabled={composerSending || allowedModels.length === 0}
              class="oh-tap-press text-xs px-2.5 py-1.5 rounded-m3-sm flex items-center gap-1.5 disabled:opacity-50 min-w-0"
              style={{
                border: '1px solid var(--m3-outline)',
                color: 'var(--m3-on-surface)',
                background: 'var(--m3-surface)',
                maxWidth: '260px',
              }}
              title={t('composer.model', '模型')}
            >
              <span class="truncate">
                {selectedModel?.model_id || selectedModel?.label || t('composer.modelEmpty', '主控制台未配置模型')}
              </span>
            </button>

            <div
              class="flex items-center gap-1 rounded-m3-sm p-0.5"
              style={{
                background: 'var(--m3-surface)',
                border: '1px solid var(--m3-outline)',
              }}
              aria-label={t('composer.mode', '模式')}
            >
              {modelAllowedModes.map((m) => {
                const active = m === composerMode;
                const label = m === 'normal'
                  ? t('composer.mode.normal', '普通')
                  : m === 'image'
                    ? t('composer.mode.image', '图像')
                    : m === 'video'
                      ? t('composer.mode.video', '视频')
                      : m === 'audio'
                        ? t('composer.mode.audio', '音频')
                        : m;
                return (
                  <button
                    key={m}
                    type="button"
                    onClick={() => setComposerMode(m)}
                    disabled={composerSending || active}
                    class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm disabled:opacity-90"
                    style={{
                      background: active ? 'var(--m3-secondary-container)' : 'transparent',
                      color: active ? 'var(--m3-on-secondary-container)' : 'var(--m3-on-surface-variant)',
                      fontWeight: active ? 700 : 500,
                    }}
                    title={label}
                  >
                    <span>{label}</span>
                  </button>
                );
              })}
            </div>

            <button
              type="button"
              onClick={() => {
                if (permissionSaving) return;
                const next = session?.full_access_permission !== true;
                requestFullAccessPermissionChange(next);
              }}
              disabled={permissionSaving}
              class="oh-tap-press text-xs px-2.5 py-1.5 rounded-m3-sm"
              style={{
                border: session?.full_access_permission === true
                  ? '1px solid color-mix(in srgb, var(--m3-tertiary) 50%, transparent)'
                  : '1px solid var(--m3-outline)',
                color: session?.full_access_permission === true ? 'var(--m3-on-tertiary-container)' : 'var(--m3-on-surface-variant)',
                background: session?.full_access_permission === true
                  ? 'var(--m3-tertiary-container)'
                  : 'transparent',
              }}
              title={t('topbar.perm.title', '权限模式')}
            >
              <span>
                {session?.full_access_permission === true
                  ? t('topbar.perm.full', '完全访问权限')
                  : t('topbar.perm.default', '默认权限')}
              </span>
            </button>

            <button
              type="button"
              onClick={() => {
                if (!autoFollow || autoFollowPaused || unreadCount > 0) {
                  resumeToLatest();
                } else {
                  setAutoFollow(false);
                  setAutoFollowPaused(false);
                }
              }}
              class="oh-tap-press text-xs px-2.5 py-1.5 rounded-m3-sm"
              style={{
                border: '1px solid var(--m3-outline)',
                background: autoFollow || autoFollowPaused || unreadCount > 0
                  ? 'var(--m3-primary-container)'
                  : 'transparent',
                color: autoFollow || autoFollowPaused || unreadCount > 0
                  ? 'var(--m3-on-primary-container)'
                  : 'var(--m3-on-surface-variant)',
              }}
              title={autoFollowPaused || unreadCount > 0
                ? t('detail.resumeToLatest', '回到底部')
                : t('composer.autoFollow', '自动跟随到底部')}
            >
              <span>
                {autoFollowPaused || unreadCount > 0
                  ? t('detail.resumeToLatest', '回到底部')
                  : autoFollow
                    ? t('common.on', '开启')
                    : t('common.off', '关闭')}
              </span>
            </button>

            <button
              type="button"
              onClick={() => setComposerCollapsed((v) => !v)}
              class="oh-tap-press text-xs px-2.5 py-1.5 rounded-m3-sm ml-auto"
              style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface-variant)' }}
              title={composerCollapsed ? t('composer.expand', '展开输入区') : t('composer.collapse', '收起输入区')}
            >
              {composerCollapsed ? '▴' : '▾'}
            </button>
          </div>

          <div
            class="oh-composer-body"
            data-collapsed={composerCollapsed ? 'true' : 'false'}
            aria-hidden={composerCollapsed ? 'true' : undefined}
          >
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
              resize: 'none',
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
          {attachmentsAllowed && composerAttachments.length > 0 ? (
            <div class="mt-2">
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
                          <span aria-hidden style={{ fontSize: '12px', fontWeight: 700 }}>ATT</span>
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
            </div>
          ) : null}

          {composerError ? (
            <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
              {composerError}
            </p>
          ) : null}
          </div>

          <div class="flex flex-wrap items-center gap-2 mt-3">
            {attachmentsAllowed ? (
              <label
                class="oh-tap-press text-xs px-3 py-2 rounded-m3-sm cursor-pointer flex items-center gap-1.5"
                style={{
                  border: '1px solid var(--m3-outline)',
                  color: 'var(--m3-on-surface-variant)',
                  background: 'var(--m3-surface)',
                }}
              >
                <span aria-hidden>＋</span>
                {t('composer.attachment.add', '添加附件')}
                <input
                  type="file"
                  multiple
                  onChange={handleAttachmentInput}
                  style={{ display: 'none' }}
                />
              </label>
            ) : null}
            <span class="text-xs flex-1 min-w-[160px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {composerText.length > 0
                ? `${composerText.length.toLocaleString()} ${t('composer.charUnit', '字符')}`
                : t('composer.shortcutHint', 'Cmd / Ctrl + Enter 发送')}
            </span>
            {composerAttachments.length > 0 ? (
              <span class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {composerAttachments.length} {t('composer.attachment.unit', '个附件')}
              </span>
            ) : null}
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

      {auditMessage ? (
        <MessageAuditDialog
          message={auditMessage}
          onClose={() => setAuditMessage(null)}
        />
      ) : null}
      {sessionAuditOpen && detail ? (
        <SessionAuditDialog
          detail={detail}
          messages={messages}
          onClose={() => setSessionAuditOpen(false)}
        />
      ) : null}
      {sessionMetadataOpen && detail ? (
        <SessionMetadataDialog
          detail={detail}
          messages={messages}
          onClose={() => setSessionMetadataOpen(false)}
        />
      ) : null}
      {pendingDeleteAction ? (
        <ConfirmDialog
          title={pendingDeleteAction.cascade
            ? t('detail.deleteAfter.confirmTitle', '删除此条及后续消息?')
            : t('detail.delete.confirmTitle', '删除这条消息?')}
          body={pendingDeleteAction.cascade
            ? t('detail.deleteAfter.confirmBody', '此操作会删除当前消息以及它之后的所有消息，删除后不可恢复。')
            : t('detail.delete.confirmBody', '此操作会删除当前消息，删除后不可恢复。')}
          danger
          busy={deleteBusy}
          confirmLabel={deleteBusy ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          onCancel={() => {
            if (!deleteBusy) setPendingDeleteAction(null);
          }}
          onConfirm={confirmDeleteMessage}
        />
      ) : null}
      {pendingSessionDelete ? (
        <ConfirmDialog
          title={t('topbar.deleteConfirmTitle', '删除该会话?')}
          body={t('topbar.deleteConfirm', '确定删除该会话?此操作不可恢复')}
          danger
          busy={sessionDeleteBusy}
          confirmLabel={sessionDeleteBusy ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => {
            if (!sessionDeleteBusy) setPendingSessionDelete(false);
          }}
          onConfirm={confirmDeleteSession}
        />
      ) : null}
      {pendingFullAccess === true ? (
        <ConfirmDialog
          title={t('topbar.perm.fullConfirmTitle', '启用完全访问权限')}
          body={t(
            'topbar.perm.fullConfirmBody',
            '启用后，Web 会话中的写文件、执行命令等高风险操作将按 APP 完全访问权限模式自动执行。请确认当前会话和浏览器设备可信。',
          )}
          danger
          busy={permissionSaving}
          confirmLabel={permissionSaving
            ? t('common.saving', '保存中…')
            : t('topbar.perm.enableFullAccess', '启用完全访问权限')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => {
            if (!permissionSaving) setPendingFullAccess(null);
          }}
          onConfirm={() => void applyFullAccessPermission(true)}
        />
      ) : null}
      {pendingWriteApproval ? (
        <ConfirmDialog
          title={t('detail.writeApproval.title', '确认写操作')}
          body={`${t('detail.writeApproval.body', '当前默认权限模式需要确认后才会继续执行写文件或命令操作。')}\n\n${t('detail.writeApproval.cwd', '工作目录')}：${pendingWriteApproval.working_directory || '-'}\n${t('detail.writeApproval.command', '命令')}：${pendingWriteApproval.command}`}
          danger
          busy={writeApprovalBusy}
          confirmLabel={writeApprovalBusy
            ? t('common.processing', '处理中…')
            : t('detail.writeApproval.approve', '允许执行')}
          cancelLabel={t('detail.writeApproval.reject', '拒绝')}
          onCancel={() => void handleWriteApproval(false)}
          onConfirm={() => void handleWriteApproval(true)}
        />
      ) : null}
      {showComposerModelPicker ? (
        <ModelPickerDialog
          models={allowedModels}
          selectedKey={composerModelKey}
          onSelect={(key) => {
            setComposerModelKey(key);
            pushRecentModel(key);
          }}
          onClose={() => setShowComposerModelPicker(false)}
        />
      ) : null}
      {/* 服务端会话已被删除时的友好提示弹窗。返回前先 ping 一次会话列表 API
          预热缓存 / 触发 store 刷新（当前列表页自身亦会重新拉，这里的 await 仅
          为了在弹窗关闭瞬间用户跳转过去看到的就是最新数据）。 */}
      <SessionGoneDialog
        open={sessionGone}
        onBeforeNavigate={async () => {
          try {
            await listSessions({ page: 1, pageSize: 20 });
          } catch {
            // 静默：列表刷新失败也不影响导航
          }
        }}
      />
    </main>
  );
}

/// 错误条带：自动识别 Connection refused / 网络断开 等常见错误，给出本地化解释 +
/// [重试] [复制] [关闭] 三档操作。普通错误退化为单行 Material 错误样式。
function ErrorBanner({
  message,
  onRetry,
  onDismiss,
}: {
  message: string;
  onRetry: () => void;
  onDismiss: () => void;
}) {
  const lower = message.toLowerCase();
  const isConnRefused =
    lower.includes('connection refused') ||
    lower.includes('econnrefused') ||
    lower.includes('errno = 61') ||
    lower.includes('errno = 111') ||
    lower.includes('failed to connect');
  const isNetwork =
    !isConnRefused &&
    (lower.includes('socketexception') ||
      lower.includes('handshakeexception') ||
      lower.includes('network is unreachable') ||
      lower.includes('failed host lookup') ||
      lower.includes('errno = 8') ||
      lower.includes('errno = 65'));
  const isTimeout =
    !isConnRefused &&
    !isNetwork &&
    (lower.includes('timeout') || lower.includes('timed out'));

  let title: string;
  let hint: string | null;
  if (isConnRefused) {
    title = t('detail.error.connRefused.title', '无法连接到 AI 服务');
    hint = t(
      'detail.error.connRefused.hint',
      '后端拒绝连接：请确认 Base URL 与端口可访问，确认代理（如 Clash）端口/规则正确，或切换至备用模型/服务商再试。',
    );
  } else if (isNetwork) {
    title = t('detail.error.network.title', '网络异常');
    hint = t(
      'detail.error.network.hint',
      '请求未能完成：检查本机网络连接、DNS 与代理设置；如使用专线/VPN 请确认隧道在线。',
    );
  } else if (isTimeout) {
    title = t('detail.error.timeout.title', '请求超时');
    hint = t(
      'detail.error.timeout.hint',
      '远端长时间未响应：可重试一次；若持续超时请尝试更小的输入或切换模型。',
    );
  } else {
    title = t('detail.lastError', '最近错误：');
    hint = null;
  }

  const copyText = async () => {
    const ok = await copyTextToClipboard(message);
    showSnackbar(ok
      ? t('detail.error.copy.ok', '已复制错误详情')
      : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
        tone: ok ? 'success' : 'error',
      });
  };

  return (
    <div
      class="rounded-md px-3 py-2 text-xs flex flex-col gap-1.5"
      style={{
        background: 'color-mix(in srgb, var(--m3-error) 8%, transparent)',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-error) 35%, transparent)',
        maxWidth: '100%',
      }}
      role="alert"
    >
      <div class="flex items-start gap-2">
        <div class="flex-1 min-w-0">
          <div style={{ color: 'var(--m3-error)', fontWeight: 600 }}>{title}</div>
          {hint ? (
            <div style={{ color: 'var(--m3-on-surface-variant)', marginTop: 2 }}>{hint}</div>
          ) : null}
          <div
            style={{
              marginTop: 4,
              fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
              wordBreak: 'break-all',
              color: 'var(--m3-on-surface-variant)',
            }}
          >
            {message}
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2 self-end">
        <button
          type="button"
          class="oh-tap-press"
          onClick={onRetry}
          style={{
            padding: '4px 10px',
            borderRadius: 999,
            background: 'var(--m3-primary)',
            color: 'var(--m3-on-primary)',
            border: 'none',
            fontSize: 12,
            cursor: 'pointer',
          }}
        >
          {t('common.retry', '重试')}
        </button>
        <button
          type="button"
          class="oh-tap-press"
          onClick={() => void copyText()}
          style={{
            padding: '4px 10px',
            borderRadius: 999,
            background: 'transparent',
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
            fontSize: 12,
            cursor: 'pointer',
          }}
        >
          {t('common.copy', '复制')}
        </button>
        <button
          type="button"
          class="oh-tap-press"
          onClick={onDismiss}
          aria-label={t('common.cancel', '取消')}
          style={{
            padding: '4px 10px',
            borderRadius: 999,
            background: 'transparent',
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid transparent',
            fontSize: 12,
            cursor: 'pointer',
          }}
        >
          ✕
        </button>
      </div>
    </div>
  );
}

/// 消息审计弹窗：展示原始 JSON（id / kind / role / metadata / created_at / character_count），
/// 用于排查 tool_call 元数据 / 文件变动等问题。复用全局对话框样式。
function MessageAuditDialog({
  message,
  onClose,
}: {
  message: SessionMessage;
  onClose: () => void;
}) {
  const json = JSON.stringify(message, null, 2);
  const node = (
    <div
      class="oh-dialog-fade-in fixed inset-0 z-[2600] flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.40)', zIndex: 2600 }}
      onClick={onClose}
    >
      <div
        class="oh-dialog-pop-in rounded-m3-md p-4 max-w-2xl w-full flex flex-col"
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          maxHeight: '80vh',
          border: '1px solid var(--m3-outline)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="flex items-center justify-between gap-3 mb-3">
          <h2 class="text-base font-semibold">{t('common.audit', '审计')} · {message.id}</h2>
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline)' }}
              onClick={() => void copyJsonWithFeedback(json)}
            >
              {t('common.copy', '复制')}
            </button>
            <button
              type="button"
              class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
              onClick={onClose}
            >
              {t('common.close', '关闭')}
            </button>
          </div>
        </header>
        <pre
          class="text-xs overflow-auto rounded-m3-sm p-3 whitespace-pre-wrap flex-1 min-h-0"
          style={{
            background: 'var(--m3-surface)',
            border: '1px solid var(--m3-outline)',
            maxHeight: 'calc(80vh - 96px)',
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
          }}
        >
          {json}
        </pre>
      </div>
    </div>
  );
  return typeof document === 'undefined' ? node : createPortal(node, document.body);
}

function formatDialogDate(value?: string | null): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function SessionMetadataDialog({
  detail,
  messages,
  onClose,
}: {
  detail: SessionDetailResponse;
  messages: SessionMessage[];
  onClose: () => void;
}) {
  const session = detail.session;
  const latest = messages[messages.length - 1];
  const tokenRows = [
    [t('metadata.tokens.total', '总 Token'), `${session.total_tokens ?? 0}`],
    [t('metadata.tokens.prompt', 'Prompt'), `${session.total_prompt_tokens ?? 0}`],
    [t('metadata.tokens.completion', 'Completion'), `${session.total_completion_tokens ?? 0}`],
    [t('metadata.tokens.compress', '压缩点'), `${session.compression_point_count ?? 0}`],
  ];
  const sections: Array<{ title: string; rows: Array<[string, string]> }> = [
    {
      title: t('metadata.section.identity', '会话身份'),
      rows: [
        [t('metadata.id', '会话 ID'), session.id],
        [t('metadata.title', '标题'), session.title || t('sessions.untitled', '未命名会话')],
        [t('metadata.mode', '会话模式'), session.mode === 'plan' ? t('sessions.mode.plan', '计划模式') : t('sessions.mode.chat', '聊天模式')],
        [t('metadata.permission', '权限'), session.full_access_permission ? t('topbar.perm.full', '完全访问权限') : t('topbar.perm.default', '默认权限')],
      ],
    },
    {
      title: t('metadata.section.template', '模板与模型'),
      rows: [
        [t('metadata.template', '线程模板'), session.template_name || session.template_id],
        [t('metadata.templateId', '模板 ID'), session.template_id],
        [t('metadata.templateVersion', '模板版本'), session.template_internal_version != null ? `v${session.template_internal_version}` : '—'],
        [t('metadata.model', '最近模型'), session.last_used_model_label || session.last_used_model_id || '—'],
      ],
    },
    {
      title: t('metadata.section.runtime', '运行状态'),
      rows: [
        [t('metadata.sendPhase', '发送阶段'), sendPhaseLabel(detail.runtime.send_phase || session.send_phase || 'idle')],
        [t('metadata.canStop', '可停止'), detail.runtime.can_stop ? t('common.yes', '是') : t('common.no', '否')],
        [t('metadata.lastError', '最近错误'), detail.runtime.last_error || '—'],
        [t('metadata.pendingPlan', '待批准计划'), session.awaiting_plan_approval ? t('common.yes', '是') : t('common.no', '否')],
      ],
    },
    {
      title: t('metadata.section.time', '时间与来源'),
      rows: [
        [t('metadata.createdAt', '创建时间'), formatDialogDate(session.created_at)],
        [t('metadata.updatedAt', '更新时间'), formatDialogDate(session.updated_at)],
        [t('metadata.source', '来源'), session.source || '—'],
        [t('metadata.device', '设备'), session.device_id || '—'],
      ],
    },
  ];
  const node = (
    <div
      class="oh-dialog-fade-in fixed inset-0 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.40)', zIndex: 2600 }}
      onClick={onClose}
    >
      <div
        class="oh-dialog-pop-in rounded-m3-md p-4 max-w-4xl w-full flex flex-col"
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline-variant)',
          maxHeight: '84vh',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="flex items-center justify-between gap-3 mb-4">
          <div class="min-w-0">
            <h2 class="text-base font-semibold truncate">{t('metadata.titleBar', '会话元数据')} · {session.title}</h2>
            <p class="text-xs mt-0.5" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {session.message_count} {t('sessions.messageUnit', '条消息')} · {session.tool_message_count ?? 0} tool
            </p>
          </div>
          <div class="flex items-center gap-2 flex-none">
            <button
              type="button"
              class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline)' }}
              onClick={() => void copyJsonWithFeedback(JSON.stringify({ session, runtime: detail.runtime }, null, 2))}
            >
              {t('common.copy', '复制')}
            </button>
            <button
              type="button"
              class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
              onClick={onClose}
            >
              {t('common.close', '关闭')}
            </button>
          </div>
        </header>
        <div class="grid gap-2 mb-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
          {tokenRows.map(([label, value]) => (
            <div
              key={label}
              class="rounded-m3-sm p-3"
              style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
            >
              <div class="text-[11px]" style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</div>
              <div class="text-base font-semibold mt-1">{value}</div>
            </div>
          ))}
        </div>
        <div class="overflow-auto pr-1 flex-1 min-h-0">
          <div class="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))' }}>
            {sections.map((section) => (
              <section
                key={section.title}
                class="rounded-m3-sm p-3"
                style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
              >
                <h3 class="text-sm font-semibold mb-2">{section.title}</h3>
                <dl class="space-y-2">
                  {section.rows.map(([label, value]) => (
                    <div key={label} class="grid gap-1" style={{ gridTemplateColumns: '96px minmax(0, 1fr)' }}>
                      <dt class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</dt>
                      <dd class="text-xs break-words">{value}</dd>
                    </div>
                  ))}
                </dl>
              </section>
            ))}
            <section
              class="rounded-m3-sm p-3"
              style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
            >
              <h3 class="text-sm font-semibold mb-2">{t('metadata.section.latest', '最近加载消息')}</h3>
              <dl class="space-y-2">
                <div class="grid gap-1" style={{ gridTemplateColumns: '96px minmax(0, 1fr)' }}>
                  <dt class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{t('metadata.loaded', '已加载')}</dt>
                  <dd class="text-xs">{messages.length}</dd>
                </div>
                <div class="grid gap-1" style={{ gridTemplateColumns: '96px minmax(0, 1fr)' }}>
                  <dt class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{t('metadata.latestRole', '最新角色')}</dt>
                  <dd class="text-xs">{latest?.role || '—'}</dd>
                </div>
                <div class="grid gap-1" style={{ gridTemplateColumns: '96px minmax(0, 1fr)' }}>
                  <dt class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{t('metadata.latestKind', '最新类型')}</dt>
                  <dd class="text-xs">{latest?.kind || '—'}</dd>
                </div>
                <div class="grid gap-1" style={{ gridTemplateColumns: '96px minmax(0, 1fr)' }}>
                  <dt class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{t('metadata.latestId', '最新 ID')}</dt>
                  <dd class="text-xs break-all">{latest?.id || '—'}</dd>
                </div>
              </dl>
            </section>
          </div>
        </div>
      </div>
    </div>
  );
  return typeof document === 'undefined' ? node : createPortal(node, document.body);
}

function SessionAuditDialog({
  detail,
  messages,
  onClose,
}: {
  detail: SessionDetailResponse;
  messages: SessionMessage[];
  onClose: () => void;
}) {
  const session = detail.session;
  const json = JSON.stringify({
    session,
    runtime: detail.runtime,
    loaded_message_count: messages.length,
    loaded_message_ids: messages.map((item) => item.id),
  }, null, 2);
  const stats = [
    `${session.message_count} ${t('sessions.messageUnit', '条消息')}`,
    `${session.total_tokens ?? 0} tokens`,
    `${session.tool_message_count ?? 0} tool`,
    `${session.compression_point_count ?? 0} compress`,
  ];
  const node = (
    <div
      class="oh-dialog-fade-in fixed inset-0 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.40)', zIndex: 2600 }}
      onClick={onClose}
    >
      <div
        class="oh-dialog-pop-in rounded-m3-md p-4 max-w-3xl w-full flex flex-col"
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline)',
          maxHeight: '84vh',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="flex items-center justify-between gap-3 mb-3">
          <div class="min-w-0">
            <h2 class="text-base font-semibold truncate">{t('topbar.audit', '会话审计')} · {session.title}</h2>
            <p class="text-xs mt-0.5" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {session.id}
            </p>
          </div>
          <div class="flex items-center gap-2 flex-none">
            <button
              type="button"
              class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline)' }}
              onClick={() => void copyJsonWithFeedback(json)}
            >
              {t('common.copy', '复制')}
            </button>
            <button
              type="button"
              class="oh-tap-press text-sm px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
              onClick={onClose}
            >
              {t('common.close', '关闭')}
            </button>
          </div>
        </header>
        <div class="flex flex-wrap gap-2 mb-3">
          {stats.map((item) => (
            <span
              key={item}
              class="text-xs px-2 py-1 rounded-full"
              style={{
                color: 'var(--m3-on-surface-variant)',
                background: 'var(--m3-surface)',
                border: '1px solid var(--m3-outline)',
              }}
            >
              {item}
            </span>
          ))}
        </div>
        <pre
          class="text-xs overflow-auto rounded-m3-sm p-3 whitespace-pre-wrap flex-1 min-h-0"
          style={{
            background: 'var(--m3-surface)',
            border: '1px solid var(--m3-outline)',
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
          }}
        >
          {json}
        </pre>
      </div>
    </div>
  );
  return typeof document === 'undefined' ? node : createPortal(node, document.body);
}
