import {
  DEFERRED_MESSAGE_CONTENT_METADATA_KEY,
  DEFERRED_MESSAGE_DISPLAY_METADATA_KEY,
  type SessionMessage,
} from '../../api/sessions';
import {
  recordOrNullFromUnknown,
  stringifyJsonSafely,
} from './value';

export interface MergeServerWindowOptions {
  preserveLocalStreamingTail?: boolean;
}

export interface MergeServerWindowResult {
  items: SessionMessage[];
  offset: number;
  membershipChanged: boolean;
}

export interface MessageWindowMembershipTracker {
  revision: number;
  sessionId: string;
  windowOffset: number;
  messageIds: string[];
  source: SessionMessage[] | null;
}

export function updateMessageWindowMembership(
  tracker: MessageWindowMembershipTracker,
  sessionId: string,
  windowOffset: number,
  messages: SessionMessage[],
): string {
  if (
    tracker.sessionId === sessionId &&
    tracker.windowOffset === windowOffset &&
    tracker.source === messages
  ) {
    return `${sessionId}|${tracker.revision}`;
  }
  let changed =
    tracker.sessionId !== sessionId ||
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
  tracker.source = messages;
  return `${sessionId}|${tracker.revision}`;
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
  DEFERRED_MESSAGE_CONTENT_METADATA_KEY,
  DEFERRED_MESSAGE_DISPLAY_METADATA_KEY,
  'knowledge_base',
  'message_feedback',
  'response_variants',
  'response_variant_index',
] as const;

const metadataRenderFingerprintCache = new WeakMap<object, string>();
const messageRenderSignatureCache = new WeakMap<SessionMessage, string>();

function metadataTextLength(value: unknown): number {
  if (typeof value === 'string') return value.length;
  if (value == null) return 0;
  return stringifyJsonSafely(value)?.length ?? String(value).length;
}

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
  const metadata = recordOrNullFromUnknown(value);
  if (!metadata) return '';
  const cached = metadataRenderFingerprintCache.get(metadata);
  if (cached != null) return cached;
  const fingerprint = MESSAGE_RENDER_METADATA_KEYS
    .map((key) => `${key}=${metadataValueFingerprint(metadata[key])}`)
    .join('|');
  metadataRenderFingerprintCache.set(metadata, fingerprint);
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

export function messageFollowSignature(message: SessionMessage): string {
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

/** 比较真实 JSON 值，避免等长内容中间变化被采样指纹吞掉。 */
function renderValuesEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a == null || b == null || typeof a !== 'object' || typeof b !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const left = a as Record<string, unknown>;
  const right = b as Record<string, unknown>;
  const keys = Object.keys(left);
  if (keys.length !== Object.keys(right).length) return false;
  return keys.every((key) => Object.hasOwn(right, key) && renderValuesEqual(left[key], right[key]));
}

function metadataEquivalentForRender(rawA: unknown, rawB: unknown): boolean {
  if (rawA === rawB) return true;
  const a = recordOrNullFromUnknown(rawA);
  const b = recordOrNullFromUnknown(rawB);
  return MESSAGE_RENDER_METADATA_KEYS.every((key) => renderValuesEqual(a?.[key], b?.[key]));
}

/** 分层短路比较消息，流式正文变化时不计算昂贵的元数据指纹。 */
export function messagesEquivalentForRender(
  a: SessionMessage,
  b: SessionMessage,
): boolean {
  if (a === b) return true;
  const contentA = a.content ?? '';
  const contentB = b.content ?? '';
  if (
    a.id !== b.id ||
    a.role !== b.role ||
    a.kind !== b.kind ||
    contentA.length !== contentB.length ||
    (a.character_count ?? 0) !== (b.character_count ?? 0) ||
    a.created_at !== b.created_at ||
    (a.model_id ?? '') !== (b.model_id ?? '') ||
    (a.model_label ?? '') !== (b.model_label ?? '') ||
    (a.feedback ?? '') !== (b.feedback ?? '')
  ) {
    return false;
  }
  if (contentA !== contentB) return false;
  if (usageRenderFingerprint(a) !== usageRenderFingerprint(b)) return false;
  return metadataEquivalentForRender(a.metadata, b.metadata);
}

