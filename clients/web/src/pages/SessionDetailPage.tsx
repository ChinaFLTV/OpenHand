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
//   GET   /api/sessions/:id/messages?limit=&offset=&tail= → {session, items, offset, limit, total, has_more, send_phase, last_error}
//   POST  /api/sessions/:id/messages  body {content, mode, model_key, attachments}
//   POST  /api/sessions/:id/stop     body {}

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { useRoute } from 'preact-iso';
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
  compactSession,
  type CompactSessionResponse,
  type CompactSessionStatus,
  type SendMessageAttachment,
  type SessionDetailResponse,
  type SessionMessage,
  type SessionSummary,
} from '../api/sessions';
import { ApiError, UnauthorizedError } from '../api/client';
import { subscribeSessionEvents, type PendingWriteApproval } from '../api/session_events';
import { listSessions } from '../api/sessions';
import { SessionGoneDialog } from '../components/SessionGoneDialog';
import { t } from '../i18n';
import { useAuth } from '../state/auth';
import type { ApiMetaInstruction, ApiMetaModel, ApiMetaShortcutBinding } from '../api/meta';
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
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { getDialogExitDurationMs } from '../hooks/useDialogMotionSettings';
import { useEventCallback } from '../hooks/useEventCallback';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { showSnackbar } from '../components/Snackbar';
import { OverlayPortal } from '../components/OverlayPortal';
import { copyTextToClipboard } from '../utils/clipboard';
import { buildSessionAssetUrl } from '../utils/session_asset';
import { PopMenu } from '../components/PopMenu';
import { listSkills, type SkillSummary } from '../api/toolbox';
import {
  ImageEditorDialog,
  type ImageEditorInput,
  type ImageEditorResult,
} from '../components/ImageEditorDialog';

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
const COMPOSER_CHIP_EXIT_MS = 190;
const QUEUE_SEND_SETTLE_MS = 600;
const COMPOSER_COLLAPSED_STORAGE_KEY = 'openhand.web.composer_collapsed';
const DEFAULT_COMPOSER_MODES = ['normal', 'image', 'video', 'audio', 'deep_research'];

function readPersistedComposerCollapsed(): boolean {
  try {
    return window.localStorage.getItem(COMPOSER_COLLAPSED_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

function persistComposerCollapsed(value: boolean): void {
  try {
    if (value) {
      window.localStorage.setItem(COMPOSER_COLLAPSED_STORAGE_KEY, '1');
    } else {
      window.localStorage.removeItem(COMPOSER_COLLAPSED_STORAGE_KEY);
    }
  } catch {
    // private mode / quota errors should never block typing.
  }
}

async function copyJsonWithFeedback(json: string): Promise<void> {
  const ok = await copyTextToClipboard(json);
  showSnackbar(ok
    ? t('common.copied', '已复制')
    : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
}

// 时间戳与角色标签现在由 MessageCard 内部处理，本页不再直接使用。

interface MergeServerWindowOptions {
  preserveLocalStreamingTail?: boolean;
}

export interface MergeServerWindowResult {
  items: SessionMessage[];
  offset: number;
}

function isRunningPhase(phase: string | null | undefined): boolean {
  return Boolean(phase && phase !== 'idle');
}

export function shouldApplySessionAsyncResult(
  currentSessionId: string,
  requestSessionId: string,
  componentMounted = true,
): boolean {
  return componentMounted && requestSessionId.length > 0 && currentSessionId === requestSessionId;
}

function isStreamingTailMessage(message: SessionMessage): boolean {
  return message.role === 'assistant' || message.role === 'tool';
}

function isAssistantTextLikeMessage(message: SessionMessage): boolean {
  if (message.role !== 'assistant') return false;
  return ![
    'tool',
    'tool_call',
    'mcp',
    'skill',
    'hook',
    'status',
    'compression_point',
    'file_mutation_summary',
    'self_learning',
  ].includes(message.kind);
}

function messageMetadataStreaming(message: SessionMessage): boolean {
  const value = message.metadata?.streaming;
  return value === true || value === 'true' || value === 1 || value === '1';
}

function shouldKeepLongerStreamingMessage(
  existing: SessionMessage | undefined,
  incoming: SessionMessage,
  options: MergeServerWindowOptions,
): boolean {
  return Boolean(
    options.preserveLocalStreamingTail &&
    existing &&
    existing.id === incoming.id &&
    existing.kind === incoming.kind &&
    existing.role === incoming.role &&
    isStreamingTailMessage(existing) &&
    existing.content.length > incoming.content.length,
  );
}

/// 流式增量合并：保留与上一次 snapshot 相同的对象引用，仅替换发生变化的尾巴消息。
/// 使 `<MessageCard memo>` 在 SSE 80ms 推流期间跳过不变前缀的重新 diff，
/// 让流式更新感觉真正像"逐字增长"而不是"全帧重排"。
export function mergeStream(
  prev: SessionMessage[],
  next: SessionMessage[],
  options: MergeServerWindowOptions = {},
): SessionMessage[] {
  if (prev === next) return prev;
  if (prev.length === 0 || next.length === 0) return next;
  // 长度变化或前缀 id 不一致 → 走完整替换；其他场景按 id+content+metadata 比较保留引用。
  const out: SessionMessage[] = new Array(next.length);
  let identical = prev.length === next.length;
  for (let i = 0; i < next.length; i += 1) {
    const a = i < prev.length ? prev[i] : undefined;
    const b = next[i];
    if (shouldKeepLongerStreamingMessage(a, b, options)) {
      out[i] = a!;
    } else if (
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

function appendLocalStreamingTail(
  prev: SessionMessage[],
  merged: SessionMessage[],
): SessionMessage[] {
  if (prev.length === 0 || merged.length === 0) return merged;
  const mergedIndexById = new Map<string, number>();
  merged.forEach((item, index) => mergedIndexById.set(item.id, index));
  let prevSharedIndex = -1;
  let mergedSharedIndex = -1;
  for (let index = prev.length - 1; index >= 0; index -= 1) {
    const match = mergedIndexById.get(prev[index]!.id);
    if (match != null) {
      prevSharedIndex = index;
      mergedSharedIndex = match;
      break;
    }
  }
  if (prevSharedIndex < 0 || mergedSharedIndex !== merged.length - 1) return merged;
  const suffix = prev.slice(prevSharedIndex + 1);
  if (suffix.length === 0 || !suffix.every(isStreamingTailMessage)) return merged;
  return [...merged, ...suffix];
}

export function mergeServerWindowResult(
  prev: SessionMessage[],
  latest: SessionMessage[],
  currentOffset: number,
  nextOffset: number,
  options: MergeServerWindowOptions = {},
): MergeServerWindowResult {
  if (prev.length === 0) return { items: latest, offset: nextOffset };
  if (options.preserveLocalStreamingTail && latest.length === 0) {
    return { items: prev, offset: currentOffset };
  }
  if (nextOffset < currentOffset) {
    if (options.preserveLocalStreamingTail) {
      const firstPrev = prev[0];
      const overlapIndex = firstPrev
        ? latest.findIndex((item) => item.id === firstPrev.id)
        : -1;
      if (overlapIndex >= 0) {
        const merged = mergeStream(prev, latest.slice(overlapIndex), options);
        return {
          items: appendLocalStreamingTail(prev, merged),
          offset: currentOffset,
        };
      }
      return { items: prev, offset: currentOffset };
    }
    return { items: latest, offset: nextOffset };
  }
  const prefixCount = nextOffset - currentOffset;
  if (prefixCount <= 0) {
    const merged = mergeStream(prev, latest, options);
    return {
      items: options.preserveLocalStreamingTail
        ? appendLocalStreamingTail(prev, merged)
        : merged,
      offset: currentOffset,
    };
  }
  if (prefixCount > prev.length) return { items: latest, offset: nextOffset };
  if (options.preserveLocalStreamingTail && latest.length > 0) {
    const suffix = prev.slice(prefixCount);
    const firstLatestId = latest[0]?.id;
    const expectedFirstId = suffix[0]?.id;
    if (suffix.length > 0 && firstLatestId && expectedFirstId !== firstLatestId) {
      const overlapIndex = suffix.findIndex((item) => item.id === firstLatestId);
      if (overlapIndex > 0) {
        const prefix = prev.slice(0, prefixCount + overlapIndex);
        const merged = [
          ...prefix,
          ...mergeStream(prev.slice(prefixCount + overlapIndex), latest, options),
        ];
        return {
          items: appendLocalStreamingTail(prev, merged),
          offset: currentOffset,
        };
      }
      if (overlapIndex < 0 && suffix.some(isStreamingTailMessage)) {
        return { items: prev, offset: currentOffset };
      }
    }
  }
  const prefix = prev.slice(0, prefixCount);
  const merged = [...prefix, ...mergeStream(prev.slice(prefixCount), latest, options)];
  return {
    items: options.preserveLocalStreamingTail
      ? appendLocalStreamingTail(prev, merged)
      : merged,
    offset: currentOffset,
  };
}

export function mergeServerWindow(
  prev: SessionMessage[],
  latest: SessionMessage[],
  currentOffset: number,
  nextOffset: number,
  options: MergeServerWindowOptions = {},
): SessionMessage[] {
  return mergeServerWindowResult(prev, latest, currentOffset, nextOffset, options).items;
}

function sessionModeLabel(mode: string): string {
  return mode === 'plan'
    ? t('sessions.mode.plan', '计划模式')
    : t('sessions.mode.chat', '聊天模式');
}

type ComposerIconName =
  | 'attachment'
  | 'chat'
  | 'chevronDown'
  | 'chevronUp'
  | 'close'
  | 'copy'
  | 'edit'
  | 'file'
  | 'image'
  | 'model'
  | 'mode'
  | 'plan'
  | 'permission'
  | 'plus'
  | 'research'
  | 'refresh'
  | 'send'
  | 'sound'
  | 'spark'
  | 'stop'
  | 'video'
  | 'follow';

function sessionModeIconName(mode: string): ComposerIconName {
  return mode === 'plan' ? 'plan' : 'chat';
}

function composerModeIconName(mode: string): ComposerIconName {
  switch (mode) {
    case 'plan':
      return 'plan';
    case 'image':
      return 'image';
    case 'video':
      return 'video';
    case 'audio':
      return 'sound';
    case 'deep_research':
      return 'research';
    case 'normal':
      return 'chat';
    default:
      return 'mode';
  }
}

function ComposerIcon({ name, size = 18 }: { name: ComposerIconName; size?: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    'aria-hidden': true,
    focusable: 'false',
  };
  const stroke = {
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 2,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
  };
  switch (name) {
    case 'attachment':
      return <svg {...common}><path {...stroke} d="M21.4 11.6 12 21a5.2 5.2 0 0 1-7.4-7.4l9.7-9.7a3.5 3.5 0 0 1 5 5l-9.8 9.8a1.8 1.8 0 0 1-2.6-2.6l8.9-8.9" /></svg>;
    case 'chat':
      return <svg {...common}><path {...stroke} d="M5 6.5A3.5 3.5 0 0 1 8.5 3h7A3.5 3.5 0 0 1 19 6.5v5A3.5 3.5 0 0 1 15.5 15h-4.7L6 19v-4.2a3.5 3.5 0 0 1-1-2.3z" /><path {...stroke} d="M9 8h6M9 11h3.8" /></svg>;
    case 'chevronDown':
      return <svg {...common}><path {...stroke} d="m7 10 5 5 5-5" /></svg>;
    case 'chevronUp':
      return <svg {...common}><path {...stroke} d="m7 14 5-5 5 5" /></svg>;
    case 'close':
      return <svg {...common}><path {...stroke} d="M7 7l10 10M17 7 7 17" /></svg>;
    case 'copy':
      return <svg {...common}><rect {...stroke} x="8" y="8" width="11" height="11" rx="2" /><path {...stroke} d="M5 15V7a2 2 0 0 1 2-2h8" /></svg>;
    case 'edit':
      return <svg {...common}><path {...stroke} d="M4 20h4.4L19 9.4A2.1 2.1 0 0 0 16 6.4L5.4 17H4z" /><path {...stroke} d="m14.8 7.6 1.6 1.6" /></svg>;
    case 'file':
      return <svg {...common}><path {...stroke} d="M7 3h6l4 4v14H7z" /><path {...stroke} d="M13 3v5h5M9 13h6M9 17h4" /></svg>;
    case 'follow':
      return <svg {...common}><path {...stroke} d="M12 5v10M8 11l4 4 4-4M5 19h14" /></svg>;
    case 'refresh':
      return <svg {...common}><path {...stroke} d="M4 12a8 8 0 0 1 13.4-5.9" /><path {...stroke} d="M17 3v4h-4" /><path {...stroke} d="M20 12a8 8 0 0 1-13.4 5.9" /><path {...stroke} d="M7 21v-4h4" /></svg>;
    case 'image':
      return <svg {...common}><path {...stroke} d="M5 5h14v14H5z" /><path {...stroke} d="m5 16 4.5-4.5 3.5 3.5 2-2 4 4" /><path {...stroke} d="M14.5 8.5h.01" /></svg>;
    case 'model':
      return <svg {...common}><rect {...stroke} x="7" y="7" width="10" height="10" rx="2" /><path {...stroke} d="M9 3v4M15 3v4M9 17v4M15 17v4M3 9h4M3 15h4M17 9h4M17 15h4" /><path {...stroke} d="M10 12h4" /></svg>;
    case 'mode':
      return <svg {...common}><path {...stroke} d="M5 7h8M17 7h2M5 12h2M11 12h8M5 17h10M19 17h0" /><path {...stroke} d="M13 5v4M9 10v4M15 15v4" /></svg>;
    case 'permission':
      return <svg {...common}><path {...stroke} d="M12 3 5 6v5c0 4.4 2.8 8.4 7 10 4.2-1.6 7-5.6 7-10V6z" /><path {...stroke} d="m9.5 12 1.7 1.7 3.6-4" /></svg>;
    case 'plan':
      return <svg {...common}><path {...stroke} d="M7 4h10a2 2 0 0 1 2 2v14H5V6a2 2 0 0 1 2-2z" /><path {...stroke} d="M9 8h6M9 12h6M9 16h3" /><path {...stroke} d="m15 16 1.2 1.2L19 14.4" /></svg>;
    case 'plus':
      return <svg {...common}><path {...stroke} d="M12 5v14M5 12h14" /></svg>;
    case 'research':
      return <svg {...common}><path {...stroke} d="M10.5 18a7.5 7.5 0 1 1 5.3-2.2L21 21" /><path {...stroke} d="M8 10h5M8 13h3" /></svg>;
    case 'send':
      return <svg {...common}><path {...stroke} d="M4 12 20 4l-5 16-3-7z" /><path {...stroke} d="m12 13 4-5" /></svg>;
    case 'sound':
      return <svg {...common}><path {...stroke} d="M4 10v4h4l5 4V6L8 10z" /><path {...stroke} d="M16 9.5a4 4 0 0 1 0 5M19 7a8 8 0 0 1 0 10" /></svg>;
    case 'spark':
      return <svg {...common}><path {...stroke} d="m12 3 1.6 5.2L19 10l-5.4 1.8L12 17l-1.6-5.2L5 10l5.4-1.8z" /><path {...stroke} d="M19 16v4M17 18h4" /></svg>;
    case 'stop':
      return <svg {...common}><rect {...stroke} x="7" y="7" width="10" height="10" rx="2" /></svg>;
    case 'video':
      return <svg {...common}><path {...stroke} d="M5 7h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5z" /><path {...stroke} d="m17 10 4-2.5v9L17 14" /></svg>;
    default:
      return <svg {...common}><path {...stroke} d="M12 3v18M3 12h18" /></svg>;
  }
}

/// Web composer 用户指令胶囊条（与 App 端 _ComposerInstructionsStrip 1:1 对齐）。
///
/// 增强：
/// - hover/focus 1 秒延时弹出预览卡片，显示 description / 截断后的 body；
///   预览卡片走 OverlayPortal 投射到 body，避开 oh-composer-body 的 overflow: clip
///   与 fullscreen containing block。
/// - Ctrl+1..Ctrl+9（macOS 同时也响应 Meta+1..Meta+9）切换前 9 个胶囊的跳过状态，
///   Ctrl+0 / Meta+0 重置：所有指令重新生效（清空跳过集合）。
function ComposerInstructionsStrip({
  entries,
  skipped,
  disabled,
  onToggle,
  onResetAll,
  t,
}: {
  entries: ApiMetaInstruction[];
  skipped: Set<string>;
  disabled: boolean;
  onToggle: (id: string) => void;
  onResetAll?: () => void;
  t: (key: string, fallback: string) => string;
}) {
  const [hoverEntry, setHoverEntry] = useState<{
    entry: ApiMetaInstruction;
    rect: DOMRect;
  } | null>(null);
  const hoverTimerRef = useRef<number | null>(null);
  const cancelHover = useCallback(() => {
    if (hoverTimerRef.current != null) {
      window.clearTimeout(hoverTimerRef.current);
      hoverTimerRef.current = null;
    }
    setHoverEntry(null);
  }, []);
  useEffect(() => () => cancelHover(), [cancelHover]);

  // Ctrl/Meta + 0..9 快捷键：与 App 端 hardness 同款思路，
  // 全局监听 keydown，仅在没有命中文本输入复合键（IME composing）时生效。
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent): void {
      if (!(e.ctrlKey || e.metaKey)) return;
      if (e.altKey || e.shiftKey) return;
      if (e.isComposing) return;
      const key = e.key;
      if (key.length !== 1) return;
      const digit = key.charCodeAt(0) - 48;
      if (digit < 0 || digit > 9) return;
      e.preventDefault();
      if (disabled) return;
      if (digit === 0) {
        if (onResetAll) {
          onResetAll();
        } else {
          // 兜底：逐个清空。
          for (const id of skipped) onToggle(id);
        }
        return;
      }
      const entry = entries[digit - 1];
      if (!entry) return;
      onToggle(entry.id);
    }
    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true } as EventListenerOptions);
  }, [entries, skipped, disabled, onToggle, onResetAll]);

  function scheduleHover(entry: ApiMetaInstruction, target: HTMLElement): void {
    if (hoverTimerRef.current != null) window.clearTimeout(hoverTimerRef.current);
    hoverTimerRef.current = window.setTimeout(() => {
      hoverTimerRef.current = null;
      setHoverEntry({ entry, rect: target.getBoundingClientRect() });
    }, 480);
  }

  return (
    <div class="oh-composer-instructions-strip mb-3" role="group" aria-label={t('composer.instructions.aria', '当前会话生效的用户指令')}>
      <span class="oh-composer-instructions-strip-label">
        {t('composer.instructions.label', '用户指令')}
      </span>
      <div class="oh-composer-instructions-strip-list">
        {entries.map((entry, index) => {
          const isSkipped = skipped.has(entry.id);
          const baseTip = entry.description?.trim()
            ? entry.description
            : isSkipped
              ? t('composer.instructions.tooltipSkipped', '点击恢复：本轮临时跳过此指令')
              : t('composer.instructions.tooltipActive', '点击跳过：本轮临时不携带此指令');
          // 前 9 项追加快捷键提示
          const hotkey = index < 9
            ? ` · ${navigator.platform.toLowerCase().includes('mac') ? '⌘' : 'Ctrl'}${index + 1}`
            : '';
          return (
            <button
              key={entry.id}
              type="button"
              class={`oh-composer-instruction-pill oh-tap-press${isSkipped ? ' is-skipped' : ''}`}
              data-skipped={isSkipped ? 'true' : 'false'}
              title={baseTip + hotkey}
              aria-pressed={isSkipped ? 'false' : 'true'}
              onClick={() => onToggle(entry.id)}
              onMouseEnter={(e) => scheduleHover(entry, e.currentTarget as HTMLElement)}
              onMouseLeave={cancelHover}
              onFocus={(e) => scheduleHover(entry, e.currentTarget as HTMLElement)}
              onBlur={cancelHover}
              disabled={disabled}
            >
              <span class="oh-composer-instruction-pill-icon" aria-hidden="true">
                <ComposerIcon name="spark" size={14} />
              </span>
              <span class="oh-composer-instruction-pill-label">
                {entry.name?.trim() || entry.id}
              </span>
              <span class="oh-composer-instruction-pill-toggle" aria-hidden="true">
                <ComposerIcon name={isSkipped ? 'plus' : 'close'} size={13} />
              </span>
            </button>
          );
        })}
      </div>
      {hoverEntry ? (
        <ComposerInstructionPreviewCard hover={hoverEntry} t={t} />
      ) : null}
    </div>
  );
}

function ComposerInstructionPreviewCard({
  hover,
  t,
}: {
  hover: { entry: ApiMetaInstruction; rect: DOMRect };
  t: (key: string, fallback: string) => string;
}) {
  const { entry, rect } = hover;
  // 与 OverlayPortal 注释一致：position: fixed 锚定胶囊矩形。
  // 上方空间不足时下翻，并把 max-height 限在可用空间内，避免上边缘被视口裁切。
  const cardWidth = 360;
  const margin = 12;
  const gap = 10;
  const left = Math.max(margin, Math.min(rect.left, window.innerWidth - cardWidth - margin));
  const rawAbove = Math.max(0, rect.top - margin - gap);
  const rawBelow = Math.max(0, window.innerHeight - rect.bottom - margin - gap);
  const placeAbove = rawAbove >= 180 || rawAbove >= rawBelow;
  const availableHeight = Math.max(
    120,
    Math.min(480, placeAbove ? rawAbove : rawBelow, window.innerHeight - margin * 2),
  );
  const cardStyle: Record<string, string> = {
    position: 'fixed',
    left: `${left}px`,
    width: `${cardWidth}px`,
    maxHeight: `${availableHeight}px`,
  };
  if (placeAbove) {
    cardStyle.bottom = `${Math.max(margin, window.innerHeight - rect.top + gap)}px`;
  } else {
    cardStyle.top = `${Math.min(window.innerHeight - margin - availableHeight, rect.bottom + gap)}px`;
  }
  const description = entry.description?.trim();
  const body = entry.body?.trim();
  return (
    <OverlayPortal>
      <div
        class="oh-composer-instruction-preview"
        data-placement={placeAbove ? 'above' : 'below'}
        role="tooltip"
        style={cardStyle}
      >
        <div class="oh-composer-instruction-preview-title">
          {entry.name?.trim() || entry.id}
        </div>
        {description ? (
          <div class="oh-composer-instruction-preview-desc">{description}</div>
        ) : null}
        {body ? (
          <pre class="oh-composer-instruction-preview-body">{body}</pre>
        ) : (
          <div class="oh-composer-instruction-preview-empty">
            {t('composer.instructions.previewEmpty', '此指令暂无正文。')}
          </div>
        )}
        {entry.body_truncated ? (
          <div class="oh-composer-instruction-preview-foot">
            {t('composer.instructions.previewTruncated', '正文已截断 · 完整内容请在 App 端查看')}
          </div>
        ) : null}
      </div>
    </OverlayPortal>
  );
}

interface EditableAttachmentAsset {
  path: string;
  name: string;
  mime?: string;
}

function basename(path: string): string {
  const i = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i >= 0 ? path.slice(i + 1) : path;
}

function pushEditableAttachmentAsset(
  out: EditableAttachmentAsset[],
  rawPath: unknown,
  rawName?: unknown,
  rawMime?: unknown,
): void {
  if (typeof rawPath !== 'string') return;
  const path = rawPath.trim();
  if (!path || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
    return;
  }
  out.push({
    path,
    name: typeof rawName === 'string' && rawName.trim() ? rawName.trim() : basename(path),
    mime: typeof rawMime === 'string' && rawMime.trim() ? rawMime.trim() : undefined,
  });
}

function collectEditableAttachmentAssets(message: SessionMessage): EditableAttachmentAsset[] {
  const meta = message.metadata as Record<string, unknown> | undefined;
  if (!meta) return [];
  const out: EditableAttachmentAsset[] = [];
  const attachments = meta['attachments'];
  if (Array.isArray(attachments)) {
    for (const entry of attachments) {
      if (entry && typeof entry === 'object') {
        const item = entry as Record<string, unknown>;
        const name = item['name'] ?? item['file_name'] ?? item['original_name'];
        const mime = item['mime'] ?? item['content_type'];
        pushEditableAttachmentAsset(
          out,
          item['storage_path'] ?? item['path'] ?? item['file_path'] ?? item['original_source_path'],
          name,
          mime,
        );
      } else {
        pushEditableAttachmentAsset(out, entry);
      }
    }
  }
  const seen = new Set<string>();
  return out.filter((item) => {
    if (seen.has(item.path)) return false;
    seen.add(item.path);
    return true;
  });
}

function sameJsonValue(
  a: unknown,
  b: unknown,
  seen: WeakMap<object, WeakSet<object>> = new WeakMap(),
): boolean {
  if (Object.is(a, b)) return true;
  if (a == null || b == null) return false;
  if (typeof a !== typeof b) return false;
  if (typeof a !== 'object' || typeof b !== 'object') return false;
  const aObj = a as Record<string, unknown>;
  const bObj = b as Record<string, unknown>;
  let paired = seen.get(aObj);
  if (paired?.has(bObj)) return true;
  if (!paired) {
    paired = new WeakSet<object>();
    seen.set(aObj, paired);
  }
  paired.add(bObj);

  const aIsArray = Array.isArray(a);
  const bIsArray = Array.isArray(b);
  if (aIsArray || bIsArray) {
    if (!aIsArray || !bIsArray) return false;
    const aArray = a as unknown[];
    const bArray = b as unknown[];
    if (aArray.length !== bArray.length) return false;
    for (let i = 0; i < aArray.length; i += 1) {
      if (!sameJsonValue(aArray[i], bArray[i], seen)) return false;
    }
    return true;
  }

  const aKeys = Object.keys(aObj);
  const bKeys = Object.keys(bObj);
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) {
    if (!Object.prototype.hasOwnProperty.call(bObj, key)) return false;
    if (!sameJsonValue(aObj[key], bObj[key], seen)) return false;
  }
  return true;
}

function sameMetadata(a: unknown, b: unknown): boolean {
  return sameJsonValue(a, b);
}

function compareMessageCreatedAt(a: SessionMessage, b: SessionMessage): number {
  const ta = new Date(a.created_at).getTime();
  const tb = new Date(b.created_at).getTime();
  if (Number.isNaN(ta) || Number.isNaN(tb)) return 0;
  return ta - tb;
}

function messagesAreChronological(items: SessionMessage[]): boolean {
  for (let i = 1; i < items.length; i += 1) {
    if (compareMessageCreatedAt(items[i - 1]!, items[i]!) > 0) return false;
  }
  return true;
}

function mergeSessionSummary(
  previous: SessionDetailResponse['session'],
  incoming: SessionDetailResponse['session'],
): SessionDetailResponse['session'] {
  return {
    ...previous,
    ...incoming,
    metadata: incoming.metadata ?? previous.metadata,
    web_context: incoming.web_context ?? previous.web_context,
    environment: incoming.environment ?? previous.environment,
    last_prompt_metadata: incoming.last_prompt_metadata ?? previous.last_prompt_metadata,
    plan_history: incoming.plan_history ?? previous.plan_history,
    recent_errors: incoming.recent_errors ?? previous.recent_errors,
    latest_compression_point: incoming.latest_compression_point ?? previous.latest_compression_point,
  };
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
    case 'plan':
      return true;
    default:
      return true;
  }
}

