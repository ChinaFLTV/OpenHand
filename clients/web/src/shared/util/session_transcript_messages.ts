import type { SessionMessage } from '../../api/sessions';

const TRANSCRIPT_MEDIA_METADATA_KEYS = [
  'image_path',
  'image_paths',
  'generated_image_path',
  'generated_image_paths',
  'video_path',
  'video_paths',
  'generated_video_path',
  'generated_video_paths',
  'audio_path',
  'audio_paths',
  'generated_audio_path',
  'generated_audio_paths',
  'media_path',
  'media_paths',
] as const;

const TRANSCRIPT_STRUCTURED_METADATA_KEYS = [
  'machine_expert_request_card',
  'web_reverse_request_card',
  'android_reverse_request_card',
  'goal_id',
  'goal_objective',
  'goal_evaluation_id',
  'goal_auto_follow_up',
  'goal_evaluation_message',
] as const;

const TRANSCRIPT_TOOL_METADATA_KEYS = [
  'tool_call_id',
  'tool_name',
  'tool_arguments',
  'tool_calls',
  'tool_arguments_streaming',
  'tool_preparing',
  'tool_execution_status',
  'tool_status',
  'status',
  'tool_execution_command',
  'tool_execution_stdout',
  'tool_execution_stderr',
  'tool_execution_result',
  'result_text',
] as const;

const TRANSCRIPT_FILE_MUTATION_METADATA_KEYS = [
  'file_mutation_path',
  'file_mutation_paths',
  'file_mutation_kind',
  'round_summary_tool_call_ids',
  'round_summary_source_message_ids',
  'round_summary_record_count',
] as const;

const TOOL_RESULT_KINDS = new Set(['tool', 'mcp', 'skill', 'hook']);

const STANDALONE_TOOL_RESULT_SUPPRESSED_TOOL_NAMES = new Set([
  'machineterminalread',
  'terminalread',
  'machineterminalwrite',
  'terminalwrite',
  'machineterminalexec',
  'terminalexec',
  'terminalcommand',
  'machineterminalcontrol',
  'terminalcontrol',
]);

function recordOrNullFromUnknown(value: unknown): Record<string, unknown> | null {
  if (value != null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function stringFromUnknown(value: unknown): string {
  return value == null ? '' : String(value).trim();
}

function metadataHasRenderableValue(value: unknown): boolean {
  if (value == null) return false;
  if (typeof value === 'string') return value.trim().length > 0;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return Number.isFinite(value) && value > 0;
  if (Array.isArray(value)) return value.some(metadataHasRenderableValue);
  if (typeof value === 'object') {
    return Object.values(value as Record<string, unknown>).some(metadataHasRenderableValue);
  }
  return true;
}

function metadataHasAnyRenderableValue(
  metadata: Record<string, unknown> | null,
  keys: readonly string[],
): boolean {
  if (!metadata) return false;
  return keys.some((key) => metadataHasRenderableValue(metadata[key]));
}

export function messageHasRenderableTranscriptOutput(message: SessionMessage): boolean {
  const content = (message.content ?? '').trim();
  if (content.length > 0) return true;
  const metadata = recordOrNullFromUnknown(message.metadata);
  if (metadataHasRenderableValue(metadata?.['attachments'])) return true;
  if (metadataHasAnyRenderableValue(metadata, TRANSCRIPT_MEDIA_METADATA_KEYS)) return true;

  switch (message.kind) {
    case 'tool_call':
    case 'tool':
    case 'mcp':
    case 'skill':
    case 'hook':
      return metadataHasAnyRenderableValue(metadata, TRANSCRIPT_TOOL_METADATA_KEYS);
    case 'file_mutation_summary':
      return metadataHasAnyRenderableValue(metadata, TRANSCRIPT_FILE_MUTATION_METADATA_KEYS);
    case 'status':
      return metadata?.['round_file_mutation_summary'] === true &&
        metadataHasAnyRenderableValue(metadata, TRANSCRIPT_FILE_MUTATION_METADATA_KEYS);
    default:
      return metadataHasAnyRenderableValue(metadata, TRANSCRIPT_STRUCTURED_METADATA_KEYS);
  }
}

function compareMessageCreatedAt(a: SessionMessage, b: SessionMessage): number {
  const ta = a.created_at ?? '';
  const tb = b.created_at ?? '';
  if (ta === tb) return 0;
  if (ta && tb) return ta < tb ? -1 : 1;
  return ta ? 1 : -1;
}

function messagesAreChronological(items: SessionMessage[]): boolean {
  for (let i = 1; i < items.length; i += 1) {
    if (compareMessageCreatedAt(items[i - 1]!, items[i]!) > 0) return false;
  }
  return true;
}

function messagesInDisplayOrder(items: SessionMessage[]): SessionMessage[] {
  return messagesAreChronological(items) ? items : [...items].sort(compareMessageCreatedAt);
}

function messageToolCallId(message: SessionMessage): string {
  return stringFromUnknown(message.metadata?.['tool_call_id']);
}

function normalizedToolName(metadata: Record<string, unknown> | null): string {
  return stringFromUnknown(metadata?.['tool_name'] ?? metadata?.['name']).toLowerCase();
}

function contentLooksLikeMachineTerminalOutput(content: string): boolean {
  const text = content.trimStart();
  return text.startsWith('terminal_id:') &&
    text.includes('\nstatus:') &&
    (text.includes('\nduration_ms:') ||
      text.includes('\nwritten_chars:') ||
      text.includes('\noutput:'));
}

function metadataLooksLikeMachineTerminal(metadata: Record<string, unknown> | null): boolean {
  if (!metadata) return false;
  return stringFromUnknown(metadata['terminal_id']).length > 0 ||
    metadata['machine_terminal_snapshot'] != null ||
    metadata['machine_terminal_metadata'] != null;
}

function isStandaloneMachineTerminalToolResult(message: SessionMessage): boolean {
  if (message.kind !== 'tool') return false;
  const metadata = recordOrNullFromUnknown(message.metadata);
  if (STANDALONE_TOOL_RESULT_SUPPRESSED_TOOL_NAMES.has(normalizedToolName(metadata))) {
    return true;
  }
  return metadataLooksLikeMachineTerminal(metadata) &&
    contentLooksLikeMachineTerminalOutput(message.content ?? '');
}

function shouldSuppressTranscriptToolResult(
  message: SessionMessage,
  toolCallIds: ReadonlySet<string>,
): boolean {
  if (!TOOL_RESULT_KINDS.has(message.kind)) return false;
  const toolCallId = messageToolCallId(message);
  if (toolCallId.length > 0 && toolCallIds.has(toolCallId)) {
    return true;
  }
  return isStandaloneMachineTerminalToolResult(message);
}

export function displayableTranscriptMessages(items: SessionMessage[]): SessionMessage[] {
  const ordered = messagesInDisplayOrder(items).filter(messageHasRenderableTranscriptOutput);
  const toolCallIds = new Set<string>();
  for (const message of ordered) {
    if (message.kind !== 'tool_call') continue;
    const toolCallId = messageToolCallId(message);
    if (toolCallId.length > 0) toolCallIds.add(toolCallId);
  }
  return ordered.filter((message) => !shouldSuppressTranscriptToolResult(message, toolCallIds));
}