function isStreamingTailMessage(message: SessionMessage): boolean {
  return message.role === 'assistant' || message.role === 'tool';
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

function mergeStream(
  previous: SessionMessage[],
  next: SessionMessage[],
  options: MergeServerWindowOptions,
): SessionMessage[] {
  if (previous === next) return previous;
  if (previous.length === 0 || next.length === 0) return next;
  const merged: SessionMessage[] = new Array(next.length);
  let identical = previous.length === next.length;
  for (let index = 0; index < next.length; index += 1) {
    const current = index < previous.length ? previous[index] : undefined;
    const incoming = next[index]!;
    if (shouldKeepLongerStreamingMessage(current, incoming, options)) {
      merged[index] = current!;
    } else if (current && messagesEquivalentForRender(current, incoming)) {
      merged[index] = current;
    } else {
      merged[index] = incoming;
      identical = false;
    }
  }
  return identical ? previous : merged;
}

function appendLocalStreamingTail(
  previous: SessionMessage[],
  merged: SessionMessage[],
): SessionMessage[] {
  if (previous === merged || previous.at(-1)?.id === merged.at(-1)?.id) {
    return merged;
  }
  if (previous.length === 0 || merged.length === 0) return merged;
  const mergedIndexById = new Map<string, number>();
  merged.forEach((message, index) => mergedIndexById.set(message.id, index));
  let previousSharedIndex = -1;
  let mergedSharedIndex = -1;
  for (let index = previous.length - 1; index >= 0; index -= 1) {
    const match = mergedIndexById.get(previous[index]!.id);
    if (match != null) {
      previousSharedIndex = index;
      mergedSharedIndex = match;
      break;
    }
  }
  if (previousSharedIndex < 0 || mergedSharedIndex !== merged.length - 1) {
    return merged;
  }
  const suffix = previous.slice(previousSharedIndex + 1);
  if (suffix.length === 0 || !suffix.every(isStreamingTailMessage)) {
    return merged;
  }
  return [...merged, ...suffix];
}

function messageMembershipChangedFrom(
  previous: SessionMessage[],
  next: SessionMessage[],
  compareFrom = 0,
): boolean {
  if (previous.length !== next.length) return true;
  for (let index = Math.max(0, compareFrom); index < next.length; index += 1) {
    if (previous[index]?.id !== next[index]?.id) return true;
  }
  return false;
}

/** 合并服务端尾窗，并保留未变化历史消息的对象引用。 */
export function mergeServerWindowResult(
  previous: SessionMessage[],
  latest: SessionMessage[],
  currentOffset: number,
  nextOffset: number,
  options: MergeServerWindowOptions = {},
  previousIndexById?: ReadonlyMap<string, number>,
): MergeServerWindowResult {
  if (previous.length === 0) {
    return {
      items: latest,
      offset: nextOffset,
      membershipChanged: latest.length > 0,
    };
  }
  if (options.preserveLocalStreamingTail && latest.length === 0) {
    return { items: previous, offset: currentOffset, membershipChanged: false };
  }
  const latestFirstId = latest[0]?.id;
  const indexedOverlap = latestFirstId
    ? previousIndexById?.get(latestFirstId)
    : undefined;
  const overlapIndex =
    indexedOverlap != null && previous[indexedOverlap]?.id === latestFirstId
      ? indexedOverlap
      : latestFirstId
        ? previous.findIndex((message) => message.id === latestFirstId)
        : -1;
  if (overlapIndex < 0 && nextOffset < currentOffset) {
    if (options.preserveLocalStreamingTail) {
      const firstPrevious = previous[0];
      const latestOverlap = firstPrevious
        ? latest.findIndex((message) => message.id === firstPrevious.id)
        : -1;
      if (latestOverlap >= 0) {
        const merged = mergeStream(
          previous,
          latest.slice(latestOverlap),
          options,
        );
        const items = appendLocalStreamingTail(previous, merged);
        return {
          items,
          offset: currentOffset,
          membershipChanged: messageMembershipChangedFrom(previous, items),
        };
      }
      return {
        items: previous,
        offset: currentOffset,
        membershipChanged: false,
      };
    }
    return {
      items: latest,
      offset: nextOffset,
      membershipChanged: messageMembershipChangedFrom(previous, latest),
    };
  }
  const prefixCount =
    overlapIndex >= 0 ? overlapIndex : nextOffset - currentOffset;
  if (prefixCount <= 0) {
    const merged = mergeStream(previous, latest, options);
    const items = options.preserveLocalStreamingTail
      ? appendLocalStreamingTail(previous, merged)
      : merged;
    return {
      items,
      offset: currentOffset,
      membershipChanged: messageMembershipChangedFrom(previous, items),
    };
  }
  if (prefixCount > previous.length) {
    return {
      items: latest,
      offset: nextOffset,
      membershipChanged: messageMembershipChangedFrom(previous, latest),
    };
  }
  if (options.preserveLocalStreamingTail && latest.length > 0) {
    const suffix = previous.slice(prefixCount);
    if (
      suffix.length > 0 &&
      latest[0]?.id &&
      suffix[0]?.id !== latest[0]?.id &&
      suffix.some(isStreamingTailMessage)
    ) {
      return {
        items: previous,
        offset: currentOffset,
        membershipChanged: false,
      };
    }
  }
  const previousSuffix = previous.slice(prefixCount);
  const mergedSuffix = mergeStream(previousSuffix, latest, options);
  const merged =
    mergedSuffix === previousSuffix
      ? previous
      : [...previous.slice(0, prefixCount), ...mergedSuffix];
  const items = options.preserveLocalStreamingTail
    ? appendLocalStreamingTail(previous, merged)
    : merged;
  return {
    items,
    offset: currentOffset,
    membershipChanged: messageMembershipChangedFrom(
      previous,
      items,
      prefixCount,
    ),
  };
}