function composerModeLabel(mode: string): string {
  switch (mode) {
    case 'normal':
      return t('composer.mode.normal', '文本模式');
    case 'image':
      return t('composer.mode.image', '图像');
    case 'video':
      return t('composer.mode.video', '视频');
    case 'audio':
      return t('composer.mode.audio', '音频');
    case 'plan':
      return t('composer.mode.plan', '计划模式');
    case 'deep_research':
      return t('composer.mode.deepResearch', '深度研究');
    default:
      return mode;
  }
}

function allComposerModes(allowedModes: string[]): string[] {
  const merged = new Set<string>([...allowedModes, ...DEFAULT_COMPOSER_MODES]);
  return [...merged];
}

function parseShortcutLabel(binding: ApiMetaShortcutBinding | undefined, fallback: string[]): string[] {
  const label = binding?.label?.trim();
  const source = label && label !== 'Not set' ? label.split('+') : fallback;
  return source.map((token) => token.trim().toLowerCase()).filter(Boolean);
}

function keyMatchesShortcutToken(event: KeyboardEvent, token: string): boolean {
  const key = event.key.toLowerCase();
  switch (token) {
    case 'enter':
      return key === 'enter';
    case 'esc':
    case 'escape':
      return key === 'escape';
    case 'space':
      return key === ' ' || key === 'spacebar';
    case 'tab':
      return key === 'tab';
    case '←':
      return key === 'arrowleft';
    case '→':
      return key === 'arrowright';
    case '↑':
      return key === 'arrowup';
    case '↓':
      return key === 'arrowdown';
    default:
      return key === token;
  }
}

function eventMatchesShortcut(
  event: KeyboardEvent,
  binding: ApiMetaShortcutBinding | undefined,
  fallback: string[],
): boolean {
  const tokens = parseShortcutLabel(binding, fallback);
  if (tokens.length === 0) return false;
  const needsCtrl = tokens.includes('ctrl');
  const needsShift = tokens.includes('shift');
  const needsAlt = tokens.includes('alt');
  const needsMeta = tokens.includes('cmd') || tokens.includes('meta');
  if (event.ctrlKey !== needsCtrl) return false;
  if (event.shiftKey !== needsShift) return false;
  if (event.altKey !== needsAlt) return false;
  if (event.metaKey !== needsMeta) return false;
  const keyTokens = tokens.filter(
    (token) => !['ctrl', 'shift', 'alt', 'cmd', 'meta'].includes(token),
  );
  return keyTokens.length === 1 && keyMatchesShortcutToken(event, keyTokens[0]!);
}

function isEditableShortcutTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return Boolean(target.closest('input,textarea,select,[contenteditable="true"]'));
}

interface RouteParams {
  id?: string;
}

interface QueuedComposerMessage {
  id: string;
  content: string;
  attachments: SendMessageAttachment[];
  modelKey: string;
  modelLabel: string;
  mode: string;
  selectedSkill: {
    name: string;
    relative_directory_path: string;
  } | null;
  skillLabel: string | null;
  /// 排队时快照下来的本轮跳过指令 id；与 send 时实参一致，
  /// 保证排队消息被实际派发时仍按用户最初意图过滤指令。
  skippedInstructionIds: string[];
  createdAt: number;
}

export interface ComposerCollapsedSummaryState {
  textLength: number;
  attachmentCount: number;
  queuedCount: number;
  editing: boolean;
  responseRunning: boolean;
}

export interface ComposerCollapsedSummaryLabels {
  draft: string;
  charUnit: string;
  attachments: string;
  queue: string;
  editing: string;
  running: string;
}

export function composerCollapsedSummaryParts(
  state: ComposerCollapsedSummaryState,
  labels: ComposerCollapsedSummaryLabels,
): string[] {
  const parts: string[] = [];
  if (state.editing) parts.push(labels.editing);
  if (state.responseRunning) parts.push(labels.running);
  if (state.queuedCount > 0) parts.push(`${labels.queue} ${state.queuedCount}`);
  if (state.attachmentCount > 0) parts.push(`${labels.attachments} ${state.attachmentCount}`);
  if (state.textLength > 0) parts.push(`${labels.draft} ${state.textLength.toLocaleString()} ${labels.charUnit}`);
  return parts;
}

