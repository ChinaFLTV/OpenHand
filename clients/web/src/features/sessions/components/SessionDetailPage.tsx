import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ComponentChildren, JSX } from 'preact';
import { useRoute } from 'preact-iso';
import { FitAddon } from '@xterm/addon-fit';
import { Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';
import {
  GOAL_DEFAULT_MAX_AUTO_TURNS,
  GOAL_HARD_MAX_AUTO_TURNS,
  KNOWLEDGE_BASE_MESSAGE_METADATA_KEY,
  controlMachineTerminal,
  clearSessionThrottle,
  compactSession,
  DEFERRED_MESSAGE_TELEMETRY_METADATA_KEY,
  deleteMessage,
  deleteMessageCascade,
  deleteSession,
  EXPORT_SESSION_TIMEOUT_ERROR,
  exportSessionDownload,
  fetchMessageTtsPlayback,
  forkSessionFromMessage,
  generateSessionTitle,
  getMachineTerminal,
  getSession,
  getSessionMessage,
  isGoalModeAllowedForTemplate,
  listMessages,
  listSessionTitleSourceMessages,
  pauseGoal,
  regenerateMessage,
  renameSession,
  respondWriteApproval,
  resumeGoal,
  sendMessage,
  setMessageFeedback,
  setSessionThrottle,
  syncGoalQueueYield,
  stopMessage,
  stopMessageTtsPlayback,
  terminateGoal,
  toggleMessageTtsPlayback,
  translateMessage,
  updateSessionFullAccessPermission,
  updateSessionMode,
  writeMachineTerminal,
  type MachineTerminalSnapshot,
  type MachineTerminalWorkspace,
  type CompactSessionStatus,
  type GoalStartOptions,
  type MessageTtsPlaybackState,
  type SendMessageAttachment,
  type SessionCacheHitTrendPoint,
  type SessionDetailResponse,
  type SessionGoalRecord,
  type SessionGoalState,
  type SessionMessage,
  type SessionMessageFeedback,
  type SessionMode,
  type SessionSummary,
} from '../../../api/sessions';
import { ApiError, UnauthorizedError } from '../../../api/client';
import { ignoreError, isAbortError } from '../../../shared/util/errors';
import {
  formatLocalDateTimeSecond,
  formatLocalTimeSecond,
} from '../../../shared/util/date_time';
import {
  PAGE_SHELL_CLASS,
  SESSION_DETAIL_SHELL_CLASS,
} from '../../../shared/ui/layout';
import { subscribeSessionEvents, type PendingWriteApproval, type SessionEventSnapshot } from '../../../api/session_events';
import { listSessions } from '../../../api/sessions';
import { SessionGoneDialog } from '../../../components/SessionGoneDialog';
import { RollingText } from '../../../components/RollingText';
import { t } from '../../../i18n';
import { refreshMeta, useAuth } from '../../../state/auth';
import {
  updateModelReasoningEffort,
  type ApiMetaInstruction,
  type ApiMetaModel,
  type ApiMetaShortcutBinding,
} from '../../../api/meta';
import { MessageCard, markMessagesAsAppeared } from '../../../components/MessageCard';
import { PlanTimeline } from '../../../components/PlanTimeline';
import CacheHitTrendChart, { type CacheHitDisplayMode } from './CacheHitTrendChart';
import {
  cacheHitDisplayData,
  DEFAULT_CACHE_HIT_DISPLAY_MODE,
  type CacheHitTrendPoint,
} from '../cache_hit_stats';
import { notifyIfHidden } from '../../../services/pwa';
import { readBrowserStorage, removeBrowserStorage, writeBrowserStorage } from '../../../shared/util/browser_storage';
import {
  knowledgeBaseHitTokenEstimateTotal,
  knowledgeBaseResultsUsedByAnswer,
} from '../../../shared/util/knowledge';
import { messageFeedbackValue } from '../../../shared/util/message_feedback';
import { clampNumber, strictPositiveIntegerFromText } from '../../../shared/util/number';
import { basenameFromPath } from '../../../shared/util/path';
import { truncateEndText } from '../../../shared/util/text';
import {
  clearTranscriptScrollActivity,
  isTranscriptScrollActive,
  markTranscriptScrollActivity,
  subscribeTranscriptScrollActivity,
} from '../../../shared/ui/transcript_scroll_activity';
import { STREAMING_TURN_IDLE_DEBOUNCE_MS } from '../../../shared/ui/streaming_turn_timing';
import {
  arrayFromUnknown,
  finiteNumberFromUnknown,
  integerFromUnknown,
  nonNegativeIntegerFromUnknown,
  parseJsonRecordSafely,
  booleanFromUnknown,
  recordFromUnknown,
  recordOrNullFromUnknown,
  roundedNonNegativeIntegerOrNullFromUnknown,
  strictStringFromUnknown,
  stringifyJsonSafely,
  stringFromUnknown,
  stringListFromUnknown,
} from '../../../shared/util/value';
import {
  displayableTranscriptMessages,
  messageHasRenderableTranscriptOutput,
} from '../../../shared/util/session_transcript_messages';
import { SessionTopBar, type SessionToolbarCapsule } from '../../../components/SessionTopBar';
import { ModelPickerDialog } from '../../../components/ModelPickerDialog';
import { ReasoningEffortControl } from '../../../components/ReasoningEffortControl';
import { PullIndicator } from '../../../components/PullIndicator';
import { usePullToRefresh } from '../../../hooks/usePullToRefresh';
import { useReducedMotion } from '../../../hooks/useReducedMotion';
import type { MessageContentFormat } from '../../../hooks/useMessageContentFormat';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import { useBrowserFullscreen } from '../../../hooks/useBrowserFullscreen';
import { useDelayedFalse } from '../../../hooks/useDelayedFalse';
import { useDialogExitMotion } from '../../../hooks/useDialogExitMotion';
import { useDelayedVisibility } from '../../../hooks/useDelayedVisibility';
import { useEventCallback } from '../../../hooks/useEventCallback';
import { useTimeoutController } from '../../../hooks/useTimeoutController';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import { showSnackbar } from '../../../components/Snackbar';
import { OverlayPortal } from '../../../components/OverlayPortal';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_LOW_Z_INDEX,
  DialogActionButton,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from '../../../components/DialogFrame';
import { WebReverseDashboardDialog } from '../../../components/WebReverseDashboardDialog';
import { AndroidReverseDashboardDialog } from '../../../components/AndroidReverseDashboardDialog';
import { copyTextToClipboard } from '../../../utils/clipboard';
import {
  base64PayloadFromDataUrl,
  readBlobAsDataUrl,
} from '../../../utils/blob_data_url';
import { fetchBlobBounded } from '../../../utils/bounded_response';
import { buildSessionAssetUrl } from '../../../utils/session_asset';
import { createTimedAbortController } from '../../../utils/timed_abort';
import { PopMenu } from '../../../components/PopMenu';
import { svgIconProps } from '../../../shared/ui/svg_icon';
import { STORAGE_KEY_COMPOSER_COLLAPSED } from '../../../shared/util/storage_keys';
import { listSkills, type SkillSummary } from '../../../api/toolbox';
import { ImageEditorDialog, type ImageEditorInput, type ImageEditorResult } from '../../../components/ImageEditorDialog';
import { CreationOptionsDialog, type CreationOptions } from '../../../components/CreationOptionsDialog';
import { TitleSummaryDialog } from '../../../components/TitleSummaryDialog';
import { TrajectoryDialog } from '../../../components/TrajectoryDialog';
import { MediaGeneratingPlaceholderTransition, type MediaGenerationMode } from '../../../components/MediaGeneratingPlaceholder';
import {
  MESSAGE_LIST_DEFAULT_INITIAL_PAGE_SIZE,
  MESSAGE_LIST_DEFAULT_PAGE_SIZE,
  MESSAGE_LIST_ESTIMATED_ROW_HEIGHT_PX,
  MESSAGE_LIST_MAX_LOADED_MESSAGES,
  MESSAGE_LIST_VIRTUALIZATION_OVERSCAN_PX,
  boundLiveMessageWindow,
  buildHeightPrefix,
  clampMessageRowHeight,
  initialVirtualMessageRange,
  rebaseVirtualMessageRange,
  resolveVirtualMessageRange,
  remainingNewerMessageCount,
  shouldVirtualizeMessageList,
  virtualMessageTop,
  virtualMessageRangeAroundIndex,
  virtualMessageTotalHeight,
  type VirtualMessageRange,
} from '../../../shared/util/virtual_message_list_math';

// 首屏加载最近一页消息；更早历史只在用户点击“加载更早”时进入当前滚动范围。
const PAGE_SIZE = MESSAGE_LIST_DEFAULT_PAGE_SIZE;
const INITIAL_PAGE_SIZE = MESSAGE_LIST_DEFAULT_INITIAL_PAGE_SIZE;
const CACHE_HIT_REVEAL_MATERIALIZE_FRAMES = 12;
const CACHE_HIT_REVEAL_HIGHLIGHT_MS = 1400;
const CACHE_HIT_REVEAL_SCROLL_GUARD_MS = 1800;

function supportsTitleGeneration(model: ApiMetaModel | undefined): boolean {
  return !!model && model.supports_text_title_generation !== false;
}

function resolveDefaultTitleModelKey(models: ApiMetaModel[], currentKey: string): string {
  const current = currentKey ? models.find((model) => model.key === currentKey) : undefined;
  if (supportsTitleGeneration(current)) return current!.key;
  const providerDefaultKey = current?.provider_default_title_model_key ?? '';
  if (providerDefaultKey) {
    const providerDefault = models.find((model) => model.key === providerDefaultKey);
    if (supportsTitleGeneration(providerDefault)) return providerDefault!.key;
  }
  const globalDefault = models.find((model) => model.is_global_default_title_model);
  if (supportsTitleGeneration(globalDefault)) return globalDefault!.key;
  if (current) return '';
  return models.find((model) => supportsTitleGeneration(model))?.key ?? '';
}

function positiveIntegerOr(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0
    ? value
    : fallback;
}

function decodedBase64Size(encoded: string): number {
  if (!encoded) return 0;
  const padding = encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0;
  return Math.max(0, Math.floor(encoded.length / 4) * 3 - padding);
}

const LOAD_OLDER_RENDER_SETTLE_MS = 160;
const AUTO_FOLLOW_NEAR_BOTTOM_PX = 64;
const AUTO_FOLLOW_SCROLL_TOP_EPSILON_PX = 0.05;
const AUTO_FOLLOW_WHEEL_INTENT_EPSILON_PX = 0;
const AUTO_FOLLOW_USER_SCROLL_INTENT_MS = 1200;
const AUTO_FOLLOW_SETTLE_MAX_FRAMES = 36;
const AUTO_FOLLOW_SETTLE_STABLE_FRAMES = 4;
const AUTO_FOLLOW_SETTLE_EPSILON_PX = 0.75;
const TRANSCRIPT_INITIAL_SETTLE_MAX_FRAMES = 72;
const TRANSCRIPT_INITIAL_SETTLE_MAX_MS = 1400;
const TRANSCRIPT_INITIAL_SETTLE_MIN_FRAMES = 14;
const TRANSCRIPT_INITIAL_SETTLE_STABLE_FRAMES = 4;
const TRANSCRIPT_INITIAL_SETTLE_EPSILON_PX = 0.75;
// 测量任务仅在宽限帧内阻断首屏揭示，避免微小布局调整持续重置稳定计数。
const TRANSCRIPT_INITIAL_SETTLE_MEASURE_GRACE_FRAMES = 24;
const COMPOSER_LAYOUT_TRANSITION_GUARD_MS = 440;
const KNOWLEDGE_USAGE_PREVIEW_MAX_CHARS = 420;
const COMPOSER_INSTRUCTION_HOVER_PREVIEW_DELAY_MS = 480;
const COMPOSER_EDIT_FOCUS_DELAY_MS = 0;

// 助手回复期间的轮询间隔。仅作为 SSE 失败时的兜底；正常路径走 SSE 实时推送。
const POLL_INTERVAL_MS = 1500;

// SSE 正常时仍保留一个低频 phase guard，专门兜底最后一次 idle 状态丢失。
const SSE_PHASE_GUARD_INTERVAL_MS = 2500;

// 单次 phase guard 请求的硬超时，避免网络层异常导致兜底轮询永久挂起。
const SESSION_PHASE_POLL_TIMEOUT_MS = 15_000;
const TTS_PLAYBACK_POLL_INTERVAL_MS = 1000;
const TTS_PLAYBACK_POLL_TIMEOUT_MS = 10_000;
let lastMessageTtsSessionId: string | null = null;

// SSE 连续失败 N 次以上才彻底切到 polling，避免短暂网络抖动造成体验切换。
const SSE_FAIL_THRESHOLD = 3;

const DEFAULT_ATTACHMENT_MAX_BYTES = 10 * 1024 * 1024;
const DEFAULT_ATTACHMENT_MAX_TOTAL_BYTES = 16 * 1024 * 1024;
const DEFAULT_ATTACHMENT_MAX_COUNT = 20;
const COMPOSER_QUEUE_MAX_MESSAGES = 32;
const COMPOSER_QUEUE_MAX_ATTACHMENT_BYTES = 64 * 1024 * 1024;
/// 输入文本状态的去抖同步窗口，避免每次键入都触发整页重渲染。
const COMPOSER_TEXT_STATE_SYNC_MS = 150;
const ATTACHMENT_READ_TIMEOUT_MS = 30_000;
const COMPOSER_ITEM_EXIT_MS = 190;
const QUEUE_SEND_SETTLE_MS = 600;
const REMOTE_RUNNING_LOCAL_SEND_GRACE_MS = 4_000;
const DEFAULT_COMPOSER_MODES = ['normal', 'image', 'video', 'audio', 'deep_research'];
const THROTTLE_BUCKET_TICK_MS = 1000;
const AUTO_TITLE_FOLLOW_UP_DELAYS_MS = [1200, 3200, 7000, 14000, 24000] as const;
const USER_SKILL_SELECTION_METADATA_KEY = 'user_skill_selection';
const TOKEN_STATS_DIALOG_MAX_HEIGHT = 'min(720px, calc(100vh - 32px))';
const COMPOSER_TRIGGER_ROOT_OFFSET = 0;
const COMPOSER_TRIGGER_WINDOWS_DRIVE_RE = /^[A-Za-z]:/;
const EMPTY_SESSION_MESSAGES: SessionMessage[] = [];
const IMAGE_ATTACHMENT_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg']);
const VIDEO_ATTACHMENT_EXTENSIONS = new Set(['mp4', 'avi', 'mov', 'mkv', 'wmv']);
const AUDIO_ATTACHMENT_EXTENSIONS = new Set(['mp3', 'wav', 'flac', 'm4a', 'ogg']);
const FILE_ATTACHMENT_EXTENSIONS = new Set([
  'txt',
  'md',
  'markdown',
  'json',
  'yaml',
  'yml',
  'toml',
  'xml',
  'html',
  'htm',
  'css',
  'scss',
  'sass',
  'js',
  'jsx',
  'ts',
  'tsx',
  'dart',
  'go',
  'py',
  'java',
  'kt',
  'kts',
  'rb',
  'rs',
  'c',
  'cc',
  'cpp',
  'h',
  'hpp',
  'sh',
  'zsh',
  'bash',
  'fish',
  'ps1',
  'swift',
  'php',
  'cs',
  'scala',
  'sql',
  'log',
  'csv',
  'tsv',
  'xls',
  'xlsx',
  'pdf',
]);
type AwaitingCreationMode = Extract<MediaGenerationMode, 'image' | 'video' | 'audio'>;

interface ComposerTriggerDismissal {
  offset: number;
  query: string;
}

interface SlashTriggerInfo {
  triggerOffset: number;
  tokenEnd: number;
  query: string;
  token: string;
}

interface AtMentionTriggerInfo {
  triggerOffset: number;
  tokenEnd: number;
  query: string;
  token: string;
}

interface ComposerPickerAnchor {
  bottomGap: number;
  left: number;
  width: number;
  maxHeight: number;
}

interface SessionMessageWindowView {
  ordered: SessionMessage[];
  tail: SessionMessage | null;
  tailSignature: string;
  followSignature: string;
  latestAssistantMessage: SessionMessage | null;
  latestStreamingTextMessageId: string | null;
  lastCreationModeAwaitingAssistant: AwaitingCreationMode | null;
  hasUserMessage: boolean;
}

function isComposerTriggerWhitespaceCode(code: number): boolean {
  return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d;
}

function isComposerPathLikeQuery(query: string): boolean {
  if (query.length === 0) return false;
  if (query.startsWith('/') || query.startsWith('\\') || query.includes('/') || query.includes('\\') || query.startsWith('./') || query.startsWith('../') || query.startsWith('~/') || query.startsWith('.\\') || query.startsWith('..\\') || query.startsWith('~\\')) {
    return true;
  }
  return COMPOSER_TRIGGER_WINDOWS_DRIVE_RE.test(query);
}

function shouldSuppressSlashSkillQuery(query: string): boolean {
  return isComposerPathLikeQuery(query) || query.startsWith('*');
}

function shouldSuppressDismissedComposerTrigger(dismissedQuery: string, currentQuery: string): boolean {
  const dismissed = dismissedQuery.trim().toLowerCase();
  const current = currentQuery.trim().toLowerCase();
  return current.length >= dismissed.length && current.startsWith(dismissed);
}

function computeComposerPickerAnchor(node: HTMLElement | null, maxWidth = 480): ComposerPickerAnchor | null {
  if (!node || typeof window === 'undefined') return null;
  const rect = node.getBoundingClientRect();
  const viewportW = window.innerWidth;
  const viewportH = window.innerHeight;
  const width = maxWidth >= 220 ? clampNumber(rect.width, 220, maxWidth) : maxWidth;
  return {
    bottomGap: Math.max(8, viewportH - rect.top + 10),
    left: clampNumber(rect.left, 12, Math.max(12, viewportW - width - 12)),
    width,
    maxHeight: clampNumber(rect.top - 16, 160, 360),
  };
}

function readComposerTriggerQueryAtOffset(text: string, triggerOffset: number, triggerChar: string, requireWhitespaceBefore: boolean): string | null {
  if (triggerOffset < 0 || triggerOffset >= text.length) return null;
  if (text.charAt(triggerOffset) !== triggerChar) return null;
  if (requireWhitespaceBefore && triggerOffset > 0) {
    const prevCode = text.charCodeAt(triggerOffset - 1);
    if (!isComposerTriggerWhitespaceCode(prevCode)) return null;
  }
  let tokenEnd = text.length;
  for (let i = triggerOffset + 1; i < text.length; i += 1) {
    if (isComposerTriggerWhitespaceCode(text.charCodeAt(i))) {
      tokenEnd = i;
      break;
    }
  }
  return text.slice(triggerOffset + 1, tokenEnd);
}

interface RestoredSkillSelection {
  name: string;
  path: string;
  relativePath: string;
  emoji: string | null;
}

function extractUserSkillSelection(message: SessionMessage): RestoredSkillSelection | null {
  const metadata = recordOrNullFromUnknown(message.metadata);
  const skill = recordOrNullFromUnknown(metadata?.[USER_SKILL_SELECTION_METADATA_KEY]) ?? recordOrNullFromUnknown(metadata?.['selected_skill']);
  if (!skill) return null;
  const name = strictStringFromUnknown(skill['name']);
  const path = strictStringFromUnknown(skill['path']) || strictStringFromUnknown(skill['manifest_path']);
  const relativePath = strictStringFromUnknown(skill['relative_directory_path']) || strictStringFromUnknown(skill['relative_path']);
  if (!name && !path && !relativePath) return null;
  return {
    name,
    path,
    relativePath,
    emoji: strictStringFromUnknown(skill['emoji']) || null,
  };
}

function skillMatchesSelection(skill: SkillSummary, selection: RestoredSkillSelection): boolean {
  if (selection.relativePath && skill.relative_directory_path === selection.relativePath) {
    return true;
  }
  if (selection.path) {
    const normalized = selection.path.replaceAll('\\', '/');
    const relative = skill.relative_directory_path.replaceAll('\\', '/');
    if (normalized.endsWith(`/${relative}`) || normalized.endsWith(`/${relative}/SKILL.md`)) {
      return true;
    }
  }
  return Boolean(selection.name && skill.name === selection.name);
}

function skillSummaryFromSelection(selection: RestoredSkillSelection, source: SkillSummary[]): SkillSummary | null {
  const found = source.find((skill) => skillMatchesSelection(skill, selection));
  if (found) return found;
  if (!selection.name) return null;
  return {
    name: selection.name,
    description: '',
    directory_path: selection.path,
    relative_directory_path: selection.relativePath,
    has_default_prompt: false,
    emoji_icon: selection.emoji,
  };
}

function readPersistedComposerCollapsed(): boolean {
  return readBrowserStorage(STORAGE_KEY_COMPOSER_COLLAPSED) === '1';
}

function persistComposerCollapsed(value: boolean): void {
  if (value) {
    writeBrowserStorage(STORAGE_KEY_COMPOSER_COLLAPSED, '1');
  } else {
    removeBrowserStorage(STORAGE_KEY_COMPOSER_COLLAPSED);
  }
}

async function copyJsonWithFeedback(json: string): Promise<void> {
  const ok = await copyTextToClipboard(json);
  showSnackbar(ok ? t('common.copied', '已复制') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
    tone: ok ? 'success' : 'error',
  });
}

function JsonDialogActions({
  json,
  requestClose,
  surfaceStyle,
  closeTone = 'ghost',
}: {
  json: string;
  requestClose: () => void;
  surfaceStyle?: JSX.CSSProperties;
  closeTone?: 'ghost' | 'secondary';
}) {
  const copyStyle = surfaceStyle
    ? { ...surfaceStyle, color: 'var(--m3-primary)' }
    : { color: 'var(--m3-primary)' };
  const closeStyle = surfaceStyle
    ? { ...surfaceStyle, color: 'var(--m3-on-surface-variant)' }
    : undefined;
  return (
    <div class="flex flex-wrap items-center justify-end gap-2 flex-none">
      <DialogActionButton
        tone="secondary"
        style={copyStyle}
        onClick={() => void copyJsonWithFeedback(json)}
      >
        <ComposerIcon name="copy" size={14} />
        <span>{t('common.copy', '复制')}</span>
      </DialogActionButton>
      <DialogActionButton
        onClick={requestClose}
        tone={closeTone}
        style={closeStyle}
      >
        <ComposerIcon name="close" size={14} />
        <span>{t('common.close', '关闭')}</span>
      </DialogActionButton>
    </div>
  );
}

interface MergeServerWindowOptions {
  preserveLocalStreamingTail?: boolean;
}

interface MergeServerWindowResult {
  items: SessionMessage[];
  offset: number;
}

function isRunningPhase(phase: string | null | undefined): boolean {
  return Boolean(phase && phase !== 'idle');
}

function shouldApplyPollingMessageWindow(sseLive: boolean, pollSendPhase: string | null | undefined): boolean {
  return !sseLive || !isRunningPhase(pollSendPhase);
}

function shouldApplySessionAsyncResult(currentSessionId: string, requestSessionId: string, componentMounted = true): boolean {
  return componentMounted && requestSessionId.length > 0 && currentSessionId === requestSessionId;
}

function isStreamingTailMessage(message: SessionMessage): boolean {
  return message.role === 'assistant' || message.role === 'tool';
}

function isAssistantTextLikeMessage(message: SessionMessage): boolean {
  if (message.role !== 'assistant') return false;
  return !['tool', 'tool_call', 'mcp', 'skill', 'hook', 'status', 'compression_point', 'file_mutation_summary', 'self_learning'].includes(message.kind);
}

function messageMetadataStreaming(message: SessionMessage): boolean {
  return booleanFromUnknown(message.metadata?.streaming);
}

function messageWithFeedback(
  message: SessionMessage,
  feedback: SessionMessageFeedback | null,
): SessionMessage {
  const metadata = { ...(message.metadata ?? {}) };
  if (feedback == null) {
    delete metadata['message_feedback'];
  } else {
    metadata['message_feedback'] = feedback;
  }
  return { ...message, feedback, metadata };
}

function metadataTextLength(value: unknown): number {
  if (typeof value === 'string') return value.length;
  if (value == null) return 0;
  return stringifyJsonSafely(value)?.length ?? String(value).length;
}

const MESSAGE_RENDER_METADATA_KEYS = [
  'streaming',
  'content_format',
  'tool_call_id',
  'tool_name',
  'name',
  'tool_arguments',
  'tool_arguments_streaming',
  'tool_execution_stdout',
  'tool_execution_stderr',
  'tool_execution_result',
  'result_text',
  'tool_execution_status',
  'tool_status',
  'status',
  'tool_execution_command',
  'command',
  'tool_execution_working_directory',
  'working_directory',
  'tool_execution_elapsed_ms',
  'tool_execution_duration_ms',
  'tool_execution_exit_code',
  'exit_code',
  'sandbox_applied',
  'sandbox_blocked',
  'sandbox_backend',
  'sandbox_unavailable_reason',
  'sandbox_proxy_enabled',
  'sandbox_proxy_http_port',
  'sandbox_proxy_socks_port',
  'file_mutation_kind',
  'file_mutation_path',
  'read_file_path',
  'file_mutation_paths',
  'file_mutation_write_reason',
  'write_analysis_reason',
  'tool_execution_write_analysis_reason',
  'round_summary_record_count',
  'mcp_server_name',
  'mcp_tool_name',
  'tool_source',
  'plan_mode_awaiting_approval',
  'plan_mode_approved',
  'attachments',
  'attachment_count',
  'generated_image_paths',
  'generated_video_paths',
  'generated_audio_paths',
  'creation_request',
  'conversation_mode',
  'user_skill_selection',
  'selected_skill',
  'knowledge_base',
  'message_feedback',
  'response_variants',
  'response_variant_index',
] as const;

const metadataRenderFingerprintCache = new WeakMap<object, string>();
const messageRenderSignatureCache = new WeakMap<SessionMessage, string>();

function metadataValueFingerprint(value: unknown): string {
  if (value == null) return '';
  if (typeof value === 'string') {
    return `${value.length}:${value.slice(0, 48)}:${value.slice(-24)}`;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return `json:${metadataTextLength(value)}`;
}

function metadataRenderFingerprint(value: unknown): string {
  const meta = recordOrNullFromUnknown(value);
  if (!meta) return '';
  const cached = metadataRenderFingerprintCache.get(meta);
  if (cached != null) return cached;
  const fingerprint = MESSAGE_RENDER_METADATA_KEYS
    .map((key) => `${key}=${metadataValueFingerprint(meta[key])}`)
    .join('|');
  metadataRenderFingerprintCache.set(meta, fingerprint);
  return fingerprint;
}

function usageRenderFingerprint(message: SessionMessage): string {
  const usage = message.usage;
  if (!usage) return '';
  return [
    usage.prompt_tokens ?? '',
    usage.completion_tokens ?? '',
    usage.total_tokens ?? '',
    usage.cache_read_tokens ?? '',
    usage.cache_creation_tokens ?? '',
    usage.reasoning_tokens ?? '',
    usage.audio_input_tokens ?? '',
    usage.image_input_tokens ?? '',
    usage.video_input_tokens ?? '',
    usage.web_search_tool_usage ?? '',
    usage.web_search_page_usage ?? '',
  ].join(':');
}

function messageRenderSignature(message: SessionMessage): string {
  const cached = messageRenderSignatureCache.get(message);
  if (cached != null) return cached;
  const content = message.content ?? '';
  const signature = [
    message.id,
    message.role,
    message.kind,
    content.length,
    content.slice(0, 64),
    content.slice(-32),
    message.character_count ?? 0,
    message.created_at,
    message.model_id ?? '',
    message.model_label ?? '',
    message.feedback ?? '',
    usageRenderFingerprint(message),
    metadataRenderFingerprint(message.metadata),
  ].join('|');
  messageRenderSignatureCache.set(message, signature);
  return signature;
}

/// 渲染等价比较（与 messageRenderSignature 同一组判据，但分层短路）：
/// - SSE 每 chunk 都会 JSON.parse 出全新对象，签名 WeakMap 必然 miss；
///   整签名重建要对 attachments/response_variants 等对象值做完整 JSON
///   序列化，窗口 × 12.5次/秒 是稳定的主线程税。
/// - 流式尾消息在 content 长度处即返回 false，完全跳过 metadata 指纹；
/// - 未变前缀逐键比较：原始值 === 快速通过（字符串比较是原生 memcmp），
///   仅对象值才回退指纹比较，且首个差异即止。
function messagesEquivalentForRender(a: SessionMessage, b: SessionMessage): boolean {
  if (a === b) return true;
  const contentA = a.content ?? '';
  const contentB = b.content ?? '';
  if (
    a.id !== b.id
    || a.role !== b.role
    || a.kind !== b.kind
    || contentA.length !== contentB.length
    || (a.character_count ?? 0) !== (b.character_count ?? 0)
    || a.created_at !== b.created_at
    || (a.model_id ?? '') !== (b.model_id ?? '')
    || (a.model_label ?? '') !== (b.model_label ?? '')
    || (a.feedback ?? '') !== (b.feedback ?? '')
  ) {
    return false;
  }
  if (
    contentA.slice(0, 64) !== contentB.slice(0, 64)
    || contentA.slice(-32) !== contentB.slice(-32)
  ) {
    return false;
  }
  if (usageRenderFingerprint(a) !== usageRenderFingerprint(b)) return false;
  return metadataEquivalentForRender(a.metadata, b.metadata);
}

function metadataEquivalentForRender(rawA: unknown, rawB: unknown): boolean {
  if (rawA === rawB) return true;
  const a = recordOrNullFromUnknown(rawA);
  const b = recordOrNullFromUnknown(rawB);
  if (!a || !b) {
    return metadataRenderFingerprint(rawA) === metadataRenderFingerprint(rawB);
  }
  for (const key of MESSAGE_RENDER_METADATA_KEYS) {
    const valueA = a[key];
    const valueB = b[key];
    if (valueA === valueB) continue;
    if (metadataValueFingerprint(valueA) !== metadataValueFingerprint(valueB)) {
      return false;
    }
  }
  return true;
}

function messageFollowSignature(message: SessionMessage): string {
  return messageRenderSignature(message);
}

function toolMessageHasOutput(metadata: Record<string, unknown> | null): boolean {
  if (!metadata) return false;
  return (
    stringFromUnknown(metadata['tool_execution_stdout']).length > 0 ||
    stringFromUnknown(metadata['tool_execution_stderr']).length > 0 ||
    stringFromUnknown(metadata['tool_execution_result']).length > 0 ||
    stringFromUnknown(metadata['result_text']).length > 0
  );
}

function isActiveFollowMessage(message: SessionMessage): boolean {
  if (messageMetadataStreaming(message)) return true;
  if (message.kind !== 'tool_call' && message.kind !== 'hook') return false;
  const metadata = recordOrNullFromUnknown(message.metadata);
  if (booleanFromUnknown(metadata?.['tool_arguments_streaming']) || booleanFromUnknown(metadata?.['tool_preparing'])) {
    return true;
  }
  const status = stringFromUnknown(metadata?.['tool_execution_status'] ?? metadata?.['tool_status'] ?? metadata?.['status']);
  return status.length === 0 && !toolMessageHasOutput(metadata);
}

function shouldKeepLongerStreamingMessage(existing: SessionMessage | undefined, incoming: SessionMessage, options: MergeServerWindowOptions): boolean {
  return Boolean(options.preserveLocalStreamingTail && existing && existing.id === incoming.id && existing.kind === incoming.kind && existing.role === incoming.role && isStreamingTailMessage(existing) && existing.content.length > incoming.content.length);
}

/// 流式增量合并：保留与上一次 snapshot 相同的对象引用，仅替换发生变化的尾巴消息。
/// 使 `<MessageCard memo>` 在 SSE 80ms 推流期间跳过不变前缀的重新 diff，
/// 让流式更新感觉真正像"逐字增长"而不是"全帧重排"。
function mergeStream(prev: SessionMessage[], next: SessionMessage[], options: MergeServerWindowOptions = {}): SessionMessage[] {
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
    } else if (a && messagesEquivalentForRender(a, b)) {
      out[i] = a;
    } else {
      out[i] = b;
      identical = false;
    }
  }
  return identical ? prev : out;
}

function appendLocalStreamingTail(prev: SessionMessage[], merged: SessionMessage[]): SessionMessage[] {
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

function mergeServerWindowResult(prev: SessionMessage[], latest: SessionMessage[], currentOffset: number, nextOffset: number, options: MergeServerWindowOptions = {}): MergeServerWindowResult {
  if (prev.length === 0) return { items: latest, offset: nextOffset };
  if (options.preserveLocalStreamingTail && latest.length === 0) {
    return { items: prev, offset: currentOffset };
  }
  if (nextOffset < currentOffset) {
    if (options.preserveLocalStreamingTail) {
      const firstPrev = prev[0];
      const overlapIndex = firstPrev ? latest.findIndex((item) => item.id === firstPrev.id) : -1;
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
      items: options.preserveLocalStreamingTail ? appendLocalStreamingTail(prev, merged) : merged,
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
        const merged = [...prefix, ...mergeStream(prev.slice(prefixCount + overlapIndex), latest, options)];
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
    items: options.preserveLocalStreamingTail ? appendLocalStreamingTail(prev, merged) : merged,
    offset: currentOffset,
  };
}

function sessionModeLabel(mode: string): string {
  if (mode === 'plan') return t('sessions.mode.plan', '计划模式');
  if (mode === 'goal') return t('sessions.mode.goal', '目标模式');
  return t('sessions.mode.chat', '聊天模式');
}

function isActiveGoalStatus(status: string | null | undefined): boolean {
  return status === 'running' || status === 'paused';
}

const GOAL_PAUSED_FOR_QUEUE_STATUS_REASON = 'Paused for queued user messages.';

function isGoalPausedForQueuedMessages(goal: SessionGoalRecord | null | undefined): boolean {
  return goal?.status === 'paused' && goal.status_reason === GOAL_PAUSED_FOR_QUEUE_STATUS_REASON;
}

function goalStatusLabel(status: string | null | undefined): string {
  switch (status) {
    case 'running':
      return t('goal.status.running', '运行中');
    case 'paused':
      return t('goal.status.paused', '已暂停');
    case 'completed':
      return t('goal.status.completed', '已完成');
    case 'terminated':
      return t('goal.status.terminated', '已终止');
    case 'failed':
      return t('goal.status.failed', '失败');
    case 'round_limit_reached':
      return t('goal.status.roundLimitReached', '轮次耗尽');
    case 'token_budget_reached':
      return t('goal.status.tokenBudgetReached', '预算耗尽');
    default:
      return t('goal.status.unknown', '未知');
  }
}

function goalStatusReasonLabel(reason: string | null | undefined): string {
  const normalized = stringFromUnknown(reason);
  switch (normalized) {
    case 'Paused by user.':
      return t('goal.reason.pausedByUser', '用户已暂停目标。');
    case GOAL_PAUSED_FOR_QUEUE_STATUS_REASON:
      return t('goal.reason.pausedForQueue', '已让出给等待队列中的消息。');
    case 'Terminated by user.':
      return t('goal.reason.terminatedByUser', '用户已终止目标。');
    case 'Resumed by goal runtime.':
      return t('goal.reason.resumedByRuntime', '目标运行时已恢复执行。');
    case 'Token budget reached before evaluation.':
      return t('goal.reason.tokenBudgetBeforeEvaluation', '评估前已达到 token 预算。');
    case 'No evaluator model is configured.':
      return t('goal.reason.noEvaluatorModel', '未配置可用评估模型。');
    case 'Round limit reached before evidence was sufficient.':
      return t('goal.reason.roundLimitBeforeEvidence', '证据充分前已达到轮次限制。');
    case 'Token budget reached before evidence was sufficient.':
      return t('goal.reason.tokenBudgetBeforeEvidence', '证据充分前已达到 token 预算。');
    default:
      return normalized;
  }
}

function goalEvaluationSummaryLabel(summary: string | null | undefined): string {
  const normalized = stringFromUnknown(summary);
  switch (normalized) {
    case 'Evaluator failed.':
      return t('goal.evaluation.summary.failed', '评估模型调用失败。');
    case 'Evaluator returned invalid JSON.':
      return t('goal.evaluation.summary.invalidJson', '评估模型返回了无效 JSON。');
    case 'Goal is complete.':
      return t('goal.evaluation.summary.complete', '目标已完成。');
    case 'Goal is not complete yet.':
      return t('goal.evaluation.summary.incomplete', '目标尚未完成。');
    default:
      return normalized;
  }
}

function goalDisplayTurnLimit(goal: SessionGoalRecord): number {
  const configured = typeof goal.max_turns === 'number' ? Math.round(goal.max_turns) : 0;
  return Math.round(clampNumber(configured || GOAL_DEFAULT_MAX_AUTO_TURNS, 1, GOAL_HARD_MAX_AUTO_TURNS));
}

function goalProgressLabel(goal: SessionGoalRecord): string {
  const turns = `${Math.max(0, goal.turn_count ?? 0)}/${goalDisplayTurnLimit(goal)}`;
  const budget = goal.token_budget != null
    ? ` · ${Math.max(0, goal.tokens_used ?? 0).toLocaleString()}/${goal.token_budget.toLocaleString()} tok`
    : '';
  return `${goalStatusLabel(goal.status)} · ${turns}${budget}`;
}

function latestGoalRecord(goalState: SessionGoalState | null | undefined): SessionGoalRecord | null {
  if (goalState?.current) return goalState.current;
  const history = goalState?.history ?? [];
  return history.length > 0 ? history[history.length - 1]! : null;
}

function goalOptionsFromRecord(goal: SessionGoalRecord | null): GoalStartOptions | null {
  const evaluatorProviderConfigId = (goal?.evaluator_provider_config_id ?? '').trim();
  const evaluatorModelId = (goal?.evaluator_model_id ?? '').trim();
  if (!evaluatorProviderConfigId || !evaluatorModelId) return null;
  const evaluatorModelLabel = (goal?.evaluator_model_label ?? '').trim() || evaluatorModelId;
  return {
    evaluator_provider_config_id: evaluatorProviderConfigId,
    evaluator_model_id: evaluatorModelId,
    evaluator_model_label: evaluatorModelLabel,
    max_turns: goal?.max_turns ?? null,
    token_budget: goal?.token_budget ?? null,
  };
}

function messageKnowledgeBaseMetadata(message: SessionMessage): Record<string, unknown> | null {
  const metadata = recordOrNullFromUnknown(message.metadata);
  return recordOrNullFromUnknown(metadata?.[KNOWLEDGE_BASE_MESSAGE_METADATA_KEY]);
}

function messageKnowledgeBaseHasReferences(metadata: Record<string, unknown> | null): boolean {
  const results = metadata?.['results'];
  return metadata?.['enabled'] === true &&
    metadata?.['status'] === 'success' &&
    Array.isArray(results) &&
    results.length > 0;
}

function knowledgeBaseResultMaps(metadata: Record<string, unknown> | null): Record<string, unknown>[] {
  const results = metadata?.['results'];
  if (!Array.isArray(results)) return [];
  return results
    .map((item) => recordOrNullFromUnknown(item))
    .filter((item): item is Record<string, unknown> => item != null);
}

function knowledgeBaseMetadataUsedByAnswer(
  metadata: Record<string, unknown> | null,
  answerText: string,
): Record<string, unknown> | null {
  if (!messageKnowledgeBaseHasReferences(metadata)) return null;
  const usedResults = knowledgeBaseResultsUsedByAnswer(
    knowledgeBaseResultMaps(metadata),
    answerText,
    {
      coerceValues: true,
      hitKey: knowledgeBaseCitationKey,
    },
  );
  if (usedResults.length === 0) return null;
  const promptAppend = recordOrNullFromUnknown(metadata?.['prompt_append']) ?? {};
  const tokenEstimate = knowledgeBaseHitTokenEstimateTotal(usedResults);
  return {
    ...(metadata ?? {}),
    results: usedResults,
    prompt_append: {
      ...promptAppend,
      chunk_count: usedResults.length,
      ...(tokenEstimate > 0 ? { token_estimate: tokenEstimate } : {}),
    },
  };
}

function knowledgeBaseCitationKey(hit: Record<string, unknown>): string {
  const sourceId = stringFromUnknown(hit['source_id']);
  if (sourceId) return `source:${sourceId}`;
  const path = stringFromUnknown(hit['path']) || stringFromUnknown(hit['original_path']);
  if (path) return `path:${path}`;
  const chunkId = stringFromUnknown(hit['chunk_id']) || stringFromUnknown(hit['id']);
  if (chunkId) return `chunk:${chunkId}`;
  return `label:${stringFromUnknown(hit['source_title']) || stringFromUnknown(hit['title'])}`;
}

function knowledgeBaseMetadataFromRoundToolMessages(
  messages: SessionMessage[],
  answerText: string,
): Record<string, unknown> | null {
  const results: Record<string, unknown>[] = [];
  const queries: string[] = [];
  const seen = new Set<string>();
  for (const message of messages) {
    const extracted = knowledgeBaseMetadataFromToolMessage(message);
    if (!extracted) continue;
    const query = stringFromUnknown(extracted['query']);
    if (query) queries.push(query);
    for (const result of knowledgeBaseResultMaps(extracted)) {
      const key = knowledgeBaseCitationKey(result);
      if (seen.has(key)) continue;
      seen.add(key);
      results.push(result);
    }
  }
  if (results.length === 0) return null;
  return knowledgeBaseMetadataUsedByAnswer({
    enabled: true,
    status: 'success',
    query: Array.from(new Set(queries)).join(' | '),
    results,
    prompt_append: {
      chunk_count: results.length,
      token_estimate: knowledgeBaseHitTokenEstimateTotal(results),
    },
    source: 'knowledge_tools',
  }, answerText);
}

function knowledgeBaseMetadataFromToolMessage(message: SessionMessage): Record<string, unknown> | null {
  if (message.kind !== 'tool_call' && message.kind !== 'tool') return null;
  const meta = recordOrNullFromUnknown(message.metadata);
  if (!meta) return null;
  const toolName = stringFromUnknown(meta['tool_name']).toLowerCase();
  const isSearch = toolName === 'knowledgesearch' || toolName === 'knowledge_search';
  const isRead = toolName === 'knowledgeread' || toolName === 'knowledge_read';
  if (!isSearch && !isRead) return null;
  const status = stringFromUnknown(meta['tool_execution_status'] ?? meta['status']).toLowerCase();
  if (status && status !== 'success' && status !== 'ok' && status !== 'completed') return null;
  const rawResults = knowledgeToolResultRows(meta);
  if (rawResults.length === 0) return null;
  const results = rawResults
    .map((row) => (isRead ? knowledgeReadRowToMessageHit(row) : knowledgeSearchRowToHit(row)))
    .filter((hit) => stringFromUnknown(hit['source_title']) || stringFromUnknown(hit['title']) || stringFromUnknown(hit['path']) || stringFromUnknown(hit['chunk_id']));
  if (results.length === 0) return null;
  return {
    enabled: true,
    status: 'success',
    query: knowledgeToolQuery(meta, isRead),
    results,
    prompt_append: {
      chunk_count: results.length,
      token_estimate: knowledgeBaseHitTokenEstimateTotal(results),
    },
  };
}

function knowledgeToolResultRows(metadata: Record<string, unknown>): Record<string, unknown>[] {
  const direct = metadata['results'];
  if (Array.isArray(direct)) {
    return direct
      .map((item) => recordOrNullFromUnknown(item))
      .filter((item): item is Record<string, unknown> => item != null);
  }
  const resultText = stringFromUnknown(metadata['tool_execution_result'] ?? metadata['result_text']);
  if (!resultText) return [];
  const results = parseJsonRecordSafely(resultText)?.['results'];
  if (!Array.isArray(results)) return [];
  return results
    .map((item) => recordOrNullFromUnknown(item))
    .filter((item): item is Record<string, unknown> => item != null);
}

function knowledgeToolQuery(metadata: Record<string, unknown>, isRead: boolean): string {
  const direct = stringFromUnknown(metadata['query']);
  if (direct) return direct;
  const args = knowledgeToolArguments(metadata['tool_arguments']);
  if (!isRead) return stringFromUnknown(args['query']);
  const chunkId = stringFromUnknown(args['chunk_id']) || stringFromUnknown(metadata['chunk_id']);
  if (chunkId) return `chunk_id:${chunkId}`;
  const sourceId = stringFromUnknown(args['source_id']) || stringFromUnknown(metadata['source_id']);
  return sourceId ? `source_id:${sourceId}` : '';
}

function knowledgeToolArguments(raw: unknown): Record<string, unknown> {
  const direct = recordOrNullFromUnknown(raw);
  if (direct) return direct;
  const text = stringFromUnknown(raw);
  if (!text) return {};
  return parseJsonRecordSafely(text) ?? {};
}

function knowledgeSearchRowToHit(row: Record<string, unknown>): Record<string, unknown> {
  return {
    ...row,
    title: row['title'] ?? row['source_title'],
    path: row['path'] ?? row['original_path'],
  };
}

function knowledgeReadRowToMessageHit(row: Record<string, unknown>): Record<string, unknown> {
  const content = stringFromUnknown(row['content']);
  const existingPreview = stringFromUnknown(row['preview']);
  const previewSource = existingPreview || content;
  return {
    chunk_id: row['chunk_id'] ?? row['id'],
    source_id: row['source_id'],
    title: row['source_title'] ?? row['title'],
    path: row['original_path'] ?? row['path'],
    source_kind: row['kind'] ?? row['source_kind'],
    document_time: row['document_time'],
    updated_at: row['updated_at'],
    token_estimate: row['token_estimate'],
    heading_path: row['heading_path'],
    preview: truncateEndText(previewSource, KNOWLEDGE_USAGE_PREVIEW_MAX_CHARS, {
      ellipsis: '...',
    }),
  };
}

interface AssociatedKnowledgeBaseBuildCache {
  messages: SessionMessage[];
  result: Map<string, Record<string, unknown>>;
}

/// 按对象引用识别公共消息前缀，仅从最近的用户回合边界重放知识库引用。
function buildAssociatedKnowledgeBaseMetadataByMessageId(
  messages: SessionMessage[],
  buildCache?: { current: AssociatedKnowledgeBaseBuildCache | null },
): Map<string, Record<string, unknown>> {
  const previous = buildCache?.current;
  const result = new Map<string, Record<string, unknown>>();
  let startIndex = 0;
  if (previous && previous.messages.length > 0 && messages.length > 0) {
    const shared = Math.min(previous.messages.length, messages.length);
    let prefix = 0;
    while (prefix < shared && previous.messages[prefix] === messages[prefix]) {
      prefix += 1;
    }
    // 回退到 prefix 内最近的 user 边界（replayFrom 指向该 user 本身或 0），
    // 保证重放起点的回合状态从空开始。
    let replayFrom = Math.min(prefix, messages.length);
    while (replayFrom > 0 && messages[replayFrom]?.kind !== 'user') {
      replayFrom -= 1;
    }
    for (let index = 0; index < replayFrom; index += 1) {
      const cachedValue = previous.result.get(messages[index]!.id);
      if (cachedValue) result.set(messages[index]!.id, cachedValue);
    }
    startIndex = replayFrom;
  }

  let roundCandidates: SessionMessage[] = [];
  let pendingUserMetadata: Record<string, unknown> | null = null;

  for (let index = startIndex; index < messages.length; index += 1) {
    const message = messages[index]!;
    if (message.kind === 'user') {
      const metadata = messageKnowledgeBaseMetadata(message);
      pendingUserMetadata = messageKnowledgeBaseHasReferences(metadata) ? metadata : null;
      roundCandidates = [];
      continue;
    }

    if (message.kind !== 'assistant') {
      roundCandidates.push(message);
      continue;
    }

    // 与 APP 端一致：流式中的助手消息不展示知识库引用，内容每 chunk 都在
    // 变化，对半成品做全文匹配是纯浪费；流结束后的稳定实例会重新计算。
    if (!messageMetadataStreaming(message)) {
      const directMetadata = messageKnowledgeBaseMetadata(message);
      const usedDirectMetadata = knowledgeBaseMetadataUsedByAnswer(directMetadata, message.content);
      const usedUserMetadata = usedDirectMetadata
        ? null
        : knowledgeBaseMetadataUsedByAnswer(pendingUserMetadata, message.content);
      const usedToolMetadata = usedDirectMetadata || usedUserMetadata
        ? null
        : knowledgeBaseMetadataFromRoundToolMessages(roundCandidates, message.content);
      const metadata = usedDirectMetadata ?? usedUserMetadata ?? usedToolMetadata;
      if (metadata) {
        result.set(message.id, metadata);
      }
    }

    if (message.content.trim().length > 0) {
      pendingUserMetadata = null;
      roundCandidates = [];
    }
  }

  if (buildCache) {
    buildCache.current = { messages, result };
  }
  return result;
}

interface AssociatedKnowledgeBaseCacheEntry {
  signature: string;
  value: Record<string, unknown>;
}

function associatedKnowledgeBaseMetadataSignature(metadata: Record<string, unknown>): string {
  return stringifyJsonSafely(metadata) ?? `fallback:${metadataTextLength(metadata)}`;
}

function stabilizeAssociatedKnowledgeBaseMetadataByMessageId(
  next: Map<string, Record<string, unknown>>,
  cache: Map<string, AssociatedKnowledgeBaseCacheEntry>,
): Map<string, Record<string, unknown>> {
  if (next.size === 0) {
    cache.clear();
    return next;
  }
  const stable = new Map<string, Record<string, unknown>>();
  const nextCache = new Map<string, AssociatedKnowledgeBaseCacheEntry>();
  for (const [messageId, metadata] of next) {
    const cached = cache.get(messageId);
    // 同引用快速路径：增量重放复用的条目无需再做整段 JSON 序列化签名。
    if (cached && cached.value === metadata) {
      stable.set(messageId, metadata);
      nextCache.set(messageId, cached);
      continue;
    }
    const signature = associatedKnowledgeBaseMetadataSignature(metadata);
    const value = cached?.signature === signature ? cached.value : metadata;
    stable.set(messageId, value);
    nextCache.set(messageId, { signature, value });
  }
  cache.clear();
  for (const [messageId, entry] of nextCache) {
    cache.set(messageId, entry);
  }
  return stable;
}

type ComposerIconName = 'attachment' | 'chat' | 'chevronDown' | 'chevronUp' | 'close' | 'copy' | 'edit' | 'file' | 'follow' | 'goal' | 'guide' | 'history' | 'image' | 'knowledge' | 'model' | 'mode' | 'pause' | 'plan' | 'play' | 'permission' | 'plus' | 'research' | 'refresh' | 'restore' | 'send' | 'sound' | 'spark' | 'stop' | 'trash' | 'video';

function sessionModeIconName(mode: string): ComposerIconName {
  if (mode === 'plan') return 'plan';
  if (mode === 'goal') return 'goal';
  return 'chat';
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
  // 描边属性挂在 <svg> 上由子元素继承，无需逐个图形重复下发。
  const common = svgIconProps({ size });
  switch (name) {
    case 'attachment':
      return (
        <svg {...common}>
          <path d="M21.4 11.6 12 21a5.2 5.2 0 0 1-7.4-7.4l9.7-9.7a3.5 3.5 0 0 1 5 5l-9.8 9.8a1.8 1.8 0 0 1-2.6-2.6l8.9-8.9" />
        </svg>
      );
    case 'chat':
      return (
        <svg {...common}>
          <path d="M5 6.5A3.5 3.5 0 0 1 8.5 3h7A3.5 3.5 0 0 1 19 6.5v5A3.5 3.5 0 0 1 15.5 15h-4.7L6 19v-4.2a3.5 3.5 0 0 1-1-2.3z" />
          <path d="M9 8h6M9 11h3.8" />
        </svg>
      );
    case 'chevronDown':
      return (
        <svg {...common}>
          <path d="m7 10 5 5 5-5" />
        </svg>
      );
    case 'chevronUp':
      return (
        <svg {...common}>
          <path d="m7 14 5-5 5 5" />
        </svg>
      );
    case 'close':
      return (
        <svg {...common}>
          <path d="M7 7l10 10M17 7 7 17" />
        </svg>
      );
    case 'copy':
      return (
        <svg {...common}>
          <rect x="8" y="8" width="11" height="11" rx="2" />
          <path d="M5 15V7a2 2 0 0 1 2-2h8" />
        </svg>
      );
    case 'edit':
      return (
        <svg {...common}>
          <path d="M4 20h4.4L19 9.4A2.1 2.1 0 0 0 16 6.4L5.4 17H4z" />
          <path d="m14.8 7.6 1.6 1.6" />
        </svg>
      );
    case 'file':
      return (
        <svg {...common}>
          <path d="M7 3h6l4 4v14H7z" />
          <path d="M13 3v5h5M9 13h6M9 17h4" />
        </svg>
      );
    case 'follow':
      return (
        <svg {...common}>
          <path d="M12 5v10M8 11l4 4 4-4M5 19h14" />
        </svg>
      );
    case 'goal':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="7" />
          <circle cx="12" cy="12" r="3" />
          <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
        </svg>
      );
    case 'guide':
      return (
        <svg {...common}>
          <path d="M9 18h6M10 22h4" />
          <path d="M8.2 14.4a6 6 0 1 1 7.6 0c-.8.6-1.1 1.4-1.2 2.6H9.4c-.1-1.2-.4-2-1.2-2.6z" />
          <path d="M12 7.5V11l2 1.2" />
        </svg>
      );
    case 'history':
      return (
        <svg {...common}>
          <path d="M3 12a9 9 0 1 0 3-6.7" />
          <path d="M3 4.5v4h4" />
          <path d="M12 7v5l3 2" />
        </svg>
      );
    case 'refresh':
      return (
        <svg {...common}>
          <path d="M4 12a8 8 0 0 1 13.4-5.9" />
          <path d="M17 3v4h-4" />
          <path d="M20 12a8 8 0 0 1-13.4 5.9" />
          <path d="M7 21v-4h4" />
        </svg>
      );
    case 'image':
      return (
        <svg {...common}>
          <path d="M5 5h14v14H5z" />
          <path d="m5 16 4.5-4.5 3.5 3.5 2-2 4 4" />
          <path d="M14.5 8.5h.01" />
        </svg>
      );
    case 'knowledge':
      return (
        <svg {...common}>
          <path d="M5 5.8A2.8 2.8 0 0 1 7.8 3H19v15H8a3 3 0 0 0-3 3z" />
          <path d="M5 5.8V21" />
          <path d="M9 7h6M9 11h7M9 15h5" />
        </svg>
      );
    case 'model':
      return (
        <svg {...common}>
          <rect x="7" y="7" width="10" height="10" rx="2" />
          <path d="M9 3v4M15 3v4M9 17v4M15 17v4M3 9h4M3 15h4M17 9h4M17 15h4" />
          <path d="M10 12h4" />
        </svg>
      );
    case 'mode':
      return (
        <svg {...common}>
          <path d="M5 7h8M17 7h2M5 12h2M11 12h8M5 17h10M19 17h0" />
          <path d="M13 5v4M9 10v4M15 15v4" />
        </svg>
      );
    case 'permission':
      return (
        <svg {...common}>
          <path d="M12 3 5 6v5c0 4.4 2.8 8.4 7 10 4.2-1.6 7-5.6 7-10V6z" />
          <path d="m9.5 12 1.7 1.7 3.6-4" />
        </svg>
      );
    case 'pause':
      return (
        <svg {...common}>
          <rect x="7" y="5" width="3.5" height="14" rx="1" />
          <rect x="13.5" y="5" width="3.5" height="14" rx="1" />
        </svg>
      );
    case 'plan':
      return (
        <svg {...common}>
          <path d="M7 4h10a2 2 0 0 1 2 2v14H5V6a2 2 0 0 1 2-2z" />
          <path d="M9 8h6M9 12h6M9 16h3" />
          <path d="m15 16 1.2 1.2L19 14.4" />
        </svg>
      );
    case 'play':
      return (
        <svg {...common}>
          <path d="M8 5v14l11-7z" />
        </svg>
      );
    case 'plus':
      return (
        <svg {...common}>
          <path d="M12 5v14M5 12h14" />
        </svg>
      );
    case 'research':
      return (
        <svg {...common}>
          <path d="M10.5 18a7.5 7.5 0 1 1 5.3-2.2L21 21" />
          <path d="M8 10h5M8 13h3" />
        </svg>
      );
    case 'restore':
      return (
        <svg {...common}>
          <path d="M4 12a8 8 0 1 0 2.7-6" />
          <path d="M4 4.5v5h5" />
          <path d="M12 8v4l3 2" />
        </svg>
      );
    case 'send':
      return (
        <svg {...common}>
          <path d="M4 12 20 4l-5 16-3-7z" />
          <path d="m12 13 4-5" />
        </svg>
      );
    case 'sound':
      return (
        <svg {...common}>
          <path d="M4 10v4h4l5 4V6L8 10z" />
          <path d="M16 9.5a4 4 0 0 1 0 5M19 7a8 8 0 0 1 0 10" />
        </svg>
      );
    case 'spark':
      return (
        <svg {...common}>
          <path d="m12 3 1.6 5.2L19 10l-5.4 1.8L12 17l-1.6-5.2L5 10l5.4-1.8z" />
          <path d="M19 16v4M17 18h4" />
        </svg>
      );
    case 'stop':
      return (
        <svg {...common}>
          <rect x="7" y="7" width="10" height="10" rx="2" />
        </svg>
      );
    case 'trash':
      return (
        <svg {...common}>
          <path d="M4 7h16M9 7V5h6v2M8 10v8M12 10v8M16 10v8" />
          <path d="M6.5 7 7.4 21h9.2l.9-14" />
        </svg>
      );
    case 'video':
      return (
        <svg {...common}>
          <path d="M5 7h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5z" />
          <path d="m17 10 4-2.5v9L17 14" />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <path d="M12 3v18M3 12h18" />
        </svg>
      );
  }
}

const MACHINE_TERMINAL_XTERM_THEME = {
  background: '#0B0D10',
  foreground: '#E7ECF3',
  cursor: '#E6F6C3',
  selectionBackground: '#4D7CFF66',
  black: '#101217',
  red: '#FF6B6B',
  green: '#5FE3A1',
  yellow: '#E8D66B',
  blue: '#75A7FF',
  magenta: '#D98CFF',
  cyan: '#62DCE8',
  white: '#F4F7FB',
  brightBlack: '#6E7681',
  brightRed: '#FF8F86',
  brightGreen: '#7CF3B6',
  brightYellow: '#F4E58D',
  brightBlue: '#9DBDFF',
  brightMagenta: '#E7A8FF',
  brightCyan: '#8FEAF2',
  brightWhite: '#FFFFFF',
} as const;
const MACHINE_TERMINAL_POLL_INTERVAL_MS = 1200;
const MACHINE_TERMINAL_POLL_TIMEOUT_MS = 15_000;

function MachineTerminalPanel({ sessionId }: { sessionId: string }) {
  const shellRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const lastAnsiOutputRef = useRef('');
  const writeErrorShownRef = useRef(false);
  const activeTerminalIdRef = useRef<string | undefined>(undefined);
  const lastResizeRef = useRef('');
  const resizeFrameRef = useRef<number | null>(null);
  const requestTerminalFitRef = useRef<(() => void) | null>(null);
  const [workspace, setWorkspace] = useState<MachineTerminalWorkspace | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [historyRefreshing, setHistoryRefreshing] = useState(false);
  const [detailTerminal, setDetailTerminal] = useState<MachineTerminalSnapshot | null>(null);
  const active = workspace?.active_terminal ?? null;
  const historyDetailsActive = historyOpen || Boolean(detailTerminal);

  useEffect(() => {
    activeTerminalIdRef.current = active?.terminal_id || undefined;
    lastResizeRef.current = '';
    requestTerminalFitRef.current?.();
  }, [active?.terminal_id]);

  const fetchTerminal = useCallback(async (
    start = true,
    options: { includeHistory?: boolean; signal?: AbortSignal } = {},
  ) => {
    const res = await getMachineTerminal(sessionId, {
      start,
      includeHistory: options.includeHistory,
      signal: options.signal,
    });
    return res.terminal;
  }, [sessionId]);

  useEffect(() => {
    const root = shellRef.current;
    if (!root) return;
    const terminal = new Terminal({
      allowProposedApi: false,
      convertEol: true,
      cursorBlink: true,
      cursorStyle: 'block',
      fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", monospace',
      fontSize: 13,
      lineHeight: 1.18,
      scrollback: 5000,
      theme: MACHINE_TERMINAL_XTERM_THEME,
    });
    const fit = new FitAddon();
    terminal.loadAddon(fit);
    terminal.open(root);
    try {
      fit.fit();
    } catch {
      // 布局稳定后由下方定时调整重试。
    }
    terminal.focus();
    terminalRef.current = terminal;
    fitRef.current = fit;
    const dataDisposable = terminal.onData((data) => {
      void writeMachineTerminal(sessionId, { data })
        .then((res) => {
          writeErrorShownRef.current = false;
          if (res.terminal) setWorkspace(res.terminal);
        })
        .catch((error) => {
          if (writeErrorShownRef.current) return;
          writeErrorShownRef.current = true;
          const message = error instanceof Error ? error.message : String(error);
          showSnackbar(`${t('terminal.write.failed', '终端写入失败')}：${message}`, { tone: 'error' });
        });
    });
    const publishResize = () => {
      if (root.clientWidth <= 0 || root.clientHeight <= 0) return;
      try {
        fit.fit();
      } catch {
        return;
      }
      const columns = terminal.cols;
      const rows = terminal.rows;
      if (!Number.isFinite(columns) || !Number.isFinite(rows) || columns <= 0 || rows <= 0) return;
      const key = `${activeTerminalIdRef.current || ''}:${columns}x${rows}`;
      if (lastResizeRef.current === key) return;
      lastResizeRef.current = key;
      void controlMachineTerminal(sessionId, {
        action: 'resize',
        terminalId: activeTerminalIdRef.current,
        columns,
        rows,
      }).catch(() => {
        lastResizeRef.current = '';
      });
    };

    const scheduleResize = () => {
      if (resizeFrameRef.current != null) {
        window.cancelAnimationFrame(resizeFrameRef.current);
      }
      resizeFrameRef.current = window.requestAnimationFrame(() => {
        resizeFrameRef.current = window.requestAnimationFrame(() => {
          resizeFrameRef.current = null;
          publishResize();
        });
      });
    };

    const resizeObserver = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(scheduleResize);
    requestTerminalFitRef.current = scheduleResize;
    resizeObserver?.observe(root);
    if (root.parentElement) resizeObserver?.observe(root.parentElement);
    window.addEventListener('resize', scheduleResize);
    scheduleResize();
    return () => {
      dataDisposable.dispose();
      resizeObserver?.disconnect();
      window.removeEventListener('resize', scheduleResize);
      if (resizeFrameRef.current != null) {
        window.cancelAnimationFrame(resizeFrameRef.current);
        resizeFrameRef.current = null;
      }
      terminal.dispose();
      terminalRef.current = null;
      fitRef.current = null;
      requestTerminalFitRef.current = null;
      lastAnsiOutputRef.current = '';
    };
  }, [sessionId]);

  useAsyncPolling(
    async (isActive, signal) => {
      const next = await fetchTerminal(true, {
        includeHistory: historyDetailsActive,
        signal,
      });
      if (!isActive()) return;
      setWorkspace(next);
      const activeTerminal = next.active_terminal ?? null;
      const ansiOutput = activeTerminal?.ansi_output ?? activeTerminal?.output ?? '';
      const terminal = terminalRef.current;
      if (!terminal) return;
      const previous = lastAnsiOutputRef.current;
      if (ansiOutput.startsWith(previous)) {
        const delta = ansiOutput.slice(previous.length);
        if (delta) terminal.write(delta);
      } else {
        terminal.reset();
        if (ansiOutput) terminal.write(ansiOutput);
      }
      lastAnsiOutputRef.current = ansiOutput;
    },
    {
      intervalMs: MACHINE_TERMINAL_POLL_INTERVAL_MS,
      taskTimeoutMs: MACHINE_TERMINAL_POLL_TIMEOUT_MS,
    },
  );

  async function runControl(
    action: string,
    terminalId?: string,
    options: { includeHistory?: boolean; throwOnError?: boolean } = {},
  ): Promise<void> {
    if (busyAction) return;
    setBusyAction(action);
    try {
      const res = await controlMachineTerminal(sessionId, {
        action,
        terminalId,
        includeHistory: options.includeHistory,
      });
      setWorkspace(res.terminal);
      if (action === 'clear' || action === 'select' || action === 'new' || action === 'duplicate' || action === 'close' || action === 'restore' || action === 'delete') {
        lastAnsiOutputRef.current = '';
        terminalRef.current?.reset();
        const nextActive = res.terminal.active_terminal ?? null;
        const output = nextActive?.ansi_output ?? nextActive?.output ?? '';
        if (output) terminalRef.current?.write(output);
        lastAnsiOutputRef.current = output;
      }
      terminalRef.current?.focus();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      showSnackbar(`${t('terminal.control.failed', '终端操作失败')}：${message}`, { tone: 'error' });
      if (options.throwOnError) throw error;
    } finally {
      setBusyAction(null);
    }
  }

  async function openHistoryDialog(): Promise<void> {
    setHistoryOpen(true);
    setHistoryRefreshing(true);
    try {
      const next = await fetchTerminal(false, { includeHistory: true });
      setWorkspace(next);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      showSnackbar(`${t('terminal.history.sync.failed', '同步终端历史失败')}：${message}`, { tone: 'error' });
    } finally {
      setHistoryRefreshing(false);
    }
  }

  const tabs = (workspace?.terminals ?? []).filter(terminalAttached);
  const status = active?.status ?? 'starting';
  return (
    <>
      <aside class="oh-machine-terminal-panel">
        <div class="oh-machine-terminal-header">
          <div class="oh-machine-terminal-title">
            <span class="oh-machine-terminal-glyph" aria-hidden>
              <ComposerIcon name="mode" size={18} />
            </span>
            <span class="min-w-0">
              <span class="oh-machine-terminal-title-text">{t('terminal.title', '机器终端')}</span>
              <span class="oh-machine-terminal-subtitle">{active?.identity || t('terminal.starting', '正在启动')}</span>
            </span>
          </div>
          <button
            type="button"
            class="oh-machine-terminal-icon oh-tap-press"
            title={t('terminal.copyId', '复制终端 ID')}
            disabled={!active?.terminal_id}
            onClick={() => active?.terminal_id ? void copyTextToClipboard(active.terminal_id).then(() => showSnackbar(t('terminal.copyId.ok', '终端 ID 已复制'), { tone: 'success' })) : undefined}
          >
            <ComposerIcon name="copy" size={16} />
          </button>
        </div>

        <div class="oh-machine-terminal-chips">
          <span class={`oh-machine-terminal-chip is-${status}`}>{terminalStatusLabel(status)}</span>
          <span class="oh-machine-terminal-chip">{active?.terminal_id || '-'}</span>
          <span class="oh-machine-terminal-chip">PID {active?.pid ?? '-'}</span>
          <span class="oh-machine-terminal-chip">{active ? `${active.columns}x${active.rows}` : '-'}</span>
        </div>

        <div class="oh-machine-terminal-actions">
          <button type="button" title={t('terminal.new', '新建终端')} onClick={() => void runControl('new')} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction)}>
            <ComposerIcon name="plus" size={16} />
          </button>
          <button type="button" title={t('terminal.duplicate', '复制终端')} onClick={() => void runControl('duplicate', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="copy" size={16} />
          </button>
          <button type="button" title={t('terminal.start', '启动')} onClick={() => void runControl('start', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || status === 'running')}>
            <ComposerIcon name="play" size={16} />
          </button>
          <button type="button" title={t('terminal.stop', '停止')} onClick={() => void runControl('stop', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || status !== 'running')}>
            <ComposerIcon name="stop" size={16} />
          </button>
          <button type="button" title={t('terminal.restart', '重启')} onClick={() => void runControl('restart', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="refresh" size={16} />
          </button>
          <button type="button" title={t('terminal.clear', '清屏')} onClick={() => void runControl('clear', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="spark" size={16} />
          </button>
          <button type="button" title={t('terminal.history', '执行历史')} onClick={() => void openHistoryDialog()} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(!workspace || historyRefreshing)}>
            <ComposerIcon name="history" size={16} />
          </button>
          <button type="button" title={t('terminal.close', '关闭终端')} onClick={() => void runControl('close', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="close" size={16} />
          </button>
        </div>

        <div class="oh-machine-terminal-tabs" role="tablist">
          {tabs.map((terminal) => {
            const selected = terminal.terminal_id === workspace?.active_terminal_id;
            return (
              <button
                key={terminal.terminal_id}
                type="button"
                role="tab"
                aria-selected={selected}
                class={`oh-machine-terminal-tab ${selected ? 'is-active' : ''}`}
                onClick={() => selected ? undefined : void runControl('select', terminal.terminal_id)}
              >
                <span class={`oh-machine-terminal-dot is-${terminal.status}`} />
                <span class="truncate">{terminal.terminal_id}</span>
              </button>
            );
          })}
        </div>

        <div class="oh-machine-terminal-viewport" ref={shellRef} />

        <div class="oh-machine-terminal-meta">
          <span class="truncate">{active?.working_directory || '-'}</span>
          <span>{active ? formatLocalTimeSecond(active.updated_at) : '-'}</span>
        </div>
      </aside>
      {historyOpen && workspace ? (
        <MachineTerminalHistoryDialog
          workspace={workspace}
          busyAction={historyRefreshing ? 'history' : busyAction}
          onClose={() => setHistoryOpen(false)}
          onOpenDetails={(terminal) => setDetailTerminal(terminal)}
          onRestore={(terminalId) => runControl('restore', terminalId, { includeHistory: true, throwOnError: true })}
          onDelete={(terminalId) => runControl('delete', terminalId, { includeHistory: true, throwOnError: true })}
        />
      ) : null}
      {detailTerminal ? (
        <MachineTerminalHistoryDetailDialog
          terminal={detailTerminal}
          onClose={() => setDetailTerminal(null)}
        />
      ) : null}
    </>
  );
}

function MachineTerminalHistoryDialog({
  workspace,
  busyAction,
  onClose,
  onOpenDetails,
  onRestore,
  onDelete,
}: {
  workspace: MachineTerminalWorkspace;
  busyAction: string | null;
  onClose: () => void;
  onOpenDetails: (terminal: MachineTerminalSnapshot) => void;
  onRestore: (terminalId: string) => Promise<void>;
  onDelete: (terminalId: string) => Promise<void>;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [restoringId, setRestoringId] = useState<string | null>(null);
  const [pendingDeleteTerminal, setPendingDeleteTerminal] = useState<MachineTerminalSnapshot | null>(null);
  const terminals = workspace.terminals ?? [];
  const attachedCount = terminals.filter(terminalAttached).length;
  const commandTotal = terminals.reduce((total, item) => total + terminalCommandCount(item), 0);
  const outputTotal = terminals.reduce((total, item) => total + terminalHistoryOutputCharacters(item), 0);

  async function confirmDeleteTerminal(): Promise<boolean> {
    const terminal = pendingDeleteTerminal;
    if (!terminal || deletingId || busyAction) return false;
    const terminalId = terminal.terminal_id;
    setDeletingId(terminalId);
    try {
      await onDelete(terminalId);
      showSnackbar(t('terminal.history.delete.ok', '终端会话已删除'), { tone: 'success' });
      return true;
    } catch {
      // runControl 已报告具体错误。
      return false;
    } finally {
      setDeletingId(null);
    }
  }

  async function restoreTerminal(terminal: MachineTerminalSnapshot): Promise<void> {
    if (terminalAttached(terminal) || restoringId || deletingId || busyAction) return;
    const terminalId = terminal.terminal_id;
    setRestoringId(terminalId);
    try {
      await onRestore(terminalId);
      showSnackbar(t('terminal.history.restore.ok', '终端会话已恢复到面板'), { tone: 'success' });
    } catch {
      // runControl 已报告具体错误。
    } finally {
      setRestoringId(null);
    }
  }

  return (
    <>
      <DialogFrame
        closing={closing}
        onRequestClose={requestClose}
        ariaLabel={t('terminal.history.title', '终端执行历史')}
        {...createStandardDialogFrameAppearance({
          overlayTone: 'strong',
          overlayBlurPx: 4,
          panelClassName: 'oh-machine-terminal-history-dialog',
          panelSurface: {
            width: 'min(1180px, calc(100vw - 24px))',
            maxHeight: 'min(86vh, 740px)',
            overflow: 'hidden',
            background: 'var(--m3-surface)',
          },
        })}
      >
        <div class="oh-machine-terminal-dialog-head">
          <span class="oh-machine-terminal-dialog-icon" aria-hidden>
            <ComposerIcon name="history" size={20} />
          </span>
          <div class="min-w-0 flex-1">
            <h2>{t('terminal.history.title', '终端执行历史')}</h2>
            <p>
              {t('terminal.history.subtitle', '当前线程关联终端会话')} {terminals.length} · {t('terminal.history.panelCount', '面板')} {attachedCount} · {t('terminal.history.active', '当前')} {workspace.active_terminal_id || '-'}
            </p>
          </div>
          <button type="button" class="oh-machine-terminal-dialog-close oh-tap-press" onClick={requestClose} title={t('common.close', '关闭')}>
            <ComposerIcon name="close" size={16} />
          </button>
        </div>

        <div class="oh-machine-terminal-history-metrics">
          <MachineTerminalHistoryMetric icon="mode" label={t('terminal.history.metric.terminals', '终端数量')} value={`${terminals.length}`} />
          <MachineTerminalHistoryMetric icon="plan" label={t('terminal.history.metric.commands', '命令记录')} value={`${commandTotal}`} />
          <MachineTerminalHistoryMetric icon="file" label={t('terminal.history.metric.output', '历史输出')} value={formatTerminalHistorySize(outputTotal)} />
        </div>

        <div class="oh-machine-terminal-history-table-shell">
          {terminals.length === 0 ? (
            <div class="oh-machine-terminal-history-empty">{t('terminal.history.empty', '暂无终端会话历史。')}</div>
          ) : (
            <table class="oh-machine-terminal-history-table">
              <colgroup>
                <col class="oh-machine-terminal-history-col-terminal" />
                <col class="oh-machine-terminal-history-col-status" />
                <col class="oh-machine-terminal-history-col-pid" />
                <col class="oh-machine-terminal-history-col-size" />
                <col class="oh-machine-terminal-history-col-commands" />
                <col class="oh-machine-terminal-history-col-output" />
                <col class="oh-machine-terminal-history-col-started" />
                <col class="oh-machine-terminal-history-col-updated" />
                <col class="oh-machine-terminal-history-col-actions" />
              </colgroup>
              <thead>
                <tr>
                  <th>{t('terminal.history.col.terminal', '终端')}</th>
                  <th>{t('terminal.history.col.status', '状态')}</th>
                  <th>PID</th>
                  <th>{t('terminal.history.col.size', '尺寸')}</th>
                  <th>{t('terminal.history.col.commands', '命令')}</th>
                  <th>{t('terminal.history.col.output', '输出')}</th>
                  <th>{t('terminal.history.col.started', '启动时间')}</th>
                  <th>{t('terminal.history.col.updated', '更新时间')}</th>
                  <th class="text-right">{t('terminal.history.col.actions', '操作')}</th>
                </tr>
              </thead>
              <tbody>
                {terminals.map((terminal) => {
                  const active = terminal.terminal_id === workspace.active_terminal_id;
                  const deleting = deletingId === terminal.terminal_id;
                  const restoring = restoringId === terminal.terminal_id;
                  const attached = terminalAttached(terminal);
                  const actionDisabled = Boolean(deleting || restoring || busyAction);
                  return (
                    <tr
                      key={terminal.terminal_id}
                      class={`${active ? 'is-active ' : ''}is-clickable`}
                      tabIndex={actionDisabled ? -1 : 0}
                      title={t('terminal.history.viewDetails', '查看详情')}
                      onClick={() => actionDisabled ? undefined : onOpenDetails(terminal)}
                      onKeyDown={(event) => {
                        if (actionDisabled || (event.key !== 'Enter' && event.key !== ' ')) return;
                        event.preventDefault();
                        onOpenDetails(terminal);
                      }}
                    >
                      <td>
                        <span class="oh-machine-terminal-history-terminal">
                          <span class={`oh-machine-terminal-dot is-${terminal.status}`} />
                          <span class="truncate">{terminal.terminal_id}</span>
                          {active ? <span class="oh-machine-terminal-history-active">{t('terminal.history.active', '当前')}</span> : null}
                          {!attached ? <span class="oh-machine-terminal-history-active is-closed">{t('terminal.history.closed', '已关闭')}</span> : null}
                        </span>
                      </td>
                      <td><span class={`oh-machine-terminal-history-status is-${terminal.status}`}>{terminalStatusLabel(terminal.status)}</span></td>
                      <td class="tabular-nums">{terminal.pid ?? '-'}</td>
                      <td class="tabular-nums">{terminal.columns}x{terminal.rows}</td>
                      <td class="tabular-nums">{terminalCommandCount(terminal)}</td>
                      <td>{formatTerminalHistorySize(terminalHistoryOutputCharacters(terminal))}</td>
                      <td class="oh-machine-terminal-history-time tabular-nums">{formatLocalDateTimeSecond(terminal.started_at)}</td>
                      <td class="oh-machine-terminal-history-time tabular-nums">{formatLocalDateTimeSecond(terminal.updated_at)}</td>
                      <td>
                        <div class="oh-machine-terminal-history-actions">
                          <button
                            type="button"
                            class="oh-machine-terminal-history-action oh-tap-press"
                            onClick={(event) => {
                              event.stopPropagation();
                              onOpenDetails(terminal);
                            }}
                            title={t('terminal.history.viewDetails', '查看详情')}
                            disabled={actionDisabled}
                          >
                            <ComposerIcon name="file" size={15} />
                          </button>
                          <button
                            type="button"
                            class="oh-machine-terminal-history-action oh-tap-press"
                            onClick={(event) => {
                              event.stopPropagation();
                              void restoreTerminal(terminal);
                            }}
                            title={attached ? t('terminal.history.restore.attached', '已在终端面板中') : t('terminal.history.restore', '恢复到终端面板')}
                            disabled={actionDisabled || attached}
                          >
                            <ComposerIcon name={restoring ? 'refresh' : 'restore'} size={15} />
                          </button>
                          <button
                            type="button"
                            class="oh-machine-terminal-history-action is-danger oh-tap-press"
                            onClick={(event) => {
                              event.stopPropagation();
                              setPendingDeleteTerminal(terminal);
                            }}
                            title={t('terminal.history.delete', '删除')}
                            disabled={actionDisabled}
                          >
                            <ComposerIcon name={deleting ? 'refresh' : 'trash'} size={15} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        <div class="oh-machine-terminal-dialog-footer">
          <DialogActionButton onClick={requestClose} tone="ghost">
            <ComposerIcon name="close" size={14} />
            {t('common.close', '关闭')}
          </DialogActionButton>
        </div>
      </DialogFrame>
      {pendingDeleteTerminal ? (
        <ConfirmDialog
          title={t('terminal.history.delete.confirmTitle', '删除终端历史?')}
          body={t(
            'terminal.history.delete.confirmBody',
            `将删除 ${pendingDeleteTerminal.terminal_id} 的会话、命令记录和历史输出，此操作不可恢复。`,
          )}
          danger
          busy={deletingId === pendingDeleteTerminal.terminal_id}
          confirmBeforeClose
          confirmLabel={deletingId === pendingDeleteTerminal.terminal_id ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setPendingDeleteTerminal(null)}
          onConfirm={confirmDeleteTerminal}
          onConfirmSuccess={() => setPendingDeleteTerminal(null)}
        />
      ) : null}
    </>
  );
}

function MachineTerminalHistoryMetric({
  icon,
  label,
  value,
}: {
  icon: ComposerIconName;
  label: string;
  value: string;
}) {
  return (
    <div class="oh-machine-terminal-history-metric">
      <span aria-hidden><ComposerIcon name={icon} size={17} /></span>
      <span class="truncate">{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function MachineTerminalHistoryDetailDialog({
  terminal,
  onClose,
}: {
  terminal: MachineTerminalSnapshot;
  onClose: () => void;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [view, setView] = useState<'commands' | 'replay'>(
    () => (terminal.command_history?.length ? 'commands' : 'replay'),
  );

  useEffect(() => {
    setView(terminal.command_history?.length ? 'commands' : 'replay');
  }, [terminal.terminal_id, terminal.command_history?.length]);

  async function copyDetails(): Promise<void> {
    await copyTextToClipboard(terminalHistoryPlainText(terminal));
    showSnackbar(t('terminal.history.copy.ok', '终端历史详情已复制'), { tone: 'success' });
  }

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      ariaLabel={t('terminal.detail.title', '终端历史详情')}
      {...createStandardDialogFrameAppearance({
        overlayTone: 'strong',
        overlayBlurPx: 4,
        panelClassName: 'oh-machine-terminal-detail-dialog',
        panelSurface: {
          width: 'min(980px, calc(100vw - 32px))',
          maxHeight: 'min(88vh, 780px)',
          overflow: 'hidden',
          background: 'var(--m3-surface)',
        },
      })}
    >
      <div class="oh-machine-terminal-dialog-head">
        <span class="oh-machine-terminal-dialog-icon" aria-hidden>
          <ComposerIcon name="file" size={20} />
        </span>
        <div class="min-w-0 flex-1">
          <h2>{t('terminal.detail.title', '终端历史详情')}</h2>
          <p>
            {terminal.terminal_id} · {formatTerminalHistorySize(terminalHistoryOutputCharacters(terminal))} · {terminalCommandCount(terminal)} {t('terminal.detail.commands', '条命令')}
          </p>
        </div>
        <button type="button" class="oh-machine-terminal-dialog-close oh-tap-press" onClick={() => void copyDetails()} title={t('terminal.history.copy', '复制详情')}>
          <ComposerIcon name="copy" size={16} />
        </button>
        <button type="button" class="oh-machine-terminal-dialog-close oh-tap-press" onClick={requestClose} title={t('common.close', '关闭')}>
          <ComposerIcon name="close" size={16} />
        </button>
      </div>

      <div class="oh-machine-terminal-replay-meta">
        <span class={`oh-machine-terminal-history-status is-${terminal.status}`}>{terminalStatusLabel(terminal.status)}</span>
        <span>{terminal.columns}x{terminal.rows}</span>
        <span>{formatDialogDate(terminal.updated_at)}</span>
      </div>
      <div class="oh-machine-terminal-detail-body">
        <div class="oh-machine-terminal-detail-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={view === 'commands'}
            class={`oh-machine-terminal-detail-tab ${view === 'commands' ? 'is-active' : ''}`}
            onClick={() => setView('commands')}
          >
            <ComposerIcon name="plan" size={15} />
            {t('terminal.detail.tab.commands', '命令输出')}
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={view === 'replay'}
            class={`oh-machine-terminal-detail-tab ${view === 'replay' ? 'is-active' : ''}`}
            onClick={() => setView('replay')}
          >
            <ComposerIcon name="mode" size={15} />
            {t('terminal.detail.tab.replay', '终端回放')}
          </button>
        </div>
        <div class="oh-machine-terminal-detail-pane">
          {view === 'commands'
            ? <MachineTerminalCommandHistoryList terminal={terminal} />
            : <MachineTerminalReplayViewport terminal={terminal} />}
        </div>
      </div>
    </DialogFrame>
  );
}

function MachineTerminalCommandHistoryList({ terminal }: { terminal: MachineTerminalSnapshot }) {
  const commands = terminal.command_history ?? [];
  if (commands.length === 0) {
    return <div class="oh-machine-terminal-history-empty">{t('terminal.detail.commands.empty', '暂无结构化命令记录。')}</div>;
  }
  return (
    <div class="oh-machine-terminal-command-list">
      {commands.map((entry, index) => (
        <article key={entry.id || `${entry.terminal_id}-${index}`} class="oh-machine-terminal-command-card">
          <header class="oh-machine-terminal-command-card-head">
            <span class={`oh-machine-terminal-command-state ${terminalCommandSucceeded(entry) ? 'is-success' : 'is-error'}`}>
              {terminalCommandSucceeded(entry) ? t('terminal.detail.command.ok', '完成') : t('terminal.detail.command.failed', '异常')}
            </span>
            <code>{entry.command}</code>
            <button
              type="button"
              class="oh-machine-terminal-history-action oh-tap-press"
              title={t('terminal.detail.command.copy', '复制输出')}
              onClick={() => {
                void copyTextToClipboard(terminalCommandPlainText(entry)).then(() => {
                  showSnackbar(t('terminal.detail.command.copy.ok', '命令输出已复制'), { tone: 'success' });
                });
              }}
            >
              <ComposerIcon name="copy" size={14} />
            </button>
          </header>
          <div class="oh-machine-terminal-command-meta">
            <span>#{index + 1}</span>
            <span>exit {entry.exit_code ?? '-'}</span>
            <span>{entry.duration_ms}ms</span>
            <span>{formatDialogDate(entry.completed_at)}</span>
            {entry.timed_out ? <span>{t('terminal.detail.command.timeout', '超时')}</span> : null}
          </div>
          <pre class="oh-machine-terminal-command-output">{terminalCommandOutput(entry)}</pre>
        </article>
      ))}
    </div>
  );
}

function MachineTerminalReplayViewport({ terminal }: { terminal: MachineTerminalSnapshot }) {
  const shellRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const root = shellRef.current;
    if (!root) return;
    const replayOutput = terminalReplayAnsiOutput(terminal);
    const replay = new Terminal({
      allowProposedApi: false,
      convertEol: true,
      cursorBlink: false,
      disableStdin: true,
      fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", monospace',
      fontSize: 13,
      lineHeight: 1.18,
      scrollback: 10000,
      theme: MACHINE_TERMINAL_XTERM_THEME,
    });
    const fit = new FitAddon();
    let disposed = false;
    let renderFrame = 0;
    let renderedSize = '';
    replay.loadAddon(fit);
    replay.open(root);

    const renderReplay = () => {
      if (disposed) return;
      fit.fit();
      if (replay.cols <= 0 || replay.rows <= 0) return;
      const sizeKey = `${replay.cols}x${replay.rows}`;
      if (renderedSize === sizeKey) return;
      renderedSize = sizeKey;
      replay.reset();
      fit.fit();
      replay.write(replayOutput, () => {
        if (!disposed) replay.scrollToTop();
      });
    };

    const scheduleRender = () => {
      if (renderFrame) cancelAnimationFrame(renderFrame);
      renderFrame = requestAnimationFrame(() => {
        renderFrame = requestAnimationFrame(() => {
          renderFrame = 0;
          renderReplay();
        });
      });
    };

    const resizeObserver = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(scheduleRender);
    resizeObserver?.observe(root);
    scheduleRender();
    return () => {
      disposed = true;
      if (renderFrame) cancelAnimationFrame(renderFrame);
      resizeObserver?.disconnect();
      replay.dispose();
    };
  }, [terminal]);

  return <div class="oh-machine-terminal-replay-viewport" ref={shellRef} />;
}

function terminalCommandCount(terminal: MachineTerminalSnapshot): number {
  return terminal.command_count ?? terminal.command_history?.length ?? 0;
}

function terminalAttached(terminal: MachineTerminalSnapshot): boolean {
  return terminal.attached !== false;
}

function terminalHistoryOutputCharacters(terminal: MachineTerminalSnapshot): number {
  return terminal.history_output_characters ?? terminal.output_characters ?? 0;
}

type MachineTerminalCommandEntry = NonNullable<MachineTerminalSnapshot['command_history']>[number];

function terminalCommandSucceeded(entry: MachineTerminalCommandEntry): boolean {
  return !entry.timed_out && !entry.error && (entry.exit_code ?? 0) === 0;
}

function terminalCommandOutput(entry: MachineTerminalCommandEntry): string {
  const output = entry.output.trimEnd();
  const error = entry.error?.trim();
  if (output && error) return `${output}\n\nerror: ${error}`;
  if (output) return output;
  if (error) return `error: ${error}`;
  return '(no output)';
}

function terminalCommandPlainText(entry: MachineTerminalCommandEntry): string {
  return [
    `$ ${entry.command}`,
    `terminal_id: ${entry.terminal_id}`,
    `started_at: ${entry.started_at}`,
    `completed_at: ${entry.completed_at}`,
    `duration_ms: ${entry.duration_ms}`,
    `exit_code: ${entry.exit_code ?? '-'}`,
    `timed_out: ${entry.timed_out}`,
    ...(entry.error?.trim() ? [`error: ${entry.error.trim()}`] : []),
    'output:',
    terminalCommandOutput(entry),
  ].join('\n');
}

function terminalHistoryPlainText(terminal: MachineTerminalSnapshot): string {
  const lines = [
    `terminal_id: ${terminal.terminal_id}`,
    `identity: ${terminal.identity}`,
    `status: ${terminal.status}`,
    `shell: ${terminal.shell}`,
    `working_directory: ${terminal.working_directory}`,
    `size: ${terminal.columns}x${terminal.rows}`,
    `attached: ${terminalAttached(terminal)}`,
    `pid: ${terminal.pid ?? '-'}`,
    `started_at: ${terminal.started_at}`,
    `updated_at: ${terminal.updated_at}`,
    `command_count: ${terminalCommandCount(terminal)}`,
    `history_output_characters: ${terminalHistoryOutputCharacters(terminal)}`,
  ];
  const commands = terminal.command_history ?? [];
  if (commands.length > 0) {
    lines.push('', 'commands:');
    for (const entry of commands) {
      lines.push('', `--- ${entry.id} ---`, terminalCommandPlainText(entry));
    }
  }
  const history = (terminal.history_output ?? terminal.output ?? '').trimEnd();
  if (history) {
    lines.push('', 'terminal_output:', history);
  }
  return lines.join('\n').trimEnd();
}

function formatTerminalHistorySize(characters: number): string {
  if (!Number.isFinite(characters) || characters <= 0) return '0';
  if (characters < 1024) return `${Math.round(characters)} chars`;
  const units = ['KB', 'MB', 'GB'];
  let value = characters / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value >= 10 ? value.toFixed(1) : value.toFixed(2)} ${units[unitIndex]}`;
}

function terminalReplayAnsiOutput(terminal: MachineTerminalSnapshot): string {
  const history = (terminal.history_ansi_output ?? '').trimEnd();
  if (history) return history;
  const live = (terminal.ansi_output ?? terminal.output ?? '').trimEnd();
  if (live) return live;
  const commandHistory = terminal.command_history ?? [];
  if (commandHistory.length > 0) {
    return commandHistory.map((entry) => {
      const output = entry.output.trimEnd();
      return [
        `\x1b[38;5;75m$ ${entry.command}\x1b[0m`,
        output,
        `\x1b[38;5;244mexit=${entry.exit_code ?? '-'} timeout=${entry.timed_out} duration=${entry.duration_ms}ms\x1b[0m`,
      ].filter(Boolean).join('\r\n');
    }).join('\r\n\r\n');
  }
  return '\x1b[38;5;245mNo terminal history recorded.\x1b[0m\r\n';
}

function terminalStatusLabel(status: string): string {
  if (status === 'running') return t('terminal.status.running', '运行中');
  if (status === 'starting') return t('terminal.status.starting', '启动中');
  if (status === 'stopped') return t('terminal.status.stopped', '已停止');
  if (status === 'failed') return t('terminal.status.failed', '异常');
  return t('terminal.status.idle', '待机');
}

/// Web composer 用户指令胶囊条（与 App 端 _ComposerInstructionsStrip 1:1 对齐）。
///
/// 增强：
/// - hover/focus 1 秒延时弹出预览卡片，显示 description / 截断后的 body；
///   预览卡片走 OverlayPortal 投射到 body，避开 oh-composer-body 的 overflow: clip
///   与 fullscreen containing block。
/// - Ctrl+1..Ctrl+9（macOS 同时也响应 Meta+1..Meta+9）切换前 9 个胶囊的跳过状态，
///   Ctrl+0 / Meta+0 重置：所有指令重新生效（清空跳过集合）。
function ComposerInstructionsStrip({ entries, skipped, disabled, onToggle, onResetAll, t }: { entries: ApiMetaInstruction[]; skipped: Set<string>; disabled: boolean; onToggle: (id: string) => void; onResetAll?: () => void; t: (key: string, fallback: string) => string }) {
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

  // Ctrl/Meta + 0..9 快捷键：与 App 端 harness 同款思路，
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
    return () =>
      window.removeEventListener('keydown', onKeyDown, {
        capture: true,
      } as EventListenerOptions);
  }, [entries, skipped, disabled, onToggle, onResetAll]);

  function scheduleHover(entry: ApiMetaInstruction, target: HTMLElement): void {
    if (hoverTimerRef.current != null) window.clearTimeout(hoverTimerRef.current);
    hoverTimerRef.current = window.setTimeout(() => {
      hoverTimerRef.current = null;
      setHoverEntry({ entry, rect: target.getBoundingClientRect() });
    }, COMPOSER_INSTRUCTION_HOVER_PREVIEW_DELAY_MS);
  }

  return (
    <div class="oh-composer-instructions-strip mb-3" role="group" aria-label={t('composer.instructions.aria', '当前会话生效的用户指令')}>
      <div class="oh-composer-instructions-strip-list">
        {entries.map((entry, index) => {
          const isSkipped = skipped.has(entry.id);
          const baseTip = entry.description?.trim() ? entry.description : isSkipped ? t('composer.instructions.tooltipSkipped', '点击恢复：本轮临时跳过此指令') : t('composer.instructions.tooltipActive', '点击跳过：本轮临时不携带此指令');
          // 前 9 项追加快捷键提示
          const hotkey = index < 9 ? ` · ${navigator.platform.toLowerCase().includes('mac') ? '⌘' : 'Ctrl'}${index + 1}` : '';
          return (
            <button key={entry.id} type="button" class={`oh-composer-instruction-pill oh-tap-press${isSkipped ? ' is-skipped' : ''}`} data-skipped={isSkipped ? 'true' : 'false'} title={baseTip + hotkey} aria-pressed={isSkipped ? 'false' : 'true'} onClick={() => onToggle(entry.id)} onMouseEnter={(e) => scheduleHover(entry, e.currentTarget as HTMLElement)} onMouseLeave={cancelHover} onFocus={(e) => scheduleHover(entry, e.currentTarget as HTMLElement)} onBlur={cancelHover} disabled={disabled}>
              <span class="oh-composer-instruction-pill-icon" aria-hidden="true">
                <ComposerIcon name="spark" size={14} />
              </span>
              <span class="oh-composer-instruction-pill-label">{entry.name?.trim() || entry.id}</span>
              <span class="oh-composer-instruction-pill-toggle" aria-hidden="true">
                <ComposerIcon name={isSkipped ? 'plus' : 'close'} size={13} />
              </span>
            </button>
          );
        })}
      </div>
      {hoverEntry ? <ComposerInstructionPreviewCard hover={hoverEntry} t={t} /> : null}
    </div>
  );
}

function ComposerInstructionPreviewCard({ hover, t }: { hover: { entry: ApiMetaInstruction; rect: DOMRect }; t: (key: string, fallback: string) => string }) {
  const { entry, rect } = hover;
  // 与 OverlayPortal 注释一致：position: fixed 锚定胶囊矩形。
  // 上方空间不足时下翻，并把 max-height 限在可用空间内，避免上边缘被视口裁切。
  const cardWidth = 360;
  const margin = 12;
  const gap = 10;
  const left = clampNumber(rect.left, margin, Math.max(margin, window.innerWidth - cardWidth - margin));
  const rawAbove = Math.max(0, rect.top - margin - gap);
  const rawBelow = Math.max(0, window.innerHeight - rect.bottom - margin - gap);
  const placeAbove = rawAbove >= 180 || rawAbove >= rawBelow;
  const maxAvailableHeight = clampNumber(window.innerHeight - margin * 2, 120, 480);
  const availableHeight = clampNumber(
    placeAbove ? rawAbove : rawBelow,
    120,
    maxAvailableHeight,
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
      <div class="oh-composer-instruction-preview" data-placement={placeAbove ? 'above' : 'below'} role="tooltip" style={cardStyle}>
        <div class="oh-composer-instruction-preview-title">{entry.name?.trim() || entry.id}</div>
        {description ? <div class="oh-composer-instruction-preview-desc">{description}</div> : null}
        {body ? <pre class="oh-composer-instruction-preview-body">{body}</pre> : <div class="oh-composer-instruction-preview-empty">{t('composer.instructions.previewEmpty', '此指令暂无正文。')}</div>}
        {entry.body_truncated ? <div class="oh-composer-instruction-preview-foot">{t('composer.instructions.previewTruncated', '正文已截断 · 完整内容请在 App 端查看')}</div> : null}
      </div>
    </OverlayPortal>
  );
}

interface EditableAttachmentAsset {
  path: string;
  name: string;
  mime?: string;
}

function pushEditableAttachmentAsset(out: EditableAttachmentAsset[], rawPath: unknown, rawName?: unknown, rawMime?: unknown): void {
  const path = strictStringFromUnknown(rawPath);
  if (!path || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
    return;
  }
  const name = strictStringFromUnknown(rawName);
  const mime = strictStringFromUnknown(rawMime);
  out.push({
    path,
    name: name || basenameFromPath(path),
    mime: mime || undefined,
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
        pushEditableAttachmentAsset(out, item['storage_path'] ?? item['path'] ?? item['file_path'] ?? item['original_source_path'], name, mime);
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

function creationModeFromMessage(message: SessionMessage): string {
  const meta = message.metadata ?? {};
  const creationReq = meta['creation_request'] as Record<string, unknown> | undefined;
  const mode = (creationReq?.['mode'] as string) || (meta['conversation_mode'] as string) || '';
  return mode;
}

function deriveMessageWindowView(
  items: SessionMessage[],
  hasHiddenOlderMessages: boolean,
): SessionMessageWindowView {
  const ordered = displayableTranscriptMessages(items, hasHiddenOlderMessages);
  let lastCreationModeAwaitingAssistant: AwaitingCreationMode | null = null;
  let hasUserMessage = false;
  let latestAssistantMessage: SessionMessage | null = null;
  let latestStreamingTextMessageId: string | null = null;
  const tail = ordered.length > 0 ? ordered[ordered.length - 1]! : null;
  const followParts = tail ? [`tail:${messageFollowSignature(tail)}`] : [];
  let activeFollowCount = 0;
  let creationRequestResolved = false;
  let latestTextLikeAssistantResolved = false;

  for (let index = ordered.length - 1; index >= 0; index -= 1) {
    const message = ordered[index];
    if (!message) continue;

    if (activeFollowCount < 4 && isActiveFollowMessage(message)) {
      followParts.push(`active:${index}:${messageFollowSignature(message)}`);
      activeFollowCount += 1;
    }

    if (message.role === 'assistant') {
      latestAssistantMessage ??= message;
      if (!latestTextLikeAssistantResolved && isAssistantTextLikeMessage(message)) {
        if (messageMetadataStreaming(message)) {
          latestStreamingTextMessageId = message.id;
        }
        latestTextLikeAssistantResolved = true;
      }
      if (!creationRequestResolved && messageHasRenderableTranscriptOutput(message)) {
        creationRequestResolved = true;
      }
      continue;
    }

    if (message.role !== 'user') continue;
    if (!hasUserMessage && (message.content ?? '').trim().length > 0) {
      hasUserMessage = true;
    }
    if (!creationRequestResolved) {
      const mode = creationModeFromMessage(message);
      if (mode === 'image' || mode === 'video' || mode === 'audio') {
        lastCreationModeAwaitingAssistant = mode;
      }
      creationRequestResolved = true;
    }
  }

  return {
    ordered,
    tail,
    tailSignature: tail ? messageFollowSignature(tail) : '',
    followSignature: followParts.join('||'),
    latestAssistantMessage,
    latestStreamingTextMessageId,
    lastCreationModeAwaitingAssistant,
    hasUserMessage,
  };
}

interface MessageWindowMembershipTracker {
  revision: number;
  sessionId: string;
  windowOffset: number;
  messageIds: string[];
}

function updateMessageWindowMembership(
  tracker: MessageWindowMembershipTracker,
  sessionId: string,
  windowOffset: number,
  messages: SessionMessage[],
): string {
  let changed = tracker.sessionId !== sessionId ||
    tracker.windowOffset !== windowOffset ||
    tracker.messageIds.length !== messages.length;
  if (!changed) {
    for (let index = 0; index < messages.length; index += 1) {
      if (tracker.messageIds[index] !== messages[index]?.id) {
        changed = true;
        break;
      }
    }
  }
  if (changed) {
    tracker.revision += 1;
    tracker.sessionId = sessionId;
    tracker.windowOffset = windowOffset;
    tracker.messageIds = messages.map((message) => message.id);
  }
  return `${sessionId}|${tracker.revision}`;
}

interface VirtualMessageListProps {
  messages: SessionMessage[];
  membershipKey: string;
  scrollContainerRef: { current: HTMLElement | null };
  revealTarget: { messageId: string; generation: number } | null;
  highlightedMessageId: string | null;
  onInitialLayoutSettled: () => void;
  renderMessage: (message: SessionMessage) => ComponentChildren;
}

/// 卡片高度动画（WAAPI）期间每帧都会改变 offsetHeight。若照单全收地提交，
/// 一次 300ms 的展开动画就等于 18 帧「测量 → 前缀和重建 → 锚点写 scrollTop」，
/// 主线程被自激循环占满。这里让位给动画，收敛后只提交一次终值；超过上限
/// 仍强制提交，避免无限动画把行高永久钉住。
const MESSAGE_ROW_ANIMATION_DEFER_MAX_FRAMES = 48;

function isMessageRowAnimating(element: HTMLElement): boolean {
  const getAnimations = (element as Element & {
    getAnimations?: (options?: { subtree?: boolean }) => unknown[];
  }).getAnimations;
  if (typeof getAnimations !== 'function') return false;
  return getAnimations.call(element, { subtree: true }).length > 0;
}

function MeasuredMessageRow({
  message,
  onHeightChange,
  highlighted,
  children,
}: {
  message: SessionMessage;
  onHeightChange: (messageId: string, height: number) => void;
  highlighted: boolean;
  children: ComponentChildren;
}) {
  const rowRef = useRef<HTMLLIElement | null>(null);

  useLayoutEffect(() => {
    const element = rowRef.current;
    if (!element) return undefined;
    let frame: number | null = null;
    let deferredFrames = 0;
    const measure = () => {
      frame = null;
      if (
        deferredFrames < MESSAGE_ROW_ANIMATION_DEFER_MAX_FRAMES &&
        isMessageRowAnimating(element)
      ) {
        deferredFrames += 1;
        frame = window.requestAnimationFrame(measure);
        return;
      }
      deferredFrames = 0;
      onHeightChange(message.id, element.offsetHeight);
    };
    frame = window.requestAnimationFrame(measure);
    if (typeof ResizeObserver === 'undefined') {
      return () => {
        if (frame != null) window.cancelAnimationFrame(frame);
      };
    }
    const observer = new ResizeObserver(() => {
      if (frame != null) return;
      frame = window.requestAnimationFrame(measure);
    });
    observer.observe(element);
    return () => {
      observer.disconnect();
      if (frame != null) window.cancelAnimationFrame(frame);
    };
  }, [message.id, onHeightChange]);

  return (
    <li
      ref={rowRef}
      class={`oh-session-message-row${highlighted ? ' is-cache-hit-target' : ''}`}
      data-message-id={message.id}
    >
      {children}
    </li>
  );
}

function VirtualMessageList({
  messages,
  membershipKey,
  scrollContainerRef,
  revealTarget,
  highlightedMessageId,
  onInitialLayoutSettled,
  renderMessage,
}: VirtualMessageListProps) {
  const virtualized = shouldVirtualizeMessageList(messages.length);
  const listRef = useRef<HTMLDivElement | null>(null);
  const rangeFrameRef = useRef<number | null>(null);
  const heightCommitFrameRef = useRef<number | null>(null);
  const heightCommitPendingRef = useRef(false);
  const heightAnchorRef = useRef<{ messageId: string; viewportOffset: number } | null>(null);
  const measuredHeightsRef = useRef(new Map<string, number>());
  const initialLayoutSettledRef = useRef(false);
  const initialLayoutStartedAtRef = useRef(Date.now());
  const [heightRevision, setHeightRevision] = useState(0);
  // 打开会话时贴住底部，首帧只挂载有限尾部，避免首次范围测量前渲染完整长列表。
  const [range, setRange] = useState<VirtualMessageRange>(() =>
    initialVirtualMessageRange(messages.length),
  );

  // 流式更新会替换消息对象但保留窗口内 ID，仅在成员变化时重建高度索引。
  const messageIds = useMemo(
    () => messages.map((message) => message.id),
    [membershipKey],
  );
  const previousMembershipRef = useRef({
    key: membershipKey,
    messageIds,
    virtualized,
  });
  const revealIndex = revealTarget == null
    ? -1
    : messageIds.indexOf(revealTarget.messageId);
  // 高度几何同时写入 ref：范围计算与滚动监听只读 ref，让 updateRange 保持
  // 稳定标识。否则每次测量提交都会重建 heights/prefix → 新函数标识 →
  // scroll/resize 监听与 ResizeObserver 整体拆装，而 RO 挂载时规范要求立刻
  // 回调一次，等于把一次测量放大成两次强制回流。
  const geometryRef = useRef<{ heights: number[]; prefix: number[] }>({
    heights: [],
    prefix: [0],
  });
  const geometry = useMemo(() => {
    const heights = messageIds.map((messageId) =>
      measuredHeightsRef.current.get(messageId) ??
      MESSAGE_LIST_ESTIMATED_ROW_HEIGHT_PX,
    );
    const next = { heights, prefix: buildHeightPrefix(heights) };
    geometryRef.current = next;
    return next;
  }, [heightRevision, messageIds]);
  const heightPrefix = geometry.prefix;
  const totalHeight = virtualMessageTotalHeight(heightPrefix, messages.length);
  const pendingTotalHeightRef = useRef(totalHeight);
  const [stableTotalHeight, setStableTotalHeight] = useState(totalHeight);

  useLayoutEffect(() => {
    pendingTotalHeightRef.current = totalHeight;
    if (!isTranscriptScrollActive()) {
      setStableTotalHeight((current) =>
        Math.abs(current - totalHeight) < 0.5 ? current : totalHeight,
      );
    }
  }, [totalHeight]);

  const previousMembership = previousMembershipRef.current;
  const membershipChanged = previousMembership.key !== membershipKey;
  const enteredVirtualization = virtualized && !previousMembership.virtualized;
  const initialRange = initialVirtualMessageRange(messages.length);
  let renderRange = range;
  if (!virtualized) {
    renderRange = { start: 0, end: messages.length };
  } else if (enteredVirtualization) {
    // 首屏分页低于虚拟化阈值，服务端窗口补齐后应在当前渲染中直接贴回尾部。
    renderRange = initialRange;
  } else if (membershipChanged) {
    // 同长度换窗也必须立即按消息标识重定位，避免先挂载错误范围再二次替换。
    renderRange = rebaseVirtualMessageRange(
      previousMembership.messageIds,
      messageIds,
      range,
    ) ?? initialRange;
  } else if (
    range.end > messages.length ||
    range.start >= messages.length ||
    (messages.length > 0 && range.end - range.start > messages.length)
  ) {
    renderRange = initialRange;
  }

  useLayoutEffect(() => {
    previousMembershipRef.current = { key: membershipKey, messageIds, virtualized };
    if (membershipChanged) {
      const retainedIds = new Set(messageIds);
      for (const messageId of measuredHeightsRef.current.keys()) {
        if (!retainedIds.has(messageId)) {
          measuredHeightsRef.current.delete(messageId);
        }
      }
    }
    setRange((current) =>
      current.start === renderRange.start && current.end === renderRange.end
        ? current
        : renderRange,
    );
  }, [membershipKey, messageIds, renderRange.end, renderRange.start, virtualized]);

  const scheduleHeightCommit = useCallback(() => {
    if (isTranscriptScrollActive()) {
      heightCommitPendingRef.current = true;
      return;
    }
    if (heightCommitFrameRef.current != null) return;
    heightCommitFrameRef.current = window.requestAnimationFrame(() => {
      heightCommitFrameRef.current = null;
      heightCommitPendingRef.current = false;
      const scroller = scrollContainerRef.current;
      const list = listRef.current;
      if (scroller && list) {
        const scrollerRect = scroller.getBoundingClientRect();
        const rows = list.querySelectorAll<HTMLElement>('.oh-session-message-row[data-message-id]');
        for (const row of rows) {
          const rect = row.getBoundingClientRect();
          if (rect.bottom <= scrollerRect.top || rect.top >= scrollerRect.bottom) continue;
          const messageId = row.dataset['messageId'];
          if (messageId) {
            heightAnchorRef.current = {
              messageId,
              viewportOffset: rect.top - scrollerRect.top,
            };
          }
          break;
        }
      }
      setHeightRevision((value) => value + 1);
    });
  }, [scrollContainerRef]);

  const handleHeightChange = useCallback((messageId: string, height: number) => {
    const next = clampMessageRowHeight(height);
    const previous = measuredHeightsRef.current.get(messageId);
    if (previous != null && Math.abs(previous - next) < 1) return;
    measuredHeightsRef.current.set(messageId, next);
    scheduleHeightCommit();
  }, [scheduleHeightCommit]);

  useEffect(() => subscribeTranscriptScrollActivity((active) => {
    if (active) return;
    setStableTotalHeight((current) => {
      const next = pendingTotalHeightRef.current;
      return Math.abs(current - next) < 0.5 ? current : next;
    });
    if (heightCommitPendingRef.current) scheduleHeightCommit();
  }), [scheduleHeightCommit]);

  useLayoutEffect(() => {
    const anchor = heightAnchorRef.current;
    if (!anchor) return;
    heightAnchorRef.current = null;
    const scroller = scrollContainerRef.current;
    const list = listRef.current;
    if (!scroller || !list) return;
    const scrollerRect = scroller.getBoundingClientRect();
    const rows = list.querySelectorAll<HTMLElement>('.oh-session-message-row[data-message-id]');
    for (const row of rows) {
      if (row.dataset['messageId'] !== anchor.messageId) continue;
      const delta = row.getBoundingClientRect().top - scrollerRect.top - anchor.viewportOffset;
      if (Math.abs(delta) >= 0.5) scroller.scrollTop += delta;
      break;
    }
  }, [heightRevision, scrollContainerRef]);

  // 范围计算的输入同样走 ref 镜像，保证 updateRange / scheduleRangeUpdate
  // 的标识在整个组件生命周期内恒定。
  const rangeInputsRef = useRef({
    virtualized,
    messageCount: messages.length,
    revealIndex,
  });
  rangeInputsRef.current = {
    virtualized,
    messageCount: messages.length,
    revealIndex,
  };

  const updateRange = useCallback(() => {
    rangeFrameRef.current = null;
    const {
      virtualized: rangeVirtualized,
      messageCount,
      revealIndex: rangeRevealIndex,
    } = rangeInputsRef.current;
    const applyRange = (next: VirtualMessageRange) => {
      setRange((current) =>
        current.start === next.start && current.end === next.end ? current : next,
      );
    };
    if (!rangeVirtualized) {
      applyRange({ start: 0, end: messageCount });
      return;
    }
    if (rangeRevealIndex >= 0) {
      const seed = initialVirtualMessageRange(messageCount);
      const span = Math.max(1, seed.end - seed.start);
      applyRange(virtualMessageRangeAroundIndex(messageCount, rangeRevealIndex, span));
      return;
    }
    const scroller = scrollContainerRef.current;
    const list = listRef.current;
    if (!scroller || !list || messageCount === 0) {
      applyRange(initialVirtualMessageRange(messageCount));
      return;
    }
    const scrollerRect = scroller.getBoundingClientRect();
    const listRect = list.getBoundingClientRect();
    const listTopInScroller = listRect.top - scrollerRect.top + scroller.scrollTop;
    const viewportTop = Math.max(0, scroller.scrollTop - listTopInScroller);
    const viewportBottom =
      scroller.scrollTop - listTopInScroller + scroller.clientHeight;
    const { heights, prefix } = geometryRef.current;
    applyRange(resolveVirtualMessageRange({
      messageCount,
      prefix,
      heights,
      viewportTop,
      viewportBottom,
      overscanPx: MESSAGE_LIST_VIRTUALIZATION_OVERSCAN_PX,
      virtualized: true,
    }));
  }, [scrollContainerRef]);

  const scheduleRangeUpdate = useCallback(() => {
    if (rangeFrameRef.current != null) return;
    rangeFrameRef.current = window.requestAnimationFrame(updateRange);
  }, [updateRange]);

  useLayoutEffect(() => {
    scheduleRangeUpdate();
  }, [scheduleRangeUpdate, totalHeight, messages.length, revealIndex, virtualized]);

  useEffect(() => {
    const scroller = scrollContainerRef.current;
    if (!scroller) return undefined;
    const onScroll = () => scheduleRangeUpdate();
    scroller.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    const observer = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(onScroll);
    observer?.observe(scroller);
    return () => {
      scroller.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
      observer?.disconnect();
    };
  }, [scheduleRangeUpdate, scrollContainerRef]);

  useEffect(() => () => {
    if (rangeFrameRef.current != null) {
      window.cancelAnimationFrame(rangeFrameRef.current);
      rangeFrameRef.current = null;
    }
    if (heightCommitFrameRef.current != null) {
      window.cancelAnimationFrame(heightCommitFrameRef.current);
      heightCommitFrameRef.current = null;
    }
  }, []);

  useLayoutEffect(() => {
    if (initialLayoutSettledRef.current) return undefined;
    let frame: number | null = null;
    let framesRemaining = TRANSCRIPT_INITIAL_SETTLE_MAX_FRAMES;
    let elapsedFrames = 0;
    let stableFrames = 0;
    let previousScrollHeight: number | null = null;

    const settle = () => {
      frame = null;
      const scroller = scrollContainerRef.current;
      const timedOut =
        Date.now() - initialLayoutStartedAtRef.current >=
        TRANSCRIPT_INITIAL_SETTLE_MAX_MS;
      if (!scroller || framesRemaining <= 0 || timedOut) {
        initialLayoutSettledRef.current = true;
        onInitialLayoutSettled();
        return;
      }
      framesRemaining -= 1;
      elapsedFrames += 1;
      const target = Math.max(0, scroller.scrollHeight - scroller.clientHeight);
      const heightChanged = previousScrollHeight != null &&
        Math.abs(scroller.scrollHeight - previousScrollHeight) >
          TRANSCRIPT_INITIAL_SETTLE_EPSILON_PX;
      previousScrollHeight = scroller.scrollHeight;
      const distance = Math.abs(scroller.scrollTop - target);
      if (distance > TRANSCRIPT_INITIAL_SETTLE_EPSILON_PX) {
        scroller.scrollTop = target;
      }
      const measurementsPending =
        elapsedFrames <= TRANSCRIPT_INITIAL_SETTLE_MEASURE_GRACE_FRAMES &&
        (heightCommitPendingRef.current || heightCommitFrameRef.current != null);
      stableFrames = heightChanged || distance > TRANSCRIPT_INITIAL_SETTLE_EPSILON_PX || measurementsPending
        ? 0
        : stableFrames + 1;
      const ready =
        elapsedFrames >= TRANSCRIPT_INITIAL_SETTLE_MIN_FRAMES &&
        stableFrames >= TRANSCRIPT_INITIAL_SETTLE_STABLE_FRAMES;
      if (ready || framesRemaining <= 0) {
        initialLayoutSettledRef.current = true;
        onInitialLayoutSettled();
        return;
      }
      frame = window.requestAnimationFrame(settle);
    };

    frame = window.requestAnimationFrame(settle);
    return () => {
      if (frame != null) window.cancelAnimationFrame(frame);
    };
  }, [membershipKey, onInitialLayoutSettled, scrollContainerRef]);

  useEffect(() => {
    const liveIds = new Set(messageIds);
    for (const id of measuredHeightsRef.current.keys()) {
      if (!liveIds.has(id)) measuredHeightsRef.current.delete(id);
    }
  }, [messageIds]);

  if (!virtualized) {
    return (
      <ul class="oh-session-message-list flex flex-col gap-3">
        {messages.map((message) => (
          <li
            key={message.id}
            class={`oh-session-message-row${highlightedMessageId === message.id ? ' is-cache-hit-target' : ''}`}
            data-message-id={message.id}
          >
            {renderMessage(message)}
          </li>
        ))}
      </ul>
    );
  }

  const safeStart = Math.min(renderRange.start, messages.length);
  const safeEnd = Math.max(safeStart, Math.min(renderRange.end, messages.length));
  const visibleMessages = messages.slice(safeStart, safeEnd);
  const topSpacer = virtualMessageTop(heightPrefix, safeStart);

  return (
    <div
      ref={listRef}
      class="oh-session-virtual-message-list"
      data-virtualized="true"
      style={{ height: `${Math.max(0, stableTotalHeight)}px` }}
    >
      <ul
        class="oh-session-message-list oh-session-virtual-window flex flex-col gap-3"
        style={{ transform: `translate3d(0, ${Math.max(0, topSpacer)}px, 0)` }}
      >
        {visibleMessages.map((message) => (
          <MeasuredMessageRow
            key={message.id}
            message={message}
            onHeightChange={handleHeightChange}
            highlighted={highlightedMessageId === message.id}
          >
            {renderMessage(message)}
          </MeasuredMessageRow>
        ))}
      </ul>
    </div>
  );
}

function messagesWindowLooksIdentical(prev: SessionMessage[], next: SessionMessage[], prevOffset: number, nextOffset: number): boolean {
  if (prev === next) return prevOffset === nextOffset;
  if (prevOffset !== nextOffset || prev.length !== next.length) return false;
  if (next.length === 0) return true;
  const tailIndex = next.length - 1;
  if (!messagesEquivalentForRender(prev[tailIndex]!, next[tailIndex]!)) {
    return false;
  }
  for (let index = 0; index < tailIndex; index += 1) {
    const a = prev[index];
    const b = next[index];
    if (!a || !b) return false;
    if (
      !messagesEquivalentForRender(a, b)
    ) {
      return false;
    }
  }
  return true;
}

function snapshotMessagesFingerprint(messages: SessionMessage[]): string {
  const count = messages.length;
  if (count === 0) return '0';
  const first = messages[0]!;
  const tail = messages[count - 1]!;
  const previousTail = count > 1 ? messages[count - 2]! : null;
  return [
    count,
    first.id,
    first.content?.length ?? 0,
    previousTail ? messageFollowSignature(previousTail) : '',
    messageFollowSignature(tail),
  ].join('|');
}

function mergeSessionSummary(previous: SessionDetailResponse['session'], incoming: SessionDetailResponse['session']): SessionDetailResponse['session'] {
  const statistics = incoming.statistics == null
    ? previous.statistics
    : previous.statistics == null
    ? incoming.statistics
    : {
        ...previous.statistics,
        ...incoming.statistics,
        cache_hit_trend_points:
          incoming.statistics.cache_hit_trend_points ??
          previous.statistics.cache_hit_trend_points,
      };
  return {
    ...previous,
    ...incoming,
    statistics,
    metadata: incoming.metadata ?? previous.metadata,
    web_context: incoming.web_context ?? previous.web_context,
    environment: incoming.environment ?? previous.environment,
    last_prompt_metadata: incoming.last_prompt_metadata ?? previous.last_prompt_metadata,
    plan_history: incoming.plan_history ?? previous.plan_history,
    goal_state: incoming.goal_state ?? previous.goal_state,
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

type ComposerAttachmentKind = 'image' | 'video' | 'audio' | 'file' | 'unsupported';

function extensionFromName(name: string): string {
  const normalized = name.trim().toLowerCase();
  const dot = normalized.lastIndexOf('.');
  return dot >= 0 && dot < normalized.length - 1 ? normalized.slice(dot + 1) : '';
}

function composerAttachmentKind(name: string, mime?: string): ComposerAttachmentKind {
  const normalizedMime = (mime ?? '').trim().toLowerCase();
  const extension = extensionFromName(name);
  if (normalizedMime.startsWith('image/') || IMAGE_ATTACHMENT_EXTENSIONS.has(extension)) {
    return 'image';
  }
  if (normalizedMime.startsWith('video/') || VIDEO_ATTACHMENT_EXTENSIONS.has(extension)) {
    return 'video';
  }
  if (normalizedMime.startsWith('audio/') || AUDIO_ATTACHMENT_EXTENSIONS.has(extension)) {
    return 'audio';
  }
  if (FILE_ATTACHMENT_EXTENSIONS.has(extension)) {
    return 'file';
  }
  return 'unsupported';
}

function mimeForAttachmentName(name: string): string | null {
  switch (extensionFromName(name)) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'svg':
      return 'image/svg+xml';
    case 'mp4':
      return 'video/mp4';
    case 'avi':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/mov';
    case 'mkv':
      return 'video/x-matroska';
    case 'wmv':
      return 'video/x-ms-wmv';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'flac':
      return 'audio/flac';
    case 'm4a':
      return 'audio/mp4';
    case 'ogg':
      return 'audio/ogg';
    case 'pdf':
      return 'application/pdf';
    case 'csv':
      return 'text/csv';
    case 'tsv':
      return 'text/tab-separated-values';
    case 'json':
      return 'application/json';
    case 'yaml':
    case 'yml':
      return 'application/yaml';
    case 'toml':
      return 'application/toml';
    case 'xml':
      return 'application/xml';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    default:
      return FILE_ATTACHMENT_EXTENSIONS.has(extensionFromName(name)) ? 'text/plain' : null;
  }
}

function modelSupportsAttachmentKind(
  model: ApiMetaModel | undefined,
  kind: ComposerAttachmentKind,
  name?: string,
): boolean {
  if (!model || model.supports_attachments === false) return false;
  if (name && model.attachment_extensions?.length) {
    const extension = extensionFromName(name);
    if (!model.attachment_extensions.includes(extension)) return false;
  }
  if (kind === 'image') return model.supports_image_input === true;
  if (kind === 'video') return model.supports_video_input === true;
  if (kind === 'audio') return model.supports_audio_input === true;
  if (kind === 'file') return model.supports_file_input !== false;
  return false;
}

function attachmentAcceptForModel(model: ApiMetaModel | undefined): string {
  if (!model || model.supports_attachments === false) return '';
  if (model.attachment_extensions?.length) {
    return Array.from(new Set(model.attachment_extensions.map((extension) => `.${extension}`))).join(',');
  }
  const extensions: string[] = [];
  if (model.supports_image_input === true) {
    extensions.push(...Array.from(IMAGE_ATTACHMENT_EXTENSIONS).map((ext) => `.${ext}`));
  }
  if (model.supports_video_input === true) {
    extensions.push(...Array.from(VIDEO_ATTACHMENT_EXTENSIONS).map((ext) => `.${ext}`));
  }
  if (model.supports_audio_input === true) {
    extensions.push(...Array.from(AUDIO_ATTACHMENT_EXTENSIONS).map((ext) => `.${ext}`));
  }
  if (model.supports_file_input !== false) {
    extensions.push(...Array.from(FILE_ATTACHMENT_EXTENSIONS).map((ext) => `.${ext}`));
  }
  return Array.from(new Set(extensions)).join(',');
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

function eventMatchesShortcut(event: KeyboardEvent, binding: ApiMetaShortcutBinding | undefined, fallback: string[]): boolean {
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
  const keyTokens = tokens.filter((token) => !['ctrl', 'shift', 'alt', 'cmd', 'meta'].includes(token));
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

interface MessageTranslationState {
  source: string;
  settingsFingerprint: string;
  text: string | null;
  loading: boolean;
  visible: boolean;
}

interface MessageTtsPlaybackViewState {
  playing: boolean;
  messageId: string | null;
  provider: string | null;
  error: string | null;
  failureId: string | null;
}

const EMPTY_TTS_PLAYBACK: MessageTtsPlaybackViewState = {
  playing: false,
  messageId: null,
  provider: null,
  error: null,
  failureId: null,
};

function normalizeTtsPlaybackState(
  playback: MessageTtsPlaybackState | null | undefined,
): MessageTtsPlaybackViewState {
  const messageId = strictStringFromUnknown(playback?.message_id);
  const provider = strictStringFromUnknown(playback?.provider);
  const error = strictStringFromUnknown(playback?.error);
  const failureId = strictStringFromUnknown(playback?.failure_id);
  return {
    playing: Boolean(playback?.playing),
    messageId: messageId || null,
    provider: provider || null,
    error: error || null,
    failureId: failureId || null,
  };
}

function sameTtsPlaybackState(
  a: MessageTtsPlaybackViewState,
  b: MessageTtsPlaybackViewState,
): boolean {
  return a.playing === b.playing &&
    a.messageId === b.messageId &&
    a.provider === b.provider &&
    a.error === b.error &&
    a.failureId === b.failureId;
}

function normalizeMetaMessageContentFormat(
  value: unknown,
): MessageContentFormat | undefined {
  return value === 'markdown' || value === 'plain_text' || value === 'html'
    ? value
    : undefined;
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
  const associatedKnowledgeBaseCacheRef = useRef(new Map<string, AssociatedKnowledgeBaseCacheEntry>());
  const associatedKnowledgeBaseBuildCacheRef = useRef<AssociatedKnowledgeBaseBuildCache | null>(null);
  const windowOffsetRef = useRef(0);
  const totalKnownRef = useRef(0);

  const [detail, setDetail] = useState<SessionDetailResponse | null>(null);
  const [messages, setMessages] = useState<SessionMessage[]>([]);
  // 当前本地 messages[0] 在服务端 oldest-first 序列里的 offset；0 表示历史已加载到头。
  const [windowOffset, setWindowOffset] = useState(0);
  const [totalKnown, setTotalKnown] = useState(0);
  const [transcriptRevealTarget, setTranscriptRevealTarget] = useState<{
    messageId: string;
    generation: number;
  } | null>(null);
  const [highlightedMessageId, setHighlightedMessageId] = useState<string | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(true);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [olderRenderSettling, setOlderRenderSettling] = useState(false);
  const [transcriptReadySessionId, setTranscriptReadySessionId] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sendPhase, setSendPhase] = useState<string>('idle');
  const [lastError, setLastError] = useState<string | null>(null);
  const [sessionGone, setSessionGone] = useState(false);

  // 输入区状态。composerText 仅供渲染读取（字符计数等低频 UI）；
  // 键入路径不直接写它，见下方 setComposerText/handleComposerTextInput。
  const [composerText, setComposerTextState] = useState<string>('');
  const [composerMode, setComposerMode] = useState<string>('normal');
  const [composerModelKey, setComposerModelKey] = useState<string>('');
  const [composerAttachments, setComposerAttachments] = useState<SendMessageAttachment[]>([]);
  const [composerAttachmentIds, setComposerAttachmentIds] = useState<string[]>([]);
  const [editingDraftMessage, setEditingDraftMessage] = useState<SessionMessage | null>(null);
  const [selectedSkill, setSelectedSkill] = useState<SkillSummary | null>(null);
  // 仅记录本轮临时跳过的用户指令，切换会话时清空。
  const [skippedInstructionIds, setSkippedInstructionIds] = useState<Set<string>>(() => new Set());
  const [skills, setSkills] = useState<SkillSummary[]>([]);
  const [skillPickerOpen, setSkillPickerOpen] = useState(false);
  const [skillPickerQuery, setSkillPickerQuery] = useState('');
  const [skillPickerLoading, setSkillPickerLoading] = useState(false);
  const [skillPickerSelectedIndex, setSkillPickerSelectedIndex] = useState(0);
  const {
    visible: skillPickerVisible,
    closing: skillPickerClosing,
    show: showSkillPicker,
    hide: hideSkillPicker,
  } = useDelayedVisibility();
  const [skillPickerAnchor, setSkillPickerAnchor] = useState<ComposerPickerAnchor | null>(null);
  const [atMentionFilePickerOpen, setAtMentionFilePickerOpen] = useState(false);
  const [atMentionFilePickerQuery, setAtMentionFilePickerQuery] = useState('');
  const {
    visible: atMentionFilePickerVisible,
    closing: atMentionFilePickerClosing,
    show: showAtMentionFilePicker,
    hide: hideAtMentionFilePicker,
  } = useDelayedVisibility();
  const [atMentionFilePickerAnchor, setAtMentionFilePickerAnchor] = useState<ComposerPickerAnchor | null>(null);

  // 附件预览 (image/* → dataURL); key 与 composerAttachments 同序
  const [attachmentPreviews, setAttachmentPreviews] = useState<{ mime: string; dataUrl: string; size: number }[]>([]);
  const [exitingComposerChipKeys, setExitingComposerChipKeys] = useState<string[]>([]);
  const [dragOver, setDragOver] = useState<boolean>(false);
  const [composerSending, setComposerSending] = useState<boolean>(false);
  const [composerError, setComposerError] = useState<string | null>(null);
  const [queuedComposerMessages, setQueuedComposerMessages] = useState<QueuedComposerMessage[]>([]);
  const [exitingQueuedMessageIds, setExitingQueuedMessageIds] = useState<string[]>([]);
  const [editingQueuedMessageId, setEditingQueuedMessageId] = useState<string | null>(null);
  const [queuedEditText, setQueuedEditText] = useState('');
  const [queueDispatchingId, setQueueDispatchingId] = useState<string | null>(null);
  const [queueGuidanceDispatchingId, setQueueGuidanceDispatchingId] = useState<string | null>(null);
  const [blockedQueuedMessageId, setBlockedQueuedMessageId] = useState<string | null>(null);
  const [queuedListMotionGeneration, setQueuedListMotionGeneration] = useState(0);
  const [stopping, setStopping] = useState<boolean>(false);
  const [composerCollapsed, setComposerCollapsed] = useState(readPersistedComposerCollapsed);
  const [autoFollow, setAutoFollow] = useState(true);
  const [autoFollowPaused, setAutoFollowPaused] = useState(false);
  const browserFullscreen = useBrowserFullscreen();
  const [showComposerModelPicker, setShowComposerModelPicker] = useState(false);
  const [reasoningEffortSaving, setReasoningEffortSaving] = useState(false);
  const [showCreationOptions, setShowCreationOptions] = useState<'image' | 'video' | 'audio' | null>(null);
  const [creationOptions, setCreationOptions] = useState<CreationOptions>({});
  const [showTitleSummary, setShowTitleSummary] = useState(false);
  const [showTrajectory, setShowTrajectory] = useState(false);
  const [permissionSaving, setPermissionSaving] = useState(false);
  const [pendingFullAccess, setPendingFullAccess] = useState<boolean | null>(null);
  const [pendingWriteApproval, setPendingWriteApproval] = useState<PendingWriteApproval | null>(null);

  // 当前会话的有效流式节流状态（来自 SSE snapshot）。用于
  // TopBar 节流胶囊渲染绿/灰色与字符/卡片速率。
  const [streamThrottle, setStreamThrottle] = useState<{
    chars: number;
    cards: number;
    hasOverride: boolean;
    durationExpired: boolean;
    // 当前生效的「启用节流」状态：会话级覆盖 > 全局。
    // 关闭时胶囊渲染为灰色，Dialog 中的 Switch 同步显示关闭态。
    enabled: boolean;
    // 会话历史上是否曾节流；用于胶囊可见性兜底。
    wasInitiallyThrottled: boolean;
    // 字符吞吐 30s 桶（桶 0 = 当前秒）。
    throughputBuckets?: number[];
  } | null>(null);
  const [throttleDialogOpen, setThrottleDialogOpen] = useState(false);
  const [writeApprovalBusy, setWriteApprovalBusy] = useState(false);

  const detailAbortRef = useRef<AbortController | null>(null);
  const messagesAbortRef = useRef<AbortController | null>(null);
  const olderMessagesAbortRef = useRef<AbortController | null>(null);
  const sseCloseRef = useRef<(() => void) | null>(null);
  const composerTextareaRef = useRef<HTMLTextAreaElement | null>(null);
  // composerText 的即时镜像。textarea 改为非受控：受控绑定会让每个
  // keystroke 重执行整个页面组件（11k 行 JSX diff），长会话下输入可感延迟。
  // 键入只写 ref（事件处理一律读 ref，去抖窗口内的输入不丢失），state 去抖
  // 同步用于字符计数等低频渲染；程序化写入（清空/编辑回填/插入技能）立即
  // 同步 DOM + state。
  const composerTextRef = useRef('');
  const composerTextSyncTimerRef = useRef<number | null>(null);
  const setComposerText = useCallback((next: string) => {
    composerTextRef.current = next;
    if (composerTextSyncTimerRef.current != null) {
      window.clearTimeout(composerTextSyncTimerRef.current);
      composerTextSyncTimerRef.current = null;
    }
    const node = composerTextareaRef.current;
    if (node && node.value !== next) node.value = next;
    setComposerTextState(next);
  }, []);
  const handleComposerTextInput = useCallback((next: string) => {
    composerTextRef.current = next;
    if (composerTextSyncTimerRef.current != null) {
      window.clearTimeout(composerTextSyncTimerRef.current);
    }
    composerTextSyncTimerRef.current = window.setTimeout(() => {
      composerTextSyncTimerRef.current = null;
      setComposerTextState(composerTextRef.current);
    }, COMPOSER_TEXT_STATE_SYNC_MS);
  }, []);
  useEffect(() => () => {
    if (composerTextSyncTimerRef.current != null) {
      window.clearTimeout(composerTextSyncTimerRef.current);
    }
  }, []);
  const composerFileInputRef = useRef<HTMLInputElement | null>(null);
  const slashDismissalRef = useRef<ComposerTriggerDismissal | null>(null);
  const skillPickerOverlayRef = useRef<HTMLDivElement | null>(null);
  const slashTriggerOffsetRef = useRef<number | null>(null);
  const atMentionFilePickerOverlayRef = useRef<HTMLDivElement | null>(null);
  const atMentionDismissalRef = useRef<ComposerTriggerDismissal | null>(null);
  const atMentionTriggerOffsetRef = useRef<number | null>(null);
  const imageEditorResolverRef = useRef<((result: ImageEditorResult | null) => void) | null>(null);
  const goalStartOptionsResolverRef = useRef<((result: GoalStartOptions | null) => void) | null>(null);
  const skillsLoadedRef = useRef(false);
  const detailRef = useRef<SessionDetailResponse | null>(null);
  const sessionIdRef = useRef(sessionId);
  const { scheduleTimer: scheduleComposerEditFocusTimer } =
    useTimeoutController();

  function resetSlashTriggerState(): void {
    slashDismissalRef.current = null;
    slashTriggerOffsetRef.current = null;
  }

  function resetAtMentionTriggerState(): void {
    atMentionDismissalRef.current = null;
    atMentionTriggerOffsetRef.current = null;
  }
  const mountedRef = useRef(true);
  const editingDraftMessageRef = useRef<SessionMessage | null>(null);
  const autoTitleRefreshTimersRef = useRef<number[]>([]);
  const composerChipExitTimersRef = useRef<number[]>([]);
  const queuedMessageExitTimersRef = useRef<number[]>([]);
  const queuedComposerMessagesRef = useRef<QueuedComposerMessage[]>([]);
  const queuedMessageSeqRef = useRef(0);
  const queueDispatchingRef = useRef(false);
  const queueGuidanceDispatchingRef = useRef(false);
  const queuedGoalResumeInFlightRef = useRef(false);
  const blockedQueuedMessageIdRef = useRef<string | null>(null);
  const composerAttachmentIdsRef = useRef<string[]>([]);
  const attachmentIdSeqRef = useRef(0);
  // 用户离底超过阈值时暂停自动跟随；检测到远端生成且本地有草稿时显示冲突提示。
  const isNearBottomRef = useRef<boolean>(true);
  const autoFollowRef = useRef<boolean>(true);
  const autoFollowPausedRef = useRef<boolean>(false);
  const programmaticScrollUntilRef = useRef<number>(0);
  const composerLayoutTransitionUntilRef = useRef<number>(0);
  const composerLayoutPinnedRef = useRef<boolean>(false);
  // 区分「用户主动向上滑动」与「内容增长导致的视觉远离底部」：
  // recalc 仅在 scrollTop 真正减小 (用户上滑) 时才允许 setAutoFollowPaused=true。
  // 否则 (内容增长 / 程序滚动) 不应自动暂停跟随，让 ResizeObserver follow 接管。
  const lastScrollTopRef = useRef<number>(0);
  const lastUserScrollIntentAtRef = useRef<number>(0);
  const followFrameRef = useRef<number | null>(null);
  const followSettleFrameRef = useRef<number | null>(null);
  const followSettleRemainingRef = useRef(0);
  const followSettleStableFramesRef = useRef(0);
  const resizeFollowFrameRef = useRef<number | null>(null);
  const postRenderFrameRefs = useRef<number[]>([]);
  const lastTailIdRef = useRef<string | null>(null);
  const lastTailSignatureRef = useRef<string>('');
  const lastFollowSignatureRef = useRef<string>('');
  const olderRenderSettlingRef = useRef(false);
  const cacheHitRevealAbortRef = useRef<AbortController | null>(null);
  const cacheHitRevealGenerationRef = useRef(0);
  const cacheHitHighlightTimerRef = useRef<number | null>(null);
  const cacheStatisticsHydratingSessionIdRef = useRef<string | null>(null);
  const lastLocalSendAtRef = useRef<number>(0);
  const [remoteRunning, setRemoteRunning] = useState<boolean>(false);

  // 消息操作栏：审计弹窗 + 删除确认。
  const [auditMessage, setAuditMessage] = useState<SessionMessage | null>(null);
  const [pendingDeleteAction, setPendingDeleteAction] = useState<{
    message: SessionMessage;
    cascade: boolean;
  } | null>(null);
  const [pendingForkMessage, setPendingForkMessage] = useState<SessionMessage | null>(null);
  const forkedSessionIdRef = useRef<string | null>(null);
  const [activeMessageId, setActiveMessageId] = useState<string | null>(null);
  const [sessionMetadataOpen, setSessionMetadataOpen] = useState(false);
  const [tokenStatsOpen, setTokenStatsOpen] = useState(false);
  const [goalDetailsOpen, setGoalDetailsOpen] = useState(false);
  const [goalStartOptionsOpen, setGoalStartOptionsOpen] = useState(false);
  const [pendingGoalOptionsBySessionId, setPendingGoalOptionsBySessionId] = useState<Record<string, GoalStartOptions>>({});
  const [goalControlBusy, setGoalControlBusy] = useState<'pause' | 'resume' | 'terminate' | null>(null);
  const [webReverseDashboardOpen, setWebReverseDashboardOpen] = useState(false);
  const [androidReverseDashboardOpen, setAndroidReverseDashboardOpen] = useState(false);
  const [imageEditorInput, setImageEditorInput] = useState<ImageEditorInput | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [forkBusy, setForkBusy] = useState(false);
  const [messageTranslations, setMessageTranslations] = useState<Record<string, MessageTranslationState>>({});
  const [ttsPlayback, setTtsPlayback] = useState<MessageTtsPlaybackViewState>(EMPTY_TTS_PLAYBACK);
  const shownTtsFailureIdRef = useRef<string | null>(null);
  const [feedbackBusyMessageIds, setFeedbackBusyMessageIds] = useState<Set<string>>(() => new Set());
  const [regeneratingMessageIds, setRegeneratingMessageIds] = useState<Set<string>>(() => new Set());
  const [pendingSessionDelete, setPendingSessionDelete] = useState(false);
  const [sessionDeleteBusy, setSessionDeleteBusy] = useState(false);

  const applyTtsPlayback = useCallback((playback: MessageTtsPlaybackState | null | undefined) => {
    const next = normalizeTtsPlaybackState(playback);
    if (next.error && next.failureId && shownTtsFailureIdRef.current !== next.failureId) {
      shownTtsFailureIdRef.current = next.failureId;
      showSnackbar(`${t('message.tts.failed', '朗读失败')}：${next.error}`, { tone: 'error' });
    }
    setTtsPlayback((current) => (sameTtsPlaybackState(current, next) ? current : next));
  }, []);

  function cancelPostRenderFrames(): void {
    for (const frame of postRenderFrameRefs.current) {
      window.cancelAnimationFrame(frame);
    }
    postRenderFrameRefs.current = [];
  }

  function schedulePostRenderFrame(action: () => void): void {
    if (typeof window === 'undefined') return;
    const frame = window.requestAnimationFrame(() => {
      postRenderFrameRefs.current = postRenderFrameRefs.current.filter((item) => item !== frame);
      if (!mountedRef.current) return;
      action();
    });
    postRenderFrameRefs.current.push(frame);
  }

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
      cancelPostRenderFrames();
    };
  }, []);

  useEffect(() => {
    queuedComposerMessagesRef.current = queuedComposerMessages;
  }, [queuedComposerMessages]);

  useEffect(() => {
    setTtsPlayback(EMPTY_TTS_PLAYBACK);
    const previousTtsSessionId = lastMessageTtsSessionId;
    if (sessionId) lastMessageTtsSessionId = sessionId;
    if (sessionId) {
      const requestSessionId = sessionId;
      const playbackRequest = previousTtsSessionId != null &&
          previousTtsSessionId !== requestSessionId
        ? stopMessageTtsPlayback()
        : fetchMessageTtsPlayback();
      void playbackRequest
        .then((result) => {
          if (mountedRef.current && sessionIdRef.current === requestSessionId) {
            applyTtsPlayback(result.playback);
          }
        })
        .catch(ignoreError);
    }
    queueDispatchingRef.current = false;
    queueGuidanceDispatchingRef.current = false;
    blockedQueuedMessageIdRef.current = null;
    setQueuedComposerMessages([]);
    setExitingQueuedMessageIds([]);
    setEditingQueuedMessageId(null);
    setQueuedEditText('');
    setQueueDispatchingId(null);
    setQueueGuidanceDispatchingId(null);
    setComposerSending(false);
    setStopping(false);
    setPendingDeleteAction(null);
    setDeleteBusy(false);
    setPendingForkMessage(null);
    forkedSessionIdRef.current = null;
    setForkBusy(false);
    setMessageTranslations({});
    setFeedbackBusyMessageIds(new Set());
    setRegeneratingMessageIds(new Set());
    setPendingSessionDelete(false);
    setSessionDeleteBusy(false);
    setTranscriptReadySessionId(null);
    setPermissionSaving(false);
    setPendingFullAccess(null);
    setWriteApprovalBusy(false);
    setPendingWriteApproval(null);
    setSessionGone(false);
    setAuditMessage(null);
    resetSlashTriggerState();
    resetAtMentionTriggerState();
    setAtMentionFilePickerOpen(false);
    setAtMentionFilePickerQuery('');
    setSessionMetadataOpen(false);
    setTokenStatsOpen(false);
    setGoalDetailsOpen(false);
    setGoalStartOptionsOpen(false);
    setGoalControlBusy(null);
    setThrottleDialogOpen(false);
    setWebReverseDashboardOpen(false);
    setAndroidReverseDashboardOpen(false);
    imageEditorResolverRef.current?.(null);
    imageEditorResolverRef.current = null;
    goalStartOptionsResolverRef.current?.(null);
    goalStartOptionsResolverRef.current = null;
    setImageEditorInput(null);
    // 与 App 端 _skippedInstructionIds 一致：会话切换时清空跳过集合，
    // 避免上一会话的跳过状态泄漏到新会话。
    setSkippedInstructionIds(new Set());
  }, [applyTtsPlayback, sessionId]);

  useAsyncPolling(
    async (isActive, signal) => {
      try {
        const result = await fetchMessageTtsPlayback({ signal });
        if (isActive()) applyTtsPlayback(result.playback);
      } catch (e) {
        if (!isActive()) return;
        if (handleAuthError(e)) return;
        setTtsPlayback(EMPTY_TTS_PLAYBACK);
      }
    },
    {
      enabled: ttsPlayback.playing,
      immediate: false,
      intervalMs: TTS_PLAYBACK_POLL_INTERVAL_MS,
      taskTimeoutMs: TTS_PLAYBACK_POLL_TIMEOUT_MS,
      onError: (e) => {
        if (handleAuthError(e)) return;
        setTtsPlayback(EMPTY_TTS_PLAYBACK);
      },
    },
  );

  useEffect(
    () => () => {
      imageEditorResolverRef.current?.(null);
      imageEditorResolverRef.current = null;
      goalStartOptionsResolverRef.current?.(null);
      goalStartOptionsResolverRef.current = null;
    },
    [],
  );

  useEffect(
    () => () => {
      for (const timer of composerChipExitTimersRef.current) {
        window.clearTimeout(timer);
      }
      composerChipExitTimersRef.current = [];
      for (const timer of queuedMessageExitTimersRef.current) {
        window.clearTimeout(timer);
      }
      queuedMessageExitTimersRef.current = [];
    },
    [],
  );

  // 卸载时收回全部跟随动画帧；复用同名取消函数，避免两处清理口径漂移。
  useEffect(
    () => () => {
      cancelFollowSettle();
      cancelResizeFollowFrame();
      cancelPostRenderFrames();
    },
    [],
  );

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

  function blockQueuedMessageRetry(id: string): void {
    blockedQueuedMessageIdRef.current = id;
    setBlockedQueuedMessageId(id);
  }

  function clearQueuedMessageRetryBlock(id?: string): void {
    if (!id || blockedQueuedMessageIdRef.current === id) {
      blockedQueuedMessageIdRef.current = null;
      setBlockedQueuedMessageId(null);
    }
  }

  function runAfterTrackedExit(
    id: string,
    isExiting: (id: string) => boolean,
    setExitingIds: (updater: (ids: string[]) => string[]) => void,
    timersRef: { current: number[] },
    action: () => void,
  ): void {
    if (isExiting(id)) return;
    if (reduceMotion || typeof window === 'undefined') {
      action();
      return;
    }
    setExitingIds((ids) => (ids.includes(id) ? ids : [...ids, id]));
    const timer = window.setTimeout(() => {
      action();
      setExitingIds((ids) => ids.filter((item) => item !== id));
      timersRef.current = timersRef.current.filter((item) => item !== timer);
    }, COMPOSER_ITEM_EXIT_MS);
    timersRef.current.push(timer);
  }

  function runAfterComposerChipExit(key: string, action: () => void): void {
    runAfterTrackedExit(
      key,
      composerChipIsExiting,
      setExitingComposerChipKeys,
      composerChipExitTimersRef,
      action,
    );
  }

  function runAfterQueuedMessageExit(id: string, action: () => void): void {
    runAfterTrackedExit(
      id,
      queuedMessageIsExiting,
      setExitingQueuedMessageIds,
      queuedMessageExitTimersRef,
      action,
    );
  }

  const setAutoFollowEnabled = (value: boolean) => {
    autoFollowRef.current = value;
    if (!value) {
      cancelAutoFollowMotion();
      autoFollowPausedRef.current = false;
      setAutoFollowPaused((current) => (current ? false : current));
      composerLayoutPinnedRef.current = false;
      programmaticScrollUntilRef.current = 0;
    }
    setAutoFollow((current) => (current === value ? current : value));
  };

  const setAutoFollowPausedValue = (value: boolean) => {
    autoFollowPausedRef.current = value;
    setAutoFollowPaused((current) => (current === value ? current : value));
  };

  const markUserScrollIntent = useCallback(() => {
    composerLayoutPinnedRef.current = false;
    lastUserScrollIntentAtRef.current = Date.now();
    markTranscriptScrollActivity(AUTO_FOLLOW_USER_SCROLL_INTENT_MS);
    cancelFollowSettle();
  }, []);

  const hasRecentUserScrollIntent = useCallback(() => {
    return Date.now() - lastUserScrollIntentAtRef.current <= AUTO_FOLLOW_USER_SCROLL_INTENT_MS;
  }, []);

  const setOlderRenderSettlingValue = (value: boolean) => {
    olderRenderSettlingRef.current = value;
    setOlderRenderSettling((current) => (current === value ? current : value));
  };

  function extendProgrammaticScrollWindow(durationMs: number): void {
    programmaticScrollUntilRef.current = Math.max(
      programmaticScrollUntilRef.current,
      Date.now() + durationMs,
    );
  }

  function markComposerLayoutTransition(): void {
    composerLayoutTransitionUntilRef.current = Math.max(
      composerLayoutTransitionUntilRef.current,
      Date.now() + COMPOSER_LAYOUT_TRANSITION_GUARD_MS,
    );
    markTranscriptScrollActivity(COMPOSER_LAYOUT_TRANSITION_GUARD_MS);
  }

  function isComposerLayoutTransitioning(): boolean {
    return Date.now() < composerLayoutTransitionUntilRef.current;
  }

  function cancelFollowSettle(): void {
    if (followFrameRef.current != null) {
      window.cancelAnimationFrame(followFrameRef.current);
      followFrameRef.current = null;
    }
    if (followSettleFrameRef.current != null) {
      window.cancelAnimationFrame(followSettleFrameRef.current);
      followSettleFrameRef.current = null;
    }
    followSettleRemainingRef.current = 0;
    followSettleStableFramesRef.current = 0;
  }

  function cancelResizeFollowFrame(): void {
    if (resizeFollowFrameRef.current != null) {
      window.cancelAnimationFrame(resizeFollowFrameRef.current);
      resizeFollowFrameRef.current = null;
    }
  }

  function cancelAutoFollowMotion(): void {
    cancelFollowSettle();
    cancelResizeFollowFrame();
    const el = mainRef.current;
    if (el) {
      el.scrollTo({ top: el.scrollTop, behavior: 'auto' });
    }
  }

  const pinMessagesToBottom = () => {
    const el = mainRef.current;
    if (!el) return;
    const bottomTop = Math.max(0, el.scrollHeight - el.clientHeight);
    if (Math.abs(el.scrollTop - bottomTop) > 0.5) {
      el.scrollTop = bottomTop;
    }
  };

  const messagesAreNearBottom = () => {
    const el = mainRef.current;
    if (!el) return isNearBottomRef.current;
    const distance = el.scrollHeight - (el.scrollTop + el.clientHeight);
    return distance <= AUTO_FOLLOW_NEAR_BOTTOM_PX;
  };

  const shouldPinComposerLayoutToBottom = () => {
    return autoFollowRef.current &&
      !autoFollowPausedRef.current &&
      (composerLayoutPinnedRef.current || messagesAreNearBottom()) &&
      !hasRecentUserScrollIntent();
  };

  const pinComposerLayoutToBottom = () => {
    if (!shouldPinComposerLayoutToBottom()) return false;
    extendProgrammaticScrollWindow(320);
    pinMessagesToBottom();
    isNearBottomRef.current = true;
    setAutoFollowPausedValue(false);
    return true;
  };

  const scrollMessagesToBottom = (behavior: ScrollBehavior = 'auto') => {
    const el = mainRef.current;
    if (!el) return;
    extendProgrammaticScrollWindow(behavior === 'smooth' ? 700 : 220);
    if (behavior === 'smooth') {
      el.scrollTo({
        top: Math.max(0, el.scrollHeight - el.clientHeight),
        behavior,
      });
    } else {
      pinMessagesToBottom();
    }
  };

  function queueFollowSettlePass(): void {
    if (followSettleFrameRef.current != null) return;
    if (followSettleRemainingRef.current <= 0) return;
    followSettleFrameRef.current = requestAnimationFrame(() => {
      followSettleFrameRef.current = null;
      const el = mainRef.current;
      if (!el || !shouldFollowPinnedMessages()) {
        followSettleRemainingRef.current = 0;
        followSettleStableFramesRef.current = 0;
        return;
      }

      followSettleRemainingRef.current = Math.max(
        0,
        followSettleRemainingRef.current - 1,
      );
      const beforeTop = el.scrollTop;
      const beforeBottomTop = Math.max(0, el.scrollHeight - el.clientHeight);
      extendProgrammaticScrollWindow(220);
      pinMessagesToBottom();
      const afterBottomTop = Math.max(0, el.scrollHeight - el.clientHeight);
      const changed =
        Math.abs(el.scrollTop - beforeTop) > AUTO_FOLLOW_SETTLE_EPSILON_PX ||
        Math.abs(afterBottomTop - beforeBottomTop) >
          AUTO_FOLLOW_SETTLE_EPSILON_PX ||
        Math.abs(afterBottomTop - el.scrollTop) >
          AUTO_FOLLOW_SETTLE_EPSILON_PX;
      followSettleStableFramesRef.current = changed
        ? 0
        : followSettleStableFramesRef.current + 1;
      if (
        followSettleRemainingRef.current > 0 &&
        followSettleStableFramesRef.current < AUTO_FOLLOW_SETTLE_STABLE_FRAMES
      ) {
        queueFollowSettlePass();
      } else {
        followSettleRemainingRef.current = 0;
        followSettleStableFramesRef.current = 0;
      }
    });
  }

  const scheduleFollowToBottom = (behavior: ScrollBehavior = 'auto') => {
    const el = mainRef.current;
    if (!el) return;
    extendProgrammaticScrollWindow(behavior === 'smooth' ? 900 : 260);
    scrollMessagesToBottom(behavior);
    isNearBottomRef.current = true;
    setAutoFollowPausedValue(false);
    if (followFrameRef.current != null) {
      window.cancelAnimationFrame(followFrameRef.current);
    }
    if (followSettleFrameRef.current != null) {
      window.cancelAnimationFrame(followSettleFrameRef.current);
      followSettleFrameRef.current = null;
    }
    followSettleRemainingRef.current = Math.max(
      followSettleRemainingRef.current,
      AUTO_FOLLOW_SETTLE_MAX_FRAMES,
    );
    followSettleStableFramesRef.current = 0;
    followFrameRef.current = requestAnimationFrame(() => {
      followFrameRef.current = null;
      queueFollowSettlePass();
    });
  };

  const canAutoFollowMessages = ({
    requireNearBottom = false,
    allowDuringComposerTransition = false,
  }: {
    requireNearBottom?: boolean;
    allowDuringComposerTransition?: boolean;
  } = {}) => {
    return autoFollowRef.current &&
      !autoFollowPausedRef.current &&
      (!requireNearBottom || isNearBottomRef.current) &&
      !hasRecentUserScrollIntent() &&
      (allowDuringComposerTransition || !isComposerLayoutTransitioning());
  };

  const scheduleAutoFollowToBottom = (
    behavior: ScrollBehavior = 'auto',
    options?: {
      requireNearBottom?: boolean;
      allowDuringComposerTransition?: boolean;
    },
  ) => {
    if (!canAutoFollowMessages(options)) {
      cancelFollowSettle();
      return false;
    }
    scheduleFollowToBottom(behavior);
    return true;
  };

  const shouldFollowPinnedMessages = () => {
    return canAutoFollowMessages({
      requireNearBottom: true,
      allowDuringComposerTransition: true,
    });
  };


  function updateMessageInLocalWindow(
    messageId: string,
    updater: (message: SessionMessage) => SessionMessage,
  ): void {
    setMessages((prev) => {
      const index = prev.findIndex((item) => item.id === messageId);
      if (index < 0) return prev;
      const nextMessage = updater(prev[index]!);
      if (nextMessage === prev[index]) return prev;
      const next = prev.slice();
      next[index] = nextMessage;
      messagesRef.current = next;
      return next;
    });
  }

  function setMessageFeedbackBusy(messageId: string, busy: boolean): void {
    setFeedbackBusyMessageIds((current) => {
      if (busy && current.has(messageId)) return current;
      if (!busy && !current.has(messageId)) return current;
      const next = new Set(current);
      if (busy) next.add(messageId);
      else next.delete(messageId);
      return next;
    });
  }

  function setMessageRegenerating(messageId: string, busy: boolean): void {
    setRegeneratingMessageIds((current) => {
      if (busy && current.has(messageId)) return current;
      if (!busy && !current.has(messageId)) return current;
      const next = new Set(current);
      if (busy) next.add(messageId);
      else next.delete(messageId);
      return next;
    });
  }

  // 传给 MessageCard 的回调必须保持恒定标识：这些 handler 的依赖（翻译表、
  // 反馈中集合、sendPhase）在一个回合内高频变化，进依赖数组会让窗口内每张
  // 卡片的 memo 浅比较全部失效，等于整屏重渲染 + 重解析。
  const handleToggleMessageTranslation = useEventCallback(async (m: SessionMessage) => {
    if (!sessionId) return;
    const source = m.content ?? '';
    const settingsFingerprint =
      auth.meta?.message_content_settings?.translation_settings_fingerprint ?? '';
    const modelSettingsFingerprint =
      auth.meta?.message_content_settings?.translation_model_settings_fingerprint ?? '';
    const fallbackModelKey =
      detail?.session.last_model_key || auth.meta?.active_model_key || '';
    const requestFingerprint = [
      settingsFingerprint,
      modelSettingsFingerprint,
      fallbackModelKey,
    ].join('|');
    const current = messageTranslations[m.id];
    const cacheMatches =
      current?.source === source &&
      current.settingsFingerprint === requestFingerprint;
    if (cacheMatches && current.loading) return;
    if (cacheMatches && current.text) {
      setMessageTranslations((prev) => ({
        ...prev,
        [m.id]: { ...current, visible: !current.visible },
      }));
      return;
    }
    const requestSessionId = sessionId;
    setMessageTranslations((prev) => ({
      ...prev,
      [m.id]: {
        source,
        settingsFingerprint: requestFingerprint,
        text: null,
        loading: true,
        visible: false,
      },
    }));
    try {
      const result = await translateMessage(requestSessionId, m.id);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      const translated = (result.text ?? '').trim();
      if (!translated) {
        showSnackbar(t('message.translate.empty', '未得到可展示的译文'), { tone: 'error' });
        setMessageTranslations((prev) => ({
          ...prev,
          [m.id]: {
            source,
            settingsFingerprint: requestFingerprint,
            text: null,
            loading: false,
            visible: false,
          },
        }));
        return;
      }
      setMessageTranslations((prev) => ({
        ...prev,
        [m.id]: {
          source,
          settingsFingerprint: requestFingerprint,
          text: translated,
          loading: false,
          visible: true,
        },
      }));
      showSnackbar(t('message.translate.ok', '已翻译消息'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setMessageTranslations((prev) => ({
        ...prev,
        [m.id]: {
          source,
          settingsFingerprint: requestFingerprint,
          text: null,
          loading: false,
          visible: false,
        },
      }));
      showSnackbar(`${t('message.translate.failed', '翻译失败')}：${message}`, { tone: 'error' });
    }
  });

  const handleToggleMessageTts = useCallback(async (m: SessionMessage) => {
    if (!sessionId) return;
    const requestSessionId = sessionId;
    try {
      const result = await toggleMessageTtsPlayback(requestSessionId, m.id);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      applyTtsPlayback(result.playback);
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      showSnackbar(`${t('message.tts.failed', '朗读失败')}：${message}`, { tone: 'error' });
      setTtsPlayback(EMPTY_TTS_PLAYBACK);
    }
  }, [applyTtsPlayback, sessionId]);

  const handleSetMessageFeedback = useEventCallback(async (
    m: SessionMessage,
    feedback: SessionMessageFeedback | null,
  ) => {
    if (!sessionId || feedbackBusyMessageIds.has(m.id)) return;
    const requestSessionId = sessionId;
    const previousMessage = messagesRef.current.find((item) => item.id === m.id) ?? m;
    const previousFeedback = messageFeedbackValue(previousMessage);
    setMessageFeedbackBusy(m.id, true);
    updateMessageInLocalWindow(m.id, (message) => messageWithFeedback(message, feedback));
    try {
      const result = await setMessageFeedback(requestSessionId, m.id, feedback);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (result.message) {
        updateMessageInLocalWindow(m.id, () => result.message!);
      } else {
        updateMessageInLocalWindow(m.id, (message) => messageWithFeedback(message, result.feedback ?? feedback));
      }
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      updateMessageInLocalWindow(m.id, (message) => messageWithFeedback(message, previousFeedback));
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      showSnackbar(`${t('message.feedback.failed', '反馈提交失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setMessageFeedbackBusy(m.id, false);
    }
  });

  const handleRegenerateMessage = useEventCallback(async (m: SessionMessage) => {
    if (!sessionId || regeneratingMessageIds.has(m.id)) return;
    if (sendPhase !== 'idle') {
      showSnackbar(t('message.regenerate.busy', '当前会话正在运行，稍后再试'), { tone: 'error' });
      return;
    }
    const requestSessionId = sessionId;
    setMessageRegenerating(m.id, true);
    try {
      const result = await regenerateMessage(requestSessionId, m.id, {
        modelKey: composerModelKey,
      });
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setActiveMessageId(null);
      updateSendPhaseValue(result.send_phase || 'sendingMessage');
      lastLocalSendAtRef.current = Date.now();
      scheduleAutoFollowToBottom(reduceMotion ? 'auto' : 'smooth');
      showSnackbar(t('message.regenerate.started', '已开始重新生成'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      showSnackbar(`${t('message.regenerate.failed', '重新生成失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setMessageRegenerating(m.id, false);
    }
  });

  const handleCopyMessage = useCallback(async (m: SessionMessage) => {
    const text = m.content ?? '';
    const ok = await copyTextToClipboard(text);
    showSnackbar(ok ? t('detail.copy.ok', '已复制消息内容') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
      tone: ok ? 'success' : 'error',
    });
  }, []);
  const handleDeleteMessage = useCallback((m: SessionMessage) => {
    setPendingDeleteAction({ message: m, cascade: false });
  }, []);
  const handleDeleteMessageCascade = useCallback((m: SessionMessage) => {
    setPendingDeleteAction({ message: m, cascade: true });
  }, []);
  const handleForkMessage = useCallback((m: SessionMessage) => {
    setPendingForkMessage(m);
  }, []);
  const confirmDeleteMessage = async (): Promise<boolean> => {
    if (!sessionId || !pendingDeleteAction || deleteBusy) return false;
    const requestSessionId = sessionId;
    setDeleteBusy(true);
    const { message, cascade } = pendingDeleteAction;
    try {
      if (cascade) {
        await deleteMessageCascade(requestSessionId, message.id);
      } else {
        await deleteMessage(requestSessionId, message.id);
      }
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      showSnackbar(cascade ? t('detail.deleteAfter.ok', '已删除此条及后续消息') : t('detail.delete.ok', '已删除消息'), { tone: 'success' });
      return true;
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      if (handleAuthError(e)) return false;
      if (handleSessionGoneError(e)) return false;
      setError(e instanceof Error ? e.message : String(e));
      showSnackbar(t('detail.delete.failed', '删除消息失败'), {
        tone: 'error',
      });
      return false;
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setDeleteBusy(false);
    }
  };
  const confirmForkMessage = async (): Promise<boolean> => {
    if (!sessionId || !pendingForkMessage || forkBusy) return false;
    const requestSessionId = sessionId;
    const message = pendingForkMessage;
    setForkBusy(true);
    try {
      const res = await forkSessionFromMessage(requestSessionId, message.id);
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      showSnackbar(t('detail.fork.ok', '已派生新会话'), { tone: 'success' });
      forkedSessionIdRef.current = res.session?.id ?? null;
      return true;
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      if (handleAuthError(e)) return false;
      if (handleSessionGoneError(e)) return false;
      const messageText = e instanceof Error ? e.message : String(e);
      setError(messageText);
      showSnackbar(`${t('detail.fork.failed', '派生会话失败')}：${messageText}`, {
        tone: 'error',
      });
      return false;
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setForkBusy(false);
    }
  };

  const confirmDeleteSession = async (): Promise<boolean> => {
    if (!sessionId || sessionDeleteBusy) return false;
    const requestSessionId = sessionId;
    setSessionDeleteBusy(true);
    try {
      await deleteSession(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      showSnackbar(t('topbar.delete.ok', '已删除会话'), { tone: 'success' });
      return true;
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      if (handleAuthError(e)) return false;
      if (e instanceof ApiError && e.status === 404) {
        showSnackbar(t('topbar.delete.ok', '已删除会话'), { tone: 'success' });
        return true;
      }
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.delete.failed', '删除会话失败')}：${message}`, {
        tone: 'error',
      });
      return false;
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) {
        setSessionDeleteBusy(false);
      }
    }
  };

  const applyFullAccessPermission = async (next: boolean): Promise<boolean> => {
    if (permissionSaving) return false;
    const requestSessionId = sessionId;
    setPermissionSaving(true);
    try {
      const res = await updateSessionFullAccessPermission(requestSessionId, next);
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      setDetail((prev) => (prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev));
      showSnackbar(t('topbar.perm.ok', '已更新权限设置'), { tone: 'success' });
      return true;
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      if (handleAuthError(e)) return false;
      if (handleSessionGoneError(e)) return false;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('topbar.perm.failed', '更新权限设置失败')}：${message}`, { tone: 'error' });
      return false;
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) {
        setPermissionSaving(false);
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

  const handleWriteApproval = async (
    decision: 'approved' | 'rejected',
  ): Promise<boolean> => {
    if (!pendingWriteApproval || writeApprovalBusy) return false;
    const requestSessionId = sessionId;
    const approvalId = pendingWriteApproval.id;
    if (decision !== 'approved') setPendingWriteApproval(null);
    setWriteApprovalBusy(true);
    try {
      await respondWriteApproval(requestSessionId, approvalId, decision);
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      const tone = decision === 'approved' ? 'success' : undefined;
      const label = (() => {
        switch (decision) {
          case 'approved':
            return t('detail.writeApproval.approved', '已批准写操作');
          case 'rejected':
            return t('detail.writeApproval.rejected', '已拒绝写操作');
        }
      })();
      showSnackbar(label, { tone });
      void refresh();
      return true;
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return false;
      if (handleAuthError(e)) return false;
      if (handleSessionGoneError(e)) return false;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('detail.writeApproval.failed', '处理写操作确认失败')}：${message}`, { tone: 'error' });
      return false;
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
    resetSlashTriggerState();
    setComposerCollapsed(false);
    setComposerAttachments([]);
    setComposerAttachmentIds([]);
    setAttachmentPreviews([]);
    void restoreSelectedSkillForEdit(m);
    void restoreAttachmentsForEdit(m);
    scheduleComposerEditFocusTimer(
      () => composerTextareaRef.current?.focus(),
      COMPOSER_EDIT_FOCUS_DELAY_MS,
    );
    scheduleAutoFollowToBottom(reduceMotion ? 'auto' : 'smooth');
  });
  const handleAuditMessage = useCallback((m: SessionMessage) => {
    setAuditMessage(m);
    if (m.metadata?.[DEFERRED_MESSAGE_TELEMETRY_METADATA_KEY] !== true) {
      return;
    }
    const auditSessionId = sessionId;
    void getSessionMessage(auditSessionId, m.id)
      .then(({ message }) => {
        if (!ownsSessionAsyncResult(auditSessionId)) return;
        setAuditMessage((current) => current?.id === m.id ? message : current);
      })
      .catch(ignoreError);
  }, [sessionId]);
  const handleMessageActiveChange = useCallback((message: SessionMessage, active: boolean) => {
    setActiveMessageId(active ? message.id : null);
  }, []);

  useEffect(() => {
    const upwardScrollKeys = new Set(['ArrowUp', 'PageUp', 'Home']);
    const isScrollbarPointerIntent = (event: PointerEvent, el: HTMLElement): boolean => {
      if (event.button !== 0) return false;
      const scrollbarWidth = el.offsetWidth - el.clientWidth;
      if (scrollbarWidth <= 0) return false;
      const rect = el.getBoundingClientRect();
      const hitInset = Math.max(14, scrollbarWidth + 2);
      const direction = window.getComputedStyle(el).direction;
      if (direction === 'rtl') {
        return event.clientX >= rect.left && event.clientX <= rect.left + hitInset;
      }
      return event.clientX <= rect.right && event.clientX >= rect.right - hitInset;
    };
    const handleWheel = (event: WheelEvent) => {
      if (event.deltaY < -AUTO_FOLLOW_WHEEL_INTENT_EPSILON_PX) {
        markUserScrollIntent();
      }
    };
    const handlePointerDown = (event: PointerEvent) => {
      const el = mainRef.current;
      if (el && isScrollbarPointerIntent(event, el)) {
        markUserScrollIntent();
        cancelFollowSettle();
      }
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || isEditableShortcutTarget(event.target)) return;
      if (upwardScrollKeys.has(event.key) || (event.key === ' ' && event.shiftKey)) {
        markUserScrollIntent();
        cancelFollowSettle();
      }
    };

    function recalc() {
      const el = mainRef.current;
      if (!el) return;
      const currentScrollTop = el.scrollTop;
      const prevScrollTop = lastScrollTopRef.current;
      const scrolledUp = currentScrollTop < prevScrollTop - AUTO_FOLLOW_SCROLL_TOP_EPSILON_PX;
      lastScrollTopRef.current = currentScrollTop;
      const dist = el.scrollHeight - (currentScrollTop + el.clientHeight);
      isNearBottomRef.current = dist <= AUTO_FOLLOW_NEAR_BOTTOM_PX;
      if (Date.now() <= programmaticScrollUntilRef.current) {
        if (autoFollowRef.current && autoFollowPausedRef.current) {
          setAutoFollowPausedValue(false);
        }
        return;
      }
      // 一律读 ref：autoFollow / autoFollowPaused 在流式期间高频变化，若进依赖
      // 数组，这整套监听器每来一条消息就拆装一次，并同步跑 recalc 强制回流。
      if (!autoFollowRef.current) {
        cancelFollowSettle();
        if (autoFollowPausedRef.current) setAutoFollowPausedValue(false);
        if (isNearBottomRef.current) setAutoFollowEnabled(true);
        return;
      }
      if (isNearBottomRef.current) {
        if (autoFollowPausedRef.current) setAutoFollowPausedValue(false);
      } else if (!autoFollowPausedRef.current && scrolledUp && hasRecentUserScrollIntent()) {
        // 仅在用户近期有明确滚动意图且 scrollTop 确实向上时暂停跟随。
        // 浏览器滚动锚点、代码高亮、Markdown/工具卡片测高等流式布局变化也可能
        // 让 scrollTop 回退；这些内容增长场景不能自动取消用户开启的贴底跟随。
        cancelFollowSettle();
        setAutoFollowPausedValue(true);
      }
    }
    recalc();
    const el = mainRef.current;
    if (el) lastScrollTopRef.current = el.scrollTop;
    el?.addEventListener('wheel', handleWheel, { passive: true });
    el?.addEventListener('touchstart', markUserScrollIntent, { passive: true });
    el?.addEventListener('touchmove', markUserScrollIntent, { passive: true });
    el?.addEventListener('pointerdown', handlePointerDown, { passive: true });
    const handleScroll = () => {
      markTranscriptScrollActivity();
      recalc();
    };
    el?.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('resize', recalc);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      el?.removeEventListener('wheel', handleWheel);
      el?.removeEventListener('touchstart', markUserScrollIntent);
      el?.removeEventListener('touchmove', markUserScrollIntent);
      el?.removeEventListener('pointerdown', handlePointerDown);
      el?.removeEventListener('scroll', handleScroll);
      window.removeEventListener('resize', recalc);
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [hasRecentUserScrollIntent, markUserScrollIntent]);

  // 只在离开会话页时清除滚动活动，避免监听器重挂提前提交测量任务。
  useEffect(() => clearTranscriptScrollActivity, []);

  useEffect(() => {
    const target = messagesContentRef.current;
    const scroller = mainRef.current;
    if (!target || !scroller || typeof ResizeObserver === 'undefined') return;
    // 内容增长时持续跟随到底部，仅在用户主动上滑后暂停。
    const shouldFollowOnGrow = () =>
      autoFollowRef.current &&
      !autoFollowPausedRef.current &&
      !hasRecentUserScrollIntent() &&
      !isComposerLayoutTransitioning();
    const observer = new ResizeObserver(() => {
      if (!shouldFollowOnGrow()) return;
      if (resizeFollowFrameRef.current != null) return;
      resizeFollowFrameRef.current = requestAnimationFrame(() => {
        resizeFollowFrameRef.current = null;
        if (shouldFollowOnGrow()) scheduleAutoFollowToBottom('auto');
      });
    });
    observer.observe(target);
    observer.observe(scroller);
    return () => {
      observer.disconnect();
      if (resizeFollowFrameRef.current != null) {
        cancelAnimationFrame(resizeFollowFrameRef.current);
        resizeFollowFrameRef.current = null;
      }
    };
  }, [autoFollow, autoFollowPaused, hasRecentUserScrollIntent]);

  useEffect(() => {
    messagesRef.current = messages;
  }, [messages]);

  const detailBelongsToRoute = detail?.session.id === sessionId;
  const session = detailBelongsToRoute ? detail?.session : undefined;
  const modelSelectionLocked = session?.input_cache_model_selection_locked === true;
  const modelSelectionLockReason = t(
    'composer.model.lockedByInputCache',
    '已锁定服务商、模型与推理强度以保证缓存命中（可在设置→AI→成本控制中关闭输入缓存后再切换）',
  );
  const currentGoal = session?.goal_state?.current ?? null;
  const goalPausedForQueuedMessages = isGoalPausedForQueuedMessages(currentGoal);
  const hasModeLockedGoal = isActiveGoalStatus(currentGoal?.status);
  const hasActiveGoal = hasModeLockedGoal && !goalPausedForQueuedMessages;
  const goalPaused = currentGoal?.status === 'paused';
  const hasRunnableQueuedMessages = queuedComposerMessages.length > 0 && blockedQueuedMessageId !== queuedComposerMessages[0]?.id;
  const goalModeAvailable = Boolean(session && isGoalModeAllowedForTemplate(session.template_id));
  const routeMessages = detailBelongsToRoute ? messages : EMPTY_SESSION_MESSAGES;

  useEffect(() => {
    if (modelSelectionLocked) setShowComposerModelPicker(false);
  }, [modelSelectionLocked]);

  const messageWindowView = useMemo(
    () => deriveMessageWindowView(routeMessages, windowOffset > 0),
    [routeMessages, windowOffset],
  );
  const messageMembershipTrackerRef = useRef<MessageWindowMembershipTracker>({
    revision: 0,
    sessionId: '',
    windowOffset: -1,
    messageIds: [],
  });
  const messageMembershipKey = updateMessageWindowMembership(
    messageMembershipTrackerRef.current,
    sessionId,
    windowOffset,
    messageWindowView.ordered,
  );
  const visibleMessageIdSet = useMemo(() => {
    return new Set(messageWindowView.ordered.map((message) => message.id));
  }, [messageMembershipKey]);

  useEffect(() => {
    if (!olderRenderSettling) return;
    const handle = window.setTimeout(() => {
      setOlderRenderSettlingValue(false);
    }, LOAD_OLDER_RENDER_SETTLE_MS);
    return () => window.clearTimeout(handle);
  }, [olderRenderSettling]);

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

  useLayoutEffect(() => {
    if (!composerLayoutPinnedRef.current) return;
    markTranscriptScrollActivity(COMPOSER_LAYOUT_TRANSITION_GUARD_MS);
    pinComposerLayoutToBottom();
  }, [composerCollapsed]);

  // 折叠/展开期间稳住消息：observer 跟踪 composer 高度变化，
  // 当用户「未在底部」时把 transcript scrollTop 反向补偿，让可视区底部
  // 锚到原始内容偏移，从而上方消息不被「挤上去 / 压下来」。
  // 使用 rAF 合并同帧内的多次 ResizeObserver 回调，避免 CSS transition
  // 期间反复触发补偿导致消息列表抽搐/鬼畜。
  useEffect(() => {
    if (typeof window === 'undefined' || typeof ResizeObserver === 'undefined') return;
    const composerEl = composerSectionRef.current;
    const scroller = mainRef.current;
    if (!composerEl || !scroller) return;
    // 使用 offsetHeight 而非 getBoundingClientRect().height：
    // offsetHeight 不受 CSS transform (scale) 影响，反映真实布局高度，
    // 避免展开/折叠动画期间 scale 变化导致测量值抖动。
    let lastH = composerEl.offsetHeight;
    let pendingDelta = 0;
    let rafId: number | null = null;
    const observer = new ResizeObserver(() => {
      const measured = composerEl.offsetHeight;
      const delta = measured - lastH;
      lastH = measured;
      if (delta === 0) return;
      if (pinComposerLayoutToBottom()) {
        pendingDelta = 0;
        return;
      }
      pendingDelta += delta;
      if (rafId != null) return;
      rafId = requestAnimationFrame(() => {
        rafId = null;
        const totalDelta = pendingDelta;
        pendingDelta = 0;
        if (Math.abs(totalDelta) < 0.5 || !scroller) return;
        if (pinComposerLayoutToBottom()) return;
        // 补偿 scrollTop：保持用户当前可视位置不变。
        // 不使用 clamp 到 maxScroll，因为在 transition 期间
        // scrollHeight 可能尚未更新到位。直接设置即可，
        // 浏览器会自动 clamp 到有效范围。
        scroller.scrollTop = scroller.scrollTop + totalDelta;
      });
    });
    observer.observe(composerEl);
    return () => {
      observer.disconnect();
      if (rafId != null) cancelAnimationFrame(rafId);
    };
  }, []);

  useLayoutEffect(() => {
    if (!isComposerLayoutTransitioning() && shouldFollowPinnedMessages()) {
      scheduleAutoFollowToBottom('auto', { requireNearBottom: true });
    }
  }, [composerAttachments.length, selectedSkill?.name, editingDraftMessage?.id, composerError]);

  useEffect(() => {
    if (activeMessageId == null) return;
    if (visibleMessageIdSet.has(activeMessageId)) return;
    setActiveMessageId(null);
  }, [visibleMessageIdSet, activeMessageId]);

  useEffect(() => {
    if (!editingDraftMessage || composerSending) return;
    if (visibleMessageIdSet.has(editingDraftMessage.id)) return;
    editingDraftMessageRef.current = null;
    setEditingDraftMessage(null);
    showSnackbar(t('composer.edit.targetGone', '原消息已在其他客户端被更新'), {
      tone: 'error',
    });
  }, [visibleMessageIdSet, editingDraftMessage, composerSending]);

  // messages 变化 → 自动跟随 / 累计未读
  // 用 useLayoutEffect 在浏览器 paint 前同步钉到底部，避免插入新内容后浏览器 scroll-anchor
  // 先把视口锁在旧位置、随后我们再回拉造成的「上移 → 降落」鬼畜抖动。
  useLayoutEffect(() => {
    const tail = messageWindowView.tail;
    if (!tail) {
      lastTailIdRef.current = null;
      lastTailSignatureRef.current = '';
      lastFollowSignatureRef.current = '';
      return;
    }
    const tailSignature = messageWindowView.tailSignature;
    const followSignature = messageWindowView.followSignature;
    if (lastTailIdRef.current === null) {
      lastTailIdRef.current = tail.id;
      lastTailSignatureRef.current = tailSignature;
      lastFollowSignatureRef.current = followSignature;
      scheduleAutoFollowToBottom('auto');
      return;
    }
    const tailChanged = tail.id !== lastTailIdRef.current;
    const tailContentChanged = tailSignature !== lastTailSignatureRef.current;
    const followContentChanged = followSignature !== lastFollowSignatureRef.current;
    if (!tailChanged && !tailContentChanged && !followContentChanged) return;
    lastTailIdRef.current = tail.id;
    lastTailSignatureRef.current = tailSignature;
    lastFollowSignatureRef.current = followSignature;
    if (canAutoFollowMessages()) {
      const streamingChange = tailContentChanged || followContentChanged;
      const behavior = reduceMotion || streamingChange ? 'auto' : 'smooth';
      scheduleAutoFollowToBottom(behavior);
    } else {
      if (autoFollow) setAutoFollowPausedValue(true);
    }
  }, [
    messageWindowView.tail?.id,
    messageWindowView.tailSignature,
    messageWindowView.followSignature,
    autoFollow,
    autoFollowPaused,
    hasRecentUserScrollIntent,
    reduceMotion,
  ]);

  useEffect(() => {
    if (!pendingWriteApproval || !shouldFollowPinnedMessages()) return;
    scheduleAutoFollowToBottom(reduceMotion ? 'auto' : 'smooth', {
      requireNearBottom: true,
    });
  }, [pendingWriteApproval?.id, autoFollow, autoFollowPaused, reduceMotion]);

  // sendPhase 变化 → 远端冲突探测
  useEffect(() => {
    const running = sendPhase !== 'idle' && sendPhase !== '';
    if (!running) {
      if (remoteRunning) setRemoteRunning(false);
      return;
    }
    const sinceLocal = Date.now() - lastLocalSendAtRef.current;
    if (sinceLocal > REMOTE_RUNNING_LOCAL_SEND_GRACE_MS && !remoteRunning) {
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

  // 识别会话已删除响应，并阻止调用方重复展示普通错误。
  function handleSessionGoneError(e: unknown): boolean {
    if (e instanceof ApiError && e.status === 404) {
      const body = e.body as { error?: string; message?: string } | string | null;
      const marker = typeof body === 'string' ? body : `${body?.error ?? ''} ${body?.message ?? ''}`;
      if (marker.includes('session_deleted_or_not_found')) {
        sseCloseRef.current?.();
        sseCloseRef.current = null;
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
    if (!current || current.is_title_manually_edited || current.auto_title_acquired || current.auto_title_generated_at) {
      return false;
    }
    const visibleUserMessages = messagesRef.current.filter((item) => item.role === 'user' && (item.content ?? '').trim().length > 0);
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
        ? {
            ...prev,
            session: mergeSessionSummary(prev.session, summary),
            runtime,
          }
        : { session: summary, runtime };
    });
    if (typeof summary.message_count === 'number') {
      updateTotalKnown(summary.message_count);
    }
    if (summary.auto_title_acquired || summary.auto_title_generated_at || summary.is_title_manually_edited) {
      clearAutoTitleRefreshTimers();
    }
  }

  async function hydrateCacheStatisticsOnDemand(): Promise<void> {
    if (!sessionId || cacheStatisticsHydratingSessionIdRef.current === sessionId) {
      return;
    }
    const requestSessionId = sessionId;
    cacheStatisticsHydratingSessionIdRef.current = requestSessionId;
    try {
      const fresh = await getSession(requestSessionId, {
        hydrateCacheStatistics: true,
      });
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setDetail((previous) => previous
        ? {
            ...fresh,
            session: mergeSessionSummary(previous.session, fresh.session),
          }
        : fresh);
      updateTotalKnown(fresh.session.message_count ?? totalKnownRef.current);
    } catch (error: unknown) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(error) || handleSessionGoneError(error)) return;
    } finally {
      if (cacheStatisticsHydratingSessionIdRef.current === requestSessionId) {
        cacheStatisticsHydratingSessionIdRef.current = null;
      }
    }
  }

  function replaceMessageWindow(items: SessionMessage[], offset: number): void {
    if (messagesWindowLooksIdentical(messagesRef.current, items, windowOffsetRef.current, offset)) {
      return;
    }
    messagesRef.current = items;
    windowOffsetRef.current = offset;
    setMessages(items);
    setWindowOffset(offset);
  }

  function replaceBoundedMessageWindow(items: SessionMessage[], offset: number): void {
    const bounded = boundLiveMessageWindow(items, offset);
    replaceMessageWindow(bounded.items, bounded.offset);
  }

  function updateTotalKnown(value: number): void {
    totalKnownRef.current = value;
    setTotalKnown((current) => (current === value ? current : value));
  }

  function messageWindowHasNewerMessages(): boolean {
    return remainingNewerMessageCount(
      totalKnownRef.current,
      windowOffsetRef.current,
      messagesRef.current.length,
    ) > 0;
  }

  function renderedMessageRow(messageId: string): HTMLElement | null {
    const container = messagesContentRef.current;
    if (!container || !messageId) return null;
    const escaped = typeof CSS !== 'undefined' && typeof CSS.escape === 'function'
      ? CSS.escape(messageId)
      : messageId.replace(/["\\]/g, '\\$&');
    return container.querySelector<HTMLElement>(`[data-message-id="${escaped}"]`);
  }

  function updateSendPhaseValue(value: string): void {
    setSendPhase((current) => (current === value ? current : value));
  }

  function updateLastErrorValue(value: string | null): void {
    setLastError((current) => (current === value ? current : value));
  }

  function samePendingWriteApproval(a: PendingWriteApproval | null | undefined, b: PendingWriteApproval | null | undefined): boolean {
    return (a?.id ?? '') === (b?.id ?? '');
  }

  function updatePendingWriteApprovalValue(value: PendingWriteApproval | null | undefined): void {
    const next = value ?? null;
    setPendingWriteApproval((current) => (samePendingWriteApproval(current, next) ? current : next));
  }

  function updateStreamThrottleValue(throttle: NonNullable<SessionEventSnapshot['effective_stream_throttle']> | undefined): void {
    if (!throttle) return;
    setStreamThrottle((current) => {
      const next = {
        chars: throttle.chars_per_second ?? 0,
        cards: throttle.cards_per_second ?? 0,
        hasOverride: throttle.has_session_override === true,
        durationExpired: throttle.duration_expired === true,
        enabled: throttle.enabled !== false,
        wasInitiallyThrottled: throttle.was_initially_throttled === true,
        throughputBuckets: throttle.throughput_buckets,
      };
      const sameBuckets =
        (current?.throughputBuckets?.length ?? 0) === (next.throughputBuckets?.length ?? 0) &&
        (current?.throughputBuckets ?? []).every((value, index) => value === next.throughputBuckets?.[index]);
      return current &&
        current.chars === next.chars &&
        current.cards === next.cards &&
        current.hasOverride === next.hasOverride &&
        current.durationExpired === next.durationExpired &&
        current.enabled === next.enabled &&
        current.wasInitiallyThrottled === next.wasInitiallyThrottled &&
        sameBuckets
        ? current
        : next;
    });
  }

  function applyServerMessageWindow(latest: SessionMessage[], nextOffset: number, options: MergeServerWindowOptions = {}): void {
    const result = mergeServerWindowResult(messagesRef.current, latest, windowOffsetRef.current, nextOffset, options);
    replaceBoundedMessageWindow(result.items, result.offset);
  }

  async function refreshAutoTitleSummary(): Promise<boolean> {
    if (!sessionId) return true;
    const current = detailRef.current?.session;
    if (!current || current.is_title_manually_edited || current.auto_title_acquired || current.auto_title_generated_at) {
      return true;
    }
    const fresh = await getSession(sessionId);
    if (!ownsSessionAsyncResult(sessionId)) return true;
    setDetail((prev) =>
      prev
        ? {
            ...fresh,
            session: mergeSessionSummary(prev.session, fresh.session),
          }
        : fresh,
    );
    updateSendPhaseValue(fresh.runtime.send_phase);
    updateLastErrorValue(fresh.runtime.last_error);
    updateTotalKnown(fresh.session.message_count ?? messagesRef.current.length);
    return Boolean(fresh.session.is_title_manually_edited || fresh.session.auto_title_acquired || fresh.session.auto_title_generated_at);
  }

  function scheduleAutoTitleFollowUp(): void {
    clearAutoTitleRefreshTimers();
    autoTitleRefreshTimersRef.current = AUTO_TITLE_FOLLOW_UP_DELAYS_MS.map((delay) =>
      window.setTimeout(() => {
        void refreshAutoTitleSummary()
          .then((done) => {
            if (done) clearAutoTitleRefreshTimers();
          })
          .catch((error: unknown) => {
            if (handleAuthError(error) || handleSessionGoneError(error)) {
              clearAutoTitleRefreshTimers();
            }
          });
      }, delay),
    );
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
    setOlderRenderSettlingValue(false);
    setTranscriptReadySessionId(null);
    setError(null);
    associatedKnowledgeBaseCacheRef.current.clear();
    replaceMessageWindow([], 0);
    updateTotalKnown(0);
    setActiveMessageId(null);
    setComposerModelKey('');
    setComposerMode('normal');
    editingDraftMessageRef.current = null;
    setEditingDraftMessage(null);
    lastTailIdRef.current = null;
    lastTailSignatureRef.current = '';
    Promise.all([
      getSession(requestSessionId, { signal: ctrl.signal }),
      listMessages(requestSessionId, {
        limit: INITIAL_PAGE_SIZE,
        tail: true,
        signal: ctrl.signal,
      }),
    ])
      .then(([d, m]) => {
        if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
        setDetail(m.session ? { ...d, session: mergeSessionSummary(d.session, m.session) } : d);
        // 历史会话首批消息直接标记为已入场，绕过 CSS 入场 + 高度量动画的
        // 并发开销；后续流式 / SSE 真正新增的消息仍会正常入场。
        markMessagesAsAppeared(m.items.map((it) => it.id));
        replaceBoundedMessageWindow(m.items, m.offset);
        updateTotalKnown(m.total);
        updateSendPhaseValue(m.send_phase || d.runtime.send_phase || 'idle');
        updateLastErrorValue(m.last_error ?? d.runtime.last_error ?? null);
        updatePendingWriteApprovalValue(m.pending_write_approval);
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

  async function refresh({
    replaceWithLatest = false,
  }: { replaceWithLatest?: boolean } = {}): Promise<void> {
    if (!sessionId) return;
    const requestSessionId = sessionId;
    const shouldReplaceWindow = replaceWithLatest || messageWindowHasNewerMessages();
    if (messagesAbortRef.current) {
      if (!shouldReplaceWindow) return;
      messagesAbortRef.current.abort();
      messagesAbortRef.current = null;
      setRefreshing(false);
    }
    if (olderMessagesAbortRef.current) {
      if (!shouldReplaceWindow) return;
      olderMessagesAbortRef.current.abort();
      olderMessagesAbortRef.current = null;
      setLoadingOlder(false);
      setOlderRenderSettlingValue(false);
    }
    const ctrl = new AbortController();
    messagesAbortRef.current = ctrl;
    setRefreshing(true);
    try {
      const m = await listMessages(requestSessionId, {
        limit: PAGE_SIZE,
        tail: true,
        signal: ctrl.signal,
      });
      if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
      if (shouldReplaceWindow) {
        markMessagesAsAppeared(m.items.map((item) => item.id));
        replaceBoundedMessageWindow(m.items, m.offset);
      } else {
        applyServerMessageWindow(m.items, m.offset, {
          preserveLocalStreamingTail: isRunningPhase(m.send_phase) || isRunningPhase(sendPhase),
        });
      }
      updateTotalKnown(m.total);
      updateSendPhaseValue(m.send_phase);
      updateLastErrorValue(m.last_error);
      updatePendingWriteApprovalValue(m.pending_write_approval);
      if (m.session) mergeSessionSummaryFromPolling(m.session);
      if (shouldReplaceWindow) {
        schedulePostRenderFrame(() => scheduleAutoFollowToBottom('auto'));
      }
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
    if (
      loadingOlder ||
      olderRenderSettlingRef.current ||
      olderMessagesAbortRef.current ||
      messagesAbortRef.current
    ) {
      return;
    }
    const currentOffset = windowOffsetRef.current;
    if (currentOffset <= 0) return;
    const requestSessionId = sessionId;
    const ctrl = new AbortController();
    olderMessagesAbortRef.current = ctrl;
    setLoadingOlder(true);
    const scroller = mainRef.current;
    const beforeHeight = scroller?.scrollHeight ?? 0;
    const beforeY = scroller?.scrollTop ?? 0;
    const currentMessages = messagesRef.current;
    const anchorId = currentMessages[0]?.id ?? '';
    const anchorTop = renderedMessageRow(anchorId)?.getBoundingClientRect().top;
    try {
      const offset = Math.max(0, currentOffset - PAGE_SIZE);
      const requestedLimit = Math.min(
        MESSAGE_LIST_MAX_LOADED_MESSAGES,
        currentMessages.length + (currentOffset - offset),
      );
      const m = await listMessages(requestSessionId, {
        limit: Math.max(1, requestedLimit),
        offset,
        signal: ctrl.signal,
      });
      if (ctrl.signal.aborted || !ownsSessionAsyncResult(requestSessionId)) return;
      const existing = new Set(currentMessages.map((item) => item.id));
      const incoming = m.items.filter((item) => !existing.has(item.id));
      markMessagesAsAppeared(incoming.map((item) => item.id));
      setOlderRenderSettlingValue(incoming.length > 0);
      replaceBoundedMessageWindow(m.items, m.offset);
      updateTotalKnown(m.total);
      updateSendPhaseValue(m.send_phase);
      updateLastErrorValue(m.last_error);
      updatePendingWriteApprovalValue(m.pending_write_approval);
      if (m.session) mergeSessionSummaryFromPolling(m.session);
      schedulePostRenderFrame(() => {
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        const el = mainRef.current;
        if (!el) return;
        const anchoredRow = renderedMessageRow(anchorId);
        if (anchoredRow != null && anchorTop != null) {
          el.scrollBy({
            top: anchoredRow.getBoundingClientRect().top - anchorTop,
            behavior: 'auto',
          });
          return;
        }
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

  async function revealCacheHitTurn(point: CacheHitTrendPoint): Promise<void> {
    const anchorMessageId = point.anchorMessageId?.trim() ?? '';
    const starterMessageId = point.starterMessageId?.trim() ?? '';
    let targetMessageId = anchorMessageId || starterMessageId;
    if (!targetMessageId) {
      showSnackbar(t('tokenPopup.revealUnavailable', '该轮次暂时没有可定位的消息。'));
      return;
    }

    cacheHitRevealAbortRef.current?.abort();
    if (cacheHitHighlightTimerRef.current != null) {
      window.clearTimeout(cacheHitHighlightTimerRef.current);
      cacheHitHighlightTimerRef.current = null;
    }
    setTranscriptRevealTarget(null);
    setHighlightedMessageId(null);
    const ctrl = new AbortController();
    cacheHitRevealAbortRef.current = ctrl;
    const generation = ++cacheHitRevealGenerationRef.current;
    const requestSessionId = sessionId;
    const requestIsCurrent = () =>
      !ctrl.signal.aborted &&
      cacheHitRevealGenerationRef.current === generation &&
      ownsSessionAsyncResult(requestSessionId);

    try {
      let targetFound = messagesRef.current.some(
        (message) => message.id === targetMessageId,
      );
      let pageResult: Awaited<ReturnType<typeof listMessages>> | null = null;

      if (!targetFound) {
        pageResult = await listMessages(requestSessionId, {
          limit: MESSAGE_LIST_MAX_LOADED_MESSAGES,
          revealMessageId: starterMessageId || targetMessageId,
          signal: ctrl.signal,
        });
        if (!requestIsCurrent()) return;
        const resolvedMessageId =
          pageResult.resolved_reveal_message_id?.trim() ?? '';
        if (resolvedMessageId) targetMessageId = resolvedMessageId;
        targetFound = pageResult.items.some(
          (message) => message.id === targetMessageId,
        );
      }

      if (!targetFound || !requestIsCurrent()) {
        showSnackbar(
          t(
            'tokenPopup.revealFailed',
            '未能定位该轮次消息，消息可能已被删除或没有可展示内容。',
          ),
        );
        return;
      }

      if (pageResult != null) {
        markMessagesAsAppeared(pageResult.items.map((message) => message.id));
        replaceMessageWindow(pageResult.items, pageResult.offset);
        updateTotalKnown(pageResult.total);
        updateSendPhaseValue(pageResult.send_phase);
        updateLastErrorValue(pageResult.last_error);
        updatePendingWriteApprovalValue(pageResult.pending_write_approval);
        if (pageResult.session) mergeSessionSummaryFromPolling(pageResult.session);
      }

      setAutoFollowEnabled(false);
      extendProgrammaticScrollWindow(CACHE_HIT_REVEAL_SCROLL_GUARD_MS);
      setTranscriptRevealTarget({ messageId: targetMessageId, generation });
      setHighlightedMessageId(targetMessageId);

      let row: HTMLElement | null = null;
      for (let attempt = 0; attempt < CACHE_HIT_REVEAL_MATERIALIZE_FRAMES; attempt += 1) {
        await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()));
        if (!requestIsCurrent()) return;
        row = renderedMessageRow(targetMessageId);
        if (row) break;
      }
      if (!row) {
        setTranscriptRevealTarget(null);
        setHighlightedMessageId(null);
        showSnackbar(
          t('tokenPopup.revealFailed', '未能定位该轮次消息，消息可能已被删除或没有可展示内容。'),
        );
        return;
      }

      row.scrollIntoView({
        block: 'center',
        inline: 'nearest',
        behavior: reduceMotion ? 'auto' : 'smooth',
      });
      if (cacheHitHighlightTimerRef.current != null) {
        window.clearTimeout(cacheHitHighlightTimerRef.current);
      }
      cacheHitHighlightTimerRef.current = window.setTimeout(() => {
        cacheHitHighlightTimerRef.current = null;
        if (cacheHitRevealGenerationRef.current !== generation) return;
        setTranscriptRevealTarget(null);
        setHighlightedMessageId(null);
      }, CACHE_HIT_REVEAL_HIGHLIGHT_MS);
    } catch (error: unknown) {
      if (!requestIsCurrent() || isAbortError(error)) return;
      if (handleAuthError(error) || handleSessionGoneError(error)) return;
      showSnackbar(
        `${t('tokenPopup.revealFailed', '未能定位该轮次消息')}：${
          error instanceof Error ? error.message : String(error)
        }`,
        { tone: 'error' },
      );
    } finally {
      if (cacheHitRevealAbortRef.current === ctrl) {
        cacheHitRevealAbortRef.current = null;
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
      cacheHitRevealAbortRef.current?.abort();
      cacheHitRevealAbortRef.current = null;
      cacheHitRevealGenerationRef.current += 1;
      if (cacheHitHighlightTimerRef.current != null) {
        window.clearTimeout(cacheHitHighlightTimerRef.current);
        cacheHitHighlightTimerRef.current = null;
      }
      sseCloseRef.current?.();
      sseCloseRef.current = null;
      clearAutoTitleRefreshTimers();
      cancelPostRenderFrames();
    };
  }, [auth.loading, sessionId]);

  // SSE 同步消息和运行状态，连续失败后切换到轮询兜底。
  useEffect(() => {
    if (auth.loading || !sessionId) return;
    sseCloseRef.current?.();
    const eventSessionId = sessionId;
    sseFailRef.current = 0;
    setSseLive(false);
    // 使用轻量指纹跳过未变化的完整窗口快照，避免重复合并。
    let lastSnapshotFingerprint = '';
    const close = subscribeSessionEvents(eventSessionId, {
      onOpen: () => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
        sseFailRef.current = 0;
        setSseLive(true);
      },
      onSnapshot: (snap) => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
        // Token 统计纳入指纹，确保统计变化能刷新弹窗。
        const stats = (snap.session.statistics ?? {}) as Record<string, unknown>;
        const tokenSig = `${stats['total_prompt_tokens'] ?? 0}:${stats['cache_read_tokens'] ?? 0}:${stats['cache_creation_tokens'] ?? 0}:${stats['cache_hit_ratio'] ?? 'n'}:${(stats['cache_hit_trend_points'] as unknown[] | undefined)?.length ?? 0}`;
        const promptMeta = recordFromUnknown(snap.session.last_prompt_metadata);
        const contextSig = `${promptMeta['context_budget_estimated_prompt_tokens'] ?? 0}:${promptMeta['context_budget_effective_window_tokens'] ?? 0}:${promptMeta['context_budget_usage_percent'] ?? 0}`;
        const fingerprint = `${snapshotMessagesFingerprint(snap.messages)}|` + `${snap.send_phase}|${snap.last_error?.length ?? 0}|${snap.session.message_count ?? 0}|${snap.session.updated_at ?? ''}|` + `tok=${tokenSig}|ctx=${contextSig}`;
        if (fingerprint === lastSnapshotFingerprint) return;
        lastSnapshotFingerprint = fingerprint;
        // 增量合并复用未变化的消息前缀，仅更新流式尾消息。
        const snapOffset = snap.message_window?.offset ?? Math.max(0, (snap.session.message_count ?? snap.messages.length) - snap.messages.length);
        const snapTotal = snap.message_window?.total ?? snap.session.message_count ?? snap.messages.length;
        const emptyWindowWouldHideLoadedHistory = snap.messages.length === 0 && snapTotal > 0 && messagesRef.current.length > 0;
        if (!emptyWindowWouldHideLoadedHistory && !messageWindowHasNewerMessages()) {
          applyServerMessageWindow(snap.messages, snapOffset, {
            preserveLocalStreamingTail: isRunningPhase(snap.send_phase),
          });
        }
        updateTotalKnown(snapTotal);
        setDetail((prev) => {
          const runtime = {
            send_phase: snap.send_phase,
            can_stop: snap.can_stop,
            last_error: snap.last_error,
          };
          return prev
            ? {
                ...prev,
                session: mergeSessionSummary(prev.session, snap.session),
                runtime,
              }
            : { session: snap.session, runtime };
        });
        if (snap.session.auto_title_acquired || snap.session.auto_title_generated_at || snap.session.is_title_manually_edited) {
          clearAutoTitleRefreshTimers();
        }
        updateSendPhaseValue(snap.send_phase);
        updateLastErrorValue(snap.last_error);
        updatePendingWriteApprovalValue(snap.pending_write_approval);
        updateStreamThrottleValue(snap.effective_stream_throttle);
      },
      onDeleted: () => {
        if (!ownsSessionAsyncResult(eventSessionId)) return;
        if (sseCloseRef.current === close) {
          sseCloseRef.current?.();
          sseCloseRef.current = null;
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
  const attachmentMaxBytes = positiveIntegerOr(
    meta?.attachments?.max_file_bytes,
    DEFAULT_ATTACHMENT_MAX_BYTES,
  );
  const attachmentMaxTotalBytes = positiveIntegerOr(
    meta?.attachments?.max_total_bytes,
    DEFAULT_ATTACHMENT_MAX_TOTAL_BYTES,
  );
  const attachmentMaxCount = positiveIntegerOr(
    meta?.attachments?.max_count,
    DEFAULT_ATTACHMENT_MAX_COUNT,
  );
  const allowedModels = useMemo<ApiMetaModel[]>(() => meta?.models ?? [], [meta]);
  const allowedModes = useMemo<string[]>(() => meta?.conversation_modes ?? ['normal'], [meta]);
  // 与 App 端 _ComposerInstructionsStrip 1:1 对齐：meta.instructions 已在
  // service 端按 allowedInstructionIds + enabled 过滤，前端直接消费。
  const availableInstructions = useMemo<ApiMetaInstruction[]>(() => meta?.instructions ?? [], [meta]);
  const shortcutBindings = useMemo(() => meta?.shortcut_bindings ?? {}, [meta]);
  const selectedModel = useMemo(() => allowedModels.find((model) => model.key === composerModelKey), [allowedModels, composerModelKey]);
  const selectedModelName = selectedModel?.model_id || selectedModel?.label || '';
  const titleSummaryDefaultModelKey = useMemo(() => {
    const sessionModelKey = detail?.session.last_model_key ?? '';
    return resolveDefaultTitleModelKey(
      allowedModels,
      sessionModelKey || composerModelKey || meta?.active_model_key || '',
    );
  }, [allowedModels, composerModelKey, detail?.session.last_model_key, meta?.active_model_key]);
  const modelAllowedModes = useMemo(() => {
    const filtered = allowedModes.filter((mode) => modelSupportsMode(selectedModel, mode));
    return filtered.length > 0 ? filtered : ['normal'];
  }, [allowedModes, selectedModel]);
  const composerModeOptions = useMemo(() => allComposerModes(allowedModes), [allowedModes]);
  const allowedMessageTypes = useMemo<string[]>(() => meta?.message_types ?? ['text', 'attachment'], [meta]);
  const sessionModeOptions = useMemo<SessionMode[]>(() => {
    const modes: SessionMode[] = ['chat'];
    if (meta?.service?.plan_mode_enabled) modes.push('plan');
    if (goalModeAvailable) modes.push('goal');
    return modes;
  }, [goalModeAvailable, meta?.service?.plan_mode_enabled]);
  const attachmentsAllowed =
    allowedMessageTypes.includes('attachment') &&
    (modelSupportsAttachmentKind(selectedModel, 'image') || modelSupportsAttachmentKind(selectedModel, 'file'));
  const attachmentAccept = useMemo(() => attachmentAcceptForModel(selectedModel), [selectedModel]);
  const textAllowed = allowedMessageTypes.includes('text');

  async function changeComposerReasoningEffort(effort: string): Promise<boolean> {
    if (!selectedModel || reasoningEffortSaving) return false;
    if (modelSelectionLocked) {
      showSnackbar(modelSelectionLockReason);
      return false;
    }
    setReasoningEffortSaving(true);
    let saved = false;
    try {
      await updateModelReasoningEffort(selectedModel.key, effort, sessionId);
      saved = true;
      await refreshMeta();
      showSnackbar(t('composer.reasoning.saved', '推理强度已更新'), {
        tone: 'success',
      });
      return true;
    } catch (error) {
      if (handleAuthError(error)) return false;
      if (saved) {
        showSnackbar(
          t(
            'composer.reasoning.savedRefreshPending',
            '推理强度已保存，界面将在下次同步时刷新',
          ),
        );
      } else {
        const message = error instanceof Error ? error.message : String(error);
        showSnackbar(
          `${t('composer.reasoning.saveFailed', '推理强度保存失败')}：${message}`,
          { tone: 'error' },
        );
      }
      return saved;
    } finally {
      if (mountedRef.current) setReasoningEffortSaving(false);
    }
  }

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
    setAtMentionFilePickerOpen(false);
    resetSlashTriggerState();
    resetAtMentionTriggerState();
    if (!composerCollapsed) {
      schedulePostRenderFrame(() => composerTextareaRef.current?.focus());
    }
  }

  function validateComposerPayload(text: string, attachments: SendMessageAttachment[], modelKey: string, mode: string, model: typeof selectedModel): string | null {
    if (!text && attachments.length === 0) return t('composer.error.empty', '请输入内容或添加附件');
    if (text && !textAllowed) return t('composer.error.textNotAllowed', '当前 service 禁用了文本消息');
    if (attachments.length > 0 && (!allowedMessageTypes.includes('attachment') || model?.supports_attachments === false)) {
      return t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件');
    }
    if (attachments.length > attachmentMaxCount) {
      return `${t('composer.error.attachmentCountLimit', '单条消息附件数量已达上限')} (${attachmentMaxCount})`;
    }
    const attachmentBytes = attachments.reduce(
      (total, attachment) => total + decodedBase64Size(attachment.data_base64),
      0,
    );
    if (attachmentBytes > attachmentMaxTotalBytes) {
      return `${t('composer.error.attachmentTotalLimit', '单条消息附件总大小已达上限')} (${(attachmentMaxTotalBytes / (1024 * 1024)).toFixed(0)} MiB)`;
    }
    const unsupported = attachments.some((attachment) => !modelSupportsAttachmentKind(
      model,
      composerAttachmentKind(attachment.name),
      attachment.name,
    ));
    if (unsupported) {
      return t('composer.error.attachmentTypeNotSupported', '当前模型不支持所选附件类型');
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
    // 读 ref 而非 state：去抖窗口内的最新输入不能丢。
    const text = composerTextRef.current.trim();
    const attachments = copyQueuedAttachments();
    const validation = validateComposerPayload(text, attachments, composerModelKey, composerMode, selectedModel);
    if (validation) {
      setComposerError(validation);
      return false;
    }
    const currentQueue = queuedComposerMessagesRef.current;
    if (currentQueue.length >= COMPOSER_QUEUE_MAX_MESSAGES) {
      setComposerError(
        `${t('composer.queue.countLimit', '等待队列已达上限')} (${COMPOSER_QUEUE_MAX_MESSAGES})`,
      );
      return false;
    }
    const queuedAttachmentBytes = currentQueue.reduce(
      (queueTotal, item) => queueTotal + item.attachments.reduce(
        (itemTotal, attachment) => itemTotal + decodedBase64Size(attachment.data_base64),
        0,
      ),
      0,
    );
    const nextAttachmentBytes = attachments.reduce(
      (total, attachment) => total + decodedBase64Size(attachment.data_base64),
      0,
    );
    if (queuedAttachmentBytes + nextAttachmentBytes > COMPOSER_QUEUE_MAX_ATTACHMENT_BYTES) {
      setComposerError(
        `${t('composer.queue.attachmentLimit', '等待队列附件总大小已达上限')} (${COMPOSER_QUEUE_MAX_ATTACHMENT_BYTES / (1024 * 1024)} MiB)`,
      );
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
    clearQueuedMessageRetryBlock();
    const nextQueue = [...currentQueue, queued];
    queuedComposerMessagesRef.current = nextQueue;
    setQueuedComposerMessages(nextQueue);
    setQueuedListMotionGeneration((value) => value + 1);
    setComposerError(null);
    clearComposerAfterQueue();
    showSnackbar(t('composer.queue.added', '消息已加入等待队列，将在当前回答完成后自动发送'), { tone: 'success' });
    return true;
  }

  function removeQueuedMessage(id: string): void {
    if (queueDispatchingId === id || queuedMessageIsExiting(id)) return;
    runAfterQueuedMessageExit(id, () => {
      clearQueuedMessageRetryBlock(id);
      setQueuedComposerMessages((prev) => prev.filter((item) => item.id !== id));
      setQueuedListMotionGeneration((value) => value + 1);
      if (editingQueuedMessageId === id) {
        setEditingQueuedMessageId(null);
        setQueuedEditText('');
      }
    });
  }

  function moveQueuedMessage(from: number, to: number): void {
    clearQueuedMessageRetryBlock();
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
    clearQueuedMessageRetryBlock(id);
    setQueuedComposerMessages((prev) => prev.map((item) => (item.id === id ? { ...item, content: trimmed } : item)));
    setEditingQueuedMessageId(null);
    setQueuedEditText('');
    setQueuedListMotionGeneration((value) => value + 1);
  }

  function removeQueuedMessageAfterSend(id: string): void {
    clearQueuedMessageRetryBlock(id);
    runAfterQueuedMessageExit(id, () => {
      setQueuedComposerMessages((prev) => (prev[0]?.id === id ? prev.slice(1) : prev.filter((item) => item.id !== id)));
      setQueuedListMotionGeneration((value) => value + 1);
      if (editingQueuedMessageId === id) {
        setEditingQueuedMessageId(null);
        setQueuedEditText('');
      }
    });
  }

  async function sendQueuedComposerMessage(next: QueuedComposerMessage): Promise<boolean> {
    const queuedModel = allowedModels.find((model) => model.key === next.modelKey);
    const validation = validateComposerPayload(next.content, next.attachments, next.modelKey, next.mode, queuedModel);
    if (validation) {
      blockQueuedMessageRetry(next.id);
      setComposerError(validation);
      return false;
    }
    const dispatchSessionId = sessionId;
    const returnToLatestAfterSend = messageWindowHasNewerMessages();
    setComposerError(null);
    lastLocalSendAtRef.current = Date.now();
    try {
      const res = await sendMessage(dispatchSessionId, {
        content: next.content,
        modelKey: next.modelKey,
        mode: next.mode,
        attachments: next.attachments,
        selectedSkill: next.selectedSkill,
        skippedInstructionIds: next.skippedInstructionIds,
        allowQueuedGoalInterruption: true,
      });
      if (!ownsSessionAsyncResult(dispatchSessionId)) return false;
      removeQueuedMessageAfterSend(next.id);
      updateSendPhaseValue(res.send_phase || 'sendingMessage');
      if (returnToLatestAfterSend) {
        void returnToLatest();
      } else if (!sseLive) {
        void refresh();
      }
      if (shouldWatchAutoTitleAfterSend(next.content)) scheduleAutoTitleFollowUp();
      return true;
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(dispatchSessionId)) return false;
      if (handleAuthError(e)) return false;
      if (handleSessionGoneError(e)) return false;
      blockQueuedMessageRetry(next.id);
      if (e instanceof ApiError) {
        const body = e.body as { error?: string; message?: string } | null;
        setComposerError(body?.message || t('composer.queue.sendFailed', '等待队列发送失败：HTTP ') + String(e.status) + (body?.error ? ` (${body.error})` : ''));
      } else {
        setComposerError(t('composer.queue.sendFailed', '等待队列发送失败：HTTP ') + (e instanceof Error ? e.message : String(e)));
      }
      return false;
    }
  }

  async function dispatchNextQueuedMessage(): Promise<void> {
    if (queueDispatchingRef.current || queueGuidanceDispatchingRef.current || composerSending || isRunningPhase(sendPhase)) return;
    const next = queuedComposerMessagesRef.current[0];
    if (!next) return;
    if (blockedQueuedMessageIdRef.current === next.id) {
      return;
    }
    queueDispatchingRef.current = true;
    setQueueDispatchingId(next.id);
    try {
      await sendQueuedComposerMessage(next);
    } finally {
      queueDispatchingRef.current = false;
      setQueueDispatchingId(null);
    }
  }

  async function guideQueuedMessage(id: string): Promise<void> {
    if (queueGuidanceDispatchingRef.current || queueDispatchingRef.current || composerSending || stopping) return;
    const next = queuedComposerMessagesRef.current.find((item) => item.id === id);
    if (!next) return;
    queueGuidanceDispatchingRef.current = true;
    setQueueGuidanceDispatchingId(id);
    clearQueuedMessageRetryBlock(id);
    setComposerError(null);
    const requestSessionId = sessionId;
    try {
      if (isRunningPhase(sendPhase)) {
        const previousSendPhase = sendPhase;
        setStopping(true);
        updateSendPhaseValue('idle');
        try {
          const res = await stopMessage(requestSessionId);
          if (!ownsSessionAsyncResult(requestSessionId)) return;
          updateSendPhaseValue(res.send_phase || 'idle');
          if (!sseLive) void refresh();
        } catch (e: unknown) {
          if (!ownsSessionAsyncResult(requestSessionId)) return;
          if (handleAuthError(e)) return;
          if (handleSessionGoneError(e)) return;
          updateSendPhaseValue(previousSendPhase || 'responding');
          updateLastErrorValue(e instanceof Error ? e.message : String(e));
          return;
        } finally {
          if (ownsSessionAsyncResult(requestSessionId)) {
            setStopping(false);
          }
        }
      }
      await sendQueuedComposerMessage(next);
    } finally {
      queueGuidanceDispatchingRef.current = false;
      if (mountedRef.current) {
        setQueueGuidanceDispatchingId(null);
      }
    }
  }

  async function resumeQueuedDeferredGoalIfReady(): Promise<void> {
    if (
      !sessionId ||
      !goalPausedForQueuedMessages ||
      hasRunnableQueuedMessages ||
      queuedGoalResumeInFlightRef.current ||
      queueDispatchingRef.current ||
      queueGuidanceDispatchingRef.current ||
      composerSending ||
      isRunningPhase(sendPhase)
    ) {
      return;
    }
    queuedGoalResumeInFlightRef.current = true;
    const requestSessionId = sessionId;
    try {
      const res = await resumeGoal(requestSessionId, composerModelKey || detail?.session.last_model_key || undefined);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      updateSendPhaseValue(res.send_phase || 'sendingMessage');
      void refresh();
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      setLastError(e instanceof Error ? e.message : String(e));
    } finally {
      queuedGoalResumeInFlightRef.current = false;
    }
  }

  useEffect(() => {
    if (!sessionId || queuedComposerMessages.length === 0) return;
    if (composerSending || queueDispatchingRef.current || queueGuidanceDispatchingRef.current || isRunningPhase(sendPhase)) return;
    const timer = window.setTimeout(() => {
      void dispatchNextQueuedMessage();
    }, QUEUE_SEND_SETTLE_MS);
    return () => window.clearTimeout(timer);
  }, [sessionId, queuedComposerMessages, sendPhase, composerSending, queueGuidanceDispatchingId, allowedModels, allowedMessageTypes, textAllowed, sseLive]);

  useEffect(() => {
    if (!sessionId) return;
    void syncGoalQueueYield(sessionId, hasRunnableQueuedMessages).catch(ignoreError);
    return () => {
      void syncGoalQueueYield(sessionId, false).catch(ignoreError);
    };
  }, [sessionId, hasRunnableQueuedMessages]);

  useEffect(() => {
    if (!sessionId || !goalPausedForQueuedMessages || hasRunnableQueuedMessages) return;
    if (composerSending || queueDispatchingId || queueGuidanceDispatchingId || isRunningPhase(sendPhase)) return;
    const timer = window.setTimeout(() => {
      void resumeQueuedDeferredGoalIfReady();
    }, QUEUE_SEND_SETTLE_MS);
    return () => window.clearTimeout(timer);
  }, [sessionId, goalPausedForQueuedMessages, hasRunnableQueuedMessages, composerSending, queueDispatchingId, queueGuidanceDispatchingId, sendPhase, composerModelKey, detail?.session.last_model_key]);

  useEffect(() => {
    if (allowedModels.length === 0) return;
    const activeModelKey = meta?.active_model_key ?? '';
    const activeModelAllowed = activeModelKey ? allowedModels.some((model) => model.key === activeModelKey) : false;
    const fallbackModelKey = activeModelAllowed ? activeModelKey : allowedModels[0]!.key;
    const sessionModelKey = detail?.session.last_model_key ?? '';
    const sessionModelAllowed = sessionModelKey ? allowedModels.some((model) => model.key === sessionModelKey) : false;
    setComposerModelKey((current) => {
      const currentAllowed = current ? allowedModels.some((model) => model.key === current) : false;
      if (modelSelectionLocked && sessionModelAllowed) return sessionModelKey;
      if (sessionModelAllowed && (!currentAllowed || current === fallbackModelKey)) {
        return sessionModelKey;
      }
      if (!currentAllowed) return fallbackModelKey;
      return current;
    });
  }, [allowedModels, detail?.session.id, detail?.session.last_model_key, meta?.active_model_key, modelSelectionLocked]);

  useEffect(() => {
    if (modelAllowedModes.length > 0 && !modelAllowedModes.includes(composerMode)) {
      setComposerMode(modelAllowedModes[0]!);
    }
  }, [modelAllowedModes, composerMode]);

  // SSE 故障时轮询消息；连接存活时保留低频状态校验。
  const phasePollEnabled = !auth.loading && !sessionGone && Boolean(sessionId) && sendPhase !== 'idle' && sendPhase !== '';
  const phasePollIntervalMs = sseLive ? SSE_PHASE_GUARD_INTERVAL_MS : POLL_INTERVAL_MS;
  useAsyncPolling(
    async (isActive, signal) => {
      const pollSessionId = sessionId;
      if (!pollSessionId) return;
      try {
        const m = await listMessages(pollSessionId, {
          limit: PAGE_SIZE,
          tail: true,
          signal,
        });
        if (!isActive() || !ownsSessionAsyncResult(pollSessionId)) return;
        const offset = m.offset ?? Math.max(0, m.total - m.items.length);
        if (shouldApplyPollingMessageWindow(sseLive, m.send_phase)) {
          // 只合并最新窗口；不动「加载更早」拉过来的历史前缀。
          if (!messageWindowHasNewerMessages()) {
            applyServerMessageWindow(m.items, offset, {
              preserveLocalStreamingTail: isRunningPhase(m.send_phase) || isRunningPhase(sendPhase),
            });
          }
          updateTotalKnown(m.total);
          updateSendPhaseValue(m.send_phase);
          updateLastErrorValue(m.last_error);
          updatePendingWriteApprovalValue(m.pending_write_approval);
          if (m.session) mergeSessionSummaryFromPolling(m.session);
        }
      } catch (e: unknown) {
        if (!isActive() || !ownsSessionAsyncResult(pollSessionId)) return;
        if (handleAuthError(e)) return;
        if (handleSessionGoneError(e)) return;
        updateLastErrorValue(e instanceof Error ? e.message : String(e));
      }
    },
    {
      enabled: phasePollEnabled,
      immediate: false,
      intervalMs: phasePollIntervalMs,
      taskTimeoutMs: SESSION_PHASE_POLL_TIMEOUT_MS,
      onError: (e) => updateLastErrorValue(e instanceof Error ? e.message : String(e)),
    },
  );

  // 窗口隐藏时通知新的助手消息，同一消息只通知一次。
  const lastNotifiedAssistantIdRef = useRef<string | null>(null);
  useEffect(() => {
    const assistant = messageWindowView.latestAssistantMessage;
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
    }).catch(ignoreError);
  }, [messageWindowView.latestAssistantMessage?.id, sessionId, detail?.session.title]);

  const skillPickerResults = useMemo(() => {
    const query = skillPickerQuery.trim().toLowerCase();
    const base = query.length === 0 ? skills : skills.filter((skill) => `${skill.name} ${skill.description}`.toLowerCase().includes(query));
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
    const anchor = computeComposerPickerAnchor(composerTextareaRef.current);
    if (anchor) setSkillPickerAnchor(anchor);
  }, []);

  const recomputeAtMentionFilePickerAnchor = useCallback(() => {
    const anchor = computeComposerPickerAnchor(composerTextareaRef.current);
    if (anchor) setAtMentionFilePickerAnchor(anchor);
  }, []);

  // 浮窗 open ↔ visible 同步：退场生命周期由 useDelayedVisibility 统一管理。
  useEffect(() => {
    if (skillPickerOpen) {
      recomputeSkillPickerAnchor();
      showSkillPicker();
      return;
    }
    hideSkillPicker();
  }, [hideSkillPicker, recomputeSkillPickerAnchor, showSkillPicker, skillPickerOpen]);

  useEffect(() => {
    if (atMentionFilePickerOpen) {
      recomputeAtMentionFilePickerAnchor();
      showAtMentionFilePicker();
      return;
    }
    hideAtMentionFilePicker();
  }, [
    atMentionFilePickerOpen,
    hideAtMentionFilePicker,
    recomputeAtMentionFilePickerAnchor,
    showAtMentionFilePicker,
  ]);

  // 滚动 / resize 时让浮窗锚点跟随 textarea。
  useEffect(() => {
    if (!skillPickerVisible || typeof window === 'undefined') return;
    const handler = () => recomputeSkillPickerAnchor();
    window.addEventListener('scroll', handler, true);
    window.addEventListener('resize', handler);
    return () => {
      window.removeEventListener('scroll', handler, true);
      window.removeEventListener('resize', handler);
    };
  }, [skillPickerVisible, recomputeSkillPickerAnchor]);

  useEffect(() => {
    if (!atMentionFilePickerVisible || typeof window === 'undefined') return;
    const handler = () => recomputeAtMentionFilePickerAnchor();
    window.addEventListener('scroll', handler, true);
    window.addEventListener('resize', handler);
    return () => {
      window.removeEventListener('scroll', handler, true);
      window.removeEventListener('resize', handler);
    };
  }, [atMentionFilePickerVisible, recomputeAtMentionFilePickerAnchor]);

  useEffect(() => {
    if (!skillPickerVisible || typeof document === 'undefined') return;
    const handlePointerDown = (event: PointerEvent) => {
      const target = event.target;
      const textarea = composerTextareaRef.current;
      const overlay = skillPickerOverlayRef.current;
      if (!(target instanceof Node)) return;
      if (textarea?.contains(target) || overlay?.contains(target)) return;
      dismissSkillPicker(true);
    };
    document.addEventListener('pointerdown', handlePointerDown, true);
    return () => {
      document.removeEventListener('pointerdown', handlePointerDown, true);
    };
  }, [skillPickerVisible]);

  useEffect(() => {
    if (!atMentionFilePickerVisible || typeof document === 'undefined') return;
    const handlePointerDown = (event: PointerEvent) => {
      const target = event.target;
      const textarea = composerTextareaRef.current;
      const overlay = atMentionFilePickerOverlayRef.current;
      if (!(target instanceof Node)) return;
      if (textarea?.contains(target) || overlay?.contains(target)) return;
      dismissAtMentionFilePicker(true);
    };
    document.addEventListener('pointerdown', handlePointerDown, true);
    return () => {
      document.removeEventListener('pointerdown', handlePointerDown, true);
    };
  }, [atMentionFilePickerVisible]);

  async function ensureSkillsLoadedForPicker(): Promise<void> {
    if (skillsLoadedRef.current || skillPickerLoading) return;
    setSkillPickerLoading(true);
    try {
      const res = await listSkills();
      setSkills(res.items);
    } catch (error: unknown) {
      setComposerError(`${t('composer.skill.loadFailed', '加载技能列表失败')}：${error instanceof Error ? error.message : String(error)}`);
    } finally {
      skillsLoadedRef.current = true;
      setSkillPickerLoading(false);
    }
  }

  async function restoreSelectedSkillForEdit(message: SessionMessage): Promise<void> {
    const selection = extractUserSkillSelection(message);
    if (!selection) {
      setSelectedSkill(null);
      return;
    }
    let source = skills;
    if (!skillsLoadedRef.current) {
      try {
        const res = await listSkills();
        source = res.items;
        if (!ownsSessionAsyncResult(sessionId) || editingDraftMessageRef.current?.id !== message.id) {
          return;
        }
        setSkills(res.items);
        skillsLoadedRef.current = true;
      } catch {
        source = skills;
        skillsLoadedRef.current = true;
      }
    }
    if (!ownsSessionAsyncResult(sessionId) || editingDraftMessageRef.current?.id !== message.id) {
      return;
    }
    setSelectedSkill(skillSummaryFromSelection(selection, source));
  }

  function computeAtMentionTrigger(text: string, cursor: number): AtMentionTriggerInfo | null {
    const safeCursor = clampNumber(cursor, 0, text.length);
    let atIndex = -1;
    for (let i = safeCursor - 1; i >= 0; i -= 1) {
      const code = text.charCodeAt(i);
      if (code === 0x40) {
        atIndex = i;
        break;
      }
      if (isComposerTriggerWhitespaceCode(code)) break;
    }
    if (atIndex < 0) return null;
    if (atIndex > 0 && !isComposerTriggerWhitespaceCode(text.charCodeAt(atIndex - 1))) {
      return null;
    }
    let tokenEnd = text.length;
    for (let i = atIndex + 1; i < text.length; i += 1) {
      if (isComposerTriggerWhitespaceCode(text.charCodeAt(i))) {
        tokenEnd = i;
        break;
      }
    }
    if (safeCursor > tokenEnd) return null;
    const query = text.slice(atIndex + 1, tokenEnd);
    if (isComposerPathLikeQuery(query)) return null;
    return {
      triggerOffset: atIndex,
      tokenEnd,
      query,
      token: text.slice(atIndex, tokenEnd),
    };
  }

  function pruneAtMentionDismissalForText(text: string): void {
    const dismissal = atMentionDismissalRef.current;
    if (!dismissal) return;
    const currentQuery = readComposerTriggerQueryAtOffset(text, dismissal.offset, '@', true);
    if (currentQuery == null || !shouldSuppressDismissedComposerTrigger(dismissal.query, currentQuery)) {
      atMentionDismissalRef.current = null;
    }
  }

  function readAtMentionDismissalAtOffset(text: string, offset: number): ComposerTriggerDismissal | null {
    const query = readComposerTriggerQueryAtOffset(text, offset, '@', true);
    return query == null ? null : { offset, query };
  }

  function atMentionDismissalSuppresses(text: string, offset: number): boolean {
    pruneAtMentionDismissalForText(text);
    const dismissal = atMentionDismissalRef.current;
    if (!dismissal || dismissal.offset !== offset) return false;
    const current = readAtMentionDismissalAtOffset(text, offset);
    return current != null && shouldSuppressDismissedComposerTrigger(dismissal.query, current.query);
  }

  function updateAtMentionFilePickerForText(text: string, cursor: number): void {
    const trigger = computeAtMentionTrigger(text, cursor);
    if (!trigger) {
      if (atMentionTriggerOffsetRef.current != null) {
        atMentionDismissalRef.current =
          readAtMentionDismissalAtOffset(text, atMentionTriggerOffsetRef.current) ??
          atMentionDismissalRef.current;
      }
      setAtMentionFilePickerOpen(false);
      setAtMentionFilePickerQuery('');
      pruneAtMentionDismissalForText(text);
      return;
    }
    if (atMentionDismissalSuppresses(text, trigger.triggerOffset)) {
      setAtMentionFilePickerOpen(false);
      return;
    }
    atMentionDismissalRef.current = null;
    atMentionTriggerOffsetRef.current = trigger.triggerOffset;
    setAtMentionFilePickerQuery(trigger.query);
    setAtMentionFilePickerOpen(true);
    setSkillPickerOpen(false);
  }

  function removeAtMentionTriggerText(): void {
    const textarea = composerTextareaRef.current;
    const text = textarea?.value ?? composerTextRef.current;
    const cursor = textarea?.selectionStart ?? text.length;
    const trigger =
      computeAtMentionTrigger(text, cursor) ??
      (atMentionTriggerOffsetRef.current == null
        ? null
        : (() => {
            const query = readComposerTriggerQueryAtOffset(text, atMentionTriggerOffsetRef.current!, '@', true);
            if (query == null) return null;
            const tokenStart = atMentionTriggerOffsetRef.current!;
            return {
              triggerOffset: tokenStart,
              tokenEnd: tokenStart + query.length + 1,
              query,
              token: text.slice(tokenStart, tokenStart + query.length + 1),
            };
          })());
    if (!trigger) return;
    const removeEnd =
      trigger.tokenEnd < text.length && /[ \t]/.test(text.charAt(trigger.tokenEnd))
        ? trigger.tokenEnd + 1
        : trigger.tokenEnd;
    const nextText = text.slice(0, trigger.triggerOffset) + text.slice(removeEnd);
    const caret = Math.min(trigger.triggerOffset, nextText.length);
    setComposerText(nextText);
    schedulePostRenderFrame(() => {
      const node = composerTextareaRef.current;
      node?.focus();
      node?.setSelectionRange(caret, caret);
    });
  }

  function openLocalFilePickerFromAtMention(): void {
    if (!attachmentsAllowed) {
      setComposerError(t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件'));
      dismissAtMentionFilePicker(true);
      return;
    }
    removeAtMentionTriggerText();
    dismissAtMentionFilePicker(false);
    composerFileInputRef.current?.click();
  }

  function computeSlashTrigger(text: string, cursor: number): SlashTriggerInfo | null {
    if (!text.startsWith('/')) return null;
    let tokenEnd = text.length;
    for (let i = 0; i < text.length; i += 1) {
      const ch = text.charCodeAt(i);
      if (isComposerTriggerWhitespaceCode(ch)) {
        tokenEnd = i;
        break;
      }
    }
    if (cursor > tokenEnd) return null;
    const query = text.slice(1, tokenEnd);
    if (shouldSuppressSlashSkillQuery(query)) return null;
    const token = text.slice(0, tokenEnd);
    return {
      triggerOffset: COMPOSER_TRIGGER_ROOT_OFFSET,
      tokenEnd,
      query,
      token,
    };
  }

  function pruneSlashDismissalForText(text: string): void {
    const dismissal = slashDismissalRef.current;
    if (!dismissal) return;
    const currentQuery = readComposerTriggerQueryAtOffset(text, dismissal.offset, '/', false);
    if (currentQuery == null || !shouldSuppressDismissedComposerTrigger(dismissal.query, currentQuery)) {
      slashDismissalRef.current = null;
    }
  }

  function readSlashDismissalAtOffset(text: string, offset: number): ComposerTriggerDismissal | null {
    const query = readComposerTriggerQueryAtOffset(text, offset, '/', false);
    return query == null ? null : { offset, query };
  }

  function slashDismissalSuppresses(text: string, offset: number): boolean {
    pruneSlashDismissalForText(text);
    const dismissal = slashDismissalRef.current;
    if (!dismissal || dismissal.offset !== offset) return false;
    const current = readSlashDismissalAtOffset(text, offset);
    return current != null && shouldSuppressDismissedComposerTrigger(dismissal.query, current.query);
  }

  function updateSkillPickerForText(text: string, cursor: number): void {
    if (selectedSkill) {
      setSkillPickerOpen(false);
      return;
    }
    const trigger = computeSlashTrigger(text, cursor);
    if (!trigger) {
      if (slashTriggerOffsetRef.current != null) {
        slashDismissalRef.current = readSlashDismissalAtOffset(text, slashTriggerOffsetRef.current) ?? slashDismissalRef.current;
      }
      setSkillPickerOpen(false);
      setSkillPickerQuery('');
      pruneSlashDismissalForText(text);
      return;
    }
    if (slashDismissalSuppresses(text, trigger.triggerOffset)) {
      setSkillPickerOpen(false);
      return;
    }
    slashDismissalRef.current = null;
    slashTriggerOffsetRef.current = trigger.triggerOffset;
    setSkillPickerQuery(trigger.query);
    setSkillPickerOpen(true);
    setAtMentionFilePickerOpen(false);
    setSkillPickerSelectedIndex(0);
    void ensureSkillsLoadedForPicker();
  }

  function selectSkillForComposer(skill: SkillSummary): void {
    const textarea = composerTextareaRef.current;
    const text = textarea?.value ?? composerTextRef.current;
    const cursor = textarea?.selectionStart ?? 0;
    const trigger = computeSlashTrigger(text, cursor);
    const remainderStart = trigger ? (trigger.tokenEnd < text.length && /[ \t]/.test(text.charAt(trigger.tokenEnd)) ? trigger.tokenEnd + 1 : trigger.tokenEnd) : 0;
    const nextText = text.slice(remainderStart);
    setComposerText(nextText);
    setSelectedSkill(skill);
    setSkillPickerOpen(false);
    resetSlashTriggerState();
    schedulePostRenderFrame(() => {
      const node = composerTextareaRef.current;
      node?.focus();
      node?.setSelectionRange(0, 0);
    });
  }

  function dismissSkillPicker(remember = false): void {
    const textarea = composerTextareaRef.current;
    const text = textarea?.value ?? composerTextRef.current;
    const cursor = textarea?.selectionStart ?? 0;
    const trigger = computeSlashTrigger(text, cursor);
    if (remember && trigger) {
      slashDismissalRef.current = readSlashDismissalAtOffset(text, trigger.triggerOffset) ?? {
        offset: trigger.triggerOffset,
        query: trigger.query,
      };
    } else if (remember && slashTriggerOffsetRef.current != null) {
      slashDismissalRef.current = readSlashDismissalAtOffset(text, slashTriggerOffsetRef.current) ?? slashDismissalRef.current;
    }
    setSkillPickerOpen(false);
  }

  function dismissAtMentionFilePicker(remember = false): void {
    const textarea = composerTextareaRef.current;
    const text = textarea?.value ?? composerTextRef.current;
    const cursor = textarea?.selectionStart ?? text.length;
    const trigger = computeAtMentionTrigger(text, cursor);
    if (remember && trigger) {
      atMentionDismissalRef.current = readAtMentionDismissalAtOffset(text, trigger.triggerOffset) ?? {
        offset: trigger.triggerOffset,
        query: trigger.query,
      };
    } else if (remember && atMentionTriggerOffsetRef.current != null) {
      atMentionDismissalRef.current =
        readAtMentionDismissalAtOffset(text, atMentionTriggerOffsetRef.current) ??
        atMentionDismissalRef.current;
    }
    setAtMentionFilePickerOpen(false);
    if (!remember) setAtMentionFilePickerQuery('');
  }

  function handleComposerKeyDown(e: KeyboardEvent): void {
    if (atMentionFilePickerOpen) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        return;
      }
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        openLocalFilePickerFromAtMention();
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        dismissAtMentionFilePicker(true);
        return;
      }
    }
    if (skillPickerOpen) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSkillPickerSelectedIndex((index) => (skillPickerResults.length === 0 ? 0 : (index + 1) % skillPickerResults.length));
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

  async function readFileAsAttachment(file: File): Promise<{ att: SendMessageAttachment; mime: string; dataUrl: string }> {
    const dataUrl = await readBlobAsDataUrl(file, {
      timeoutMs: ATTACHMENT_READ_TIMEOUT_MS,
      failureMessage: '附件读取失败',
      timeoutMessage: '附件读取超时',
    });
    const data = base64PayloadFromDataUrl(dataUrl);
    if (data == null) throw new Error('附件内容为空');
    const mime = file.type || mimeForAttachmentName(file.name) || 'application/octet-stream';
    return {
      att: { name: file.name, data_base64: data },
      mime,
      dataUrl: `data:${mime};base64,${data}`,
    };
  }

  async function restoreAttachmentsForEdit(message: SessionMessage): Promise<void> {
    const requestSessionId = sessionId;
    const assets = collectEditableAttachmentAssets(message);
    if (assets.length === 0) return;
    const restoredAttachments: SendMessageAttachment[] = [];
    const restoredPreviews: { mime: string; dataUrl: string; size: number }[] = [];
    let restoredBytes = 0;
    let failed = 0;
    for (const asset of assets) {
      if (restoredAttachments.length >= attachmentMaxCount) {
        failed += 1;
        continue;
      }
      const timed = createTimedAbortController(ATTACHMENT_READ_TIMEOUT_MS);
      try {
        const blob = await fetchBlobBounded(
          buildSessionAssetUrl(requestSessionId, asset.path),
          {
            credentials: 'same-origin',
            maxBytes: attachmentMaxBytes,
            signal: timed.controller.signal,
          },
        );
        if (restoredBytes + blob.size > attachmentMaxTotalBytes) {
          throw new Error(t('composer.error.attachmentTotalLimit', '单条消息附件总大小已达上限'));
        }
        const file = new File([blob], asset.name, {
          type: asset.mime || blob.type || 'application/octet-stream',
        });
        const item = await readFileAsAttachment(file);
        restoredAttachments.push(item.att);
        restoredPreviews.push({
          mime: item.mime,
          dataUrl: item.dataUrl,
          size: blob.size,
        });
        restoredBytes += blob.size;
      } catch {
        failed += 1;
      } finally {
        timed.dispose();
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
    return new Promise((resolve) => {
      imageEditorResolverRef.current = resolve;
      setImageEditorInput(input);
    });
  }

  function settleImageEditor(result: ImageEditorResult | null): void {
    const resolve = imageEditorResolverRef.current;
    imageEditorResolverRef.current = null;
    setImageEditorInput(null);
    resolve?.(result);
  }

  function openGoalStartOptionsDialog(): Promise<GoalStartOptions | null> {
    goalStartOptionsResolverRef.current?.(null);
    setGoalStartOptionsOpen(true);
    return new Promise((resolve) => {
      goalStartOptionsResolverRef.current = resolve;
    });
  }

  function settleGoalStartOptions(result: GoalStartOptions | null): void {
    const resolve = goalStartOptionsResolverRef.current;
    goalStartOptionsResolverRef.current = null;
    setGoalStartOptionsOpen(false);
    resolve?.(result);
  }

  function rememberPendingGoalOptions(targetSessionId: string, options: GoalStartOptions): void {
    setPendingGoalOptionsBySessionId((prev) => ({ ...prev, [targetSessionId]: options }));
  }

  function rememberedGoalOptionsForSession(targetSessionId: string, summary: SessionSummary | null | undefined): GoalStartOptions | null {
    const cached = pendingGoalOptionsBySessionId[targetSessionId];
    if (cached) return cached;
    const restored = goalOptionsFromRecord(latestGoalRecord(summary?.goal_state));
    if (restored) {
      rememberPendingGoalOptions(targetSessionId, restored);
    }
    return restored;
  }

  function clearPendingGoalOptions(targetSessionId: string): void {
    setPendingGoalOptionsBySessionId((prev) => {
      if (!(targetSessionId in prev)) return prev;
      const next = { ...prev };
      delete next[targetSessionId];
      return next;
    });
  }

  // 从 File[] 追加附件。共用与 file input / drag-drop / paste
  async function appendFiles(files: File[]): Promise<void> {
    if (files.length === 0) return;
    const requestSessionId = sessionId;
    setComposerError(null);
    const nextAtt: SendMessageAttachment[] = [...composerAttachments];
    const nextPv: { mime: string; dataUrl: string; size: number }[] = [...attachmentPreviews];
    const nextIds = [...composerAttachmentIds];
    let nextTotalBytes = nextAtt.reduce(
      (total, attachment) => total + decodedBase64Size(attachment.data_base64),
      0,
    );
    let unsupportedCount = 0;
    let limitSkippedCount = 0;
    for (const file of files) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (nextAtt.length >= attachmentMaxCount) {
        limitSkippedCount += 1;
        continue;
      }
      const kind = composerAttachmentKind(file.name, file.type);
      if (!modelSupportsAttachmentKind(selectedModel, kind, file.name)) {
        unsupportedCount += 1;
        continue;
      }
      if (file.size > attachmentMaxBytes) {
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        setComposerError(t('composer.attachment.tooLarge', '附件超过 ') + (attachmentMaxBytes / (1024 * 1024)).toFixed(0) + ' MiB');
        continue;
      }
      if (nextTotalBytes + file.size > attachmentMaxTotalBytes) {
        setComposerError(t('composer.error.attachmentTotalLimit', '单条消息附件总大小已达上限'));
        continue;
      }
      try {
        const r = await readFileAsAttachment(file);
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        if (kind === 'image') {
          const edited = await openImageEditor({
            name: file.name,
            mime: r.mime,
            dataUrl: r.dataUrl,
            size: file.size,
          });
          if (!ownsSessionAsyncResult(requestSessionId)) return;
          if (!edited) continue;
          if (edited.size > attachmentMaxBytes) {
            setComposerError(t('composer.attachment.tooLarge', '附件超过 ') + (attachmentMaxBytes / (1024 * 1024)).toFixed(0) + ' MiB');
            continue;
          }
          if (nextTotalBytes + edited.size > attachmentMaxTotalBytes) {
            setComposerError(t('composer.error.attachmentTotalLimit', '单条消息附件总大小已达上限'));
            continue;
          }
          nextAtt.push({ name: edited.name, data_base64: edited.dataBase64 });
          nextPv.push({
            mime: edited.mime,
            dataUrl: edited.dataUrl,
            size: edited.size,
          });
          nextIds.push(nextAttachmentUiId());
          nextTotalBytes += edited.size;
        } else {
          nextAtt.push(r.att);
          nextPv.push({ mime: r.mime, dataUrl: r.dataUrl, size: file.size });
          nextIds.push(nextAttachmentUiId());
          nextTotalBytes += file.size;
        }
      } catch (e: unknown) {
        if (!ownsSessionAsyncResult(requestSessionId)) return;
        setComposerError(t('composer.attachment.readFailed', '附件读取失败：') + (e instanceof Error ? e.message : String(e)));
      }
    }
    if (!ownsSessionAsyncResult(requestSessionId)) return;
    setComposerAttachments(nextAtt);
    setComposerAttachmentIds(nextIds);
    setAttachmentPreviews(nextPv);
    if (limitSkippedCount > 0) {
      setComposerError(`${t('composer.error.attachmentCountLimit', '单条消息附件数量已达上限')} (${attachmentMaxCount})`);
    } else if (unsupportedCount > 0) {
      setComposerError(t('composer.error.attachmentTypeNotSupported', '当前模型不支持所选附件类型'));
    }
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
    if (edited.size > attachmentMaxBytes) {
      setComposerError(t('composer.attachment.tooLarge', '附件超过 ') + (attachmentMaxBytes / (1024 * 1024)).toFixed(0) + ' MiB');
      return;
    }
    const retainedBytes = attachmentPreviews.reduce(
      (total, item, itemIndex) => total + (itemIndex === idx ? 0 : item.size),
      0,
    );
    if (retainedBytes + edited.size > attachmentMaxTotalBytes) {
      setComposerError(t('composer.error.attachmentTotalLimit', '单条消息附件总大小已达上限'));
      return;
    }
    setComposerAttachments((prev) => prev.map((item, i) => (i === idx ? { name: edited.name, data_base64: edited.dataBase64 } : item)));
    setAttachmentPreviews((prev) => prev.map((item, i) => (i === idx ? { mime: edited.mime, dataUrl: edited.dataUrl, size: edited.size } : item)));
  }

  async function handleSend(): Promise<void> {
    if (composerSending) return;
    if (hasModeLockedGoal) {
      const message = t('goal.manualSend.blocked', '目标执行中，请先暂停、恢复或终止当前目标。');
      setComposerError(message);
      showSnackbar(message, { tone: 'error' });
      return;
    }
    if (isRunningPhase(sendPhase)) {
      enqueueCurrentComposerMessage();
      return;
    }
    const text = composerTextRef.current.trim();
    const validation = validateComposerPayload(text, composerAttachments, composerModelKey, composerMode, selectedModel);
    if (validation) {
      setComposerError(validation);
      return;
    }
    let goalOptions: GoalStartOptions | null = null;
    if (session?.mode === 'goal') {
      if (!goalModeAvailable) {
        const message = t('goal.start.unavailable', '当前线程模板暂不支持目标模式');
        setComposerError(message);
        showSnackbar(message, { tone: 'error' });
        return;
      }
      goalOptions = rememberedGoalOptionsForSession(sessionId, session ?? null);
      if (!goalOptions) {
        goalOptions = await openGoalStartOptionsDialog();
        if (!goalOptions) return;
        rememberPendingGoalOptions(sessionId, goalOptions);
      }
    }
    const shouldTrackAutoTitle = shouldWatchAutoTitleAfterSend(text);
    setComposerSending(true);
    setComposerError(null);
    // 标记「这是本地刚刚发起的 send」, 抑制后续 sendPhase running 触发远端冲突 banner
    lastLocalSendAtRef.current = Date.now();
    const requestSessionId = sessionId;
    const editTarget = editingDraftMessage;
    const returnToLatestAfterSend = messageWindowHasNewerMessages();
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
            updateTotalKnown(Math.min(
              totalKnownRef.current,
              windowOffsetRef.current + idx,
            ));
          }
        }
      }
      const res = await sendMessage(requestSessionId, {
        content: text,
        modelKey: composerModelKey,
        mode: composerMode,
        attachments: composerAttachments,
        creationOptions:
          composerMode === 'image' || composerMode === 'video' || composerMode === 'audio'
            ? {
                aspect_ratio: creationOptions.aspectRatio,
                duration_seconds: creationOptions.durationSeconds,
                count: creationOptions.count,
                quality: creationOptions.quality,
                style: creationOptions.style,
                output_format: creationOptions.outputFormat,
                background: creationOptions.background,
                negative_prompt: creationOptions.negativePrompt,
                prompt_enhance: creationOptions.promptEnhance,
                watermark: creationOptions.watermark,
                seed: creationOptions.seed,
                resolution: creationOptions.resolution,
                frame_rate: creationOptions.frameRate,
                num_frames: creationOptions.numFrames,
                mode: creationOptions.mode,
                voice: creationOptions.voice,
                omit_voice: creationOptions.omitVoice,
                speed: creationOptions.speed,
                sample_rate: creationOptions.sampleRate,
                bitrate: creationOptions.bitrate,
                volume: creationOptions.volume,
                pitch: creationOptions.pitch,
              }
            : undefined,
        selectedSkill: selectedSkill
          ? {
              name: selectedSkill.name,
              relative_directory_path: selectedSkill.relative_directory_path,
            }
          : null,
        skippedInstructionIds: Array.from(skippedInstructionIds),
        goalOptions,
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
      setAtMentionFilePickerOpen(false);
      resetSlashTriggerState();
      resetAtMentionTriggerState();
      updateSendPhaseValue(res.send_phase || 'sendingMessage');
      // SSE 通道在 service 端立即推送 user 消息落库；若 SSE 不可用，refresh()
      // 兜底拉一次让 user 消息出现在尾部。
      if (returnToLatestAfterSend) {
        void returnToLatest();
      } else if (!sseLive) {
        void refresh();
      }
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
        setComposerError(body?.message || t('composer.error.send', '发送失败：HTTP ') + String(e.status) + (body?.error ? ` (${body.error})` : ''));
      } else {
        setComposerError(t('composer.error.send', '发送失败：HTTP ') + (e instanceof Error ? e.message : String(e)));
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
    composerLayoutPinnedRef.current =
      autoFollowRef.current &&
      !autoFollowPausedRef.current &&
      messagesAreNearBottom();
    markComposerLayoutTransition();
    setComposerCollapsed((value) => !value);
    // DOM 提交后的 useLayoutEffect 与 ResizeObserver 会在绘制前钉底；
    // 非贴底场景仍走 ResizeObserver 的位置补偿。
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
    const previousSendPhase = sendPhase;
    updateSendPhaseValue('idle');
    try {
      const res = await stopMessage(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      updateSendPhaseValue(res.send_phase || 'idle');
      // 拉一次让 finalize 后的内容立刻可见
      void returnToLatest();
    } catch (e: unknown) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      updateSendPhaseValue(previousSendPhase || 'responding');
      updateLastErrorValue(e instanceof Error ? e.message : String(e));
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) {
        setStopping(false);
      }
    }
  }

  async function handlePauseGoal(): Promise<void> {
    if (!sessionId || goalControlBusy) return;
    setGoalControlBusy('pause');
    const requestSessionId = sessionId;
    try {
      const res = await pauseGoal(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setDetail((prev) => (prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev));
      updateSendPhaseValue('idle');
      void refresh();
      showSnackbar(t('goal.pause.ok', '已暂停目标'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('goal.pause.failed', '暂停目标失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setGoalControlBusy(null);
    }
  }

  async function handleResumeGoal(): Promise<void> {
    if (!sessionId || goalControlBusy || !currentGoal || !goalPaused) return;
    setGoalControlBusy('resume');
    const requestSessionId = sessionId;
    try {
      const res = await resumeGoal(requestSessionId, composerModelKey || detail?.session.last_model_key || undefined);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      updateSendPhaseValue(res.send_phase || 'sendingMessage');
      void refresh();
      showSnackbar(t('goal.resume.ok', '已恢复目标'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('goal.resume.failed', '恢复目标失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setGoalControlBusy(null);
    }
  }

  async function handleTerminateGoal(): Promise<void> {
    if (!sessionId || goalControlBusy) return;
    setGoalControlBusy('terminate');
    const requestSessionId = sessionId;
    try {
      const res = await terminateGoal(requestSessionId);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      setDetail((prev) => (prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev));
      updateSendPhaseValue('idle');
      void refresh();
      showSnackbar(t('goal.terminate.ok', '已终止目标'), { tone: 'success' });
    } catch (e) {
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (handleAuthError(e)) return;
      if (handleSessionGoneError(e)) return;
      const message = e instanceof Error ? e.message : String(e);
      setLastError(message);
      showSnackbar(`${t('goal.terminate.failed', '终止目标失败')}：${message}`, { tone: 'error' });
    } finally {
      if (ownsSessionAsyncResult(requestSessionId)) setGoalControlBusy(null);
    }
  }

  const effectiveLoadingDetail = loadingDetail || Boolean(detail && !detailBelongsToRoute);
  const currentSessionMode: SessionMode = session?.mode === 'plan' || session?.mode === 'goal' ? session.mode : 'chat';
  const canToggleSessionMode =
    !hasModeLockedGoal && sessionModeOptions.length > 1;
  async function applySessionMode(next: SessionMode): Promise<void> {
    if (!sessionId) return;
    if (hasModeLockedGoal) {
      showSnackbar(t('goal.mode.locked', '目标执行期间不能切换会话模式'), { tone: 'error' });
      return;
    }
    if (!sessionModeOptions.includes(next)) {
      return;
    }
    if (next === currentSessionMode) {
      return;
    }
    const requestSessionId = sessionId;
    let pendingGoalOptions: GoalStartOptions | null = null;
    if (next === 'goal') {
      if (!goalModeAvailable) {
        const message = t('goal.start.unavailable', '当前线程模板暂不支持目标模式');
        setComposerError(message);
        showSnackbar(message, { tone: 'error' });
        return;
      }
      pendingGoalOptions = await openGoalStartOptionsDialog();
      if (!pendingGoalOptions) return;
      if (!ownsSessionAsyncResult(requestSessionId)) return;
    }
    try {
      const res = await updateSessionMode(requestSessionId, next);
      if (!ownsSessionAsyncResult(requestSessionId)) return;
      if (next === 'goal' && pendingGoalOptions) {
        rememberPendingGoalOptions(requestSessionId, pendingGoalOptions);
      } else {
        clearPendingGoalOptions(requestSessionId);
      }
      setDetail((prev) => (prev ? { ...prev, session: mergeSessionSummary(prev.session, res.session) } : prev));
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
          ? {
              ...fresh,
              session: mergeSessionSummary(prev.session, fresh.session),
            }
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
  const remainingNewer = remainingNewerMessageCount(
    totalKnown,
    windowOffset,
    messages.length,
  );
  const sessionCapsules = useMemo<SessionToolbarCapsule[]>(() => {
    if (!session) return [];
    const templateLabel = session.template_name || session.template_id;
    const templateVersion = session.template_internal_version != null ? ` · v${session.template_internal_version}` : '';
    const lastPromptMetadata = recordFromUnknown(session.last_prompt_metadata);
    const runtimeNotices = stringListFromUnknown(lastPromptMetadata['runtime_tool_catalog_notices']);
    const lazyLoadingCapsule = mcpLazyLoadingCapsule(runtimeNotices);
    const tokenStats = recordFromUnknown(session.statistics);
    const sessPrompt = readStatNumber(tokenStats['total_prompt_tokens'], session.total_prompt_tokens);
    const cacheHitSummary = buildSessionCacheHitDisplay(session, tokenStats);
    const sessCacheRead = cacheHitSummary.cacheReadTokens;
    const claudeStyle = usesClaudeStyleCacheMath(session.last_used_model_protocol);
    const cacheHitPercent = cacheHitSummary.cacheHitRatio;
    const cacheHitBase = claudeStyle ? sessPrompt + sessCacheRead : sessPrompt;
    const contextWindowUsage = parseContextWindowUsage(session);
    const tokensBadge =
      cacheHitSummary.hasCacheHitMetrics
        ? {
            text: `${cacheHitPercent}%`,
            title: `${t('topbar.tokens.cacheSavings', '缓存命中率')} · ${sessCacheRead.toLocaleString()} / ${cacheHitBase.toLocaleString()}`,
            tone: 'primary' as const,
          }
        : undefined;
    const capsules: SessionToolbarCapsule[] = [];
    const tokensCapsule: SessionToolbarCapsule = {
      key: 'tokens',
      icon: 'tokens',
      label: '',
      title: `${t('topbar.tokens', 'Token 统计')} · ${t('tokenPopup.context.window', '上下文窗口')} ${contextWindowUsage.percent}%`,
      badge: tokensBadge,
      progress: {
        ratio: contextWindowUsage.ratio,
        title: `${t('tokenPopup.context.window', '上下文窗口')} ${contextWindowUsage.percent}%`,
      },
      onClick: () => {
        setTokenStatsOpen(true);
        void hydrateCacheStatisticsOnDemand();
      },
    };
    const goal = latestGoalRecord(session.goal_state);
    if (goal) {
      const active = isActiveGoalStatus(goal.status);
      capsules.push({
        key: 'goal',
        icon: 'goal',
        label: `${t('goal.capsule.label', '目标')} · ${goalProgressLabel(goal)}`,
        title: goal.objective,
        tone: active ? (goal.status === 'paused' ? 'warning' : 'success') : 'muted',
        onClick: () => setGoalDetailsOpen(true),
      });
    }
    if (lazyLoadingCapsule) capsules.push(lazyLoadingCapsule);
    if (runtimeNotices.length > 0) {
      capsules.push({
        key: 'runtime-notices',
        icon: 'runtime',
        label: t('topbar.runtimeNotices', '{count} 项运行时 Notice').replace('{count}', String(runtimeNotices.length)),
        title: runtimeNotices.join('\n'),
      });
    }
    capsules.push({
      key: 'template',
      icon: 'template',
      label: `${templateLabel}${templateVersion}`,
      title: `${t('sessions.template.label', '模板：')}${templateLabel}${templateVersion}`,
    });
    if (session.template_id === 'hermes_talker') {
      capsules.push({
        key: 'hermes-warning',
        icon: 'runtime',
        label: t('topbar.hermesSelfLearningNotice', 'Hermes 自学习状态'),
        title: t('topbar.hermesSelfLearningNotice.title', '可在 App 定时任务面板检查 Hermes Talker 自学习开关。'),
      });
    }
    capsules.push({
      key: 'metadata',
      icon: 'metadata',
      label: t('topbar.metadata', '会话元数据'),
      title: `${totalKnown} ${t('sessions.messageUnit', '条消息')} · ${session.tool_message_count ?? 0} tool`,
      onClick: () => void openSessionMetadataDialog(),
    });
    // TopBar 节流指示胶囊：绿色 = 字符与卡片限速都开着；
    // 灰色 = 任一被关闭或当前生效值为 0；duration_expired 时也变灰，
    // 表示节流时长已耗尽、剩余响应正按 AI 真实速率追加。
    // 可见性闸：只有会话曾/正节流（hasOverride / wasInitiallyThrottled
    // 或 chars+cards > 0）才显示胶囊；从未节流过的会话不放胶囊。
    if (streamThrottle) {
      const enabledOff = streamThrottle.enabled === false;
      const rateOff = (streamThrottle.chars ?? 0) <= 0 || (streamThrottle.cards ?? 0) <= 0;
      const disabled = enabledOff || rateOff;
      const expired = streamThrottle.durationExpired === true;
      const showAsGray = disabled || expired;
      const ratesActive = (streamThrottle.chars ?? 0) > 0 && (streamThrottle.cards ?? 0) > 0;
      const pillVisible = streamThrottle.hasOverride || streamThrottle.wasInitiallyThrottled || ratesActive;
      if (pillVisible) {
        const label = disabled ? t('topbar.throttle.off', '节流·关') : expired ? t('topbar.throttle.expired', '节流·已耗尽') : t('topbar.throttle.value', '字{chars}·卡{cards}').replace('{chars}', String(streamThrottle.chars)).replace('{cards}', String(streamThrottle.cards));
        capsules.push({
          key: 'stream-throttle',
          icon: 'throttle',
          label,
          title: disabled ? t('topbar.throttle.off.title', '节流已关闭：AI 输出将以真实速率全速渲染。') : expired ? t('topbar.throttle.expired.title', '节流时长已耗尽：剩余流式响应将按 AI 真实速率追加渲染。') : t('topbar.throttle.on.title', '点击调整本会话节流速率（重启后仍保留）'),
          tone: showAsGray ? 'muted' : 'success',
          onClick: () => setThrottleDialogOpen(true),
        });
      }
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
    if (session.template_id === 'web_reverse_expert') {
      const meta = (session.metadata ?? {}) as Record<string, unknown>;
      const cfg = meta['web_reverse_config'] as Record<string, unknown> | undefined;
      const port = cfg?.['cdp_port'];
      capsules.push({
        key: 'web-reverse-debug',
        icon: 'debug',
        label: typeof port === 'number' ? `CDP :${port}` : t('topbar.webReverseDebug', 'CDP 调试'),
        title: t('topbar.webReverseDebug.title', '查看 Web 逆向调试面板'),
        onClick: () => setWebReverseDashboardOpen(true),
      });
    }
    if (session.template_id === 'android_reverse_expert') {
      const meta = (session.metadata ?? {}) as Record<string, unknown>;
      const cfg = recordFromUnknown(meta['android_reverse_config']);
      const runtime = recordFromUnknown(meta['android_reverse_runtime']);
      const connected = recordFromUnknown(runtime['connected_device']);
      const serial = stringFromUnknown(connected['serial']) || stringFromUnknown(cfg['device_serial']);
      const running = booleanFromUnknown(runtime['is_running']);
      const state = stringFromUnknown(runtime['state']);
      const processCount = nonNegativeIntegerFromUnknown(runtime['process_count']);
      const visibleDeviceCount = arrayFromUnknown(runtime['visible_devices']).length;
      const deviceLabel = serial || (visibleDeviceCount > 0 ? `${visibleDeviceCount} 台设备` : running ? '无设备' : state === 'stopped' ? '已停止' : '待连接');
      const processLabel = ` · ${processCount} 进程`;
      capsules.push({
        key: 'android-reverse-debug',
        icon: 'debug',
        label: `ADB ${deviceLabel}${processLabel}`,
        title: `${t('topbar.androidReverseDebug.title', '查看 Android 逆向调试面板')} · ${deviceLabel}${processLabel}`,
        onClick: () => setAndroidReverseDashboardOpen(true),
      });
    }
    capsules.push(tokensCapsule);
    return capsules;
  }, [session, totalKnown, sessionId, streamThrottle]);
  const pull = usePullToRefresh(mainRef, {
    enabled:
      !effectiveLoadingDetail &&
      !loadingOlder &&
      !olderRenderSettling,
    onRefresh: async () => {
      if (remainingOlder > 0) {
        await loadOlder();
      } else if (remainingNewer > 0) {
        await returnToLatest();
      } else {
        await refresh();
      }
    },
    activationDistance: 84,
  });

  // 注意：服务端按 created_at 升序返回（store loadMessages 默认升序），
  // 直接渲染即是「上旧下新」。如果出现倒序问题，派生视图会做一次排序兜底。
  const sortedMessages = messageWindowView.ordered;
  const transcriptPreparing =
    !effectiveLoadingDetail &&
    !error &&
    sortedMessages.length > 0 &&
    transcriptReadySessionId !== sessionId;
  const handleTranscriptInitialLayoutSettled = useCallback(() => {
    if (sessionIdRef.current !== sessionId) return;
    setTranscriptReadySessionId((current) => current === sessionId ? current : sessionId);
  }, [sessionId]);
  const webMessageFeatureConfig = auth.meta?.service;
  const messageContentSettings = auth.meta?.message_content_settings;
  const readAloudEnabled =
    webMessageFeatureConfig?.read_aloud_enabled !== false &&
    messageContentSettings?.tts_enabled === true;
  const translationEnabled =
    webMessageFeatureConfig?.translation_enabled !== false &&
    messageContentSettings?.translation_enabled === true;
  const translationSettingsFingerprint =
    messageContentSettings?.translation_settings_fingerprint ?? '';
  const translationModelSettingsFingerprint =
    messageContentSettings?.translation_model_settings_fingerprint ?? '';
  const translationFallbackModelKey =
    detail?.session.last_model_key || meta?.active_model_key || '';
  const translationRequestFingerprint = [
    translationSettingsFingerprint,
    translationModelSettingsFingerprint,
    translationFallbackModelKey,
  ].join('|');
  const textActionContentFormat = normalizeMetaMessageContentFormat(
    messageContentSettings?.message_content_format,
  );
  const feedbackEnabled = webMessageFeatureConfig?.feedback_enabled !== false;
  const regenerationEnabled = webMessageFeatureConfig?.regeneration_enabled !== false;

  useEffect(() => {
    if (readAloudEnabled || !ttsPlayback.playing) return;
    void stopMessageTtsPlayback()
      .then((result) => applyTtsPlayback(result.playback))
      .catch(() => setTtsPlayback(EMPTY_TTS_PLAYBACK));
  }, [applyTtsPlayback, readAloudEnabled, ttsPlayback.playing]);

  const visibleSortedMessages = sortedMessages;
  const associatedKnowledgeBaseByMessageId = useMemo(
    () => stabilizeAssociatedKnowledgeBaseMetadataByMessageId(
      buildAssociatedKnowledgeBaseMetadataByMessageId(
        visibleSortedMessages,
        associatedKnowledgeBaseBuildCacheRef,
      ),
      associatedKnowledgeBaseCacheRef.current,
    ),
    [visibleSortedMessages],
  );

  const returnToLatest = async () => {
    setAutoFollowEnabled(true);
    setAutoFollowPausedValue(false);
    isNearBottomRef.current = true;
    await refresh({ replaceWithLatest: true });
  };

  const responseRunning = isRunningPhase(sendPhase);
  const stableResponseRunning = useDelayedFalse(
    responseRunning,
    STREAMING_TURN_IDLE_DEBOUNCE_MS,
  );
  const latestStreamingTextMessageId = messageWindowView.latestStreamingTextMessageId;
  function renderSessionMessage(m: SessionMessage): ComponentChildren {
    const translation = messageTranslations[m.id];
    const translationMatches =
      translation?.source === (m.content ?? '') &&
      translation.settingsFingerprint === translationRequestFingerprint;
    const associatedKnowledgeBaseMetadata = associatedKnowledgeBaseByMessageId.get(m.id) ?? null;
    const streaming = m.id === latestStreamingTextMessageId || messageMetadataStreaming(m);
    return (
      <MessageCard
        message={m}
        active={activeMessageId === m.id}
        streaming={streaming}
        turnActive={stableResponseRunning}
        sessionId={sessionId}
        readAloudEnabled={readAloudEnabled}
        readAloudPlaying={ttsPlayback.playing && ttsPlayback.messageId === m.id}
        textActionContentFormat={textActionContentFormat}
        translationEnabled={translationEnabled}
        feedbackEnabled={feedbackEnabled}
        regenerationEnabled={regenerationEnabled}
        translatedContent={translationMatches ? translation.text : null}
        translationLoading={translationMatches && translation.loading}
        translationVisible={translationMatches && translation.visible}
        associatedKnowledgeBaseMetadata={associatedKnowledgeBaseMetadata}
        feedbackBusy={feedbackBusyMessageIds.has(m.id)}
        regenerating={regeneratingMessageIds.has(m.id)}
        onActiveChange={handleMessageActiveChange}
        onCopy={handleCopyMessage}
        onDelete={handleDeleteMessage}
        onDeleteAfter={handleDeleteMessageCascade}
        onEdit={m.role === 'user' ? handleEditMessage : undefined}
        onAudit={handleAuditMessage}
        onFork={handleForkMessage}
        onToggleReadAloud={handleToggleMessageTts}
        onToggleTranslation={handleToggleMessageTranslation}
        onSetFeedback={handleSetMessageFeedback}
        onRegenerate={handleRegenerateMessage}
      />
    );
  }
  const loadTitleSourceMessages = useCallback(async (options: { signal: AbortSignal }) => {
    if (!sessionId) return [];
    const res = await listSessionTitleSourceMessages(sessionId, { signal: options.signal });
    return res.items;
  }, [sessionId]);

  if (!sessionId) {
    return (
      <main class="min-h-screen flex items-center justify-center">
        <p class="text-sm oh-text-error">
          {t('detail.missingId', '缺少会话 ID')}
        </p>
      </main>
    );
  }

  const subtitle = session ? [session.template_name || session.template_id, `${totalKnown} ${t('sessions.messageUnit', '条消息')}`, session.total_tokens != null ? `${session.total_tokens.toLocaleString()} tokens` : '', session.tool_message_count ? `${session.tool_message_count} tool` : '', session.compression_point_count ? `${session.compression_point_count} compress` : ''].filter(Boolean).join(' · ') : t('detail.loading', '加载会话中…');
  const composerSendDisabled = composerSending || allowedModels.length === 0 || stopping || hasModeLockedGoal;
  const isMachineExpertSession = session?.template_id === 'machine_expert';

  return (
    <main
      ref={pageRootRef}
      class={`oh-session-detail-page ${PAGE_SHELL_CLASS} h-screen overflow-hidden flex flex-col`}
      style={{ background: 'var(--m3-surface)' }}
    >
      <PullIndicator pulled={pull.pulled} refreshing={pull.refreshing} willRelease={pull.willRelease} activationDistance={84} />
      <div
        class={`${SESSION_DETAIL_SHELL_CLASS} w-full flex-1 min-h-0 ${
          isMachineExpertSession ? 'oh-machine-workbench is-machine-expert' : 'flex flex-col'
        }`}
      >
        {isMachineExpertSession ? <MachineTerminalPanel sessionId={sessionId} /> : null}
        <div class={isMachineExpertSession ? 'oh-machine-chat-column' : 'oh-session-chat-column'}>
        <SessionTopBar
          title={session?.title || t('sessions.untitled', '未命名会话')}
          subtitle={subtitle}
          titleGenerating={Boolean(session && !session.is_title_manually_edited && !session.auto_title_acquired && !session.auto_title_generated_at && messageWindowView.hasUserMessage)}
          onBack={() => location.route('/threads')}
          onRename={async (next) => {
            const requestSessionId = sessionId;
            try {
              const res = await renameSession(requestSessionId, next);
              if (!ownsSessionAsyncResult(requestSessionId)) return false;
              setDetail((prev) =>
                prev
                  ? {
                      ...prev,
                      session: mergeSessionSummary(prev.session, res.session),
                    }
                  : prev,
              );
              showSnackbar(t('topbar.rename.ok', '已重命名会话'), {
                tone: 'success',
              });
              return true;
            } catch (e) {
              if (!ownsSessionAsyncResult(requestSessionId)) return false;
              if (handleAuthError(e)) return false;
              if (handleSessionGoneError(e)) return false;
              const message = e instanceof Error ? e.message : String(e);
              setLastError(message);
              showSnackbar(`${t('topbar.rename.failed', '重命名失败')}：${message}`, { tone: 'error' });
              return false;
            }
          }}
          onDelete={async () => {
            setPendingSessionDelete(true);
          }}
          onExport={async () => {
            const requestSessionId = sessionId;
            try {
              showSnackbar(t('topbar.export.started', '正在导出会话数据…'));
              const result = await exportSessionDownload(requestSessionId, session?.title || requestSessionId);
              if (!ownsSessionAsyncResult(requestSessionId)) return;
              showSnackbar(`${t('topbar.export.ok', '已保存导出文件')}：${result.filename}`, { tone: 'success' });
            } catch (e) {
              if (!ownsSessionAsyncResult(requestSessionId)) return;
              if (isAbortError(e)) return;
              if (handleAuthError(e)) return;
              if (handleSessionGoneError(e)) return;
              const message = e instanceof Error && e.message === EXPORT_SESSION_TIMEOUT_ERROR ? t('topbar.export.timeout', '导出会话超时，请稍后重试') : e instanceof Error ? e.message : String(e);
              setLastError(message);
              showSnackbar(`${t('topbar.export.failed', '导出会话失败')}：${message}`, { tone: 'error' });
            }
          }}
          onGenerateTitle={() => setShowTitleSummary(true)}
          onOpenTrajectory={() => setShowTrajectory(true)}
          onToggleFullscreen={() => void browserFullscreen.toggle()}
          fullscreenActive={browserFullscreen.active}
          sessionId={sessionId}
          capsules={sessionCapsules}
          trailing={
            <button
              type="button"
              onClick={() => void (remainingNewer > 0 ? returnToLatest() : refresh())}
              disabled={refreshing || effectiveLoadingDetail}
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

        {lastError ? <ErrorBanner message={lastError} onRetry={() => void refresh()} onDismiss={() => setLastError(null)} /> : null}

        {remoteRunning ? (
          <div class="oh-remote-running-banner rounded-md px-3 py-2 text-xs flex items-start gap-2">
            <span class="oh-remote-running-text">{t('detail.remoteRunning', '另一处客户端已发送消息，AI 正在生成回复中。如本端正在编辑草稿，建议等回复完成后再发送，避免消息顺序混乱。')}</span>
          </div>
        ) : null}

        {/* 主区：只有这块滚动，顶部 TopBar / 底部 Composer 固定在视口内。 */}
        <div class="oh-session-messages-frame relative flex-1 min-h-0">
          <section
            ref={mainRef}
            class="oh-session-messages absolute inset-0 overflow-y-auto pr-1 pb-3"
            data-transcript-preparing={transcriptPreparing ? 'true' : 'false'}
            aria-busy={effectiveLoadingDetail || transcriptPreparing}
          >
            <div
              ref={messagesContentRef}
              class={`oh-session-message-content oh-session-transcript-content${transcriptPreparing ? ' is-preparing' : ''}`}
            >
            {effectiveLoadingDetail ? (
              <div class="oh-session-state-card is-loading">
                <span class="oh-session-state-icon oh-spin" aria-hidden>
                  <ComposerIcon name="refresh" size={18} />
                </span>
                <span>{t('detail.loading', '加载会话中…')}</span>
              </div>
            ) : error ? (
              <div class="oh-session-state-card is-error">
                <span class="oh-session-state-icon" aria-hidden>
                  <ComposerIcon name="refresh" size={18} />
                </span>
                <span>{error}</span>
                <button type="button" onClick={loadDetail} class="oh-session-state-action oh-tap-press">
                  {t('sessions.retry', '重试')}
                </button>
              </div>
            ) : (
              <>
                {/* 加载更早 */}
                {remainingOlder > 0 ? (
                  <div class="text-center mb-3">
                    <button type="button" onClick={loadOlder} disabled={loadingOlder || olderRenderSettling} class="oh-session-load-older-button oh-tap-press disabled:opacity-50">
                      <span class={loadingOlder || olderRenderSettling ? 'oh-spin' : undefined} aria-hidden>
                        <ComposerIcon name="refresh" size={13} />
                      </span>
                      {olderRenderSettling
                        ? t('detail.preparingEarlier', '正在准备更早消息…')
                        : loadingOlder
                        ? t('detail.loadingOlder', '加载中…')
                        : t('detail.loadOlder', '加载更早 ') + `(${remainingOlder})`}
                    </button>
                  </div>
                ) : null}

                {sortedMessages.length === 0 ? (
                  <div class="oh-session-empty-plain" role="status">
                    <span class="oh-session-empty-icon" aria-hidden>
                      <ComposerIcon name="chat" size={20} />
                    </span>
                    <span>{t('detail.empty', '该会话尚无消息。')}</span>
                  </div>
                ) : (
                  <>
                    {session ? <PlanTimeline session={session} modelKey={composerModelKey} /> : null}
                    <VirtualMessageList
                      key={sessionId}
                      messages={visibleSortedMessages}
                      membershipKey={messageMembershipKey}
                      scrollContainerRef={mainRef}
                      revealTarget={transcriptRevealTarget}
                      highlightedMessageId={highlightedMessageId}
                      onInitialLayoutSettled={handleTranscriptInitialLayoutSettled}
                      renderMessage={renderSessionMessage}
                    />
                    {remainingNewer > 0 ? (
                      <div class="text-center mt-3">
                        <button
                          type="button"
                          onClick={() => void returnToLatest()}
                          disabled={refreshing}
                          class="oh-session-load-older-button oh-tap-press disabled:opacity-50"
                        >
                          <ComposerIcon name="follow" size={13} />
                          {t('detail.returnToLatest', '回到最新消息') + ` (${remainingNewer})`}
                        </button>
                      </div>
                    ) : null}
                    <MediaGeneratingPlaceholderTransition
                      mode={responseRunning ? messageWindowView.lastCreationModeAwaitingAssistant : null}
                      className="mt-3"
                    />
                  </>
                )}
              </>
            )}
            </div>
          </section>
          {!effectiveLoadingDetail && !error && sortedMessages.length > 0 ? (
            <div
              class={`oh-session-prepare-overlay${transcriptPreparing ? ' is-visible' : ''}`}
              role="status"
              aria-hidden={!transcriptPreparing}
            >
              <span class="oh-session-prepare-icon oh-spin" aria-hidden>
                <ComposerIcon name="refresh" size={19} />
              </span>
              <span>{t('detail.preparingMessages', '正在准备消息…')}</span>
            </div>
          ) : null}
        </div>

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
          <div class="oh-composer-toolbar" data-collapsed={composerCollapsed ? 'true' : 'false'}>
            {!composerCollapsed ? (
              <>
                {sessionModeOptions.length > 1 ? (
                  <PopMenu
                    align="left"
                    width={196}
                    wrapperClassName="oh-session-mode-menu"
                    items={sessionModeOptions.map((mode) => {
                      const active = mode === currentSessionMode;
                      const label = sessionModeLabel(mode);
                      return {
                        key: mode,
                        label: active ? `${label} · ${t('common.current', '当前')}` : label,
                        disabled: composerSending || active || !canToggleSessionMode,
                        selected: active,
                        onClick: () => void applySessionMode(mode),
                      };
                    })}
                    trigger={({ open, toggle }) => (
                      <button type="button" onClick={toggle} disabled={composerSending || !canToggleSessionMode} class={`oh-session-mode-button oh-composer-control oh-tap-press ${currentSessionMode === 'goal' ? 'is-goal' : currentSessionMode === 'plan' ? 'is-plan' : 'is-chat'}`} aria-expanded={open} aria-pressed={currentSessionMode !== 'chat'} title={hasModeLockedGoal ? t('goal.mode.locked', '目标执行期间不能切换会话模式') : sessionModeLabel(currentSessionMode)}>
                        <span key={`session-mode-icon-${currentSessionMode}`} class="oh-composer-control-icon oh-session-mode-icon oh-soft-replace">
                          <ComposerIcon name={sessionModeIconName(currentSessionMode)} />
                        </span>
                        <span key={`session-mode-label-${currentSessionMode}`} class="oh-session-mode-label oh-soft-replace">
                          {sessionModeLabel(currentSessionMode)}
                        </span>
                        <span class={`oh-composer-caret ${open ? 'is-open' : ''}`}>
                          <ComposerIcon name="chevronDown" size={16} />
                        </span>
                      </button>
                    )}
                  />
                ) : null}

                <span class="oh-composer-model-menu" title={modelSelectionLocked ? modelSelectionLockReason : undefined}>
                  <button type="button" onClick={() => setShowComposerModelPicker(true)} disabled={composerSending || modelSelectionLocked || allowedModels.length === 0} class="oh-composer-control oh-composer-model-control oh-tap-press disabled:opacity-50 min-w-0" title={modelSelectionLocked ? undefined : selectedModelName || t('composer.model', '模型')}>
                    <span class="truncate">
                      {selectedModelName || t('composer.modelEmpty', '主控制台未配置模型')}
                    </span>
                  </button>
                </span>

                <ReasoningEffortControl
                  model={selectedModel}
                  disabled={composerSending || modelSelectionLocked}
                  disabledReason={modelSelectionLocked ? modelSelectionLockReason : undefined}
                  saving={reasoningEffortSaving}
                  onSelect={changeComposerReasoningEffort}
                />

                <PopMenu
                  align="left"
                  width={220}
                  wrapperClassName="oh-composer-mode-menu"
                  items={composerModeOptions.map((mode) => {
                    const serviceAllowed = allowedModes.includes(mode);
                    const modelAllowed = modelSupportsMode(selectedModel, mode);
                    const active = mode === composerMode;
                    const label = composerModeLabel(mode);
                    const suffix = !serviceAllowed ? t('composer.mode.disabled.service', '（未启用）') : !modelAllowed ? t('composer.mode.disabled.model', '（当前模型不支持）') : '';
                    return {
                      key: mode,
                      label: active ? `${label} · ${t('common.current', '当前')}` : `${label}${suffix}`,
                      disabled: composerSending || active || !serviceAllowed || !modelAllowed,
                      selected: active,
                      onClick: () => {
                        setComposerMode(mode);
                        // 选择多媒体模式时弹出生成选项弹窗
                        if (mode === 'image' || mode === 'video' || mode === 'audio') {
                          setShowCreationOptions(mode as 'image' | 'video' | 'audio');
                        }
                      },
                    };
                  })}
                  trigger={({ open, toggle }) => (
                    <button type="button" onClick={toggle} disabled={composerSending} class="oh-composer-control oh-composer-mode-control oh-tap-press is-tonal disabled:opacity-50" aria-expanded={open} title={t('composer.mode', '模式')}>
                      <span key={`composer-mode-icon-${composerMode}`} class="oh-composer-control-icon oh-soft-replace">
                        <ComposerIcon name={composerModeIconName(composerMode)} />
                      </span>
                      <span key={`composer-mode-label-${composerMode}`} class="oh-soft-replace">
                        {composerModeLabel(composerMode)}
                      </span>
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
                  <span>{session?.full_access_permission === true ? t('topbar.perm.full', '完全访问权限') : t('topbar.perm.default', '默认权限')}</span>
                </button>
              </>
            ) : null}

            <button type="button" onClick={toggleComposerCollapsed} class={`oh-composer-icon-control oh-composer-collapse-control oh-tap-press ${composerCollapsed ? '' : 'ml-auto'}`} title={composerCollapsed ? t('composer.expand', '展开输入区') : t('composer.collapse', '收起输入区')} aria-label={composerCollapsed ? t('composer.expand', '展开输入区') : t('composer.collapse', '收起输入区')} aria-expanded={!composerCollapsed}>
              <ComposerIcon name={composerCollapsed ? 'chevronUp' : 'chevronDown'} />
            </button>
          </div>

          <div class="oh-composer-body" data-collapsed={composerCollapsed ? 'true' : 'false'} aria-hidden={composerCollapsed ? 'true' : undefined} {...(composerCollapsed ? { inert: true } : {})}>
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
                  onClick={() =>
                    runAfterComposerChipExit('edit-draft', () => {
                      editingDraftMessageRef.current = null;
                      setEditingDraftMessage(null);
                    })
                  }
                  disabled={composerSending || composerChipIsExiting('edit-draft')}
                  title={t('composer.edit.cancel', '取消编辑历史消息')}
                >
                  <span class="oh-composer-pill-icon">
                    <ComposerIcon name="edit" size={16} />
                  </span>
                  <span class="truncate max-w-[180px]">{t('composer.edit.active', '正在编辑历史消息')}</span>
                  <span class="oh-composer-pill-icon">
                    <ComposerIcon name="close" size={15} />
                  </span>
                </button>
              ) : null}
              <span key={`mode-${composerMode}`} class="oh-composer-pill oh-composer-mode-pill oh-composer-chip-motion">
                <span class="oh-composer-pill-icon">
                  <ComposerIcon name={composerModeIconName(composerMode)} size={16} />
                </span>
                {composerModeLabel(composerMode)}
              </span>
              {selectedSkill ? (
                <span class={`oh-composer-pill oh-composer-skill-pill oh-composer-chip-motion ${composerChipIsExiting(`skill-${selectedSkill.relative_directory_path}-${selectedSkill.name}`) ? 'is-exiting' : ''}`} title={selectedSkill.name}>
                  <span class="oh-composer-pill-icon">{selectedSkill.emoji_icon || <ComposerIcon name="spark" size={16} />}</span>
                  <span class="truncate max-w-[180px]">{selectedSkill.name}</span>
                  <button type="button" class="oh-composer-pill-close oh-tap-press" onClick={() => runAfterComposerChipExit(`skill-${selectedSkill.relative_directory_path}-${selectedSkill.name}`, () => setSelectedSkill(null))} disabled={composerSending || composerChipIsExiting(`skill-${selectedSkill.relative_directory_path}-${selectedSkill.name}`)} aria-label={t('composer.skill.clear', '移除已选择技能')} title={t('composer.skill.clear', '移除已选择技能')}>
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
                    <li key={chipKey} class={`oh-composer-attachment-chip oh-composer-chip-motion ${composerChipIsExiting(chipKey) ? 'is-exiting' : ''} ${isImage ? 'is-image' : ''}`}>
                      {isImage && pv ? (
                        <button type="button" class="oh-composer-image-thumb" onClick={() => void editAttachmentAt(i)} disabled={composerSending} title={t('imageEditor.title', '编辑图片')}>
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
                      ) : null}
                      <button type="button" onClick={() => requestRemoveAttachmentAt(i)} disabled={composerSending || composerChipIsExiting(chipKey)} class="oh-composer-chip-close" aria-label={t('composer.attachment.remove', '移除附件')}>
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
                    const isGuidingQueued = queueGuidanceDispatchingId === item.id;
                    const queueGuidanceBusy = queueGuidanceDispatchingId !== null;
                    const queueActionsLocked = queueGuidanceBusy || isDispatchingQueued;
                    const queueKey = `${item.id}-${queuedListMotionGeneration}`;
                    return (
                      <li key={queueKey} class={`oh-queued-message-row ${queuedMessageIsExiting(item.id) ? 'is-exiting' : ''} ${isDispatchingQueued ? 'is-dispatching' : ''} ${isGuidingQueued ? 'is-guiding' : ''}`}>
                        <div class="oh-queued-message-index">{index + 1}</div>
                        <div class="oh-queued-message-main">
                          {isEditingQueued ? (
                            <div class="oh-queued-message-edit">
                              <textarea value={queuedEditText} onInput={(event) => setQueuedEditText(event.currentTarget.value)} rows={3} aria-label={t('composer.queue.editLabel', '编辑等待消息')} />
                              <div class="oh-queued-message-edit-actions">
                                <button type="button" class="oh-tap-press oh-queued-message-mini-action" onClick={() => saveQueuedMessageEdit(item.id)} disabled={!queuedEditText.trim()}>
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
                              <p class="oh-queued-message-text">{item.content || t('composer.queue.attachmentOnly', '仅附件消息')}</p>
                              <div class="oh-queued-message-meta">
                                <span>{composerModeLabel(item.mode)}</span>
                                <span>{item.modelLabel || item.modelKey}</span>
                                {item.selectedSkill ? <span>{item.skillLabel ?? item.selectedSkill.name}</span> : null}
                                {item.attachments.length > 0 ? (
                                  <span>
                                    {item.attachments.length} {t('composer.attachment.unit', '个附件')}
                                  </span>
                                ) : null}
                                {isDispatchingQueued ? <span>{t('composer.queue.sending', '正在自动发送')}</span> : null}
                                {isGuidingQueued ? <span>{t('composer.queue.guiding', '正在指导发送')}</span> : null}
                              </div>
                            </>
                          )}
                        </div>
                        <div class="oh-queued-message-actions">
                          <button type="button" class="oh-tap-press oh-queued-message-icon-action" onClick={() => moveQueuedMessage(index, index - 1)} disabled={index === 0 || queueActionsLocked} title={t('composer.queue.moveUp', '上移')} aria-label={t('composer.queue.moveUp', '上移')}>
                            <ComposerIcon name="chevronUp" size={15} />
                          </button>
                          <button type="button" class="oh-tap-press oh-queued-message-icon-action" onClick={() => moveQueuedMessage(index, index + 1)} disabled={index >= queuedComposerMessages.length - 1 || queueActionsLocked} title={t('composer.queue.moveDown', '下移')} aria-label={t('composer.queue.moveDown', '下移')}>
                            <ComposerIcon name="chevronDown" size={15} />
                          </button>
                          <button type="button" class="oh-tap-press oh-queued-message-icon-action" onClick={() => startEditQueuedMessage(item)} disabled={queueActionsLocked} title={t('composer.queue.edit', '编辑')} aria-label={t('composer.queue.edit', '编辑')}>
                            <ComposerIcon name="edit" size={15} />
                          </button>
                          <button type="button" class="oh-tap-press oh-queued-message-icon-action is-guide" onClick={() => void guideQueuedMessage(item.id)} disabled={queueGuidanceBusy || queueDispatchingId !== null || composerSending || stopping} title={t('composer.queue.guide', '指导')} aria-label={t('composer.queue.guide', '指导')}>
                            <span class={isGuidingQueued ? 'oh-spin' : undefined}>
                              <ComposerIcon name={isGuidingQueued ? 'refresh' : 'guide'} size={15} />
                            </span>
                          </button>
                          <button type="button" class="oh-tap-press oh-queued-message-icon-action is-danger" onClick={() => removeQueuedMessage(item.id)} disabled={queueActionsLocked} title={t('composer.queue.remove', '删除')} aria-label={t('composer.queue.remove', '删除')}>
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
                if (Array.from(e.dataTransfer?.types ?? []).includes('Files')) {
                  e.preventDefault();
                  if (attachmentsAllowed && !dragOver) setDragOver(true);
                }
              }}
              onDragLeave={(e) => {
                if (e.currentTarget === e.target) setDragOver(false);
              }}
              onDrop={(e) => {
                const files = Array.from(e.dataTransfer?.files ?? []);
                if (files.length === 0) return;
                e.preventDefault();
                setDragOver(false);
                if (!attachmentsAllowed) {
                  setComposerError(t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件'));
                  return;
                }
                void appendFiles(files);
              }}
            >
                {atMentionFilePickerVisible && atMentionFilePickerAnchor ? (
                  <OverlayPortal>
                    <div
                      ref={atMentionFilePickerOverlayRef}
                      class={`oh-file-picker oh-skill-picker ${atMentionFilePickerClosing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'}`}
                      role="listbox"
                      style={{
                        position: 'fixed',
                        bottom: `${atMentionFilePickerAnchor.bottomGap}px`,
                        left: `${atMentionFilePickerAnchor.left}px`,
                        width: `${atMentionFilePickerAnchor.width}px`,
                        maxHeight: `${atMentionFilePickerAnchor.maxHeight}px`,
                        zIndex: DIALOG_OVERLAY_LOW_Z_INDEX,
                      }}
                    >
                      <div class="oh-skill-picker-title">
                        <span aria-hidden>
                          <ComposerIcon name="attachment" size={16} />
                        </span>
                        {t('composer.file.pick', '选择文件')}
                      </div>
                      {!attachmentsAllowed ? (
                        <div class="oh-skill-picker-empty">{t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件')}</div>
                      ) : (
                        <ul class="oh-skill-picker-list">
                          <li>
                            <button
                              type="button"
                              role="option"
                              aria-selected="true"
                              class="oh-skill-picker-item"
                              data-active="true"
                              onPointerDown={(event) => {
                                if (event.button !== 0) return;
                                event.preventDefault();
                                openLocalFilePickerFromAtMention();
                              }}
                              onClick={(event) => {
                                if (event.detail === 0) openLocalFilePickerFromAtMention();
                              }}
                            >
                              <span class="oh-skill-picker-leading" aria-hidden>
                                <ComposerIcon name="file" size={16} />
                              </span>
                              <span class="min-w-0 flex-1 text-left">
                                <span class="block truncate font-semibold">{t('composer.file.local', '添加本地文件')}</span>
                                <span class="block truncate text-[11px] opacity-70">
                                  {atMentionFilePickerQuery.trim()
                                    ? atMentionFilePickerQuery.trim()
                                    : t('composer.file.localKinds', '图片、文本、代码、表格、PDF')}
                                </span>
                              </span>
                            </button>
                          </li>
                        </ul>
                      )}
                    </div>
                  </OverlayPortal>
                ) : null}
                {skillPickerVisible && skillPickerAnchor ? (
                  <OverlayPortal>
                    <div
                      ref={skillPickerOverlayRef}
                      class={`oh-skill-picker ${skillPickerClosing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'}`}
                      role="listbox"
                      style={{
                        position: 'fixed',
                        bottom: `${skillPickerAnchor.bottomGap}px`,
                        left: `${skillPickerAnchor.left}px`,
                        width: `${skillPickerAnchor.width}px`,
                        maxHeight: `${skillPickerAnchor.maxHeight}px`,
                        zIndex: DIALOG_OVERLAY_LOW_Z_INDEX,
                      }}
                    >
                      <div class="oh-skill-picker-title">
                        <span aria-hidden>
                          <ComposerIcon name="spark" size={16} />
                        </span>
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
                                onPointerDown={(event) => {
                                  if (event.button !== 0) return;
                                  event.preventDefault();
                                  selectSkillForComposer(skill);
                                }}
                                onClick={(event) => {
                                  if (event.detail === 0) selectSkillForComposer(skill);
                                }}
                              >
                                <span class="oh-skill-picker-leading" aria-hidden>
                                  {skill.emoji_icon || <ComposerIcon name="spark" size={16} />}
                                </span>
                                <span class="min-w-0 flex-1 text-left">
                                  <span class="block truncate font-semibold">{skill.name}</span>
                                  {(skill.description ?? '').trim() ? <span class="block truncate text-[11px] opacity-70">{skill.description}</span> : null}
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
                  defaultValue={composerTextRef.current}
                  onBlur={(e) => {
                    const nextFocusTarget = e.relatedTarget;
                    const skillOverlay = skillPickerOverlayRef.current;
                    const fileOverlay = atMentionFilePickerOverlayRef.current;
                    if (
                      !(nextFocusTarget instanceof Node) ||
                      (!skillOverlay?.contains(nextFocusTarget) &&
                        !fileOverlay?.contains(nextFocusTarget))
                    ) {
                      dismissSkillPicker(true);
                      dismissAtMentionFilePicker(true);
                    }
                  }}
                  onInput={(e) => {
                    const target = e.currentTarget as HTMLTextAreaElement;
                    handleComposerTextInput(target.value);
                    updateSkillPickerForText(target.value, target.selectionStart ?? target.value.length);
                    updateAtMentionFilePickerForText(target.value, target.selectionStart ?? target.value.length);
                  }}
                  onSelect={(e) => {
                    const target = e.currentTarget as HTMLTextAreaElement;
                    updateSkillPickerForText(target.value, target.selectionStart ?? target.value.length);
                    updateAtMentionFilePickerForText(target.value, target.selectionStart ?? target.value.length);
                  }}
                  onPaste={(e) => {
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
                      if (!attachmentsAllowed) {
                        setComposerError(t('composer.error.attachmentNotAllowed', '当前 service 禁用了附件'));
                        return;
                      }
                      void appendFiles(files);
                    }
                  }}
                  onKeyDown={(e) => {
                    handleComposerKeyDown(e as unknown as KeyboardEvent);
                  }}
                  disabled={composerSending || composerCollapsed || hasModeLockedGoal}
                  rows={4}
                  placeholder={hasActiveGoal ? t('goal.composer.placeholder', '目标模式由 Agent Runtime 接管中') : t('composer.placeholder', '输入消息')}
                  class="oh-composer-textarea w-full px-3 py-2 rounded-md text-sm"
                />
                {dragOver ? <div class="oh-composer-drop-overlay absolute inset-0 rounded-md flex items-center justify-center text-sm pointer-events-none oh-appear-up">{t('composer.attachment.drop', '松开即可添加附件')}</div> : null}
            </div>

            {composerError ? (
              <p class="text-xs mt-2 oh-text-error">
                {composerError}
              </p>
            ) : null}
          </div>

          <div class="oh-composer-footer flex flex-wrap items-center gap-2 mt-3" data-collapsed={composerCollapsed ? 'true' : 'false'} aria-hidden={composerCollapsed ? 'true' : undefined} {...(composerCollapsed ? { inert: true } : {})}>
            {attachmentsAllowed ? (
              <label class="oh-tap-press oh-composer-footer-action is-attachment cursor-pointer">
                <span class="oh-composer-action-icon">
                  <ComposerIcon name="attachment" size={16} />
                </span>
                {t('composer.attachment.add', '添加附件')}
                <input ref={composerFileInputRef} type="file" multiple accept={attachmentAccept} onChange={handleAttachmentInput} style={{ display: 'none' }} />
              </label>
            ) : null}
            <span class="text-xs flex-1 min-w-[160px] oh-text-muted">
              {composerText.length > 0 ? <RollingText text={`${composerText.length.toLocaleString()} ${t('composer.charUnit', '字符')}`} /> : ''}
            </span>
            {composerAttachments.length > 0 ? (
              <span class="text-xs oh-text-muted">
                {composerAttachments.length} {t('composer.attachment.unit', '个附件')}
              </span>
            ) : null}
            {hasActiveGoal ? (
              <>
                <button type="button" onClick={() => void (goalPaused ? handleResumeGoal() : handlePauseGoal())} disabled={goalControlBusy !== null} class={`oh-tap-press oh-composer-footer-action ${goalPaused ? 'is-goal-resume' : 'is-goal-pause'} disabled:opacity-50`}>
                  <span class={goalControlBusy === 'pause' || goalControlBusy === 'resume' ? 'oh-spin' : undefined}>
                    <ComposerIcon name={goalControlBusy === 'pause' || goalControlBusy === 'resume' ? 'refresh' : goalPaused ? 'play' : 'pause'} size={16} />
                  </span>
                  <span>
                    {goalControlBusy === 'pause'
                      ? t('goal.pause.busy', '正在暂停…')
                      : goalControlBusy === 'resume'
                        ? t('goal.resume.busy', '正在恢复…')
                        : goalPaused
                          ? t('goal.resume.action', '恢复目标')
                          : t('goal.pause.action', '暂停目标')}
                  </span>
                </button>
                <button type="button" onClick={() => void handleTerminateGoal()} disabled={goalControlBusy !== null} class="oh-tap-press oh-composer-footer-action is-goal-terminate disabled:opacity-50">
                  <span class={goalControlBusy === 'terminate' ? 'oh-spin' : undefined}>
                    <ComposerIcon name={goalControlBusy === 'terminate' ? 'refresh' : 'stop'} size={16} />
                  </span>
                  <span>{goalControlBusy === 'terminate' ? t('goal.terminate.busy', '正在终止…') : t('goal.terminate.action', '终止目标')}</span>
                </button>
              </>
            ) : responseRunning ? (
              <button type="button" onClick={handleStop} disabled={stopping} class="oh-tap-press oh-composer-footer-action is-stop disabled:opacity-50">
                <span class={stopping ? 'oh-spin' : undefined}>
                  <ComposerIcon name={stopping ? 'refresh' : 'stop'} size={16} />
                </span>
                <span>{stopping ? t('composer.stopping', '正在停止…') : t('composer.stop', '停止响应')}</span>
              </button>
            ) : null}
            {!hasActiveGoal ? (
              <button type="button" onClick={handleSend} disabled={composerSendDisabled} class={`oh-tap-press oh-composer-footer-action is-send disabled:opacity-50 ${responseRunning ? 'is-queueing' : ''}`}>
                <span class={composerSending ? 'oh-spin' : undefined}>
                  <ComposerIcon name={composerSending ? 'refresh' : 'send'} size={16} />
                </span>
                <span>{composerSending ? t('composer.sending', '发送中…') : responseRunning ? t('composer.queue.aheadSend', '提前发送') : t('composer.send', '发送')}</span>
              </button>
            ) : null}
          </div>
        </section>
        </div>
      </div>

      {auditMessage ? <MessageAuditDialog message={auditMessage} onClose={() => setAuditMessage(null)} /> : null}
      {sessionMetadataOpen && detail ? <SessionMetadataDialog detail={detail} messages={sortedMessages} onClose={() => setSessionMetadataOpen(false)} /> : null}
      {goalDetailsOpen && session ? <GoalDetailsDialog session={session} onClose={() => setGoalDetailsOpen(false)} /> : null}
      {tokenStatsOpen && detail ? (
        <SessionTokenStatsDialog
          detail={detail}
          modelKey={composerModelKey}
          responseRunning={responseRunning}
          onClose={() => setTokenStatsOpen(false)}
          onCompacted={() => void refresh()}
          onPointSelected={(point) => void revealCacheHitTurn(point)}
        />
      ) : null}
      {webReverseDashboardOpen && session ? <WebReverseDashboardDialog session={session} onClose={() => setWebReverseDashboardOpen(false)} /> : null}
      {androidReverseDashboardOpen && session ? <AndroidReverseDashboardDialog session={session} onClose={() => setAndroidReverseDashboardOpen(false)} /> : null}
      {throttleDialogOpen && sessionId ? <SessionThrottleDialog sessionId={sessionId} current={streamThrottle} onClose={() => setThrottleDialogOpen(false)} /> : null}
      {pendingDeleteAction ? (
        <ConfirmDialog
          title={pendingDeleteAction.cascade ? t('detail.deleteAfter.confirmTitle', '删除此条及后续消息?') : t('detail.delete.confirmTitle', '删除这条消息?')}
          body={pendingDeleteAction.cascade ? t('detail.deleteAfter.confirmBody', '此操作会删除当前消息以及它之后的所有消息，删除后不可恢复。') : t('detail.delete.confirmBody', '此操作会删除当前消息，删除后不可恢复。')}
          danger
          busy={deleteBusy}
          confirmBeforeClose
          confirmLabel={deleteBusy ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          onCancel={() => setPendingDeleteAction(null)}
          onConfirm={confirmDeleteMessage}
          onConfirmSuccess={() => setPendingDeleteAction(null)}
        />
      ) : null}
      {pendingForkMessage ? (
        <ConfirmDialog
          title={t('detail.fork.confirmTitle', '派生新会话?')}
          body={t('detail.fork.confirmBody', '将从当前会话的这条消息之后派生出一个新会话。新会话会保留这条消息及之前的内容，并丢弃之后的消息。')}
          busy={forkBusy}
          confirmBeforeClose
          confirmLabel={forkBusy ? t('detail.fork.creating', '派生中…') : t('common.fork', '派生')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setPendingForkMessage(null)}
          onConfirm={confirmForkMessage}
          onConfirmSuccess={() => {
            const nextId = forkedSessionIdRef.current;
            forkedSessionIdRef.current = null;
            setPendingForkMessage(null);
            if (nextId) location.route(`/threads/${encodeURIComponent(nextId)}`);
          }}
        />
      ) : null}
      {pendingSessionDelete ? (
        <ConfirmDialog
          title={t('topbar.deleteConfirmTitle', '删除该会话?')}
          body={t('topbar.deleteConfirm', '确定删除该会话?此操作不可恢复')}
          danger
          busy={sessionDeleteBusy}
          confirmBeforeClose
          confirmLabel={sessionDeleteBusy ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setPendingSessionDelete(false)}
          onConfirm={confirmDeleteSession}
          onConfirmSuccess={() => {
            setPendingSessionDelete(false);
            location.route('/threads');
          }}
        />
      ) : null}
      {pendingFullAccess === true ? (
        <ConfirmDialog
          title={t('topbar.perm.fullConfirmTitle', '启用完全访问权限')}
          body={t('topbar.perm.fullConfirmBody', '启用后，Web 会话中的写文件、执行命令等高风险操作将按 APP 完全访问权限模式自动执行。请确认当前会话和浏览器设备可信。')}
          danger
          busy={permissionSaving}
          confirmBeforeClose
          confirmLabel={permissionSaving ? t('common.saving', '保存中…') : t('topbar.perm.enableFullAccess', '启用完全访问权限')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setPendingFullAccess(null)}
          onConfirm={() => applyFullAccessPermission(true)}
          onConfirmSuccess={() => setPendingFullAccess(null)}
        />
      ) : null}
      {pendingWriteApproval ? (
        <ConfirmDialog
          title={t('detail.writeApproval.title', '确认写操作')}
          body={
            <div class="oh-write-approval-dialog-content">
              <p class="oh-write-approval-dialog-copy">{t('detail.writeApproval.body', '当前默认权限模式需要确认后才会继续执行写文件或命令操作。')}</p>
              <p class="oh-write-approval-dialog-copy" style={{ marginTop: 6, opacity: 0.8 }}>
                {t('detail.writeApproval.hint', '快捷键：Enter 允许；拒绝请使用下方按钮')}
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
          }
          danger
          busy={writeApprovalBusy}
          confirmBeforeClose
          closeOnEscape={false}
          wide
          scrollBody
          disableBackdropClose
          confirmLabel={writeApprovalBusy ? t('common.processing', '处理中…') : t('detail.writeApproval.approve', '允许执行')}
          cancelLabel={t('detail.writeApproval.reject', '拒绝')}
          onCancel={() => void handleWriteApproval('rejected')}
          onConfirm={() => handleWriteApproval('approved')}
          onConfirmSuccess={() => setPendingWriteApproval(null)}
        />
      ) : null}
      {imageEditorInput ? <ImageEditorDialog input={imageEditorInput} onCancel={() => settleImageEditor(null)} onSave={(result) => settleImageEditor(result)} /> : null}
      {showComposerModelPicker && !modelSelectionLocked ? (
        <ModelPickerDialog
          models={allowedModels}
          selectedKey={composerModelKey}
          onSelect={(key) => {
            if (modelSelectionLocked) {
              showSnackbar(modelSelectionLockReason);
              return;
            }
            setComposerModelKey(key);
          }}
          onClose={() => setShowComposerModelPicker(false)}
        />
      ) : null}
      {goalStartOptionsOpen ? (
        <GoalStartOptionsDialog
          models={allowedModels}
          initialModelKey={composerModelKey || session?.last_model_key || meta?.active_model_key || ''}
          onConfirm={settleGoalStartOptions}
          onCancel={() => settleGoalStartOptions(null)}
        />
      ) : null}
      {showCreationOptions ? (
        <CreationOptionsDialog
          mode={showCreationOptions}
          initial={creationOptions}
          onConfirm={(options) => {
            setCreationOptions(options);
            setShowCreationOptions(null);
          }}
          onCancel={() => setShowCreationOptions(null)}
        />
      ) : null}
      {showTitleSummary && session ? (
        <TitleSummaryDialog
          initialMessages={sortedMessages}
          loadMessages={loadTitleSourceMessages}
          models={allowedModels}
          initialModelKey={titleSummaryDefaultModelKey}
          onGenerate={async (startIdx, endIdx, userMsgs, options) => {
            const selectedContent = userMsgs
              .slice(startIdx, endIdx + 1)
              .map((m) => m.content.trim())
              .join('\n\n');
            const res = await generateSessionTitle(sessionId, selectedContent, {
              signal: options.signal,
              modelKey: options.modelKey,
            });
            // 刷新会话详情以获取新标题
            loadDetail();
            return res.title;
          }}
          onClose={() => setShowTitleSummary(false)}
          onTitleUpdated={(title) => {
            setDetail((prev) => (prev ? { ...prev, session: { ...prev.session, title } } : prev));
          }}
        />
      ) : null}
      {showTrajectory && session ? (
        <TrajectoryDialog
          sessionId={sessionId}
          sessionTitle={session.title || t('sessions.untitled', '未命名会话')}
          sessionCreatedAt={session.created_at}
          messages={sortedMessages}
          messageWindowStart={windowOffset}
          messageTotal={totalKnown}
          hasOlder={remainingOlder > 0}
          loadingOlder={loadingOlder || olderRenderSettling}
          onLoadOlder={loadOlder}
          onClose={() => setShowTrajectory(false)}
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
function ErrorBanner({ message, onRetry, onDismiss }: { message: string; onRetry: () => void; onDismiss: () => void }) {
  const lower = message.toLowerCase();
  const isConnRefused = lower.includes('connection refused') || lower.includes('econnrefused') || lower.includes('errno = 61') || lower.includes('errno = 111') || lower.includes('failed to connect');
  const isNetwork = !isConnRefused && (lower.includes('socketexception') || lower.includes('handshakeexception') || lower.includes('network is unreachable') || lower.includes('failed host lookup') || lower.includes('errno = 8') || lower.includes('errno = 65'));
  const isTimeout = !isConnRefused && !isNetwork && (lower.includes('timeout') || lower.includes('timed out'));

  let title: string;
  let hint: string | null;
  if (isConnRefused) {
    title = t('detail.error.connRefused.title', '无法连接到 AI 服务');
    hint = t('detail.error.connRefused.hint', '后端拒绝连接：请确认 Base URL 与端口可访问，确认代理（如 Clash）端口/规则正确，或切换至备用模型/服务商再试。');
  } else if (isNetwork) {
    title = t('detail.error.network.title', '网络异常');
    hint = t('detail.error.network.hint', '请求未能完成：检查本机网络连接、DNS 与代理设置；如使用专线/VPN 请确认隧道在线。');
  } else if (isTimeout) {
    title = t('detail.error.timeout.title', '请求超时');
    hint = t('detail.error.timeout.hint', '远端长时间未响应：可重试一次；若持续超时请尝试更小的输入或切换模型。');
  } else {
    title = t('detail.lastError', '最近错误：');
    hint = null;
  }

  const copyText = async () => {
    const ok = await copyTextToClipboard(message);
    showSnackbar(ok ? t('detail.error.copy.ok', '已复制错误详情') : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'), {
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
          <div class="oh-session-error-title" style={{ color: 'var(--m3-error)', fontWeight: 600 }}>
            {title}
          </div>
          {hint ? (
            <div class="oh-session-error-hint" style={{ color: 'var(--m3-on-surface-variant)', marginTop: 2 }}>
              {hint}
            </div>
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

function GoalStartOptionsDialog({
  models,
  initialModelKey,
  onConfirm,
  onCancel,
}: {
  models: ApiMetaModel[];
  initialModelKey: string;
  onConfirm: (options: GoalStartOptions) => void;
  onCancel: () => void;
}) {
  const [modelKey, setModelKey] = useState(() => {
    return models.some((model) => model.key === initialModelKey)
      ? initialModelKey
      : models[0]?.key ?? '';
  });
  const [modelPickerOpen, setModelPickerOpen] = useState(false);
  const [turnLimitEnabled, setTurnLimitEnabled] = useState(false);
  const [turnLimit, setTurnLimit] = useState(String(GOAL_DEFAULT_MAX_AUTO_TURNS));
  const [tokenBudgetEnabled, setTokenBudgetEnabled] = useState(false);
  const [tokenBudget, setTokenBudget] = useState('');
  const [error, setError] = useState<string | null>(null);
  const pendingOptionsRef = useRef<GoalStartOptions | null>(null);
  const { closing, requestCloseWithReason } = useDialogExitMotion<
    'cancel' | 'confirm'
  >((reason) => {
    const options = pendingOptionsRef.current;
    pendingOptionsRef.current = null;
    if (reason === 'confirm' && options != null) {
      onConfirm(options);
      return;
    }
    onCancel();
  });
  const requestClose = () => requestCloseWithReason('cancel');

  useEffect(() => {
    setModelKey((current) => {
      if (current && models.some((model) => model.key === current)) return current;
      return models[0]?.key ?? '';
    });
  }, [models]);

  const selectedModel = models.find((model) => model.key === modelKey);
  const modelLabel = selectedModel
    ? `${selectedModel.label || selectedModel.model_id}${selectedModel.provider ? ` · ${selectedModel.provider}` : ''}`
    : t('composer.modelEmpty', '主控制台未配置模型');

  const submit = (event?: Event) => {
    event?.preventDefault();
    if (!selectedModel) {
      setError(t('composer.error.modelMissing', '请选择模型'));
      return;
    }
    const turns = turnLimitEnabled ? strictPositiveIntegerFromText(turnLimit) : null;
    if (turnLimitEnabled && (turns == null || turns > GOAL_HARD_MAX_AUTO_TURNS)) {
      setError(t('goal.start.turnLimit.invalid', '轮次限制请输入 1 到 60 的正整数'));
      return;
    }
    const budget = tokenBudgetEnabled ? strictPositiveIntegerFromText(tokenBudget) : null;
    if (tokenBudgetEnabled && budget == null) {
      setError(t('goal.start.tokenBudget.invalid', 'Token 预算请输入正整数'));
      return;
    }
    pendingOptionsRef.current = {
      evaluator_provider_config_id: selectedModel.provider_id || selectedModel.key,
      evaluator_model_id: selectedModel.model_id,
      evaluator_model_label: selectedModel.label || selectedModel.model_id,
      max_turns: turns,
      token_budget: budget,
    };
    requestCloseWithReason('confirm');
  };

  const SwitchButton = ({
    checked,
    onClick,
    label,
  }: {
    checked: boolean;
    onClick: () => void;
    label: string;
  }) => (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={onClick}
      class={`oh-goal-switch oh-tap-press ${checked ? 'is-on' : ''}`}
      title={label}
    >
      <span />
    </button>
  );

  return (
    <>
      <DialogFrame
        closing={closing}
        onRequestClose={requestClose}
        {...createStandardDialogFrameAppearance({
          overlayTone: 'strong',
          panelClassName: 'rounded-m3-md p-5 max-w-lg w-full flex flex-col',
          panelBorder: 'outline',
          panelSurface: {
            maxHeight: '82vh',
          },
        })}
        ariaLabel={t('goal.start.title', '启动目标模式')}
      >
        <form onSubmit={submit} class="oh-goal-start-form">
          <header class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h2 class="text-base font-semibold oh-text-body">
                {t('goal.start.title', '启动目标模式')}
              </h2>
              <p class="text-xs mt-1 oh-text-muted">
                {t('goal.start.subtitle', '当前输入内容会成为本线程目标，由 Agent Runtime 自动推进并评估完成证据。')}
              </p>
            </div>
            <DialogActionButton onClick={requestClose} tone="ghost">
              <ComposerIcon name="close" size={14} />
              <span>{t('common.close', '关闭')}</span>
            </DialogActionButton>
          </header>

          <label class="oh-goal-field text-xs oh-text-muted">
            {t('goal.start.evaluatorModel', '评估模型')}
            <button
              type="button"
              onClick={() => setModelPickerOpen(true)}
              disabled={models.length === 0}
              class="oh-tap-press oh-goal-model-button text-left"
            >
              <span class="oh-goal-model-icon" aria-hidden>
                <ComposerIcon name="model" size={16} />
              </span>
              <span class="truncate">{modelLabel}</span>
            </button>
          </label>

          <div class="oh-goal-option-stack">
            <div class="oh-goal-option-row">
              <div class="min-w-0 flex-1">
                <div class="text-sm font-semibold oh-text-body">{t('goal.start.turnLimit', '轮次限制')}</div>
                <div class="text-xs mt-1 oh-text-muted">{t('goal.start.turnLimit.hint', '关闭时使用运行时默认安全上限。')}</div>
              </div>
              <SwitchButton checked={turnLimitEnabled} onClick={() => setTurnLimitEnabled((value) => !value)} label={t('goal.start.turnLimit', '轮次限制')} />
            </div>
            {turnLimitEnabled ? (
              <input
                type="number"
                min={1}
                max={GOAL_HARD_MAX_AUTO_TURNS}
                value={turnLimit}
                onInput={(event) => setTurnLimit((event.currentTarget as HTMLInputElement).value)}
                class="oh-goal-number-input"
                aria-label={t('goal.start.turnLimit', '轮次限制')}
              />
            ) : null}
          </div>

          <div class="oh-goal-option-stack">
            <div class="oh-goal-option-row">
              <div class="min-w-0 flex-1">
                <div class="text-sm font-semibold oh-text-body">{t('goal.start.tokenBudget', 'Token 预算')}</div>
                <div class="text-xs mt-1 oh-text-muted">{t('goal.start.tokenBudget.hint', '关闭时不额外设置预算，只保留硬性轮次保护。')}</div>
              </div>
              <SwitchButton checked={tokenBudgetEnabled} onClick={() => setTokenBudgetEnabled((value) => !value)} label={t('goal.start.tokenBudget', 'Token 预算')} />
            </div>
            {tokenBudgetEnabled ? (
              <input
                type="number"
                min={1}
                value={tokenBudget}
                onInput={(event) => setTokenBudget((event.currentTarget as HTMLInputElement).value)}
                class="oh-goal-number-input"
                placeholder="128000"
                aria-label={t('goal.start.tokenBudget', 'Token 预算')}
              />
            ) : null}
          </div>

          {error ? <p class="text-xs oh-text-error">{error}</p> : null}

          <div class="oh-goal-dialog-actions">
            <DialogActionButton onClick={requestClose}>
              {t('common.cancel', '取消')}
            </DialogActionButton>
            <DialogActionButton type="submit" tone="primary">
              <ComposerIcon name="goal" size={14} />
              <span>{t('goal.start.confirm', '启动目标')}</span>
            </DialogActionButton>
          </div>
        </form>
      </DialogFrame>
      {modelPickerOpen ? (
        <ModelPickerDialog
          models={models}
          selectedKey={modelKey}
          onSelect={(key) => {
            setModelKey(key);
          }}
          onClose={() => setModelPickerOpen(false)}
        />
      ) : null}
    </>
  );
}

function GoalDetailsDialog({ session, onClose }: { session: SessionSummary; onClose: () => void }) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const state = session.goal_state;
  const current = state?.current ?? null;
  const history = [...(state?.history ?? [])].reverse();
  const environment = recordFromUnknown(session.environment);

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayTone: 'strong',
        panelClassName: 'rounded-m3-md p-5 max-w-3xl w-full flex flex-col',
        panelBorder: 'outline',
        panelSurface: {
          maxHeight: '86vh',
        },
      })}
      ariaLabel={t('goal.details.title', '目标执行详情')}
    >
      <header class="flex flex-wrap items-start justify-between gap-3 mb-4">
        <div class="min-w-0">
          <h2 class="text-base font-semibold oh-text-body">
            {t('goal.details.title', '目标执行详情')}
          </h2>
          <p class="text-xs mt-1 oh-text-muted">
            {session.template_name || session.template_id} · {sessionModeLabel(session.mode)}
          </p>
        </div>
        <DialogActionButton onClick={requestClose} tone="ghost">
          <ComposerIcon name="close" size={14} />
          <span>{t('common.close', '关闭')}</span>
        </DialogActionButton>
      </header>

      <div class="oh-goal-details-scroll">
        {current ? (
          <GoalRecordSection goal={current} title={t('goal.details.current', '当前目标')} full />
        ) : (
          <section class="oh-goal-section">
            <h3>{t('goal.details.current', '当前目标')}</h3>
            <p class="text-sm oh-text-muted">{t('goal.details.noCurrent', '当前没有正在执行的目标。')}</p>
          </section>
        )}

        <section class="oh-goal-section">
          <h3>{t('goal.details.environment', '环境信息')}</h3>
          <div class="oh-goal-kv-grid">
            <GoalKv label={t('goal.details.session', '线程')} value={session.id} />
            <GoalKv label={t('goal.details.template', '模板')} value={session.template_name || session.template_id} />
            <GoalKv label={t('goal.details.mode', '当前模式')} value={sessionModeLabel(session.mode)} />
            <GoalKv label={t('goal.details.messages', '消息数')} value={String(session.message_count ?? 0)} />
            <GoalKv label={t('goal.details.platform', '平台')} value={stringFromUnknown(environment['platform']) || '—'} />
            <GoalKv label={t('goal.details.workingDirectory', '工作目录')} value={stringFromUnknown(environment['application_directory'] ?? environment['working_directory']) || '—'} />
            <GoalKv label={t('goal.details.sessionsDirectory', '会话目录')} value={stringFromUnknown(environment['sessions_directory_path'] ?? environment['sessions_directory']) || '—'} />
          </div>
        </section>

        <section class="oh-goal-section">
          <h3>{t('goal.details.history', '历史目标')}</h3>
          {history.length === 0 ? (
            <p class="text-sm oh-text-muted">{t('goal.details.history.empty', '暂无历史目标。')}</p>
          ) : (
            <div class="flex flex-col gap-3">
              {history.map((goal) => <GoalRecordSection key={goal.id} goal={goal} title={goalStatusLabel(goal.status)} />)}
            </div>
          )}
        </section>
      </div>
    </DialogFrame>
  );
}

function GoalRecordSection({ goal, title, full = false }: { goal: SessionGoalRecord; title: string; full?: boolean }) {
  const evaluations = [...(goal.evaluations ?? [])].reverse().slice(0, full ? 8 : 3);
  return (
    <section class="oh-goal-section">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3>{title}</h3>
        <span class={`oh-goal-status-chip ${isActiveGoalStatus(goal.status) ? 'is-active' : ''}`}>
          {goalProgressLabel(goal)}
        </span>
      </div>
      <p class="oh-goal-objective">{goal.objective}</p>
      <div class="oh-goal-kv-grid">
        <GoalKv label={t('goal.details.evaluator', '评估模型')} value={goal.evaluator_model_label || goal.evaluator_model_id} />
        <GoalKv label={t('goal.details.createdAt', '创建时间')} value={formatDialogDate(goal.created_at)} />
        <GoalKv label={t('goal.details.updatedAt', '更新时间')} value={formatDialogDate(goal.updated_at)} />
        <GoalKv label={t('goal.details.finishedAt', '结束时间')} value={formatDialogDate(goal.completed_at ?? goal.terminated_at)} />
      </div>
      {goal.status_reason ? (
        <p class="oh-goal-reason">{goalStatusReasonLabel(goal.status_reason)}</p>
      ) : null}
      {evaluations.length > 0 ? (
        <div class="oh-goal-evaluation-list">
          {evaluations.map((evaluation) => {
            const summary = goalEvaluationSummaryLabel(evaluation.summary) || goalEvaluationSummaryLabel(evaluation.error) || '—';
            return (
              <div key={evaluation.id} class={`oh-goal-evaluation ${evaluation.passed ? 'is-pass' : 'is-miss'}`}>
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <strong>{evaluation.passed ? t('goal.evaluation.pass', '证据通过') : t('goal.evaluation.miss', '继续推进')}</strong>
                  <span>{formatDialogDate(evaluation.created_at)} · #{evaluation.round_index}</span>
                </div>
                <p>{summary}</p>
                {evaluation.evidence?.length ? (
                  <div class="oh-goal-evaluation-block">
                    <span>{t('goal.evaluation.evidence', '证据')}</span>
                    <div class="oh-goal-inline-list">{evaluation.evidence.slice(0, 4).map((item, index) => <span key={`e-${index}`}>{item}</span>)}</div>
                  </div>
                ) : null}
                {evaluation.missing?.length ? (
                  <div class="oh-goal-evaluation-block">
                    <span>{t('goal.evaluation.missing', '缺口')}</span>
                    <div class="oh-goal-inline-list is-missing">{evaluation.missing.slice(0, 4).map((item, index) => <span key={`m-${index}`}>{item}</span>)}</div>
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      ) : null}
    </section>
  );
}

function GoalKv({ label, value }: { label: string; value: ComponentChildren }) {
  return (
    <div class="oh-goal-kv">
      <span>{label}</span>
      <strong>{value || '—'}</strong>
    </div>
  );
}

/// 消息审计弹窗：展示原始 JSON（id / kind / role / metadata / created_at / character_count），
/// 用于排查 tool_call 元数据 / 文件变动等问题。复用全局对话框样式。
function MessageAuditDialog({ message, onClose }: { message: SessionMessage; onClose: () => void }) {
  const json = JSON.stringify(message, null, 2);
  const { closing, requestClose } = useDialogExitMotion(onClose);
  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayTone: 'strong',
        panelClassName: 'rounded-m3-md p-4 max-w-2xl w-full flex flex-col',
        panelBorder: 'outline',
        panelSurface: {
          maxHeight: '80vh',
        },
      })}
      ariaLabel={`${t('common.audit', '审计')} ${message.id}`}
    >
      <header class="flex flex-wrap items-center justify-between gap-3 mb-3">
        <h2 class="text-base font-semibold min-w-0 truncate">
          {t('common.audit', '审计')} · {message.id}
        </h2>
        <JsonDialogActions json={json} requestClose={requestClose} />
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
    </DialogFrame>
  );
}

type ContextUsageCategory =
  | 'system_prompt'
  | 'builtin_tools'
  | 'mcp'
  | 'instructions'
  | 'memory'
  | 'skills'
  | 'hooks'
  | 'conversation'
  | 'runtime';

interface ContextUsageItem {
  category: ContextUsageCategory;
  characterCount: number;
  tokenCount: number;
}

interface ContextUsageBreakdown {
  items: ContextUsageItem[];
  totalCharacters: number;
  totalTokens: number;
  measured: boolean;
}

interface ContextWindowUsage {
  usedTokens: number;
  windowTokens: number;
  ratio: number;
  percent: number;
  canManuallyCompact: boolean;
}

const MANUAL_COMPACTION_MIN_CONTEXT_USAGE_RATIO = 0.2;

const CONTEXT_USAGE_CATEGORIES: ContextUsageCategory[] = [
  'system_prompt',
  'builtin_tools',
  'mcp',
  'instructions',
  'memory',
  'skills',
  'hooks',
  'conversation',
  'runtime',
];

const CONTEXT_USAGE_PRESENTATION: Record<ContextUsageCategory, { key: string; fallback: string; color: string }> = {
  system_prompt: { key: 'tokenPopup.context.systemPrompt', fallback: '系统 Prompt', color: 'var(--m3-primary)' },
  builtin_tools: { key: 'tokenPopup.context.builtinTools', fallback: '内建 Tool', color: 'var(--m3-secondary)' },
  mcp: { key: 'tokenPopup.context.mcp', fallback: 'MCP', color: 'var(--m3-tertiary)' },
  instructions: { key: 'tokenPopup.context.instructions', fallback: '指令', color: 'color-mix(in srgb, var(--m3-primary) 58%, var(--m3-tertiary))' },
  memory: { key: 'tokenPopup.context.memory', fallback: '记忆', color: 'color-mix(in srgb, var(--m3-error) 42%, var(--m3-tertiary))' },
  skills: { key: 'tokenPopup.context.skills', fallback: '技能', color: 'color-mix(in srgb, var(--m3-secondary) 48%, var(--m3-tertiary))' },
  hooks: { key: 'tokenPopup.context.hooks', fallback: 'Hooks', color: 'color-mix(in srgb, var(--m3-error) 44%, var(--m3-primary))' },
  conversation: { key: 'tokenPopup.context.conversation', fallback: '会话', color: 'color-mix(in srgb, var(--m3-primary) 42%, var(--m3-secondary))' },
  runtime: { key: 'tokenPopup.context.runtime', fallback: '运行时', color: 'var(--m3-outline)' },
};

function parseContextUsage(session: SessionSummary): ContextUsageBreakdown | null {
  const metadata = recordFromUnknown(session.last_prompt_metadata);
  const raw = recordFromUnknown(metadata['context_usage_breakdown']);
  const rawItems = arrayFromUnknown(raw['items']);
  if (rawItems.length === 0) return null;
  const byCategory = new Map<ContextUsageCategory, ContextUsageItem>();
  for (const rawItem of rawItems) {
    const item = recordFromUnknown(rawItem);
    const category = strictStringFromUnknown(item['category']) as ContextUsageCategory;
    if (!CONTEXT_USAGE_CATEGORIES.includes(category)) continue;
    byCategory.set(category, {
      category,
      characterCount: nonNegativeIntegerFromUnknown(item['character_count']),
      tokenCount: 0,
    });
  }
  const parsedItems = CONTEXT_USAGE_CATEGORIES.map((category) => byCategory.get(category) ?? {
    category,
    characterCount: 0,
    tokenCount: 0,
  });
  const totalCharactersBigInt = parsedItems.reduce(
    (sum, item) => sum + BigInt(item.characterCount),
    0n,
  );
  const declaredTokens = nonNegativeIntegerFromUnknown(raw['total_tokens']);
  if (totalCharactersBigInt <= 0n || declaredTokens <= 0) return null;
  const totalCharacters = Number(
    totalCharactersBigInt > BigInt(Number.MAX_SAFE_INTEGER)
      ? BigInt(Number.MAX_SAFE_INTEGER)
      : totalCharactersBigInt,
  );
  const items = distributeContextUsageTokens(parsedItems, totalCharactersBigInt, declaredTokens);
  return {
    items,
    totalCharacters,
    totalTokens: declaredTokens,
    measured: strictStringFromUnknown(raw['token_source']) === 'provider',
  };
}

function distributeContextUsageTokens(
  items: ContextUsageItem[],
  totalCharacters: bigint,
  totalTokens: number,
): ContextUsageItem[] {
  const remainders: { index: number; value: bigint }[] = [];
  const tokenCounts = items.map((item, index) => {
    const weighted = BigInt(totalTokens) * BigInt(item.characterCount);
    remainders.push({ index, value: weighted % totalCharacters });
    return Number(weighted / totalCharacters);
  });
  let allocated = tokenCounts.reduce((sum, value) => sum + value, 0);
  remainders.sort((a, b) => a.value === b.value ? a.index - b.index : a.value > b.value ? -1 : 1);
  for (let index = 0; allocated < totalTokens; index += 1) {
    tokenCounts[remainders[index % remainders.length]!.index]! += 1;
    allocated += 1;
  }
  return items.map((item, index) => ({ ...item, tokenCount: tokenCounts[index] ?? 0 }));
}

function parseContextWindowUsage(session: SessionSummary): ContextWindowUsage {
  const metadata = recordFromUnknown(session.last_prompt_metadata);
  const usedTokens = nonNegativeIntegerFromUnknown(metadata['context_budget_estimated_prompt_tokens']);
  const windowTokens = nonNegativeIntegerFromUnknown(metadata['context_budget_effective_window_tokens']);
  const ratio = usedTokens > 0 && windowTokens > 0
    ? clampNumber(usedTokens / windowTokens, 0, 1)
    : 0;
  return {
    usedTokens,
    windowTokens,
    ratio,
    percent: Math.round(ratio * 100),
    canManuallyCompact:
      usedTokens > 0 &&
      windowTokens > 0 &&
      ratio > MANUAL_COMPACTION_MIN_CONTEXT_USAGE_RATIO,
  };
}

interface SessionTokenStatsViewModel {
  promptTokens: number;
  completionTokens: number;
  reasoningTokens: number;
  audioInputTokens: number;
  imageInputTokens: number;
  videoInputTokens: number;
  webSearchToolUsage: number;
  webSearchPageUsage: number;
  totalTokens: number;
  totalMessageCount: number;
  promptBuildCount: number;
  totalPromptCharacters: number;
  cacheHit: SessionCacheHitDisplay;
  contextUsage: ContextUsageBreakdown | null;
  contextWindowUsage: ContextWindowUsage;
}

function buildSessionTokenStatsViewModel(session: SessionSummary): SessionTokenStatsViewModel {
  const stats = recordFromUnknown(session.statistics);
  const promptTokensTotal = readStatNumber(stats['total_prompt_tokens'], session.total_prompt_tokens);
  const completionTokens = readStatNumber(stats['total_completion_tokens'], session.total_completion_tokens);
  const reasoningTokens = readStatNumber(stats['reasoning_tokens'], 0);
  const audioInputTokens = readStatNumber(stats['audio_input_tokens'], 0);
  const imageInputTokens = readStatNumber(stats['image_input_tokens'], 0);
  const videoInputTokens = readStatNumber(stats['video_input_tokens'], 0);
  const webSearchToolUsage = readStatNumber(stats['web_search_tool_usage'], 0);
  const webSearchPageUsage = readStatNumber(stats['web_search_page_usage'], 0);
  const totalTokens = readStatNumber(stats['total_tokens'], session.total_tokens ?? promptTokensTotal + completionTokens);
  const totalMessageCount = readStatNumber(stats['total_message_count'], session.message_count);
  const promptBuildCount = readStatNumber(stats['prompt_build_count'], 0);
  const totalPromptCharacters = readStatNumber(stats['total_prompt_characters'], 0);
  const contextUsage = parseContextUsage(session);
  const contextWindowUsage = parseContextWindowUsage(session);
  // WEB 端纯只读：缓存命中率 / 走势数据均从后端 metadata
  // 实时取得，不做任何客户端计算。后端 _patchedStatistics 保证不存在 stale
  // 0 值，_resolveCacheHitTrend 保证逐消息缺失时有累积统计兜底。
  const cacheHit = buildSessionCacheHitDisplay(session, stats);
  return {
    promptTokens: promptTokensTotal,
    completionTokens,
    reasoningTokens,
    audioInputTokens,
    imageInputTokens,
    videoInputTokens,
    webSearchToolUsage,
    webSearchPageUsage,
    totalTokens,
    totalMessageCount,
    promptBuildCount,
    totalPromptCharacters,
    cacheHit,
    contextUsage,
    contextWindowUsage,
  };
}

function contextUsagePercent(tokens: number, totalTokens: number): string {
  if (tokens <= 0 || totalTokens <= 0) return '0%';
  const value = tokens / totalTokens * 100;
  if (value < 0.1) return '<0.1%';
  return value >= 10 ? `${Math.round(value)}%` : `${value.toFixed(1)}%`;
}

function ContextUsageOverview({
  usage,
  windowUsage,
  canCompact = false,
  compacting = false,
  onCompact,
}: {
  usage: ContextUsageBreakdown | null;
  windowUsage: ContextWindowUsage;
  canCompact?: boolean;
  compacting?: boolean;
  onCompact?: () => void;
}) {
  const activeItems = usage?.items.filter((item) => item.tokenCount > 0) ?? [];
  const contextColor = windowUsage.ratio >= 0.9
    ? 'var(--m3-error)'
    : windowUsage.ratio >= 0.7
      ? 'var(--m3-tertiary)'
      : 'var(--m3-primary)';
  const hasWindowData = windowUsage.windowTokens > 0;
  const showCompact = canCompact || compacting;
  const compactMotionCurve = showCompact
    ? 'var(--oh-dialog-curve)'
    : 'var(--oh-dialog-exit-curve)';
  const compactMotionDuration = showCompact
    ? 'var(--oh-dialog-enter-duration)'
    : 'var(--oh-dialog-exit-duration)';
  return (
    <section
      class="rounded-m3-md p-3"
      style={{
        background: 'var(--m3-surface-container-low)',
        border: '1px solid var(--m3-outline-variant)',
      }}
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h3 class="text-xs font-extrabold oh-text-body">
            {t('tokenPopup.context.title', '上下文数据概览')}
          </h3>
          {usage ? (
            <p class="mt-0.5 text-[11px] oh-text-muted">
              {usage.measured
                ? t('tokenPopup.context.measured', '总量实测 · 分类折算')
                : t('tokenPopup.context.estimated', '按请求内容估算')}
            </p>
          ) : null}
        </div>
        {usage ? (
          <div class="shrink-0 text-right">
            <strong class="block text-sm tabular-nums oh-text-primary">
              {usage.totalTokens.toLocaleString()}
            </strong>
            <span class="text-[10px] font-semibold oh-text-muted">Token</span>
          </div>
        ) : null}
      </div>
      {hasWindowData ? (
        <div
          class="mt-3 rounded-m3-sm px-2.5 py-2.5"
          style={{
            background: `color-mix(in srgb, ${contextColor} 7%, transparent)`,
            border: `1px solid color-mix(in srgb, ${contextColor} 20%, transparent)`,
          }}
        >
          <div class="flex items-center gap-2">
            <span class="text-[11px] font-extrabold oh-text-body">
              {t('tokenPopup.context.window', '上下文窗口')}
            </span>
            <span class="ml-auto text-xs font-black tabular-nums" style={{ color: contextColor }}>
              <RollingText text={`${windowUsage.percent}%`} />
            </span>
          </div>
          <div class="mt-2 h-[7px] overflow-hidden rounded-full" style={{ background: 'var(--m3-surface-container-highest)' }}>
            <div
              class="h-full rounded-full"
              style={{
                width: `${windowUsage.ratio * 100}%`,
                background: contextColor,
                transition: 'width var(--oh-dialog-duration) var(--oh-dialog-curve), background var(--oh-dialog-duration) var(--oh-dialog-curve)',
              }}
            />
          </div>
          <div class="mt-1.5 text-right text-[10px] tabular-nums oh-text-muted">
            {windowUsage.usedTokens.toLocaleString()} / {windowUsage.windowTokens.toLocaleString()} Token
          </div>
        </div>
      ) : null}
      {hasWindowData || compacting ? (
        <div
          aria-hidden={!showCompact}
          style={{
            maxHeight: showCompact ? '48px' : '0px',
            marginTop: showCompact ? '10px' : '0px',
            opacity: showCompact ? 1 : 0,
            transform: showCompact ? 'translateY(0) scale(1)' : 'translateY(-5px) scale(.96)',
            overflow: 'hidden',
            pointerEvents: showCompact ? 'auto' : 'none',
            transition: `max-height ${compactMotionDuration} ${compactMotionCurve}, margin ${compactMotionDuration} ${compactMotionCurve}, opacity ${compactMotionDuration} ${compactMotionCurve}, transform ${compactMotionDuration} ${compactMotionCurve}`,
          }}
        >
          <button
            type="button"
            class="oh-tap-press ml-auto flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-bold disabled:opacity-60"
            style={{
              color: 'var(--m3-on-primary-container)',
              background: 'var(--m3-primary-container)',
              border: '1px solid color-mix(in srgb, var(--m3-primary) 30%, transparent)',
            }}
            disabled={compacting}
            onClick={onCompact}
          >
            {compacting ? <span class="oh-spin"><ComposerIcon name="refresh" size={14} /></span> : null}
            <span>{compacting ? t('tokenPopup.context.compacting', '正在压缩…') : t('tokenPopup.context.compactNow', '主动压缩')}</span>
          </button>
        </div>
      ) : null}
      {usage ? (
        <>
          <div class="mt-3 flex h-[7px] overflow-hidden rounded-full" style={{ background: 'var(--m3-surface-container-highest)' }}>
            {activeItems.map((item) => (
              <span
                key={item.category}
                style={{
                  background: CONTEXT_USAGE_PRESENTATION[item.category].color,
                  flexGrow: Math.max(0.001, item.tokenCount / usage.totalTokens),
                  flexBasis: 0,
                  transition: 'flex-grow var(--oh-dialog-duration) var(--oh-dialog-curve)',
                }}
              />
            ))}
          </div>
          <div class="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
            {usage.items.map((item) => {
              const presentation = CONTEXT_USAGE_PRESENTATION[item.category];
              const active = item.tokenCount > 0;
              return (
                <div
                  key={item.category}
                  class="min-w-0 rounded-m3-sm px-2.5 py-2"
                  style={{
                    background: `color-mix(in srgb, ${presentation.color} ${active ? '9%' : '3.5%'}, transparent)`,
                    border: `1px solid color-mix(in srgb, ${presentation.color} ${active ? '24%' : '10%'}, transparent)`,
                  }}
                >
                  <div class="flex min-w-0 items-center gap-1.5">
                    <span class="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: presentation.color }} />
                    <span class="truncate text-[10px] font-bold" style={{ color: active ? 'var(--m3-on-surface)' : 'var(--m3-on-surface-variant)' }}>
                      {t(presentation.key, presentation.fallback)}
                    </span>
                  </div>
                  <div class="mt-1 flex items-end justify-between gap-1">
                    <strong class="min-w-0 truncate text-xs tabular-nums oh-text-body">
                      {item.tokenCount.toLocaleString()}
                    </strong>
                    <span class="shrink-0 text-[10px] font-bold tabular-nums" style={{ color: presentation.color }}>
                      {contextUsagePercent(item.tokenCount, usage.totalTokens)}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </>
      ) : (
        <div
          class="mt-3 flex items-center gap-2 rounded-m3-sm px-2.5 py-2.5 text-[11px] font-semibold"
          style={{
            color: 'var(--m3-on-surface-variant)',
            background: 'color-mix(in srgb, var(--m3-surface-container-highest) 46%, transparent)',
            border: '1px solid color-mix(in srgb, var(--m3-outline-variant) 46%, transparent)',
          }}
        >
          <span class="shrink-0 oh-text-primary">
            <ComposerIcon name="history" size={16} />
          </span>
          <span>{t('tokenPopup.context.empty', '发送下一条消息后生成概览')}</span>
        </div>
      )}
    </section>
  );
}

function SessionTokenStatsContent({
  stats,
  trendDisplayMode,
  onTrendDisplayModeChange,
  onPointSelected,
  canCompact,
  compacting,
  onCompact,
}: {
  stats: SessionTokenStatsViewModel;
  trendDisplayMode: CacheHitDisplayMode;
  onTrendDisplayModeChange: (mode: CacheHitDisplayMode) => void;
  onPointSelected?: (point: CacheHitTrendPoint) => void;
  canCompact?: boolean;
  compacting?: boolean;
  onCompact?: () => void;
}) {
  const {
    promptTokens,
    completionTokens,
    reasoningTokens,
    audioInputTokens,
    imageInputTokens,
    videoInputTokens,
    webSearchToolUsage,
    webSearchPageUsage,
    totalTokens,
    totalMessageCount,
    promptBuildCount,
    totalPromptCharacters,
    cacheHit,
    contextUsage,
    contextWindowUsage,
  } = stats;
  const {
    cacheReadTokens,
    cacheWriteTokens,
    uncachedPromptTokens,
    cacheHitRatio,
    trendData,
    claudeStyle,
  } = cacheHit;
  return (
    <>
      <TokenStatsSection title={t('tokenPopup.input', '输入')}>
        <TokenStatsRow label={t('tokenPopup.prompt', '提示词')} value={promptTokens} />
        {audioInputTokens > 0 ? <TokenStatsRow label={t('tokenPopup.audioInput', '音频输入')} value={audioInputTokens} /> : null}
        {imageInputTokens > 0 ? <TokenStatsRow label={t('tokenPopup.imageInput', '图片输入')} value={imageInputTokens} /> : null}
        {videoInputTokens > 0 ? <TokenStatsRow label={t('tokenPopup.videoInput', '视频输入')} value={videoInputTokens} /> : null}
        {cacheHit.hasCacheUsageTelemetry ? (
          <>
            <TokenStatsRow label={t('tokenPopup.cacheRead', '缓存命中')} value={cacheReadTokens} tone="accent" />
            <TokenStatsRow label={t('tokenPopup.cacheWrite', '缓存写入')} value={cacheWriteTokens} tone="accent" />
          </>
        ) : null}
      </TokenStatsSection>
      <TokenStatsSection title={t('tokenPopup.output', '输出')}>
        <TokenStatsRow label={t('tokenPopup.completion', '回复')} value={completionTokens} />
        {reasoningTokens > 0 ? <TokenStatsRow label={t('tokenPopup.reasoning', '推理')} value={reasoningTokens} /> : null}
      </TokenStatsSection>
      {webSearchToolUsage > 0 || webSearchPageUsage > 0 ? (
        <TokenStatsSection title={t('tokenPopup.webSearch', '联网搜索')}>
          {webSearchToolUsage > 0 ? <TokenStatsRow label={t('tokenPopup.webSearchCalls', '调用次数')} value={webSearchToolUsage} tone="accent" /> : null}
          {webSearchPageUsage > 0 ? <TokenStatsRow label={t('tokenPopup.webSearchPages', '返回页面')} value={webSearchPageUsage} tone="accent" /> : null}
        </TokenStatsSection>
      ) : null}
      <TokenStatsSection
        title={t('tokenPopup.total', '总计')}
        emphasized
        trailing={(
          <span class="text-lg font-black tabular-nums oh-text-primary">
            <RollingText text={totalTokens.toLocaleString()} />
          </span>
        )}
      />
      <ContextUsageOverview
        usage={contextUsage}
        windowUsage={contextWindowUsage}
        canCompact={canCompact}
        compacting={compacting}
        onCompact={onCompact}
      />
      {cacheHit.hasCacheHitMetrics ? (
        <CacheHitTrendChart
          points={trendData?.points ?? []}
          averageRatio={trendData?.averageRatio ?? cacheHitRatio / 100}
          fallbackComposition={{
            cacheReadTokens,
            cacheWriteTokens,
            uncachedPromptTokens,
          }}
          claudeStyle={claudeStyle}
          height={136}
          displayMode={trendDisplayMode}
          onDisplayModeChange={onTrendDisplayModeChange}
          onPointSelected={onPointSelected}
          t={t}
        />
      ) : null}
      <TokenStatsSection title={t('tokenPopup.session', '会话累计')}>
        <TokenStatsRow label={t('tokenPopup.messages', '消息总数')} value={totalMessageCount} />
        <TokenStatsRow label={t('tokenPopup.promptBuilds', '提示词构建')} value={promptBuildCount} />
        <TokenStatsRow label={t('tokenPopup.promptChars', '提示词字符')} value={totalPromptCharacters} />
      </TokenStatsSection>
    </>
  );
}

function SessionTokenStatsDialog({
  detail,
  modelKey,
  responseRunning,
  onClose,
  onCompacted,
  onPointSelected,
}: {
  detail: SessionDetailResponse;
  modelKey: string;
  responseRunning: boolean;
  onClose: () => void;
  onCompacted: () => void;
  onPointSelected: (point: CacheHitTrendPoint) => void;
}) {
  const [trendDisplayMode, setTrendDisplayMode] = useState<CacheHitDisplayMode>(DEFAULT_CACHE_HIT_DISPLAY_MODE);
  const [compacting, setCompacting] = useState(false);
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const session = detail.session;
  const tokenStats = useMemo(() => buildSessionTokenStatsViewModel(session), [session]);
  const canCompact = tokenStats.contextWindowUsage.canManuallyCompact && !responseRunning;

  async function handleCompact() {
    if (!canCompact || compacting) return;
    setCompacting(true);
    try {
      const response = await compactSession(session.id, { modelKey });
      showSnackbar(compactStatusMessage(response.status, response.retry_after_ms), {
        tone: response.ok ? 'success' : 'error',
      });
      if (response.ok) onCompacted();
    } catch (error) {
      showSnackbar(
        t('contextStats.error', '压缩请求失败：{detail}').replace(
          '{detail}',
          error instanceof Error ? error.message : String(error),
        ),
        { tone: 'error' },
      );
    } finally {
      setCompacting(false);
    }
  }
  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayTone: 'soft',
        panelClassName: 'w-full max-w-md min-h-0 rounded-m3-xl p-5 flex flex-col overflow-hidden',
        panelSurface: {
          maxHeight: TOKEN_STATS_DIALOG_MAX_HEIGHT,
        },
      })}
      ariaLabel={t('topbar.tokens', 'Token 统计')}
    >
      <header class="mb-4 flex shrink-0 items-start justify-between gap-3">
        <div class="min-w-0">
          <h2 class="text-base font-semibold">{t('topbar.tokens', 'Token 统计')}</h2>
          <p class="mt-0.5 truncate text-xs oh-text-muted">
            {session.title || t('sessions.untitled', '未命名会话')}
          </p>
        </div>
        <DialogActionButton onClick={requestClose} tone="ghost">
          {t('common.close', '关闭')}
        </DialogActionButton>
      </header>
      <div class="min-h-0 flex-1 space-y-4 overflow-y-auto" style={{ scrollbarWidth: 'thin', overscrollBehavior: 'contain' }}>
        <SessionTokenStatsContent
          stats={tokenStats}
          trendDisplayMode={trendDisplayMode}
          onTrendDisplayModeChange={setTrendDisplayMode}
          canCompact={canCompact}
          compacting={compacting}
          onCompact={() => void handleCompact()}
          onPointSelected={(point) => {
            requestClose();
            onPointSelected(point);
          }}
        />
      </div>
    </DialogFrame>
  );
}

function compactStatusMessage(status: CompactSessionStatus, retryAfterMs?: number): string {
  switch (status) {
    case 'success':
      return t('contextStats.success', '已生成压缩检查点。');
    case 'cooldown': {
      const secs = Math.max(1, Math.round((retryAfterMs ?? 30000) / 1000));
      return t('contextStats.cooldown', '刚刚已经压缩过，约 {secs} 秒后再试。').replace('{secs}', String(secs));
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

function TokenStatsSection({
  title,
  children,
  trailing,
  emphasized = false,
}: {
  title: string;
  children?: ComponentChildren;
  trailing?: ComponentChildren;
  emphasized?: boolean;
}) {
  return (
    <section
      class="rounded-m3-md p-3"
      style={{
        background: emphasized
          ? 'color-mix(in srgb, var(--m3-primary-container) 64%, var(--m3-surface-container-low))'
          : 'var(--m3-surface-container-low)',
        border: emphasized
          ? '1px solid color-mix(in srgb, var(--m3-primary) 30%, transparent)'
          : '1px solid color-mix(in srgb, var(--m3-outline-variant) 72%, transparent)',
      }}
    >
      <div class="flex items-center justify-between gap-3">
        <h3 class="text-xs font-extrabold oh-text-body">
          {title}
        </h3>
        {trailing}
      </div>
      {children ? <div class="mt-2 space-y-1.5">{children}</div> : null}
    </section>
  );
}

function TokenStatsRow({ label, value, tone = 'neutral' }: { label: string; value: number; tone?: 'neutral' | 'accent' }) {
  const accent = tone === 'accent';
  return (
    <div
      class="flex items-center justify-between gap-3 rounded-m3-sm px-2.5 py-2 text-sm hover:-translate-y-px"
      style={{
        background: accent
          ? 'color-mix(in srgb, var(--m3-primary) 7%, transparent)'
          : 'color-mix(in srgb, var(--m3-surface) 58%, transparent)',
        border: accent
          ? '1px solid color-mix(in srgb, var(--m3-primary) 18%, transparent)'
          : '1px solid color-mix(in srgb, var(--m3-outline-variant) 42%, transparent)',
        transition: 'transform var(--oh-dialog-duration) var(--oh-dialog-curve), border-color var(--oh-dialog-duration) var(--oh-dialog-curve)',
      }}
    >
      <span class="text-xs font-medium oh-text-muted">{label}</span>
      <span class="font-bold tabular-nums" style={{ color: accent ? 'var(--m3-primary)' : 'var(--m3-on-surface)' }}>
        <RollingText text={value.toLocaleString()} />
      </span>
    </div>
  );
}

function readStatNumber(value: unknown, fallback: unknown): number {
  const safeFallback = nonNegativeIntegerFromUnknown(fallback);
  return nonNegativeIntegerFromUnknown(value, safeFallback);
}

function usesClaudeStyleCacheMath(protocol: unknown): boolean {
  const normalized = String(protocol ?? '')
    .trim()
    .toLowerCase();
  return normalized === 'claude';
}

const CACHE_HIT_RATIO_PERCENT_EPSILON = 0.0001;

function cacheHitRatioPercent(value: number): number {
  if (value <= CACHE_HIT_RATIO_PERCENT_EPSILON) return 0;
  return Math.round(clampNumber(value * 100, 0, 100));
}

function shouldShowSessionCacheHitMetrics({
  cacheReadTokens,
  cacheWriteTokens,
  trendPointCount,
  hasCacheUsageTelemetry,
  hasCacheHitRatio,
}: {
  cacheReadTokens: number;
  cacheWriteTokens: number;
  trendPointCount: number;
  hasCacheUsageTelemetry: boolean;
  hasCacheHitRatio: boolean;
}): boolean {
  return hasCacheUsageTelemetry ||
    hasCacheHitRatio ||
    cacheReadTokens > 0 ||
    cacheWriteTokens > 0 ||
    trendPointCount > 0;
}

interface SessionCacheHitDisplay {
  cacheReadTokens: number;
  cacheWriteTokens: number;
  uncachedPromptTokens: number;
  cacheHitRatio: number;
  hasCacheUsageTelemetry: boolean;
  hasCacheHitMetrics: boolean;
  claudeStyle: boolean;
  trendData: {
    points: CacheHitTrendPoint[];
    averageRatio: number;
  } | null;
}

function fallbackCacheEligiblePromptTokens(
  stats: Record<string, unknown>,
  fallbackPromptTokens: unknown,
): number {
  const total = readStatNumber(stats['total_prompt_tokens'], fallbackPromptTokens);
  const first = readStatNumber(stats['first_prompt_tokens'], 0);
  return total - Math.min(total, first);
}

function resolveSessionCacheHitRatio(
  session: SessionSummary,
  stats: Record<string, unknown>,
): number {
  const cacheReadTokens = readStatNumber(stats['cache_read_tokens'], 0);
  const cacheWriteTokens = readStatNumber(stats['cache_creation_tokens'], 0);
  const promptTokens = fallbackCacheEligiblePromptTokens(stats, session.total_prompt_tokens);
  const claudeStyle = usesClaudeStyleCacheMath(session.last_used_model_protocol);
  const denominator = claudeStyle
    ? promptTokens + cacheReadTokens + cacheWriteTokens
    : Math.max(promptTokens, cacheReadTokens + cacheWriteTokens);
  const fallbackRatio = denominator > 0 ? cacheReadTokens / denominator : 0;
  const persistedRatio = stats['cache_hit_ratio'];
  return clampNumber(
    persistedRatio == null ? fallbackRatio : finiteNumberFromUnknown(persistedRatio, fallbackRatio),
    0,
    1,
  );
}

function buildSessionCacheHitDisplay(
  session: SessionSummary,
  stats: Record<string, unknown>,
): SessionCacheHitDisplay {
  const cacheReadTokens = readStatNumber(stats['cache_read_tokens'], 0);
  const cacheWriteTokens = readStatNumber(stats['cache_creation_tokens'], 0);
  const eligiblePromptTokens = fallbackCacheEligiblePromptTokens(stats, session.total_prompt_tokens);
  const backendHitRatio = resolveSessionCacheHitRatio(session, stats);
  const backendTrendPoints = (stats['cache_hit_trend_points'] ?? []) as SessionCacheHitTrendPoint[] | undefined;
  const claudeStyle = usesClaudeStyleCacheMath(session.last_used_model_protocol);
  const trendPoints = backendTrendPoints?.map((p) => ({
    turnIndex: p.turn_index,
    hitRatio: p.hit_ratio,
    promptTokens: p.prompt_tokens,
    cacheReadTokens: p.cache_read_tokens,
    cacheWriteTokens: p.cache_write_tokens,
    starterMessageId: p.starter_message_id ?? null,
    starterMessageKind: p.starter_message_kind ?? null,
    starterOrigin: p.starter_origin ?? null,
    anchorMessageId: p.anchor_message_id ?? null,
    idleGapSeconds: p.idle_gap_seconds ?? null,
  })) ?? [];
  const defaultDisplay = trendPoints.length > 0
    ? cacheHitDisplayData({
      points: trendPoints,
      displayMode: DEFAULT_CACHE_HIT_DISPLAY_MODE,
      claudeStyle,
      fallbackAverageRatio: backendHitRatio,
    })
    : null;
  const cacheHitRatio = cacheHitRatioPercent(
    defaultDisplay?.averageRatio ?? backendHitRatio,
  );
  const trendData = trendPoints.length > 0
    ? {
      points: trendPoints,
      averageRatio: defaultDisplay?.averageRatio ?? backendHitRatio,
    }
    : null;
  const uncachedPromptTokens = defaultDisplay?.averagePointCount
    ? defaultDisplay.uncachedPromptTokens
    : claudeStyle
    ? eligiblePromptTokens
    : Math.max(0, eligiblePromptTokens - cacheReadTokens - cacheWriteTokens);
  const hasCacheUsageTelemetry =
    stats['cache_read_tokens'] != null ||
    stats['cache_creation_tokens'] != null ||
    trendPoints.length > 0;
  const hasCacheHitMetrics = shouldShowSessionCacheHitMetrics({
    cacheReadTokens,
    cacheWriteTokens,
    trendPointCount: trendData?.points.length ?? 0,
    hasCacheUsageTelemetry,
    hasCacheHitRatio: stats['cache_hit_ratio'] != null,
  });
  return {
    cacheReadTokens,
    cacheWriteTokens,
    uncachedPromptTokens,
    cacheHitRatio,
    hasCacheUsageTelemetry,
    hasCacheHitMetrics,
    claudeStyle,
    trendData,
  };
}

function formatDialogDate(value?: string | null): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function mcpLazyLoadingCapsule(notices: string[]): SessionToolbarCapsule | null {
  const pattern = /MCP tool lazy loading active.*?(\d+)\s+of\s+(\d+)\s+MCP tool/i;
  for (const notice of notices) {
    const match = pattern.exec(notice);
    if (!match) continue;
    const deferred = Number.parseInt(match[1] ?? '', 10);
    const total = Number.parseInt(match[2] ?? '', 10);
    if (!Number.isFinite(deferred) || !Number.isFinite(total) || total <= 0) continue;
    const loaded = clampNumber(total - deferred, 0, total);
    return {
      key: 'mcp-lazy-loading',
      icon: 'runtime',
      label: t('topbar.mcpLazyLoading', 'MCP {loaded}/{total}').replace('{loaded}', String(loaded)).replace('{total}', String(total)),
      title: notice,
    };
  }
  return null;
}

function metadataValue(value: unknown): string {
  if (value == null || value === '') return '—';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return stringifyJsonSafely(value, 2) ?? String(value);
}

function metadataFieldLabel(field: string): string {
  const labels: Record<string, string> = {
    session_id: '会话 ID',
    template: '模板',
    created_at: '创建时间',
    updated_at: '更新时间',
    last_model: '最近模型',
    auto_title_acquired: '标题获取状态',
    auto_title_retry_count: '标题重试次数',
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

function SessionMetadataDialog({ detail, messages, onClose }: { detail: SessionDetailResponse; messages: SessionMessage[]; onClose: () => void }) {
  const session = detail.session;
  const [metadataTrendDisplayMode, setMetadataTrendDisplayMode] = useState<CacheHitDisplayMode>(DEFAULT_CACHE_HIT_DISPLAY_MODE);
  const { closing, requestClose } = useDialogExitMotion(onClose);

  const stats = recordFromUnknown(session.statistics);
  const cacheHit = buildSessionCacheHitDisplay(session, stats);
  const metadata = recordFromUnknown(session.metadata);
  const machineTerminalMetadata = recordFromUnknown(metadata['machine_terminal']);
  const environment = recordFromUnknown(session.environment);
  const lastPromptMetadata = recordFromUnknown(session.last_prompt_metadata);
  const latestCompressionPoint = recordFromUnknown(session.latest_compression_point);
  const latestCompressionPointMetadata = recordFromUnknown(latestCompressionPoint['metadata']);
  const rehydration = recordFromUnknown(lastPromptMetadata['post_compact_rehydration']);
  const hasPromptMetadata = Object.keys(lastPromptMetadata).length > 0;
  const runtimeToolNames = stringListFromUnknown(lastPromptMetadata['current_tool_names']);
  const planModePlanningToolNames = stringListFromUnknown(lastPromptMetadata['plan_mode_planning_tool_names']);
  const runtimeNotices = stringListFromUnknown(lastPromptMetadata['runtime_tool_catalog_notices']);
  const runtimeToolCount = Math.max(integerFromUnknown(lastPromptMetadata['current_tool_count']), runtimeToolNames.length);
  const runtimeStale = lastPromptMetadata['runtime_tool_catalog_stale'] === true;
  const awaitingPlanApproval = lastPromptMetadata['awaiting_plan_approval'] === true || session.awaiting_plan_approval === true;
  const exitPlanModeAvailable = lastPromptMetadata['plan_mode_exit_plan_mode_available'] === true;
  const planRecoveryRequired = lastPromptMetadata['plan_mode_recovery_inspection_required'] === true || lastPromptMetadata['plan_recovery_required'] === true;
  const planExecutionApproved = lastPromptMetadata['plan_mode_execution_approved_for_send'] === true;
  const hasActivePlanState = Boolean(session.todo_items?.length) || Boolean((session.pending_plan ?? '').trim());
  let gateReason = stringFromUnknown(lastPromptMetadata['runtime_tool_gate_reason']);
  if (!gateReason) {
    gateReason = awaitingPlanApproval ? 'awaiting_plan_approval' : session.mode !== 'plan' ? (hasPromptMetadata ? 'chat_mode' : 'no_runtime_snapshot') : planRecoveryRequired ? 'plan_mode_recovery_inspection' : planExecutionApproved ? 'plan_mode_execution' : hasActivePlanState ? 'plan_mode_planning_with_exit_allowed' : 'plan_mode_planning_only';
  }
  const runtimeModeLabel = session.mode !== 'plan' ? '聊天模式' : awaitingPlanApproval ? '计划待审' : planRecoveryRequired ? '计划审阅' : planExecutionApproved ? '计划执行' : hasActivePlanState ? '计划草拟' : '计划模式';
  const toolCatalogState = !hasPromptMetadata ? '暂无运行时快照' : runtimeStale ? '工具目录待刷新' : '工具目录已同步';
  const promptBudgetTokens = integerFromUnknown(lastPromptMetadata['context_budget_estimated_prompt_tokens']);
  const contextStatus = stringFromUnknown(lastPromptMetadata['context_budget_status']) || 'unknown';
  const contextStatusLabel = contextStatus === 'critical' ? '危险' : contextStatus === 'auto_compact' ? '需压缩' : contextStatus === 'warning' ? '偏高' : contextStatus === 'ok' ? '正常' : '未知';
  const usagePercent = integerFromUnknown(lastPromptMetadata['context_budget_usage_percent']);
  const usageValue = clampNumber(usagePercent, 0, 100);
  const sidecarPath = stringFromUnknown(rehydration['session_memory_sidecar_path']);
  const sidecarPresent = rehydration['session_memory_sidecar_present'] === true;
  const compressionRestored = latestCompressionPointMetadata['restored_from_compact_memory_sidecar'] === true;
  const hasCompressionPoint = Boolean(stringFromUnknown(latestCompressionPoint['id']));
  const sidecarStatus = !hasCompressionPoint ? '未生成' : compressionRestored ? '已恢复' : sidecarPresent ? '已登记' : '等待下次 Prompt 刷新';
  const visibleMetadataEntries = Object.entries(metadata).filter(([key]) => {
    if (key === 'machine_terminal') return false;
    if (session.template_id === 'harness_engineering' && key === 'harness_config') return false;
    if (session.template_id === 'programming_expert' && key === 'programming_expert_config') return false;
    if (session.template_id === 'web_reverse_expert' && key === 'web_reverse_config') return false;
    if (session.template_id === 'android_reverse_expert' && key === 'android_reverse_config') return false;
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
      <div class="text-sm font-semibold oh-text-muted">
        {label}
      </div>
      <div class="mt-1.5 text-xl font-extrabold tabular-nums">{value}</div>
    </div>
  );
  const Chip = ({ label }: { label: string }) => (
    <span
      class="inline-flex rounded-full px-2.5 py-1.5 text-xs font-bold"
      style={{
        background: 'var(--m3-surface-container-highest)',
        color: 'var(--m3-on-surface)',
      }}
    >
      {label}
    </span>
  );
  const EntryRow = ({ label, value }: { label: string; value: ComponentChildren }) => (
    <div class="mb-2.5 min-w-0">
      <div class="text-xs font-bold oh-text-muted">
        {label}
      </div>
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
      style={{
        background: 'var(--m3-surface)',
        border: '1px solid var(--m3-outline-variant)',
      }}
    >
      {JSON.stringify(content ?? {}, null, 2)}
    </pre>
  );
  const machineMetadataFieldTitle = (key: string): string => {
    const labels: Record<string, string> = {
      schema_version: 'Schema 版本',
      template_id: '模板 ID',
      surface: '渲染面板',
      workflow: '工作流',
      session_id: '会话 ID',
      terminal_workspace_id: '终端工作区 ID',
      active_terminal_id: '当前终端 ID',
      default_working_directory: '默认工作目录',
      created_at: '创建时间',
      updated_at: '更新时间',
      terminal_defaults: '终端默认参数',
      capabilities: '终端能力',
      ui: '界面特性',
      tool_names: '内建终端工具',
      runtime: '运行时',
      status: '状态',
      terminal_count: '终端数量',
      active_terminal: '当前终端',
      terminals: '终端列表',
      terminal_id: '终端 ID',
      identity: '终端身份',
      shell: 'Shell',
      working_directory: '工作目录',
      rows: '行数',
      columns: '列数',
      max_rows: '最大行数',
      max_columns: '最大列数',
      scrollback_lines: '回滚行数',
      command_timeout_ms: '命令超时',
      command_poll_interval_ms: '命令轮询间隔',
      max_retained_output_characters: '保留输出上限',
      max_tool_output_characters: '工具输出上限',
      output_characters: '输出字符数',
      started_at: '启动时间',
      pid: '进程 ID',
      exit_code: '退出码',
      error_message: '错误信息',
      panel: '面板位置',
      auto_scroll_to_bottom: '自动滚动到底部',
      terminal_tabs: '终端标签',
      status_bar: '状态栏',
      metadata_bar: '元数据栏',
      read: '读取终端',
      write: '写入终端',
      execute: '执行命令',
      control: '控制终端',
      resize: '调整尺寸',
      multiple_terminals: '多终端',
      duplicate_terminal: '复制终端',
      interactive_input: '交互输入',
      ansi_output: 'ANSI 输出',
      shell_completion: 'Shell 补全',
      formatted_command_output: '格式化命令输出',
      marker_isolated_exec: '分隔标记执行',
      status_inspection: '状态查看',
      environment_metadata: '环境元数据',
      native_keybindings: '原生快捷键',
      smooth_auto_scroll: '丝滑自动滚动',
    };
    const normalized = key.trim();
    if (!normalized) return '—';
    if (labels[normalized]) return labels[normalized];
    return normalized
      .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
      .split(/[_\-\s]+/)
      .filter(Boolean)
      .map((part) => part.length <= 1 ? part.toUpperCase() : `${part[0]?.toUpperCase() ?? ''}${part.slice(1).toLowerCase()}`)
      .join(' ') || normalized;
  };
  const machineMetadataCleanString = (value: unknown): string | null => {
    const text = stringFromUnknown(value).trim();
    return text.length > 0 ? text : null;
  };
  const terminalSizeText = (terminal: Record<string, unknown>): string => {
    const columns = integerFromUnknown(terminal['columns']);
    const rows = integerFromUnknown(terminal['rows']);
    return columns > 0 && rows > 0 ? `${columns}×${rows}` : '—';
  };
  const machineTerminalStatusLabel = (status: string | null): string => {
    switch (status) {
      case 'running':
        return '运行中';
      case 'starting':
        return '启动中';
      case 'stopped':
        return '已停止';
      case 'failed':
        return '异常';
      case 'idle':
        return '空闲';
      default:
        return '未知';
    }
  };
  const machineTerminalStatusColor = (status: string | null): string => {
    switch (status) {
      case 'running':
        return 'var(--m3-primary)';
      case 'starting':
        return 'var(--m3-tertiary)';
      case 'failed':
        return 'var(--m3-error)';
      case 'idle':
        return 'var(--m3-secondary)';
      default:
        return 'var(--m3-outline)';
    }
  };
  const isShortMetadataScalar = (value: unknown): boolean => {
    if (value == null || typeof value === 'number' || typeof value === 'boolean') return true;
    return typeof value === 'string' && value.trim().length <= 48 && !value.includes('\n');
  };
  const GroupLabel = ({ label, detail }: { label: string; detail?: string }) => (
    <div>
      <div class="text-sm font-extrabold">{label}</div>
      {detail ? (
        <div class="mt-1 text-xs leading-relaxed oh-text-muted">
          {detail}
        </div>
      ) : null}
    </div>
  );
  const InfoTile = ({ icon, label, value, color }: { icon: ComposerIconName; label: string; value: string; color: string }) => (
    <div
      class="flex items-center gap-2.5 rounded-m3-sm p-3"
      style={{
        width: '188px',
        background: `color-mix(in srgb, ${color} 10%, transparent)`,
        border: `1px solid color-mix(in srgb, ${color} 22%, transparent)`,
      }}
    >
      <div
        class="flex h-8 w-8 shrink-0 items-center justify-center rounded-m3-sm"
        style={{ color, background: `color-mix(in srgb, ${color} 14%, transparent)` }}
      >
        <ComposerIcon name={icon} size={16} />
      </div>
      <div class="min-w-0">
        <div class="truncate text-xs font-bold oh-text-muted">
          {label}
        </div>
        <div class="mt-1 truncate text-sm font-extrabold tabular-nums">{value}</div>
      </div>
    </div>
  );
  const CapabilityChip = ({ label, enabled }: { label: string; enabled: boolean }) => {
    const color = enabled ? 'var(--m3-primary)' : 'var(--m3-outline)';
    return (
      <span
        class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs font-bold"
        style={{
          color: enabled ? 'var(--m3-on-surface)' : 'var(--m3-on-surface-variant)',
          background: `color-mix(in srgb, ${color} ${enabled ? 12 : 8}%, transparent)`,
          border: `1px solid color-mix(in srgb, ${color} 22%, transparent)`,
        }}
      >
        <span style={{ color }}>{enabled ? '✓' : '–'}</span>
        {label}
      </span>
    );
  };
  const renderStructuredMetadataNode = (value: unknown, depth = 0): ComponentChildren => {
    if (value != null && typeof value === 'object' && !Array.isArray(value)) {
      const entries = Object.entries(recordFromUnknown(value));
      if (entries.length === 0) {
        return <span class="text-sm oh-text-muted">—</span>;
      }
      if (depth >= 3) return <JsonPanel content={value} />;
      return (
        <div
          class="rounded-m3-sm p-3 pb-1"
          style={{
            background: 'var(--m3-surface)',
            border: '1px solid var(--m3-outline-variant)',
          }}
        >
          {entries.map(([key, item]) => {
            const isNested = item != null && typeof item === 'object';
            return isNested ? (
              <div key={key} class="mb-3">
                <GroupLabel label={machineMetadataFieldTitle(key)} />
                <div class="mt-2">{renderStructuredMetadataNode(item, depth + 1)}</div>
              </div>
            ) : (
              <EntryRow key={key} label={machineMetadataFieldTitle(key)} value={metadataValue(item)} />
            );
          })}
        </div>
      );
    }
    if (Array.isArray(value)) {
      if (value.length === 0) {
        return <span class="text-sm oh-text-muted">—</span>;
      }
      if (value.every(isShortMetadataScalar) && value.length <= 24) {
        return (
          <div class="flex flex-wrap gap-2">
            {value.map((item, index) => <Chip key={`${metadataValue(item)}-${index}`} label={metadataValue(item)} />)}
          </div>
        );
      }
      if (depth >= 3) return <JsonPanel content={value} />;
      const visibleItems = value.slice(0, 40);
      return (
        <div class="flex flex-col gap-2.5">
          {visibleItems.map((item, index) => (
            <div
              key={index}
              class="rounded-m3-sm p-3"
              style={{
                background: 'var(--m3-surface)',
                border: '1px solid var(--m3-outline-variant)',
              }}
            >
              <div class="mb-2 text-xs font-extrabold oh-text-muted">
                #{index + 1}
              </div>
              {isShortMetadataScalar(item) || typeof item === 'string' ? (
                <div class="text-sm leading-relaxed whitespace-pre-wrap break-words select-text">{metadataValue(item)}</div>
              ) : (
                renderStructuredMetadataNode(item, depth + 1)
              )}
            </div>
          ))}
          {value.length > visibleItems.length ? (
            <div class="text-xs oh-text-muted">
              还有 {value.length - visibleItems.length} 项未展示，请复制完整元数据查看。
            </div>
          ) : null}
        </div>
      );
    }
    return <span class="text-sm leading-relaxed whitespace-pre-wrap break-words select-text">{metadataValue(value)}</span>;
  };
  const StructuredValue = ({ label, value }: { label: string; value: unknown }) => (
    <div class="mb-3 min-w-0">
      <div class="text-xs font-bold oh-text-muted">
        {machineMetadataFieldTitle(label)}
      </div>
      <div class="mt-2">{renderStructuredMetadataNode(value)}</div>
    </div>
  );
  const MachineTerminalCard = ({ index, terminal }: { index: number; terminal: Record<string, unknown> }) => {
    const status = machineMetadataCleanString(terminal['status']);
    const color = machineTerminalStatusColor(status);
    const id = machineMetadataCleanString(terminal['terminal_id']) ?? '—';
    const identity = machineMetadataCleanString(terminal['identity']) ?? '—';
    const size = terminalSizeText(terminal);
    const outputCharacters = integerFromUnknown(terminal['output_characters']);
    return (
      <div
        class="rounded-m3-sm p-3"
        style={{
          background: 'var(--m3-surface)',
          border: '1px solid var(--m3-outline-variant)',
        }}
      >
        <div class="flex flex-wrap items-center gap-2">
          <div class="text-sm font-extrabold">终端 #{index}</div>
          <span
            class="rounded-full px-2.5 py-1 text-xs font-extrabold"
            style={{ color, background: `color-mix(in srgb, ${color} 13%, transparent)` }}
          >
            {machineTerminalStatusLabel(status)}
          </span>
        </div>
        <div class="mt-3 flex flex-wrap gap-2">
          <Chip label={`ID ${id}`} />
          <Chip label={identity} />
          <Chip label={size === '—' ? '尺寸 —' : size} />
          <Chip label={`输出 ${outputCharacters} 字符`} />
        </div>
        <div class="mt-3">
          <EntryRow label={machineMetadataFieldTitle('shell')} value={metadataValue(terminal['shell'])} />
          <EntryRow label={machineMetadataFieldTitle('working_directory')} value={metadataValue(terminal['working_directory'])} />
          <EntryRow label={machineMetadataFieldTitle('started_at')} value={metadataValue(terminal['started_at'])} />
          <EntryRow label={machineMetadataFieldTitle('updated_at')} value={metadataValue(terminal['updated_at'])} />
          {Object.prototype.hasOwnProperty.call(terminal, 'pid') ? <EntryRow label={machineMetadataFieldTitle('pid')} value={metadataValue(terminal['pid'])} /> : null}
          {Object.prototype.hasOwnProperty.call(terminal, 'exit_code') ? <EntryRow label={machineMetadataFieldTitle('exit_code')} value={metadataValue(terminal['exit_code'])} /> : null}
          {machineMetadataCleanString(terminal['error_message']) ? <EntryRow label={machineMetadataFieldTitle('error_message')} value={metadataValue(terminal['error_message'])} /> : null}
        </div>
      </div>
    );
  };
  const renderMachineTerminalMetadata = () => {
    const defaults = recordFromUnknown(machineTerminalMetadata['terminal_defaults']);
    const capabilities = recordFromUnknown(machineTerminalMetadata['capabilities']);
    const ui = recordFromUnknown(machineTerminalMetadata['ui']);
    const runtime = recordFromUnknown(machineTerminalMetadata['runtime']);
    const activeTerminal = recordFromUnknown(runtime['active_terminal']);
    const terminals = arrayFromUnknown(runtime['terminals']).map(recordFromUnknown).filter((item) => Object.keys(item).length > 0);
    const toolNames = stringListFromUnknown(machineTerminalMetadata['tool_names']);
    const status = machineMetadataCleanString(runtime['status']);
    const activeTerminalId = machineMetadataCleanString(runtime['active_terminal_id']) ?? machineMetadataCleanString(machineTerminalMetadata['active_terminal_id']);
    const terminalCount = Math.max(integerFromUnknown(runtime['terminal_count']), terminals.length);
    return (
      <Section title="机器终端元数据">
        <div class="mb-3 flex flex-wrap gap-2.5">
          <InfoTile icon="mode" label="运行状态" value={machineTerminalStatusLabel(status)} color={machineTerminalStatusColor(status)} />
          <InfoTile icon="plus" label="终端数量" value={`${terminalCount}`} color="var(--m3-primary)" />
          <InfoTile icon="permission" label="当前终端" value={activeTerminalId ?? '—'} color="var(--m3-tertiary)" />
          <InfoTile icon="refresh" label="终端尺寸" value={terminalSizeText(activeTerminal)} color="var(--m3-secondary)" />
        </div>
        <EntryRow label="工作流" value={metadataValue(machineTerminalMetadata['workflow'])} />
        <EntryRow label="渲染面板" value={metadataValue(machineTerminalMetadata['surface'])} />
        <EntryRow label="工作区 ID" value={metadataValue(machineTerminalMetadata['terminal_workspace_id'])} />
        <EntryRow label="默认工作目录" value={metadataValue(machineTerminalMetadata['default_working_directory'])} />
        <EntryRow label="创建时间" value={metadataValue(machineTerminalMetadata['created_at'])} />
        <EntryRow label="更新时间" value={metadataValue(machineTerminalMetadata['updated_at'])} />
        {Object.keys(activeTerminal).length > 0 ? <StructuredValue label="当前终端状态" value={activeTerminal} /> : null}
        {Object.keys(defaults).length > 0 ? <StructuredValue label="终端默认参数" value={defaults} /> : null}
        {Object.keys(capabilities).length > 0 ? (
          <div class="mb-3">
            <GroupLabel label="终端能力" detail="AI 与用户在机器专家线程内可用的终端能力" />
            <div class="mt-2 flex flex-wrap gap-2">
              {Object.entries(capabilities).map(([key, value]) => (
                <CapabilityChip key={key} label={machineMetadataFieldTitle(key)} enabled={value === true} />
              ))}
            </div>
          </div>
        ) : null}
        {Object.keys(ui).length > 0 ? <StructuredValue label="界面特性" value={ui} /> : null}
        {toolNames.length > 0 ? (
          <div class="mb-3">
            <GroupLabel label="内建终端工具" detail="仅机器专家模板开放" />
            <div class="mt-2 flex flex-wrap gap-2">
              {toolNames.map((toolName) => <Chip key={toolName} label={toolName} />)}
            </div>
          </div>
        ) : null}
        {terminals.length > 0 ? (
          <div>
            <GroupLabel label="运行中终端" detail="轻量状态摘要，不包含终端输出正文" />
            <div class="mt-2 flex flex-col gap-2.5">
              {terminals.map((terminal, index) => <MachineTerminalCard key={stringFromUnknown(terminal['terminal_id']) || index} index={index + 1} terminal={terminal} />)}
            </div>
          </div>
        ) : null}
      </Section>
    );
  };

  const renderCacheHitPanel = (withTopMargin: boolean) => {
    if (!cacheHit.hasCacheHitMetrics) {
      return null;
    }
    return (
      <div class={withTopMargin ? 'mt-4' : ''}>
        <CacheHitTrendChart
          points={cacheHit.trendData?.points ?? []}
          averageRatio={cacheHit.trendData?.averageRatio ?? cacheHit.cacheHitRatio / 100}
          fallbackComposition={{
            cacheReadTokens: cacheHit.cacheReadTokens,
            cacheWriteTokens: cacheHit.cacheWriteTokens,
            uncachedPromptTokens: cacheHit.uncachedPromptTokens,
          }}
          claudeStyle={cacheHit.claudeStyle}
          height={136}
          displayMode={metadataTrendDisplayMode}
          onDisplayModeChange={setMetadataTrendDisplayMode}
          t={t}
        />
      </div>
    );
  };

  const renderProgrammingConfig = () => {
    const config = recordFromUnknown(metadata['programming_expert_config']);
    return (
      <Section title="编程专家配置">
        {Object.keys(config).length === 0 ? (
          <p class="text-sm oh-text-muted">
            配置数据尚未写入会话元数据。
          </p>
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

  const renderHarnessConfig = () => {
    const config = recordFromUnknown(metadata['harness_config']);
    const roleKeys = ['profiler', 'reader', 'planner', 'implementer', 'reviewer'];
    return (
      <Section title="Harness Engineering 配置">
        {Object.keys(config).length === 0 ? (
          <p class="text-sm oh-text-muted">
            配置数据尚未写入会话元数据（该会话可能创建于功能推出之前）。
          </p>
        ) : (
          <>
            <EntryRow label="任务描述" value={metadataValue(config['task'])} />
            <EntryRow label="工作目录" value={metadataValue(config['working_directory'])} />
            <EntryRow label="持久化目录" value={metadataValue(config['persistence_directory'])} />
            <EntryRow label="首次运行" value={config['first_run'] === true ? '是（含探档阶段）' : '否（增量运行）'} />
            <div class="mt-3 mb-2 text-sm font-extrabold">角色配置</div>
            {roleKeys.map((key) => {
              const role = recordFromUnknown(config[key]);
              const cli = stringFromUnknown(role['cli_name']);
              const model = stringFromUnknown(role['model_id']);
              return <EntryRow key={key} label={key} value={cli || model ? `${cli || '-'} · ${model || '-'}` : '未配置'} />;
            })}
          </>
        )}
      </Section>
    );
  };

  const renderAndroidReverseConfig = () => {
    const config = recordFromUnknown(metadata['android_reverse_config']);
    const keywords = stringListFromUnknown(config['keywords']);
    const analysisMode = stringFromUnknown(config['analysis_mode']);
    const analysisModeLabel = analysisMode === 'static_first'
      ? '静态优先'
      : analysisMode === 'dynamic_first'
        ? '动态验证优先'
        : analysisMode === 'balanced'
          ? '均衡分析'
          : metadataValue(analysisMode);
    return (
      <Section title="Android 逆向配置">
        {Object.keys(config).length === 0 ? (
          <p class="text-sm oh-text-muted">
            配置数据尚未写入会话元数据。
          </p>
        ) : (
          <>
            <EntryRow label="逆向目标" value={metadataValue(config['objective'])} />
            <EntryRow label="目标包名" value={metadataValue(config['package_name'])} />
            <EntryRow label="APK 路径" value={metadataValue(config['apk_path'])} />
            <EntryRow label="设备序列号" value={metadataValue(config['device_serial'] ?? '自动选择唯一在线设备')} />
            <EntryRow label="分析模式" value={analysisModeLabel} />
            <EntryRow label="授权范围" value={metadataValue(config['authorization_scope'])} />
            <EntryRow label="ADB MCP" value={config['adb_mcp_enabled'] === true ? '启用' : '关闭'} />
            <EntryRow label="Frida MCP" value={config['frida_mcp_enabled'] === true ? '启用' : '关闭'} />
            {keywords.length > 0 ? <EntryRow label="关键字" value={keywords.join(', ')} /> : null}
            {stringFromUnknown(config['notes']) ? <EntryRow label="备注" value={metadataValue(config['notes'])} /> : null}
          </>
        )}
      </Section>
    );
  };

  const cacheHitPanel = renderCacheHitPanel(promptBudgetTokens > 0);
  const metadataSnapshotJson = JSON.stringify(
    {
      session,
      runtime: detail.runtime,
      loaded_messages: messages.length,
    },
    null,
    2,
  );
  const auditSnapshotJson = JSON.stringify(
    {
      session,
      runtime: detail.runtime,
      loaded_message_count: messages.length,
      loaded_message_ids: messages.map((item) => item.id),
    },
    null,
    2,
  );
  const auditSummary = [`${session.message_count} ${t('sessions.messageUnit', '条消息')}`, `${session.total_tokens ?? 0} tokens`, `${session.tool_message_count ?? 0} tool`, `${session.compression_point_count ?? 0} compress`];
  const auditCacheRead = readStatNumber(stats['cache_read_tokens'], 0);
  const auditCacheWrite = readStatNumber(stats['cache_creation_tokens'], 0);
  const auditReasoning = readStatNumber(stats['reasoning_tokens'], 0);
  if (auditCacheRead > 0) auditSummary.push(`cache read ${auditCacheRead.toLocaleString()}`);
  if (auditCacheWrite > 0) auditSummary.push(`cache write ${auditCacheWrite.toLocaleString()}`);
  if (auditReasoning > 0) auditSummary.push(`reasoning ${auditReasoning.toLocaleString()}`);
  const metadataActionButtonSurface = {
    background: 'var(--m3-surface-container-high)',
    border: '1px solid var(--m3-outline-variant)',
  };

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayTone: 'inverse',
        panelClassName: 'rounded-m3-lg w-full flex flex-col overflow-hidden',
        panelSurface: {
          maxWidth: '860px',
          maxHeight: '84vh',
        },
      })}
      ariaLabel={t('metadata.currentTitle', '当前会话元数据')}
    >
      <header
        class="flex shrink-0 flex-wrap items-start justify-between gap-3 px-5 py-4"
        style={{ borderBottom: '1px solid var(--m3-outline-variant)' }}
      >
        <div class="min-w-0 flex-1">
          <h2 class="text-2xl font-extrabold truncate">{t('metadata.currentTitle', '当前会话元数据')}</h2>
          <p class="text-sm mt-2 truncate oh-text-muted">
            {session.title}
          </p>
        </div>
        <JsonDialogActions
          json={metadataSnapshotJson}
          requestClose={requestClose}
          surfaceStyle={metadataActionButtonSurface}
          closeTone="secondary"
        />
      </header>
      <div
        class="min-h-0 flex-1 overflow-auto px-5 py-4 pr-4"
        style={{ scrollbarWidth: 'thin', overscrollBehavior: 'contain' }}
      >
        <div class="flex flex-wrap gap-3 mb-4">
          <SummaryTile label="消息总数" value={`${stats.total_message_count ?? session.message_count ?? 0}`} />
          <SummaryTile label="Prompt 构建" value={`${stats.prompt_build_count ?? 0}`} />
          <SummaryTile label="压缩次数" value={`${stats.compression_run_count ?? 0}`} />
          <SummaryTile label="总 Token" value={`${stats.total_tokens ?? session.total_tokens ?? 0}`} />
          <SummaryTile label="当前模式" value={runtimeModeLabel} />
          <SummaryTile label="运行工具" value={!hasPromptMetadata || runtimeStale ? '待刷新' : `${runtimeToolCount}`} />
        </div>
        <div class="flex flex-col gap-4">
          <Section title="会话概览">
            <EntryRow label={metadataFieldLabel('session_id')} value={session.id} />
            <EntryRow label={metadataFieldLabel('template')} value={`${session.template_name || session.template_id} · v${session.template_internal_version ?? '—'}`} />
            <EntryRow label={metadataFieldLabel('created_at')} value={formatDialogDate(session.created_at)} />
            <EntryRow label={metadataFieldLabel('updated_at')} value={formatDialogDate(session.updated_at)} />
            <EntryRow label={metadataFieldLabel('last_model')} value={session.last_used_model_label || session.last_used_model_id || '—'} />
            <EntryRow label={metadataFieldLabel('auto_title_acquired')} value={session.auto_title_acquired ? '✓ 已获取' : '✗ 未获取'} />
            <EntryRow label={metadataFieldLabel('auto_title_retry_count')} value={`${session.auto_title_retry_count ?? 0}`} />
            <EntryRow label={metadataFieldLabel('compression_checkpoint')} value={session.latest_compression_checkpoint_message_id || '—'} />
            <EntryRow label={metadataFieldLabel('latest_compression_at')} value={formatDialogDate(session.latest_compression_at)} />
          </Section>
          {session.template_id === 'harness_engineering' ? renderHarnessConfig() : null}
          {session.template_id === 'programming_expert' ? renderProgrammingConfig() : null}
          {session.template_id === 'android_reverse_expert' ? renderAndroidReverseConfig() : null}
          {Object.keys(machineTerminalMetadata).length > 0 ? renderMachineTerminalMetadata() : null}
          {visibleMetadataEntries.length > 0 ? (
            <Section title="扩展元数据">
              {visibleMetadataEntries.map(([key, value]) => (
                <StructuredValue key={key} label={key} value={value} />
              ))}
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
          {promptBudgetTokens > 0 || cacheHitPanel ? (
            <Section title="上下文预算">
              {promptBudgetTokens > 0 ? (
                <>
                  <div class="flex items-center gap-3 mb-3">
                    <div class="h-2 flex-1 rounded-full overflow-hidden" style={{ background: 'var(--m3-surface-container-highest)' }}>
                      <div
                        class="h-full rounded-full"
                        style={{
                          width: `${usageValue}%`,
                          background: contextStatus === 'critical' ? 'var(--m3-error)' : 'var(--m3-primary)',
                        }}
                      />
                    </div>
                    <Chip label={contextStatusLabel} />
                  </div>
                  <EntryRow label={metadataFieldLabel('context_budget_estimated_prompt_tokens')} value={`${promptBudgetTokens}`} />
                  <EntryRow label={metadataFieldLabel('context_budget_model_max_tokens')} value={metadataValue(lastPromptMetadata['context_budget_model_max_tokens'])} />
                  <EntryRow label={metadataFieldLabel('context_budget_effective_window_tokens')} value={metadataValue(lastPromptMetadata['context_budget_effective_window_tokens'])} />
                  <EntryRow label={metadataFieldLabel('context_budget_auto_compact_threshold_tokens')} value={metadataValue(lastPromptMetadata['context_budget_auto_compact_threshold_tokens'])} />
                  <EntryRow label={metadataFieldLabel('context_budget_remaining_tokens')} value={metadataValue(lastPromptMetadata['context_budget_remaining_tokens'])} />
                  <EntryRow label={metadataFieldLabel('context_budget_percent_left')} value={`${integerFromUnknown(lastPromptMetadata['context_budget_percent_left'])}%`} />
                  <EntryRow label={metadataFieldLabel('context_budget_usage_percent')} value={`${usagePercent}%`} />
                </>
              ) : null}
              {cacheHitPanel}
            </Section>
          ) : null}
          {Object.keys(rehydration).length > 0 ? (
            <Section title="压缩后上下文恢复">
              <EntryRow label={metadataFieldLabel('post_compact_active')} value={rehydration['active'] === true ? '启用' : '未启用'} />
              <EntryRow label={metadataFieldLabel('checkpoint_message_id')} value={metadataValue(rehydration['checkpoint_message_id'])} />
              <EntryRow label={metadataFieldLabel('checkpoint_created_at')} value={metadataValue(rehydration['checkpoint_created_at'])} />
              <EntryRow label={metadataFieldLabel('runtime_tool_count')} value={`${integerFromUnknown(rehydration['runtime_tool_count'])} (${integerFromUnknown(rehydration['builtin_tool_count'])} builtin, ${integerFromUnknown(rehydration['skill_tool_count'])} skill, ${integerFromUnknown(rehydration['mcp_tool_count'])} MCP)`} />
              <EntryRow label={metadataFieldLabel('restored_signal_counts')} value={`read_files=${integerFromUnknown(rehydration['recent_read_file_count'])}, skills=${integerFromUnknown(rehydration['invoked_skill_count'])}, mcp_instructions=${integerFromUnknown(rehydration['mcp_server_instruction_count'])}, session_hooks=${integerFromUnknown(rehydration['session_start_hook_count'])}, agent_results=${integerFromUnknown(rehydration['agent_result_count'])}, deferred_tools=${integerFromUnknown(rehydration['deferred_builtin_tool_count'])}, agent_types=${integerFromUnknown(rehydration['agent_type_count'])}`} />
              <div class="mt-2 mb-2 text-sm font-extrabold">恢复通道</div>
              <div class="flex flex-wrap gap-2">
                {stringListFromUnknown(rehydration['restored_channels']).length === 0 ? (
                  <span class="text-sm oh-text-muted">
                    暂无恢复通道。
                  </span>
                ) : (
                  stringListFromUnknown(rehydration['restored_channels']).map((item) => <Chip key={item} label={item} />)
                )}
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
              <p class="text-sm oh-text-muted">
                Prompt 元数据尚不可用。
              </p>
            ) : (
              <>
                <EntryRow label="写命令确认" value={lastPromptMetadata['write_command_confirmation_enabled'] === true ? '必需' : '不需要'} />
                <EntryRow label="允许规则" value={`${integerFromUnknown(lastPromptMetadata['allow_command_rule_count'])}`} />
                <div class="flex flex-wrap gap-2">
                  {arrayFromUnknown(lastPromptMetadata['allow_command_rules']).length === 0 ? (
                    <span class="text-sm oh-text-muted">
                      暂无显式允许命令规则。
                    </span>
                  ) : (
                    arrayFromUnknown(lastPromptMetadata['allow_command_rules']).map((raw, index) => {
                      const rule = recordFromUnknown(raw);
                      const pattern = stringFromUnknown(rule['pattern']);
                      const mode = stringFromUnknown(rule['match_mode']);
                      return pattern ? <Chip key={`${pattern}-${index}`} label={`${mode ? `${mode}: ` : ''}${pattern}`} /> : null;
                    })
                  )}
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
            <EntryRow label="ExitPlanMode" value={!hasPromptMetadata ? '不可用' : exitPlanModeAvailable ? '已开放' : session.mode === 'plan' ? '未开放' : '不适用'} />
            {planModePlanningToolNames.length > 0 ? (
              <>
                <div class="mt-3 mb-2 text-sm font-extrabold">计划期工具</div>
                <div class="flex flex-wrap gap-2">
                  {planModePlanningToolNames.map((item) => (
                    <Chip key={item} label={item} />
                  ))}
                </div>
              </>
            ) : null}
            {runtimeNotices.length > 0 ? (
              <>
                <div class="mt-3 mb-2 text-sm font-extrabold">运行时提示</div>
                <div class="flex flex-wrap gap-2">
                  {runtimeNotices.map((item) => (
                    <Chip key={item} label={item} />
                  ))}
                </div>
              </>
            ) : null}
            {runtimeToolNames.length > 0 && !runtimeStale ? (
              <>
                <div class="mt-3 mb-2 text-sm font-extrabold">当前运行工具</div>
                <div class="flex flex-wrap gap-2">
                  {runtimeToolNames.map((item) => (
                    <Chip key={item} label={item} />
                  ))}
                </div>
              </>
            ) : null}
          </Section>
          <Section title="任务跟踪">
            <EntryRow label="当前 Todos" value={`${todos.length}`} />
            <EntryRow label="计划记录" value={`${planHistory.length}`} />
            <EntryRow label="TodoWrite 提醒" value={hasPromptMetadata ? (lastPromptMetadata['todo_write_recommended'] === true ? '已触发' : '未触发') : '不可用'} />
            {stringFromUnknown(lastPromptMetadata['todo_write_reason']) ? <EntryRow label="提醒原因" value={stringFromUnknown(lastPromptMetadata['todo_write_reason'])} /> : null}
            {todos.length > 0 ? (
              <div class="flex flex-wrap gap-2">
                {todos.map((todo) => (
                  <Chip key={todo.id} label={`${todo.status ? `[${todo.status}] ` : ''}${todo.id ? `${todo.id}: ` : ''}${todo.content}`} />
                ))}
              </div>
            ) : null}
            {planHistory.length > 0 ? (
              <div class="mt-4 flex flex-col gap-2">
                {planHistory.map((plan, index) => (
                  <div
                    key={plan.id || index}
                    class="rounded-m3-sm p-3"
                    style={{
                      background: 'var(--m3-surface)',
                      border: '1px solid var(--m3-outline-variant)',
                    }}
                  >
                    <div class="text-sm font-bold">
                      计划 #{planHistory.length - index} · {plan.status || '—'}
                    </div>
                    <div class="mt-1 text-xs oh-text-muted">
                      {formatDialogDate(plan.created_at)} → {formatDialogDate(plan.updated_at)}
                    </div>
                    {plan.plan ? <div class="mt-2 text-sm whitespace-pre-wrap">{plan.plan}</div> : null}
                    {plan.steps?.length ? (
                      <div class="mt-2 flex flex-wrap gap-2">
                        {plan.steps.map((step) => (
                          <Chip key={step.id} label={`${step.status ? `[${step.status}] ` : ''}${step.id}: ${step.content}`} />
                        ))}
                      </div>
                    ) : null}
                  </div>
                ))}
              </div>
            ) : null}
          </Section>
          <Section title="最近错误">
            {recentErrors.length === 0 ? (
              <p class="text-sm oh-text-muted">
                暂无会话错误。
              </p>
            ) : (
              recentErrors.map((error) => (
                <div
                  key={error.id}
                  class="rounded-m3-sm p-3 mb-2"
                  style={{
                    background: 'var(--m3-surface)',
                    border: '1px solid var(--m3-outline-variant)',
                  }}
                >
                  <div class="text-sm font-bold oh-text-error">
                    {error.stage || 'error'} · {formatDialogDate(error.created_at)}
                  </div>
                  <div class="mt-2 text-sm whitespace-pre-wrap">{error.message}</div>
                  {error.detail ? <pre class="mt-2 text-xs whitespace-pre-wrap overflow-auto">{error.detail}</pre> : null}
                </div>
              ))
            )}
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
          <Section title={t('topbar.audit', '会话审计')}>
            <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
              <div class="min-w-0">
                <div class="text-xs font-bold oh-text-muted">
                  {metadataFieldLabel('session_id')}
                </div>
                <div class="mt-1 break-all text-sm font-semibold select-text">{session.id}</div>
              </div>
              <DialogActionButton
                tone="secondary"
                style={{ ...metadataActionButtonSurface, color: 'var(--m3-primary)' }}
                onClick={() => void copyJsonWithFeedback(auditSnapshotJson)}
              >
                <ComposerIcon name="copy" size={14} />
                <span>{t('common.copy', '复制')}</span>
              </DialogActionButton>
            </div>
            <div class="mb-4 flex flex-wrap gap-2">
              {auditSummary.map((item) => (
                <span
                  key={item}
                  class="rounded-full px-2.5 py-1.5 text-xs font-semibold"
                  style={{
                    color: 'var(--m3-on-surface-variant)',
                    background: 'var(--m3-surface)',
                    border: '1px solid var(--m3-outline-variant)',
                  }}
                >
                  {item}
                </span>
              ))}
            </div>
            <pre
              class="overflow-auto rounded-m3-sm p-3 text-xs whitespace-pre-wrap select-text"
              style={{
                maxHeight: '48vh',
                background: 'var(--m3-surface)',
                border: '1px solid var(--m3-outline-variant)',
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
              }}
            >
              {auditSnapshotJson}
            </pre>
          </Section>
        </div>
      </div>
    </DialogFrame>
  );
}

// 会话级节流覆盖写入 metadata；留空沿用全局值，0 表示关闭对应方向。
// 弹窗使用 SSE 快照中的吞吐桶绘制最近 30 秒统计。
function SessionThrottleDialog({
  sessionId,
  current,
  onClose,
}: {
  sessionId: string;
  current: {
    chars: number;
    cards: number;
    hasOverride: boolean;
    durationExpired?: boolean;
    enabled?: boolean;
    wasInitiallyThrottled?: boolean;
    throughputBuckets?: number[];
  } | null;
  onClose: () => void;
}) {
  const initialChars = current?.hasOverride ? String(current.chars) : '';
  const initialCards = current?.hasOverride ? String(current.cards) : '';
  const [chars, setChars] = useState(initialChars);
  const [cards, setCards] = useState(initialCards);
  // 会话级启用开关：undefined = 沿用全局；true/false = 强制
  // 覆盖。Switch 切换会立即 PUT，让流式响应在下一帧就感受到差异。
  const [enabledOverride, setEnabledOverride] = useState<boolean>(current?.enabled !== false);
  const [busy, setBusy] = useState(false);
  const { closing, requestClose } = useDialogExitMotion(onClose);

  const parse = (raw: string): number | null | undefined => {
    const trimmed = raw.trim();
    if (trimmed.length === 0) return undefined;
    return roundedNonNegativeIntegerOrNullFromUnknown(trimmed);
  };

  const apply = async () => {
    const c = parse(chars);
    const m = parse(cards);
    if (c === null || m === null) {
      showSnackbar(t('topbar.throttle.invalid', '请输入 0 或正整数'), {
        tone: 'error',
      });
      return;
    }
    setBusy(true);
    try {
      const patch: {
        charsPerSecond?: number | null;
        cardsPerSecond?: number | null;
        enabled?: boolean | null;
      } = {};
      patch.charsPerSecond = c === undefined ? null : c;
      patch.cardsPerSecond = m === undefined ? null : m;
      patch.enabled = enabledOverride;
      await setSessionThrottle(sessionId, patch);
      showSnackbar(t('topbar.throttle.saved', '已应用本会话节流'), {
        tone: 'success',
      });
      requestClose();
    } catch (err) {
      showSnackbar(`${t('topbar.throttle.failed', '应用节流失败')}：${err instanceof Error ? err.message : String(err)}`, { tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  const reset = async () => {
    setBusy(true);
    try {
      await clearSessionThrottle(sessionId);
      showSnackbar(t('topbar.throttle.reset', '已恢复模板/全局节流'), {
        tone: 'success',
      });
      requestClose();
    } catch (err) {
      showSnackbar(`${t('topbar.throttle.failed', '应用节流失败')}：${err instanceof Error ? err.message : String(err)}`, { tone: 'error' });
    } finally {
      setBusy(false);
    }
  };

  const buckets = current?.throughputBuckets ?? [];
  // 本地墙钟自滑动：SSE 仅在控制器 notifyListeners 时推快照，
  // 模型沉默期间柱状图会僵在 0/s。这里每秒 tick 一次，按 (now-lastUpdate)
  // 把 buckets 整体左移，前端永远能看到「秒级别更新」的吞吐曲线。
  const lastUpdateRef = useRef<number>(Date.now());
  const lastBucketsRef = useRef<number[]>(buckets);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    lastUpdateRef.current = Date.now();
    lastBucketsRef.current = buckets;
  }, [current?.throughputBuckets]);
  useEffect(() => {
    if (closing || typeof window === 'undefined') return undefined;
    const id = window.setInterval(
      () => setTick((n) => n + 1),
      THROTTLE_BUCKET_TICK_MS,
    );
    return () => window.clearInterval(id);
  }, [closing]);
  const displayedBuckets = useMemo(() => {
    void tick;
    const base = lastBucketsRef.current;
    if (base.length === 0) return base;
    const elapsed = Math.floor(
      (Date.now() - lastUpdateRef.current) / THROTTLE_BUCKET_TICK_MS,
    );
    if (elapsed <= 0) return base;
    const keep = Math.max(0, base.length - elapsed);
    const out = new Array<number>(base.length).fill(0);
    for (let i = 0; i < keep; i++) out[i + elapsed] = base[i];
    return out;
  }, [tick, current?.throughputBuckets]);
  const cap = Math.max(current?.chars ?? 1, ...displayedBuckets, 1);
  const peak = displayedBuckets.length === 0 ? 0 : Math.max(...displayedBuckets);
  const nowVal = displayedBuckets.length === 0 ? 0 : displayedBuckets[0];

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      closeOnBackdrop={!busy && !closing}
      {...createStandardDialogFrameAppearance({
        overlayClassName: `oh-dialog-backdrop ${DIALOG_OVERLAY_CENTER_CLASS}`,
        overlayTone: 'intense',
        panelClassName: 'rounded-m3-md p-5 w-full max-w-md',
        panelBorder: 'none',
        panelSurface: {
          background: 'var(--m3-surface-container-high)',
        },
      })}
      ariaLabel={t('topbar.throttle.dialogTitle', '本会话流式节流')}
    >
      <h2 class="text-base font-semibold mb-1 oh-text-body">
        {t('topbar.throttle.dialogTitle', '本会话流式节流')}
      </h2>
      <p class="text-xs mb-3 oh-text-muted">
        {t('topbar.throttle.dialogHint', '调整后在本会话中持久生效（重启后仍会保留）。留空 = 沿用全局值，0 = 关闭节流。')}
      </p>
      <div
        class="rounded-m3-sm p-3 mb-3"
        style={{
          background: 'var(--m3-surface-container-highest)',
          border: '1px solid var(--m3-outline-variant)',
        }}
      >
        <div class="flex items-center justify-between text-xs mb-2">
          <div class="font-semibold oh-text-muted">
            {t('topbar.throttle.gaugeTitle', '字符吞吐 (30s)')}
          </div>
          <div
            style={{
              color: 'var(--m3-on-surface)',
              fontVariantNumeric: 'tabular-nums',
            }}
          >
            {t('topbar.throttle.gaugeStats', '当前 {now}/s · 峰 {peak}/s · 上限 {cap}/s')
              .replace('{now}', String(nowVal))
              .replace('{peak}', String(peak))
              .replace('{cap}', String(current?.chars ?? 0))}
          </div>
        </div>
        <ThroughputBars samples={displayedBuckets} cap={cap} limitValue={current?.chars ?? 0} />
      </div>
      {/* 会话级启用节流开关：切换会立即 PUT，让正在输出
            的响应消息一帧内感受到差异；关闭后 TopBar 胶囊会变灰展示
            「节流·关」，但只要会话历史曾节流过，胶囊就不会消失。 */}
      <div
        class="flex items-start justify-between rounded-m3-sm p-3 mb-3 gap-3"
        style={{
          background: 'var(--m3-surface-container-highest)',
          border: '1px solid var(--m3-outline-variant)',
        }}
      >
        <div class="flex-1 min-w-0">
          <div class="text-sm font-semibold mb-1 oh-text-body">
            {t('topbar.throttle.enabledTitle', '启用流式输出节流（本会话）')}
          </div>
          <div class="text-xs oh-text-muted">
            {enabledOverride ? t('topbar.throttle.enabledOnHint', '已启用：按下方速率限制字符 / 卡片吞吐。') : t('topbar.throttle.enabledOffHint', '已关闭：流式响应将不再受任何节流限制，按 AI 真实速率渲染。')}
          </div>
        </div>
        <button
          type="button"
          role="switch"
          aria-checked={enabledOverride}
          disabled={busy || closing}
          onClick={async () => {
            if (busy || closing) return;
            const next = !enabledOverride;
            setEnabledOverride(next);
            setBusy(true);
            try {
              await setSessionThrottle(sessionId, { enabled: next });
            } catch (err: unknown) {
              showSnackbar(`${t('topbar.throttle.failed', '应用节流失败')}：${err instanceof Error ? err.message : String(err)}`, { tone: 'error' });
              setEnabledOverride(!next);
            } finally {
              setBusy(false);
            }
          }}
          class="oh-tap-press"
          style={{
            flex: '0 0 auto',
            width: '40px',
            height: '24px',
            borderRadius: '12px',
            border: '1px solid var(--m3-outline-variant)',
            background: enabledOverride ? 'var(--m3-primary)' : 'var(--m3-surface)',
            position: 'relative',
            transition: 'background 160ms ease-out',
            cursor: busy || closing ? 'not-allowed' : 'pointer',
          }}
        >
          <span
            style={{
              position: 'absolute',
              top: '2px',
              left: enabledOverride ? '18px' : '2px',
              width: '18px',
              height: '18px',
              borderRadius: '50%',
              background: enabledOverride ? 'var(--m3-on-primary)' : 'var(--m3-on-surface-variant)',
              transition: 'left 160ms ease-out, background 160ms ease-out',
            }}
          />
        </button>
      </div>
      <label class="block text-xs mb-2 oh-text-muted">
        {t('topbar.throttle.charsLabel', '字符 / 秒（当前生效：{cur}）').replace('{cur}', String(current?.chars ?? 0))}
      </label>
      <input
        type="number"
        min={0}
        value={chars}
        onInput={(e) => setChars((e.target as HTMLInputElement).value)}
        class="w-full mb-3 px-3 py-2 rounded-m3-sm text-sm"
        style={{
          background: 'var(--m3-surface)',
          border: '1px solid var(--m3-outline-variant)',
          color: 'var(--m3-on-surface)',
        }}
        placeholder={current ? String(current.chars) : '10'}
      />
      <label class="block text-xs mb-2 oh-text-muted">
        {t('topbar.throttle.cardsLabel', '卡片 / 秒（当前生效：{cur}）').replace('{cur}', String(current?.cards ?? 0))}
      </label>
      <input
        type="number"
        min={0}
        value={cards}
        onInput={(e) => setCards((e.target as HTMLInputElement).value)}
        class="w-full mb-4 px-3 py-2 rounded-m3-sm text-sm"
        style={{
          background: 'var(--m3-surface)',
          border: '1px solid var(--m3-outline-variant)',
          color: 'var(--m3-on-surface)',
        }}
        placeholder={current ? String(current.cards) : '1'}
      />
      <div class="flex justify-center gap-3">
        <button
          type="button"
          onClick={reset}
          disabled={busy || closing}
          class="oh-tap-press text-xs px-4 py-2 rounded-m3-sm"
          style={{
            border: '1px solid var(--m3-outline-variant)',
            color: 'var(--m3-on-surface)',
          }}
        >
          {t('topbar.throttle.reset.action', '恢复默认')}
        </button>
        <button
          type="button"
          onClick={requestClose}
          disabled={busy || closing}
          class="oh-tap-press text-xs px-4 py-2 rounded-m3-sm"
          style={{
            border: '1px solid var(--m3-outline-variant)',
            color: 'var(--m3-on-surface)',
          }}
        >
          {t('common.cancel', '取消')}
        </button>
        <button
          type="button"
          onClick={apply}
          disabled={busy || closing}
          class="oh-tap-press text-xs px-4 py-2 rounded-m3-sm"
          style={{
            background: 'var(--m3-primary)',
            color: 'var(--m3-on-primary)',
          }}
        >
          {t('common.apply', '应用')}
        </button>
      </div>
    </DialogFrame>
  );
}

// 30 秒字符吞吐曲线图。bucket 0 = 当前秒（最右），越往左越旧。
//
// SSE 每秒推一次新桶，先把每根 sample 从旧值 easeOutCubic 滑到新值。
// SVG 曲线使用 Catmull-Rom → 三次贝塞尔，并支持双指捏合 / Ctrl+滚轮放缩时间区间。
const THROTTLE_CHART_VIEWBOX_WIDTH = 100;
const THROTTLE_CHART_VIEWBOX_HEIGHT = 64;
const THROTTLE_CHART_PAD_X = 4;
const THROTTLE_CHART_PAD_TOP = 7;
const THROTTLE_CHART_PAD_BOTTOM = 7;

function ThroughputBars({ samples, cap, limitValue }: { samples: number[]; cap: number; limitValue: number }) {
  const fullN = samples.length === 0 ? 30 : samples.length;
  const padded = samples.length === 0 ? new Array<number>(30).fill(0) : samples;
  const safeCap = Math.max(cap, 1);

  // 时间区间放缩：1× = 全部 fullN 桶，4× = 最近 fullN/4 桶。
  const [zoom, setZoom] = useState(1);
  const visibleN = Math.max(3, Math.round(fullN / zoom));
  const windowed = padded.slice(0, Math.min(visibleN, padded.length));
  const n = windowed.length;
  const targets = windowed.map((v) => Math.min(1, v / safeCap));

  // 每根 sample 当前展示的归一化高度（0..1），长度恒为 n。
  const displayedRef = useRef<number[]>([]);
  const fromRef = useRef<number[]>([]);
  const targetRef = useRef<number[]>([]);
  const startRef = useRef<number>(0);
  const rafRef = useRef<number | null>(null);
  const [, forceTick] = useState(0);

  useEffect(() => {
    if (displayedRef.current.length !== n) {
      displayedRef.current = [...targets];
      forceTick((c) => c + 1);
      return;
    }
    fromRef.current = [...displayedRef.current];
    targetRef.current = [...targets];
    startRef.current = typeof performance !== 'undefined' ? performance.now() : Date.now();
    if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    const tick = () => {
      const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
      const elapsed = now - startRef.current;
      const t = Math.min(1, elapsed / 320);
      const e = 1 - Math.pow(1 - t, 3);
      const next = new Array<number>(n);
      for (let i = 0; i < n; i++) {
        const a = fromRef.current[i] ?? 0;
        const b = targetRef.current[i] ?? 0;
        next[i] = a + (b - a) * e;
      }
      displayedRef.current = next;
      forceTick((c) => c + 1);
      if (t < 1) rafRef.current = requestAnimationFrame(tick);
      else rafRef.current = null;
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    };
    // 仅在 samples 内容 / 窗口长度变化时重启动画。
  }, [windowed.join(','), n]);

  const displayed = displayedRef.current.length === n ? displayedRef.current : targets;

  // Catmull-Rom → 三次贝塞尔（张力 1/6）。绘图区主动内缩，避免满速
  // 平台线、0 速底线和当前秒高亮圆点贴住 SVG 边界后被裁切。
  const W = THROTTLE_CHART_VIEWBOX_WIDTH;
  const H = THROTTLE_CHART_VIEWBOX_HEIGHT;
  const plotLeft = THROTTLE_CHART_PAD_X;
  const plotRight = W - THROTTLE_CHART_PAD_X;
  const plotTop = THROTTLE_CHART_PAD_TOP;
  const plotBottom = H - THROTTLE_CHART_PAD_BOTTOM;
  const plotHeight = Math.max(1, plotBottom - plotTop);
  const plotWidth = Math.max(1, plotRight - plotLeft);
  const stepX = n <= 1 ? plotWidth : plotWidth / (n - 1);
  // 视觉 X：sample[0] = 当前 = 右；sample[n-1] = 最老 = 左。
  const points = displayed
    .map((h, i) => ({
      x: plotLeft + (n - 1 - i) * stepX,
      y: plotBottom - h * plotHeight,
    }))
    .sort((a, b) => a.x - b.x);

  let pathD = '';
  let fillD = '';
  if (points.length === 1) {
    const p = points[0];
    pathD = `M ${p.x.toFixed(2)} ${p.y.toFixed(2)}`;
    fillD = '';
  } else if (points.length > 1) {
    pathD = `M ${points[0].x.toFixed(2)} ${points[0].y.toFixed(2)}`;
    for (let i = 0; i < points.length - 1; i++) {
      const p0 = i === 0 ? points[i] : points[i - 1];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];
      const c1x = p1.x + (p2.x - p0.x) / 6;
      const c1y = p1.y + (p2.y - p0.y) / 6;
      const c2x = p2.x - (p3.x - p1.x) / 6;
      const c2y = p2.y - (p3.y - p1.y) / 6;
      pathD += ` C ${c1x.toFixed(2)} ${c1y.toFixed(2)} ${c2x.toFixed(2)} ${c2y.toFixed(2)} ${p2.x.toFixed(2)} ${p2.y.toFixed(2)}`;
    }
    fillD = `${pathD} L ${points[points.length - 1].x.toFixed(2)} ${plotBottom} L ${points[0].x.toFixed(2)} ${plotBottom} Z`;
  }

  // 当前秒（右端）的 sample[0] 坐标，用于实心圆 + 光晕。
  const lastP = points.length > 0 ? points[points.length - 1] : null;

  // Wheel + Ctrl = trackpad pinch（浏览器约定）；普通滚轮不触发以免误伤。
  const onWheel = (e: WheelEvent) => {
    if (!e.ctrlKey) return;
    e.preventDefault();
    const delta = -e.deltaY / 200;
    setZoom((z) => clampNumber(z * (1 + delta), 1, 4));
  };

  return (
    <div class="relative" style={{ height: `${H}px`, touchAction: 'pan-x' }} onWheel={onWheel as any} title="Ctrl + 滚轮（或触控板双指捏合）放缩时间区间">
      <div
        class="absolute inset-0"
        style={{
          backgroundImage: 'linear-gradient(to top, var(--m3-outline-variant) 0, transparent 1px)',
        }}
      />
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: '100%', height: '100%', display: 'block' }}>
        {fillD && <path d={fillD} fill="var(--m3-primary)" opacity={0.22} />}
        {pathD && <path d={pathD} fill="none" stroke="var(--m3-primary)" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke" />}
        {/* 超阈值点 */}
        {points.map((p, sortedIdx) => {
          // 反推原 index：sorted 后按 x 升序 → sample index = n - 1 - sortedIdx
          const origIdx = n - 1 - sortedIdx;
          const v = windowed[origIdx] ?? 0;
          if (limitValue > 0 && v > limitValue) {
            return <circle key={`o${sortedIdx}`} cx={p.x} cy={p.y} r={1.6} fill="var(--m3-error)" />;
          }
          return null;
        })}
        {/* 当前秒高亮 */}
        {lastP && (
          <>
            <circle cx={lastP.x} cy={lastP.y} r={3.4} fill="var(--m3-primary)" opacity={0.22} />
            <circle cx={lastP.x} cy={lastP.y} r={2.0} fill="var(--m3-primary)" />
          </>
        )}
      </svg>
      {zoom > 1.05 && (
        <div
          class="absolute top-0 right-1 text-[10px] px-1.5 py-0.5 rounded"
          style={{
            background: 'var(--m3-surface-container-high)',
            color: 'var(--m3-on-surface-variant)',
            fontVariantNumeric: 'tabular-nums',
          }}
        >
          {n}s · {zoom.toFixed(1)}×
        </div>
      )}
    </div>
  );
}
