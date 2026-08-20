// 按 AiSessionMessage.kind 分发到不同视觉模板，与 OpenHand APP 端
// `_home_transcript.dart` / `tool_call_card.dart` / `reasoning_card.dart` 等
// 视觉语义对齐。
//
// 复刻范围（基于服务端 _messageJson 已经导出的字段）：
// - user / assistant / system / tool / reasoning
// - tool_call（解析 ```json``` 入参或纯文本）
// - mcp / skill / hook / self_learning / file_mutation_summary / status / compression_point
//
// Web 端不执行撤销/重做等本地文件 ledger 操作，只做只读审阅展示。

import { KNOWLEDGE_BASE_MESSAGE_METADATA_KEY, type SessionMessage, type SessionMessageFeedback } from '../api/sessions';
import {
  KNOWLEDGE_VECTOR_DEFAULT_MAX_POINTS,
  fetchKnowledgeHitDetail,
  fetchKnowledgeVectorDistribution,
  type KnowledgeChunkDto,
  type KnowledgeSourceDto,
} from '../api/knowledge';
import type { ComponentChildren } from 'preact';
import { t, tDuration, tNumber } from '../i18n';
import { Markdown, looksLikeRenderableHtml, openHtmlInNewTab } from './Markdown';
import { MediaGeneratingPlaceholderTransition, type MediaGenerationMode } from './MediaGeneratingPlaceholder';
import { MediaPreviewDialog, MessageMedia, messageHasMultimedia, stripCollectedNetworkMedia } from './MessageMedia';
import type { MediaItem } from './MessageMedia';
import { MessageToolMeta } from './MessageToolMeta';
import { ToolResultBody } from './ToolResultBody';
import {
  DialogCloseButton,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import { memo } from 'preact/compat';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { showSnackbar } from './Snackbar';
import { copyTextToClipboard } from '../utils/clipboard';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { useMessageContentFormat, type MessageContentFormat } from '../hooks/useMessageContentFormat';
import {
  useStreamingReveal,
  useStreamingStagedText,
} from '../hooks/useStreamingReveal';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import {
  getDialogEnterDurationMs,
  getDialogExitDurationMs,
  getDialogMotionCurve,
  getDialogMotionExitCurve,
} from '../hooks/useDialogMotionSettings';
import { useStickyBottom } from '../hooks/useStickyBottom';
import { useDelayedVisibility } from '../hooks/useDelayedVisibility';
import { useDelayedFalse } from '../hooks/useDelayedFalse';
import { useTimeoutController } from '../hooks/useTimeoutController';
import { boundedFnv1aHashBase36 } from '../shared/util/hash';
import {
  knowledgeBaseHitTokenEstimateTotal,
  knowledgeBaseResultsUsedByAnswer,
} from '../shared/util/knowledge';
import { messageFeedbackValue } from '../shared/util/message_feedback';
import { isTerminalToolExecutionStatus } from '../shared/util/session_transcript_messages';
import {
  clampNumber,
  strictPositiveIntegerFromUnknown,
  strictPositiveNumberFromUnknown,
} from '../shared/util/number';
import { textExceedsLength, truncateEndText } from '../shared/util/text';
import {
  booleanFromUnknown,
  finiteNumberOrNullFromUnknown,
  nonNegativeIntegerFromUnknown,
  parseJsonRecordSafely,
  parseJsonSafely,
  recordOrNullFromUnknown,
  strictStringFromUnknown,
  stringifyJsonSafely,
  stringFromUnknown,
  stringListFromUnknown,
} from '../shared/util/value';
import {
  isTranscriptScrollActive,
  scheduleAfterTranscriptScrollSettles,
} from '../shared/ui/transcript_scroll_activity';
import { STREAMING_TURN_IDLE_DEBOUNCE_MS } from '../shared/ui/streaming_turn_timing';
import { messageBubbleMaxWidth } from '../shared/ui/layout';
import { MediaKindIcon } from './MediaKindIcon';
import { svgIconProps } from '../shared/ui/svg_icon';
import { formatLocalDateTimeMinute } from '../shared/util/date_time';

const TOOL_LIVE_ELAPSED_TICK_MS = 1000;

function isLiveToolExecutionStatus(status: string): boolean {
  const s = status.toLowerCase();
  return s === 'running' || s === 'pending' || s === 'in_progress';
}

function timestampMsFromUnknown(value: unknown): number | null {
  const raw = stringFromUnknown(value).trim();
  if (!raw) return null;
  const parsed = Date.parse(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatCompactDurationMs(milliseconds: number): string {
  const safeMs = Math.max(0, Math.round(milliseconds));
  const totalSeconds = Math.floor(safeMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

function useToolLiveElapsedMs(
  metadata: Record<string, unknown>,
  status: string,
  messageCreatedAt: string,
): number | null {
  const storedElapsedMs = finiteNumberOrNullFromUnknown(
    metadata['tool_execution_elapsed_ms'] ?? metadata['tool_execution_duration_ms'],
  );
  const startedAtMs =
    timestampMsFromUnknown(metadata['tool_execution_started_at']) ??
    timestampMsFromUnknown(messageCreatedAt);
  const finishedAtMs = timestampMsFromUnknown(metadata['tool_execution_finished_at']);
  const live = isLiveToolExecutionStatus(status) && startedAtMs != null;
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    if (!live) return undefined;
    setNowMs(Date.now());
    const timer = window.setInterval(() => {
      setNowMs(Date.now());
    }, TOOL_LIVE_ELAPSED_TICK_MS);
    return () => window.clearInterval(timer);
  }, [live, startedAtMs]);

  const safeStored = storedElapsedMs == null ? null : Math.max(0, storedElapsedMs);
  if (live && startedAtMs != null) {
    return Math.max(safeStored ?? 0, Math.max(0, nowMs - startedAtMs));
  }
  if (safeStored != null) return safeStored;
  if (startedAtMs != null && finishedAtMs != null) {
    return Math.max(0, finishedAtMs - startedAtMs);
  }
  return null;
}

/// 活跃工具的耗时 chip 独立成组件：1s tick 的 setState 只重渲染这个小
/// chip，不再拖着整张工具卡（含入参 pretty-print、输出分行判定）每秒
/// 全量重渲染。
function ToolLiveElapsedChip({
  metadata,
  status,
  messageCreatedAt,
}: {
  metadata: Record<string, unknown>;
  status: string;
  messageCreatedAt: string;
}) {
  const elapsedMs = useToolLiveElapsedMs(metadata, status, messageCreatedAt);
  if (elapsedMs == null) return null;
  return (
    <MetaChip
      label={`${t('detail.tool.elapsed', '耗时')}: ${formatCompactDurationMs(elapsedMs)}`}
    />
  );
}

async function copyPathWithFeedback(path: string): Promise<void> {
  const ok = await copyTextToClipboard(path);
  showSnackbar(ok
    ? t('detail.fileMutation.copyPath.ok', '已复制文件路径')
    : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
}

function roleLabel(role: string): string {
  switch (role) {
    case 'user': return t('detail.role.user', '用户');
    case 'assistant': return t('detail.role.assistant', '助手');
    case 'system': return t('detail.role.system', '系统');
    case 'tool': return t('detail.role.tool', '工具');
    default: return role;
  }
}

function resolveMessageContentFormat(raw: unknown, fallback: MessageContentFormat): MessageContentFormat {
  return raw === 'markdown' || raw === 'plain_text' || raw === 'html'
    ? raw
    : fallback;
}

interface KindStyle {
  background: string;
  color: string;
  border?: string;
  shadow?: string;
  label: string;
  icon: MessageIconName;
  /// 标题区是否额外带图标徽章。
  badge?: boolean;
  /// pre-wrap 文字是否走 mono 字体（工具/json 适合）。
  mono?: boolean;
  /// 折叠超长内容（thinking / tool stdout 等）。
  collapsible?: boolean;
}

type MessageIconName =
  | 'image'
  | 'video'
  | 'audio'
  | 'deepResearch'
  | 'attachmentFile'
  | 'reasoning'
  | 'toolCall'
  | 'tool'
  | 'mcp'
  | 'skill'
  | 'hook'
  | 'learn'
  | 'fileMutation'
  | 'status'
  | 'compression'
  | 'goal'
  | 'knowledge'
  | 'user'
  | 'assistant'
  | 'copy'
  | 'edit'
  | 'audit'
  | 'fork'
  | 'code'
  | 'codeOff'
  | 'trash'
  | 'cascade'
  | 'close'
  | 'chevronDown'
  | 'chevronUp'
  | 'write'
  | 'delete'
  | 'mutate'
  | 'globe'
  | 'model'
  | 'clock'
  | 'speech'
  | 'stop'
  | 'translate'
  | 'thumbUp'
  | 'thumbDown'
  | 'refresh';

const MESSAGE_REASONING_BACKGROUND = '#18181B';
const MESSAGE_REASONING_TEXT = '#F7F7FA';
const MESSAGE_REASONING_BORDER =
  '1px solid color-mix(in srgb, var(--m3-inverse-on-surface) 18%, transparent)';
const MESSAGE_REASONING_SHADOW =
  'var(--m3-elev-2), 0 16px 38px -24px rgba(0, 0, 0, 0.72)';

function MessageIcon({ name, size = 16 }: { name: MessageIconName; size?: number }) {
  const common = svgIconProps({ size, strokeWidth: 1.9 });
  switch (name) {
    // 媒体类别图标与消息里的媒体块共用一份，避免同一种附件在两处长得不一样。
    case 'image':
    case 'video':
    case 'audio':
      return <MediaKindIcon kind={name} size={size} />;
    case 'deepResearch':
      return <svg {...common}><circle cx="11" cy="11" r="6" /><path d="m16 16 4 4" /><path d="M8.5 11h5M11 8.5v5" /></svg>;
    case 'attachmentFile':
      return <svg {...common}><path d="M7 3h7l3 3v15H7z" /><path d="M14 3v4h4" /></svg>;
    case 'reasoning':
      return <svg {...common}><path d="M9 18h6" /><path d="M10 22h4" /><path d="M8.3 14.8A6 6 0 1 1 15.7 14c-.8.7-1.2 1.4-1.2 2H9.5c0-.7-.4-1.2-1.2-1.8z" /></svg>;
    case 'toolCall':
      return <svg {...common}><path d="m8 8-4 4 4 4" /><path d="m16 8 4 4-4 4" /><path d="m14 5-4 14" /></svg>;
    case 'tool':
      return <svg {...common}><path d="M14.7 6.3a4 4 0 0 0-5 5L4 17v3h3l5.7-5.7a4 4 0 0 0 5-5l-2.4 2.4-2.9-2.9z" /></svg>;
    case 'mcp':
      return <svg {...common}><circle cx="6" cy="12" r="2.4" /><circle cx="18" cy="7" r="2.4" /><circle cx="18" cy="17" r="2.4" /><path d="M8.2 11 15.8 8M8.2 13l7.6 3" /></svg>;
    case 'skill':
      return <svg {...common}><path d="m12 3 1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7z" /><path d="M19 16v4M17 18h4" /></svg>;
    case 'hook':
      return <svg {...common}><path d="M7 8a4 4 0 0 1 4-4h2" /><path d="M17 16a4 4 0 0 1-4 4h-2" /><path d="m16 4 4 4-4 4" /><path d="m8 12-4 4 4 4" /></svg>;
    case 'learn':
      return <svg {...common}><path d="M4 12a8 8 0 0 1 13.4-5.9" /><path d="M17 3v4h-4" /><path d="M7 21v-4h4" /><path d="M20 12a8 8 0 0 1-13.4 5.9" /></svg>;
    case 'fileMutation':
      return <svg {...common}><path d="M7 3h6l4 4v14H7z" /><path d="M13 3v5h5" /><path d="M10 14h4M12 12v4" /></svg>;
    case 'status':
      return <svg {...common}><circle cx="12" cy="12" r="8" /><path d="M12 8h.01M11 12h1v4h1" /></svg>;
    case 'compression':
      return <svg {...common}><path d="M6 4h12v5H6z" /><path d="M8 9v11h8V9" /><path d="m9 14 3 3 3-3" /></svg>;
    case 'goal':
      return <svg {...common}><circle cx="12" cy="12" r="7" /><circle cx="12" cy="12" r="3" /><path d="M12 3v3M12 18v3M3 12h3M18 12h3" /></svg>;
    case 'knowledge':
      return <svg {...common}><path d="M5 5.8A2.8 2.8 0 0 1 7.8 3H19v15H8a3 3 0 0 0-3 3z" /><path d="M5 5.8V21" /><path d="M9 7h6M9 11h7M9 15h5" /></svg>;
    case 'user':
      return <svg {...common}><circle cx="12" cy="8" r="4" /><path d="M5 21a7 7 0 0 1 14 0" /></svg>;
    case 'assistant':
      return <svg {...common}><rect x="6" y="7" width="12" height="10" rx="3" /><path d="M9 3v4M15 3v4M9 12h.01M15 12h.01M10 17v2h4v-2" /></svg>;
    case 'copy':
      return <svg {...common}><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M5 15V7a2 2 0 0 1 2-2h8" /></svg>;
    case 'edit':
      return <svg {...common}><path d="M4 20h4.4L19 9.4a2.1 2.1 0 0 0-3-3L5.4 17H4z" /><path d="m14.8 7.6 1.6 1.6" /></svg>;
    case 'audit':
      return <svg {...common}><path d="M9 4h6l1 2h2v14H6V6h2z" /><path d="M9 12h6M9 16h4" /></svg>;
    case 'fork':
      return <svg {...common}><path d="M4 7h4c3.5 0 5 5 8.2 5H20" /><path d="M4 17h4c2.2 0 3.8-2 5.4-3.4" /><path d="m17 9 3 3-3 3" /></svg>;
    case 'trash':
      return <svg {...common}><path d="M4 7h16" /><path d="M10 11v6M14 11v6" /><path d="M6 7l1 14h10l1-14" /><path d="M9 7V4h6v3" /></svg>;
    case 'cascade':
      return <svg {...common}><path d="M5 6h14" /><path d="M8 12h8" /><path d="M10 18h4" /><path d="M18 6v5a7 7 0 0 1-7 7" /></svg>;
    case 'close':
      return <svg {...common}><path d="M7 7l10 10M17 7 7 17" /></svg>;
    case 'chevronDown':
      return <svg {...common}><path d="m6 9 6 6 6-6" /></svg>;
    case 'chevronUp':
      return <svg {...common}><path d="m18 15-6-6-6 6" /></svg>;
    case 'write':
      return <svg {...common}><path d="M12 5v14M5 12h14" /></svg>;
    case 'delete':
      return <svg {...common}><path d="M5 12h14" /></svg>;
    case 'mutate':
      return <svg {...common}><path d="M7 7h10v10H7z" /><path d="M4 12h16M12 4v16" /></svg>;
    case 'code':
      return <svg {...common}><path d="m8 8-4 4 4 4" /><path d="m16 8 4 4-4 4" /></svg>;
    case 'codeOff':
      return <svg {...common}><path d="m8 8-4 4 4 4" /><path d="m16 8 4 4-4 4" /><path d="m4 4 16 16" /></svg>;
    case 'globe':
      return <svg {...common}><circle cx="12" cy="12" r="9" /><path d="M3 12h18" /><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" /></svg>;
    case 'model':
      return <svg {...common}><rect x="5" y="5" width="14" height="14" rx="3" /><path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3" /><path d="M9 12h6" /></svg>;
    case 'clock':
      return <svg {...common}><circle cx="12" cy="12" r="8" /><path d="M12 7v5l3 2" /></svg>;
    case 'speech':
      return <svg {...common}><path d="M4 10v4h3l5 4V6l-5 4z" /><path d="M16 9.5a3.2 3.2 0 0 1 0 5" /><path d="M18.5 7a6.5 6.5 0 0 1 0 10" /></svg>;
    case 'stop':
      return <svg {...common}><rect x="7" y="7" width="10" height="10" rx="2" /><circle cx="12" cy="12" r="9" /></svg>;
    case 'translate':
      return <svg {...common}><path d="M4 5h8" /><path d="M8 3v2" /><path d="M10.5 5c-.7 2.7-2.3 5-5.5 6.5" /><path d="M5.5 8.5c1.1 1.5 2.4 2.6 4.2 3.4" /><path d="M13 21l4.5-10L22 21" /><path d="M14.4 18h6.2" /></svg>;
    case 'thumbUp':
      return <svg {...common}><path d="M7 10v10H4V10z" /><path d="M7 10 12 3c.8 0 1.6.6 1.6 1.7V8H19a2 2 0 0 1 2 2.3l-1.2 7A3 3 0 0 1 16.9 20H7" /></svg>;
    case 'thumbDown':
      return <svg {...common}><path d="M7 14V4H4v10z" /><path d="M7 14 12 21c.8 0 1.6-.6 1.6-1.7V16H19a2 2 0 0 0 2-2.3l-1.2-7A3 3 0 0 0 16.9 4H7" /></svg>;
    case 'refresh':
      return <svg {...common}><path d="M4 12a8 8 0 0 1 13.4-5.9" /><path d="M17 3v4h-4" /><path d="M20 12a8 8 0 0 1-13.4 5.9" /><path d="M7 21v-4h4" /></svg>;
  }
}

function styleForKind(kind: string, role: string): KindStyle {
  switch (kind) {
    case 'reasoning':
      return {
        background: MESSAGE_REASONING_BACKGROUND,
        color: MESSAGE_REASONING_TEXT,
        border: MESSAGE_REASONING_BORDER,
        shadow: MESSAGE_REASONING_SHADOW,
        label: t('detail.kind.reasoning', '思考'),
        icon: 'reasoning',
        badge: true,
        collapsible: true,
      };
    case 'tool_call':
      return {
        background: 'color-mix(in srgb, var(--m3-primary) 10%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-primary) 35%, transparent)',
        label: t('detail.kind.toolCall', '工具调用'),
        icon: 'toolCall',
        badge: true,
        mono: true,
      };
    case 'tool':
      return {
        background: 'var(--m3-surface)',
        color: 'var(--m3-on-surface)',
        border: '1px solid var(--m3-outline)',
        label: t('detail.kind.tool', '工具结果'),
        icon: 'tool',
        badge: true,
        mono: true,
        collapsible: true,
      };
    case 'mcp':
      return {
        background: 'color-mix(in srgb, var(--m3-primary-container) 70%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-primary) 34%, transparent)',
        label: t('detail.kind.mcp', 'MCP'),
        icon: 'mcp',
        badge: true,
        mono: true,
      };
    case 'skill':
      return {
        background: 'color-mix(in srgb, var(--m3-tertiary-container) 66%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-tertiary) 36%, transparent)',
        label: t('detail.kind.skill', '技能'),
        icon: 'skill',
        badge: true,
      };
    case 'hook':
      return {
        background: 'color-mix(in srgb, var(--m3-secondary-container) 66%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-secondary) 34%, transparent)',
        label: t('detail.kind.hook', 'Hook'),
        icon: 'hook',
        badge: true,
      };
    case 'self_learning':
      return {
        background: 'color-mix(in srgb, var(--m3-secondary-container) 76%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-secondary) 36%, transparent)',
        label: t('detail.kind.selfLearning', '自学习'),
        icon: 'learn',
        badge: true,
      };
    case 'file_mutation_summary':
      return {
        background: 'color-mix(in srgb, var(--m3-primary) 8%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid var(--m3-outline)',
        label: t('detail.kind.fileMutation', '本轮文件变动汇总'),
        icon: 'fileMutation',
        badge: true,
        mono: true,
      };
    case 'status':
      return {
        background: 'transparent',
        color: 'var(--m3-on-surface-variant)',
        border: '1px dashed var(--m3-outline)',
        label: t('detail.kind.status', '状态'),
        icon: 'status',
        badge: true,
      };
    case 'compression_point':
      return {
        background: 'transparent',
        color: 'var(--m3-on-surface-variant)',
        border: '1px dashed var(--m3-outline)',
        label: t('detail.kind.compression', '压缩点'),
        icon: 'compression',
        badge: true,
      };
    default:
      // user/assistant 等普通文本：按 role 区分 user 主色 / assistant 中性。
      if (role === 'user') {
        return {
          background: 'var(--m3-primary)',
          color: 'var(--m3-on-primary)',
          label: t('detail.role.user', '用户'),
          icon: 'user',
        };
      }
      return {
        background: 'color-mix(in srgb, var(--m3-surface-container-high) 88%, var(--m3-surface))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--oh-full-access) 24%, var(--m3-outline-variant))',
        label: t('detail.role.assistant', '助手'),
        icon: 'assistant',
      };
  }
}

interface MessageContextChip {
  key: string;
  label: string;
  icon?: MessageIconName;
  emoji?: string;
  tone?: 'knowledge';
  onClick?: () => void;
}

interface KnowledgeBaseCitationSource {
  key: string;
  label: string;
}

interface KnowledgeVectorDistributionPoint {
  id: string;
  kind: 'corpus' | 'match' | 'query';
  title: string;
  preview: string;
  x: number;
  y: number;
  z: number;
  score?: number;
  rerankScore?: number;
}

interface KnowledgeVectorDistributionData {
  algorithm: string;
  originalDimensions: number;
  sampledCount: number;
  hasMore: boolean;
  durationMs?: number;
  generatedAt?: string;
  points: KnowledgeVectorDistributionPoint[];
}

interface MachineExpertRequestViewModel {
  terminalApplication?: string;
  terminalLocation?: string;
  appleScriptTarget?: string;
  taskRequirement?: string;
  truncated: boolean;
}

interface WebReverseRequestViewModel {
  targetUrl?: string;
  reverseTarget?: string;
  triggerActions?: string;
  loginState?: string;
  browser?: string;
  cdpPort?: string;
  cdpMcp?: string;
  proxy?: string;
  keywords?: string;
  evidenceDiscipline?: string;
  deliverables?: string;
  acceptanceCriteria?: string;
  truncated: boolean;
}

interface AndroidReverseRequestViewModel {
  reverseTarget?: string;
  packageName?: string;
  apkPath?: string;
  device?: string;
  deviceSerial?: string;
  analysisMode?: string;
  authorizationScope?: string;
  adbMcp?: string;
  fridaMcp?: string;
  keywords?: string;
  notes?: string;
  evidenceDiscipline?: string;
  acceptanceCriteria?: string;
  truncated: boolean;
}

interface ExpertRequestFieldViewModel {
  label: string;
  value: string;
}

interface ExpertRequestBodyViewModel {
  icon: MessageIconName;
  title: string;
  description: string;
  chips: MessageContextChip[];
  fields: ExpertRequestFieldViewModel[];
  truncated: boolean;
}

const MACHINE_EXPERT_REQUEST_CARD_METADATA_KEY = 'machine_expert_request_card';
const WEB_REVERSE_REQUEST_CARD_METADATA_KEY = 'web_reverse_request_card';
const ANDROID_REVERSE_REQUEST_CARD_METADATA_KEY = 'android_reverse_request_card';
const EXPERT_REQUEST_CARD_MAX_FIELD_CHARACTERS = 1600;
const MACHINE_EXPERT_PROMPT_FIELD_LABELS = [
  '终端应用',
  '打开的终端位置',
  'AppleScript 精确定位',
  '需求内容',
] as const;
const WEB_REVERSE_PROMPT_FIELD_LABELS = [
  '目标 URL',
  '逆向目标',
  '触发动作',
  '登录态',
  '浏览器',
  'CDP 端口',
  'AI 侧 CDP MCP',
  '代理',
  '关键字',
  '取证纪律',
  '任务产物',
  '验收标准',
] as const;
const ANDROID_REVERSE_PROMPT_FIELD_LABELS = [
  '逆向目标',
  '目标包名',
  'APK 路径',
  '设备',
  '设备序列号',
  '分析模式',
  '授权范围',
  'ADB MCP',
  'Frida MCP',
  '关键字',
  '备注',
  '取证纪律',
  '验收标准',
] as const;

const KB_VECTOR_BATCH_SIZE = 120;
const KB_VECTOR_BATCH_INTERVAL_MS = 92;
const KB_VECTOR_MIN_ZOOM = 0.62;
const KB_VECTOR_MAX_ZOOM = 10;
const KB_VECTOR_ZOOM_BUTTON_FACTOR = 1.48;
const KB_VECTOR_SCROLL_ZOOM_SENSITIVITY = 0.0034;
const KB_VECTOR_AXIS_EXTENT = 1.18;
const KB_VECTOR_AXIS_TICK_SCREEN_LENGTH = 8;
const KB_VECTOR_AXIS_MINOR_TICK_SCREEN_LENGTH = 5;
const KB_VECTOR_AXIS_TARGET_TICK_GAP = 54;
const KB_VECTOR_POINT_HIT_RADIUS = 18;
const KB_VECTOR_POINT_HIT_PADDING = 14;
const KB_VECTOR_QUERY_HIT_PRIORITY_RADIUS = 30;
const KB_VECTOR_DRAG_START_PX = 8;
const KB_VECTOR_POPOVER_PADDING = 12;
const KB_VECTOR_POPOVER_WIDTH = 300;
const KB_VECTOR_INITIAL_SIZE = { width: 760, height: 460 } as const;

interface KnowledgeVectorSceneSize {
  width: number;
  height: number;
}

interface KnowledgeVectorAxisScale {
  step: number;
  labelStep: number;
  gridStep: number;
}

interface KnowledgeVectorAxisSpec {
  label: 'X' | 'Y' | 'Z';
  x: number;
  y: number;
  z: number;
  tickX: number;
  tickY: number;
  tickZ: number;
}

interface KnowledgeProjectedVectorPoint {
  point: KnowledgeVectorDistributionPoint;
  x: number;
  y: number;
  depth: number;
  perspective: number;
  radius: number;
}

interface KnowledgeSceneProjection {
  x: number;
  y: number;
  depth: number;
  perspective: number;
}

const KB_VECTOR_AXIS_SPECS: KnowledgeVectorAxisSpec[] = [
  { label: 'X', x: 1, y: 0, z: 0, tickX: 0, tickY: 0, tickZ: 1 },
  { label: 'Y', x: 0, y: 1, z: 0, tickX: 1, tickY: 0, tickZ: 0 },
  { label: 'Z', x: 0, y: 0, z: 1, tickX: 1, tickY: 0, tickZ: 0 },
];

const KNOWLEDGE_FIELD_LABEL_KEYS: Record<string, string> = {
  provider_config_id: 'message.kbDialog.field.providerConfigId',
  model_id: 'message.kbDialog.field.modelId',
  dimensions: 'message.kbDialog.field.dimensions',
  duration_ms: 'message.kbDialog.field.durationMs',
  top_n: 'message.kbDialog.field.topN',
  top_k: 'message.kbDialog.field.topK',
  min_similarity: 'message.kbDialog.field.minSimilarity',
  filters: 'message.kbDialog.field.filters',
  chunk_count: 'message.kbDialog.field.chunkCount',
  token_estimate: 'message.kbDialog.field.tokenEstimate',
  tokens: 'message.kbDialog.field.tokens',
  content_hash: 'message.kbDialog.field.contentHash',
  mode: 'message.kbDialog.field.mode',
  strategy: 'message.kbDialog.field.strategy',
  candidate_count: 'message.kbDialog.field.candidateCount',
  rerank_input_count: 'message.kbDialog.field.rerankInputCount',
  rerank_output_count: 'message.kbDialog.field.rerankOutputCount',
  kept_count: 'message.kbDialog.field.keptCount',
  discarded_count: 'message.kbDialog.field.discardedCount',
  error: 'message.kbDialog.field.error',
  status: 'message.kbDialog.field.status',
  query: 'message.kbDialog.field.query',
  chunk_id: 'message.kbDialog.field.chunkId',
  source_id: 'message.kbDialog.field.sourceId',
  source_title: 'message.kbDialog.field.sourceTitle',
  source_kind: 'message.kbDialog.field.sourceKind',
  path: 'message.kbDialog.field.path',
  tags: 'message.kbDialog.field.tags',
  document_time: 'message.kbDialog.field.documentTime',
  updated_at: 'message.kbDialog.field.updatedAt',
  created_at: 'message.kbDialog.field.createdAt',
  imported_at: 'message.kbDialog.field.importedAt',
  indexed_at: 'message.kbDialog.field.indexedAt',
  score: 'message.kbDialog.field.score',
  rerank_score: 'message.kbDialog.field.rerankScore',
  final_score: 'message.kbDialog.field.finalScore',
  time_field: 'message.kbDialog.field.timeField',
  title: 'message.kbDialog.field.title',
  heading_path: 'message.kbDialog.field.headingPath',
  chunk_index: 'message.kbDialog.field.chunkIndex',
  parent_chunk_id: 'message.kbDialog.field.parentChunkId',
  char_count: 'message.kbDialog.field.charCount',
  start_offset: 'message.kbDialog.field.startOffset',
  end_offset: 'message.kbDialog.field.endOffset',
  page_number: 'message.kbDialog.field.pageNumber',
  original_path: 'message.kbDialog.field.originalPath',
  stored_path: 'message.kbDialog.field.storedPath',
  mime_type: 'message.kbDialog.field.mimeType',
  size_bytes: 'message.kbDialog.field.sizeBytes',
  metadata: 'message.kbDialog.field.metadata',
};

function knowledgeFieldLabel(key: string): string {
  const normalized = key.trim();
  const translationKey = KNOWLEDGE_FIELD_LABEL_KEYS[normalized];
  if (translationKey) return t(translationKey, normalized);
  return normalized.replace(/_/g, ' ');
}

function parseKnowledgeVectorDistribution(
  raw: unknown,
): KnowledgeVectorDistributionData | null {
  const record = recordOrNullFromUnknown(raw);
  if (!record) return null;
  const points = Array.isArray(record['points'])
    ? record['points'].map((item): KnowledgeVectorDistributionPoint | null => {
      const pointRecord = recordOrNullFromUnknown(item);
      if (!pointRecord) return null;
      const id = strictStringFromUnknown(pointRecord['id']);
      const kind = strictStringFromUnknown(pointRecord['kind']);
      const x = finiteNumberOrNullFromUnknown(pointRecord['x']);
      const y = finiteNumberOrNullFromUnknown(pointRecord['y']);
      const z = finiteNumberOrNullFromUnknown(pointRecord['z']);
      if (!id || (kind !== 'corpus' && kind !== 'match' && kind !== 'query') || x == null || y == null || z == null) return null;
      const point: KnowledgeVectorDistributionPoint = {
        id,
        kind,
        title: strictStringFromUnknown(pointRecord['title']),
        preview: strictStringFromUnknown(pointRecord['preview']),
        x,
        y,
        z,
      };
      const score = finiteNumberOrNullFromUnknown(pointRecord['score']);
      const rerankScore = finiteNumberOrNullFromUnknown(pointRecord['rerank_score']);
      if (score != null) point.score = score;
      if (rerankScore != null) point.rerankScore = rerankScore;
      return point;
    }).filter((item): item is KnowledgeVectorDistributionPoint => item != null)
    : [];
  if (points.length === 0) return null;
  const durationMs = finiteNumberOrNullFromUnknown(record['duration_ms']);
  return {
    algorithm: strictStringFromUnknown(record['algorithm']) || 'deterministic_random_projection_3d',
    originalDimensions: nonNegativeIntegerFromUnknown(record['original_dimensions']),
    sampledCount: Math.max(points.length, nonNegativeIntegerFromUnknown(record['sampled_count'], points.length)),
    hasMore: record['has_more'] === true,
    ...(durationMs != null ? { durationMs: nonNegativeIntegerFromUnknown(durationMs) } : {}),
    ...(strictStringFromUnknown(record['generated_at']) ? { generatedAt: strictStringFromUnknown(record['generated_at']) } : {}),
    points,
  };
}

function knowledgeBaseMetadata(message: SessionMessage): Record<string, unknown> | null {
  const meta = recordOrNullFromUnknown(message.metadata);
  return recordOrNullFromUnknown(meta?.[KNOWLEDGE_BASE_MESSAGE_METADATA_KEY]);
}

function knowledgeBaseResults(kb: Record<string, unknown> | null): Record<string, unknown>[] {
  const raw = kb?.['results'];
  if (!Array.isArray(raw)) return [];
  return raw
    .map((item) => recordOrNullFromUnknown(item))
    .filter((item): item is Record<string, unknown> => item != null);
}

function knowledgeBaseHasReferences(message: SessionMessage): boolean {
  const kb = knowledgeBaseMetadata(message);
  return knowledgeBaseMetadataHasReferences(kb);
}

function knowledgeBaseMetadataHasReferences(kb: Record<string, unknown> | null): boolean {
  return kb?.['enabled'] === true &&
    kb?.['status'] === 'success' &&
    knowledgeBaseResults(kb).length > 0;
}

function knowledgeBaseMetadataUsedByAnswer(
  kb: Record<string, unknown> | null,
  answerText: string,
): Record<string, unknown> | null {
  if (!knowledgeBaseMetadataHasReferences(kb)) return null;
  const usedResults = knowledgeBaseResultsUsedByAnswer(
    knowledgeBaseResults(kb),
    answerText,
    {
      hitKey: (hit) =>
        knowledgeBaseCitationKey(hit, knowledgeBaseCitationLabel(hit)),
    },
  );
  if (usedResults.length === 0) return null;
  const promptAppend = recordOrNullFromUnknown(kb?.['prompt_append']) ?? {};
  const tokenEstimate = knowledgeBaseHitTokenEstimateTotal(usedResults);
  return {
    ...(kb ?? {}),
    results: usedResults,
    prompt_append: {
      ...promptAppend,
      chunk_count: usedResults.length,
      ...(tokenEstimate > 0 ? { token_estimate: tokenEstimate } : {}),
    },
  };
}

function knowledgeBaseTokenEstimate(kb: Record<string, unknown> | null): number | null {
  return finiteNumberOrNullFromUnknown(recordOrNullFromUnknown(kb?.['prompt_append'])?.['token_estimate']);
}

function knowledgeBaseContextContent(kb: Record<string, unknown> | null): string {
  return strictStringFromUnknown(kb?.['prompt_append_content']);
}

function knowledgeBaseVectorDistribution(kb: Record<string, unknown> | null): KnowledgeVectorDistributionData | null {
  return parseKnowledgeVectorDistribution(kb?.['vector_distribution']);
}

function knowledgeBaseCitationSources(
  kb: Record<string, unknown> | null,
  limit = Number.POSITIVE_INFINITY,
): KnowledgeBaseCitationSource[] {
  const sources: KnowledgeBaseCitationSource[] = [];
  const seen = new Set<string>();
  for (const hit of knowledgeBaseResults(kb)) {
    const label = knowledgeBaseCitationLabel(hit);
    if (!label) continue;
    const key = knowledgeBaseCitationKey(hit, label);
    if (seen.has(key)) continue;
    seen.add(key);
    sources.push({ key, label });
    if (sources.length >= limit) break;
  }
  return sources;
}

function knowledgeBaseCitationKey(hit: Record<string, unknown>, label: string): string {
  const sourceId = strictStringFromUnknown(hit['source_id']);
  if (sourceId) return `source:${sourceId}`;
  const path = strictStringFromUnknown(hit['path']);
  if (path) return `path:${path}`;
  return `label:${label}`;
}

function knowledgeBaseCitationLabel(hit: Record<string, unknown>): string {
  const title = strictStringFromUnknown(hit['source_title']) || strictStringFromUnknown(hit['title']);
  if (title) return title;
  const path = strictStringFromUnknown(hit['path']);
  if (path) {
    const normalized = path.replace(/\\/g, '/');
    const slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.slice(slash + 1) : normalized;
  }
  return strictStringFromUnknown(hit['chunk_id']);
}

/// 消息派生 view model 的按对象缓存。它们在卡片主体与 context chips 两条路径
/// 上各算一次，元数据未命中时还要对整条消息逐行跑正则。流式合并会为未变更的
/// 消息保留对象引用，因此 WeakMap 同时消除「同一次渲染算两遍」与「每次重渲染
/// 都重算」两类浪费；内容变更会产生新对象，缓存自然失效。
function memoizeByMessage<T>(
  compute: (message: SessionMessage) => T,
): (message: SessionMessage) => T {
  const cache = new WeakMap<SessionMessage, { value: T }>();
  return (message) => {
    const cached = cache.get(message);
    if (cached) return cached.value;
    const value = compute(message);
    cache.set(message, { value });
    return value;
  };
}

const webReverseRequestViewModel = memoizeByMessage(computeWebReverseRequestViewModel);
const androidReverseRequestViewModel = memoizeByMessage(computeAndroidReverseRequestViewModel);
const goalMessageViewModel = memoizeByMessage(computeGoalMessageViewModel);

function messageContextChips(message: SessionMessage): MessageContextChip[] {
  const meta = recordOrNullFromUnknown(message.metadata);
  const expertRequestChips = message.role === 'user'
    ? [
      ...machineExpertRequestChips(message),
      ...webReverseRequestChips(message),
      ...androidReverseRequestChips(message),
    ]
    : [];
  if (!meta) return expertRequestChips;
  return [
    ...expertRequestChips,
    ...(message.role === 'user' ? creationModeChips(meta) : []),
    ...(message.role === 'user' ? skillChips(meta) : []),
  ];
}

const machineExpertRequestViewModel = memoizeByMessage(
  (message: SessionMessage): MachineExpertRequestViewModel | null => {
    if (message.role !== 'user') return null;
    const meta = recordOrNullFromUnknown(message.metadata);
    const fromMeta = machineExpertRequestFromMetadata(meta?.[MACHINE_EXPERT_REQUEST_CARD_METADATA_KEY]);
    if (fromMeta) return fromMeta;
    return machineExpertRequestFromPrompt(message.content ?? '');
  },
);

function machineExpertRequestChips(message: SessionMessage): MessageContextChip[] {
  const view = machineExpertRequestViewModel(message);
  if (!view) return [];
  return [
    {
      key: 'machine-expert-request',
      icon: 'tool',
      label: t('message.machineRequest.chip.request', '机器专家请求'),
    },
    ...(view.appleScriptTarget ? [{
      key: 'machine-expert-precise',
      icon: 'globe' as const,
      label: t('message.machineRequest.chip.precise', '精确定位'),
    }] : []),
  ];
}

function machineExpertRequestFromMetadata(raw: unknown): MachineExpertRequestViewModel | null {
  const card = recordOrNullFromUnknown(raw);
  if (!card) return null;
  const view: MachineExpertRequestViewModel = {
    terminalApplication: strictStringFromUnknown(card['terminal_application']) || undefined,
    terminalLocation: strictStringFromUnknown(card['terminal_location']) || undefined,
    appleScriptTarget: strictStringFromUnknown(card['applescript_target']) || undefined,
    taskRequirement: strictStringFromUnknown(card['task_requirement']) || undefined,
    truncated: card['truncated'] === true,
  };
  return machineExpertRequestIsEmpty(view) ? null : view;
}

function machineExpertRequestFromPrompt(content: string): MachineExpertRequestViewModel | null {
  const fields = {
    terminalApplication: readPromptField(content, '终端应用', MACHINE_EXPERT_PROMPT_FIELD_LABELS),
    terminalLocation: readPromptField(content, '打开的终端位置', MACHINE_EXPERT_PROMPT_FIELD_LABELS),
    appleScriptTarget: readPromptField(content, 'AppleScript 精确定位', MACHINE_EXPERT_PROMPT_FIELD_LABELS),
    taskRequirement: readPromptField(content, '需求内容', MACHINE_EXPERT_PROMPT_FIELD_LABELS),
  };
  if (
    !fields.taskRequirement.trim() ||
    (!fields.terminalApplication.trim() && !fields.terminalLocation.trim()) ||
    Object.values(fields).every((value) => !value.trim())
  ) {
    return null;
  }
  const view: MachineExpertRequestViewModel = {
    terminalApplication: boundedExpertRequestField(fields.terminalApplication) || undefined,
    terminalLocation: boundedExpertRequestField(fields.terminalLocation) || undefined,
    appleScriptTarget: boundedExpertRequestField(fields.appleScriptTarget) || undefined,
    taskRequirement: boundedExpertRequestField(fields.taskRequirement) || undefined,
    truncated: Object.values(fields).some((value) => fieldNeedsExpertRequestTruncation(value)),
  };
  return machineExpertRequestIsEmpty(view) ? null : view;
}

function machineExpertRequestIsEmpty(view: MachineExpertRequestViewModel): boolean {
  return !view.terminalApplication &&
    !view.terminalLocation &&
    !view.appleScriptTarget &&
    !view.taskRequirement;
}

function computeWebReverseRequestViewModel(message: SessionMessage): WebReverseRequestViewModel | null {
  if (message.role !== 'user') return null;
  const meta = recordOrNullFromUnknown(message.metadata);
  const fromMeta = webReverseRequestFromMetadata(meta?.[WEB_REVERSE_REQUEST_CARD_METADATA_KEY]);
  if (fromMeta) return fromMeta;
  return webReverseRequestFromPrompt(message.content ?? '');
}

function webReverseRequestChips(message: SessionMessage): MessageContextChip[] {
  const view = webReverseRequestViewModel(message);
  if (!view) return [];
  return [
    {
      key: 'web-reverse-request',
      icon: 'globe',
      label: t('message.webReverseRequest.chip.request', 'Web 逆向请求'),
    },
    ...(view.cdpPort ? [{
      key: 'web-reverse-cdp',
      icon: 'tool' as const,
      label: `CDP ${view.cdpPort}`,
    }] : []),
  ];
}

function webReverseRequestFromMetadata(raw: unknown): WebReverseRequestViewModel | null {
  const card = recordOrNullFromUnknown(raw);
  if (!card) return null;
  const view: WebReverseRequestViewModel = {
    targetUrl: strictStringFromUnknown(card['target_url']) || undefined,
    reverseTarget: strictStringFromUnknown(card['reverse_target']) || undefined,
    triggerActions: strictStringFromUnknown(card['trigger_actions']) || undefined,
    loginState: strictStringFromUnknown(card['login_state']) || undefined,
    browser: strictStringFromUnknown(card['browser']) || undefined,
    cdpPort: strictStringFromUnknown(card['cdp_port']) || undefined,
    cdpMcp: strictStringFromUnknown(card['cdp_mcp']) || undefined,
    proxy: strictStringFromUnknown(card['proxy']) || undefined,
    keywords: strictStringFromUnknown(card['keywords']) || undefined,
    evidenceDiscipline: strictStringFromUnknown(card['evidence_discipline']) || undefined,
    deliverables: strictStringFromUnknown(card['deliverables']) || undefined,
    acceptanceCriteria: strictStringFromUnknown(card['acceptance_criteria']) || undefined,
    truncated: card['truncated'] === true,
  };
  return webReverseRequestIsEmpty(view) ? null : view;
}

function webReverseRequestFromPrompt(content: string): WebReverseRequestViewModel | null {
  if (!hasPromptHeading(content, '请求模板')) return null;
  const fields = {
    targetUrl: readPromptField(content, '目标 URL', WEB_REVERSE_PROMPT_FIELD_LABELS),
    reverseTarget: readPromptField(content, '逆向目标', WEB_REVERSE_PROMPT_FIELD_LABELS),
    triggerActions: readPromptField(content, '触发动作', WEB_REVERSE_PROMPT_FIELD_LABELS),
    loginState: readPromptField(content, '登录态', WEB_REVERSE_PROMPT_FIELD_LABELS),
    browser: readPromptField(content, '浏览器', WEB_REVERSE_PROMPT_FIELD_LABELS),
    cdpPort: readPromptField(content, 'CDP 端口', WEB_REVERSE_PROMPT_FIELD_LABELS),
    cdpMcp: readPromptField(content, 'AI 侧 CDP MCP', WEB_REVERSE_PROMPT_FIELD_LABELS),
    proxy: readPromptField(content, '代理', WEB_REVERSE_PROMPT_FIELD_LABELS),
    keywords: readPromptField(content, '关键字', WEB_REVERSE_PROMPT_FIELD_LABELS),
    evidenceDiscipline: readPromptField(content, '取证纪律', WEB_REVERSE_PROMPT_FIELD_LABELS),
    deliverables: readPromptField(content, '任务产物', WEB_REVERSE_PROMPT_FIELD_LABELS),
    acceptanceCriteria: readPromptField(content, '验收标准', WEB_REVERSE_PROMPT_FIELD_LABELS),
  };
  if (
    !fields.targetUrl.trim() ||
    !fields.reverseTarget.trim() ||
    (!fields.browser.trim() && !fields.cdpPort.trim() && !fields.cdpMcp.trim())
  ) {
    return null;
  }
  const view: WebReverseRequestViewModel = {
    targetUrl: boundedExpertRequestField(fields.targetUrl) || undefined,
    reverseTarget: boundedExpertRequestField(fields.reverseTarget) || undefined,
    triggerActions: boundedExpertRequestField(fields.triggerActions) || undefined,
    loginState: boundedExpertRequestField(fields.loginState) || undefined,
    browser: boundedExpertRequestField(fields.browser) || undefined,
    cdpPort: boundedExpertRequestField(fields.cdpPort) || undefined,
    cdpMcp: boundedExpertRequestField(fields.cdpMcp) || undefined,
    proxy: boundedExpertRequestField(fields.proxy) || undefined,
    keywords: boundedExpertRequestField(fields.keywords) || undefined,
    evidenceDiscipline: boundedExpertRequestField(fields.evidenceDiscipline) || undefined,
    deliverables: boundedExpertRequestField(fields.deliverables) || undefined,
    acceptanceCriteria: boundedExpertRequestField(fields.acceptanceCriteria) || undefined,
    truncated: Object.values(fields).some((value) => fieldNeedsExpertRequestTruncation(value)),
  };
  return webReverseRequestIsEmpty(view) ? null : view;
}

function webReverseRequestIsEmpty(view: WebReverseRequestViewModel): boolean {
  return !view.targetUrl &&
    !view.reverseTarget &&
    !view.loginState &&
    !view.browser &&
    !view.cdpPort &&
    !view.cdpMcp &&
    !view.evidenceDiscipline &&
    !view.deliverables &&
    !view.acceptanceCriteria;
}

function computeAndroidReverseRequestViewModel(message: SessionMessage): AndroidReverseRequestViewModel | null {
  if (message.role !== 'user') return null;
  const meta = recordOrNullFromUnknown(message.metadata);
  const fromMeta = androidReverseRequestFromMetadata(meta?.[ANDROID_REVERSE_REQUEST_CARD_METADATA_KEY]);
  if (fromMeta) return fromMeta;
  return androidReverseRequestFromPrompt(message.content ?? '');
}

function androidReverseRequestChips(message: SessionMessage): MessageContextChip[] {
  const view = androidReverseRequestViewModel(message);
  if (!view) return [];
  return [
    {
      key: 'android-reverse-request',
      icon: 'model',
      label: t('message.androidReverseRequest.chip.request', 'Android 逆向请求'),
    },
    ...(view.packageName ? [{
      key: 'android-reverse-package',
      icon: 'tool' as const,
      label: view.packageName,
    }] : []),
  ];
}

function androidReverseRequestFromMetadata(raw: unknown): AndroidReverseRequestViewModel | null {
  const card = recordOrNullFromUnknown(raw);
  if (!card) return null;
  const view: AndroidReverseRequestViewModel = {
    reverseTarget: strictStringFromUnknown(card['reverse_target']) || undefined,
    packageName: strictStringFromUnknown(card['package_name']) || undefined,
    apkPath: strictStringFromUnknown(card['apk_path']) || undefined,
    device: strictStringFromUnknown(card['device']) || undefined,
    deviceSerial: strictStringFromUnknown(card['device_serial']) || undefined,
    analysisMode: strictStringFromUnknown(card['analysis_mode']) || undefined,
    authorizationScope: strictStringFromUnknown(card['authorization_scope']) || undefined,
    adbMcp: strictStringFromUnknown(card['adb_mcp']) || undefined,
    fridaMcp: strictStringFromUnknown(card['frida_mcp']) || undefined,
    keywords: strictStringFromUnknown(card['keywords']) || undefined,
    notes: strictStringFromUnknown(card['notes']) || undefined,
    evidenceDiscipline: strictStringFromUnknown(card['evidence_discipline']) || undefined,
    acceptanceCriteria: strictStringFromUnknown(card['acceptance_criteria']) || undefined,
    truncated: card['truncated'] === true,
  };
  return androidReverseRequestIsEmpty(view) ? null : view;
}

function androidReverseRequestFromPrompt(content: string): AndroidReverseRequestViewModel | null {
  if (!hasPromptHeading(content, 'Android 逆向请求')) return null;
  const fields = {
    reverseTarget: readPromptField(content, '逆向目标', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    packageName: readPromptField(content, '目标包名', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    apkPath: readPromptField(content, 'APK 路径', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    device: readPromptField(content, '设备', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    deviceSerial: readPromptField(content, '设备序列号', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    analysisMode: readPromptField(content, '分析模式', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    authorizationScope: readPromptField(content, '授权范围', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    adbMcp: readPromptField(content, 'ADB MCP', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    fridaMcp: readPromptField(content, 'Frida MCP', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    keywords: readPromptField(content, '关键字', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    notes: readPromptField(content, '备注', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    evidenceDiscipline: readPromptField(content, '取证纪律', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
    acceptanceCriteria: readPromptField(content, '验收标准', ANDROID_REVERSE_PROMPT_FIELD_LABELS),
  };
  if (
    !fields.reverseTarget.trim() ||
    (
      !fields.packageName.trim() &&
      !fields.apkPath.trim() &&
      !fields.device.trim() &&
      !fields.deviceSerial.trim() &&
      !fields.analysisMode.trim()
    )
  ) {
    return null;
  }
  const view: AndroidReverseRequestViewModel = {
    reverseTarget: boundedExpertRequestField(fields.reverseTarget) || undefined,
    packageName: boundedExpertRequestField(fields.packageName) || undefined,
    apkPath: boundedExpertRequestField(fields.apkPath) || undefined,
    device: boundedExpertRequestField(fields.device) || undefined,
    deviceSerial: boundedExpertRequestField(fields.deviceSerial) || undefined,
    analysisMode: boundedExpertRequestField(fields.analysisMode) || undefined,
    authorizationScope: boundedExpertRequestField(fields.authorizationScope) || undefined,
    adbMcp: boundedExpertRequestField(fields.adbMcp) || undefined,
    fridaMcp: boundedExpertRequestField(fields.fridaMcp) || undefined,
    keywords: boundedExpertRequestField(fields.keywords) || undefined,
    notes: boundedExpertRequestField(fields.notes) || undefined,
    evidenceDiscipline: boundedExpertRequestField(fields.evidenceDiscipline) || undefined,
    acceptanceCriteria: boundedExpertRequestField(fields.acceptanceCriteria) || undefined,
    truncated: Object.values(fields).some((value) => fieldNeedsExpertRequestTruncation(value)),
  };
  return androidReverseRequestIsEmpty(view) ? null : view;
}

function androidReverseRequestIsEmpty(view: AndroidReverseRequestViewModel): boolean {
  return !view.reverseTarget &&
    !view.packageName &&
    !view.apkPath &&
    !view.device &&
    !view.deviceSerial &&
    !view.analysisMode &&
    !view.authorizationScope &&
    !view.adbMcp &&
    !view.fridaMcp &&
    !view.evidenceDiscipline &&
    !view.acceptanceCriteria;
}

function readPromptField(content: string, label: string, knownLabels: readonly string[]): string {
  // 绝大多数普通用户消息不含任何字段标签，先用一次子串扫描短路，
  // 省掉整条消息的 split + 逐行正则。
  if (!content.includes(label)) return '';
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const normalized = stripPromptBullet(lines[i]);
    if (!isPromptFieldLabel(normalized, label)) continue;
    const buffer = [normalized];
    for (let j = i + 1; j < lines.length; j += 1) {
      if (containsClosedCjkBracket(buffer.join('\n'))) break;
      const nextNormalized = stripPromptBullet(lines[j]);
      if (looksLikePromptField(nextNormalized, knownLabels)) break;
      buffer.push(lines[j]);
    }
    const joined = buffer.join('\n');
    return extractCjkBracketValue(joined) || readAfterSeparator(joined);
  }
  return '';
}

function stripPromptBullet(line: string): string {
  return line.trim().replace(/^[-*]\s*/, '');
}

function looksLikePromptField(line: string, knownLabels: readonly string[]): boolean {
  return knownLabels.some((label) => isPromptFieldLabel(line, label));
}

// 标签集合是固定的常量列表，按标签缓存已编译正则；否则逐行匹配会为每一行
// 每一个候选标签重新编译一次正则。
const promptFieldLabelPatterns = new Map<string, RegExp>();

function isPromptFieldLabel(line: string, label: string): boolean {
  if (line === label) return true;
  let pattern = promptFieldLabelPatterns.get(label);
  if (!pattern) {
    const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    pattern = new RegExp(`^${escaped}(?:\\s*[:：]|\\s*[（(])`);
    promptFieldLabelPatterns.set(label, pattern);
  }
  return pattern.test(line);
}

function hasPromptHeading(content: string, heading: string): boolean {
  return content.split(/\r?\n/).some((line) => {
    const normalized = stripPromptBullet(line);
    return normalized === heading || normalized === `${heading}：` || normalized === `${heading}:`;
  });
}

function containsClosedCjkBracket(value: string): boolean {
  const separator = value.indexOf('：【');
  const start = separator >= 0 ? separator + 1 : value.indexOf('【');
  const end = value.lastIndexOf('】');
  return start >= 0 && end > start;
}

function extractCjkBracketValue(value: string): string {
  const separator = value.indexOf('：【');
  const start = separator >= 0 ? separator + 1 : value.indexOf('【');
  const end = value.lastIndexOf('】');
  if (start < 0 || end <= start) return '';
  return value.slice(start + 1, end).trim();
}

function readAfterSeparator(value: string): string {
  const cjk = value.indexOf('：');
  const ascii = value.indexOf(':');
  const index = cjk >= 0 ? cjk : ascii;
  return index >= 0 ? value.slice(index + 1).trim() : '';
}

function fieldNeedsExpertRequestTruncation(value: string): boolean {
  return textExceedsLength(value.trim(), EXPERT_REQUEST_CARD_MAX_FIELD_CHARACTERS);
}

function boundedExpertRequestField(value: string): string {
  const normalized = value.trim();
  return truncateEndText(normalized, EXPERT_REQUEST_CARD_MAX_FIELD_CHARACTERS, {
    ellipsis: '...',
    trimEnd: true,
  });
}

function isGoalEvaluationMessage(message: SessionMessage): boolean {
  return recordOrNullFromUnknown(message.metadata)?.['goal_evaluation_message'] === true;
}

function goalEvaluationChips(message: SessionMessage, meta: Record<string, unknown>): MessageContextChip[] {
  if (meta['goal_evaluation_message'] !== true) return [];
  const type = strictStringFromUnknown(meta['goal_evaluation_message_type']);
  const round = strictStringFromUnknown(meta['goal_evaluation_round_index']);
  const suffix = round ? ` · #${round}` : '';
  return [{
    key: `goal-evaluation:${type || message.id}:${strictStringFromUnknown(meta['goal_evaluation_id']) || message.id}`,
    icon: 'audit',
    label: type === 'request'
      ? `${t('message.context.goalEvaluationRequest', '目标评估请求')}${suffix}`
      : `${t('message.context.goalEvaluationResponse', '目标评估响应')}${suffix}`,
  }];
}

function goalAutoFollowUpChips(message: SessionMessage, meta: Record<string, unknown>): MessageContextChip[] {
  if (meta['goal_evaluation_message'] === true) return [];
  if (meta['goal_auto_follow_up'] !== true) return [];
  const goalId = strictStringFromUnknown(meta['goal_id']);
  return [{
    key: `goal-auto:${goalId || message.id}`,
    icon: 'goal',
    label: goalId
      ? `${t('message.context.goalAutoFollowUp', '目标自动推进')} · ${goalId}`
      : t('message.context.goalAutoFollowUp', '目标自动推进'),
  }];
}

function goalObjectiveChips(message: SessionMessage, meta: Record<string, unknown>): MessageContextChip[] {
  if (message.role !== 'user') return [];
  if (meta['goal_evaluation_message'] === true || meta['goal_auto_follow_up'] === true) return [];
  const senderOrigin = strictStringFromUnknown(meta['sender_origin']);
  if (senderOrigin && senderOrigin !== 'explicit_user') return [];
  const goalId = strictStringFromUnknown(meta['goal_id']);
  const goalObjective = meta['goal_objective'];
  const hasGoalObjective = goalObjective === true || strictStringFromUnknown(goalObjective).length > 0;
  if (!goalId || !hasGoalObjective) return [];
  return [{
    key: `goal-objective:${goalId}`,
    icon: 'goal',
    label: `${t('message.context.goalObjective', '目标')} · ${shortGoalId(goalId)}`,
  }];
}

type GoalMessageKind = 'auto_follow_up' | 'evaluation_request' | 'evaluation_response';

interface GoalMessageViewModel {
  kind: GoalMessageKind;
  icon: MessageIconName;
  title: string;
  description: string;
  objective?: string;
  summary?: string;
  followUpPrompt?: string;
  passed?: boolean;
  confidence?: number;
  evidence: string[];
  missing: string[];
  metrics: MessageContextChip[];
}

function computeGoalMessageViewModel(message: SessionMessage): GoalMessageViewModel | null {
  const meta = recordOrNullFromUnknown(message.metadata);
  if (!meta) return null;
  if (meta['goal_auto_follow_up'] === true) {
    const parsed = parseGoalAutoFollowUpContent(message.content ?? '');
    return {
      kind: 'auto_follow_up',
      icon: 'goal',
      title: t('message.goal.auto.title', '继续推进当前目标'),
      description: t('message.goal.auto.description', 'Agent Runtime 自动发送，用于在上一轮评估未通过后继续收敛目标。'),
      objective: strictStringFromUnknown(meta['goal_objective']) || parsed.objective,
      summary: parsed.prompt,
      evidence: [],
      missing: [],
      metrics: goalMetricsFromMeta(meta),
    };
  }
  if (meta['goal_evaluation_message'] !== true) return null;
  const type = strictStringFromUnknown(meta['goal_evaluation_message_type']);
  if (type === 'request') {
    const payload = parseJsonObjectFromMarker(message.content ?? '', '{"goal":');
    const goal = recordOrNullFromUnknown(payload?.['goal']);
    const recent = Array.isArray(payload?.['recent_messages'])
      ? payload?.['recent_messages'] as unknown[]
      : [];
    return {
      kind: 'evaluation_request',
      icon: 'audit',
      title: t('message.goal.evaluationRequest.title', '验证目标完成证据'),
      description: t('message.goal.evaluationRequest.description', '评估模型会基于当前目标和最近对话判断完成证据是否充分。'),
      objective: strictStringFromUnknown(goal?.['objective']),
      evidence: [],
      missing: [],
      metrics: [
        ...goalMetricsFromMeta(meta),
        ...goalMetricsFromGoal(goal),
        ...(recent.length > 0 ? [{
          key: 'recent',
          icon: 'assistant' as const,
          label: t('message.goal.recentMessages', `最近 ${recent.length} 条`).replace('{count}', String(recent.length)),
        }] : []),
      ],
    };
  }
  if (type === 'response') {
    const decoded = parseJsonObjectFromMarker(message.content ?? '', '{');
    const passed = decoded?.['passed'] === true || meta['goal_evaluation_passed'] === true;
    const confidence = finiteNumberOrNullFromUnknown(decoded?.['confidence']) ?? undefined;
    return {
      kind: 'evaluation_response',
      icon: 'audit',
      title: passed
        ? t('message.goal.evaluationResponse.passedTitle', '目标证据已通过')
        : t('message.goal.evaluationResponse.continueTitle', '目标仍需推进'),
      description: passed
        ? t('message.goal.evaluationResponse.passedDescription', '评估模型认为当前证据足以完成目标。')
        : t('message.goal.evaluationResponse.continueDescription', '评估模型认为证据仍不足，需要继续推进。'),
      summary: strictStringFromUnknown(decoded?.['summary']),
      followUpPrompt: strictStringFromUnknown(decoded?.['follow_up_prompt']),
      passed,
      confidence,
      evidence: stringListFromUnknown(decoded?.['evidence']).slice(0, 8),
      missing: stringListFromUnknown(decoded?.['missing']).slice(0, 8),
      metrics: [
        ...goalMetricsFromMeta(meta),
        ...(confidence != null ? [{
          key: 'confidence',
          icon: 'audit' as const,
          label: `${Math.round(clampNumber(confidence, 0, 1) * 100)}%`,
        }] : []),
        ...goalCompletionMetricsFromMeta(meta, passed),
      ],
    };
  }
  return null;
}

function parseGoalAutoFollowUpContent(content: string): { prompt?: string; objective?: string } {
  const trimmed = content.trim();
  const match = /\n\s*Goal:\s*/i.exec(trimmed);
  if (!match) return { prompt: trimmed || undefined };
  const prompt = trimmed.slice(0, match.index).trim();
  const objective = trimmed.slice(match.index + match[0].length).trim();
  return {
    prompt: prompt || undefined,
    objective: objective || undefined,
  };
}

function parseJsonObjectFromMarker(content: string, marker: string): Record<string, unknown> | null {
  const index = content.indexOf(marker);
  if (index < 0) return null;
  return parseJsonRecordSafely(content.slice(index).trim());
}

function goalMetricsFromMeta(meta: Record<string, unknown>): MessageContextChip[] {
  const round = strictStringFromUnknown(meta['goal_evaluation_round_index']);
  const goalId = strictStringFromUnknown(meta['goal_id']);
  return [
    ...(round ? [{ key: 'round', icon: 'refresh' as const, label: `#${round}` }] : []),
    ...(goalId ? [{ key: 'goal-id', icon: 'goal' as const, label: shortGoalId(goalId) }] : []),
  ];
}

function goalMetricsFromGoal(goal: Record<string, unknown> | null): MessageContextChip[] {
  if (!goal) return [];
  const turnCount = finiteNumberOrNullFromUnknown(goal['turn_count']);
  const maxTurns = finiteNumberOrNullFromUnknown(goal['max_turns']);
  const tokensUsed = finiteNumberOrNullFromUnknown(goal['tokens_used']);
  const tokenBudget = finiteNumberOrNullFromUnknown(goal['token_budget']);
  return [
    ...(turnCount != null || maxTurns != null ? [{
      key: 'turns',
      icon: 'refresh' as const,
      label: `${Math.round(turnCount ?? 0)}/${Math.round(maxTurns ?? 12)}`,
    }] : []),
    ...(tokensUsed != null ? [{
      key: 'tokens',
      icon: 'model' as const,
      label: `${tNumber(Math.round(tokensUsed))}${tokenBudget != null ? `/${tNumber(Math.round(tokenBudget))}` : ''} ${t('message.goal.metric.tokens', '令牌')}`,
    }] : []),
  ];
}

function goalCompletionMetricsFromMeta(meta: Record<string, unknown>, passed: boolean): MessageContextChip[] {
  if (!passed) return [];
  const elapsedMs = finiteNumberOrNullFromUnknown(meta['goal_elapsed_ms']);
  const totalTokens = finiteNumberOrNullFromUnknown(meta['goal_total_tokens']);
  return [
    ...(elapsedMs != null ? [{
      key: 'total-duration',
      icon: 'clock' as const,
      label: `${t('message.goal.metric.totalDuration', '总耗时')} ${tDuration(Math.max(0, elapsedMs))}`,
    }] : []),
    ...(totalTokens != null ? [{
      key: 'total-tokens',
      icon: 'model' as const,
      label: `${t('message.goal.metric.totalTokens', '总令牌')} ${tNumber(Math.round(Math.max(0, totalTokens)))}`,
    }] : []),
  ];
}

function shortGoalId(goalId: string): string {
  return goalId.length <= 8 ? goalId : goalId.slice(0, 8);
}

function creationModeChips(meta: Record<string, unknown>): MessageContextChip[] {
  const request = recordOrNullFromUnknown(meta['creation_request']);
  const options = recordOrNullFromUnknown(request?.['options']);
  const mode = strictStringFromUnknown(request?.['mode']) || strictStringFromUnknown(meta['conversation_mode']);
  const data = creationModeData(mode);
  if (!data) return [];
  const detail = creationOptionDetail(options);
  const modePrefix = t('message.context.kind.mode', '模式');
  const label = `${modePrefix} · ${data.label}`;
  return [{
    key: `mode:${mode}`,
    icon: data.icon,
    label: detail ? `${label} · ${detail}` : label,
  }];
}

function creationModeData(mode: string): { icon: MessageIconName; label: string } | null {
  switch (mode) {
    case 'image':
      return { icon: 'image', label: t('message.context.mode.image', '图片生成') };
    case 'video':
      return { icon: 'video', label: t('message.context.mode.video', '视频生成') };
    case 'audio':
      return { icon: 'audio', label: t('message.context.mode.audio', '音频生成') };
    case 'deep_research':
      return { icon: 'deepResearch', label: t('message.context.mode.deepResearch', '深度研究') };
    default:
      return null;
  }
}

function mediaGenerationModeFromMetadata(
  metadata: Record<string, unknown>,
): MediaGenerationMode | null {
  const creationRequest = recordOrNullFromUnknown(metadata['creation_request']);
  const mode = strictStringFromUnknown(creationRequest?.['mode']) || strictStringFromUnknown(metadata['conversation_mode']);
  return mode === 'image' || mode === 'video' || mode === 'audio' || mode === 'deep_research'
    ? mode
    : null;
}

function creationOptionDetail(options: Record<string, unknown> | null): string {
  if (!options) return '';
  const parts: string[] = [];
  const aspectRatio = strictStringFromUnknown(options['aspect_ratio']);
  const size = strictStringFromUnknown(options['size']);
  const quality = strictStringFromUnknown(options['quality']);
  const style = strictStringFromUnknown(options['style']);
  const outputFormat = strictStringFromUnknown(options['output_format']);
  const background = strictStringFromUnknown(options['background']);
  const resolution = strictStringFromUnknown(options['resolution']);
  const mode = strictStringFromUnknown(options['mode']);
  const voice = strictStringFromUnknown(options['voice']);
  const duration = strictPositiveIntegerFromUnknown(options['duration_seconds']);
  const count = strictPositiveIntegerFromUnknown(options['count']);
  const frameRate = strictPositiveIntegerFromUnknown(options['frame_rate']);
  const numFrames = strictPositiveIntegerFromUnknown(options['num_frames']);
  const seed = strictPositiveIntegerFromUnknown(options['seed']);
  const speed = strictPositiveNumberFromUnknown(options['speed']);
  const sampleRate = strictPositiveIntegerFromUnknown(options['sample_rate']);
  const bitrate = strictPositiveIntegerFromUnknown(options['bitrate']);
  if (aspectRatio) parts.push(aspectRatio);
  else if (size) parts.push(size);
  if (duration != null) parts.push(`${duration}s`);
  if (resolution) parts.push(resolution);
  if (frameRate != null) parts.push(`${frameRate}fps`);
  if (numFrames != null) parts.push(`${numFrames}f`);
  if (quality) parts.push(quality);
  if (style) parts.push(style);
  if (outputFormat) parts.push(outputFormat);
  if (background) parts.push(background);
  if (mode) parts.push(mode);
  if (voice) parts.push(voice);
  if (speed != null) parts.push(`${speed}x`);
  if (sampleRate != null) parts.push(`${sampleRate}Hz`);
  if (bitrate != null) parts.push(`${Math.round(bitrate / 1000)}kbps`);
  if (seed != null) parts.push(`seed ${seed}`);
  if (typeof options['prompt_enhance'] === 'boolean') parts.push(options['prompt_enhance'] ? 'prompt+' : 'prompt-');
  if (typeof options['watermark'] === 'boolean') parts.push(options['watermark'] ? 'watermark' : 'no wm');
  if (strictStringFromUnknown(options['negative_prompt'])) parts.push('negative');
  if (count != null && count > 1) parts.push(`x${count}`);
  return parts.join(' · ');
}

function skillChips(meta: Record<string, unknown>): MessageContextChip[] {
  const skill = recordOrNullFromUnknown(meta['user_skill_selection']) ?? recordOrNullFromUnknown(meta['selected_skill']);
  const name = strictStringFromUnknown(skill?.['name']);
  if (!name) return [];
  const emoji = strictStringFromUnknown(skill?.['emoji']);
  return [{
    key: `skill:${name}`,
    icon: emoji ? undefined : 'skill',
    emoji: emoji || undefined,
    label: `${t('message.context.skill', '技能')} · ${name}`,
  }];
}

function MessageContextCapsule({ chip }: { chip: MessageContextChip }) {
  const content = (
    <>
      {chip.emoji ? (
        <span class="oh-message-context-emoji" aria-hidden>{chip.emoji}</span>
      ) : chip.icon ? (
        <span class="oh-message-context-icon" aria-hidden>
          <MessageIcon name={chip.icon} size={13} />
        </span>
      ) : null}
      <span class="truncate">{chip.label}</span>
    </>
  );
  if (chip.onClick) {
    return (
      <button
        type="button"
        class={`oh-message-context-capsule oh-soft-replace ${chip.tone === 'knowledge' ? 'is-knowledge' : ''}`}
        title={chip.label}
        onClick={(event) => {
          event.stopPropagation();
          chip.onClick?.();
        }}
      >
        {content}
      </button>
    );
  }
  return (
    <span class={`oh-message-context-capsule oh-soft-replace ${chip.tone === 'knowledge' ? 'is-knowledge' : ''}`} title={chip.label}>
      {content}
    </span>
  );
}

const messageActionSurfaceStyle = {
  color: 'currentColor',
  border: '1px solid color-mix(in srgb, currentColor 28%, transparent)',
  background: 'transparent',
};

type MessageActionTone = 'neutral' | 'positive' | 'improvement';

function messageActionSelectedSurfaceStyle(
  tone: MessageActionTone,
  hovered = false,
): Record<string, string> {
  const neutralBackground = hovered
    ? 'color-mix(in srgb, currentColor 22%, transparent)'
    : 'color-mix(in srgb, currentColor 16%, transparent)';
  switch (tone) {
    case 'positive':
      return {
        background: hovered
          ? 'color-mix(in srgb, var(--m3-primary-container) 92%, var(--m3-surface))'
          : 'color-mix(in srgb, var(--m3-primary-container) 82%, var(--m3-surface))',
        borderColor: 'color-mix(in srgb, var(--m3-primary) 68%, var(--m3-outline-variant))',
        color: 'var(--m3-on-primary-container)',
        boxShadow: '0 6px 18px -14px color-mix(in srgb, var(--m3-primary) 72%, transparent)',
      };
    case 'improvement':
      return {
        background: hovered
          ? 'color-mix(in srgb, var(--oh-full-access-container) 88%, var(--m3-secondary-container))'
          : 'color-mix(in srgb, var(--oh-full-access-container) 76%, var(--m3-secondary-container))',
        borderColor: 'color-mix(in srgb, var(--oh-full-access) 72%, var(--m3-outline-variant))',
        color: 'var(--oh-on-full-access-container)',
        boxShadow: '0 6px 18px -14px color-mix(in srgb, var(--oh-full-access) 74%, transparent)',
      };
    case 'neutral':
      return {
        background: neutralBackground,
        borderColor: 'color-mix(in srgb, currentColor 54%, transparent)',
        boxShadow: 'none',
      };
  }
}

function messageActionDefaultSurfaceStyle(hovered = false): Record<string, string> {
  return {
    background: hovered
      ? 'color-mix(in srgb, currentColor 8%, transparent)'
      : 'transparent',
    boxShadow: 'none',
  };
}

function messageActionVisualStyle(
  tone: MessageActionTone,
  selected: boolean,
  hovered = false,
): Record<string, string> {
  return selected
    ? messageActionSelectedSurfaceStyle(tone, hovered)
    : messageActionDefaultSurfaceStyle(hovered);
}

// reasoning（思考）专用：超过 5-6 行文本即默认折叠到预览态。
// 以 14px 行高 + 1.55 line-height ≈ 22px / 行换算，5-6 行约 110-130 字符的单行长度；
// 保守取 6 行 + 一个字符容差 ≈ 260 字符作为「超长」阈值。
const REASONING_AUTO_COLLAPSE_CHAR_LIMIT = 260;
const COLLAPSED_RICH_BODY_PREVIEW_MAX_CHARS = 1200;
const GENERAL_AUTO_COLLAPSE_CHAR_LIMIT = COLLAPSED_RICH_BODY_PREVIEW_MAX_CHARS;
const GENERAL_AUTO_COLLAPSE_LINE_LIMIT = 12;
// 折叠预览容器 max-height，像素值。≈ 6 行 × 22px = 132px，多给 10px 呼吸量，
// 对应 APP 端 _MarkdownPreviewBody maxHeight: 142。
const REASONING_PREVIEW_MAX_HEIGHT_PX = 142;
const RESPONSE_PREVIEW_MAX_HEIGHT_PX = 240;
const SIZE_MOTION_MIN_DELTA_PX = 1.5;
const SIZE_MOTION_TEXT_BUCKET_CHARS = 48;
const STREAMING_DIFF_REVEAL_MAX_CHARS = 32 * 1024;
const MESSAGE_APPEAR_BATCH_WINDOW_MS = 90;
const MESSAGE_UI_STATE_CACHE_LIMIT = 500;
const MESSAGE_CARD_TAP_MAX_MS = 350;
const MESSAGE_CARD_TAP_MAX_DISTANCE_PX = 8;
const COLLAPSED_BODY_BOTTOM_ENTER_PX = 2;
const COLLAPSED_BODY_BOTTOM_EXIT_PX = 10;
const COLLAPSED_BODY_SCROLL_SETTLE_MS = 180;
const MESSAGE_CARD_INTERACTIVE_TARGET_SELECTOR = [
  'button',
  'a',
  'input',
  'textarea',
  'select',
  '[role="button"]',
  '.oh-message-badge-toggle',
  '[data-message-media-interactive="true"]',
  '[data-message-scrollable-body="true"]',
  'video',
  'audio',
].join(',');

// 已经完成入场动画的消息 id 集合。防止 SSE 流式更新导致 Preact 卸载/重挂时
// CSS 入场动画重播，从而引发消息列表"闪烁→消失→重现"的鬼畜抖动。
const appearedMessageIds = new Set<string>();
const responseExpandedOverridesByMessageId = new Map<string, boolean>();
const badgeCollapsedOverridesByMessageId = new Map<string, boolean>();
const collapsedBodyScrollTopByKey = new Map<string, number>();
let messageAppearBatchStartedAt = 0;
let messageAppearBatchOrdinal = 0;

function reserveMessageAppearStaggerIndex(): number {
  const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
  if (now - messageAppearBatchStartedAt > MESSAGE_APPEAR_BATCH_WINDOW_MS) {
    messageAppearBatchStartedAt = now;
    messageAppearBatchOrdinal = 0;
  }
  const index = Math.min(12, messageAppearBatchOrdinal);
  messageAppearBatchOrdinal += 1;
  return index;
}

function trimAppearedMessageIds(): void {
  while (appearedMessageIds.size > MESSAGE_UI_STATE_CACHE_LIMIT) {
    const oldest = appearedMessageIds.values().next();
    if (oldest.done) break;
    appearedMessageIds.delete(oldest.value);
  }
}

function trackMessageAppeared(id: string): void {
  appearedMessageIds.add(id);
  trimAppearedMessageIds();
}

function rememberMessageUiState(
  cache: Map<string, boolean>,
  id: string,
  value: boolean,
): void {
  if (!id) return;
  if (cache.has(id)) cache.delete(id);
  cache.set(id, value);
  while (cache.size > MESSAGE_UI_STATE_CACHE_LIMIT) {
    const first = cache.keys().next().value;
    if (typeof first !== 'string') break;
    cache.delete(first);
  }
}

function rememberCollapsedBodyScrollTop(key: string | undefined, value: number): void {
  if (!key) return;
  if (collapsedBodyScrollTopByKey.has(key)) collapsedBodyScrollTopByKey.delete(key);
  collapsedBodyScrollTopByKey.set(key, Math.max(0, value));
  while (collapsedBodyScrollTopByKey.size > MESSAGE_UI_STATE_CACHE_LIMIT) {
    const first = collapsedBodyScrollTopByKey.keys().next().value;
    if (typeof first !== 'string') break;
    collapsedBodyScrollTopByKey.delete(first);
  }
}

function resetCollapsedBodyScrollTop(key: string | undefined): void {
  if (!key) return;
  rememberCollapsedBodyScrollTop(key, 0);
}

function isCollapsedBodyAtBottom(
  element: HTMLElement,
  currentlyAtBottom: boolean,
): boolean {
  const maxScrollTop = Math.max(0, element.scrollHeight - element.clientHeight);
  if (maxScrollTop <= COLLAPSED_BODY_BOTTOM_ENTER_PX) return true;
  const epsilon = currentlyAtBottom
    ? COLLAPSED_BODY_BOTTOM_EXIT_PX
    : COLLAPSED_BODY_BOTTOM_ENTER_PX;
  return element.scrollTop >= maxScrollTop - epsilon;
}

function stopNestedMessageScrollPropagation(event: Event): void {
  event.stopPropagation();
}

// 打开历史会话时一次性把已加载的全部 message id 标记为"已入场"。
// 历史消息没必要再跑 CSS 入场动画 + useLayoutEffect 高度量动画，避免长会话
// 首屏 N 张卡片并发 getBoundingClientRect / element.animate 撑爆主线程。
// 仅"新到达"的消息（流式 / SSE 推送）会继续走入场。
export function markMessagesAsAppeared(ids: readonly string[]): void {
  for (const id of ids) {
    if (id) appearedMessageIds.add(id);
  }
  trimAppearedMessageIds();
}

// 判定 reasoning 正文是否超过「5-6 行」：
// - 硬换行 (\n) 数 ≥ 5（即内容占 6 行及以上） → 超长；
// - 无硬换行时回退到字符数阈值（避免一大段未换行的文本被误判为短）。
function isReasoningLong(content: string): boolean {
  if (content.length > REASONING_AUTO_COLLAPSE_CHAR_LIMIT) return true;
  let lineBreaks = 0;
  for (let i = 0; i < content.length; i++) {
    if (content.charCodeAt(i) === 10) {
      lineBreaks += 1;
      if (lineBreaks >= 5) return true;
    }
  }
  return false;
}

function isGeneralMessageLong(content: string): boolean {
  if (content.length > GENERAL_AUTO_COLLAPSE_CHAR_LIMIT) return true;
  let lineBreaks = 0;
  for (let i = 0; i < content.length; i++) {
    if (content.charCodeAt(i) === 10) {
      lineBreaks += 1;
      if (lineBreaks >= GENERAL_AUTO_COLLAPSE_LINE_LIMIT) return true;
    }
  }
  return false;
}

function isAssistantResponseMessage(message: SessionMessage): boolean {
  if (message.role !== 'assistant') return false;
  if (isGoalEvaluationMessage(message)) return false;
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

function isFormalAssistantResponseMessage(message: SessionMessage): boolean {
  return isAssistantResponseMessage(message) && message.kind !== 'reasoning' && !isGoalEvaluationMessage(message);
}

function isPlainConversationMessage(message: SessionMessage): boolean {
  if (message.role !== 'user' && message.role !== 'assistant') return false;
  return !message.kind ||
    message.kind === 'text' ||
    message.kind === message.role;
}

function selectedMessageInfoChips(
  message: SessionMessage,
  associatedKnowledgeBaseMetadata: Record<string, unknown> | null = null,
  onOpenAssociatedKnowledgeBase?: () => void,
): MessageContextChip[] {
  const chips: MessageContextChip[] = [];
  const meta = recordOrNullFromUnknown(message.metadata);
  if (meta) {
    chips.push(...goalObjectiveChips(message, meta));
    chips.push(...goalEvaluationChips(message, meta));
    chips.push(...goalAutoFollowUpChips(message, meta));
  }
  if (message.role !== 'user') {
    const modelLabel = strictStringFromUnknown(message.model_label) || strictStringFromUnknown(message.model_id);
    if (modelLabel) {
      chips.push({
        key: 'model',
        icon: 'model',
        label: modelLabel,
      });
    }
  }
  const associatedSources = knowledgeBaseCitationSources(associatedKnowledgeBaseMetadata);
  if (associatedSources.length > 0) {
    chips.push({
      key: 'associated-knowledge-base',
      icon: 'knowledge',
      tone: 'knowledge',
      label: t('message.context.knowledgeBaseSources', `引用 ${associatedSources.length} 篇知识库`)
        .replace('{count}', String(associatedSources.length)),
      onClick: onOpenAssociatedKnowledgeBase,
    });
  }
  const sentAt = formatLocalDateTimeMinute(message.created_at);
  if (sentAt) {
    chips.push({
      key: 'sent-at',
      icon: 'clock',
      label: sentAt,
    });
  }
  return chips;
}

function messageSizeMotionSignal(message: SessionMessage): string {
  const metadata = message.metadata ?? {};
  return [
    message.id,
    message.role,
    message.kind,
    textLayoutMotionSignal(message.content ?? ''),
    numberLayoutMotionSignal(message.character_count),
    booleanFromUnknown(metadata['tool_arguments_streaming']) ? 1 : 0,
    stringFromUnknown(metadata['tool_execution_status'] ?? metadata['tool_status'] ?? metadata['status']),
    textLayoutMotionSignal(stringFromUnknown(metadata['tool_execution_stdout'])),
    textLayoutMotionSignal(stringFromUnknown(metadata['tool_execution_stderr'])),
    textLayoutMotionSignal(stringFromUnknown(metadata['tool_execution_result'] ?? metadata['result_text'])),
    stringFromUnknown(metadata['file_mutation_kind']),
    finiteNumberOrNullFromUnknown(metadata['round_summary_record_count']) ?? '',
  ].join('|');
}

function textLayoutMotionSignal(
  value: string,
  bucketChars = SIZE_MOTION_TEXT_BUCKET_CHARS,
): string {
  let lineBreaks = 0;
  for (let index = 0; index < value.length; index += 1) {
    if (value.charCodeAt(index) === 10) lineBreaks += 1;
  }
  return `${lineBreaks}:${Math.floor(value.length / bucketChars)}`;
}

function numberLayoutMotionSignal(value: number | undefined): string {
  return value == null ? '' : String(Math.floor(value / SIZE_MOTION_TEXT_BUCKET_CHARS));
}

function useMessageSizeMotion(signal: string, enabled: boolean) {
  const ref = useRef<HTMLDivElement | null>(null);
  const lastHeightRef = useRef<number | null>(null);
  const animationRef = useRef<Animation | null>(null);
  const overflowBeforeAnimationRef = useRef<string | null>(null);
  // IntersectionObserver gate：长会话首屏 N 张卡片同时 mount 时，offscreen
  // 卡片完全没必要跑 getBoundingClientRect（会强制 layout）也没必要起
  // element.animate。等卡片第一次滚进视口（含 rootMargin 50px 提前），
  // 再让 useLayoutEffect 体走完整路径并初始化 lastHeightRef。
  const [everVisible, setEverVisible] = useState(false);

  const restoreOverflow = useCallback((element: HTMLElement) => {
    animationRef.current?.cancel();
    animationRef.current = null;
    if (overflowBeforeAnimationRef.current != null) {
      element.style.overflow = overflowBeforeAnimationRef.current;
      overflowBeforeAnimationRef.current = null;
    }
  }, []);

  useEffect(() => () => {
    animationRef.current?.cancel();
    animationRef.current = null;
  }, []);

  useEffect(() => {
    if (everVisible) return;
    const element = ref.current;
    if (!element || typeof IntersectionObserver === 'undefined') {
      // 不支持 IntersectionObserver（极少数老环境）则直接打开 gate，
      // 退化到原行为。
      setEverVisible(true);
      return;
    }
    let cancelRevealAfterScroll: (() => void) | null = null;
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            cancelRevealAfterScroll = scheduleAfterTranscriptScrollSettles(() => {
              setEverVisible(true);
            });
            io.disconnect();
            return;
          }
        }
      },
      { rootMargin: '50px 0px 50px 0px' },
    );
    io.observe(element);
    return () => {
      cancelRevealAfterScroll?.();
      io.disconnect();
    };
  }, [everVisible]);

  useLayoutEffect(() => {
    if (!everVisible) return;
    const element = ref.current;
    if (!element) return;

    if (!enabled || isTranscriptScrollActive()) {
      restoreOverflow(element);
      lastHeightRef.current = null;
      return;
    }

    const activeAnimation = animationRef.current;
    const currentVisualHeight = activeAnimation
      ? element.getBoundingClientRect().height
      : null;
    restoreOverflow(element);

    const nextHeight = element.getBoundingClientRect().height;
    const previousHeight = lastHeightRef.current;
    lastHeightRef.current = nextHeight;
    if (previousHeight == null || typeof element.animate !== 'function') return;

    const fromHeight = currentVisualHeight ?? previousHeight;
    const delta = nextHeight - fromHeight;
    if (!Number.isFinite(fromHeight) || !Number.isFinite(nextHeight) || Math.abs(delta) < SIZE_MOTION_MIN_DELTA_PX) {
      return;
    }

    const growing = delta > 0;
    const overshoot = growing ? clampNumber(delta * 0.12, 2, 10) : 0;
    // 展开与折叠分别服从全局弹窗的方向时长与曲线。
    const baseDuration = growing
      ? getDialogEnterDurationMs()
      : getDialogExitDurationMs();
    if (baseDuration <= 0) return;
    overflowBeforeAnimationRef.current = element.style.overflow;
    element.style.overflow = 'clip';
    const animation = element.animate(
      growing
        ? [
            { height: `${fromHeight}px`, offset: 0 },
            { height: `${nextHeight + overshoot}px`, offset: 0.72 },
            { height: `${nextHeight}px`, offset: 1 },
          ]
        : [
            { height: `${fromHeight}px`, offset: 0 },
            { height: `${nextHeight}px`, offset: 1 },
          ],
      {
        duration: baseDuration,
        easing: growing ? getDialogMotionCurve() : getDialogMotionExitCurve(),
      },
    );
    animationRef.current = animation;
    const restore = () => {
      if (animationRef.current !== animation) return;
      animationRef.current = null;
      element.style.overflow = overflowBeforeAnimationRef.current ?? '';
      overflowBeforeAnimationRef.current = null;
    };
    void animation.finished.then(restore, restore);
  }, [enabled, restoreOverflow, signal, everVisible]);

  return ref;
}

function useRecentMessageActivity(
  signal: string,
  enabled: boolean,
  holdMs: number,
): boolean {
  const [active, setActive] = useState(false);
  const initializedRef = useRef(false);
  const { clearTimer, scheduleTimer } = useTimeoutController();

  useEffect(() => {
    if (!enabled) {
      clearTimer();
      initializedRef.current = true;
      setActive(false);
      return;
    }
    if (!initializedRef.current) {
      initializedRef.current = true;
      return;
    }
    setActive(true);
    scheduleTimer(() => setActive(false), holdMs);
    return clearTimer;
  }, [clearTimer, signal, enabled, holdMs, scheduleTimer]);

  return active;
}

function StreamingPlainTextReveal({
  content,
  streaming,
  reduceMotion,
  mono,
}: {
  content: string;
  streaming: boolean;
  reduceMotion: boolean;
  mono: boolean;
}) {
  const { visibleContent } = useStreamingStagedText(
    content,
    streaming,
    reduceMotion,
  );
  const revealAllowed = visibleContent.length <= STREAMING_DIFF_REVEAL_MAX_CHARS;
  const { containerRef: streamingMaskRef, streamingClass } = useStreamingReveal(
    streaming && revealAllowed,
    visibleContent.length,
    visibleContent,
    reduceMotion,
  );

  return (
    <div>
      <div
        ref={streamingMaskRef}
        class={streamingClass ? 'oh-streaming-reveal' : undefined}
      >
        <pre
          class="whitespace-pre-wrap break-words text-sm"
          style={{
            margin: 0,
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-word',
            font: 'inherit',
            lineHeight: 'inherit',
            fontFamily: mono ? 'ui-monospace, SFMono-Regular, Menlo, monospace' : undefined,
          }}
        >
          {visibleContent}
        </pre>
      </div>
    </div>
  );
}

function StreamingMarkdownReveal({
  content,
  streaming,
  reduceMotion,
  raw,
  mono,
  format,
  htmlFallback,
  deferInitialRender,
}: {
  content: string;
  streaming: boolean;
  reduceMotion: boolean;
  raw: boolean;
  mono: boolean;
  format?: 'markdown' | 'plain_text' | 'html';
  htmlFallback?: 'markdown' | 'plain_text';
  deferInitialRender: boolean;
}) {
  const contentIsHtml = looksLikeRenderableHtml(content);
  const canStageContent = streaming && format !== 'html' && !contentIsHtml;
  const { visibleContent: renderContent, staging } = useStreamingStagedText(
    content,
    canStageContent,
    reduceMotion,
  );
  const revealAllowed = renderContent.length <= STREAMING_DIFF_REVEAL_MAX_CHARS;
  const { containerRef: streamingMaskRef, streamingClass } =
    useStreamingReveal(
      streaming && revealAllowed,
      renderContent.length,
      renderContent,
      reduceMotion,
    );

  return (
    <div>
      <div
        ref={streamingMaskRef}
        class={streamingClass ? 'oh-streaming-reveal' : undefined}
      >
        <Markdown
          source={renderContent}
          raw={raw}
          mono={mono}
          format={format}
          htmlFallback={htmlFallback}
          streaming={streaming || staging}
          deferInitialRender={deferInitialRender}
        />
      </div>
    </div>
  );
}

function MachineExpertRequestBody({ view }: { view: MachineExpertRequestViewModel }) {
  const fields: ExpertRequestFieldViewModel[] = [];
  if (view.terminalApplication) fields.push({ label: t('message.machineRequest.field.terminal', '终端应用'), value: view.terminalApplication });
  if (view.terminalLocation) fields.push({ label: t('message.machineRequest.field.location', '打开位置'), value: view.terminalLocation });
  if (view.appleScriptTarget) fields.push({ label: t('message.machineRequest.field.applescript', '精确定位'), value: view.appleScriptTarget });
  if (view.taskRequirement) fields.push({ label: t('message.machineRequest.field.task', '需求'), value: view.taskRequirement });
  return <ExpertRequestBody view={{
    icon: 'tool',
    title: t('message.machineRequest.title', '机器专家执行请求'),
    description: t('message.machineRequest.description', '已绑定目标终端，会在指定会话中执行任务。'),
    chips: [
      { key: 'first', icon: 'refresh', label: '#1' },
      { key: 'template', icon: 'tool', label: t('message.machineRequest.chip.template', '机器专家') },
      ...(view.appleScriptTarget ? [{ key: 'precise', icon: 'globe' as const, label: t('message.machineRequest.chip.precise', '精确定位') }] : []),
    ],
    fields,
    truncated: view.truncated,
  }} />;
}

function WebReverseRequestBody({ view }: { view: WebReverseRequestViewModel }) {
  const fields: ExpertRequestFieldViewModel[] = [];
  if (view.targetUrl) fields.push({ label: t('message.webReverseRequest.field.targetUrl', '目标 URL'), value: view.targetUrl });
  if (view.reverseTarget) fields.push({ label: t('message.webReverseRequest.field.objective', '逆向目标'), value: view.reverseTarget });
  if (view.triggerActions) fields.push({ label: t('message.webReverseRequest.field.triggerActions', '触发动作'), value: view.triggerActions });
  if (view.browser) fields.push({ label: t('message.webReverseRequest.field.browser', '浏览器'), value: view.browser });
  if (view.cdpMcp) fields.push({ label: t('message.webReverseRequest.field.cdpMcp', 'AI 侧 CDP MCP'), value: view.cdpMcp });
  if (view.proxy) fields.push({ label: t('message.webReverseRequest.field.proxy', '代理'), value: view.proxy });
  if (view.keywords) fields.push({ label: t('message.webReverseRequest.field.keywords', '关键字'), value: view.keywords });
  if (view.evidenceDiscipline) fields.push({ label: t('message.webReverseRequest.field.evidence', '取证纪律'), value: view.evidenceDiscipline });
  if (view.deliverables) fields.push({ label: t('message.webReverseRequest.field.deliverables', '任务产物'), value: view.deliverables });
  if (view.acceptanceCriteria) fields.push({ label: t('message.webReverseRequest.field.acceptance', '验收标准'), value: view.acceptanceCriteria });
  return <ExpertRequestBody view={{
    icon: 'globe',
    title: t('message.webReverseRequest.title', 'Web 逆向请求'),
    description: t('message.webReverseRequest.description', '已绑定目标页面与 CDP 环境，按浏览器取证流程推进。'),
    chips: [
      { key: 'first', icon: 'refresh', label: '#1' },
      { key: 'template', icon: 'globe', label: t('message.webReverseRequest.chip.template', 'Web 逆向') },
      ...(view.cdpPort ? [{ key: 'cdp', icon: 'tool' as const, label: `CDP ${view.cdpPort}` }] : []),
      ...(view.loginState ? [{ key: 'login', icon: 'audit' as const, label: view.loginState }] : []),
    ],
    fields,
    truncated: view.truncated,
  }} />;
}

function AndroidReverseRequestBody({ view }: { view: AndroidReverseRequestViewModel }) {
  const fields: ExpertRequestFieldViewModel[] = [];
  const device = view.deviceSerial || view.device;
  if (view.reverseTarget) fields.push({ label: t('message.androidReverseRequest.field.objective', '逆向目标'), value: view.reverseTarget });
  if (view.packageName) fields.push({ label: t('message.androidReverseRequest.field.package', '目标包名'), value: view.packageName });
  if (view.apkPath) fields.push({ label: t('message.androidReverseRequest.field.apkPath', 'APK 路径'), value: view.apkPath });
  if (device) fields.push({ label: t('message.androidReverseRequest.field.device', '设备'), value: device });
  if (view.analysisMode) fields.push({ label: t('message.androidReverseRequest.field.analysisMode', '分析模式'), value: view.analysisMode });
  if (view.authorizationScope) fields.push({ label: t('message.androidReverseRequest.field.authorization', '授权范围'), value: view.authorizationScope });
  if (view.adbMcp) fields.push({ label: t('message.androidReverseRequest.field.adbMcp', 'ADB MCP'), value: view.adbMcp });
  if (view.fridaMcp) fields.push({ label: t('message.androidReverseRequest.field.fridaMcp', 'Frida MCP'), value: view.fridaMcp });
  if (view.keywords) fields.push({ label: t('message.androidReverseRequest.field.keywords', '关键字'), value: view.keywords });
  if (view.notes) fields.push({ label: t('message.androidReverseRequest.field.notes', '备注'), value: view.notes });
  if (view.evidenceDiscipline) fields.push({ label: t('message.androidReverseRequest.field.evidence', '取证纪律'), value: view.evidenceDiscipline });
  if (view.acceptanceCriteria) fields.push({ label: t('message.androidReverseRequest.field.acceptance', '验收标准'), value: view.acceptanceCriteria });
  return <ExpertRequestBody view={{
    icon: 'model',
    title: t('message.androidReverseRequest.title', 'Android 逆向请求'),
    description: t('message.androidReverseRequest.description', '已绑定目标应用与分析边界，按静态优先取证流程推进。'),
    chips: [
      { key: 'first', icon: 'refresh', label: '#1' },
      { key: 'template', icon: 'model', label: t('message.androidReverseRequest.chip.template', 'Android 逆向') },
      ...(view.packageName ? [{ key: 'package', icon: 'tool' as const, label: view.packageName }] : []),
      ...(view.apkPath ? [{ key: 'apk', icon: 'attachmentFile' as const, label: t('message.androidReverseRequest.chip.apk', 'APK') }] : []),
    ],
    fields,
    truncated: view.truncated,
  }} />;
}

function ExpertRequestBody({ view }: { view: ExpertRequestBodyViewModel }) {
  return (
    <div class="oh-expert-request-body">
      <div class="oh-expert-request-heading">
        <span class="oh-expert-request-icon" aria-hidden>
          <MessageIcon name={view.icon} size={16} />
        </span>
        <div class="min-w-0">
          <div class="oh-expert-request-title">{view.title}</div>
          <div class="oh-expert-request-description">{view.description}</div>
        </div>
      </div>
      {view.chips.length > 0 ? (
        <div class="oh-expert-request-metrics">
          {view.chips.map((chip) => <MessageContextCapsule key={chip.key} chip={chip} />)}
        </div>
      ) : null}
      {view.fields.map((field) => (
        <ExpertRequestField key={field.label} label={field.label} value={field.value} />
      ))}
      {view.truncated ? (
        <div class="oh-expert-request-note">
          {t('message.expertRequest.truncated', '卡片内容已截断，完整原文仍保留在消息审计与复制内容中。')}
        </div>
      ) : null}
    </div>
  );
}

function ExpertRequestField({ label, value }: { label: string; value: string }) {
  return (
    <div class="oh-expert-request-field">
      <span>{label}</span>
      <p>{value}</p>
    </div>
  );
}

function GoalMessageBody({ view }: { view: GoalMessageViewModel }) {
  return (
    <div class={`oh-goal-message-body is-${view.kind}`}>
      <div class="oh-goal-message-heading">
        <span class="oh-goal-message-icon" aria-hidden>
          <MessageIcon name={view.icon} size={16} />
        </span>
        <div class="min-w-0">
          <div class="oh-goal-message-title">{view.title}</div>
          <div class="oh-goal-message-description">{view.description}</div>
        </div>
      </div>
      {view.objective ? (
        <GoalMessageField label={t('message.goal.field.objective', '目标')} value={view.objective} />
      ) : null}
      {view.summary ? (
        <GoalMessageField label={view.kind === 'auto_follow_up' ? t('message.goal.field.instruction', '推进指令') : t('message.goal.field.summary', '评估摘要')} value={view.summary} />
      ) : null}
      {view.followUpPrompt ? (
        <GoalMessageField label={t('message.goal.field.nextStep', '下一步')} value={view.followUpPrompt} />
      ) : null}
      {view.evidence.length > 0 ? (
        <GoalMessageBulletList label={t('message.goal.field.evidence', '证据')} values={view.evidence} tone="pass" />
      ) : null}
      {view.missing.length > 0 ? (
        <GoalMessageBulletList label={t('message.goal.field.missing', '缺口')} values={view.missing} tone="missing" />
      ) : null}
      {view.metrics.length > 0 ? (
        <div class="oh-goal-message-metrics">
          {view.metrics.map((chip) => <MessageContextCapsule key={chip.key} chip={chip} />)}
        </div>
      ) : null}
    </div>
  );
}

function GoalMessageField({ label, value }: { label: string; value: string }) {
  return (
    <div class="oh-goal-message-field">
      <span>{label}</span>
      <p>{value}</p>
    </div>
  );
}

function GoalMessageBulletList({
  label,
  values,
  tone,
}: {
  label: string;
  values: string[];
  tone: 'pass' | 'missing';
}) {
  return (
    <div class={`oh-goal-message-list is-${tone}`}>
      <span>{label}</span>
      <ul>
        {values.map((value, index) => <li key={`${tone}-${index}`}>{value}</li>)}
      </ul>
    </div>
  );
}

interface MessageCardProps {
  message: SessionMessage;
  /// 由详情页受控的点击选中态；只有选中的卡片显示操作栏。
  active?: boolean;
  /// 默认 false；调用方可设为 true 强制展开。
  forceExpanded?: boolean;
  /// 当前消息是否仍在流式增长；正式响应超过阈值后进入折叠预览。
  streaming?: boolean;
  /// 当前会话回合是否仍在运行；用于稳住已完成的非 reasoning 长卡片，避免
  /// 回合状态抖动带来反复折叠/展开。
  turnActive?: boolean;
  /// 媒体资产 URL 构造需要 sessionId; 缺省则不渲染媒体卡。
  sessionId?: string;
  /// 复制本条消息正文（必传时显示「复制」按钮）。
  onCopy?: (m: SessionMessage) => void;
  /// 删除本条消息（必传时显示「删除」按钮）。
  onDelete?: (m: SessionMessage) => void;
  /// 删除本条及之后所有消息（必传时显示「删除此条及后续」按钮）。
  onDeleteAfter?: (m: SessionMessage) => void;
  /// 编辑用户消息后重新发送（必传时显示「编辑」按钮）。
  onEdit?: (m: SessionMessage) => void;
  /// 打开消息审计弹窗（展示 metadata / 原始 JSON）。
  onAudit?: (m: SessionMessage) => void;
  /// 从当前消息派生新会话。
  onFork?: (m: SessionMessage) => void;
  readAloudEnabled?: boolean;
  readAloudPlaying?: boolean;
  textActionContentFormat?: MessageContentFormat;
  translationEnabled?: boolean;
  feedbackEnabled?: boolean;
  regenerationEnabled?: boolean;
  translatedContent?: string | null;
  translationLoading?: boolean;
  translationVisible?: boolean;
  associatedKnowledgeBaseMetadata?: Record<string, unknown> | null;
  feedbackBusy?: boolean;
  regenerating?: boolean;
  onToggleReadAloud?: (m: SessionMessage) => void;
  onToggleTranslation?: (m: SessionMessage) => void;
  onSetFeedback?: (m: SessionMessage, feedback: SessionMessageFeedback | null) => void;
  onRegenerate?: (m: SessionMessage) => void;
  onActiveChange?: (m: SessionMessage, active: boolean) => void;
}

function MessageCardImpl({
  message,
  active = false,
  forceExpanded = false,
  streaming = false,
  turnActive = false,
  sessionId,
  onCopy,
  onDelete,
  onDeleteAfter,
  onEdit,
  onAudit,
  onFork,
  readAloudEnabled = true,
  readAloudPlaying = false,
  textActionContentFormat,
  translationEnabled = true,
  feedbackEnabled = true,
  regenerationEnabled = true,
  translatedContent,
  translationLoading = false,
  translationVisible = false,
  associatedKnowledgeBaseMetadata = null,
  feedbackBusy = false,
  regenerating = false,
  onToggleReadAloud,
  onToggleTranslation,
  onSetFeedback,
  onRegenerate,
  onActiveChange,
}: MessageCardProps) {
  const reduceMotion = useReducedMotion();
  const { format: contentFormat, htmlFallback: contentHtmlFallback } = useMessageContentFormat();
  const [showRawContent, setShowRawContent] = useState(false);
  const style = styleForKind(message.kind, message.role);
  const content = message.content ?? '';
  const isUserBubble = message.role === 'user';
  const goalMessageView = goalMessageViewModel(message);
  const machineExpertRequestView = machineExpertRequestViewModel(message);
  const webReverseRequestView = webReverseRequestViewModel(message);
  const androidReverseRequestView = androidReverseRequestViewModel(message);
  const useStructuredToolBody =
    message.kind === 'tool' ||
    message.kind === 'tool_call' ||
    message.kind === 'mcp';
  const useToolBody = useStructuredToolBody || message.kind === 'file_mutation_summary';
  const metadata = message.metadata ?? {};
  const [knowledgeBaseDialogOpen, setKnowledgeBaseDialogOpen] = useState(false);
  const kbMetadata = knowledgeBaseMetadata(message);
  const kbResults = knowledgeBaseResults(kbMetadata);
  const kbTokenEstimate = knowledgeBaseTokenEstimate(kbMetadata);
  const recentlyUpdatedContent = useRecentMessageActivity(
    content,
    !isUserBubble &&
      (isAssistantResponseMessage(message) || message.kind === 'reasoning'),
    12000,
  );
  const activelyStreaming = streaming || booleanFromUnknown(metadata['streaming']);
  const isReasoningMessage = message.kind === 'reasoning';
  const isActivelyStreamingReasoning = isReasoningMessage && activelyStreaming;
  const streamingContent = isReasoningMessage
    ? activelyStreaming
    : activelyStreaming || recentlyUpdatedContent;
  const visuallyStreamingContent = isReasoningMessage
    ? isActivelyStreamingReasoning
    : activelyStreaming;
  const inlineCreationMode =
    !isUserBubble && activelyStreaming && content.trim().length < 10
      ? mediaGenerationModeFromMetadata(metadata)
      : null;
  // 在同一回合内，即便此卡不再是「最新流式卡」，已完成的非 reasoning 卡
  // 只要回合仍在运行就保持展开；正在增长的正式响应达到阈值后由
  // responseCollapsedWhileStreaming 单独进入折叠预览。
  //
  // 关键去抖：服务器 send_phase 在 SSE / 2.5s phase guard / polling 三路之间
  // 存在竞态，turnActive 会瞬态 true → false → true 跳变 (~ 每隔几秒一次)，
  // 直接驱动 keepExpandedDuringTurn → 长正文卡的 collapsed 跟着跳变 → CSS
  // 360ms max-height (4000px ↔ 240px) 过渡每隔几秒跑一遍 → 视觉上正文
  // 区每隔几秒"消失再立刻显示"（卡片外框稳定，因 collapsed 只裁 body），
  // 同时撑高的工具卡在视窗中表现为"折叠 → 展开 → 折叠"。
  // 这里把 turnActive 的 false 沿做 12s 去抖：只有持续 12s false 才认为回合
  // 真正结束，覆盖慢速节流 / drain 间隔里的 idle 抖动。true 沿立即生效。
  const stableTurnActive = useDelayedFalse(
    turnActive,
    STREAMING_TURN_IDLE_DEBOUNCE_MS,
  );
  const keepExpandedDuringTurn =
    stableTurnActive && message.role === 'assistant' && !isReasoningMessage;
  const hasCollapsibleContent = content.trim().length > 0;
  const isToolCallKind = message.kind === 'tool_call' || message.kind === 'hook';
  const isToolResultKind = message.kind === 'tool' || message.kind === 'mcp' || message.kind === 'skill';
  const isCollapsibleByBadge = isToolCallKind || isToolResultKind || message.kind === 'reasoning';
  // 关键：卡片类型判定（是否为 HTML 卡）基于 metadata.content_format，
  // 优先级：metadata.content_format > global contentFormat。
  const effectiveFormat = resolveMessageContentFormat(
    message.metadata?.['content_format'],
    contentFormat,
  );
  const isAssistantResponseBadgeMessage =
    isAssistantResponseMessage(message) && !isCollapsibleByBadge;
  const contentExceedsCollapseThreshold = hasCollapsibleContent && (
    isReasoningMessage
      ? isReasoningLong(content)
      : isGeneralMessageLong(content)
  );
  const responseCollapsedWhileStreaming =
    !forceExpanded &&
    isAssistantResponseBadgeMessage &&
    activelyStreaming &&
    effectiveFormat !== 'html' &&
    contentExceedsCollapseThreshold;
  const canCollapse =
    !forceExpanded &&
    !activelyStreaming &&
    contentExceedsCollapseThreshold;
  const [expandedOverride, setExpandedOverride] = useState<boolean | null>(() => (
    responseExpandedOverridesByMessageId.has(message.id)
      ? responseExpandedOverridesByMessageId.get(message.id)!
      : null
  ));
  const [inlineImagePreview, setInlineImagePreview] = useState<{ item: MediaItem; url: string } | null>(null);
  useEffect(() => {
    setExpandedOverride(
      responseExpandedOverridesByMessageId.has(message.id)
        ? responseExpandedOverridesByMessageId.get(message.id)!
        : null,
    );
  }, [message.id]);
  const responseCollapsedByDefault =
    isAssistantResponseBadgeMessage &&
    contentExceedsCollapseThreshold &&
    expandedOverride !== true;
  const streamingExpansionAllowed =
    streamingContent && !responseCollapsedWhileStreaming && !responseCollapsedByDefault;
  const turnExpansionAllowed =
    keepExpandedDuringTurn && !responseCollapsedByDefault;
  const expanded = responseCollapsedWhileStreaming
    ? false
    : forceExpanded ||
      streamingExpansionAllowed ||
      turnExpansionAllowed ||
      expandedOverride === true ||
      !canCollapse;
  const collapsed = responseCollapsedWhileStreaming || (canCollapse && !expanded);
  // 移除已被 MessageMedia 收集为卡片的网络媒体 markdown 引用, 避免重复展示。
  const strippedContent = useMemo(() => stripCollectedNetworkMedia(content), [content]);
  const translatedText = strictStringFromUnknown(translatedContent);
  const showingTranslation = translationVisible && translatedText.length > 0;
  // 不再在内容层面截断：完整渲染后交由 CollapsibleBody 用 max-height + mask 动画过渡，
  // 避免「全多」↔「袪断+…」间的文字跳变在手动折叠/展开时生硬。
  const visibleContent = showingTranslation ? translatedText : strippedContent;

  // ── 工具调用/思考/正式响应胶囊折叠（与 APP 端消息卡对齐） ──
  // - 工具调用 / 工具结果 / hook / mcp / skill / reasoning：支持点击胶囊折叠
  // - 正式响应流式超过阈值时才显示响应胶囊并折叠预览
  // - 流式结束后，超过 5-6 行的 reasoning 默认折叠（用 max-height 预览态）
  // - 用户一旦手动切换，记住其选择，不被流式结束事件回撤
  const responseBadgeStreamingCollapsed =
    isAssistantResponseBadgeMessage && responseCollapsedWhileStreaming;
  const responseBadgeCanToggle =
    canCollapse && isAssistantResponseBadgeMessage && !activelyStreaming;
  const shouldRenderResponseBadge =
    responseBadgeStreamingCollapsed || responseBadgeCanToggle;
  const reasoningBadgeSweeping = isActivelyStreamingReasoning;
  const badgeToggleClass =
    'oh-message-badge-toggle oh-tap-press inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm';
  const staticSweepingBadgeClass =
    'oh-message-badge-toggle is-static is-sweeping inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm';
  const badgeCanCollapse =
    isCollapsibleByBadge &&
    !activelyStreaming &&
    contentExceedsCollapseThreshold;
  const defaultBadgeCollapsed = badgeCanCollapse;
  const [badgeCollapsedOverride, setBadgeCollapsedOverride] = useState<boolean | null>(() => (
    badgeCollapsedOverridesByMessageId.has(message.id)
      ? badgeCollapsedOverridesByMessageId.get(message.id)!
      : null
  ));
  useEffect(() => {
    setBadgeCollapsedOverride(
      badgeCollapsedOverridesByMessageId.has(message.id)
        ? badgeCollapsedOverridesByMessageId.get(message.id)!
        : null,
    );
  }, [message.id]);
  const badgeCollapsed = badgeCollapsedOverride ?? defaultBadgeCollapsed;
  const bodyCollapsedByCard = !isCollapsibleByBadge && collapsed;
  const badgeBodyCollapsed =
    (badgeCanCollapse && badgeCollapsed) || bodyCollapsedByCard;
  const reasoningPreviewCollapsed =
    isReasoningMessage && badgeCanCollapse && badgeCollapsed;

  // ── 入场动画：仅首次挂载时播放，防止流式更新重播 ──
  const [shouldAnimate] = useState(() => !appearedMessageIds.has(message.id));
  const [appearanceStaggerIndex] = useState(() => (
    shouldAnimate ? reserveMessageAppearStaggerIndex() : 0
  ));
  useEffect(() => {
    if (shouldAnimate) {
      trackMessageAppeared(message.id);
    }
  }, [message.id, shouldAnimate]);
  const appearClass = shouldAnimate
    ? ` oh-appear-up${appearanceStaggerIndex > 0 ? ` oh-appear-stagger-${appearanceStaggerIndex}` : ''}`
    : '';

  const responseVariantIndex =
    finiteNumberOrNullFromUnknown(metadata['response_variant_index']) ??
    finiteNumberOrNullFromUnknown(metadata['responseVariantIndex']) ??
    0;
  const scrollableCollapsedBody =
    canCollapse ||
    badgeCanCollapse ||
    responseBadgeCanToggle ||
    responseCollapsedWhileStreaming;
  const collapsedBodyKindKey = isAssistantResponseBadgeMessage
    ? 'response'
    : isCollapsibleByBadge
      ? `badge:${message.kind}`
      : `message:${message.role}:${message.kind}`;
  const collapsedBodyContentKey = activelyStreaming || recentlyUpdatedContent
    ? 'streaming'
    : `${visibleContent.length}|${boundedFnv1aHashBase36(visibleContent)}`;
  const collapsedBodyScrollStateKey = scrollableCollapsedBody
    ? [
        message.id,
        collapsedBodyKindKey,
        responseVariantIndex,
        effectiveFormat,
        showRawContent ? 'raw' : 'rendered',
        showingTranslation ? 'translation' : 'source',
        collapsedBodyContentKey,
      ].join('|')
    : undefined;
  const textActionFallbackFormat = textActionContentFormat ?? contentFormat;
  const textFeatureFormat = isUserBubble || isReasoningMessage
    ? resolveMessageContentFormat(message.metadata?.['content_format'], 'markdown')
    : resolveMessageContentFormat(
      message.metadata?.['content_format'],
      textActionFallbackFormat,
    );
  const supportsTextActions =
    textFeatureFormat === 'markdown' || textFeatureFormat === 'plain_text';
  const supportsRenderedSourceToggle =
    !goalMessageView &&
    (effectiveFormat === 'html' || effectiveFormat === 'markdown');
  const contentLooksHtml = looksLikeRenderableHtml(visibleContent);
  const renderedBodyContent = useMemo(() => {
    if (!badgeBodyCollapsed || activelyStreaming || contentLooksHtml) {
      return visibleContent;
    }
    return truncateEndText(
      visibleContent,
      COLLAPSED_RICH_BODY_PREVIEW_MAX_CHARS,
    );
  }, [activelyStreaming, badgeBodyCollapsed, contentLooksHtml, visibleContent]);
  const htmlRenderableMessage =
    !isUserBubble &&
    !useToolBody &&
    !useStructuredToolBody &&
    message.kind !== 'reasoning' &&
    message.kind !== 'file_mutation_summary' &&
    contentLooksHtml &&
    (effectiveFormat === 'html' || effectiveFormat === 'markdown');
  const textActionsSupported = supportsTextActions && !htmlRenderableMessage;
  const canOpenHtmlInBrowser = effectiveFormat === 'html' && contentLooksHtml;
  useEffect(() => {
    if (!supportsRenderedSourceToggle && showRawContent) {
      setShowRawContent(false);
    }
  }, [showRawContent, supportsRenderedSourceToggle]);
  const ttsPlaying = readAloudPlaying;
  const hasMultimediaContent = useMemo(() => messageHasMultimedia(message), [message]);
  const isFormalAssistantResponse = isFormalAssistantResponseMessage(message);
  const directKbReferenceMetadata = useMemo(
    () =>
      !isUserBubble &&
      isFormalAssistantResponse &&
      !activelyStreaming &&
      knowledgeBaseMetadataHasReferences(kbMetadata)
        ? knowledgeBaseMetadataUsedByAnswer(kbMetadata, content)
        : null,
    [isUserBubble, isFormalAssistantResponse, activelyStreaming, kbMetadata, content],
  );
  const associatedKbFallbackMetadata = useMemo(
    () =>
      !isUserBubble &&
      isFormalAssistantResponse &&
      !activelyStreaming &&
      knowledgeBaseMetadataHasReferences(associatedKnowledgeBaseMetadata)
        ? knowledgeBaseMetadataUsedByAnswer(associatedKnowledgeBaseMetadata, content)
        : null,
    [isUserBubble, isFormalAssistantResponse, activelyStreaming, associatedKnowledgeBaseMetadata, content],
  );
  const associatedKbReferenceMetadata =
    directKbReferenceMetadata ?? associatedKbFallbackMetadata;
  const knowledgeBaseDialogMetadata = isUserBubble
    ? kbMetadata
    : associatedKbReferenceMetadata;
  const textActionKindSupported =
    !goalMessageView &&
    (isUserBubble || message.kind === 'reasoning' || isFormalAssistantResponse);
  const textMessageActionSupported =
    textActionKindSupported &&
    !activelyStreaming &&
    !hasMultimediaContent &&
    textActionsSupported &&
    content.trim().length > 0;
  const ttsUnsupported = !textMessageActionSupported;
  const canReadMessage = (
    readAloudEnabled &&
    Boolean(onToggleReadAloud) &&
    !ttsUnsupported
  );
  const canTranslateMessage =
    translationEnabled &&
    Boolean(onToggleTranslation) &&
    textMessageActionSupported;
  const currentFeedback = messageFeedbackValue(message);
  const canFeedbackMessage =
    feedbackEnabled &&
    Boolean(onSetFeedback) &&
    (isUserBubble || (isFormalAssistantResponse && !activelyStreaming));
  const canRegenerateMessage =
    regenerationEnabled &&
    Boolean(onRegenerate) &&
    !goalMessageView &&
    isFormalAssistantResponse &&
    !activelyStreaming;
  const hasAnyAction = Boolean(
    onCopy ||
    canReadMessage ||
    canTranslateMessage ||
    canFeedbackMessage ||
    canRegenerateMessage ||
    onDelete ||
    onDeleteAfter ||
    onEdit ||
    onAudit ||
    onFork,
  );
  const actionsVisible = hasAnyAction && active;
  const actionPanelMotion = useDelayedVisibility({ initiallyOpen: actionsVisible });
  useLayoutEffect(() => {
    if (actionsVisible) {
      actionPanelMotion.show();
    } else {
      actionPanelMotion.hide();
    }
  }, [actionsVisible, actionPanelMotion.hide, actionPanelMotion.show]);
  const renderActionPanel = actionPanelMotion.visible;
  const actionPanelInteractive = actionsVisible && !actionPanelMotion.closing;
  const isHtmlAssistantCard =
    htmlRenderableMessage ||
    (!isUserBubble &&
      !useToolBody &&
      !useStructuredToolBody &&
      message.kind !== 'reasoning' &&
      message.kind !== 'file_mutation_summary' &&
      effectiveFormat === 'html');
  const isMachineExpertRequestCard = machineExpertRequestView != null;
  const isWebReverseRequestCard = webReverseRequestView != null;
  const isAndroidReverseRequestCard = androidReverseRequestView != null;
  const isExpertRequestCard =
    isMachineExpertRequestCard ||
    isWebReverseRequestCard ||
    isAndroidReverseRequestCard;
  const isWideSystemCard =
    useToolBody ||
    message.kind === 'reasoning' ||
    message.kind === 'system' ||
    message.role === 'system' ||
    message.role === 'tool';
  const bubbleMaxWidth = isWideSystemCard
    ? messageBubbleMaxWidth('wideSystem')
    : isHtmlAssistantCard
      ? messageBubbleMaxWidth('htmlAssistant')
      : isExpertRequestCard
      ? messageBubbleMaxWidth('expertRequest')
      : isUserBubble
      ? messageBubbleMaxWidth('user')
      : messageBubbleMaxWidth('assistant');
  const contextChips = [
    ...messageContextChips(message),
    ...(isUserBubble && knowledgeBaseHasReferences(message)
      ? [
        {
          key: 'knowledge-base',
          icon: 'knowledge' as const,
          label: kbTokenEstimate == null
            ? t('message.context.knowledgeBaseHits', `知识库 ${kbResults.length} 条`).replace('{count}', String(kbResults.length))
            : t('message.context.knowledgeBaseHitsTokens', `知识库 · ${kbResults.length} 条 · ${Math.round(kbTokenEstimate).toLocaleString()} tokens`)
              .replace('{count}', String(kbResults.length))
              .replace('{tokens}', Math.round(kbTokenEstimate).toLocaleString()),
          tone: 'knowledge' as const,
          onClick: () => setKnowledgeBaseDialogOpen(true),
        },
      ]
      : []),
  ];
  const plainRoleMeta = isPlainConversationMessage(message)
    ? ''
    : `${roleLabel(message.role)}${
        message.kind &&
        message.kind !== 'text' &&
        message.kind !== message.role
          ? ` · ${message.kind}`
          : ''
      }`;
  const shouldRenderHeader =
    style.badge || shouldRenderResponseBadge || Boolean(plainRoleMeta);
  const selectedInfoChips = selectedMessageInfoChips(
    message,
    associatedKbReferenceMetadata,
    () => setKnowledgeBaseDialogOpen(true),
  );
  const media = sessionId ? (
    <MessageMedia
      message={message}
      sessionId={sessionId}
      presentation={isUserBubble ? 'attachmentList' : 'preview'}
    />
  ) : null;
  const sizeMotionSignal = `${messageSizeMotionSignal(message)}|raw:${showRawContent ? 1 : 0}|tts:${ttsPlaying ? 1 : 0}|translated:${showingTranslation ? 1 : 0}:${visibleContent.length}|expanded:${expanded ? 1 : 0}|streaming:${streamingContent ? 1 : 0}|badgeCollapsed:${badgeCollapsed ? 1 : 0}`;
  // 正文卡片只承接折叠 / 展开 / 原始内容切换这类语义级尺寸变化。
  // 操作面板使用自己的布局槽动画，避免裁剪已加载的媒体节点。
  // 流式正文只做文本 reveal，不再跑高频高度 FLIP；表格/代码块追加时
  // 反复裁切 Markdown 容器会形成肉眼可见闪烁。
  const cardRef = useMessageSizeMotion(
    sizeMotionSignal,
    !reduceMotion &&
      !streamingContent &&
      !keepExpandedDuringTurn &&
      !isHtmlAssistantCard,
  );
  const cardPointerDownRef = useRef<{ x: number; y: number; at: number } | null>(
    null,
  );

  const toggleBadgeCollapsed = useCallback(() => {
    setBadgeCollapsedOverride((current) => {
      const next = current == null ? !defaultBadgeCollapsed : !current;
      rememberMessageUiState(
        badgeCollapsedOverridesByMessageId,
        message.id,
        next,
      );
      return next;
    });
  }, [defaultBadgeCollapsed, message.id]);

  const handleBadgeToggle = useCallback((e: Event) => {
    e.stopPropagation();
    toggleBadgeCollapsed();
  }, [toggleBadgeCollapsed]);

  const toggleResponseExpanded = useCallback(() => {
    const next = !expanded;
    if (!next) {
      resetCollapsedBodyScrollTop(collapsedBodyScrollStateKey);
    }
    rememberMessageUiState(
      responseExpandedOverridesByMessageId,
      message.id,
      next,
    );
    setExpandedOverride(next);
  }, [collapsedBodyScrollStateKey, expanded, message.id]);

  return (
    <>
      <div class={`oh-message-card-frame ${isUserBubble ? 'is-user' : 'is-other'}`}>
        <div
          ref={cardRef}
          class="oh-message-card-body-motion"
          style={{ transformOrigin: isUserBubble ? 'right top' : 'left top' }}
        >
          {isUserBubble ? media : null}
          <article
            class={`oh-message-card ${isUserBubble ? 'is-user' : 'is-other'} ${isWideSystemCard ? 'is-wide' : 'is-plain'} ${isReasoningMessage ? 'is-reasoning' : ''} ${isFormalAssistantResponse ? 'is-formal-response' : ''} ${isExpertRequestCard ? 'is-expert-request' : ''} ${isMachineExpertRequestCard ? 'is-machine-request' : ''} ${isWebReverseRequestCard ? 'is-web-reverse-request' : ''} ${isAndroidReverseRequestCard ? 'is-android-reverse-request' : ''} ${visuallyStreamingContent ? 'is-streaming-now' : ''} rounded-m3-md p-4${appearClass}`}
            style={{
              display: 'block',
              width: isHtmlAssistantCard ? bubbleMaxWidth : 'fit-content',
              maxWidth: bubbleMaxWidth,
              marginLeft: isUserBubble ? 'auto' : '0',
              marginRight: isUserBubble ? '0' : 'auto',
              background: style.background,
              color: style.color,
              boxShadow: style.shadow ?? (style.border ? 'none' : 'var(--m3-elev-1)'),
              border: style.border,
              cursor: hasAnyAction ? 'pointer' : 'default',
              overflowWrap: 'anywhere',
              transition: 'box-shadow 220ms ease-out, border-color 220ms ease-out',
            }}
            onPointerDown={(ev) => {
              if (!hasAnyAction) return;
              const target = ev.target as HTMLElement;
              if (
                target.closest(MESSAGE_CARD_INTERACTIVE_TARGET_SELECTOR)
              ) {
                cardPointerDownRef.current = null;
                return;
              }
              if (ev.button !== 0) {
                cardPointerDownRef.current = null;
                return;
              }
              cardPointerDownRef.current = {
                x: ev.clientX,
                y: ev.clientY,
                at: typeof performance !== 'undefined' ? performance.now() : Date.now(),
              };
            }}
            onClick={(ev) => {
              if (!hasAnyAction) return;
              const target = ev.target as HTMLElement;
              if (
                target.closest(MESSAGE_CARD_INTERACTIVE_TARGET_SELECTOR)
              ) {
                return;
              }
              // 卡片左上方折叠胶囊整体（含胶囊容器留白）不参与
              // 选中切换，只处理胶囊自身的展开/折叠。胶囊点击通过
              // handleBadgeToggle 的 stopPropagation 已经吞掉，但胶囊周围的
              // 容器 padding/margin 仍可能命中 article onClick，这里再补一刀。
              if (target.closest('.oh-message-badge-toggle')) return;
              // 点击图片时打开预览而非切换 selection。
              if (target.tagName === 'IMG' || target.closest('img')) {
                const img = (target.tagName === 'IMG' ? target : target.closest('img')) as HTMLImageElement | null;
                if (img?.src) {
                  ev.stopPropagation();
                  const src = img.src;
                  const alt = img.alt || '';
                  // 从 URL 中提取文件名用于展示。
                  let name = alt;
                  if (!name) {
                    try {
                      const pathname = new URL(src).pathname;
                      const lastSlash = pathname.lastIndexOf('/');
                      name = lastSlash >= 0 ? decodeURIComponent(pathname.slice(lastSlash + 1)) : 'image';
                    } catch {
                      name = 'image';
                    }
                  }
                  setInlineImagePreview({
                    item: { path: src, name, kind: 'image' },
                    url: src,
                  });
                  return;
                }
              }
              // 双击代码块选中文本时也不切换。
              const sel = typeof window !== 'undefined' ? window.getSelection() : null;
              if (sel && sel.toString().length > 0) return;
              const pointerDown = cardPointerDownRef.current;
              cardPointerDownRef.current = null;
              if (pointerDown != null) {
                const now = typeof performance !== 'undefined'
                  ? performance.now()
                  : Date.now();
                const elapsed = now - pointerDown.at;
                const movement = Math.hypot(
                  ev.clientX - pointerDown.x,
                  ev.clientY - pointerDown.y,
                );
                if (
                  elapsed > MESSAGE_CARD_TAP_MAX_MS ||
                  movement > MESSAGE_CARD_TAP_MAX_DISTANCE_PX
                ) {
                  return;
                }
              }
              onActiveChange?.(message, !active);
            }}
          >
      {shouldRenderHeader ? (
        <header class="oh-message-card-header flex items-center gap-3 text-xs mb-2 opacity-90">
          <span class="oh-message-card-meta flex items-center gap-2 min-w-0">
            {style.badge ? (
              badgeCanCollapse ? (
                <button
                  type="button"
                  class={`${badgeToggleClass}${reasoningBadgeSweeping ? ' is-sweeping' : ''}`}
                  onClick={handleBadgeToggle}
                  aria-expanded={!badgeCollapsed ? 'true' : 'false'}
                  title={badgeCollapsed
                    ? t('detail.tool.body.expand', '展开全部')
                    : t('detail.tool.body.collapse', '折叠')}
                >
                  <span class="oh-message-kind-icon" aria-hidden>
                    <MessageIcon name={style.icon} size={14} />
                  </span>
                  <span>{style.label}</span>
                  <span
                    class="oh-badge-chevron"
                    aria-hidden
                    style={{
                      display: 'inline-flex',
                      transition: reduceMotion ? 'none' : 'transform 220ms cubic-bezier(0.2, 0, 0, 1)',
                      transform: badgeCollapsed ? 'rotate(0deg)' : 'rotate(180deg)',
                    }}
                  >
                    <MessageIcon name="chevronDown" size={12} />
                  </span>
                </button>
              ) : (
                <span
                  class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
                  style={{
                    background: 'color-mix(in srgb, currentColor 14%, transparent)',
                  }}
                >
                  <span class="oh-message-kind-icon" aria-hidden>
                    <MessageIcon name={style.icon} size={14} />
                  </span>
                  <span>{style.label}</span>
                </span>
              )
            ) : shouldRenderResponseBadge ? (
              responseBadgeCanToggle ? (
                <button
                  type="button"
                  class={badgeToggleClass}
                  onClick={(event) => {
                    event.stopPropagation();
                    toggleResponseExpanded();
                  }}
                  aria-expanded={expanded ? 'true' : 'false'}
                  title={collapsed
                    ? t('detail.tool.body.expand', '展开全部')
                    : t('detail.tool.body.collapse', '折叠')}
                >
                  <span class="oh-message-kind-icon" aria-hidden>
                    <MessageIcon name="assistant" size={14} />
                  </span>
                  <span>{t('detail.kind.response', '响应')}</span>
                  <span
                    class="oh-badge-chevron"
                    aria-hidden
                    style={{
                      display: 'inline-flex',
                      transition: reduceMotion ? 'none' : 'transform 220ms cubic-bezier(0.2, 0, 0, 1)',
                      transform: collapsed ? 'rotate(0deg)' : 'rotate(180deg)',
                    }}
                  >
                    <MessageIcon name="chevronDown" size={12} />
                  </span>
                </button>
              ) : (
                <span
                  class={staticSweepingBadgeClass}
                  aria-busy="true"
                  title={t('detail.phase.streaming', 'Streaming')}
                >
                  <span class="oh-message-kind-icon" aria-hidden>
                    <MessageIcon name="assistant" size={14} />
                  </span>
                  <span>{t('detail.kind.response', '响应')}</span>
                </span>
              )
            ) : (
              <span class="opacity-90">{plainRoleMeta}</span>
            )}
          </span>
        </header>
      ) : null}
      {!isUserBubble && contextChips.length > 0 ? (
        <div class={`oh-message-context-capsules ${isUserBubble ? 'is-user' : 'is-other'}`}>
          {contextChips.map((chip) => <MessageContextCapsule key={chip.key} chip={chip} />)}
        </div>
      ) : null}
      <MessageToolMeta message={message} />
      <ReasoningCollapsibleBody
        collapsed={badgeBodyCollapsed}
        scrollableCollapsed={scrollableCollapsedBody}
        scrollStateKey={collapsedBodyScrollStateKey}
        previewMaxHeight={
          isReasoningMessage || (isCollapsibleByBadge && badgeCollapsed)
            ? REASONING_PREVIEW_MAX_HEIGHT_PX
            : RESPONSE_PREVIEW_MAX_HEIGHT_PX
        }
        fadeBackground={style.background}
      >
        {message.kind === 'file_mutation_summary' ? (
          <FileMutationSummaryCard message={message} />
        ) : useStructuredToolBody ? (
          <ToolExecutionCard message={message} autoFollow={streamingContent || stableTurnActive} />
        ) : useToolBody ? (
          content.length > 0 ? <ToolResultBody content={content} autoFollow={streamingContent || stableTurnActive} /> : null
        ) : goalMessageView ? (
          <GoalMessageBody view={goalMessageView} />
        ) : machineExpertRequestView ? (
          <MachineExpertRequestBody view={machineExpertRequestView} />
        ) : webReverseRequestView ? (
          <WebReverseRequestBody view={webReverseRequestView} />
        ) : androidReverseRequestView ? (
          <AndroidReverseRequestBody view={androidReverseRequestView} />
        ) : (
          // 思考卡在流式阶段强制使用纯文本，避免 Markdown/代码块逐 token
          // 成型时反复重排，把下方 pending tool-call 卡片顶上顶下。流式结束
          // 后再切回 Markdown 渲染；若内容超出 5-6 行，外层保持 142px 预览态。
          isActivelyStreamingReasoning ||
          responseCollapsedWhileStreaming ||
          (activelyStreaming && effectiveFormat === 'plain_text') ? (
            <StreamingPlainTextReveal
              content={renderedBodyContent}
              streaming={!reasoningPreviewCollapsed}
              reduceMotion={reduceMotion}
              mono={style.mono === true}
            />
          ) : (
            <StreamingMarkdownReveal
              key={badgeBodyCollapsed ? 'collapsed-preview' : 'expanded-body'}
              content={renderedBodyContent}
              streaming={streamingContent && !isUserBubble}
              reduceMotion={reduceMotion}
              raw={
                showRawContent ||
                (style.mono === true && effectiveFormat === 'plain_text')
              }
              mono={showRawContent || style.mono === true}
              format={
                isUserBubble || useToolBody
                  ? 'markdown'
                  : message.kind === 'reasoning'
                    ? (showRawContent ? 'plain_text' : 'markdown')
                    : effectiveFormat
              }
              htmlFallback={contentHtmlFallback}
              deferInitialRender={!shouldAnimate}
            />
          )
        )}
        {!isUserBubble &&
          !useStructuredToolBody &&
          !useToolBody &&
          message.kind !== 'file_mutation_summary' &&
          activelyStreaming ? (
          <TypewriterCaret />
        ) : null}
      </ReasoningCollapsibleBody>
      {associatedKbReferenceMetadata ? (
        <KnowledgeBaseCitationRail
          metadata={associatedKbReferenceMetadata}
          onOpen={() => setKnowledgeBaseDialogOpen(true)}
        />
      ) : null}
      {isUserBubble && contextChips.length > 0 ? (
        <div class="oh-message-context-capsules is-user is-after-content">
          {contextChips.map((chip) => <MessageContextCapsule key={chip.key} chip={chip} />)}
        </div>
      ) : null}
      {!isUserBubble ? media : null}
            <MediaGeneratingPlaceholderTransition
              mode={inlineCreationMode}
              className="mt-3"
            />
          </article>
        </div>
        {renderActionPanel ? (
          <div
            class={`oh-message-selected-panel-slot ${isUserBubble ? 'is-user' : 'is-other'} ${actionPanelInteractive ? 'is-visible' : 'is-hidden'}`}
            data-message-action-panel="true"
            aria-hidden={actionPanelInteractive ? 'false' : 'true'}
            onPointerDown={(event) => {
              event.stopPropagation();
            }}
            onClick={(event) => {
              event.stopPropagation();
            }}
            style={{
              width: '100%',
            }}
          >
            <div class="oh-message-selected-panel-clip">
              <div class={`oh-message-selected-panel ${isUserBubble ? 'is-user' : 'is-other'}`}>
                <div class="oh-message-action-row">
                  {onCopy ? (
                    <ActionBtn
                      icon="copy"
                      label={t('common.copy')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onCopy(message)}
                    />
                  ) : null}
                  {canReadMessage ? (
                    <ActionBtn
                      icon={ttsPlaying ? 'stop' : 'speech'}
                      label={ttsPlaying
                        ? t('message.tts.stop', '停止')
                        : t('message.tts.read', '朗读')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onToggleReadAloud?.(message)}
                    />
                  ) : null}
                  {canTranslateMessage ? (
                    <ActionBtn
                      icon={translationLoading ? 'refresh' : 'translate'}
                      label={translationLoading
                        ? t('message.translating', '翻译中')
                        : showingTranslation
                        ? t('message.showOriginal', '原文')
                        : t('message.translate', '翻译')}
                      disabled={!actionPanelInteractive || translationLoading}
                      selected={showingTranslation}
                      busy={translationLoading}
                      onClick={() => onToggleTranslation?.(message)}
                    />
                  ) : null}
                  {canFeedbackMessage ? (
                    <ActionBtn
                      icon="thumbUp"
                      label={t('message.feedback.like', '点赞')}
                      disabled={!actionPanelInteractive || feedbackBusy}
                      selected={currentFeedback === 'liked'}
                      tone="positive"
                      onClick={() => onSetFeedback?.(
                        message,
                        currentFeedback === 'liked' ? null : 'liked',
                      )}
                    />
                  ) : null}
                  {canFeedbackMessage ? (
                    <ActionBtn
                      icon="thumbDown"
                      label={t('message.feedback.improve', '需要改进')}
                      disabled={!actionPanelInteractive || feedbackBusy}
                      selected={currentFeedback === 'needs_improvement'}
                      tone="improvement"
                      onClick={() => onSetFeedback?.(
                        message,
                        currentFeedback === 'needs_improvement'
                          ? null
                          : 'needs_improvement',
                      )}
                    />
                  ) : null}
                  {canRegenerateMessage ? (
                    <ActionBtn
                      icon="refresh"
                      label={regenerating
                        ? t('message.regenerating', '重新生成中')
                        : t('message.regenerate', '重新生成')}
                      disabled={!actionPanelInteractive || regenerating}
                      busy={regenerating}
                      onClick={() => onRegenerate?.(message)}
                    />
                  ) : null}
                  {onEdit && message.role === 'user' ? (
                    <ActionBtn
                      icon="edit"
                      label={t('common.edit')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onEdit(message)}
                    />
                  ) : null}
                  {onAudit ? (
                    <ActionBtn
                      icon="audit"
                      label={t('common.audit')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onAudit(message)}
                    />
                  ) : null}
                  {onFork ? (
                    <ActionBtn
                      icon="fork"
                      label={t('common.fork', '派生')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onFork(message)}
                    />
                  ) : null}
                  {!goalMessageView && !isUserBubble && !useToolBody && message.kind !== 'file_mutation_summary' && supportsRenderedSourceToggle ? (
                    <ActionBtn
                      icon={showRawContent ? 'codeOff' : 'code'}
                      label={showRawContent
                        ? t('message.showRendered', '显示渲染')
                        : t('message.showRaw', '显示原始')}
                      disabled={!actionPanelInteractive}
                      onClick={() => setShowRawContent((v) => !v)}
                    />
                  ) : null}
                  {!goalMessageView && !isUserBubble && !useToolBody && message.kind !== 'reasoning' && message.kind !== 'file_mutation_summary' && canOpenHtmlInBrowser ? (
                    <ActionBtn
                      icon="globe"
                      label={t('message.openInBrowser', '浏览器打开')}
                      disabled={!actionPanelInteractive}
                      onClick={() => openHtmlInNewTab(content)}
                    />
                  ) : null}
                  {onDelete ? (
                    <ActionBtn
                      icon="trash"
                      label={t('common.delete')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onDelete(message)}
                    />
                  ) : null}
                  {onDeleteAfter ? (
                    <ActionBtn
                      icon="cascade"
                      label={t('common.deleteAfter')}
                      disabled={!actionPanelInteractive}
                      onClick={() => onDeleteAfter(message)}
                    />
                  ) : null}
                </div>
                {selectedInfoChips.length > 0 ? (
                  <div class="oh-message-selected-info-row">
                    {selectedInfoChips.map((chip) => <SelectedInfoChip key={chip.key} chip={chip} />)}
                  </div>
                ) : null}
              </div>
            </div>
          </div>
        ) : null}
      </div>
    {inlineImagePreview ? (
      <MediaPreviewDialog
        item={inlineImagePreview.item}
        url={inlineImagePreview.url}
        onClose={() => setInlineImagePreview(null)}
      />
    ) : null}
    {knowledgeBaseDialogOpen && knowledgeBaseDialogMetadata ? (
      <KnowledgeBaseRetrievalDialog
        metadata={knowledgeBaseDialogMetadata}
        onClose={() => setKnowledgeBaseDialogOpen(false)}
      />
    ) : null}
    </>
  );
}

function KnowledgeBaseCitationRail({
  metadata,
  onOpen,
}: {
  metadata: Record<string, unknown>;
  onOpen: () => void;
}) {
  const sources = knowledgeBaseCitationSources(metadata, 6);
  if (sources.length === 0) return null;
  return (
    <div class="oh-message-kb-citation-rail" aria-label={t('message.kbCitations.label', '知识库来源')}>
      {sources.map((source) => (
        <button
          key={source.key}
          type="button"
          class="oh-tap-press oh-message-kb-citation-chip"
          title={source.label}
          onClick={(event) => {
            event.stopPropagation();
            onOpen();
          }}
        >
          <span class="oh-message-kb-citation-icon" aria-hidden>
            <MessageIcon name="knowledge" size={13} />
          </span>
          <span>{source.label}</span>
        </button>
      ))}
    </div>
  );
}

const KNOWLEDGE_DIALOG_OVERLAY_Z_INDEX = 1400;
const KNOWLEDGE_DETAIL_DIALOG_OVERLAY_Z_INDEX = 1460;
const KNOWLEDGE_DIALOG_OVERLAY_BLUR_PX = 10;
const KNOWLEDGE_DIALOG_OVERLAY_BACKGROUND =
  'color-mix(in srgb, #000 42%, transparent)';
const KNOWLEDGE_DETAIL_DIALOG_OVERLAY_BACKGROUND =
  'color-mix(in srgb, #000 36%, transparent)';

const KNOWLEDGE_DIALOG_FRAME_APPEARANCE = createStandardDialogFrameAppearance({
  overlayClassName: 'oh-kb-dialog-backdrop',
  overlay: {
    background: KNOWLEDGE_DIALOG_OVERLAY_BACKGROUND,
    blurPx: KNOWLEDGE_DIALOG_OVERLAY_BLUR_PX,
    zIndex: KNOWLEDGE_DIALOG_OVERLAY_Z_INDEX,
  },
  panelClassName: 'oh-kb-dialog-card',
  panelBorder: 'outlineVariant',
});

const KNOWLEDGE_DETAIL_DIALOG_FRAME_APPEARANCE = createStandardDialogFrameAppearance({
  overlayClassName: 'oh-kb-dialog-backdrop is-nested',
  overlay: {
    background: KNOWLEDGE_DETAIL_DIALOG_OVERLAY_BACKGROUND,
    blurPx: KNOWLEDGE_DIALOG_OVERLAY_BLUR_PX,
    zIndex: KNOWLEDGE_DETAIL_DIALOG_OVERLAY_Z_INDEX,
  },
  panelClassName: 'oh-kb-dialog-card oh-kb-dialog-card-detail',
  panelBorder: 'outlineVariant',
});

function KnowledgeBaseRetrievalDialog({
  metadata,
  onClose,
}: {
  metadata: Record<string, unknown>;
  onClose: () => void;
}) {
  const [selectedHit, setSelectedHit] = useState<Record<string, unknown> | null>(null);
  const { closing, requestClose } = useDialogExitMotion(onClose, {
    active: selectedHit == null,
  });
  const results = knowledgeBaseResults(metadata);
  const embedding = recordOrNullFromUnknown(metadata['embedding']);
  const retrieval = recordOrNullFromUnknown(metadata['retrieval']);
  const promptAppend = recordOrNullFromUnknown(metadata['prompt_append']);
  const rerank = recordOrNullFromUnknown(metadata['rerank']);
  const vectorDistribution = knowledgeBaseVectorDistribution(metadata);
  const contextContent = knowledgeBaseContextContent(metadata);
  const query = strictStringFromUnknown(metadata['query']);
  const status = strictStringFromUnknown(metadata['status']) || 'unknown';
  const error = strictStringFromUnknown(metadata['error']);
  const copyJson = async () => {
    const ok = await copyTextToClipboard(JSON.stringify(metadata, null, 2));
    showSnackbar(ok ? t('detail.copy.ok', '已复制') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
  };
  const copyContext = async () => {
    const ok = await copyTextToClipboard(contextContent);
    showSnackbar(ok ? t('detail.copy.ok', '已复制') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
  };
  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...KNOWLEDGE_DIALOG_FRAME_APPEARANCE}
      ariaLabel={t('message.kbDialog.title', '引用知识库详情')}
    >
      <header class="oh-kb-dialog-header">
        <span class="oh-kb-dialog-icon" aria-hidden>
          <MessageIcon name="knowledge" size={18} />
        </span>
        <div class="min-w-0 flex-1">
          <h3>{t('message.kbDialog.title', '引用知识库详情')}</h3>
          <p>{results.length} {t('message.kbDialog.hitUnit', '条命中')} · {status}</p>
        </div>
        <DialogCloseButton
          onClick={requestClose}
          label={t('common.close', '关闭')}
          className="oh-kb-dialog-close oh-tap-press"
          iconSize={18}
        />
      </header>
      <div class="oh-kb-dialog-body">
        <KnowledgeBaseDialogSection title={t('message.kbDialog.query', '原始 query')}>
          <pre class="oh-kb-dialog-pre">{query || '—'}</pre>
          {error ? <p class="oh-kb-dialog-error">{error}</p> : null}
        </KnowledgeBaseDialogSection>
        <div class="oh-kb-dialog-grid">
          <KnowledgeBaseDialogSection title={t('message.kbDialog.embedding', 'Embedding')}>
            <KbKv label="provider_config_id" value={embedding?.['provider_config_id']} />
            <KbKv label="model_id" value={embedding?.['model_id']} />
            <KbKv label="dimensions" value={embedding?.['dimensions']} />
            <KbKv label="duration_ms" value={embedding?.['duration_ms']} />
          </KnowledgeBaseDialogSection>
          <KnowledgeBaseDialogSection title={t('message.kbDialog.retrieval', '检索参数')}>
            <KbKv label="duration_ms" value={retrieval?.['duration_ms']} />
            <KbKv label="top_n" value={retrieval?.['top_n']} />
            <KbKv label="top_k" value={retrieval?.['top_k']} />
            <KbKv label="min_similarity" value={retrieval?.['min_similarity']} />
          </KnowledgeBaseDialogSection>
          <KnowledgeBaseDialogSection title={t('message.kbDialog.promptAppend', 'Prompt 追加')}>
            <KbKv label="chunk_count" value={promptAppend?.['chunk_count']} />
            <KbKv label="token_estimate" value={promptAppend?.['token_estimate']} />
            <KbKv label="content_hash" value={promptAppend?.['content_hash']} />
          </KnowledgeBaseDialogSection>
        </div>
        <KnowledgeBaseDialogSection title={t('message.kbDialog.rerank', '重排序')}>
          {rerank ? (
            <div class="oh-kb-rerank-grid">
              <KbKv label="mode" value={rerank['mode']} />
              <KbKv label="strategy" value={rerank['strategy']} />
              <KbKv label="candidate_count" value={rerank['candidate_count']} />
              <KbKv label="rerank_input_count" value={rerank['rerank_input_count']} />
              <KbKv label="rerank_output_count" value={rerank['rerank_output_count']} />
              <KbKv label="kept_count" value={rerank['kept_count']} />
              <KbKv label="discarded_count" value={rerank['discarded_count']} />
              <KbKv label="duration_ms" value={rerank['duration_ms']} />
              <KbKv label="model_id" value={rerank['model_id']} />
              <KbKv label="error" value={rerank['error']} />
            </div>
          ) : (
            <p class="oh-kb-dialog-muted">{t('message.kbDialog.noRerank', '没有记录重排序细节。')}</p>
          )}
        </KnowledgeBaseDialogSection>
        {vectorDistribution ? (
          <KnowledgeBaseDialogSection title={t('message.kbDialog.vectorSpace', '向量空间')}>
            <KnowledgeVectorDistributionScene distribution={vectorDistribution} />
          </KnowledgeBaseDialogSection>
        ) : null}
        <KnowledgeBaseDialogSection title={t('message.kbDialog.hitsWithCount', '命中分块 ({count})').replace('{count}', String(results.length))}>
          <div class="oh-kb-hit-list">
            {results.length === 0 ? (
              <p class="oh-kb-dialog-muted">{t('message.kbDialog.noHits', '没有命中记录。')}</p>
            ) : results.map((hit, index) => (
              <button
                type="button"
                class="oh-kb-hit-card oh-tap-press"
                key={`${strictStringFromUnknown(hit['chunk_id']) || index}`}
                onClick={() => setSelectedHit(hit)}
                aria-label={t('message.kbDialog.openChunkDetail', '打开分块详情')}
              >
                <div class="oh-kb-hit-title">
                  <span>{index + 1}. {strictStringFromUnknown(hit['title']) || strictStringFromUnknown(hit['source_title']) || strictStringFromUnknown(hit['chunk_id']) || t('message.kbDialog.untitledChunk', '未命名分块')}</span>
                  <span>{finiteNumberOrNullFromUnknown(hit['score'])?.toFixed(4) ?? '—'}</span>
                </div>
                <div class="oh-kb-hit-meta">
                  <KbKv label="chunk_id" value={hit['chunk_id']} />
                  <KbKv label="source_id" value={hit['source_id']} />
                  <KbKv label="path" value={hit['path']} />
                  <KbKv label="tags" value={Array.isArray(hit['tags']) ? hit['tags'].join(', ') : hit['tags']} />
                  <KbKv label="document_time" value={hit['document_time']} />
                  <KbKv label="rerank_score" value={hit['rerank_score']} />
                  <KbKv label="tokens" value={hit['token_estimate']} />
                </div>
                {strictStringFromUnknown(hit['preview']) ? <p class="oh-kb-hit-preview">{strictStringFromUnknown(hit['preview'])}</p> : null}
              </button>
            ))}
          </div>
        </KnowledgeBaseDialogSection>
        <KnowledgeBaseDialogSection title={t('message.kbDialog.appendedContext', '实际追加上下文')}>
          <pre class="oh-kb-dialog-pre is-context">{contextContent || '—'}</pre>
        </KnowledgeBaseDialogSection>
      </div>
      <footer class="oh-kb-dialog-actions">
        <button type="button" class="oh-tap-press oh-kb-dialog-action" onClick={copyContext} disabled={!contextContent}>
          <MessageIcon name="copy" size={15} />
          {t('message.kbDialog.copyContext', '复制上下文')}
        </button>
        <button type="button" class="oh-tap-press oh-kb-dialog-action" onClick={copyJson}>
          <MessageIcon name="audit" size={15} />
          {t('message.kbDialog.copyJson', '复制 JSON')}
        </button>
      </footer>
      {selectedHit ? (
        <KnowledgeChunkDetailDialog
          hit={selectedHit}
          onClose={() => setSelectedHit(null)}
        />
      ) : null}
    </DialogFrame>
  );
}

function KnowledgeBaseDialogSection({
  title,
  children,
}: {
  title: string;
  children: ComponentChildren;
}) {
  return (
    <section class="oh-kb-dialog-section">
      <h4>{title}</h4>
      {children}
    </section>
  );
}

function KnowledgeChunkDetailDialog({
  hit,
  onClose,
}: {
  hit: Record<string, unknown>;
  onClose: () => void;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [loading, setLoading] = useState(false);
  const [source, setSource] = useState<KnowledgeSourceDto | null>(null);
  const [chunk, setChunk] = useState<KnowledgeChunkDto | null>(null);
  const [loadError, setLoadError] = useState('');
  const sourceId = strictStringFromUnknown(hit['source_id']);
  const chunkId = strictStringFromUnknown(hit['chunk_id']);
  const preview = strictStringFromUnknown(hit['content']) || strictStringFromUnknown(hit['preview']);

  useEffect(() => {
    if (!sourceId || !chunkId) {
      setSource(null);
      setChunk(null);
      setLoadError('');
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    setLoading(true);
    setLoadError('');
    fetchKnowledgeHitDetail(sourceId, chunkId, { signal: controller.signal })
      .then((payload) => {
        if (controller.signal.aborted) return;
        setSource(payload.source ?? null);
        setChunk(payload.chunk ?? null);
      })
      .catch((error) => {
        if (controller.signal.aborted) return;
        setSource(null);
        setChunk(null);
        setLoadError(knowledgeErrorMessage(error));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [sourceId, chunkId]);

  const copyChunkId = async () => {
    const text = chunk?.id || chunkId;
    if (!text) return;
    const ok = await copyTextToClipboard(text);
    showSnackbar(ok ? t('message.kbDialog.copyChunkIdOk', '已复制分块 ID。') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
  };
  const copyChunkContent = async () => {
    const text = strictStringFromUnknown(chunk?.content) || preview;
    if (!text) return;
    const ok = await copyTextToClipboard(text);
    showSnackbar(ok ? t('message.kbDialog.copyChunkContentOk', '已复制分块内容。') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
  };
  const resolvedTitle = strictStringFromUnknown(chunk?.title) || strictStringFromUnknown(hit['title']) || strictStringFromUnknown(hit['source_title']) || chunkId || t('message.kbDialog.untitledChunk', '未命名分块');
  const tags = Array.isArray(chunk?.tags)
    ? chunk.tags
    : Array.isArray(hit['tags'])
      ? hit['tags'].map((item) => strictStringFromUnknown(item)).filter(Boolean)
      : [];
  const metadata = recordOrNullFromUnknown(chunk?.metadata) ?? null;
  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...KNOWLEDGE_DETAIL_DIALOG_FRAME_APPEARANCE}
      ariaLabel={t('message.kbDialog.chunkDetailTitle', '命中分块详情')}
    >
      <header class="oh-kb-dialog-header">
        <span class="oh-kb-dialog-icon" aria-hidden>
          <MessageIcon name="knowledge" size={18} />
        </span>
        <div class="min-w-0 flex-1">
          <h3>{chunk ? t('message.kbDialog.chunkDetailTitleResolved', '分块详情') : t('message.kbDialog.chunkDetailTitle', '命中分块详情')}</h3>
          <p>{resolvedTitle}</p>
        </div>
        <DialogCloseButton
          onClick={requestClose}
          label={t('common.close', '关闭')}
          className="oh-kb-dialog-close oh-tap-press"
          iconSize={18}
        />
      </header>
      <div class="oh-kb-dialog-body">
          {loading ? (
            <div class="oh-kb-dialog-loading">
              <span aria-hidden />
              <p>{t('message.kbDialog.chunkDetailLoading', '正在加载分块详情…')}</p>
            </div>
          ) : null}
          {!loading && loadError ? (
            <p class="oh-kb-dialog-notice is-warning">
              {t('message.kbDialog.chunkDetailFallback', '未能从本地知识库恢复完整分块，下面展示消息元数据中保留的命中信息。')}
              <span>{loadError}</span>
            </p>
          ) : null}
          <KnowledgeBaseDialogSection title={t('message.kbDialog.retrievalHit', '检索命中')}>
            <div class="oh-kb-rerank-grid">
              <KbKv label="score" value={hit['score']} />
              <KbKv label="rerank_score" value={hit['rerank_score']} />
              <KbKv label="final_score" value={hit['final_score']} />
              <KbKv label="time_field" value={hit['time_field']} />
              <KbKv label="path" value={hit['path']} />
              <KbKv label="document_time" value={hit['document_time']} />
              <KbKv label="updated_at" value={hit['updated_at']} />
            </div>
          </KnowledgeBaseDialogSection>
          <KnowledgeBaseDialogSection title={t('message.kbDialog.overview', '基础信息')}>
            <div class="oh-kb-rerank-grid">
              <KbKv label="chunk_id" value={chunk?.id ?? hit['chunk_id']} />
              <KbKv label="source_id" value={source?.id ?? hit['source_id']} />
              <KbKv label="source_title" value={source?.title ?? hit['source_title']} />
              <KbKv label="source_kind" value={source?.kind ?? hit['source_kind']} />
              <KbKv label="chunk_index" value={chunk?.chunk_index ?? hit['chunk_index']} />
              <KbKv label="parent_chunk_id" value={chunk?.parent_chunk_id} />
              <KbKv label="title" value={chunk?.title ?? hit['title']} />
              <KbKv label="heading_path" value={chunk?.heading_path ?? hit['heading_path']} />
              <KbKv label="content_hash" value={chunk?.content_hash ?? hit['content_hash']} />
            </div>
          </KnowledgeBaseDialogSection>
          <KnowledgeBaseDialogSection title={t('message.kbDialog.statsLocation', '统计与定位')}>
            <div class="oh-kb-rerank-grid">
              <KbKv label="char_count" value={chunk?.char_count} />
              <KbKv label="token_estimate" value={chunk?.token_estimate ?? hit['token_estimate']} />
              <KbKv label="start_offset" value={chunk?.start_offset} />
              <KbKv label="end_offset" value={chunk?.end_offset} />
              <KbKv label="page_number" value={chunk?.page_number} />
              <KbKv label="document_time" value={chunk?.document_time ?? hit['document_time']} />
              <KbKv label="created_at" value={chunk?.created_at} />
              <KbKv label="updated_at" value={chunk?.updated_at ?? hit['updated_at']} />
            </div>
          </KnowledgeBaseDialogSection>
          <KnowledgeBaseDialogSection title={t('message.kbDialog.tags', '标签')}>
            {tags.length === 0 ? (
              <p class="oh-kb-dialog-muted">{t('message.kbDialog.noTags', '没有标签。')}</p>
            ) : (
              <div class="oh-kb-tag-list">
                {tags.map((tag) => <span key={tag}>{tag}</span>)}
              </div>
            )}
          </KnowledgeBaseDialogSection>
          {metadata ? (
            <KnowledgeBaseDialogSection title={t('message.kbDialog.metadata', '元数据')}>
              <pre class="oh-kb-dialog-pre is-json">{JSON.stringify(metadata, null, 2)}</pre>
            </KnowledgeBaseDialogSection>
          ) : null}
          <KnowledgeBaseDialogSection title={chunk ? t('message.kbDialog.fullContent', '完整内容') : t('message.kbDialog.hitPreview', '命中预览')}>
            <pre class="oh-kb-dialog-pre is-context">{strictStringFromUnknown(chunk?.content) || preview || '—'}</pre>
          </KnowledgeBaseDialogSection>
          {!chunk ? (
            <KnowledgeBaseDialogSection title={t('message.kbDialog.rawHitMetadata', '原始命中元数据')}>
              <pre class="oh-kb-dialog-pre is-json">{JSON.stringify(hit, null, 2)}</pre>
            </KnowledgeBaseDialogSection>
          ) : null}
      </div>
      <footer class="oh-kb-dialog-actions">
        <button type="button" class="oh-tap-press oh-kb-dialog-action" onClick={copyChunkId} disabled={!chunkId && !chunk?.id}>
          <MessageIcon name="audit" size={15} />
          {t('message.kbDialog.copyChunkId', '复制 ID')}
        </button>
        <button type="button" class="oh-tap-press oh-kb-dialog-action" onClick={copyChunkContent} disabled={!preview && !strictStringFromUnknown(chunk?.content)}>
          <MessageIcon name="copy" size={15} />
          {t('message.kbDialog.copyChunkContent', '复制内容')}
        </button>
        <button type="button" class="oh-tap-press oh-kb-dialog-action" onClick={requestClose}>
          {t('common.close', '关闭')}
        </button>
      </footer>
    </DialogFrame>
  );
}

function knowledgeErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === 'string') return error;
  return stringifyJsonSafely(error) ?? String(error);
}

function KnowledgeVectorDistributionScene({
  distribution,
}: {
  distribution: KnowledgeVectorDistributionData;
}) {
  const sceneRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const pointerRef = useRef<{ pointerId: number; x: number; y: number; startX: number; startY: number; dragged: boolean } | null>(null);
  const pointPointerRef = useRef<{ pointerId: number; pointId: string; x: number; y: number; startX: number; startY: number; dragged: boolean } | null>(null);
  const corpusAbortRef = useRef<AbortController | null>(null);
  const [sceneSize, setSceneSize] = useState<KnowledgeVectorSceneSize>(KB_VECTOR_INITIAL_SIZE);
  const [yaw, setYaw] = useState(-0.62);
  const [pitch, setPitch] = useState(-0.34);
  const [zoom, setZoom] = useState(1);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [showCorpus, setShowCorpus] = useState(false);
  const [corpusDistribution, setCorpusDistribution] = useState<KnowledgeVectorDistributionData | null>(null);
  const [corpusLoading, setCorpusLoading] = useState(false);
  const [corpusError, setCorpusError] = useState('');
  const [visibleLimit, setVisibleLimit] = useState(KB_VECTOR_BATCH_SIZE);
  const {
    closing: pointPopoverClosing,
    requestClose: requestPointPopoverClose,
    resetClosing: resetPointPopoverClosing,
  } = useDialogExitMotion(() => setSelectedId(null), {
    active: selectedId != null,
  });

  const selectPoint = useCallback((pointId: string | null) => {
    if (pointId == null) {
      if (selectedId != null) requestPointPopoverClose();
      return;
    }
    resetPointPopoverClosing();
    setSelectedId(pointId);
  }, [requestPointPopoverClose, resetPointPopoverClosing, selectedId]);

  useLayoutEffect(() => {
    const node = sceneRef.current;
    if (!node) return;
    const measure = () => {
      const rect = node.getBoundingClientRect();
      const width = Math.max(320, Math.round(rect.width || KB_VECTOR_INITIAL_SIZE.width));
      const height = Math.max(320, Math.round(rect.height || KB_VECTOR_INITIAL_SIZE.height));
      setSceneSize((current) => (
        current.width === width && current.height === height ? current : { width, height }
      ));
    };
    measure();
    const ResizeObserverCtor = typeof ResizeObserver === 'undefined' ? null : ResizeObserver;
    if (!ResizeObserverCtor) {
      window.addEventListener('resize', measure);
      return () => window.removeEventListener('resize', measure);
    }
    const observer = new ResizeObserverCtor(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  useEffect(() => () => corpusAbortRef.current?.abort(), []);

  const visibleDistribution = useMemo(
    () => (showCorpus && corpusDistribution
      ? mergeKnowledgeVectorDistributions(distribution, corpusDistribution)
      : distribution),
    [corpusDistribution, distribution, showCorpus],
  );
  const allPoints = visibleDistribution.points;
  const axisScale = useMemo(
    () => resolveKnowledgeVectorAxisScale(sceneSize, zoom),
    [sceneSize, zoom],
  );
  const visibleKinds = useMemo(
    () => new Set(allPoints.map((point) => point.kind)),
    [allPoints],
  );

  useEffect(() => {
    const nextInitial = Math.min(KB_VECTOR_BATCH_SIZE, allPoints.length);
    setVisibleLimit(nextInitial);
    if (allPoints.length <= nextInitial) return;
    const timer = window.setInterval(() => {
      setVisibleLimit((current) => {
        const next = Math.min(allPoints.length, current + KB_VECTOR_BATCH_SIZE);
        if (next >= allPoints.length) window.clearInterval(timer);
        return next;
      });
    }, KB_VECTOR_BATCH_INTERVAL_MS);
    return () => window.clearInterval(timer);
  }, [allPoints]);

  useEffect(() => {
    if (!selectedId || allPoints.some((point) => point.id === selectedId)) return;
    resetPointPopoverClosing();
    setSelectedId(null);
  }, [allPoints, resetPointPopoverClosing, selectedId]);

  const renderedPoints = useMemo(
    () => allPoints.slice(0, Math.min(visibleLimit, allPoints.length)),
    [allPoints, visibleLimit],
  );
  const projected = useMemo(
    () => projectKnowledgeVectorPoints(renderedPoints, sceneSize, yaw, pitch, zoom),
    [renderedPoints, sceneSize, yaw, pitch, zoom],
  );
  const paintedPoints = useMemo(
    () => sortKnowledgeProjectedVectorPointsForPaint(projected),
    [projected],
  );
  const hitPoints = useMemo(
    () => sortKnowledgeProjectedVectorPointsForHit(projected),
    [projected],
  );
  const selected = allPoints.find((point) => point.id === selectedId) ?? null;
  const selectedProjected = selected
    ? projected.find((point) => point.point.id === selected.id) ?? null
    : null;
  const gridRings = useMemo(() => {
    const ringCount = Math.floor(KB_VECTOR_AXIS_EXTENT / axisScale.gridStep);
    const rings: Array<{ radius: number; path: string }> = [];
    for (let i = 1; i <= ringCount; i += 1) {
      const radius = i * axisScale.gridStep;
      if (radius <= 1.02) {
        rings.push({ radius, path: knowledgeVectorCirclePath(sceneSize, radius, yaw, pitch, zoom) });
      }
    }
    return rings;
  }, [axisScale.gridStep, pitch, sceneSize, yaw, zoom]);
  const gridSpokes = useMemo(() => {
    const spokes = zoom >= 5 ? 12 : 8;
    return Array.from({ length: spokes }).map((_, index) => {
      const angle = index * Math.PI * 2 / spokes;
      const inner = projectKnowledgeSceneCoordinate(Math.cos(angle) * 0.18, Math.sin(angle) * 0.18, 0, sceneSize, yaw, pitch, zoom);
      const outer = projectKnowledgeSceneCoordinate(Math.cos(angle), Math.sin(angle), 0, sceneSize, yaw, pitch, zoom);
      return { inner, outer };
    });
  }, [pitch, sceneSize, yaw, zoom]);

  const setClampedZoom = useCallback((next: number) => {
    setZoom((current) => {
      const value = clampNumber(next, KB_VECTOR_MIN_ZOOM, KB_VECTOR_MAX_ZOOM);
      return Math.abs(value - current) < 0.001 ? current : value;
    });
  }, []);
  const resetViewport = useCallback(() => {
    setYaw(-0.62);
    setPitch(-0.34);
    setClampedZoom(1);
  }, [setClampedZoom]);
  const loadCorpus = useCallback(() => {
    if (corpusDistribution || corpusLoading) return;
    corpusAbortRef.current?.abort();
    const controller = new AbortController();
    corpusAbortRef.current = controller;
    setCorpusLoading(true);
    setCorpusError('');
    fetchKnowledgeVectorDistribution(KNOWLEDGE_VECTOR_DEFAULT_MAX_POINTS, { signal: controller.signal })
      .then((payload) => {
        if (controller.signal.aborted) return;
        const parsed = parseKnowledgeVectorDistribution(payload.distribution);
        setCorpusDistribution(parsed);
        if (!parsed) setCorpusError(t('message.kbDialog.corpusEmpty', '没有可叠加的全量向量点。'));
      })
      .catch((error) => {
        if (!controller.signal.aborted) setCorpusError(knowledgeErrorMessage(error));
      })
      .finally(() => {
        if (!controller.signal.aborted) setCorpusLoading(false);
      });
  }, [corpusDistribution, corpusLoading]);
  const toggleCorpus = useCallback(() => {
    if (showCorpus) {
      setShowCorpus(false);
      return;
    }
    setShowCorpus(true);
    loadCorpus();
  }, [loadCorpus, showCorpus]);

  const rotateViewportByPointerDelta = useCallback((dx: number, dy: number) => {
    setYaw((value) => value + dx * 0.010);
    setPitch((value) => clampNumber(value + dy * 0.008, -1.18, 1.18));
  }, []);

  const scenePointFromEvent = useCallback((event: { clientX: number; clientY: number }) => {
    const svg = svgRef.current;
    const matrix = svg?.getScreenCTM();
    if (svg && matrix) {
      try {
        const point = svg.createSVGPoint();
        point.x = event.clientX;
        point.y = event.clientY;
        const transformed = point.matrixTransform(matrix.inverse());
        return { x: transformed.x, y: transformed.y };
      } catch {
        // 矩阵换算失败时回退到下方的矩形坐标映射。
      }
    }
    const rect = sceneRef.current?.getBoundingClientRect();
    if (!rect) return null;
    const x = ((event.clientX - rect.left) / Math.max(1, rect.width)) * sceneSize.width;
    const y = ((event.clientY - rect.top) / Math.max(1, rect.height)) * sceneSize.height;
    return { x, y };
  }, [sceneSize]);

  const statText = `${t('message.kbDialog.vectorProjection', '投影')} ${Math.min(visibleLimit, allPoints.length)}/${allPoints.length} ${t('message.kbDialog.points', '点')} · ${visibleDistribution.originalDimensions}D${visibleDistribution.hasMore ? ` · ${t('message.kbDialog.sampled', '已采样')}` : ''}`;
  return (
    <div
      ref={sceneRef}
      class="oh-kb-vector-scene"
      onPointerDown={(event) => {
        pointerRef.current = {
          pointerId: event.pointerId,
          x: event.clientX,
          y: event.clientY,
          startX: event.clientX,
          startY: event.clientY,
          dragged: false,
        };
        event.currentTarget.setPointerCapture(event.pointerId);
      }}
      onPointerMove={(event) => {
        const previous = pointerRef.current;
        if (!previous || previous.pointerId !== event.pointerId) return;
        const moved = Math.hypot(event.clientX - previous.startX, event.clientY - previous.startY);
        const dragged = previous.dragged || moved > KB_VECTOR_DRAG_START_PX;
        pointerRef.current = { ...previous, x: event.clientX, y: event.clientY, dragged };
        if (!dragged) return;
        const dx = event.clientX - previous.x;
        const dy = event.clientY - previous.y;
        rotateViewportByPointerDelta(dx, dy);
      }}
      onPointerUp={(event) => {
        const previous = pointerRef.current;
        pointerRef.current = null;
        if (event.currentTarget.hasPointerCapture(event.pointerId)) {
          event.currentTarget.releasePointerCapture(event.pointerId);
        }
        if (previous?.dragged) return;
        const point = scenePointFromEvent(event);
        if (!point) return;
        const nearest = nearestKnowledgeVectorPoint(projected, point);
        selectPoint(nearest?.point.id ?? null);
      }}
      onPointerCancel={(event) => {
        pointerRef.current = null;
        if (event.currentTarget.hasPointerCapture(event.pointerId)) {
          event.currentTarget.releasePointerCapture(event.pointerId);
        }
      }}
      onWheel={(event) => {
        event.preventDefault();
        const factor = Math.exp(-event.deltaY * KB_VECTOR_SCROLL_ZOOM_SENSITIVITY);
        setZoom((value) => clampNumber(value * factor, KB_VECTOR_MIN_ZOOM, KB_VECTOR_MAX_ZOOM));
      }}
    >
      <svg
        ref={svgRef}
        class="oh-kb-vector-svg"
        viewBox={`0 0 ${sceneSize.width} ${sceneSize.height}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={t('message.kbDialog.vectorSpace', '向量空间')}
      >
        <g class="oh-kb-vector-grid">
          {gridRings.map((ring) => <path key={`ring-${ring.radius}`} d={ring.path} />)}
          {gridSpokes.map((spoke, index) => (
            <line key={`spoke-${index}`} x1={spoke.inner.x} y1={spoke.inner.y} x2={spoke.outer.x} y2={spoke.outer.y} />
          ))}
        </g>
        <g class="oh-kb-vector-axes">
          {KB_VECTOR_AXIS_SPECS.map((axis) => (
            <KnowledgeVectorAxis
              key={axis.label}
              axis={axis}
              axisScale={axisScale}
              pitch={pitch}
              sceneSize={sceneSize}
              yaw={yaw}
              zoom={zoom}
            />
          ))}
        </g>
        {paintedPoints.map((item, index) => (
          <circle
            key={item.point.id}
            class={`oh-kb-vector-point is-${item.point.kind} ${selectedId === item.point.id ? 'is-selected' : ''}`}
            cx={item.x}
            cy={item.y}
            r={item.radius * (selectedId === item.point.id ? 1.22 : 1)}
            style={{ animationDelay: `${Math.min(index * 7, 640)}ms` }}
          />
        ))}
        <g class="oh-kb-vector-hit-layer">
          {hitPoints.map((item) => (
            <circle
              key={`hit-${item.point.id}`}
              class="oh-kb-vector-hit-target"
              cx={item.x}
              cy={item.y}
              r={knowledgeVectorPointHitRadius(item)}
              onPointerDown={(event) => {
                event.preventDefault();
                event.stopPropagation();
                pointPointerRef.current = {
                  pointerId: event.pointerId,
                  pointId: item.point.id,
                  x: event.clientX,
                  y: event.clientY,
                  startX: event.clientX,
                  startY: event.clientY,
                  dragged: false,
                };
                event.currentTarget.setPointerCapture(event.pointerId);
              }}
              onPointerMove={(event) => {
                const previous = pointPointerRef.current;
                if (!previous || previous.pointerId !== event.pointerId) return;
                event.preventDefault();
                event.stopPropagation();
                const moved = Math.hypot(event.clientX - previous.startX, event.clientY - previous.startY);
                const dragged = previous.dragged || moved > KB_VECTOR_DRAG_START_PX;
                pointPointerRef.current = { ...previous, x: event.clientX, y: event.clientY, dragged };
                if (!dragged) return;
                rotateViewportByPointerDelta(event.clientX - previous.x, event.clientY - previous.y);
              }}
              onPointerUp={(event) => {
                const previous = pointPointerRef.current;
                pointPointerRef.current = null;
                event.preventDefault();
                event.stopPropagation();
                if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                  event.currentTarget.releasePointerCapture(event.pointerId);
                }
                if (!previous || previous.pointerId !== event.pointerId || previous.dragged) return;
                selectPoint(previous.pointId);
              }}
              onPointerCancel={(event) => {
                pointPointerRef.current = null;
                event.stopPropagation();
                if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                  event.currentTarget.releasePointerCapture(event.pointerId);
                }
              }}
            />
          ))}
        </g>
      </svg>
      <div class="oh-kb-vector-stats" onPointerDown={(event) => event.stopPropagation()}>{statText}</div>
      <div class="oh-kb-vector-controls" onPointerDown={(event) => event.stopPropagation()}>
        <button
          type="button"
          class="oh-kb-vector-control oh-tap-press"
          onClick={() => setZoom((value) => clampNumber(value / KB_VECTOR_ZOOM_BUTTON_FACTOR, KB_VECTOR_MIN_ZOOM, KB_VECTOR_MAX_ZOOM))}
          disabled={zoom <= KB_VECTOR_MIN_ZOOM + 0.001}
          title={t('message.kbDialog.zoomOut', '缩小')}
          aria-label={t('message.kbDialog.zoomOut', '缩小')}
        >-</button>
        <span>{Math.round(zoom * 100)}% · {t('message.kbDialog.tick', '刻度')} {formatKnowledgeAxisValue(axisScale.step)}</span>
        <button
          type="button"
          class="oh-kb-vector-control oh-tap-press"
          onClick={() => setZoom((value) => clampNumber(value * KB_VECTOR_ZOOM_BUTTON_FACTOR, KB_VECTOR_MIN_ZOOM, KB_VECTOR_MAX_ZOOM))}
          disabled={zoom >= KB_VECTOR_MAX_ZOOM - 0.001}
          title={t('message.kbDialog.zoomIn', '放大')}
          aria-label={t('message.kbDialog.zoomIn', '放大')}
        >+</button>
        <button
          type="button"
          class="oh-kb-vector-control is-reset oh-tap-press"
          onClick={resetViewport}
          title={t('message.kbDialog.resetView', '重置视角')}
          aria-label={t('message.kbDialog.resetView', '重置视角')}
        >{t('message.kbDialog.resetViewShort', '重置')}</button>
      </div>
      <div class="oh-kb-vector-overlay-actions" onPointerDown={(event) => event.stopPropagation()}>
        <button type="button" class="oh-kb-dialog-action oh-tap-press" onClick={toggleCorpus}>
          {showCorpus ? t('message.kbDialog.hideCorpus', '隐藏全量') : t('message.kbDialog.overlayCorpus', '叠加全量')}
        </button>
      </div>
      {(showCorpus && (corpusLoading || corpusError || corpusDistribution)) ? (
        <div class={`oh-kb-vector-status ${corpusError ? 'is-error' : ''}`} onPointerDown={(event) => event.stopPropagation()}>
          {corpusLoading
            ? t('message.kbDialog.corpusLoading', '正在按需采样并叠加全量向量。')
            : corpusError
              ? `${t('message.kbDialog.corpusLoadFailed', '全量向量加载失败：')}${corpusError}`
              : corpusDistribution?.hasMore
                ? t('message.kbDialog.corpusSampled', '已叠加 {count} 个全量采样点；数据量较大时会采样展示以保持流畅。').replace('{count}', String(corpusDistribution.points.length))
                : t('message.kbDialog.corpusReady', '已叠加 {count} 个全量向量点。').replace('{count}', String(corpusDistribution?.points.length ?? 0))}
        </div>
      ) : null}
      <div class="oh-kb-vector-legend" aria-hidden onPointerDown={(event) => event.stopPropagation()}>
        {visibleKinds.has('corpus') ? <span><i class="is-corpus" />{t('message.kbDialog.corpus', '全量')}</span> : null}
        {visibleKinds.has('match') ? <span><i class="is-match" />{t('message.kbDialog.matches', '匹配')}</span> : null}
        {visibleKinds.has('query') ? <span><i class="is-query" />{t('message.kbDialog.queryVector', '查询')}</span> : null}
      </div>
      {selected && selectedProjected ? (
        <KnowledgeVectorPointPopover
          closing={pointPopoverClosing}
          projection={selectedProjected}
          sceneSize={sceneSize}
          onClose={requestPointPopoverClose}
        />
      ) : null}
    </div>
  );
}

function KnowledgeVectorAxis({
  axis,
  axisScale,
  pitch,
  sceneSize,
  yaw,
  zoom,
}: {
  axis: KnowledgeVectorAxisSpec;
  axisScale: KnowledgeVectorAxisScale;
  pitch: number;
  sceneSize: KnowledgeVectorSceneSize;
  yaw: number;
  zoom: number;
}) {
  const start = projectKnowledgeSceneCoordinate(-axis.x * KB_VECTOR_AXIS_EXTENT, -axis.y * KB_VECTOR_AXIS_EXTENT, -axis.z * KB_VECTOR_AXIS_EXTENT, sceneSize, yaw, pitch, zoom);
  const origin = projectKnowledgeSceneCoordinate(0, 0, 0, sceneSize, yaw, pitch, zoom);
  const end = projectKnowledgeSceneCoordinate(axis.x * KB_VECTOR_AXIS_EXTENT, axis.y * KB_VECTOR_AXIS_EXTENT, axis.z * KB_VECTOR_AXIS_EXTENT, sceneSize, yaw, pitch, zoom);
  const tickCount = Math.floor(KB_VECTOR_AXIS_EXTENT / axisScale.step);
  const ticks: Array<{ value: number; point: KnowledgeSceneProjection; major: boolean; direction: { x: number; y: number } }> = [];
  for (let index = -tickCount; index <= tickCount; index += 1) {
    if (index === 0) continue;
    const value = index * axisScale.step;
    if (Math.abs(value) > KB_VECTOR_AXIS_EXTENT + 1e-6) continue;
    const point = projectKnowledgeSceneCoordinate(axis.x * value, axis.y * value, axis.z * value, sceneSize, yaw, pitch, zoom);
    ticks.push({
      value,
      point,
      major: isKnowledgeAxisStepMultiple(value, axisScale.labelStep),
      direction: knowledgeAxisTickDirection(sceneSize, axis, value, yaw, pitch, zoom),
    });
  }
  return (
    <g class={`oh-kb-vector-axis is-${axis.label.toLowerCase()}`}>
      <line class="is-negative" x1={start.x} y1={start.y} x2={origin.x} y2={origin.y} />
      <line class="is-positive" x1={origin.x} y1={origin.y} x2={end.x} y2={end.y} />
      {ticks.map((tick) => {
        const length = tick.major ? KB_VECTOR_AXIS_TICK_SCREEN_LENGTH : KB_VECTOR_AXIS_MINOR_TICK_SCREEN_LENGTH;
        const x1 = tick.point.x - tick.direction.x * (length / 2);
        const y1 = tick.point.y - tick.direction.y * (length / 2);
        const x2 = tick.point.x + tick.direction.x * (length / 2);
        const y2 = tick.point.y + tick.direction.y * (length / 2);
        const labelX = tick.point.x + tick.direction.x * (length + 7);
        const labelY = tick.point.y + tick.direction.y * (length + 7);
        return (
          <g key={`${axis.label}-${tick.value}`} class={tick.major ? 'is-major' : 'is-minor'}>
            <line class="oh-kb-vector-axis-tick" x1={x1} y1={y1} x2={x2} y2={y2} />
            {tick.major && isKnowledgeLabelVisible(labelX, labelY, sceneSize) ? (
              <text class="oh-kb-vector-axis-tick-label" x={labelX} y={labelY}>{axis.label} {formatKnowledgeAxisValue(tick.value)}</text>
            ) : null}
          </g>
        );
      })}
      {isKnowledgeLabelVisible(end.x, end.y, sceneSize, 26) ? (
        <text class="oh-kb-vector-axis-label" x={end.x + 8} y={end.y - 8}>{axis.label}</text>
      ) : null}
    </g>
  );
}

function KnowledgeVectorPointPopover({
  closing,
  projection,
  sceneSize,
  onClose,
}: {
  closing: boolean;
  projection: KnowledgeProjectedVectorPoint;
  sceneSize: KnowledgeVectorSceneSize;
  onClose: () => void;
}) {
  const width = clampNumber(
    sceneSize.width - KB_VECTOR_POPOVER_PADDING * 2,
    180,
    Math.max(180, KB_VECTOR_POPOVER_WIDTH),
  );
  const left = clampNumber(projection.x + 14, KB_VECTOR_POPOVER_PADDING, Math.max(KB_VECTOR_POPOVER_PADDING, sceneSize.width - width - KB_VECTOR_POPOVER_PADDING));
  const top = clampNumber(projection.y - 120, KB_VECTOR_POPOVER_PADDING, Math.max(KB_VECTOR_POPOVER_PADDING, sceneSize.height - 228));
  const point = projection.point;
  return (
    <div
      class={`oh-kb-vector-popover${closing ? ' oh-menu-pop-out' : ''}`}
      style={{ left: `${left}px`, top: `${top}px`, width: `${width}px` }}
      onPointerDown={(event) => event.stopPropagation()}
      data-closing={closing ? 'true' : undefined}
    >
      <div class="oh-kb-vector-popover-head">
        <strong>{point.title || point.id}</strong>
        <DialogCloseButton
          onClick={onClose}
          label={t('common.close', '关闭')}
          disabled={closing}
          className="oh-kb-vector-popover-close oh-tap-press"
          iconSize={13}
        />
      </div>
      <em>{knowledgeVectorKindLabel(point.kind)}</em>
      <div class="oh-kb-vector-popover-metrics">
        <span>X {formatKnowledgeCoordinate(point.x)}</span>
        <span>Y {formatKnowledgeCoordinate(point.y)}</span>
        <span>Z {formatKnowledgeCoordinate(point.z)}</span>
        <span>{t('message.kbDialog.depth', '深度')} {formatKnowledgeCoordinate(projection.depth)}</span>
        {point.score != null ? <span>{t('message.kbDialog.score', '召回')} {formatKnowledgeScore(point.score)}</span> : null}
        {point.rerankScore != null ? <span>{t('message.kbDialog.rerankScore', '重排')} {formatKnowledgeScore(point.rerankScore)}</span> : null}
      </div>
      {point.preview ? <span>{point.preview}</span> : null}
      <code>{point.id}</code>
    </div>
  );
}

function projectKnowledgeVectorPoints(
  points: KnowledgeVectorDistributionPoint[],
  sceneSize: KnowledgeVectorSceneSize,
  yaw: number,
  pitch: number,
  zoom: number,
): KnowledgeProjectedVectorPoint[] {
  return points.map((point) => {
    const projected = projectKnowledgeSceneCoordinate(point.x, point.y, point.z, sceneSize, yaw, pitch, zoom);
    const baseRadius = point.kind === 'query' ? 9.2 : point.kind === 'match' ? 6.8 : 4.6;
    return {
      point,
      x: projected.x,
      y: projected.y,
      depth: projected.depth,
      perspective: projected.perspective,
      radius: baseRadius * projected.perspective,
    };
  });
}

function projectKnowledgeSceneCoordinate(
  x: number,
  y: number,
  z: number,
  sceneSize: KnowledgeVectorSceneSize,
  yaw: number,
  pitch: number,
  zoom: number,
): KnowledgeSceneProjection {
  const centerX = sceneSize.width / 2;
  const centerY = sceneSize.height / 2;
  const radius = Math.min(sceneSize.width, sceneSize.height) * 0.30 * zoom;
  const cosY = Math.cos(yaw);
  const sinY = Math.sin(yaw);
  const cosP = Math.cos(pitch);
  const sinP = Math.sin(pitch);
  const x1 = x * cosY + z * sinY;
  const z1 = -x * sinY + z * cosY;
  const y1 = y * cosP - z1 * sinP;
  const z2 = y * sinP + z1 * cosP;
  const perspective = clampNumber(1 / (1.9 - z2 * 0.46), 0.42, 1.35);
  return {
    x: centerX + x1 * radius * perspective,
    y: centerY - y1 * radius * perspective,
    depth: z2,
    perspective,
  };
}

function resolveKnowledgeVectorAxisScale(
  sceneSize: KnowledgeVectorSceneSize,
  zoom: number,
): KnowledgeVectorAxisScale {
  const baseRadius = Math.min(sceneSize.width, sceneSize.height) * 0.30;
  const pixelsPerUnit = Math.max(1, baseRadius * zoom);
  const step = closestKnowledgeAxisStep(KB_VECTOR_AXIS_TARGET_TICK_GAP / pixelsPerUnit);
  const labelStep = step <= 0.10 ? 0.20 : step <= 0.25 ? 0.50 : step;
  return { step, labelStep, gridStep: Math.max(0.10, labelStep) };
}

function closestKnowledgeAxisStep(rawStep: number): number {
  const target = clampNumber(rawStep, 0.05, 1);
  const steps = [0.05, 0.10, 0.20, 0.25, 0.50, 1.0];
  let best = steps[0];
  let bestScore = Number.POSITIVE_INFINITY;
  for (const step of steps) {
    const score = Math.abs(Math.log(target / step));
    if (score < bestScore) {
      best = step;
      bestScore = score;
    }
  }
  return best;
}

function knowledgeVectorCirclePath(
  sceneSize: KnowledgeVectorSceneSize,
  radius: number,
  yaw: number,
  pitch: number,
  zoom: number,
): string {
  const segments = 72;
  let path = '';
  for (let index = 0; index <= segments; index += 1) {
    const angle = Math.PI * 2 * index / segments;
    const projected = projectKnowledgeSceneCoordinate(Math.cos(angle) * radius, Math.sin(angle) * radius, 0, sceneSize, yaw, pitch, zoom);
    path += `${index === 0 ? 'M' : 'L'}${projected.x.toFixed(2)} ${projected.y.toFixed(2)} `;
  }
  return path.trim();
}

function nearestKnowledgeVectorPoint(
  projected: KnowledgeProjectedVectorPoint[],
  offset: { x: number; y: number },
): KnowledgeProjectedVectorPoint | null {
  let nearest: KnowledgeProjectedVectorPoint | null = null;
  let bestScore = Number.POSITIVE_INFINITY;
  for (const point of projected) {
    const distance = Math.hypot(point.x - offset.x, point.y - offset.y);
    const hitRadius = knowledgeVectorPointHitRadius(point);
    if (distance > hitRadius) continue;
    const normalizedDistance = distance / hitRadius;
    const score =
      normalizedDistance -
      knowledgeVectorPointHitPriority(point.point.kind) -
      Math.min(point.radius * 0.004, 0.05) -
      Math.max(point.depth, 0) * 0.012;
    if (score < bestScore) {
      nearest = point;
      bestScore = score;
    }
  }
  return nearest;
}

function knowledgeVectorPointHitRadius(point: KnowledgeProjectedVectorPoint): number {
  const base = Math.max(KB_VECTOR_POINT_HIT_RADIUS, point.radius + KB_VECTOR_POINT_HIT_PADDING);
  return point.point.kind === 'query'
    ? Math.max(base, KB_VECTOR_QUERY_HIT_PRIORITY_RADIUS)
    : base;
}

function knowledgeVectorPointHitPriority(kind: KnowledgeVectorDistributionPoint['kind']): number {
  switch (kind) {
    case 'query': return 0.34;
    case 'match': return 0.12;
    default: return 0;
  }
}

function knowledgeVectorPointPaintPriority(kind: KnowledgeVectorDistributionPoint['kind']): number {
  switch (kind) {
    case 'query': return 3;
    case 'match': return 2;
    default: return 1;
  }
}

function sortKnowledgeProjectedVectorPointsForPaint(
  points: KnowledgeProjectedVectorPoint[],
): KnowledgeProjectedVectorPoint[] {
  return [...points].sort((a, b) => {
    const depthDelta = a.depth - b.depth;
    if (Math.abs(depthDelta) > 0.001) return depthDelta;
    return knowledgeVectorPointPaintPriority(a.point.kind) -
      knowledgeVectorPointPaintPriority(b.point.kind);
  });
}

function sortKnowledgeProjectedVectorPointsForHit(
  points: KnowledgeProjectedVectorPoint[],
): KnowledgeProjectedVectorPoint[] {
  return [...points].sort((a, b) => {
    const priorityDelta =
      knowledgeVectorPointHitPriority(a.point.kind) -
      knowledgeVectorPointHitPriority(b.point.kind);
    if (Math.abs(priorityDelta) > 0.001) return priorityDelta;
    return a.depth - b.depth;
  });
}

function knowledgeAxisTickDirection(
  sceneSize: KnowledgeVectorSceneSize,
  axis: KnowledgeVectorAxisSpec,
  value: number,
  yaw: number,
  pitch: number,
  zoom: number,
): { x: number; y: number } {
  const center = projectKnowledgeSceneCoordinate(axis.x * value, axis.y * value, axis.z * value, sceneSize, yaw, pitch, zoom);
  const side = projectKnowledgeSceneCoordinate(axis.x * value + axis.tickX * 0.08, axis.y * value + axis.tickY * 0.08, axis.z * value + axis.tickZ * 0.08, sceneSize, yaw, pitch, zoom);
  const direct = normalizeKnowledgeOffset(side.x - center.x, side.y - center.y, { x: 0, y: 0 });
  if (direct.x !== 0 || direct.y !== 0) return direct;
  const start = projectKnowledgeSceneCoordinate(-axis.x, -axis.y, -axis.z, sceneSize, yaw, pitch, zoom);
  const end = projectKnowledgeSceneCoordinate(axis.x, axis.y, axis.z, sceneSize, yaw, pitch, zoom);
  return normalizeKnowledgeOffset(-(end.y - start.y), end.x - start.x, { x: 0, y: -1 });
}

function normalizeKnowledgeOffset(
  x: number,
  y: number,
  fallback: { x: number; y: number },
): { x: number; y: number } {
  const distance = Math.hypot(x, y);
  if (!Number.isFinite(distance) || distance <= 1e-4) return fallback;
  return { x: x / distance, y: y / distance };
}

function isKnowledgeAxisStepMultiple(value: number, step: number): boolean {
  if (!Number.isFinite(value) || !Number.isFinite(step) || step <= 0) return false;
  const scaled = value / step;
  return Math.abs(scaled - Math.round(scaled)) < 1e-6;
}

function isKnowledgeLabelVisible(
  x: number,
  y: number,
  sceneSize: KnowledgeVectorSceneSize,
  padding = 52,
): boolean {
  return x >= -padding && y >= -padding && x <= sceneSize.width + padding && y <= sceneSize.height + padding;
}

function mergeKnowledgeVectorDistributions(
  retrieval: KnowledgeVectorDistributionData,
  corpus: KnowledgeVectorDistributionData,
): KnowledgeVectorDistributionData {
  const highlightedIds = new Set(
    retrieval.points
      .filter((point) => point.kind !== 'corpus')
      .map((point) => point.id)
      .filter(Boolean),
  );
  const points = [
    ...corpus.points.filter((point) => !highlightedIds.has(point.id)),
    ...retrieval.points,
  ];
  return {
    ...retrieval,
    points,
    originalDimensions: retrieval.originalDimensions > 0 ? retrieval.originalDimensions : corpus.originalDimensions,
    sampledCount: points.length,
    hasMore: corpus.hasMore,
    durationMs: corpus.durationMs,
    generatedAt: corpus.generatedAt ?? retrieval.generatedAt,
  };
}

function knowledgeVectorKindLabel(kind: KnowledgeVectorDistributionPoint['kind']): string {
  switch (kind) {
    case 'query': return t('message.kbDialog.kind.query', '查询向量');
    case 'match': return t('message.kbDialog.kind.match', '命中结果');
    case 'corpus': return t('message.kbDialog.kind.corpus', '全量采样');
  }
}

function formatKnowledgeAxisValue(value: number): string {
  const normalized = Math.abs(value) < 1e-9 ? 0 : value;
  if (Math.abs(normalized) >= 1) return normalized.toFixed(1);
  return normalized.toFixed(2).replace(/0$/, '');
}

function formatKnowledgeCoordinate(value: number): string {
  if (!Number.isFinite(value)) return '-';
  const normalized = Math.abs(value) < 1e-9 ? 0 : value;
  return Math.abs(normalized) < 0.1 ? normalized.toFixed(3) : normalized.toFixed(2);
}

function formatKnowledgeScore(value: number): string {
  if (!Number.isFinite(value)) return '-';
  return (Math.abs(value) < 1e-9 ? 0 : value).toFixed(4);
}

function KbKv({ label, value }: { label: string; value: unknown }) {
  const text = Array.isArray(value)
    ? value.join(', ')
    : value == null || value === ''
      ? '—'
      : typeof value === 'object'
        ? stringifyJsonSafely(value) ?? String(value)
        : String(value);
  return (
    <div class="oh-kb-kv">
      <span>{knowledgeFieldLabel(label)}</span>
      <span title={text}>{text}</span>
    </div>
  );
}

function SelectedInfoChip({ chip }: { chip: MessageContextChip }) {
  const content = (
    <>
      {chip.emoji ? (
        <span class="oh-message-context-emoji" aria-hidden>{chip.emoji}</span>
      ) : chip.icon ? (
        <MessageIcon name={chip.icon} size={14} />
      ) : null}
      <span>{chip.label}</span>
    </>
  );
  if (chip.onClick) {
    return (
      <button
        type="button"
        class={`oh-tap-press oh-message-action-button oh-message-info-button oh-soft-replace is-clickable ${chip.tone === 'knowledge' ? 'is-knowledge' : ''}`}
        style={messageActionSurfaceStyle}
        title={chip.label}
        onClick={(event) => {
          event.stopPropagation();
          chip.onClick?.();
        }}
      >
        {content}
      </button>
    );
  }
  return (
    <span
      class={`oh-message-action-button oh-message-info-button oh-soft-replace ${chip.tone === 'knowledge' ? 'is-knowledge' : ''}`}
      style={messageActionSurfaceStyle}
      title={chip.label}
    >
      {content}
    </span>
  );
}

function ActionBtn({
  icon,
  label,
  disabled = false,
  selected = false,
  tone = 'neutral',
  busy = false,
  onClick,
}: {
  icon: MessageIconName;
  label: string;
  disabled?: boolean;
  selected?: boolean;
  tone?: MessageActionTone;
  busy?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={(e) => {
        e.stopPropagation();
        if (disabled) return;
        onClick();
      }}
      aria-pressed={selected ? 'true' : undefined}
      class={`oh-tap-press oh-message-action-button${selected ? ' is-selected' : ''}${busy ? ' is-busy' : ''}`}
      style={{
        ...messageActionSurfaceStyle,
        ...messageActionVisualStyle(tone, selected),
      }}
      onMouseEnter={(e) => {
        Object.assign(
          (e.currentTarget as HTMLElement).style,
          messageActionVisualStyle(tone, selected, true),
        );
      }}
      onMouseLeave={(e) => {
        Object.assign(
          (e.currentTarget as HTMLElement).style,
          messageActionVisualStyle(tone, selected),
        );
      }}
    >
      <span class={`oh-message-action-icon${busy ? ' oh-spin' : ''}`} aria-hidden>
        <MessageIcon name={icon} size={14} />
      </span>
      <span class="oh-message-action-label">{label}</span>
    </button>
  );
}

// 用 memo 包裹 MessageCard，跳过 props 等价时的重渲染——SSE 80ms snapshot 期间
// 只有"流式增量的最后一条"会真正变更引用，其余卡片直接命中 memo 缓存，
// 不再重做 markdown 解析 / 高亮 / 媒体解码，达到肉眼"逐字 / 逐 token 增长"。
// 我们仅依赖父级 mergeStream 已经保证不变前缀的引用稳定，因此默认 shallow compare 已足够。
export const MessageCard = memo(MessageCardImpl);

/// 思考/工具调用类型消息卡片的可折叠正文容器：
/// - 展开：正文完整呈现。
/// - 折叠：限制 max-height ≈ 5-6 行，用 mask-image 在底部做渐隐，
///   让预览像被「窗帘」半遮住，与 APP 端 _MarkdownPreviewBody 一比一对齐。
///
/// 单一高度动画来源：不在这里播 WAAPI，交由外层 `useMessageSizeMotion`
/// 统一动画文章卡整体高度，避免父子两套 height transition 叠加产生
/// 抽搐 / 鬼畜感。本容器只负责内容切换 + 渐隐遮罩。
function ReasoningCollapsibleBody({
  collapsed,
  scrollableCollapsed = false,
  scrollStateKey,
  previewMaxHeight,
  fadeBackground,
  children,
}: {
  collapsed: boolean;
  scrollableCollapsed?: boolean;
  scrollStateKey?: string;
  previewMaxHeight: number;
  fadeBackground: string;
  children: ComponentChildren;
}) {
  const useCollapsedScroll = collapsed && scrollableCollapsed;
  const bodyRef = useRef<HTMLDivElement | null>(null);
  const {
    clearTimer: cancelScrollSettleTimer,
    scheduleTimer: scheduleScrollSettleTimer,
  } = useTimeoutController();
  const [atBottom, setAtBottom] = useState(false);
  const [scrollingCollapsedBody, setScrollingCollapsedBody] = useState(false);
  const expandedMaxHeight = scrollableCollapsed ? 'none' : '4000px';

  const syncAtBottom = useCallback((element: HTMLDivElement | null = bodyRef.current) => {
    if (!element || !useCollapsedScroll) {
      setAtBottom(false);
      return;
    }
    setAtBottom((current) => {
      const next = isCollapsedBodyAtBottom(element, current);
      return next === current ? current : next;
    });
  }, [useCollapsedScroll]);

  const settleCollapsedScroll = useCallback(() => {
    scheduleScrollSettleTimer(() => {
      setScrollingCollapsedBody(false);
      syncAtBottom();
    }, COLLAPSED_BODY_SCROLL_SETTLE_MS);
  }, [scheduleScrollSettleTimer, syncAtBottom]);

  useEffect(() => {
    if (!useCollapsedScroll) {
      cancelScrollSettleTimer();
      setScrollingCollapsedBody(false);
      setAtBottom(false);
      return;
    }
    syncAtBottom();
    return cancelScrollSettleTimer;
  }, [cancelScrollSettleTimer, scrollStateKey, syncAtBottom, useCollapsedScroll]);

  useLayoutEffect(() => {
    if (!useCollapsedScroll || !scrollStateKey) return;
    const element = bodyRef.current;
    if (!element) return;
    const restore = () => {
      const saved = collapsedBodyScrollTopByKey.get(scrollStateKey);
      if (saved == null) return;
      const maxScrollTop = Math.max(0, element.scrollHeight - element.clientHeight);
      const next = Math.min(saved, maxScrollTop);
      if (Math.abs(element.scrollTop - next) > 1) {
        element.scrollTop = next;
      }
      syncAtBottom(element);
    };
    restore();
    const raf = window.requestAnimationFrame(restore);
    return () => window.cancelAnimationFrame(raf);
  }, [children, previewMaxHeight, scrollStateKey, syncAtBottom, useCollapsedScroll]);

  const handleScroll = useCallback((event: Event) => {
    stopNestedMessageScrollPropagation(event);
    if (!useCollapsedScroll || !scrollStateKey) return;
    const target = event.currentTarget as HTMLDivElement | null;
    if (!target) return;
    rememberCollapsedBodyScrollTop(scrollStateKey, target.scrollTop);
    setScrollingCollapsedBody(true);
    setAtBottom((current) => {
      const next = isCollapsedBodyAtBottom(target, current);
      return next === current ? current : next;
    });
    settleCollapsedScroll();
  }, [scrollStateKey, settleCollapsedScroll, useCollapsedScroll]);

  // 折叠态设置 max-height；正式响应展开态不设人为上限，避免极长正文被裁剪。
  // 底部渐隐用 overlay 而不是 mask-image，避免和流式文本 reveal 的 inline
  // mask 叠加后让已稳定文本在折叠态反复明暗闪动。
  return (
    <div
      ref={bodyRef}
      class={`oh-reasoning-collapsible-body${useCollapsedScroll ? ' is-scrollable-collapsed' : ''}`}
      data-collapsed={collapsed ? 'true' : 'false'}
      data-message-scrollable-body={useCollapsedScroll ? 'true' : undefined}
      aria-expanded={collapsed ? 'false' : 'true'}
      onWheel={useCollapsedScroll ? stopNestedMessageScrollPropagation : undefined}
      onTouchMove={useCollapsedScroll ? stopNestedMessageScrollPropagation : undefined}
      onScroll={useCollapsedScroll ? handleScroll : undefined}
      style={{
        maxHeight: collapsed ? `${previewMaxHeight}px` : expandedMaxHeight,
        overflowX: 'hidden',
        overflowY: collapsed
          ? (useCollapsedScroll ? 'auto' : 'hidden')
          : (scrollableCollapsed ? 'visible' : 'hidden'),
        overscrollBehavior: useCollapsedScroll ? 'contain' : undefined,
      }}
    >
      {children}
      {collapsed ? (
        <div
          class={`oh-reasoning-collapsible-fade${atBottom ? ' is-hidden' : ''}${scrollingCollapsedBody ? ' is-scroll-sync' : ''}`}
          aria-hidden="true"
          style={{
            background: `linear-gradient(to bottom, transparent, ${fadeBackground})`,
          }}
        />
      ) : null}
    </div>
  );
}

function ToolExecutionCard({
  message,
  autoFollow = false,
}: {
  message: SessionMessage;
  autoFollow?: boolean;
}) {
  const metadata = message.metadata ?? {};
  const stdout = stringFromUnknown(metadata['tool_execution_stdout']);
  const stderr = stringFromUnknown(metadata['tool_execution_stderr']);
  const result = stringFromUnknown(metadata['tool_execution_result'] ?? metadata['result_text']);
  const command = stringFromUnknown(metadata['tool_execution_command'] ?? metadata['command']);
  const workingDirectory = stringFromUnknown(metadata['tool_execution_working_directory'] ?? metadata['working_directory']);
  const status = stringFromUnknown(
    metadata['tool_execution_status'] ??
      metadata['tool_status'] ??
      metadata['status'],
  );
  const exitCode = finiteNumberOrNullFromUnknown(metadata['tool_execution_exit_code'] ?? metadata['exit_code']);
  const sandboxApplied = booleanFromUnknown(metadata['sandbox_applied']);
  const sandboxBlocked = booleanFromUnknown(metadata['sandbox_blocked']);
  const sandboxBackend = stringFromUnknown(metadata['sandbox_backend']);
  const sandboxReason = stringFromUnknown(metadata['sandbox_unavailable_reason']);
  const sandboxProxyEnabled = booleanFromUnknown(metadata['sandbox_proxy_enabled']);
  const sandboxProxyHttpPort = finiteNumberOrNullFromUnknown(metadata['sandbox_proxy_http_port']);
  const sandboxProxySocksPort = finiteNumberOrNullFromUnknown(metadata['sandbox_proxy_socks_port']);
  const argumentsStreaming = booleanFromUnknown(metadata['tool_arguments_streaming']);
  const terminalStatus = isTerminalToolExecutionStatus(status);
  const fallback = message.content ?? '';
  const hasStructuredOutput = stdout || stderr || result || command || workingDirectory;
  const constructing =
    (!terminalStatus && argumentsStreaming) ||
    (message.kind === 'tool_call' && !status && !hasStructuredOutput && fallback.trim().length === 0);
  const autoFollowToolOutput = autoFollow || !terminalStatus || booleanFromUnknown(metadata['streaming']);

  return (
    <div class="oh-tool-execution-card flex flex-col gap-2">
      <div class="oh-tool-execution-chip-row flex flex-wrap gap-1.5 text-[11px]">
        <ToolLiveElapsedChip metadata={metadata} status={status} messageCreatedAt={message.created_at} />
        {exitCode != null ? <MetaChip label={`exit ${exitCode}`} tone={exitCode === 0 ? 'ok' : 'danger'} /> : null}
        {(sandboxApplied || sandboxBlocked || sandboxReason) ? (
          <MetaChip
            label={sandboxBlocked ? t('detail.tool.sandbox.blocked', '沙盒拦截') : `${t('detail.tool.sandbox.applied', '沙盒')}${sandboxBackend ? ` · ${sandboxBackend}` : ''}`}
            tone={sandboxBlocked ? 'danger' : 'ok'}
          />
        ) : null}
        {sandboxProxyEnabled ? (
          <MetaChip
            label={`${t('detail.tool.sandbox.proxy', '沙盒代理')} · HTTP ${sandboxProxyHttpPort || '-'}${sandboxProxySocksPort ? ` · SOCKS ${sandboxProxySocksPort}` : ''}`}
            tone="ok"
          />
        ) : null}
        {workingDirectory ? <MetaChip label={workingDirectory} mono /> : null}
        {constructing ? <ConstructingBadge /> : null}
      </div>
      <ToolArgumentsBlock metadata={metadata} autoFollow={argumentsStreaming || autoFollowToolOutput} />
      {command ? (
        <ToolSection title={t('detail.tool.command', '执行命令')} content={command} defaultExpanded autoFollow={autoFollowToolOutput} />
      ) : null}
      {stdout ? (
        <ToolSection title={t('detail.tool.stdout', '标准输出')} content={stdout} autoFollow={autoFollowToolOutput} />
      ) : null}
      {stderr ? (
        <ToolSection title={t('detail.tool.stderr', '标准错误 stderr')} content={stderr} danger defaultExpanded autoFollow={autoFollowToolOutput} />
      ) : null}
      {sandboxReason ? (
        <ToolSection title={t('detail.tool.sandbox.reason', '沙盒状态')} content={sandboxReason} danger={sandboxBlocked} defaultExpanded autoFollow={autoFollowToolOutput} />
      ) : null}
      {result ? (
        <ToolSection title={t('detail.tool.result', '工具结果')} content={result} defaultExpanded={!stdout && !stderr} autoFollow={autoFollowToolOutput} />
      ) : null}
      {!hasStructuredOutput && fallback.trim().length > 0 ? <ToolResultBody content={fallback} autoFollow={autoFollowToolOutput} /> : null}
    </div>
  );
}

function FileMutationSummaryCard({ message }: { message: SessionMessage }) {
  const metadata = message.metadata ?? {};
  const paths = collectMutationPaths(metadata);
  const recordCount = finiteNumberOrNullFromUnknown(metadata['round_summary_record_count']);
  const kind = stringFromUnknown(metadata['file_mutation_kind']);
  const reason = stringFromUnknown(
    metadata['file_mutation_write_reason'] ??
      metadata['write_analysis_reason'] ??
      metadata['tool_execution_write_analysis_reason'],
  );
  const mutationIcon: MessageIconName = kind === 'delete' ? 'delete' : kind === 'write' ? 'write' : 'mutate';
  return (
    <div
      class="oh-file-mutation-card rounded-m3-sm p-3"
      style={{
        background: 'var(--m3-surface)',
        border: '1px solid var(--m3-outline)',
      }}
    >
      <div class="oh-file-mutation-header flex items-center justify-between gap-2 mb-2">
        <div class="flex items-center gap-2 min-w-0">
          <span class="text-sm font-semibold oh-text-body">
            {t('detail.fileMutation.title', '文件变动')}
          </span>
          {kind ? <MetaChip label={kind} /> : null}
        </div>
        {recordCount != null ? (
          <span class="text-xs oh-text-muted">
            {recordCount} {t('detail.fileMutation.records', '条记录')}
          </span>
        ) : null}
      </div>
      {paths.length > 0 ? (
        <ul class="oh-file-mutation-path-list flex flex-col gap-1.5">
          {paths.map((path) => (
            <li
              key={path}
              class="oh-file-mutation-path-row flex items-center gap-2 text-xs rounded-m3-sm px-2 py-1.5"
              style={{
                background: 'var(--m3-surface-container)',
                color: 'var(--m3-on-surface)',
              }}
            >
              <span class="oh-file-mutation-icon" aria-hidden>
                <MessageIcon name={mutationIcon} size={14} />
              </span>
              <span class="font-mono truncate" title={path}>{path}</span>
              <button
                type="button"
                class="oh-tap-press oh-message-action-button is-compact ml-auto text-[11px]"
                style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
                onClick={(e) => {
                  e.stopPropagation();
                  void copyPathWithFeedback(path);
                }}
              >
                <MessageIcon name="copy" size={13} />
                <span>{t('common.copy', '复制')}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p class="text-xs oh-text-muted">
          {recordCount != null
            ? t('detail.fileMutation.summaryOnly', '本轮文件变动记录已归档，可在 App 端查看完整 diff 与撤销记录。')
            : t('detail.fileMutation.empty', '暂无可展示的文件路径。')}
        </p>
      )}
      {reason ? (
        <p class="text-xs mt-2 oh-text-muted">
          {reason}
        </p>
      ) : null}
      {message.content.trim().length > 0 ? (
        <div class="mt-2">
          <ToolResultBody content={message.content} />
        </div>
      ) : null}
    </div>
  );
}

function ToolSection({
  title,
  content,
  danger,
  defaultExpanded = false,
  autoFollow = false,
}: {
  title: string;
  content: string;
  danger?: boolean;
  defaultExpanded?: boolean;
  autoFollow?: boolean;
}) {
  const formattedContent = useMemo(
    () => formatToolSectionContent(content),
    [content],
  );
  // 有界行数判定 + memo：多 KB 的 stdout/stderr 每次重渲染整段 split
  // 会白白分配整行数组，流式期间尤甚。
  const long = useMemo(
    () =>
      formattedContent.length > 640
      || newlineCountAtLeast(formattedContent, 10),
    [formattedContent],
  );
  const [expanded, setExpanded] = useState(defaultExpanded || !long);
  const preRef = useStickyBottom<HTMLPreElement>(formattedContent, autoFollow);
  return (
    <section class="oh-tool-section">
      <div class="oh-tool-section-header flex items-center gap-2 mb-1 text-[11px] oh-text-muted">
        <span style={{ fontWeight: 600, color: danger ? 'var(--m3-error)' : undefined }}>{title}</span>
        {long ? (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setExpanded((v) => !v);
            }}
            class="oh-tap-press oh-tool-toggle-button px-1.5 py-0.5 rounded-m3-sm"
            style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface-variant)', background: 'var(--m3-surface)', fontSize: 10 }}
          >
            {expanded ? t('detail.tool.body.collapse', '折叠') : t('detail.tool.body.expand', '展开全部 ')}
          </button>
        ) : null}
      </div>
      <pre
        ref={preRef}
        class="oh-tool-section-pre text-[11px] leading-snug whitespace-pre-wrap font-mono rounded-m3-sm p-2 m-0"
        style={{
          background: 'var(--m3-surface)',
          color: danger ? 'var(--m3-error)' : 'var(--m3-on-surface)',
          border: `1px solid ${danger ? 'color-mix(in srgb, var(--m3-error) 45%, transparent)' : 'var(--m3-outline)'}`,
          wordBreak: 'break-word',
          maxHeight: long ? (expanded ? 'min(70dvh, 720px)' : '160px') : undefined,
          overflow: long ? 'auto' : 'visible',
        }}
      >
        {formattedContent}
      </pre>
    </section>
  );
}

function formatToolSectionContent(content: string): string {
  const normalized = content
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .trimEnd();
  const trimmed = normalized.trim();
  const legacyToolSearchContent = formatLegacyToolSearchContent(trimmed);
  if (legacyToolSearchContent) return legacyToolSearchContent;
  if (!looksLikeJsonText(trimmed)) return normalized;
  const parsed = parseJsonSafely(trimmed);
  return parsed == null ? normalized : stringifyJsonSafely(parsed, 2) ?? normalized;
}

function looksLikeJsonText(text: string): boolean {
  if (text.length < 2) return false;
  return (
    (text.startsWith('{') && text.endsWith('}')) ||
    (text.startsWith('[') && text.endsWith(']'))
  );
}

/// 有界换行计数：只需知道换行数是否达到 [limit]，数够即停，
/// 避免对大段工具输出整段 split 分配行数组。
function newlineCountAtLeast(text: string, limit: number): boolean {
  if (limit <= 0) return true;
  let count = 0;
  let cursor = text.indexOf('\n');
  while (cursor !== -1) {
    count += 1;
    if (count >= limit) return true;
    cursor = text.indexOf('\n', cursor + 1);
  }
  return false;
}

function formatLegacyToolSearchContent(content: string): string | null {
  const header = content.match(
    /^ToolSearch (?:loaded|matched) (\d+) of (\d+) deferred runtime tool\(s\)\./,
  );
  if (!header) return null;
  const functions: Array<Record<string, unknown>> = [];
  const functionPattern = /<function>([\s\S]*?)<\/function>/g;
  for (const match of content.matchAll(functionPattern)) {
    const rawFunction = match[1]?.trim();
    if (!rawFunction) continue;
    const decoded = parseJsonRecordSafely(rawFunction);
    if (decoded == null) return null;
    functions.push(decoded);
  }
  const matchedCount = Number.parseInt(header[1] ?? '0', 10) || 0;
  const deferredTotal = Number.parseInt(header[2] ?? '0', 10) || 0;
  if (functions.length === 0 && matchedCount > 0) return null;
  const loadedTools = functions
    .map((item) => (typeof item.name === 'string' ? item.name.trim() : ''))
    .filter(Boolean);
  return stringifyJsonSafely(
    {
      tool: 'ToolSearch',
      status: 'success',
      matched_count: matchedCount,
      deferred_total: deferredTotal,
      loaded_tools: loadedTools,
      message: matchedCount === 0
        ? 'No deferred tool matched. Try different keywords or select exact names.'
        : 'Matched tools are callable by exact name from the next model request onward.',
      functions,
    },
    2,
  ) ?? null;
}

function MetaChip({ label, tone = 'neutral', mono }: { label: string; tone?: 'neutral' | 'ok' | 'danger'; mono?: boolean }) {
  const color = tone === 'danger' ? 'var(--m3-error)' : tone === 'ok' ? 'var(--m3-primary)' : 'var(--m3-on-surface-variant)';
  return (
    <span
      class="oh-tool-meta-chip inline-flex items-center rounded-m3-sm"
      style={{
        border: `1px solid color-mix(in srgb, ${color} 40%, transparent)`,
        color,
        background: 'color-mix(in srgb, currentColor 7%, transparent)',
        fontFamily: mono ? 'ui-monospace, SFMono-Regular, Menlo, monospace' : undefined,
        maxWidth: '220px',
      }}
      title={label}
    >
      <span class="truncate">{label}</span>
    </span>
  );
}

function ConstructingBadge() {
  return (
    <span
      class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
      style={{
        border: '1px solid var(--m3-outline)',
        color: 'var(--m3-on-surface-variant)',
        background: 'color-mix(in srgb, var(--m3-on-surface-variant) 7%, transparent)',
      }}
      title={t('detail.tool.constructing.hint', '模型仍在构造工具参数')}
    >
      <span class="oh-pulse-soft" aria-hidden style={{ width: 6, height: 6, borderRadius: '50%', background: 'currentColor' }} />
      {t('detail.tool.constructing', '参数构造中')}
    </span>
  );
}

/// 流式助手消息尾部的「打字机」光标。配合 Dart 端 _StreamCharThrottle
/// 一起，给低速率字符流式输出场景一个明确的"AI 仍在打字"视觉信号。
function TypewriterCaret() {
  return (
    <span
      class="oh-typewriter-caret"
      aria-hidden
      style={{
        display: 'inline-block',
        width: 8,
        height: 14,
        marginLeft: 4,
        verticalAlign: '-2px',
        borderRadius: 2,
        background: 'currentColor',
        opacity: 0.7,
        animation: 'oh-typewriter-caret-blink 0.95s ease-in-out infinite alternate',
      }}
    />
  );
}

function collectMutationPaths(metadata: Record<string, unknown>): string[] {
  const out: string[] = [];
  const add = (value: unknown) => {
    if (typeof value !== 'string') return;
    const trimmed = value.trim();
    if (trimmed && !out.includes(trimmed)) out.push(trimmed);
  };
  add(metadata['file_mutation_path']);
  add(metadata['read_file_path']);
  const multi = metadata['file_mutation_paths'];
  if (Array.isArray(multi)) {
    for (const item of multi) add(item);
  }
  return out;
}

/// 工具入参展示块：将 metadata.tool_arguments 渲染为可折叠的 JSON 代码块。
/// - 字符串 → 尝试 JSON.parse 后 pretty-print；解析失败按原文展示。
/// - 默认折叠到 4 行；点击「展开/折叠」切换。
/// - 与工具结果（ToolResultBody）共享视觉语言：mono 字体、surface 背景、outline 边框。
function ToolArgumentsBlock({
  metadata,
  autoFollow = false,
}: {
  metadata: Record<string, unknown> | undefined;
  autoFollow?: boolean;
}) {
  const raw = metadata?.['tool_arguments'];
  // pretty 结果按 raw 缓存：卡片任何无关重渲染（每秒耗时 tick、流式
  // chunk）不再重复对整段入参做 JSON.parse + pretty-print。
  // hooks 全部提前到早退之前，顺便修正了原实现「条件早退后再调 hook」
  // 在 raw 空/非空切换时的 hooks 顺序隐患。
  const pretty = useMemo(() => {
    if (raw == null) return null;
    if (typeof raw === 'string') {
      const trimmed = raw.trim();
      if (trimmed === '') return null;
      const parsed = parseJsonSafely(trimmed);
      return parsed == null ? trimmed : stringifyJsonSafely(parsed, 2) ?? trimmed;
    }
    return stringifyJsonSafely(raw, 2) ?? String(raw);
  }, [raw]);
  const [expanded, setExpanded] = useState(false);
  const overflow = useMemo(
    () => pretty != null && (pretty.length > 200 || newlineCountAtLeast(pretty, 4)),
    [pretty],
  );
  const preRef = useStickyBottom<HTMLPreElement>(pretty ?? '', autoFollow);
  if (pretty == null) return null;
  return (
    <div class="mb-2">
      <div
        class="text-[11px] mb-1 flex items-center gap-2 oh-text-muted"
      >
        <span style={{ fontWeight: 600 }}>{t('detail.tool.argumentsTitle', '工具入参')}</span>
        {overflow ? (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setExpanded((v) => !v);
            }}
            class="oh-tap-press oh-tool-toggle-button px-1.5 py-0.5 rounded-m3-sm"
            style={{
              border: '1px solid var(--m3-outline)',
              color: 'var(--m3-on-surface-variant)',
              background: 'var(--m3-surface)',
              fontSize: 10,
            }}
          >
            {expanded
              ? t('detail.tool.body.collapse', '折叠')
              : t('detail.tool.body.expand', '展开全部 ')}
          </button>
        ) : null}
      </div>
      <pre
        ref={preRef}
        class="oh-tool-section-pre text-[11px] leading-snug whitespace-pre-wrap font-mono rounded-m3-sm p-2 m-0"
        style={{
          background: 'var(--m3-surface)',
          color: 'var(--m3-on-surface)',
          border: '1px solid var(--m3-outline)',
          wordBreak: 'break-word',
          maxHeight: overflow ? (expanded ? 'min(64dvh, 640px)' : '88px') : undefined,
          overflow: overflow ? 'auto' : 'visible',
        }}
      >
        {pretty}
      </pre>
    </div>
  );
}