export function SessionDetailPage() {
  const auth = useAuth();
  const location = useAnimatedLocation();
  const reduceMotion = useReducedMotion();
  const routeMatch = useRoute() as { params?: RouteParams } | undefined;
  const sessionId = routeMatch?.params?.id ?? '';
  const pageRootRef = useRef<HTMLElement | null>(null);
  const mainRef = useRef<HTMLElement | null>(null);
  const messagesContentRef = useRef<HTMLDivElement | null>(null);
  const composerSectionRef = useRef<HTMLElement | null>(null);
  const messagesRef = useRef<SessionMessage[]>([]);
  const windowOffsetRef = useRef(0);

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
  const [composerAttachmentIds, setComposerAttachmentIds] = useState<string[]>([]);
  const [editingDraftMessage, setEditingDraftMessage] =
    useState<SessionMessage | null>(null);
  const [selectedSkill, setSelectedSkill] = useState<SkillSummary | null>(null);
  // 与 App 端 `_skippedInstructionIds` 1:1 对齐：本轮临时跳过的用户指令 id 集合，
  // 仅作用于本次发送，不持久化。每次切换会话时清空，避免上一会话的跳过状态泄漏。
  const [skippedInstructionIds, setSkippedInstructionIds] = useState<Set<string>>(() => new Set());
  const [skills, setSkills] = useState<SkillSummary[]>([]);
  const [skillPickerOpen, setSkillPickerOpen] = useState(false);
  const [skillPickerQuery, setSkillPickerQuery] = useState('');
  const [skillPickerLoading, setSkillPickerLoading] = useState(false);
  const [skillPickerSelectedIndex, setSkillPickerSelectedIndex] = useState(0);
  const [slashDismissedToken, setSlashDismissedToken] = useState<string | null>(null);
  // 技能浮窗渲染态：用 visible+closing 双层让退场动效跑完再卸载，
  // 配合全局 dialog 动画设置（oh-dialog-pop-in / oh-dialog-pop-out）。
  const [skillPickerVisible, setSkillPickerVisible] = useState(false);
  const [skillPickerClosing, setSkillPickerClosing] = useState(false);
  const [skillPickerAnchor, setSkillPickerAnchor] = useState<
    { bottomGap: number; left: number; width: number; maxHeight: number } | null
  >(null);
  const skillPickerCloseTimerRef = useRef<number | null>(null);
  // 附件预览 (image/* → dataURL); key 与 composerAttachments 同序
  const [attachmentPreviews, setAttachmentPreviews] = useState<
    { mime: string; dataUrl: string; size: number }[]
  >([]);
  const [exitingComposerChipKeys, setExitingComposerChipKeys] = useState<string[]>([]);
  const [dragOver, setDragOver] = useState<boolean>(false);
  const [composerSending, setComposerSending] = useState<boolean>(false);
  const [composerError, setComposerError] = useState<string | null>(null);
  const [queuedComposerMessages, setQueuedComposerMessages] = useState<QueuedComposerMessage[]>([]);
  const [exitingQueuedMessageIds, setExitingQueuedMessageIds] = useState<string[]>([]);
  const [editingQueuedMessageId, setEditingQueuedMessageId] = useState<string | null>(null);
  const [queuedEditText, setQueuedEditText] = useState('');
  const [queueDispatchingId, setQueueDispatchingId] = useState<string | null>(null);
  const [queuedListMotionGeneration, setQueuedListMotionGeneration] = useState(0);
  const [stopping, setStopping] = useState<boolean>(false);
  const [composerCollapsed, setComposerCollapsed] = useState(
    readPersistedComposerCollapsed,
  );
  const [autoFollow, setAutoFollow] = useState(true);
  const [autoFollowPaused, setAutoFollowPaused] = useState(false);
  const [fullscreenActive, setFullscreenActive] = useState(false);
  const [showComposerModelPicker, setShowComposerModelPicker] = useState(false);
  const [permissionSaving, setPermissionSaving] = useState(false);
  const [pendingFullAccess, setPendingFullAccess] = useState<boolean | null>(null);
  const [pendingWriteApproval, setPendingWriteApproval] = useState<PendingWriteApproval | null>(null);
  const [writeApprovalBusy, setWriteApprovalBusy] = useState(false);

  const detailAbortRef = useRef<AbortController | null>(null);
  const messagesAbortRef = useRef<AbortController | null>(null);
  const olderMessagesAbortRef = useRef<AbortController | null>(null);
  const pollTimerRef = useRef<number | null>(null);
  const sseCloseRef = useRef<(() => void) | null>(null);
  const composerTextareaRef = useRef<HTMLTextAreaElement | null>(null);
  const imageEditorResolverRef = useRef<((result: ImageEditorResult | null) => void) | null>(null);
  const skillsLoadedRef = useRef(false);
  const detailRef = useRef<SessionDetailResponse | null>(null);
  const sessionIdRef = useRef(sessionId);
  const mountedRef = useRef(true);
  const editingDraftMessageRef = useRef<SessionMessage | null>(null);
  const autoTitleRefreshTimersRef = useRef<number[]>([]);
  const composerChipExitTimersRef = useRef<number[]>([]);
  const queuedMessageExitTimersRef = useRef<number[]>([]);
  const queuedComposerMessagesRef = useRef<QueuedComposerMessage[]>([]);
  const queuedMessageSeqRef = useRef(0);
  const queueDispatchingRef = useRef(false);
  const composerAttachmentIdsRef = useRef<string[]>([]);
  const attachmentIdSeqRef = useRef(0);
  // 跨客户端协同: 自动跟随到底 + 远端发送冲突警告
  // ---------------------------------------------------------------------
  // 1) 自动跟随: 用户离底 ≤64px 视为「贴底」, 新消息追加时直接 scrollTo bottom;
  //    否则把 Composer 控制区切到「回到底部」状态, 点击回到底部并清零。
  // 2) 冲突警告: 本地 handleSend 触发会写 lastLocalSendAtRef. 当 sendPhase 转入
  //    运行态且距离最近一次本地 send > 4s, 视为「另一处客户端在生成」,
  //    若此时 composerText 非空 → 顶部黄色 banner 提示, 防止用户误以为自己刚发了。
  const isNearBottomRef = useRef<boolean>(true);
  const autoFollowRef = useRef<boolean>(true);
  const autoFollowPausedRef = useRef<boolean>(false);
  const programmaticScrollUntilRef = useRef<number>(0);
  const followFrameRef = useRef<number | null>(null);
  const followSettleFrameRef = useRef<number | null>(null);
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
  const [tokenStatsOpen, setTokenStatsOpen] = useState(false);
  const [contextStatsOpen, setContextStatsOpen] = useState(false);
  const [imageEditorInput, setImageEditorInput] = useState<ImageEditorInput | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [pendingSessionDelete, setPendingSessionDelete] = useState(false);
  const [sessionDeleteBusy, setSessionDeleteBusy] = useState(false);

  useEffect(() => {
    detailRef.current = detail;
  }, [detail]);

  useEffect(() => {
    sessionIdRef.current = sessionId;
  }, [sessionId]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  useEffect(() => {
    queuedComposerMessagesRef.current = queuedComposerMessages;
  }, [queuedComposerMessages]);

  useEffect(() => {
    queueDispatchingRef.current = false;
    setQueuedComposerMessages([]);
    setExitingQueuedMessageIds([]);
    setEditingQueuedMessageId(null);
    setQueuedEditText('');
    setQueueDispatchingId(null);
    setComposerSending(false);
    setStopping(false);
    setPendingDeleteAction(null);
    setDeleteBusy(false);
    setPendingSessionDelete(false);
    setSessionDeleteBusy(false);
    setPermissionSaving(false);
    setPendingFullAccess(null);
    setWriteApprovalBusy(false);
    setPendingWriteApproval(null);
    setSessionGone(false);
    setSessionAuditOpen(false);
    setAuditMessage(null);
    setSessionMetadataOpen(false);
    setTokenStatsOpen(false);
    setContextStatsOpen(false);
    imageEditorResolverRef.current?.(null);
    imageEditorResolverRef.current = null;
    setImageEditorInput(null);
    // 与 App 端 _skippedInstructionIds 一致：会话切换时清空跳过集合，
    // 避免上一会话的跳过状态泄漏到新会话。
    setSkippedInstructionIds(new Set());
  }, [sessionId]);

  useEffect(() => () => {
    imageEditorResolverRef.current?.(null);
    imageEditorResolverRef.current = null;
  }, []);

  useEffect(() => () => {
    for (const timer of composerChipExitTimersRef.current) {
      window.clearTimeout(timer);
    }
    composerChipExitTimersRef.current = [];
    for (const timer of queuedMessageExitTimersRef.current) {
      window.clearTimeout(timer);
    }
    queuedMessageExitTimersRef.current = [];
  }, []);

  useEffect(() => () => {
    if (followFrameRef.current != null) {
      window.cancelAnimationFrame(followFrameRef.current);
      followFrameRef.current = null;
    }
    if (followSettleFrameRef.current != null) {
      window.cancelAnimationFrame(followSettleFrameRef.current);
      followSettleFrameRef.current = null;
    }
  }, []);

  useEffect(() => {
    autoFollowRef.current = autoFollow;
  }, [autoFollow]);

  useEffect(() => {
    autoFollowPausedRef.current = autoFollowPaused;
  }, [autoFollowPaused]);

  function nextAttachmentUiId(): string {
    attachmentIdSeqRef.current += 1;
    return `att-${Date.now().toString(36)}-${attachmentIdSeqRef.current}`;
  }

  function nextQueuedMessageId(): string {
    queuedMessageSeqRef.current += 1;
    return `queued-${Date.now().toString(36)}-${queuedMessageSeqRef.current}`;
  }

  function composerChipIsExiting(key: string): boolean {
    return exitingComposerChipKeys.includes(key);
  }

  function queuedMessageIsExiting(id: string): boolean {
    return exitingQueuedMessageIds.includes(id);
  }

  function runAfterComposerChipExit(key: string, action: () => void): void {
    if (composerChipIsExiting(key)) return;
    if (reduceMotion || typeof window === 'undefined') {
      action();
      return;
    }
    setExitingComposerChipKeys((keys) => (keys.includes(key) ? keys : [...keys, key]));
    const timer = window.setTimeout(() => {
      action();
      setExitingComposerChipKeys((keys) => keys.filter((item) => item !== key));
      composerChipExitTimersRef.current = composerChipExitTimersRef.current.filter((item) => item !== timer);
    }, COMPOSER_CHIP_EXIT_MS);
    composerChipExitTimersRef.current.push(timer);
  }

  function runAfterQueuedMessageExit(id: string, action: () => void): void {
    if (queuedMessageIsExiting(id)) return;
    if (reduceMotion || typeof window === 'undefined') {
      action();
      return;
    }
    setExitingQueuedMessageIds((ids) => (ids.includes(id) ? ids : [...ids, id]));
    const timer = window.setTimeout(() => {
      action();
      setExitingQueuedMessageIds((ids) => ids.filter((item) => item !== id));
      queuedMessageExitTimersRef.current = queuedMessageExitTimersRef.current.filter((item) => item !== timer);
    }, COMPOSER_CHIP_EXIT_MS);
    queuedMessageExitTimersRef.current.push(timer);
  }

  const setAutoFollowEnabled = (value: boolean) => {
    autoFollowRef.current = value;
    setAutoFollow((current) => (current === value ? current : value));
  };

  const setAutoFollowPausedValue = (value: boolean) => {
    autoFollowPausedRef.current = value;
    setAutoFollowPaused((current) => (current === value ? current : value));
  };

  const clearUnreadCount = () => {
    setUnreadCount((count) => (count === 0 ? count : 0));
  };

  const pinMessagesToBottom = () => {
    const el = mainRef.current;
    if (!el) return;
    const bottomTop = Math.max(0, el.scrollHeight - el.clientHeight);
    if (Math.abs(el.scrollTop - bottomTop) > 0.5) {
      el.scrollTop = bottomTop;
    }
  };

  const scrollMessagesToBottom = (behavior: ScrollBehavior = 'auto') => {
    const el = mainRef.current;
    if (!el) return;
    programmaticScrollUntilRef.current = Date.now() + (behavior === 'smooth' ? 700 : 220);
    if (behavior === 'smooth') {
      el.scrollTo({ top: Math.max(0, el.scrollHeight - el.clientHeight), behavior });
    } else {
      pinMessagesToBottom();
    }
  };

  const scheduleFollowToBottom = (behavior: ScrollBehavior = 'auto') => {
    const el = mainRef.current;
    if (!el) return;
    programmaticScrollUntilRef.current = Date.now() + (behavior === 'smooth' ? 900 : 260);
    scrollMessagesToBottom(behavior);
    isNearBottomRef.current = true;
    setAutoFollowPausedValue(false);
    clearUnreadCount();
    if (behavior === 'auto') {
      if (followFrameRef.current != null) {
        window.cancelAnimationFrame(followFrameRef.current);
      }
      if (followSettleFrameRef.current != null) {
        window.cancelAnimationFrame(followSettleFrameRef.current);
        followSettleFrameRef.current = null;
      }
      followFrameRef.current = requestAnimationFrame(() => {
        followFrameRef.current = null;
        if (!shouldFollowPinnedMessages()) return;
        pinMessagesToBottom();
        followSettleFrameRef.current = requestAnimationFrame(() => {
          followSettleFrameRef.current = null;
          if (shouldFollowPinnedMessages()) pinMessagesToBottom();
        });
      });
    }
  };

  const shouldFollowPinnedMessages = () => {
    return autoFollowRef.current && isNearBottomRef.current && !autoFollowPausedRef.current;
  };

  const toggleBrowserFullscreen = async () => {
    if (typeof document === 'undefined') return;
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        // 见 OverlayPortal 注释：全屏挂到 <html> 而不是 <main>，
        // 让 OverlayPortal 把 dialog/menu/snackbar 投射到 body，
        // 避开 oh-page-fade transform 残留 containing block 带来的「点击无效」问题。
        const target = document.documentElement;
        if (!target.requestFullscreen) {
          showSnackbar(t('topbar.fullscreen.unsupported', '当前浏览器不支持全屏'), { tone: 'error' });
          return;
        }
        await target.requestFullscreen();
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      showSnackbar(`${t('topbar.fullscreen.failed', '切换全屏失败')}：${message}`, { tone: 'error' });
    }
  };

  const handleCopyMessage = useCallback(async (m: SessionMessage) => {
    const text = m.content ?? '';
    const ok = await copyTextToClipboard(text);
    showSnackbar(ok
      ? t('detail.copy.ok', '已复制消息内容')
      : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
        tone: ok ? 'success' : 'error',
      });
  }, []);
  const handleDeleteMessage = useCallback((m: SessionMessage) => {
    setPendingDeleteAction({ message: m, cascade: false });
  }, []);
  const handleDeleteMessageCascade = useCallback((m: SessionMessage) => {
    setPendingDeleteAction({ message: m, cascade: true });
  }, []);
  const confirmDeleteMessage = async () => {
    if (!sessionId || !pendingDeleteAction || deleteBusy) return;
    const requestSessionId = sessionId;
    setDeleteBusy(true);
    const { message, cascade } = pendingDeleteAction;
    try {
      if (cascade) {
        await deleteMessageCascade(requestSessionId, message.id);
      } else {
        await deleteMessage(requestSessionId, message.id);
      }
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setPendingDeleteAction(null);
      showSnackbar(cascade
        ? t('detail.deleteAfter.ok', '已删除此条及后续消息')
        : t('detail.delete.ok', '已删除消息'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
      showSnackbar(t('detail.delete.failed', '删除消息失败'), { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setDeleteBusy(false);
    }
  };

  const confirmDeleteSession = async () => {
    if (!sessionId || sessionDeleteBusy) return;
    const requestSessionId = sessionId;
    setSessionDeleteBusy(true);
    try {
      await deleteSession(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      showSnackbar(t('topbar.delete.ok', '已删除会话'), { tone: 'success' });
      location.route('/threads');
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
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
      if (ownsSessionAsyncResult(requestSessionId)) {
        setSessionDeleteBusy(false);
        setPendingSessionDelete(false);
      }
    }
  };

  const applyFullAccessPermission = async (next: boolean) => {
    if (permissionSaving) return;
    const requestSessionId = sessionId;
    setPermissionSaving(true);
    try {
      const res = await updateSessionFullAccessPermission(requestSessionId, next);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setDetail((prev) =>
        prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev,
      );
      showSnackbar(t('topbar.perm.ok', '已更新权限设置'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.perm.failed', '更新权限设置失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) {
        setPermissionSaving(false);
        setPendingFullAccess(null);
      }
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
    const requestSessionId = sessionId;
    const approvalId = pendingWriteApproval.id;
    setWriteApprovalBusy(true);
    try {
      await respondWriteApproval(requestSessionId, approvalId, approved);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setPendingWriteApproval(null);
      showSnackbar(
        approved
          ? t('detail.writeApproval.approved', '已批准写操作')
          : t('detail.writeApproval.rejected', '已拒绝写操作'),
        { tone: approved ? 'success' : undefined },
      );
      void refresh();
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('detail.writeApproval.failed', '处理写操作确认失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setWriteApprovalBusy(false);
    }
  };
  const handleEditMessage = useEventCallback((m: SessionMessage) => {
    if (m.role !== 'user') return;
    editingDraftMessageRef.current = m;
    setEditingDraftMessage(m);
    setComposerText(m.content ?? '');
    setComposerError(null);
    setSelectedSkill(null);
    setSkillPickerOpen(false);
    setComposerCollapsed(false);
    setComposerAttachments([]);
    setComposerAttachmentIds([]);
    setAttachmentPreviews([]);
    void restoreAttachmentsForEdit(m);
    window.setTimeout(() => composerTextareaRef.current?.focus(), 0);
    scheduleFollowToBottom(reduceMotion ? 'auto' : 'smooth');
  });
  const handleAuditMessage = useCallback((m: SessionMessage) => {
    setAuditMessage(m);
  }, []);
  const handleMessageActiveChange = useCallback((message: SessionMessage, active: boolean) => {
    setActiveMessageId(active ? message.id : null);
  }, []);

  useEffect(() => {
    if (typeof document === 'undefined') return;
    const syncFullscreenState = () => setFullscreenActive(Boolean(document.fullscreenElement));
    syncFullscreenState();
    document.addEventListener('fullscreenchange', syncFullscreenState);
    return () => document.removeEventListener('fullscreenchange', syncFullscreenState);
  }, []);

  useEffect(() => {
    function recalc() {
      const el = mainRef.current;
      if (!el) return;
      const dist = el.scrollHeight - (el.scrollTop + el.clientHeight);
      isNearBottomRef.current = dist <= 64;
      if (Date.now() <= programmaticScrollUntilRef.current) {
        if (autoFollowRef.current && autoFollowPausedRef.current) {
          setAutoFollowPausedValue(false);
        }
        return;
      }
      if (!autoFollow) {
        if (autoFollowPaused) setAutoFollowPausedValue(false);
        return;
      }
      if (isNearBottomRef.current) {
        if (unreadCount !== 0) clearUnreadCount();
        if (autoFollowPaused) setAutoFollowPausedValue(false);
      } else if (!autoFollowPaused && Date.now() > programmaticScrollUntilRef.current) {
        setAutoFollowPausedValue(true);
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
    const target = messagesContentRef.current;
    const scroller = mainRef.current;
    if (!target || !scroller || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(() => {
      if (!shouldFollowPinnedMessages()) return;
      scheduleFollowToBottom('auto');
    });
    observer.observe(target);
    observer.observe(scroller);
    return () => {
      observer.disconnect();
    };
  }, [autoFollow, autoFollowPaused]);

  useEffect(() => {
    messagesRef.current = messages;
  }, [messages]);

  useEffect(() => {
    windowOffsetRef.current = windowOffset;
  }, [windowOffset]);

  useEffect(() => {
    editingDraftMessageRef.current = editingDraftMessage;
  }, [editingDraftMessage]);

  useEffect(() => {
    composerAttachmentIdsRef.current = composerAttachmentIds;
  }, [composerAttachmentIds]);

  useEffect(() => {
    persistComposerCollapsed(composerCollapsed);
  }, [composerCollapsed]);

  // 折叠/展开期间稳住消息：observer 跟踪 composer 高度变化，
  // 当用户「未在底部」时把 transcript scrollTop 反向补偿，让可视区底部
  // 锚到原始内容偏移，从而上方消息不被「挤上去 / 压下来」。
  useEffect(() => {
    if (typeof window === 'undefined' || typeof ResizeObserver === 'undefined') return;
    const composerEl = composerSectionRef.current;
    const scroller = mainRef.current;
    if (!composerEl || !scroller) return;
    let lastH = composerEl.getBoundingClientRect().height;
    const observer = new ResizeObserver(() => {
      const measured = composerEl.getBoundingClientRect().height;
      const delta = measured - lastH;
      lastH = measured;
      if (delta === 0) return;
      // 无论是否贴底都反向补偿：贴底时同帧重新锥住底部，避免 闪动；
      // 未贴底时保持可视位置锡定。
      scroller.scrollTop = scroller.scrollTop + delta;
    });
    observer.observe(composerEl);
    return () => observer.disconnect();
  }, []);

  useLayoutEffect(() => {
    if (shouldFollowPinnedMessages()) scheduleFollowToBottom('auto');
  }, [
    composerCollapsed,
    composerAttachments.length,
    selectedSkill?.name,
    editingDraftMessage?.id,
    composerError,
  ]);

  useEffect(() => {
    if (activeMessageId == null) return;
    if (messages.some((item) => item.id === activeMessageId)) return;
    setActiveMessageId(null);
  }, [messages, activeMessageId]);

  useEffect(() => {
    if (!editingDraftMessage || composerSending) return;
    if (messages.some((item) => item.id === editingDraftMessage.id)) return;
    editingDraftMessageRef.current = null;
    setEditingDraftMessage(null);
    showSnackbar(t('composer.edit.targetGone', '原消息已在其他客户端被更新'), { tone: 'error' });
  }, [messages, editingDraftMessage, composerSending]);

  // messages 变化 → 自动跟随 / 累计未读
  // 用 useLayoutEffect 在浏览器 paint 前同步钉到底部，避免插入新内容后浏览器 scroll-anchor
  // 先把视口锁在旧位置、随后我们再回拉造成的「上移 → 降落」鬼畜抖动。
  useLayoutEffect(() => {
    if (messages.length === 0) {
      lastTailIdRef.current = null;
      lastTailContentLengthRef.current = 0;
      return;
    }
    const tail = messages[messages.length - 1];
    const tailContentLength = tail.content?.length ?? tail.character_count ?? 0;
    if (lastTailIdRef.current === null) {
      lastTailIdRef.current = tail.id;
      lastTailContentLengthRef.current = tailContentLength;
      if (autoFollow) scheduleFollowToBottom('auto');
      return;
    }
    const tailChanged = tail.id !== lastTailIdRef.current;
    const tailContentChanged = tailContentLength !== lastTailContentLengthRef.current;
    if (!tailChanged && !tailContentChanged) return;
    lastTailIdRef.current = tail.id;
    lastTailContentLengthRef.current = tailContentLength;
    if (shouldFollowPinnedMessages()) {
      // 流式追加（tailContentChanged）一律走 'auto' 即时钉底；只有切换会话或新建消息这种
      // 一次性大跳跃才偶尔用 smooth，避免每个 token 都触发 smooth 缓动堆叠。
      const behavior = reduceMotion || tailContentChanged ? 'auto' : 'smooth';
      scheduleFollowToBottom(behavior);
    } else {
      if (autoFollow) setAutoFollowPausedValue(true);
      setUnreadCount((n) => (tailChanged ? n + 1 : Math.max(1, n)));
    }
  }, [messages, autoFollow, autoFollowPaused, reduceMotion]);

  useEffect(() => {
    if (!pendingWriteApproval || !shouldFollowPinnedMessages()) return;
    scheduleFollowToBottom(reduceMotion ? 'auto' : 'smooth');
  }, [pendingWriteApproval?.id, autoFollow, autoFollowPaused, reduceMotion]);

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

  function ownsSessionAsyncResult(requestSessionId: string): boolean {
    return shouldApplySessionAsyncResult(sessionIdRef.current, requestSessionId, mountedRef.current);
  }

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
        clearAutoTitleRefreshTimers();
        setSessionGone(true);
        return true;
      }
    }
    return false;
  }

  function clearAutoTitleRefreshTimers(): void {
    for (const timer of autoTitleRefreshTimersRef.current) {
      window.clearTimeout(timer);
    }
    autoTitleRefreshTimersRef.current = [];
  }

  function shouldWatchAutoTitleAfterSend(text: string): boolean {
    if (!text.trim()) return false;
    const current = detailRef.current?.session;
    if (!current || current.is_title_manually_edited || current.auto_title_generated_at) {
      return false;
    }
    const visibleUserMessages = messagesRef.current.filter(
      (item) => item.role === 'user' && (item.content ?? '').trim().length > 0,
    );
    return visibleUserMessages.length === 0;
  }

  function mergeSessionSummaryFromPolling(summary: SessionSummary): void {
    setDetail((prev) => {
      const runtime = prev?.runtime ?? {
        send_phase: sendPhase,
        can_stop: false,
        last_error: lastError,
      };
      return prev
        ? { ...prev, session: mergeSessionSummary(prev.session, summary), runtime }
        : { session: summary, runtime };
    });
    if (typeof summary.message_count === 'number') {
      setTotalKnown(summary.message_count);
    }
    if (summary.auto_title_generated_at || summary.is_title_manually_edited) {
      clearAutoTitleRefreshTimers();
    }
  }

  function replaceMessageWindow(items: SessionMessage[], offset: number): void {
    messagesRef.current = items;
    windowOffsetRef.current = offset;
    setMessages(items);
    setWindowOffset(offset);
  }

  function applyServerMessageWindow(
    latest: SessionMessage[],
    nextOffset: number,
    options: MergeServerWindowOptions = {},
  ): void {
    const result = mergeServerWindowResult(
      messagesRef.current,
      latest,
      windowOffsetRef.current,
      nextOffset,
      options,
    );
    replaceMessageWindow(result.items, result.offset);
  }

  async function refreshAutoTitleSummary(): Promise<boolean> {
    if (!sessionId) return true;
    const current = detailRef.current?.session;
    if (!current || current.is_title_manually_edited || current.auto_title_generated_at) {
      return true;
    }
    const fresh = await getSession(sessionId);
    if (!ownsSessionAsyncResult(sessionId)) return true;
    setDetail((prev) => (
      prev
        ? { ...fresh, session: mergeSessionSummary(prev.session, fresh.session) }
        : fresh
    ));
    setSendPhase(fresh.runtime.send_phase);
    setLastError(fresh.runtime.last_error);
    setTotalKnown(fresh.session.message_count ?? messagesRef.current.length);
    return Boolean(
      fresh.session.is_title_manually_edited || fresh.session.auto_title_generated_at,
    );
  }

  function scheduleAutoTitleFollowUp(): void {
    clearAutoTitleRefreshTimers();
    const delays = [1200, 3200, 7000, 14000, 24000];
    autoTitleRefreshTimersRef.current = delays.map((delay) => window.setTimeout(() => {
      void refreshAutoTitleSummary()
        .then((done) => {
          if (done) clearAutoTitleRefreshTimers();
        })
        .catch((error: unknown) => {
          if (handleAuthError(error) || handleSessionGoneError(error)) {
            clearAutoTitleRefreshTimers();
          }
        });
    }, delay));
  }

  function loadDetail(): void {
    if (!sessionId) return;
    const requestSessionId = sessionId;
    detailAbortRef.current?.abort();
    const ctrl = new AbortController();
    detailAbortRef.current = ctrl;
    setLoadingDetail(true);
    setRefreshing(false);
    setLoadingOlder(false);
    setError(null);
    replaceMessageWindow([], 0);
    setTotalKnown(0);
    setActiveMessageId(null);
    setComposerModelKey('');
    setComposerMode('normal');
    editingDraftMessageRef.current = null;
    setEditingDraftMessage(null);
    lastTailIdRef.current = null;
    lastTailContentLengthRef.current = 0;
    Promise.all([
      getSession(requestSessionId, { signal: ctrl.signal }),
      listMessages(requestSessionId, { limit: PAGE_SIZE, tail: true, signal: ctrl.signal }),
    ])
      .then(([d, m]) => {
        if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
        setDetail(m.session ? { ...d, session: mergeSessionSummary(d.session, m.session) } : d);
        replaceMessageWindow([...m.items], m.offset);
        setTotalKnown(m.total);
        setSendPhase(m.send_phase || d.runtime.send_phase || 'idle');
        setLastError(m.last_error ?? d.runtime.last_error ?? null);
        setPendingWriteApproval(m.pending_write_approval ?? null);
        setLoadingDetail(false);
      })
      .catch((e: unknown) => {
        if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
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
    if (!sessionId || refreshing || messagesAbortRef.current) return;
    const requestSessionId = sessionId;
    const ctrl = new AbortController();
    messagesAbortRef.current = ctrl;
    setRefreshing(true);
    try {
      const m = await listMessages(requestSessionId, { limit: PAGE_SIZE, tail: true, signal: ctrl.signal });
      if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
      applyServerMessageWindow(
        m.items,
        m.offset,
        { preserveLocalStreamingTail: isRunningPhase(m.send_phase) || isRunningPhase(sendPhase) },
      );
      setTotalKnown(m.total);
      setSendPhase(m.send_phase);
      setLastError(m.last_error);
      setPendingWriteApproval(m.pending_write_approval ?? null);
      if (m.session) mergeSessionSummaryFromPolling(m.session);
    } catch (e: unknown) {
      if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      if (messagesAbortRef.current === ctrl) {
        messagesAbortRef.current = null;
        if (ownsSessionAsyncResult(requestSessionId)) setRefreshing(false);
      }
    }
  }

  async function loadOlder(): Promise<void> {
    if (loadingOlder || olderMessagesAbortRef.current) return;
    if (windowOffset <= 0) return;
    const requestSessionId = sessionId;
    const ctrl = new AbortController();
    olderMessagesAbortRef.current = ctrl;
    setLoadingOlder(true);
    const scroller = mainRef.current;
    const beforeHeight = scroller?.scrollHeight ?? 0;
    const beforeY = scroller?.scrollTop ?? 0;
    try {
      const offset = Math.max(0, windowOffset - PAGE_SIZE);
      const m = await listMessages(requestSessionId, {
        limit: Math.max(1, windowOffset - offset),
        offset,
        signal: ctrl.signal,
      });
      if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
      const currentMessages = messagesRef.current;
      const existing = new Set(currentMessages.map((item) => item.id));
      const incoming = m.items.filter((item) => !existing.has(item.id));
      replaceMessageWindow([...incoming, ...currentMessages], m.offset);
      setTotalKnown(m.total);
      setSendPhase(m.send_phase);
      setLastError(m.last_error);
      setPendingWriteApproval(m.pending_write_approval ?? null);
      if (m.session) mergeSessionSummaryFromPolling(m.session);
      requestAnimationFrame(() => {
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        const el = mainRef.current;
        if (!el) return;
        const delta = el.scrollHeight - beforeHeight;
        el.scrollTo({ top: beforeY + delta, behavior: 'auto' });
      });
    } catch (e: unknown) {
      if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      if (olderMessagesAbortRef.current === ctrl) {
        olderMessagesAbortRef.current = null;
        if (ownsSessionAsyncResult(requestSessionId)) setLoadingOlder(false);
      }
    }
  }

  useEffect(() => {
    if (auth.loading) return;
    if (!sessionId) return;
    loadDetail();
    return () => {
      detailAbortRef.current?.abort();
      detailAbortRef.current = null;
      messagesAbortRef.current?.abort();
      messagesAbortRef.current = null;
      olderMessagesAbortRef.current?.abort();
      olderMessagesAbortRef.current = null;
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
      sseCloseRef.current?.();
      sseCloseRef.current = null;
      clearAutoTitleRefreshTimers();
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
    const eventSessionId = sessionId;
    sseFailRef.current = 0;
    setSseLive(false);
    const close = subscribeSessionEvents(eventSessionId, {
      onOpen: () => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
        sseFailRef.current = 0;
        setSseLive(true);
      },
      onSnapshot: (snap) => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
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
        applyServerMessageWindow(
          snap.messages,
          snapOffset,
          { preserveLocalStreamingTail: isRunningPhase(snap.send_phase) },
        );
        setTotalKnown(snap.session.message_count ?? snap.messages.length);
        setDetail((prev) => {
          const runtime = {
            send_phase: snap.send_phase,
            can_stop: snap.can_stop,
            last_error: snap.last_error,
          };
          return prev
            ? { ...prev, session: mergeSessionSummary(prev.session, snap.session), runtime }
            : { session: snap.session, runtime };
        });
        if (snap.session.auto_title_generated_at || snap.session.is_title_manually_edited) {
          clearAutoTitleRefreshTimers();
        }
        setSendPhase(snap.send_phase);
        setLastError(snap.last_error);
        setPendingWriteApproval(snap.pending_write_approval ?? null);
      },
      onDeleted: () => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
        if (sseCloseRef.current === close) {
          sseCloseRef.current?.();
          sseCloseRef.current = null;
        }
        if (pollTimerRef.current != null) {
          window.clearTimeout(pollTimerRef.current);
          pollTimerRef.current = null;
        }
        setSseLive(false);
        setSessionGone(true);
      },
      onError: () => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
        sseFailRef.current += 1;
        if (sseFailRef.current >= SSE_FAIL_THRESHOLD) {
          setSseLive(false);
        }
      },
    });
    sseCloseRef.current = close;
    return () => {
      close();
      if (sseCloseRef.current === close) sseCloseRef.current = null;
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
  // 与 App 端 _ComposerInstructionsStrip 1:1 对齐：meta.instructions 已在
  // service 端按 allowedInstructionIds + enabled 过滤，前端直接消费。
  const availableInstructions = useMemo<ApiMetaInstruction[]>(
    () => meta?.instructions ?? [],
    [meta],
  );
  const shortcutBindings = useMemo(
    () => meta?.shortcut_bindings ?? {},
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
  const composerModeOptions = useMemo(
    () => allComposerModes(allowedModes),
    [allowedModes],
  );
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

  function copyQueuedAttachments(): SendMessageAttachment[] {
    return composerAttachments.map((att) => ({ ...att }));
  }

  function queuedSelectedSkillPayload(): QueuedComposerMessage['selectedSkill'] {
    return selectedSkill
      ? {
          name: selectedSkill.name,
          relative_directory_path: selectedSkill.relative_directory_path,
        }
      : null;
  }

  function clearComposerAfterQueue(): void {
    setComposerText('');
    setComposerAttachments([]);
    setComposerAttachmentIds([]);
    setAttachmentPreviews([]);
    setSelectedSkill(null);
    setSkillPickerOpen(false);
    if (!composerCollapsed) {
      requestAnimationFrame(() => composerTextareaRef.current?.focus());
    }
  }

  function validateComposerPayload(
    text: string,
    attachments: SendMessageAttachment[],
    modelKey: string,
    mode: string,
    model: typeof selectedModel,
  ): string | null {
    if (!text && attachments.length === 0) return t('composer.error.empty', '请输入内容或添加附件');
    if (text && !textAllowed) return t('composer.error.textNotAllowed', '当前 service 禁用了文本消息');
    if (attachments.length > 0 && (!allowedMessageTypes.includes('attachment') || model?.supports_attachments === false)) {
      return t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件');
    }
    if (!modelKey) return t('composer.error.modelMissing', '请选择模型');
    if (!modelSupportsMode(model, mode)) {
      return t('composer.error.modeUnsupported', '当前模型不支持所选模式，请切换模型或模式后再发送');
    }
    return null;
  }

  function enqueueCurrentComposerMessage(): boolean {
    if (editingDraftMessage) {
      setComposerError(t('composer.queue.editingBusy', '当前正在回复，不能排队编辑历史消息'));
      return false;
    }
    const text = composerText.trim();
    const attachments = copyQueuedAttachments();
    const validation = validateComposerPayload(text, attachments, composerModelKey, composerMode, selectedModel);
    if (validation) {
      setComposerError(validation);
      return false;
    }
    const queued: QueuedComposerMessage = {
      id: nextQueuedMessageId(),
      content: text,
      attachments,
      modelKey: composerModelKey,
      modelLabel: selectedModel?.label ?? composerModelKey,
      mode: composerMode,
      selectedSkill: queuedSelectedSkillPayload(),
      skillLabel: selectedSkill?.name ?? null,
      skippedInstructionIds: Array.from(skippedInstructionIds),
      createdAt: Date.now(),
    };
    setQueuedComposerMessages((prev) => [...prev, queued]);
    setQueuedListMotionGeneration((value) => value + 1);
    setComposerError(null);
    clearComposerAfterQueue();
    showSnackbar(t('composer.queue.added', '消息已加入等待队列，将在当前回答完成后自动发送'), { tone: 'success' });
    return true;
  }

  function removeQueuedMessage(id: string): void {
    if (queueDispatchingId === id || queuedMessageIsExiting(id)) return;
    runAfterQueuedMessageExit(id, () => {
      setQueuedComposerMessages((prev) => prev.filter((item) => item.id !== id));
      setQueuedListMotionGeneration((value) => value + 1);
      if (editingQueuedMessageId === id) {
        setEditingQueuedMessageId(null);
        setQueuedEditText('');
      }
    });
  }

  function moveQueuedMessage(from: number, to: number): void {
    setQueuedComposerMessages((prev) => {
      if (from < 0 || from >= prev.length || to < 0 || to >= prev.length || from === to) return prev;
      const next = [...prev];
      const [item] = next.splice(from, 1);
      if (!item) return prev;
      next.splice(to, 0, item);
      return next;
    });
    setQueuedListMotionGeneration((value) => value + 1);
  }

  function startEditQueuedMessage(item: QueuedComposerMessage): void {
    if (queueDispatchingId === item.id) return;
    setEditingQueuedMessageId(item.id);
    setQueuedEditText(item.content);
  }

  function saveQueuedMessageEdit(id: string): void {
    const trimmed = queuedEditText.trim();
    if (!trimmed) return;
    setQueuedComposerMessages((prev) => prev.map((item) => (
      item.id === id ? { ...item, content: trimmed } : item
    )));
    setEditingQueuedMessageId(null);
    setQueuedEditText('');
    setQueuedListMotionGeneration((value) => value + 1);
  }

  async function dispatchNextQueuedMessage(): Promise<void> {
    if (queueDispatchingRef.current || composerSending || isRunningPhase(sendPhase)) return;
    const next = queuedComposerMessagesRef.current[0];
    if (!next) return;
    const queuedModel = allowedModels.find((model) => model.key === next.modelKey);
    const validation = validateComposerPayload(next.content, next.attachments, next.modelKey, next.mode, queuedModel);
    if (validation) {
      setComposerError(validation);
      return;
    }
    queueDispatchingRef.current = true;
    setQueueDispatchingId(next.id);
    setComposerError(null);
    lastLocalSendAtRef.current = Date.now();
    const dispatchSessionId = sessionId;
    try {
      const res = await sendMessage(dispatchSessionId, {
        content: next.content,
        modelKey: next.modelKey,
        mode: next.mode,
        attachments: next.attachments,
        selectedSkill: next.selectedSkill,
        skippedInstructionIds: next.skippedInstructionIds,
      });
      if (!ownsSessionAsyncResult(dispatchSessionId)) return;
      setQueuedComposerMessages((prev) => (
        prev[0]?.id === next.id ? prev.slice(1) : prev.filter((item) => item.id !== next.id)
      ));
      setQueuedListMotionGeneration((value) => value + 1);
      setSendPhase(res.send_phase || 'sendingMessage');
      if (!sseLive) void refresh();
      if (shouldWatchAutoTitleAfterSend(next.content)) scheduleAutoTitleFollowUp();
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(dispatchSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      if (e instanceof ApiError) {
        const body = e.body as { error?: string; message?: string } | null;
        setComposerError(
          body?.message ||
            t('composer.queue.sendFailed', '等待队列发送失败：HTTP ') +
              String(e.status) +
              (body?.error ? ` (${body.error})` : ''),
        );
      } else {
        setComposerError(
          t('composer.queue.sendFailed', '等待队列发送失败：HTTP ') +
            (e instanceof Error ? e.message : String(e)),
        );
      }
    } finally {
      if (ownsSessionAsyncResult(dispatchSessionId)) {
        queueDispatchingRef.current = false;
        setQueueDispatchingId(null);
      }
    }
  }

  useEffect(() => {
    if (!sessionId || queuedComposerMessages.length === 0) return;
    if (composerSending || queueDispatchingRef.current || isRunningPhase(sendPhase)) return;
    const timer = window.setTimeout(() => {
      void dispatchNextQueuedMessage();
    }, QUEUE_SEND_SETTLE_MS);
    return () => window.clearTimeout(timer);
  }, [sessionId, queuedComposerMessages, sendPhase, composerSending, allowedModels, allowedMessageTypes, textAllowed, sseLive]);

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
    const pollSessionId = sessionId;
    let ctrl: AbortController | null = null;
    async function tick(): Promise<void> {
      ctrl?.abort();
      ctrl = new AbortController();
      try {
        const m = await listMessages(pollSessionId, {
          limit: PAGE_SIZE,
          tail: true,
          signal: ctrl.signal,
        });
        if (cancelled || ctrl.signal.aborted || !ownsSessionAsyncResult(pollSessionId)) return;
        const offset = m.offset ?? Math.max(0, m.total - m.items.length);
        // 只合并最新窗口；不动「加载更早」拉过来的历史前缀。
        applyServerMessageWindow(
          m.items,
          offset,
          { preserveLocalStreamingTail: isRunningPhase(m.send_phase) || isRunningPhase(sendPhase) },
        );
        setTotalKnown(m.total);
        setSendPhase(m.send_phase);
        setLastError(m.last_error);
        setPendingWriteApproval(m.pending_write_approval ?? null);
        if (m.session) mergeSessionSummaryFromPolling(m.session);
      } catch (e: unknown) {
        if (cancelled || ctrl?.signal.aborted || !ownsSessionAsyncResult(pollSessionId)) return;
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
      ctrl?.abort();
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

  const skillPickerResults = useMemo(() => {
    const query = skillPickerQuery.trim().toLowerCase();
    const base = query.length === 0
      ? skills
      : skills.filter((skill) => `${skill.name} ${skill.description}`.toLowerCase().includes(query));
    return base.slice(0, 18);
  }, [skills, skillPickerQuery]);

  useEffect(() => {
    setSkillPickerSelectedIndex((index) => {
      if (skillPickerResults.length === 0) return 0;
      return Math.min(index, skillPickerResults.length - 1);
    });
  }, [skillPickerResults.length]);

  // —— 浮窗坐标：position: fixed 直接锚到 textarea 矩形之上，避免被 oh-composer-body
  // 的 overflow: clip 截断；同时无视祖先 transform 而成为新 containing block 的尴尬。
  const recomputeSkillPickerAnchor = useCallback(() => {
    const node = composerTextareaRef.current;
    if (!node || typeof window === 'undefined') return;
    const rect = node.getBoundingClientRect();
    const viewportW = window.innerWidth;
    const viewportH = window.innerHeight;
    const width = Math.min(480, Math.max(220, rect.width));
    const left = Math.max(12, Math.min(rect.left, viewportW - width - 12));
    const bottomGap = Math.max(8, viewportH - rect.top + 10);
    const maxHeight = Math.max(160, Math.min(360, rect.top - 16));
    setSkillPickerAnchor({ bottomGap, left, width, maxHeight });
  }, []);

  // 浮窗 open ↔ visible 同步：尊重全局 dialog 动画设置。
  useEffect(() => {
    if (skillPickerOpen) {
      if (skillPickerCloseTimerRef.current != null) {
        window.clearTimeout(skillPickerCloseTimerRef.current);
        skillPickerCloseTimerRef.current = null;
      }
      setSkillPickerClosing(false);
      setSkillPickerVisible(true);
      recomputeSkillPickerAnchor();
      return;
    }
    if (!skillPickerVisible) return;
    setSkillPickerClosing(true);
    const exitMs = getDialogExitDurationMs();
    if (exitMs <= 0) {
      setSkillPickerVisible(false);
      setSkillPickerClosing(false);
      return;
    }
    skillPickerCloseTimerRef.current = window.setTimeout(() => {
      skillPickerCloseTimerRef.current = null;
      setSkillPickerVisible(false);
      setSkillPickerClosing(false);
    }, exitMs);
  }, [skillPickerOpen, skillPickerVisible, recomputeSkillPickerAnchor]);

  // 卸载时清理动效定时器，避免 leak。
  useEffect(() => () => {
    if (skillPickerCloseTimerRef.current != null) {
      window.clearTimeout(skillPickerCloseTimerRef.current);
      skillPickerCloseTimerRef.current = null;
    }
  }, []);

  // 滚动 / resize 时让浮窗锚点跟随 textarea。
  useEffect(() => {
    if (!skillPickerVisible) return;
    const handler = () => recomputeSkillPickerAnchor();
    window.addEventListener('scroll', handler, true);
    window.addEventListener('resize', handler);
    return () => {
      window.removeEventListener('scroll', handler, true);
      window.removeEventListener('resize', handler);
    };
  }, [skillPickerVisible, recomputeSkillPickerAnchor]);

  async function ensureSkillsLoadedForPicker(): Promise<void> {
    if (skillsLoadedRef.current || skillPickerLoading) return;
    setSkillPickerLoading(true);
    try {
      const res = await listSkills();
      setSkills(res.items);
    } catch (error: unknown) {
      setComposerError(
        `${t('composer.skill.loadFailed', '加载技能列表失败')}：${error instanceof Error ? error.message : String(error)}`,
      );
    } finally {
      skillsLoadedRef.current = true;
      setSkillPickerLoading(false);
    }
  }

  function computeSlashTrigger(text: string, cursor: number): { tokenEnd: number; query: string; token: string } | null {
    if (!text.startsWith('/')) return null;
    let tokenEnd = text.length;
    for (let i = 0; i < text.length; i += 1) {
      const ch = text.charCodeAt(i);
      if (ch === 0x20 || ch === 0x09 || ch === 0x0A || ch === 0x0D) {
        tokenEnd = i;
        break;
      }
    }
    if (cursor > tokenEnd) return null;
    const token = text.slice(0, tokenEnd);
    return { tokenEnd, query: text.slice(1, tokenEnd), token };
  }

  function updateSkillPickerForText(text: string, cursor: number): void {
    if (selectedSkill) {
      setSkillPickerOpen(false);
      return;
    }
    const trigger = computeSlashTrigger(text, cursor);
    if (!trigger) {
      setSkillPickerOpen(false);
      setSkillPickerQuery('');
      setSlashDismissedToken(null);
      return;
    }
    if (slashDismissedToken === trigger.token) return;
    setSkillPickerQuery(trigger.query);
    setSkillPickerOpen(true);
    setSkillPickerSelectedIndex(0);
    void ensureSkillsLoadedForPicker();
  }

  function selectSkillForComposer(skill: SkillSummary): void {
    const textarea = composerTextareaRef.current;
    const text = textarea?.value ?? composerText;
    const cursor = textarea?.selectionStart ?? 0;
    const trigger = computeSlashTrigger(text, cursor);
    const remainderStart = trigger
      ? trigger.tokenEnd < text.length && /[ \t]/.test(text.charAt(trigger.tokenEnd))
        ? trigger.tokenEnd + 1
        : trigger.tokenEnd
      : 0;
    const nextText = text.slice(remainderStart);
    setComposerText(nextText);
    setSelectedSkill(skill);
    setSkillPickerOpen(false);
    setSlashDismissedToken(null);
    requestAnimationFrame(() => {
      const node = composerTextareaRef.current;
      node?.focus();
      node?.setSelectionRange(0, 0);
    });
  }

  function dismissSkillPicker(remember = false): void {
    const textarea = composerTextareaRef.current;
    const text = textarea?.value ?? composerText;
    const cursor = textarea?.selectionStart ?? 0;
    const trigger = computeSlashTrigger(text, cursor);
    if (remember && trigger) setSlashDismissedToken(trigger.token);
    setSkillPickerOpen(false);
  }

  function handleComposerKeyDown(e: KeyboardEvent): void {
    if (skillPickerOpen) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSkillPickerSelectedIndex((index) => (
          skillPickerResults.length === 0 ? 0 : (index + 1) % skillPickerResults.length
        ));
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSkillPickerSelectedIndex((index) => {
          if (skillPickerResults.length === 0) return 0;
          return (index - 1 + skillPickerResults.length) % skillPickerResults.length;
        });
        return;
      }
      if (e.key === 'Enter' && !e.shiftKey) {
        const skill = skillPickerResults[skillPickerSelectedIndex];
        if (skill) {
          e.preventDefault();
          selectSkillForComposer(skill);
          return;
        }
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        dismissSkillPicker(true);
        return;
      }
    }
    handleComposerShortcut(e);
  }

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

  async function restoreAttachmentsForEdit(message: SessionMessage): Promise<void> {
    const requestSessionId = sessionId;
    const assets = collectEditableAttachmentAssets(message);
    if (assets.length === 0) return;
    const restoredAttachments: SendMessageAttachment[] = [];
    const restoredPreviews: { mime: string; dataUrl: string; size: number }[] = [];
    let failed = 0;
    for (const asset of assets) {
      try {
        const res = await fetch(buildSessionAssetUrl(requestSessionId, asset.path), {
          credentials: 'same-origin',
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const blob = await res.blob();
        if (blob.size > ATTACHMENT_MAX_BYTES) {
          throw new Error(
            t('composer.attachment.tooLarge', '附件超过 ') +
              (ATTACHMENT_MAX_BYTES / (1024 * 1024)).toFixed(0) +
              ' MiB',
          );
        }
        const file = new File([blob], asset.name, {
          type: asset.mime || blob.type || 'application/octet-stream',
        });
        const item = await readFileAsAttachment(file);
        restoredAttachments.push(item.att);
        restoredPreviews.push({ mime: item.mime, dataUrl: item.dataUrl, size: blob.size });
      } catch {
        failed += 1;
      }
    }
    if (!ownsSessionAsyncResult(requestSessionId) || editingDraftMessageRef.current?.id !== message.id) return;
    setComposerAttachments(restoredAttachments);
    setComposerAttachmentIds(restoredAttachments.map(() => nextAttachmentUiId()));
    setAttachmentPreviews(restoredPreviews);
    if (failed > 0) {
      showSnackbar(t('composer.edit.attachmentRestorePartial', '部分原附件无法恢复到编辑草稿'), {
        tone: 'error',
      });
    }
  }

  function openImageEditor(input: ImageEditorInput): Promise<ImageEditorResult | null> {
    imageEditorResolverRef.current?.(null);
    setImageEditorInput(input);
    return new Promise((resolve) => {
      imageEditorResolverRef.current = resolve;
    });
  }

  function settleImageEditor(result: ImageEditorResult | null): void {
    const resolve = imageEditorResolverRef.current;
    imageEditorResolverRef.current = null;
    setImageEditorInput(null);
    resolve?.(result);
  }

  // 从 File[] 追加附件。共用与 file input / drag-drop / paste
  async function appendFiles(files: File[]): Promise<void> {
    if (files.length === 0) return;
    const requestSessionId = sessionId;
    setComposerError(null);
    const nextAtt: SendMessageAttachment[] = [...composerAttachments];
    const nextPv: { mime: string; dataUrl: string; size: number }[] = [
      ...attachmentPreviews,
    ];
    const nextIds = [...composerAttachmentIds];
    for (const file of files) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (file.size > ATTACHMENT_MAX_BYTES) {
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        setComposerError(
          t('composer.attachment.tooLarge', '附件超过 ') +
            (ATTACHMENT_MAX_BYTES / (1024 * 1024)).toFixed(0) +
            ' MiB',
        );
        continue;
      }
      try {
        const r = await readFileAsAttachment(file);
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        if (r.mime.startsWith('image/')) {
          const edited = await openImageEditor({
            name: file.name,
            mime: r.mime,
            dataUrl: r.dataUrl,
            size: file.size,
          });
          if (!ownsSessionAsyncResult(requestSessionId)) return;
          if (!edited) continue;
          if (edited.size > ATTACHMENT_MAX_BYTES) {
            setComposerError(
              t('composer.attachment.tooLarge', '附件超过 ') +
                (ATTACHMENT_MAX_BYTES / (1024 * 1024)).toFixed(0) +
                ' MiB',
            );
            continue;
          }
          nextAtt.push({ name: edited.name, data_base64: edited.dataBase64 });
          nextPv.push({ mime: edited.mime, dataUrl: edited.dataUrl, size: edited.size });
          nextIds.push(nextAttachmentUiId());
        } else {
          nextAtt.push(r.att);
          nextPv.push({ mime: r.mime, dataUrl: r.dataUrl, size: file.size });
          nextIds.push(nextAttachmentUiId());
        }
      } catch (e: unknown) {
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        setComposerError(
          t('composer.attachment.readFailed', '附件读取失败：') +
            (e instanceof Error ? e.message : String(e)),
        );
      }
    }
    if (!ownsSessionAsyncResult(requestSessionId)) return;
    setComposerAttachments(nextAtt);
    setComposerAttachmentIds(nextIds);
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
    setComposerAttachmentIds((prev) => prev.filter((_, i) => i !== idx));
    setAttachmentPreviews((prev) => prev.filter((_, i) => i !== idx));
  }

  function removeAttachmentById(id: string): void {
    const idx = composerAttachmentIdsRef.current.indexOf(id);
    if (idx < 0) return;
    removeAttachmentAt(idx);
  }

  function requestRemoveAttachmentAt(idx: number): void {
    const key = composerAttachmentIds[idx];
    if (!key) {
      removeAttachmentAt(idx);
      return;
    }
    runAfterComposerChipExit(key, () => removeAttachmentById(key));
  }

  async function editAttachmentAt(idx: number): Promise<void> {
    const requestSessionId = sessionId;
    const preview = attachmentPreviews[idx];
    const attachment = composerAttachments[idx];
    if (!preview || !attachment || !preview.mime.startsWith('image/')) return;
    const edited = await openImageEditor({
      name: attachment.name,
      mime: preview.mime,
      dataUrl: preview.dataUrl,
      size: preview.size,
    });
    if (!edited) return;
    if (!ownsSessionAsyncResult(requestSessionId)) return;
    if (edited.size > ATTACHMENT_MAX_BYTES) {
      setComposerError(
        t('composer.attachment.tooLarge', '附件超过 ') +
          (ATTACHMENT_MAX_BYTES / (1024 * 1024)).toFixed(0) +
          ' MiB',
      );
      return;
    }
    setComposerAttachments((prev) => prev.map((item, i) => (
      i === idx ? { name: edited.name, data_base64: edited.dataBase64 } : item
    )));
    setAttachmentPreviews((prev) => prev.map((item, i) => (
      i === idx ? { mime: edited.mime, dataUrl: edited.dataUrl, size: edited.size } : item
    )));
  }

  async function handleSend(): Promise<void> {
    if (composerSending) return;
    if (isRunningPhase(sendPhase)) {
      enqueueCurrentComposerMessage();
      return;
    }
    const text = composerText.trim();
    const validation = validateComposerPayload(text, composerAttachments, composerModelKey, composerMode, selectedModel);
    if (validation) {
      setComposerError(validation);
      return;
    }
    const shouldTrackAutoTitle = shouldWatchAutoTitleAfterSend(text);
    setComposerSending(true);
    setComposerError(null);
    // 标记「这是本地刚刚发起的 send」, 抑制后续 sendPhase running 触发远端冲突 banner
    lastLocalSendAtRef.current = Date.now();
    const requestSessionId = sessionId;
    const editTarget = editingDraftMessage;
    let cascadeDeleted = false;
    try {
      if (editTarget) {
        await deleteMessageCascade(requestSessionId, editTarget.id);
        cascadeDeleted = true;
        if (ownsSessionAsyncResult(requestSessionId)) {
          const currentMessages = messagesRef.current;
          const idx = currentMessages.findIndex((item) => item.id === editTarget.id);
          if (idx >= 0) {
            replaceMessageWindow(currentMessages.slice(0, idx), windowOffsetRef.current);
          }
          setTotalKnown((prev) => {
            return idx >= 0 ? Math.min(prev, windowOffsetRef.current + idx) : prev;
          });
        }
      }
      const res = await sendMessage(requestSessionId, {
        content: text,
        modelKey: composerModelKey,
        mode: composerMode,
        attachments: composerAttachments,
        selectedSkill: selectedSkill
          ? {
              name: selectedSkill.name,
              relative_directory_path: selectedSkill.relative_directory_path,
            }
          : null,
        skippedInstructionIds: Array.from(skippedInstructionIds),
      });
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setComposerText('');
      setComposerAttachments([]);
      setComposerAttachmentIds([]);
      setAttachmentPreviews([]);
      setSelectedSkill(null);
      editingDraftMessageRef.current = null;
      setEditingDraftMessage(null);
      setSkillPickerOpen(false);
      setSendPhase(res.send_phase || 'sendingMessage');
      // SSE 通道在 service 端立即推送 user 消息落库；若 SSE 不可用，refresh()
      // 兜底拉一次让 user 消息出现在尾部。
      if (!sseLive) void refresh();
      if (shouldTrackAutoTitle) scheduleAutoTitleFollowUp();
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (cascadeDeleted) {
        editingDraftMessageRef.current = null;
        setEditingDraftMessage(null);
      }
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
      if (ownsSessionAsyncResult(requestSessionId)) {
        setComposerSending(false);
      }
    }
  }

  function handleComposerShortcut(event: KeyboardEvent): boolean {
    if (event.isComposing) return false;
    if (eventMatchesShortcut(event, shortcutBindings.send_message, ['ctrl', 'enter'])) {
      event.preventDefault();
      event.stopPropagation();
      void handleSend();
      return true;
    }
    if (eventMatchesShortcut(event, shortcutBindings.toggle_composer, ['ctrl', 'p'])) {
      event.preventDefault();
      event.stopPropagation();
      toggleComposerCollapsed();
      return true;
    }
    return false;
  }

  function toggleComposerCollapsed(): void {
    setComposerCollapsed((value) => !value);
    if (autoFollow) scheduleFollowToBottom('auto');
  }

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || isEditableShortcutTarget(event.target)) return;
      handleComposerShortcut(event);
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });

  async function handleStop(): Promise<void> {
    if (stopping) return;
    setStopping(true);
    const requestSessionId = sessionId;
    try {
      const res = await stopMessage(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setSendPhase(res.send_phase || 'idle');
      // 拉一次让 finalize 后的内容立刻可见
      void refresh();
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setLastError(e instanceof Error ? e.message : String(e));
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) {
        setStopping(false);
      }
    }
  }

  const session = detail?.session;
  const currentSessionMode: 'chat' | 'plan' = session?.mode === 'plan' ? 'plan' : 'chat';
  const nextSessionMode: 'chat' | 'plan' = currentSessionMode === 'plan' ? 'chat' : 'plan';
  const canToggleSessionMode = sessionModeOptions.includes(nextSessionMode);
  async function applySessionMode(next: 'chat' | 'plan'): Promise<void> {
    if (!sessionId) return;
    const requestSessionId = sessionId;
    try {
      const res = await updateSessionMode(requestSessionId, next);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setDetail((prev) =>
        prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev,
      );
      showSnackbar(t('topbar.mode.ok', '已更新会话模式'), { tone: 'success' });
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.mode.failed', '更新会话模式失败')}：${message}`, { tone: 'error' });
    }
  }

  async function openSessionMetadataDialog(): Promise<void> {
    if (!sessionId) return;
    const requestSessionId = sessionId;
    try {
      const fresh = await getSession(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setDetail((prev) =>
        prev
          ? { ...fresh, session: mergeSessionSummary(prev.session, fresh.session) }
          : fresh,
      );
      setSessionMetadataOpen(true);
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('metadata.loadFailed', '加载会话元数据失败')}：${message}`, { tone: 'error' });
    }
  }
  const remainingOlder = windowOffset;
  const sessionCapsules = useMemo<SessionToolbarCapsule[]>(() => {
    if (!session) return [];
    const templateLabel = session.template_name || session.template_id;
    const templateVersion = session.template_internal_version != null
      ? ` · v${session.template_internal_version}`
      : '';
    const lastPromptMetadata = asRecord(session.last_prompt_metadata);
    const runtimeNotices = asStringList(lastPromptMetadata['runtime_tool_catalog_notices']);
    const lazyLoadingCapsule = mcpLazyLoadingCapsule(runtimeNotices);
    const contextBudgetLabel = contextBudgetToolbarLabel(lastPromptMetadata);
    const tokens = session.total_tokens != null
      ? `${session.total_tokens.toLocaleString()} tokens`
      : t('topbar.tokens.empty', 'Token 暂无');
    const capsules: SessionToolbarCapsule[] = [];
    capsules.push(
      {
        key: 'audit',
        icon: 'audit',
        label: t('topbar.audit', '会话审计'),
        tone: 'primary',
        onClick: () => setSessionAuditOpen(true),
      },
      {
        key: 'tokens',
        icon: 'tokens',
        label: tokens,
        title: `${t('topbar.tokens', 'Token 统计')} · prompt ${session.total_prompt_tokens ?? 0} / completion ${session.total_completion_tokens ?? 0}`,
        onClick: () => setTokenStatsOpen(true),
      },
    );
    if (lazyLoadingCapsule) capsules.push(lazyLoadingCapsule);
    if (runtimeNotices.length > 0) {
      capsules.push({
        key: 'runtime-notices',
        icon: 'runtime',
        label: t('topbar.runtimeNotices', '{count} 项运行时 Notice').replace('{count}', String(runtimeNotices.length)),
        title: runtimeNotices.join('\n'),
      });
    }
    capsules.push(
      {
        key: 'template',
        icon: 'template',
        label: `${templateLabel}${templateVersion}`,
        title: `${t('sessions.template.label', '模板：')}${templateLabel}${templateVersion}`,
      },
    );
    if (session.template_id === 'hermes_talker') {
      capsules.push({
        key: 'hermes-warning',
        icon: 'runtime',
        label: t('topbar.hermesSelfLearningNotice', 'Hermes 自学习状态'),
        title: t('topbar.hermesSelfLearningNotice.title', '可在 App 定时任务面板检查 Hermes Talker 自学习开关。'),
      });
    }
    capsules.push(
      {
        key: 'metadata',
        icon: 'metadata',
        label: t('topbar.metadata', '会话元数据'),
        title: `${totalKnown} ${t('sessions.messageUnit', '条消息')} · ${session.tool_message_count ?? 0} tool`,
        onClick: () => void openSessionMetadataDialog(),
      },
    );
    if (contextBudgetLabel) {
      capsules.push({
        key: 'context-budget',
        icon: 'runtime',
        label: contextBudgetLabel,
        onClick: () => setContextStatsOpen(true),
      });
    }
    if (session.template_id === 'programming_expert') {
      capsules.push({
        key: 'files',
        icon: 'files',
        label: t('topbar.files', '项目文件'),
        title: t('topbar.files.title', '打开项目文件'),
        onClick: () => location.route('/files'),
      });
    }
    return capsules;
  }, [session, totalKnown, sessionId]);
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
    return messagesAreChronological(messages)
      ? messages
      : [...messages].sort(compareMessageCreatedAt);
  }, [messages]);

  const resumeToLatest = () => {
    setAutoFollowEnabled(true);
    setAutoFollowPausedValue(false);
    clearUnreadCount();
    isNearBottomRef.current = true;
    scheduleFollowToBottom(reduceMotion ? 'auto' : 'smooth');
  };

  const responseRunning = isRunningPhase(sendPhase);
  const latestStreamingTextMessageId = useMemo(() => {
    for (let index = sortedMessages.length - 1; index >= 0; index -= 1) {
      const message = sortedMessages[index];
      if (!message || !isAssistantTextLikeMessage(message)) continue;
      if (messageMetadataStreaming(message) || responseRunning) return message.id;
      break;
    }
    return null;
  }, [sortedMessages, responseRunning]);

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
        `${totalKnown} ${t('sessions.messageUnit', '条消息')}`,
        session.total_tokens != null ? `${session.total_tokens.toLocaleString()} tokens` : '',
        session.tool_message_count ? `${session.tool_message_count} tool` : '',
        session.compression_point_count ? `${session.compression_point_count} compress` : '',
      ].filter(Boolean).join(' · ')
    : t('detail.loading', '加载会话中…');
  const composerSendDisabled = composerSending || allowedModels.length === 0 || stopping;

  return (
    <main ref={pageRootRef} class="oh-session-detail-page h-screen overflow-hidden px-3 sm:px-6 py-4 sm:py-6 flex flex-col" style={{ background: 'var(--m3-surface)' }}>
      <PullIndicator
        pulled={pull.pulled}
        refreshing={pull.refreshing}
        willRelease={pull.willRelease}
        activationDistance={84}
      />
      <div class="oh-session-detail-shell mx-auto max-w-3xl w-full flex-1 min-h-0 flex flex-col gap-3">
        <SessionTopBar
          title={session?.title || t('sessions.untitled', '未命名会话')}
          subtitle={subtitle}
          onBack={() => location.route('/threads')}
          onRename={async (next) => {
            const requestSessionId = sessionId;
            try {
              const res = await renameSession(requestSessionId, next);
              if (!ownsSessionAsyncResult(requestSessionId)) return;
              setDetail((prev) =>
                prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev,
              );
              showSnackbar(t('topbar.rename.ok', '已重命名会话'), { tone: 'success' });
            } catch (e) {
              if (!ownsSessionAsyncResult(requestSessionId)) return;
              if (handleAuthError(e)) return;
              if (handleSessionGoneError(e)) return;
              const message = e instanceof Error ? e.message : String(e);
              setLastError(message);
              showSnackbar(`${t('topbar.rename.failed', '重命名失败')}：${message}`, { tone: 'error' });
              throw e;
            }
          }}
          onDelete={async () => {
            setPendingSessionDelete(true);
          }}
          onExport={async () => {
            const requestSessionId = sessionId;
            try {
              showSnackbar(t('topbar.export.started', '正在导出会话数据…'));
              const result = await exportSessionDownload(
                requestSessionId,
                session?.title || requestSessionId,
              );
              if (!ownsSessionAsyncResult(requestSessionId)) return;
              showSnackbar(`${t('topbar.export.ok', '已保存导出文件')}：${result.filename}`, { tone: 'success' });
            } catch (e) {
              if (!ownsSessionAsyncResult(requestSessionId)) return;
              if (e instanceof DOMException && e.name === 'AbortError') return;
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
          onToggleFullscreen={() => void toggleBrowserFullscreen()}
          fullscreenActive={fullscreenActive}
          sessionId={sessionId}
          capsules={sessionCapsules}
          trailing={
            <button
              type="button"
              onClick={refresh}
              disabled={refreshing || loadingDetail}
              class="oh-tap-press oh-icon-button oh-session-refresh-button flex-none disabled:opacity-50"
              style={{
                border: '1px solid var(--m3-outline-variant)',
                color: 'var(--m3-on-surface-variant)',
                background: 'var(--m3-surface)',
              }}
              title={t('detail.refresh', '刷新')}
            >
              <span class={refreshing ? 'oh-spin' : undefined} aria-hidden>
                <ComposerIcon name="refresh" size={17} />
              </span>
            </button>
          }
        />

        {lastError ? (
          <ErrorBanner message={lastError} onRetry={() => void refresh()} onDismiss={() => setLastError(null)} />
        ) : null}

        {remoteRunning ? (
          <div class="oh-remote-running-banner rounded-md px-3 py-2 text-xs flex items-start gap-2">
            <span class="oh-remote-running-text">
              {t(
                'detail.remoteRunning',
                '另一处客户端正在生成回复。如本端正在编辑草稿, 建议等远端结束后再发送, 避免顺序混乱。',
              )}
            </span>
          </div>
        ) : null}

        {/* 主区：只有这块滚动，顶部 TopBar / 底部 Composer 固定在视口内。 */}
        <section ref={mainRef} class="oh-session-messages relative flex-1 min-h-0 overflow-y-auto pr-1 pb-3">
          <div ref={messagesContentRef} class="oh-session-message-content">
          {loadingDetail ? (
            <div class="oh-session-state-card is-loading">
              <span class="oh-session-state-icon oh-spin" aria-hidden><ComposerIcon name="refresh" size={18} /></span>
              <span>{t('detail.loading', '加载会话中…')}</span>
            </div>
          ) : error ? (
            <div class="oh-session-state-card is-error">
              <span class="oh-session-state-icon" aria-hidden><ComposerIcon name="refresh" size={18} /></span>
              <span>{error}</span>
              <button
                type="button"
                onClick={loadDetail}
                class="oh-session-state-action oh-tap-press"
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
                    class="oh-session-load-older-button oh-tap-press disabled:opacity-50"
                  >
                    <span class={loadingOlder ? 'oh-spin' : undefined} aria-hidden>
                      <ComposerIcon name="refresh" size={13} />
                    </span>
                    {loadingOlder
                      ? t('detail.loadingOlder', '加载中…')
                      : t('detail.loadOlder', '加载更早 ') +
                        `(${remainingOlder})`}
                  </button>
                </div>
              ) : null}

            {sortedMessages.length === 0 ? (
              <div class="oh-session-empty-state">
                <span class="oh-session-empty-icon" aria-hidden><ComposerIcon name="chat" size={20} /></span>
                <span>{t('detail.empty', '该会话尚无消息。')}</span>
              </div>
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
                        streaming={m.id === latestStreamingTextMessageId || messageMetadataStreaming(m)}
                        sessionId={sessionId}
                        onActiveChange={handleMessageActiveChange}
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
          </div>
        </section>

        {/* Composer */}
        <section
          ref={composerSectionRef}
          class="oh-session-composer rounded-xl p-4 flex-none"
          data-collapsed={composerCollapsed ? 'true' : 'false'}
          style={{
            background: 'var(--m3-surface-container)',
            boxShadow: 'var(--m3-elev-1)',
          }}
        >
          <div
            class="oh-composer-toolbar"
            data-collapsed={composerCollapsed ? 'true' : 'false'}
          >
            {!composerCollapsed ? (
              <>
            {sessionModeOptions.length > 1 ? (
              <button
                type="button"
                onClick={() => void applySessionMode(nextSessionMode)}
                disabled={composerSending || !canToggleSessionMode}
                class={`oh-session-mode-button oh-composer-control oh-tap-press ${currentSessionMode === 'plan' ? 'is-plan is-tonal' : 'is-chat'}`}
                aria-pressed={currentSessionMode === 'plan'}
                title={sessionModeLabel(currentSessionMode)}
              >
                <span key={`session-mode-icon-${currentSessionMode}`} class="oh-composer-control-icon oh-session-mode-icon oh-soft-replace">
                  <ComposerIcon name={sessionModeIconName(currentSessionMode)} />
                </span>
                <span key={`session-mode-label-${currentSessionMode}`} class="oh-session-mode-label oh-soft-replace">{sessionModeLabel(currentSessionMode)}</span>
              </button>
            ) : null}

            <button
              type="button"
              onClick={() => setShowComposerModelPicker(true)}
              disabled={composerSending || allowedModels.length === 0}
              class="oh-composer-control oh-composer-model-control oh-tap-press disabled:opacity-50 min-w-0"
              title={t('composer.model', '模型')}
            >
              <span class="oh-composer-control-icon">
                <ComposerIcon name="model" />
              </span>
              <span class="truncate">
                {selectedModel?.model_id || selectedModel?.label || t('composer.modelEmpty', '主控制台未配置模型')}
              </span>
            </button>

            <PopMenu
              align="left"
              width={220}
              wrapperClassName="oh-composer-mode-menu"
              items={composerModeOptions.map((mode) => {
                const serviceAllowed = allowedModes.includes(mode);
                const modelAllowed = modelSupportsMode(selectedModel, mode);
                const active = mode === composerMode;
                const label = composerModeLabel(mode);
                const suffix = !serviceAllowed
                  ? t('composer.mode.disabled.service', '（未启用）')
                  : !modelAllowed
                    ? t('composer.mode.disabled.model', '（当前模型不支持）')
                    : '';
                return {
                  key: mode,
                  label: active ? `${label} · ${t('common.current', '当前')}` : `${label}${suffix}`,
                  disabled: composerSending || active || !serviceAllowed || !modelAllowed,
                  selected: active,
                  onClick: () => setComposerMode(mode),
                };
              })}
              trigger={({ open, toggle }) => (
                <button
                  type="button"
                  onClick={toggle}
                  disabled={composerSending}
                  class="oh-composer-control oh-composer-mode-control oh-tap-press is-tonal disabled:opacity-50"
                  aria-expanded={open}
                  title={t('composer.mode', '模式')}
                >
                  <span key={`composer-mode-icon-${composerMode}`} class="oh-composer-control-icon oh-soft-replace">
                    <ComposerIcon name={composerModeIconName(composerMode)} />
                  </span>
                  <span key={`composer-mode-label-${composerMode}`} class="oh-soft-replace">{composerModeLabel(composerMode)}</span>
                  <span class={`oh-composer-caret ${open ? 'is-open' : ''}`}>
                    <ComposerIcon name="chevronDown" size={16} />
                  </span>
                </button>
              )}
            />

            <button
              type="button"
              onClick={() => {
                if (permissionSaving) return;
                const next = session?.full_access_permission !== true;
                requestFullAccessPermissionChange(next);
              }}
              disabled={permissionSaving}
              class={`oh-composer-control oh-composer-permission-control oh-tap-press ${session?.full_access_permission === true ? 'is-full-access' : 'is-muted'}`}
              title={t('topbar.perm.title', '权限模式')}
            >
              <span class="oh-composer-control-icon">
                <ComposerIcon name="permission" />
              </span>
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
                  setAutoFollowEnabled(false);
                  setAutoFollowPausedValue(false);
                }
              }}
              class={`oh-composer-control oh-composer-follow-control oh-tap-press ${autoFollow || autoFollowPaused || unreadCount > 0 ? 'is-tonal' : 'is-muted'}`}
              aria-label={autoFollowPaused || unreadCount > 0
                ? t('detail.resumeToLatest', '回到底部')
                : t('composer.autoFollow', '自动跟随到底部')}
              title={autoFollowPaused || unreadCount > 0
                ? t('detail.resumeToLatest', '回到底部')
                : t('composer.autoFollow', '自动跟随到底部')}
            >
              <span class="oh-composer-control-icon">
                <ComposerIcon name="follow" />
              </span>
              <span>
                {autoFollowPaused || unreadCount > 0
                  ? t('detail.resumeToLatest', '回到底部')
                  : autoFollow
                    ? t('common.on', '开启')
                    : t('common.off', '关闭')}
              </span>
            </button>

              </>
            ) : null}

            <button
              type="button"
              onClick={toggleComposerCollapsed}
              class={`oh-composer-icon-control oh-composer-collapse-control oh-tap-press ${composerCollapsed ? '' : 'ml-auto'}`}
              title={composerCollapsed ? t('composer.expand', '展开输入区') : t('composer.collapse', '收起输入区')}
              aria-label={composerCollapsed ? t('composer.expand', '展开输入区') : t('composer.collapse', '收起输入区')}
              aria-expanded={!composerCollapsed}
            >
              <ComposerIcon name={composerCollapsed ? 'chevronUp' : 'chevronDown'} />
            </button>
          </div>

          <div
            class="oh-composer-body"
            data-collapsed={composerCollapsed ? 'true' : 'false'}
            aria-hidden={composerCollapsed ? 'true' : undefined}
            {...(composerCollapsed ? { inert: true } : {})}
          >
          {availableInstructions.length > 0 ? (
            <ComposerInstructionsStrip
              entries={availableInstructions}
              skipped={skippedInstructionIds}
              disabled={composerSending}
              onToggle={(id) => {
                setSkippedInstructionIds((prev) => {
                  const next = new Set(prev);
                  if (next.has(id)) {
                    next.delete(id);
                  } else {
                    next.add(id);
                  }
                  return next;
                });
              }}
              onResetAll={() => setSkippedInstructionIds(new Set())}
              t={t}
            />
          ) : null}
          <div class="oh-composer-chip-rail mb-3">
            {editingDraftMessage ? (
              <button
                type="button"
                class={`oh-composer-pill oh-composer-edit-pill oh-composer-chip-motion ${composerChipIsExiting('edit-draft') ? 'is-exiting' : ''}`}
                onClick={() => runAfterComposerChipExit('edit-draft', () => {
                  editingDraftMessageRef.current = null;
                  setEditingDraftMessage(null);
                })}
                disabled={composerSending || composerChipIsExiting('edit-draft')}
                title={t('composer.edit.cancel', '取消编辑历史消息')}
              >
                <span class="oh-composer-pill-icon"><ComposerIcon name="edit" size={16} /></span>
                <span class="truncate max-w-[180px]">
                  {t('composer.edit.active', '正在编辑历史消息')}
                </span>
                <span class="oh-composer-pill-icon"><ComposerIcon name="close" size={15} /></span>
              </button>
            ) : null}
            <span key={`mode-${composerMode}`} class="oh-composer-pill oh-composer-mode-pill oh-composer-chip-motion">
              <span class="oh-composer-pill-icon"><ComposerIcon name={composerModeIconName(composerMode)} size={16} /></span>
              {composerModeLabel(composerMode)}
            </span>
            {selectedSkill ? (
              <span
                class={`oh-composer-pill oh-composer-skill-pill oh-composer-chip-motion ${composerChipIsExiting(`skill-${selectedSkill.relative_directory_path}-${selectedSkill.name}`) ? 'is-exiting' : ''}`}
                title={selectedSkill.name}
              >
                <span class="oh-composer-pill-icon">
                  {selectedSkill.emoji_icon || <ComposerIcon name="spark" size={16} />}
                </span>
                <span class="truncate max-w-[180px]">{selectedSkill.name}</span>
                <button
                  type="button"
                  class="oh-composer-pill-close oh-tap-press"
                  onClick={() => runAfterComposerChipExit(`skill-${selectedSkill.relative_directory_path}-${selectedSkill.name}`, () => setSelectedSkill(null))}
                  disabled={composerSending || composerChipIsExiting(`skill-${selectedSkill.relative_directory_path}-${selectedSkill.name}`)}
                  aria-label={t('composer.skill.clear', '移除已选择技能')}
                  title={t('composer.skill.clear', '移除已选择技能')}
                >
                  <ComposerIcon name="close" size={15} />
                </button>
              </span>
            ) : null}
          </div>

          {attachmentsAllowed && composerAttachments.length > 0 ? (
            <ul class="oh-composer-attachment-rail mb-3">
              {composerAttachments.map((att, i) => {
                const pv = attachmentPreviews[i];
                const chipKey = composerAttachmentIds[i] ?? `${att.name}-${i}`;
                const isImage = (pv?.mime ?? '').startsWith('image/');
                const sizeKb = pv ? (pv.size / 1024).toFixed(1) : '';
                return (
                  <li
                    key={chipKey}
                    class={`oh-composer-attachment-chip oh-composer-chip-motion ${composerChipIsExiting(chipKey) ? 'is-exiting' : ''} ${isImage ? 'is-image' : ''}`}
                  >
                    {isImage && pv ? (
                      <button
                        type="button"
                        class="oh-composer-image-thumb"
                        onClick={() => void editAttachmentAt(i)}
                        disabled={composerSending}
                        title={t('imageEditor.title', '编辑图片')}
                      >
                        <img src={pv.dataUrl} alt={att.name} decoding="async" loading="lazy" />
                      </button>
                    ) : (
                      <span aria-hidden class="oh-composer-file-leading">
                        <ComposerIcon name="file" size={16} />
                      </span>
                    )}
                    {!isImage ? (
                      <span class="flex flex-col min-w-0">
                        <span class="truncate max-w-[180px]">{att.name}</span>
                        {pv ? (
                          <span class="truncate" style={{ color: 'var(--m3-on-surface-variant)', fontSize: '10px' }}>
                            {pv.mime || 'application/octet-stream'} · {sizeKb} KB
                          </span>
                        ) : null}
                      </span>
                    ) : null}
                    <button
                      type="button"
                      onClick={() => requestRemoveAttachmentAt(i)}
                      disabled={composerSending || composerChipIsExiting(chipKey)}
                      class="oh-composer-chip-close"
                      aria-label={t('composer.attachment.remove', '移除附件')}
                    >
                      <ComposerIcon name="close" size={14} />
                    </button>
                  </li>
                );
              })}
            </ul>
          ) : null}

          {queuedComposerMessages.length > 0 ? (
            <section class="oh-queued-message-panel mb-3" aria-label={t('composer.queue.title', '自动发送等待队列')}>
              <div class="oh-queued-message-header">
                <span class="oh-queued-message-title">
                  <ComposerIcon name="send" size={15} />
                  {t('composer.queue.title', '自动发送等待队列')}
                </span>
                <span class="oh-queued-message-count">
                  {queuedComposerMessages.length} {t('composer.queue.unit', '条')}
                </span>
              </div>
              <ul class="oh-queued-message-list">
                {queuedComposerMessages.map((item, index) => {
                  const isEditingQueued = editingQueuedMessageId === item.id;
                  const isDispatchingQueued = queueDispatchingId === item.id;
                  const queueKey = `${item.id}-${queuedListMotionGeneration}`;
                  return (
                    <li
                      key={queueKey}
                      class={`oh-queued-message-row ${queuedMessageIsExiting(item.id) ? 'is-exiting' : ''} ${isDispatchingQueued ? 'is-dispatching' : ''}`}
                    >
                      <div class="oh-queued-message-index">{index + 1}</div>
                      <div class="oh-queued-message-main">
                        {isEditingQueued ? (
                          <div class="oh-queued-message-edit">
                            <textarea
                              value={queuedEditText}
                              onInput={(event) => setQueuedEditText(event.currentTarget.value)}
                              rows={3}
                              aria-label={t('composer.queue.editLabel', '编辑等待消息')}
                            />
                            <div class="oh-queued-message-edit-actions">
                              <button
                                type="button"
                                class="oh-tap-press oh-queued-message-mini-action"
                                onClick={() => saveQueuedMessageEdit(item.id)}
                                disabled={!queuedEditText.trim()}
                              >
                                {t('common.save', '保存')}
                              </button>
                              <button
                                type="button"
                                class="oh-tap-press oh-queued-message-mini-action is-muted"
                                onClick={() => {
                                  setEditingQueuedMessageId(null);
                                  setQueuedEditText('');
                                }}
                              >
                                {t('common.cancel', '取消')}
                              </button>
                            </div>
                          </div>
                        ) : (
                          <>
                            <p class="oh-queued-message-text">
                              {item.content || t('composer.queue.attachmentOnly', '仅附件消息')}
                            </p>
                            <div class="oh-queued-message-meta">
                              <span>{composerModeLabel(item.mode)}</span>
                              <span>{item.modelLabel || item.modelKey}</span>
                              {item.selectedSkill ? <span>{item.skillLabel ?? item.selectedSkill.name}</span> : null}
                              {item.attachments.length > 0 ? (
                                <span>{item.attachments.length} {t('composer.attachment.unit', '个附件')}</span>
                              ) : null}
                              {isDispatchingQueued ? <span>{t('composer.queue.sending', '正在自动发送')}</span> : null}
                            </div>
                          </>
                        )}
                      </div>
                      <div class="oh-queued-message-actions">
                        <button
                          type="button"
                          class="oh-tap-press oh-queued-message-icon-action"
                          onClick={() => moveQueuedMessage(index, index - 1)}
                          disabled={index === 0 || isDispatchingQueued}
                          title={t('composer.queue.moveUp', '上移')}
                          aria-label={t('composer.queue.moveUp', '上移')}
                        >
                          <ComposerIcon name="chevronUp" size={15} />
                        </button>
                        <button
                          type="button"
                          class="oh-tap-press oh-queued-message-icon-action"
                          onClick={() => moveQueuedMessage(index, index + 1)}
                          disabled={index >= queuedComposerMessages.length - 1 || isDispatchingQueued}
                          title={t('composer.queue.moveDown', '下移')}
                          aria-label={t('composer.queue.moveDown', '下移')}
                        >
                          <ComposerIcon name="chevronDown" size={15} />
                        </button>
                        <button
                          type="button"
                          class="oh-tap-press oh-queued-message-icon-action"
                          onClick={() => startEditQueuedMessage(item)}
                          disabled={isDispatchingQueued}
                          title={t('composer.queue.edit', '编辑')}
                          aria-label={t('composer.queue.edit', '编辑')}
                        >
                          <ComposerIcon name="edit" size={15} />
                        </button>
                        <button
                          type="button"
                          class="oh-tap-press oh-queued-message-icon-action is-danger"
                          onClick={() => removeQueuedMessage(item.id)}
                          disabled={isDispatchingQueued}
                          title={t('composer.queue.remove', '删除')}
                          aria-label={t('composer.queue.remove', '删除')}
                        >
                          <ComposerIcon name="close" size={15} />
                        </button>
                      </div>
                    </li>
                  );
                })}
              </ul>
            </section>
          ) : null}

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
          {skillPickerVisible && skillPickerAnchor ? (
            <OverlayPortal>
              <div
                class={`oh-skill-picker ${skillPickerClosing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'}`}
                role="listbox"
                style={{
                  position: 'fixed',
                  bottom: `${skillPickerAnchor.bottomGap}px`,
                  left: `${skillPickerAnchor.left}px`,
                  width: `${skillPickerAnchor.width}px`,
                  maxHeight: `${skillPickerAnchor.maxHeight}px`,
                  zIndex: 2400,
                }}
              >
              <div class="oh-skill-picker-title">
                <span aria-hidden><ComposerIcon name="spark" size={16} /></span>
                {t('composer.skill.pick', '选择一个技能')}
              </div>
              {skillPickerLoading ? (
                <div class="oh-skill-picker-empty">{t('common.loading', '加载中…')}</div>
              ) : skillPickerResults.length === 0 ? (
                <div class="oh-skill-picker-empty">{t('composer.skill.empty', '未找到匹配技能')}</div>
              ) : (
                <ul class="oh-skill-picker-list">
                  {skillPickerResults.map((skill, index) => (
                    <li key={`${skill.relative_directory_path}-${skill.name}`}>
                      <button
                        type="button"
                        role="option"
                        aria-selected={index === skillPickerSelectedIndex}
                        class="oh-skill-picker-item"
                        data-active={index === skillPickerSelectedIndex ? 'true' : 'false'}
                        onMouseEnter={() => setSkillPickerSelectedIndex(index)}
                        onClick={() => selectSkillForComposer(skill)}
                      >
                        <span class="oh-skill-picker-leading" aria-hidden>
                          {skill.emoji_icon || <ComposerIcon name="spark" size={16} />}
                        </span>
                        <span class="min-w-0 flex-1 text-left">
                          <span class="block truncate font-semibold">{skill.name}</span>
                          {(skill.description ?? '').trim() ? (
                            <span class="block truncate text-[11px] opacity-70">{skill.description}</span>
                          ) : null}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
              </div>
            </OverlayPortal>
          ) : null}
          <textarea
            ref={composerTextareaRef}
            value={composerText}
            onInput={(e) => {
              const target = e.currentTarget as HTMLTextAreaElement;
              setComposerText(target.value);
              updateSkillPickerForText(target.value, target.selectionStart ?? target.value.length);
            }}
            onSelect={(e) => {
              const target = e.currentTarget as HTMLTextAreaElement;
              updateSkillPickerForText(target.value, target.selectionStart ?? target.value.length);
            }}
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
              handleComposerKeyDown(e as unknown as KeyboardEvent);
            }}
            disabled={composerSending || composerCollapsed}
            rows={4}
            placeholder={t('composer.placeholder', '输入消息')}
            class="oh-composer-textarea w-full px-3 py-2 rounded-md text-sm"
          />
          {dragOver ? (
            <div
              class="oh-composer-drop-overlay absolute inset-0 rounded-md flex items-center justify-center text-sm pointer-events-none oh-appear-up"
            >
              {t('composer.attachment.drop', '松开即可添加附件')}
            </div>
          ) : null}
          </div>

          {composerError ? (
            <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
              {composerError}
            </p>
          ) : null}
          </div>

          <div
            class="oh-composer-footer flex flex-wrap items-center gap-2 mt-3"
            data-collapsed={composerCollapsed ? 'true' : 'false'}
            aria-hidden={composerCollapsed ? 'true' : undefined}
            {...(composerCollapsed ? { inert: true } : {})}
          >
            {attachmentsAllowed ? (
              <label
                class="oh-tap-press oh-composer-footer-action is-attachment cursor-pointer"
              >
                <span class="oh-composer-action-icon"><ComposerIcon name="attachment" size={16} /></span>
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
                : ''}
            </span>
            {composerAttachments.length > 0 ? (
              <span class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {composerAttachments.length} {t('composer.attachment.unit', '个附件')}
              </span>
            ) : null}
            {responseRunning ? (
              <button
                type="button"
                onClick={handleStop}
                disabled={stopping}
                class="oh-tap-press oh-composer-footer-action is-stop disabled:opacity-50"
              >
                <span class={stopping ? 'oh-spin' : undefined}>
                  <ComposerIcon name={stopping ? 'refresh' : 'stop'} size={16} />
                </span>
                <span>{stopping
                  ? t('composer.stopping', '正在停止…')
                  : t('composer.stop', '停止响应')}</span>
              </button>
            ) : null}
            <button
              type="button"
              onClick={handleSend}
              disabled={composerSendDisabled}
              class={`oh-tap-press oh-composer-footer-action is-send disabled:opacity-50 ${responseRunning ? 'is-queueing' : ''}`}
            >
              <span class={composerSending ? 'oh-spin' : undefined}>
                <ComposerIcon name={composerSending ? 'refresh' : 'send'} size={16} />
              </span>
              <span>{composerSending
                ? t('composer.sending', '发送中…')
                : responseRunning
                  ? t('composer.queue.aheadSend', '提前发送')
                  : t('composer.send', '发送')}</span>
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
      {tokenStatsOpen && detail ? (
        <SessionTokenStatsDialog
          detail={detail}
          onClose={() => setTokenStatsOpen(false)}
        />
      ) : null}
      {contextStatsOpen && detail ? (
        <SessionContextStatsDialog
          detail={detail}
          messages={messages}
          modelKey={composerModelKey}
          onClose={() => setContextStatsOpen(false)}
          onCompacted={() => {
            // 压缩成功后由 SSE 推送会话快照，但拉一遍 detail 仍然是稳妥的兜底。
            void refresh();
          }}
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
          body={(
            <div class="oh-write-approval-dialog-content">
              <p class="oh-write-approval-dialog-copy">
                {t('detail.writeApproval.body', '当前默认权限模式需要确认后才会继续执行写文件或命令操作。')}
              </p>
              <div class="oh-write-approval-dialog-field">
                <span class="oh-write-approval-dialog-label">{t('detail.writeApproval.cwd', '工作目录')}</span>
                <code class="oh-write-approval-dialog-path">{pendingWriteApproval.working_directory || '-'}</code>
              </div>
              <div class="oh-write-approval-dialog-field">
                <span class="oh-write-approval-dialog-label">{t('detail.writeApproval.command', '命令')}</span>
                <pre class="oh-write-approval-dialog-command">{pendingWriteApproval.command || '-'}</pre>
              </div>
            </div>
          )}
          danger
          busy={writeApprovalBusy}
          wide
          scrollBody
          confirmLabel={writeApprovalBusy
            ? t('common.processing', '处理中…')
            : t('detail.writeApproval.approve', '允许执行')}
          cancelLabel={t('detail.writeApproval.reject', '拒绝')}
          onCancel={() => void handleWriteApproval(false)}
          onConfirm={() => void handleWriteApproval(true)}
        />
      ) : null}
      {imageEditorInput ? (
        <ImageEditorDialog
          input={imageEditorInput}
          onCancel={() => settleImageEditor(null)}
          onSave={(result) => settleImageEditor(result)}
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
      class="oh-session-error-banner rounded-md px-3 py-2 text-xs flex flex-col gap-1.5"
      style={{
        background: 'color-mix(in srgb, var(--m3-error) 8%, transparent)',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-error) 35%, transparent)',
        maxWidth: '100%',
      }}
      role="alert"
    >
      <div class="oh-session-error-content flex items-start gap-2">
        <div class="flex-1 min-w-0">
          <div class="oh-session-error-title" style={{ color: 'var(--m3-error)', fontWeight: 600 }}>{title}</div>
          {hint ? (
            <div class="oh-session-error-hint" style={{ color: 'var(--m3-on-surface-variant)', marginTop: 2 }}>{hint}</div>
          ) : null}
          <div
            class="oh-session-error-message"
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
      <div class="oh-session-error-actions flex items-center gap-2 self-end">
        <button
          type="button"
          class="oh-tap-press oh-session-error-action is-primary"
          onClick={onRetry}
          style={{
            padding: '4px 10px',
            minHeight: 26,
            borderRadius: 999,
            background: 'var(--m3-primary)',
            color: 'var(--m3-on-primary)',
            border: 'none',
            fontSize: 12,
            cursor: 'pointer',
            display: 'inline-flex',
            alignItems: 'center',
            gap: 5,
            whiteSpace: 'nowrap',
            flex: '0 0 auto',
          }}
        >
          <ComposerIcon name="refresh" size={13} />
          <span>{t('common.retry', '重试')}</span>
        </button>
        <button
          type="button"
          class="oh-tap-press oh-session-error-action"
          onClick={() => void copyText()}
          style={{
            padding: '4px 10px',
            minHeight: 26,
            borderRadius: 999,
            background: 'transparent',
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
            fontSize: 12,
            cursor: 'pointer',
            display: 'inline-flex',
            alignItems: 'center',
            gap: 5,
            whiteSpace: 'nowrap',
            flex: '0 0 auto',
          }}
        >
          <ComposerIcon name="copy" size={13} />
          <span>{t('common.copy', '复制')}</span>
        </button>
        <button
          type="button"
          class="oh-tap-press oh-session-error-action is-icon"
          onClick={onDismiss}
          aria-label={t('common.cancel', '取消')}
          style={{
            padding: '4px 10px',
            minWidth: 26,
            minHeight: 26,
            borderRadius: 999,
            background: 'transparent',
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid transparent',
            fontSize: 12,
            cursor: 'pointer',
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            flex: '0 0 auto',
          }}
        >
          <ComposerIcon name="close" size={14} />
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
  const { closing, requestClose } = useDialogExitMotion(onClose);
  useEffect(() => {
    if (closing) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closing, requestClose]);
  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 z-[2600] flex items-center justify-center p-4`}
      style={{ background: 'rgba(0,0,0,0.40)', zIndex: 2600 }}
      onClick={requestClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} rounded-m3-md p-4 max-w-2xl w-full flex flex-col`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          maxHeight: '80vh',
          border: '1px solid var(--m3-outline)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="flex flex-wrap items-center justify-between gap-3 mb-3">
          <h2 class="text-base font-semibold min-w-0 truncate">{t('common.audit', '审计')} · {message.id}</h2>
          <div class="flex flex-wrap items-center justify-end gap-2">
            <button
              type="button"
              class="oh-tap-press oh-dialog-action-button"
              style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline)' }}
              onClick={() => void copyJsonWithFeedback(json)}
            >
              <ComposerIcon name="copy" size={14} />
              <span>{t('common.copy', '复制')}</span>
            </button>
            <button
              type="button"
              class="oh-tap-press oh-dialog-action-button"
              style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
              onClick={requestClose}
            >
              <ComposerIcon name="close" size={14} />
              <span>{t('common.close', '关闭')}</span>
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
  return <OverlayPortal>{node}</OverlayPortal>;
}

function SessionTokenStatsDialog({
  detail,
  onClose,
}: {
  detail: SessionDetailResponse;
  onClose: () => void;
}) {
  const session = detail.session;
  const stats = session.statistics ?? {};
  const promptTokens = readStatNumber(stats['total_prompt_tokens'], session.total_prompt_tokens);
  const completionTokens = readStatNumber(
    stats['total_completion_tokens'],
    session.total_completion_tokens,
  );
  const cacheReadTokens = readStatNumber(stats['cache_read_tokens'], 0);
  const cacheWriteTokens = readStatNumber(stats['cache_creation_tokens'], 0);
  const totalTokens = readStatNumber(
    stats['total_tokens'],
    session.total_tokens ?? promptTokens + completionTokens,
  );
  const totalMessageCount = readStatNumber(stats['total_message_count'], session.message_count);
  const promptBuildCount = readStatNumber(stats['prompt_build_count'], 0);
  const totalPromptCharacters = readStatNumber(stats['total_prompt_characters'], 0);
  const cacheHitBase = promptTokens + cacheReadTokens;
  const cacheHitRatio = cacheHitBase === 0
    ? 0
    : Math.round((cacheReadTokens / cacheHitBase) * 100);
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'rgba(0,0,0,0.36)', backdropFilter: 'blur(2px)', zIndex: 2600 }}
      onClick={requestClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} w-full max-w-md rounded-m3-xl p-5`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline-variant)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="mb-4 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-base font-semibold">{t('topbar.tokens', 'Token 统计')}</h2>
            <p class="mt-0.5 truncate text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {session.title || t('sessions.untitled', '未命名会话')}
            </p>
          </div>
          <button
            type="button"
            class="oh-tap-press rounded-m3-sm px-2 py-1 text-sm"
            style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
            onClick={requestClose}
          >
            {t('common.close', '关闭')}
          </button>
        </header>
        <div class="space-y-4">
          <TokenStatsSection title={t('tokenPopup.input', '输入')}>
            <TokenStatsRow label={t('tokenPopup.prompt', 'Prompt')} value={promptTokens} />
            <TokenStatsRow label={t('tokenPopup.cacheRead', 'Cache 命中')} value={cacheReadTokens} tone="success" />
            <TokenStatsRow label={t('tokenPopup.cacheWrite', 'Cache 写入')} value={cacheWriteTokens} tone="success" />
          </TokenStatsSection>
          <TokenStatsSection title={t('tokenPopup.output', '输出')}>
            <TokenStatsRow label={t('tokenPopup.completion', 'Completion')} value={completionTokens} />
          </TokenStatsSection>
          <div
            class="rounded-m3-md px-3 py-2.5"
            style={{
              background: 'var(--m3-primary-container)',
              color: 'var(--m3-on-primary-container)',
              border: '1px solid color-mix(in srgb, var(--m3-primary) 34%, transparent)',
            }}
          >
            <TokenStatsRow label={t('tokenPopup.total', '总计')} value={totalTokens} emphasized />
            {(cacheReadTokens > 0 || cacheWriteTokens > 0) ? (
              <TokenStatsRow label={t('tokenPopup.cacheHit', '缓存命中率')} value={cacheHitRatio} suffix="%" tone="success" />
            ) : null}
          </div>
          <TokenStatsSection title={t('tokenPopup.session', '会话累计')}>
            <TokenStatsRow label={t('tokenPopup.messages', '消息总数')} value={totalMessageCount} />
            <TokenStatsRow label={t('tokenPopup.promptBuilds', 'Prompt 构建')} value={promptBuildCount} />
            <TokenStatsRow label={t('tokenPopup.promptChars', 'Prompt 字符')} value={totalPromptCharacters} />
          </TokenStatsSection>
        </div>
      </div>
    </div>
  );
  return <OverlayPortal>{node}</OverlayPortal>;
}

interface ContextStatsBreakdown {
  userChars: number;
  assistantChars: number;
  toolChars: number;
  otherChars: number;
}

function computeContextBreakdown(messages: SessionMessage[]): ContextStatsBreakdown {
  let userChars = 0;
  let assistantChars = 0;
  let toolChars = 0;
  let otherChars = 0;
  for (const msg of messages) {
    if ((msg as { is_deleted?: boolean }).is_deleted) continue;
    const chars = typeof msg.character_count === 'number' && msg.character_count >= 0
      ? msg.character_count
      : (msg.content ?? '').length;
    switch (msg.kind) {
      case 'user':
        userChars += chars;
        break;
      case 'assistant':
      case 'reasoning':
        assistantChars += chars;
        break;
      case 'tool_call':
      case 'tool':
      case 'mcp':
      case 'skill':
      case 'hook':
        toolChars += chars;
        break;
      default:
        otherChars += chars;
    }
  }
  return { userChars, assistantChars, toolChars, otherChars };
}

function compactStatusMessage(status: CompactSessionStatus, retryAfterMs?: number): string {
  switch (status) {
    case 'success':
      return t('contextStats.success', '已生成压缩检查点。');
    case 'cooldown': {
      const secs = Math.max(1, Math.round((retryAfterMs ?? 30000) / 1000));
      return t('contextStats.cooldown', '刚刚已经压缩过，约 {secs} 秒后再试。')
        .replace('{secs}', String(secs));
    }
    case 'not_needed':
      return t('contextStats.notNeeded', '当前占用过低或没有可压缩的历史。');
    case 'inflight':
      return t('contextStats.inflight', '已有压缩任务在进行中。');
    case 'session_busy':
      return t('contextStats.sessionBusy', '当前会话正在响应，请等回复结束后再压缩。');
    case 'circuit_breaker':
      return t('contextStats.circuitBreaker', '连续压缩失败已熔断，稍后再试。');
    case 'failed':
      return t('contextStats.failed', '压缩未生效，请稍后重试。');
    case 'no_session':
      return t('contextStats.noSession', '会话不存在或已被删除。');
    default:
      return status;
  }
}

function SessionContextStatsDialog({
  detail,
  messages,
  modelKey,
  onClose,
  onCompacted,
}: {
  detail: SessionDetailResponse;
  messages: SessionMessage[];
  modelKey: string;
  onClose: () => void;
  onCompacted: () => void;
}) {
  const session = detail.session;
  const meta = asRecord(session.last_prompt_metadata);
  const estimatedTokens = asInt(meta['context_budget_estimated_prompt_tokens']);
  const percentLeftRaw = meta['context_budget_percent_left'];
  const percentLeft = typeof percentLeftRaw === 'number' ? percentLeftRaw : -1;
  const usagePercent = asInt(meta['context_budget_usage_percent']);
  const effectiveWindow = asInt(meta['context_budget_effective_window_tokens']);
  const remainingTokens = asInt(meta['context_budget_remaining_tokens']);
  const inferred = meta['context_budget_window_inferred'] === true;
  const status = String(meta['context_budget_status'] ?? '').trim();

  const breakdown = useMemo(() => computeContextBreakdown(messages), [messages]);
  const totalChars = breakdown.userChars + breakdown.assistantChars +
    breakdown.toolChars + breakdown.otherChars;
  const stats = session.statistics ?? {};
  const cumulativePromptTokens = readStatNumber(
    stats['total_prompt_tokens'],
    session.total_prompt_tokens ?? 0,
  );
  const cumulativeCompletionTokens = readStatNumber(
    stats['total_completion_tokens'],
    session.total_completion_tokens ?? 0,
  );
  const cumulativeTokens = readStatNumber(
    stats['total_tokens'],
    session.total_tokens ?? cumulativePromptTokens + cumulativeCompletionTokens,
  );

  const [busy, setBusy] = useState(false);
  const [resultMessage, setResultMessage] = useState<string | null>(null);
  const [resultIsError, setResultIsError] = useState(false);
  const { closing, requestClose } = useDialogExitMotion(onClose);

  const disableCompact = estimatedTokens <= 0 ||
    (percentLeft >= 0 && percentLeft > 85) ||
    usagePercent < 10 ||
    busy;

  const statusBadge = status === 'critical'
    ? { color: 'var(--m3-error)', label: t('topbar.contextBudget.critical', '危险') }
    : status === 'auto_compact'
      ? { color: 'var(--m3-tertiary)', label: t('topbar.contextBudget.compact', '压缩') }
      : status === 'warning'
        ? { color: '#e07a00', label: t('topbar.contextBudget.warning', '偏高') }
        : status === 'ok'
          ? { color: 'var(--m3-primary)', label: t('topbar.contextBudget.ok', '正常') }
          : { color: 'var(--m3-outline)', label: t('topbar.contextBudget.unknown', '未知') };

  async function handleCompactPressed() {
    if (busy) return;
    setBusy(true);
    setResultMessage(null);
    setResultIsError(false);
    try {
      const response: CompactSessionResponse = await compactSession(session.id, { modelKey });
      setResultMessage(compactStatusMessage(response.status, response.retry_after_ms));
      setResultIsError(!response.ok);
      if (response.ok) onCompacted();
    } catch (error) {
      setResultMessage(
        t('contextStats.error', '压缩请求失败：{detail}')
          .replace('{detail}', error instanceof Error ? error.message : String(error)),
      );
      setResultIsError(true);
    } finally {
      setBusy(false);
    }
  }

  const breakdownRows = [
    { key: 'user', label: t('contextStats.user', '用户'), chars: breakdown.userChars, color: 'var(--m3-primary)' },
    { key: 'assistant', label: t('contextStats.assistant', 'AI 回复'), chars: breakdown.assistantChars, color: 'var(--m3-secondary)' },
    { key: 'tool', label: t('contextStats.tool', '工具'), chars: breakdown.toolChars, color: 'var(--m3-tertiary)' },
    { key: 'other', label: t('contextStats.other', '附件 / 其他'), chars: breakdown.otherChars, color: 'var(--m3-outline)' },
  ];

  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'rgba(0,0,0,0.36)', backdropFilter: 'blur(2px)', zIndex: 2600 }}
      onClick={requestClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} w-full max-w-md rounded-m3-xl p-5`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline-variant)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="mb-4 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-base font-semibold">{t('contextStats.title', '上下文使用情况')}</h2>
            <p class="mt-0.5 truncate text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {session.title || t('sessions.untitled', '未命名会话')}
            </p>
          </div>
          <button
            type="button"
            class="oh-tap-press rounded-m3-sm px-2 py-1 text-sm"
            style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
            onClick={requestClose}
            disabled={busy}
          >
            {t('common.close', '关闭')}
          </button>
        </header>
        <div class="space-y-4">
          <section
            class="rounded-m3-md p-3"
            style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
          >
            <ContextStatsRow
              label={t('contextStats.estimated', '估算 prompt tokens')}
              value={estimatedTokens > 0 ? estimatedTokens.toLocaleString() : t('contextStats.empty', '暂无')}
            />
            <ContextStatsRow
              label={t('contextStats.usage', '占用 / 剩余')}
              value={estimatedTokens > 0 && percentLeft >= 0
                ? `${usagePercent}% · ${Math.round(percentLeft)}%`
                : t('contextStats.empty', '暂无')}
              valueColor={statusBadge.color}
              suffix={statusBadge.label}
            />
            <ContextStatsRow
              label={t('contextStats.window', '有效窗口 tokens')}
              value={effectiveWindow > 0
                ? `${effectiveWindow.toLocaleString()}${inferred ? '*' : ''}`
                : t('contextStats.empty', '暂无')}
            />
            <ContextStatsRow
              label={t('contextStats.remaining', '剩余 tokens')}
              value={remainingTokens > 0 ? remainingTokens.toLocaleString() : t('contextStats.empty', '暂无')}
            />
          </section>
          <section
            class="rounded-m3-md p-3"
            style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
          >
            <h3 class="mb-2 text-xs font-semibold" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('contextStats.breakdown', '会话历史字符占比')}
            </h3>
            {totalChars <= 0 ? (
              <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('contextStats.empty.history', '暂无历史。')}
              </p>
            ) : (
              <div class="space-y-2">
                {breakdownRows.map((row) => (
                  <ContextBreakdownBar
                    key={row.key}
                    label={row.label}
                    chars={row.chars}
                    totalChars={totalChars}
                    color={row.color}
                  />
                ))}
              </div>
            )}
          </section>
          <section
            class="rounded-m3-md p-3"
            style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
          >
            <ContextStatsRow
              label={t('contextStats.cumulativePrompt', '历史累计 prompt tokens')}
              value={cumulativePromptTokens.toLocaleString()}
            />
            <ContextStatsRow
              label={t('contextStats.cumulativeCompletion', '历史累计输出 tokens')}
              value={cumulativeCompletionTokens.toLocaleString()}
            />
            <ContextStatsRow
              label={t('contextStats.cumulativeTotal', '历史总 tokens')}
              value={cumulativeTokens.toLocaleString()}
              emphasized
            />
          </section>
          {resultMessage ? (
            <div
              class="rounded-m3-sm px-3 py-2 text-xs"
              style={{
                background: resultIsError
                  ? 'color-mix(in srgb, var(--m3-error-container) 60%, transparent)'
                  : 'color-mix(in srgb, var(--m3-primary-container) 60%, transparent)',
                color: resultIsError ? 'var(--m3-on-error-container)' : 'var(--m3-on-primary-container)',
                border: `1px solid ${resultIsError ? 'var(--m3-error)' : 'var(--m3-primary)'}`,
              }}
            >
              {resultMessage}
            </div>
          ) : null}
          {inferred ? (
            <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('contextStats.inferred', '* 模型未声明 maxContextTokens，按 128000 估算。')}
            </p>
          ) : null}
          <div class="flex justify-end">
            <button
              type="button"
              class="oh-tap-press rounded-m3-md px-4 py-2 text-sm font-semibold"
              style={{
                background: disableCompact ? 'var(--m3-surface-variant)' : 'var(--m3-primary)',
                color: disableCompact ? 'var(--m3-on-surface-variant)' : 'var(--m3-on-primary)',
                cursor: disableCompact ? 'not-allowed' : 'pointer',
                opacity: disableCompact ? 0.7 : 1,
              }}
              disabled={disableCompact}
              onClick={() => void handleCompactPressed()}
            >
              {busy
                ? t('contextStats.busy', '正在压缩…')
                : t('contextStats.action', '立即压缩')}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
  return <OverlayPortal>{node}</OverlayPortal>;
}

function ContextStatsRow({
  label,
  value,
  valueColor,
  suffix,
  emphasized = false,
}: {
  label: string;
  value: string;
  valueColor?: string;
  suffix?: string;
  emphasized?: boolean;
}) {
  return (
    <div class="flex items-baseline justify-between gap-3 py-1">
      <span class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</span>
      <span
        class={emphasized ? 'text-base font-bold tabular-nums' : 'text-sm font-semibold tabular-nums'}
        style={{ color: valueColor ?? 'var(--m3-on-surface)' }}
      >
        {value}
        {suffix ? <span class="ml-1 text-xs font-normal">· {suffix}</span> : null}
      </span>
    </div>
  );
}

function ContextBreakdownBar({
  label,
  chars,
  totalChars,
  color,
}: {
  label: string;
  chars: number;
  totalChars: number;
  color: string;
}) {
  const ratio = totalChars <= 0 ? 0 : chars / totalChars;
  const percent = (ratio * 100).toFixed(1);
  return (
    <div>
      <div class="flex items-baseline justify-between text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
        <span>{label}</span>
        <span class="tabular-nums">{chars.toLocaleString()} · {percent}%</span>
      </div>
      <div class="mt-1 h-1.5 w-full overflow-hidden rounded" style={{ background: 'color-mix(in srgb, ' + color + ' 18%, transparent)' }}>
        <div
          class="h-full"
          style={{
            width: `${Math.max(0, Math.min(100, ratio * 100))}%`,
            background: color,
            transition: 'width 220ms ease-out',
          }}
        />
      </div>
    </div>
  );
}

function TokenStatsSection({ title, children }: { title: string; children: ComponentChildren }) {
  return (
    <section
      class="rounded-m3-md p-3"
      style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
    >
      <h3 class="mb-2 text-[11px] font-semibold uppercase" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {title}
      </h3>
      <div class="space-y-1.5">{children}</div>
    </section>
  );
}

function TokenStatsRow({
  label,
  value,
  suffix = '',
  tone = 'neutral',
  emphasized = false,
}: {
  label: string;
  value: number;
  suffix?: string;
  tone?: 'neutral' | 'success';
  emphasized?: boolean;
}) {
  const color = tone === 'success' ? 'var(--m3-secondary)' : 'var(--m3-on-surface)';
  return (
    <div class="flex items-center justify-between gap-3 text-sm">
      <span style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</span>
      <span
        class={emphasized ? 'text-base font-bold tabular-nums' : 'font-semibold tabular-nums'}
        style={{ color }}
      >
        {value.toLocaleString()}{suffix}
      </span>
    </div>
  );
}

function readStatNumber(value: unknown, fallback: unknown): number {
  const raw = value ?? fallback;
  if (typeof raw === 'number' && Number.isFinite(raw)) return Math.max(0, Math.round(raw));
  if (typeof raw === 'string') {
    const parsed = Number(raw);
    if (Number.isFinite(parsed)) return Math.max(0, Math.round(parsed));
  }
  return 0;
}

function formatDialogDate(value?: string | null): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asInt(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  const parsed = Number.parseInt(String(value ?? '').trim(), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asStringList(value: unknown): string[] {
  return asArray(value)
    .map((item) => String(item ?? '').trim())
    .filter(Boolean);
}

function contextBudgetToolbarLabel(metadata: Record<string, unknown>): string | null {
  const estimatedTokens = asInt(metadata['context_budget_estimated_prompt_tokens']);
  if (estimatedTokens <= 0) return null;
  const percentLeft = asInt(metadata['context_budget_percent_left']);
  const status = String(metadata['context_budget_status'] ?? '').trim();
  const statusLabel = status === 'critical'
    ? t('topbar.contextBudget.critical', '危险')
    : status === 'auto_compact'
      ? t('topbar.contextBudget.compact', '压缩')
      : status === 'warning'
        ? t('topbar.contextBudget.warning', '偏高')
        : status === 'ok'
          ? t('topbar.contextBudget.ok', '正常')
          : t('topbar.contextBudget.unknown', '未知');
  return `${t('topbar.contextBudget', '上下文')} ${percentLeft}% · ${statusLabel}`;
}

function mcpLazyLoadingCapsule(notices: string[]): SessionToolbarCapsule | null {
  const pattern = /MCP tool lazy loading active.*?(\d+)\s+of\s+(\d+)\s+MCP tool/i;
  for (const notice of notices) {
    const match = pattern.exec(notice);
    if (!match) continue;
    const deferred = Number.parseInt(match[1] ?? '', 10);
    const total = Number.parseInt(match[2] ?? '', 10);
    if (!Number.isFinite(deferred) || !Number.isFinite(total) || total <= 0) continue;
    const loaded = Math.max(0, Math.min(total, total - deferred));
    return {
      key: 'mcp-lazy-loading',
      icon: 'runtime',
      label: t('topbar.mcpLazyLoading', 'MCP {loaded}/{total}')
        .replace('{loaded}', String(loaded))
        .replace('{total}', String(total)),
      title: notice,
    };
  }
  return null;
}

function metadataValue(value: unknown): string {
  if (value == null || value === '') return '—';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function metadataFieldLabel(field: string): string {
  const labels: Record<string, string> = {
    session_id: '会话 ID',
    template: '模板',
    created_at: '创建时间',
    updated_at: '更新时间',
    last_model: '最近模型',
    compression_checkpoint: '压缩检查点',
    latest_compression_at: '最近压缩时间',
    total_input_characters: '输入字符总数',
    total_output_characters: '输出字符总数',
    total_prompt_characters: 'Prompt 字符总数',
    last_prompt_system_message_count: '上次 Prompt 系统消息数',
    last_prompt_history_message_count: '上次 Prompt 历史消息数',
    context_budget_estimated_prompt_tokens: '估算 Prompt Token',
    context_budget_model_max_tokens: '模型上下文窗口',
    context_budget_effective_window_tokens: '有效上下文窗口',
    context_budget_auto_compact_threshold_tokens: '自动压缩阈值',
    context_budget_remaining_tokens: '估算剩余 Token',
    context_budget_percent_left: '距自动压缩剩余',
    context_budget_usage_percent: '估算使用率',
    compact_memory_sidecar_status: 'Sidecar 状态',
    compact_memory_checkpoint_id: 'Checkpoint ID',
    compact_memory_checkpoint_characters: 'Checkpoint 字符数',
    compact_memory_restored_from_sidecar: '从 Sidecar 恢复',
    compact_memory_sidecar_path: 'Sidecar 路径',
    locale_tag: '语言区域',
    platform: '平台',
    app_version: '应用版本',
    compression_threshold_chars: '压缩阈值字符数',
    single_round_tool_call_limit: '单轮工具调用上限',
    sequential_tool_round_limit: '连续工具轮次上限',
    application_directory: '应用目录',
    home_directory: '主目录',
    settings_file: '设置文件',
    skills_storage: '技能目录',
    mcp_servers_file: 'MCP 文件',
    user_memory_file: '记忆文件',
    sessions_directory: '会话目录',
    post_compact_active: '启用状态',
    checkpoint_message_id: 'Checkpoint 消息 ID',
    checkpoint_created_at: 'Checkpoint 创建时间',
    runtime_tool_count: '运行工具',
    restored_signal_counts: '恢复信号',
  };
  return labels[field] ?? field;
}

function boolLabel(value: boolean): string {
  return value ? t('common.yes', '是') : t('common.no', '否');
}

function runtimeGateReasonLabel(reason: string): string {
  switch (reason.trim()) {
    case 'awaiting_plan_approval':
      return '计划待批准，执行工具暂未开放';
    case 'plan_mode_recovery_inspection':
      return '计划恢复审阅中';
    case 'plan_mode_execution':
      return '计划已批准，执行工具开放';
    case 'plan_mode_planning_with_exit_allowed':
      return '计划草拟中，可退出计划模式';
    case 'plan_mode_planning_only':
      return '计划草拟中，仅规划工具开放';
    case 'mode_switch_requires_refresh':
      return '模式刚切换，需下一轮刷新';
    case 'chat_mode_no_tools':
      return '聊天模式，不开放工具';
    case 'chat_mode':
      return '聊天模式，工具目录同步';
    case 'model_no_tool_support':
      return '当前协议不支持工具调用';
    case 'no_runtime_snapshot':
      return '暂无运行时快照';
    default:
      return reason.trim() || '未记录原因';
  }
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
  const { closing, requestClose } = useDialogExitMotion(onClose);
  useEffect(() => {
    if (closing) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closing, requestClose]);

  const stats = asRecord(session.statistics);
  const metadata = asRecord(session.metadata);
  const environment = asRecord(session.environment);
  const lastPromptMetadata = asRecord(session.last_prompt_metadata);
  const latestCompressionPoint = asRecord(session.latest_compression_point);
  const latestCompressionPointMetadata = asRecord(latestCompressionPoint['metadata']);
  const rehydration = asRecord(lastPromptMetadata['post_compact_rehydration']);
  const hasPromptMetadata = Object.keys(lastPromptMetadata).length > 0;
  const runtimeToolNames = asStringList(lastPromptMetadata['current_tool_names']);
  const runtimeNotices = asStringList(lastPromptMetadata['runtime_tool_catalog_notices']);
  const runtimeToolCount = Math.max(asInt(lastPromptMetadata['current_tool_count']), runtimeToolNames.length);
  const runtimeStale = lastPromptMetadata['runtime_tool_catalog_stale'] === true;
  const awaitingPlanApproval = lastPromptMetadata['awaiting_plan_approval'] === true || session.awaiting_plan_approval === true;
  const planRecoveryRequired = lastPromptMetadata['plan_mode_recovery_inspection_required'] === true || lastPromptMetadata['plan_recovery_required'] === true;
  const planExecutionApproved = lastPromptMetadata['plan_mode_execution_approved_for_send'] === true;
  const hasActivePlanState = Boolean(session.todo_items?.length) || Boolean((session.pending_plan ?? '').trim());
  let gateReason = String(lastPromptMetadata['runtime_tool_gate_reason'] ?? '').trim();
  if (!gateReason) {
    gateReason = awaitingPlanApproval
      ? 'awaiting_plan_approval'
      : session.mode !== 'plan'
        ? (hasPromptMetadata ? 'chat_mode' : 'no_runtime_snapshot')
        : planRecoveryRequired
          ? 'plan_mode_recovery_inspection'
          : planExecutionApproved
            ? 'plan_mode_execution'
            : hasActivePlanState
              ? 'plan_mode_planning_with_exit_allowed'
              : 'plan_mode_planning_only';
  }
  const runtimeModeLabel = session.mode !== 'plan'
    ? '聊天模式'
    : awaitingPlanApproval
      ? '计划待审'
      : planRecoveryRequired
        ? '计划审阅'
        : planExecutionApproved
          ? '计划执行'
          : hasActivePlanState
            ? '计划草拟'
            : '计划模式';
  const toolCatalogState = !hasPromptMetadata
    ? '暂无运行时快照'
    : runtimeStale
      ? '工具目录待刷新'
      : '工具目录已同步';
  const promptBudgetTokens = asInt(lastPromptMetadata['context_budget_estimated_prompt_tokens']);
  const contextStatus = String(lastPromptMetadata['context_budget_status'] ?? 'unknown').trim();
  const contextStatusLabel = contextStatus === 'critical'
    ? '危险'
    : contextStatus === 'auto_compact'
      ? '需压缩'
      : contextStatus === 'warning'
        ? '偏高'
        : contextStatus === 'ok'
          ? '正常'
          : '未知';
  const usagePercent = asInt(lastPromptMetadata['context_budget_usage_percent']);
  const usageValue = Math.max(0, Math.min(100, usagePercent));
  const sidecarPath = String(rehydration['session_memory_sidecar_path'] ?? '').trim();
  const sidecarPresent = rehydration['session_memory_sidecar_present'] === true;
  const compressionRestored = latestCompressionPointMetadata['restored_from_compact_memory_sidecar'] === true;
  const hasCompressionPoint = Boolean(String(latestCompressionPoint['id'] ?? '').trim());
  const sidecarStatus = !hasCompressionPoint
    ? '未生成'
    : compressionRestored
      ? '已恢复'
      : sidecarPresent
        ? '已登记'
        : '等待下次 Prompt 刷新';
  const visibleMetadataEntries = Object.entries(metadata).filter(([key]) => {
    if (session.template_id === 'hardness_engineering' && key === 'hardness_config') return false;
    if (session.template_id === 'programming_expert' && key === 'programming_expert_config') return false;
    return true;
  });
  const planHistory = [...(session.plan_history ?? [])].reverse();
  const todos = session.todo_items ?? [];
  const recentErrors = session.recent_errors ?? [];

  const sectionStyle = {
    background: 'var(--m3-surface-container-low)',
    borderRadius: '20px',
  };

  const SummaryTile = ({ label, value }: { label: string; value: string }) => (
    <div class="p-3.5" style={{ ...sectionStyle, width: '188px' }}>
      <div class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</div>
      <div class="mt-1.5 text-xl font-extrabold tabular-nums">{value}</div>
    </div>
  );
  const Chip = ({ label }: { label: string }) => (
    <span
      class="inline-flex rounded-full px-2.5 py-1.5 text-xs font-bold"
      style={{ background: 'var(--m3-surface-container-highest)', color: 'var(--m3-on-surface)' }}
    >
      {label}
    </span>
  );
  const EntryRow = ({ label, value }: { label: string; value: ComponentChildren }) => (
    <div class="mb-2.5 min-w-0">
      <div class="text-xs font-bold" style={{ color: 'var(--m3-on-surface-variant)' }}>{label}</div>
      <div class="mt-1 text-sm leading-relaxed break-words whitespace-pre-wrap select-text">{value}</div>
    </div>
  );
  const Section = ({ title, children }: { title: string; children: ComponentChildren }) => (
    <section class="p-4" style={sectionStyle}>
      <h3 class="text-base font-extrabold mb-3.5">{title}</h3>
      {children}
    </section>
  );
  const JsonPanel = ({ content }: { content: unknown }) => (
    <pre
      class="text-xs overflow-auto rounded-m3-sm p-3 whitespace-pre-wrap max-h-72"
      style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}
    >
      {JSON.stringify(content ?? {}, null, 2)}
    </pre>
  );

  const renderProgrammingConfig = () => {
    const config = asRecord(metadata['programming_expert_config']);
    return (
      <Section title="编程专家配置">
        {Object.keys(config).length === 0 ? (
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>配置数据尚未写入会话元数据。</p>
        ) : (
          <>
            <EntryRow label="项目根目录" value={metadataValue(config['project_root'])} />
            <EntryRow label="项目语言" value={metadataValue(config['language'] ?? 'mixed')} />
            <EntryRow label="SDK 路径" value={metadataValue(config['sdk_path'])} />
            <EntryRow label="LSP 路径" value={metadataValue(config['lsp_path'])} />
          </>
        )}
      </Section>
    );
  };

  const renderHardnessConfig = () => {
    const config = asRecord(metadata['hardness_config']);
    const roleKeys = ['profiler', 'reader', 'planner', 'implementer', 'reviewer'];
    return (
      <Section title="Hardness Engineering 配置">
        {Object.keys(config).length === 0 ? (
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>配置数据尚未写入会话元数据（该会话可能创建于功能推出之前）。</p>
        ) : (
          <>
            <EntryRow label="任务描述" value={metadataValue(config['task'])} />
            <EntryRow label="工作目录" value={metadataValue(config['working_directory'])} />
            <EntryRow label="持久化目录" value={metadataValue(config['persistence_directory'])} />
            <EntryRow label="首次运行" value={config['first_run'] === true ? '是（含探档阶段）' : '否（增量运行）'} />
            <div class="mt-3 mb-2 text-sm font-extrabold">角色配置</div>
            {roleKeys.map((key) => {
              const role = asRecord(config[key]);
              const cli = String(role['cli_name'] ?? '').trim();
              const model = String(role['model_id'] ?? '').trim();
              return <EntryRow key={key} label={key} value={cli || model ? `${cli || '-'} · ${model || '-'}` : '未配置'} />;
            })}
          </>
        )}
      </Section>
    );
  };

  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'color-mix(in srgb, var(--m3-inverse-surface) 44%, transparent)', zIndex: 2600 }}
      onClick={requestClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} rounded-m3-lg p-5 w-full flex flex-col`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline-variant)',
          maxWidth: '860px',
          maxHeight: '84vh',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="flex flex-wrap items-start justify-between gap-3 mb-4">
          <div class="min-w-0">
            <h2 class="text-2xl font-extrabold truncate">{t('metadata.currentTitle', '当前会话元数据')}</h2>
            <p class="text-sm mt-2 truncate" style={{ color: 'var(--m3-on-surface-variant)' }}>{session.title}</p>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-2 flex-none">
            <button
              type="button"
              class="oh-tap-press oh-dialog-action-button"
              style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline)' }}
              onClick={() => void copyJsonWithFeedback(JSON.stringify({ session, runtime: detail.runtime, loaded_messages: messages.length }, null, 2))}
            >
              <ComposerIcon name="copy" size={14} />
              <span>{t('common.copy', '复制')}</span>
            </button>
            <button
              type="button"
              class="oh-tap-press oh-dialog-action-button"
              style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
              onClick={requestClose}
            >
              <ComposerIcon name="close" size={14} />
              <span>{t('common.close', '关闭')}</span>
            </button>
          </div>
        </header>
        <div class="flex flex-wrap gap-3 mb-4">
          <SummaryTile label="消息总数" value={`${stats.total_message_count ?? session.message_count ?? 0}`} />
          <SummaryTile label="Prompt 构建" value={`${stats.prompt_build_count ?? 0}`} />
          <SummaryTile label="压缩次数" value={`${stats.compression_run_count ?? 0}`} />
          <SummaryTile label="总 Token" value={`${stats.total_tokens ?? session.total_tokens ?? 0}`} />
          <SummaryTile label="当前模式" value={runtimeModeLabel} />
          <SummaryTile label="运行工具" value={!hasPromptMetadata || runtimeStale ? '待刷新' : `${runtimeToolCount}`} />
        </div>
        <div class="overflow-auto pr-1 flex-1 min-h-0">
          <div class="flex flex-col gap-4">
            <Section title="会话概览">
              <EntryRow label={metadataFieldLabel('session_id')} value={session.id} />
              <EntryRow label={metadataFieldLabel('template')} value={`${session.template_name || session.template_id} · v${session.template_internal_version ?? '—'}`} />
              <EntryRow label={metadataFieldLabel('created_at')} value={formatDialogDate(session.created_at)} />
              <EntryRow label={metadataFieldLabel('updated_at')} value={formatDialogDate(session.updated_at)} />
              <EntryRow label={metadataFieldLabel('last_model')} value={session.last_used_model_label || session.last_used_model_id || '—'} />
              <EntryRow label={metadataFieldLabel('compression_checkpoint')} value={session.latest_compression_checkpoint_message_id || '—'} />
              <EntryRow label={metadataFieldLabel('latest_compression_at')} value={formatDialogDate(session.latest_compression_at)} />
            </Section>
            {session.template_id === 'hardness_engineering' ? renderHardnessConfig() : null}
            {session.template_id === 'programming_expert' ? renderProgrammingConfig() : null}
            {visibleMetadataEntries.length > 0 ? (
              <Section title="扩展元数据">
                {visibleMetadataEntries.map(([key, value]) => <EntryRow key={key} label={key} value={metadataValue(value)} />)}
              </Section>
            ) : null}
            <Section title="统计信息">
              <div class="flex flex-wrap gap-2 mb-3">
                <Chip label={`用户 ${stats.user_message_count ?? 0}`} />
                <Chip label={`助手 ${stats.assistant_message_count ?? 0}`} />
                <Chip label={`工具 ${stats.tool_message_count ?? 0}`} />
                <Chip label={`MCP ${stats.mcp_message_count ?? 0}`} />
                <Chip label={`技能 ${stats.skill_message_count ?? 0}`} />
                <Chip label={`压缩 ${stats.compression_point_count ?? 0}`} />
              </div>
              <EntryRow label={metadataFieldLabel('total_input_characters')} value={`${stats.total_input_characters ?? 0}`} />
              <EntryRow label={metadataFieldLabel('total_output_characters')} value={`${stats.total_output_characters ?? 0}`} />
              <EntryRow label={metadataFieldLabel('total_prompt_characters')} value={`${stats.total_prompt_characters ?? 0}`} />
              <EntryRow label={metadataFieldLabel('last_prompt_system_message_count')} value={`${stats.last_prompt_system_message_count ?? 0}`} />
              <EntryRow label={metadataFieldLabel('last_prompt_history_message_count')} value={`${stats.last_prompt_history_message_count ?? 0}`} />
            </Section>
            {promptBudgetTokens > 0 ? (
              <Section title="上下文预算">
                <div class="flex items-center gap-3 mb-3">
                  <div class="h-2 flex-1 rounded-full overflow-hidden" style={{ background: 'var(--m3-surface-container-highest)' }}>
                    <div class="h-full rounded-full" style={{ width: `${usageValue}%`, background: contextStatus === 'critical' ? 'var(--m3-error)' : 'var(--m3-primary)' }} />
                  </div>
                  <Chip label={contextStatusLabel} />
                </div>
                <EntryRow label={metadataFieldLabel('context_budget_estimated_prompt_tokens')} value={`${promptBudgetTokens}`} />
                <EntryRow label={metadataFieldLabel('context_budget_model_max_tokens')} value={metadataValue(lastPromptMetadata['context_budget_model_max_tokens'])} />
                <EntryRow label={metadataFieldLabel('context_budget_effective_window_tokens')} value={metadataValue(lastPromptMetadata['context_budget_effective_window_tokens'])} />
                <EntryRow label={metadataFieldLabel('context_budget_auto_compact_threshold_tokens')} value={metadataValue(lastPromptMetadata['context_budget_auto_compact_threshold_tokens'])} />
                <EntryRow label={metadataFieldLabel('context_budget_remaining_tokens')} value={metadataValue(lastPromptMetadata['context_budget_remaining_tokens'])} />
                <EntryRow label={metadataFieldLabel('context_budget_percent_left')} value={`${asInt(lastPromptMetadata['context_budget_percent_left'])}%`} />
                <EntryRow label={metadataFieldLabel('context_budget_usage_percent')} value={`${usagePercent}%`} />
              </Section>
            ) : null}
            {Object.keys(rehydration).length > 0 ? (
              <Section title="压缩后上下文恢复">
                <EntryRow label={metadataFieldLabel('post_compact_active')} value={rehydration['active'] === true ? '启用' : '未启用'} />
                <EntryRow label={metadataFieldLabel('checkpoint_message_id')} value={metadataValue(rehydration['checkpoint_message_id'])} />
                <EntryRow label={metadataFieldLabel('checkpoint_created_at')} value={metadataValue(rehydration['checkpoint_created_at'])} />
                <EntryRow label={metadataFieldLabel('runtime_tool_count')} value={`${asInt(rehydration['runtime_tool_count'])} (${asInt(rehydration['builtin_tool_count'])} builtin, ${asInt(rehydration['skill_tool_count'])} skill, ${asInt(rehydration['mcp_tool_count'])} MCP)`} />
                <EntryRow label={metadataFieldLabel('restored_signal_counts')} value={`read_files=${asInt(rehydration['recent_read_file_count'])}, skills=${asInt(rehydration['invoked_skill_count'])}, mcp_instructions=${asInt(rehydration['mcp_server_instruction_count'])}, session_hooks=${asInt(rehydration['session_start_hook_count'])}, agent_results=${asInt(rehydration['agent_result_count'])}, deferred_tools=${asInt(rehydration['deferred_builtin_tool_count'])}, agent_types=${asInt(rehydration['agent_type_count'])}`} />
                <div class="mt-2 mb-2 text-sm font-extrabold">恢复通道</div>
                <div class="flex flex-wrap gap-2">
                  {asStringList(rehydration['restored_channels']).length === 0 ? <span class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>暂无恢复通道。</span> : asStringList(rehydration['restored_channels']).map((item) => <Chip key={item} label={item} />)}
                </div>
              </Section>
            ) : null}
            {hasCompressionPoint || Object.keys(rehydration).length > 0 ? (
              <Section title="压缩记忆 Sidecar">
                <EntryRow label={metadataFieldLabel('compact_memory_sidecar_status')} value={sidecarStatus} />
                <EntryRow label={metadataFieldLabel('compact_memory_checkpoint_id')} value={metadataValue(latestCompressionPoint['id'])} />
                <EntryRow label={metadataFieldLabel('compact_memory_checkpoint_characters')} value={metadataValue(latestCompressionPoint['character_count'])} />
                <EntryRow label={metadataFieldLabel('compact_memory_restored_from_sidecar')} value={boolLabel(compressionRestored)} />
                <EntryRow label={metadataFieldLabel('compact_memory_sidecar_path')} value={sidecarPath || '—'} />
              </Section>
            ) : null}
            <Section title="环境">
              <EntryRow label={metadataFieldLabel('locale_tag')} value={metadataValue(environment['locale_tag'])} />
              <EntryRow label={metadataFieldLabel('platform')} value={metadataValue(environment['platform'])} />
              <EntryRow label={metadataFieldLabel('app_version')} value={`${environment['app_version'] ?? '—'} (${environment['app_build_number'] ?? '—'})`} />
              <EntryRow label={metadataFieldLabel('compression_threshold_chars')} value={metadataValue(environment['compression_threshold_chars'])} />
              <EntryRow label={metadataFieldLabel('single_round_tool_call_limit')} value={metadataValue(environment['single_round_tool_call_limit'])} />
              <EntryRow label={metadataFieldLabel('sequential_tool_round_limit')} value={metadataValue(environment['sequential_tool_round_limit'])} />
              <EntryRow label={metadataFieldLabel('application_directory')} value={metadataValue(environment['application_directory'])} />
              <EntryRow label={metadataFieldLabel('home_directory')} value={metadataValue(environment['home_directory'])} />
              <EntryRow label={metadataFieldLabel('settings_file')} value={metadataValue(environment['settings_file_path'])} />
              <EntryRow label={metadataFieldLabel('skills_storage')} value={metadataValue(environment['skills_storage_path'])} />
              <EntryRow label={metadataFieldLabel('mcp_servers_file')} value={metadataValue(environment['mcp_servers_file_path'])} />
              <EntryRow label={metadataFieldLabel('user_memory_file')} value={metadataValue(environment['user_memory_file_path'])} />
              <EntryRow label={metadataFieldLabel('sessions_directory')} value={metadataValue(environment['sessions_directory_path'])} />
            </Section>
            <Section title="命令策略">
              {!hasPromptMetadata ? (
                <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>Prompt 元数据尚不可用。</p>
              ) : (
                <>
                  <EntryRow label="写命令确认" value={lastPromptMetadata['write_command_confirmation_enabled'] === true ? '必需' : '不需要'} />
                  <EntryRow label="允许规则" value={`${asInt(lastPromptMetadata['allow_command_rule_count'])}`} />
                  <div class="flex flex-wrap gap-2">
                    {asArray(lastPromptMetadata['allow_command_rules']).length === 0 ? <span class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>暂无显式允许命令规则。</span> : asArray(lastPromptMetadata['allow_command_rules']).map((raw, index) => {
                      const rule = asRecord(raw);
                      const pattern = String(rule['pattern'] ?? '').trim();
                      const mode = String(rule['match_mode'] ?? '').trim();
                      return pattern ? <Chip key={`${pattern}-${index}`} label={`${mode ? `${mode}: ` : ''}${pattern}`} /> : null;
                    })}
                  </div>
                </>
              )}
            </Section>
            <Section title="运行编排">
              <EntryRow label="状态来源" value={hasPromptMetadata ? '最近持久化运行时快照' : '暂无快照'} />
              <EntryRow label="模式" value={runtimeModeLabel} />
              <EntryRow label="工具目录状态" value={toolCatalogState} />
              <EntryRow label="门控原因" value={runtimeGateReasonLabel(gateReason)} />
              <EntryRow label="运行工具数" value={hasPromptMetadata && !runtimeStale ? `${runtimeToolCount}` : '下轮刷新'} />
              {runtimeNotices.length > 0 ? <><div class="mt-3 mb-2 text-sm font-extrabold">运行时提示</div><div class="flex flex-wrap gap-2">{runtimeNotices.map((item) => <Chip key={item} label={item} />)}</div></> : null}
              {runtimeToolNames.length > 0 && !runtimeStale ? <><div class="mt-3 mb-2 text-sm font-extrabold">当前运行工具</div><div class="flex flex-wrap gap-2">{runtimeToolNames.map((item) => <Chip key={item} label={item} />)}</div></> : null}
            </Section>
            <Section title="任务跟踪">
              <EntryRow label="当前 Todos" value={`${todos.length}`} />
              <EntryRow label="计划记录" value={`${planHistory.length}`} />
              <EntryRow label="TodoWrite 提醒" value={hasPromptMetadata ? (lastPromptMetadata['todo_write_recommended'] === true ? '已触发' : '未触发') : '不可用'} />
              {String(lastPromptMetadata['todo_write_reason'] ?? '').trim() ? <EntryRow label="提醒原因" value={String(lastPromptMetadata['todo_write_reason'])} /> : null}
              {todos.length > 0 ? <div class="flex flex-wrap gap-2">{todos.map((todo) => <Chip key={todo.id} label={`${todo.status ? `[${todo.status}] ` : ''}${todo.id ? `${todo.id}: ` : ''}${todo.content}`} />)}</div> : null}
              {planHistory.length > 0 ? <div class="mt-4 flex flex-col gap-2">{planHistory.map((plan, index) => <div key={plan.id || index} class="rounded-m3-sm p-3" style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}><div class="text-sm font-bold">计划 #{planHistory.length - index} · {plan.status || '—'}</div><div class="mt-1 text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>{formatDialogDate(plan.created_at)} → {formatDialogDate(plan.updated_at)}</div>{plan.plan ? <div class="mt-2 text-sm whitespace-pre-wrap">{plan.plan}</div> : null}{plan.steps?.length ? <div class="mt-2 flex flex-wrap gap-2">{plan.steps.map((step) => <Chip key={step.id} label={`${step.status ? `[${step.status}] ` : ''}${step.id}: ${step.content}`} />)}</div> : null}</div>)}</div> : null}
            </Section>
            <Section title="最近错误">
              {recentErrors.length === 0 ? <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>暂无会话错误。</p> : recentErrors.map((error) => <div key={error.id} class="rounded-m3-sm p-3 mb-2" style={{ background: 'var(--m3-surface)', border: '1px solid var(--m3-outline-variant)' }}><div class="text-sm font-bold" style={{ color: 'var(--m3-error)' }}>{error.stage || 'error'} · {formatDialogDate(error.created_at)}</div><div class="mt-2 text-sm whitespace-pre-wrap">{error.message}</div>{error.detail ? <pre class="mt-2 text-xs whitespace-pre-wrap overflow-auto">{error.detail}</pre> : null}</div>)}
            </Section>
            <Section title="最近加载消息">
              <EntryRow label="已加载" value={`${messages.length}`} />
              <EntryRow label="最新角色" value={messages[messages.length - 1]?.role || '—'} />
              <EntryRow label="最新类型" value={messages[messages.length - 1]?.kind || '—'} />
              <EntryRow label="最新 ID" value={messages[messages.length - 1]?.id || '—'} />
            </Section>
            <Section title="Last Prompt Metadata">
              <JsonPanel content={lastPromptMetadata} />
            </Section>
          </div>
        </div>
        <footer class="flex justify-end pt-4">
          <button
            type="button"
            class="oh-tap-press px-5 py-2 rounded-m3-sm text-sm font-bold"
            style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
            onClick={requestClose}
          >
            {t('common.close', '关闭')}
          </button>
        </footer>
      </div>
    </div>
  );
  return <OverlayPortal>{node}</OverlayPortal>;
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
  const { closing, requestClose } = useDialogExitMotion(onClose);
  useEffect(() => {
    if (closing) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closing, requestClose]);
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
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{ background: 'rgba(0,0,0,0.40)', zIndex: 2600 }}
      onClick={requestClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} rounded-m3-md p-4 max-w-3xl w-full flex flex-col`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-3)',
          border: '1px solid var(--m3-outline)',
          maxHeight: '84vh',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <header class="flex flex-wrap items-center justify-between gap-3 mb-3">
          <div class="min-w-0">
            <h2 class="text-base font-semibold truncate">{t('topbar.audit', '会话审计')} · {session.title}</h2>
            <p class="text-xs mt-0.5" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {session.id}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-2 flex-none">
            <button
              type="button"
              class="oh-tap-press oh-dialog-action-button"
              style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline)' }}
              onClick={() => void copyJsonWithFeedback(json)}
            >
              <ComposerIcon name="copy" size={14} />
              <span>{t('common.copy', '复制')}</span>
            </button>
            <button
              type="button"
              class="oh-tap-press oh-dialog-action-button"
              style={{ color: 'var(--m3-on-surface-variant)', background: 'transparent' }}
              onClick={requestClose}
            >
              <ComposerIcon name="close" size={14} />
              <span>{t('common.close', '关闭')}</span>
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
  return <OverlayPortal>{node}</OverlayPortal>;
}
