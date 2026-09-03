import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { JSX } from 'preact';
import {
  DEFERRED_MESSAGE_TELEMETRY_METADATA_KEY,
  getSessionMessage,
  type SessionMessage,
} from '../api/sessions';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { useTransientFlag } from '../hooks/useTransientFlag';
import { t, tFmt } from '../i18n';
import { ignoreError } from '../shared/util/errors';
import { parseJsonSafely } from '../shared/util/value';
import { copyTextToClipboard } from '../utils/clipboard';
import { Markdown } from './Markdown';
import {
  DIALOG_OVERLAY_CENTER_FLUSH_CLASS,
  DIALOG_OVERLAY_FOCUSED_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

type TrajectoryKind =
  | 'system'
  | 'user'
  | 'context'
  | 'compacted'
  | 'assistant'
  | 'tool'
  | 'subtool';

interface TrajectoryUsage {
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  cacheReadTokens?: number;
  cacheCreationTokens?: number;
  reasoningTokens?: number;
}

interface TrajectoryRecord {
  id: string;
  index: number;
  turn: number;
  step: number;
  requestNumber: number;
  kind: TrajectoryKind;
  preview: string;
  input: string;
  output: string;
  thinking: string;
  startedAt: number | null;
  durationMs: number | null;
  running: boolean;
  error: boolean;
  usage: TrajectoryUsage | null;
  sourceMessageId: string | null;
  resultMessageId: string | null;
  callId: string | null;
  toolName: string | null;
  metadata: Record<string, unknown>;
}

interface TrajectorySnapshot {
  records: TrajectoryRecord[];
  collapsibleTurns: Set<number>;
  callCounts: Map<string, number>;
  callAnchors: Map<string, string>;
}

interface TimelineSpan {
  record: TrajectoryRecord;
  start: number;
  end: number;
}

interface TimelineRange {
  start: number;
  end: number;
}

interface TrajectoryDialogProps {
  sessionId: string;
  sessionTitle: string;
  sessionCreatedAt?: string;
  messages: readonly SessionMessage[];
  messageWindowStart: number;
  messageTotal: number;
  hasOlder: boolean;
  loadingOlder?: boolean;
  onLoadOlder: () => Promise<void>;
  onClose: () => void;
}

const TOOL_RESULT_KINDS = new Set(['tool', 'mcp', 'skill', 'hook']);
const TOOL_ERROR_STATES = new Set([
  'failed',
  'cancelled',
  'denied',
  'rejected',
  'timed_out',
  'invalid_arguments',
]);
const TELEMETRY_KEYS = new Set([
  'request_payload',
  'response_raw',
  'composed_prompt_text',
  'request_started_at',
  'first_token_at',
  'duration_ms',
  'ttft_ms',
  'tokens_per_second',
  'stream_throughput_chars_per_second',
]);
const MIN_TIMELINE_VIEW = 0.04;
const TIMELINE_DRAG_THRESHOLD_PX = 3;
const DETAIL_DEFAULT_WIDTH = 390;
const DETAIL_MIN_WIDTH = 320;
const DETAIL_MAX_WIDTH = 560;
const JSON_TREE_MAX_CHARACTERS = 512 * 1024;
const JSON_TREE_MAX_NODES = 4096;
const JSON_TREE_MAX_DEPTH = 32;
const COPY_FEEDBACK_MS = 2000;
const THROUGHPUT_MAX_POINTS = 300;

interface JsonDocument {
  value: Record<string, unknown> | unknown[];
  containerPaths: Set<string>;
}

function recordOf(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function textOf(value: unknown): string {
  return typeof value === 'string' ? value.trim() : value == null ? '' : String(value).trim();
}

function finiteNumber(value: unknown): number | null {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function numberList(value: unknown, limit = THROUGHPUT_MAX_POINTS): number[] {
  if (!Array.isArray(value)) return [];
  return value
    .map(finiteNumber)
    .filter((item): item is number => item != null && item >= 0)
    .slice(0, limit);
}

function nonNegativeInteger(value: unknown): number | undefined {
  const parsed = finiteNumber(value);
  return parsed == null || parsed < 0 ? undefined : Math.round(parsed);
}

function firstNumber(metadata: Record<string, unknown>, keys: readonly string[]): number | null {
  for (const key of keys) {
    const value = finiteNumber(metadata[key]);
    if (value != null && value >= 0) return value;
  }
  return null;
}

function timestampOf(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value < 10_000_000_000 ? value * 1000 : value;
  }
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : null;
}

function firstTimestamp(metadata: Record<string, unknown>, keys: readonly string[]): number | null {
  for (const key of keys) {
    const parsed = timestampOf(metadata[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

function collapseWhitespace(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function clipped(value: string, limit = 520): string {
  const normalized = collapseWhitespace(value);
  return normalized.length <= limit ? normalized : `${normalized.slice(0, limit - 1)}…`;
}

function usageOf(message: SessionMessage): TrajectoryUsage | null {
  const usage = message.usage;
  if (!usage) return null;
  const normalized: TrajectoryUsage = {
    promptTokens: nonNegativeInteger(usage.prompt_tokens),
    completionTokens: nonNegativeInteger(usage.completion_tokens),
    totalTokens: nonNegativeInteger(usage.total_tokens),
    cacheReadTokens: nonNegativeInteger(usage.cache_read_tokens),
    cacheCreationTokens: nonNegativeInteger(usage.cache_creation_tokens),
    reasoningTokens: nonNegativeInteger(usage.reasoning_tokens),
  };
  return Object.values(normalized).some((value) => value != null) ? normalized : null;
}

function messageTiming(message: SessionMessage, kind: TrajectoryKind): [number | null, number | null] {
  const metadata = recordOf(message.metadata);
  const startKeys = kind === 'tool' || kind === 'subtool'
    ? ['tool_execution_started_at', 'started_at']
    : kind === 'assistant' && message.kind === 'reasoning'
      ? ['reasoning_started_at', 'started_at', 'request_started_at']
      : kind === 'assistant'
        ? ['request_started_at', 'started_at']
        : ['started_at'];
  const endKeys = kind === 'tool' || kind === 'subtool'
    ? ['tool_execution_finished_at', 'ended_at']
    : kind === 'assistant' && message.kind === 'reasoning'
      ? ['reasoning_ended_at', 'ended_at']
      : ['ended_at'];
  const durationKeys = kind === 'tool' || kind === 'subtool'
    ? ['tool_execution_elapsed_ms', 'tool_execution_duration_ms', 'duration_ms']
    : kind === 'assistant' && message.kind === 'reasoning'
      ? ['reasoning_elapsed_ms', 'duration_ms']
      : ['duration_ms'];
  const startedAt = firstTimestamp(metadata, startKeys) ?? timestampOf(message.created_at);
  const endedAt = firstTimestamp(metadata, endKeys);
  const recordedDuration = firstNumber(metadata, durationKeys);
  const duration = recordedDuration ?? (
    startedAt != null && endedAt != null ? Math.max(0, endedAt - startedAt) : null
  );
  return [startedAt, duration];
}

function toolOutput(metadata: Record<string, unknown>): string {
  for (const key of [
    'tool_execution_result',
    'result_text',
    'tool_execution_stdout',
    'tool_execution_stderr',
  ]) {
    const value = textOf(metadata[key]);
    if (value) return value;
  }
  return '';
}

function toolPreview(name: string, input: string, output: string): string {
  const label = name || t('trajectory.toolFallback', '工具');
  const inputPreview = clipped(input, 260);
  const outputPreview = clipped(output, 260);
  if (!inputPreview && !outputPreview) return label;
  if (!outputPreview) return `${label}  ${inputPreview}`;
  if (!inputPreview) return `${label}  →  ${outputPreview}`;
  return `${label}  ${inputPreview}  →  ${outputPreview}`;
}

function messageRecord(
  message: SessionMessage,
  index: number,
  turn: number,
  step: number,
  requestNumber: number,
  kind: TrajectoryKind,
): TrajectoryRecord {
  const metadata = recordOf(message.metadata);
  const [startedAt, recordedDurationMs] = messageTiming(message, kind);
  const durationMs = kind === 'user' || kind === 'context' ? 0 : recordedDurationMs;
  const content = (message.content ?? '').trim();
  return {
    id: `message-${message.id}`,
    index,
    turn,
    step,
    requestNumber,
    kind,
    preview: clipped(content) || (message.kind === 'file_mutation_summary' ? t('trajectory.fileMutationSummary', '文件变更摘要') : ''),
    input: kind === 'user' || kind === 'context' ? content : '',
    output: kind === 'assistant' || kind === 'compacted' ? content : '',
    thinking: message.kind === 'reasoning' ? content : '',
    startedAt,
    durationMs,
    running: metadata.streaming === true || metadata.telemetry_in_flight === true,
    error: textOf(metadata.error) !== '',
    usage: usageOf(message),
    sourceMessageId: message.id,
    resultMessageId: null,
    callId: null,
    toolName: null,
    metadata,
  };
}

function toolRecord(
  message: SessionMessage,
  result: SessionMessage | undefined,
  index: number,
  turn: number,
  step: number,
  requestNumber: number,
): TrajectoryRecord {
  const metadata = recordOf(message.metadata);
  const callId = textOf(metadata.tool_call_id);
  const toolName = textOf(metadata.tool_name ?? metadata.name);
  const input = textOf(metadata.tool_arguments ?? metadata.arguments ?? message.content);
  const output = (result?.content ?? toolOutput(metadata)).trim();
  const status = textOf(metadata.tool_execution_status).toLowerCase();
  const [startedAt, durationMs] = messageTiming(message, 'tool');
  return {
    id: callId ? `tool-${callId}` : `message-${message.id}`,
    index,
    turn,
    step,
    requestNumber,
    kind: 'tool',
    preview: toolPreview(toolName, input, output),
    input,
    output,
    thinking: '',
    startedAt,
    durationMs,
    running: status === 'running' || metadata.tool_arguments_streaming === true || (!result && !output && !status),
    error: TOOL_ERROR_STATES.has(status) || textOf(result?.metadata?.error) !== '',
    usage: usageOf(message),
    sourceMessageId: message.id,
    resultMessageId: result?.id ?? null,
    callId: callId || null,
    toolName: toolName || null,
    metadata,
  };
}

function standaloneToolRecord(
  message: SessionMessage,
  index: number,
  turn: number,
  step: number,
  requestNumber: number,
): TrajectoryRecord {
  const metadata = recordOf(message.metadata);
  const callId = textOf(metadata.tool_call_id);
  const toolName = textOf(metadata.tool_name) || message.kind;
  const status = textOf(metadata.tool_execution_status).toLowerCase();
  return {
    id: callId ? `tool-result-${callId}` : `result-${message.id}`,
    index,
    turn,
    step,
    requestNumber,
    kind: 'tool',
    preview: toolPreview(toolName, '', message.content),
    input: '',
    output: message.content,
    thinking: '',
    startedAt: timestampOf(message.created_at),
    durationMs: firstNumber(metadata, [
      'tool_execution_elapsed_ms',
      'tool_execution_duration_ms',
      'duration_ms',
    ]),
    running: status === 'running',
    error: TOOL_ERROR_STATES.has(status),
    usage: usageOf(message),
    sourceMessageId: message.id,
    resultMessageId: null,
    callId: callId || null,
    toolName: toolName || null,
    metadata,
  };
}

function hasRequestTelemetry(message: SessionMessage): boolean {
  const metadata = recordOf(message.metadata);
  if (metadata[DEFERRED_MESSAGE_TELEMETRY_METADATA_KEY] === true) return true;
  return Object.keys(metadata).some((key) => TELEMETRY_KEYS.has(key));
}

function buildSnapshot(messages: readonly SessionMessage[], sessionCreatedAt?: string): TrajectorySnapshot {
  const ordered = [...messages]
    .filter((message) => recordOf(message.metadata).deleted !== true)
    .sort((left, right) => (timestampOf(left.created_at) ?? 0) - (timestampOf(right.created_at) ?? 0));
  const resultByCallId = new Map<string, SessionMessage>();
  for (const message of ordered) {
    if (!TOOL_RESULT_KINDS.has(message.kind)) continue;
    const callId = textOf(message.metadata?.tool_call_id);
    if (callId) resultByCallId.set(callId, message);
  }
  const records: TrajectoryRecord[] = [];
  const pairedResults = new Set<string>();
  const firstTelemetry = ordered.find(hasRequestTelemetry) ?? ordered[0];
  records.push({
    id: 'system-initial',
    index: 1,
    turn: 0,
    step: 0,
    requestNumber: 0,
    kind: 'system',
    preview: t('trajectory.initialSystemPrompt', '初始系统提示词'),
    input: '',
    output: '',
    thinking: '',
    startedAt: timestampOf(sessionCreatedAt) ?? timestampOf(firstTelemetry?.created_at),
    durationMs: null,
    running: false,
    error: false,
    usage: null,
    sourceMessageId: firstTelemetry?.id ?? null,
    resultMessageId: null,
    callId: null,
    toolName: null,
    metadata: recordOf(firstTelemetry?.metadata),
  });

  let turn = 0;
  let step = 0;
  let requestNumber = 0;
  let nextAssistantStartsStep = true;
  for (const message of ordered) {
    if (pairedResults.has(message.id)) continue;
    const metadata = recordOf(message.metadata);
    const callId = textOf(metadata.tool_call_id);
    switch (message.kind) {
      case 'user':
        if (metadata.goal_evaluation === true || metadata.is_goal_evaluation_message === true) {
          records.push(messageRecord(message, records.length + 1, Math.max(1, turn), step, requestNumber, 'context'));
          break;
        }
        turn += 1;
        step = 0;
        nextAssistantStartsStep = true;
        records.push(messageRecord(message, records.length + 1, turn, 0, requestNumber, 'user'));
        break;
      case 'reasoning':
      case 'assistant':
        if (turn === 0) turn = 1;
        if (nextAssistantStartsStep || step === 0) {
          step += 1;
          requestNumber += 1;
          nextAssistantStartsStep = false;
        }
        records.push(messageRecord(message, records.length + 1, turn, step, requestNumber, 'assistant'));
        break;
      case 'tool_call': {
        if (turn === 0) turn = 1;
        if (step === 0) {
          step = 1;
          requestNumber += 1;
        }
        const result = callId ? resultByCallId.get(callId) : undefined;
        if (result) pairedResults.add(result.id);
        records.push(toolRecord(message, result, records.length + 1, turn, step, requestNumber));
        nextAssistantStartsStep = true;
        break;
      }
      case 'tool':
      case 'mcp':
      case 'skill':
      case 'hook':
        if (turn === 0) turn = 1;
        records.push(standaloneToolRecord(message, records.length + 1, turn, Math.max(1, step), requestNumber));
        nextAssistantStartsStep = true;
        break;
      case 'compression_point':
        records.push(messageRecord(message, records.length + 1, turn, step, requestNumber, 'compacted'));
        break;
      case 'status':
      case 'self_learning':
      case 'file_mutation_summary':
        if (clipped(message.content)) {
          records.push(messageRecord(message, records.length + 1, Math.max(1, turn), step, requestNumber, 'context'));
        }
        break;
      default:
        break;
    }
  }

  const recordsPerTurn = new Map<number, number>();
  for (const record of records) {
    if (record.turn > 0) recordsPerTurn.set(record.turn, (recordsPerTurn.get(record.turn) ?? 0) + 1);
  }
  const collapsibleTurns = new Set(
    [...recordsPerTurn].filter(([, count]) => count > 1).map(([turnId]) => turnId),
  );
  const callCounts = new Map<string, number>();
  const callAnchors = new Map<string, string>();
  let anchor: TrajectoryRecord | null = null;
  for (const record of records) {
    if (record.kind === 'assistant') {
      anchor = record;
      continue;
    }
    if (record.kind === 'tool' || record.kind === 'subtool') {
      if (anchor && anchor.turn === record.turn && anchor.step === record.step) {
        callAnchors.set(record.id, anchor.id);
        callCounts.set(anchor.id, (callCounts.get(anchor.id) ?? 0) + 1);
      }
      continue;
    }
    if (record.kind === 'user' || record.turn !== anchor?.turn || record.step !== anchor?.step) anchor = null;
  }
  return { records, collapsibleTurns, callCounts, callAnchors };
}

function kindLabel(kind: TrajectoryKind): string {
  return t(`trajectory.kind.${kind}`, kind.toUpperCase());
}

function laneOf(kind: TrajectoryKind): number {
  if (kind === 'system' || kind === 'user' || kind === 'context') return 0;
  if (kind === 'assistant' || kind === 'compacted') return 1;
  return 2;
}

function projectTimeline(records: readonly TrajectoryRecord[], actualDuration: boolean): TimelineSpan[] {
  if (!records.length) return [];
  if (!actualDuration) {
    return records.map((record, index) => ({
      record,
      start: index / records.length,
      end: (index + 1) / records.length,
    }));
  }
  const timed = records
    .filter((record) => record.startedAt != null)
    .sort((left, right) => (left.startedAt! - right.startedAt!) || (left.index - right.index));
  if (!timed.length) return projectTimeline(records, false);

  const epoch = timed[0]!.startedAt!;
  let removedIdle = 0;
  let coveredUntil: number | null = null;
  const projected = timed.map((record): TimelineSpan => {
    const rawStart = record.startedAt! - epoch;
    const rawEnd = rawStart + Math.max(0, record.durationMs ?? 0);
    if (coveredUntil != null && rawStart > coveredUntil) removedIdle += rawStart - coveredUntil;
    const span = { record, start: rawStart - removedIdle, end: rawEnd - removedIdle };
    coveredUntil = coveredUntil == null ? rawEnd : Math.max(coveredUntil, rawEnd);
    return span;
  });
  const domainEnd = Math.max(1, ...projected.map((span) => span.end));
  return projected.map((span) => ({
    ...span,
    start: span.start / domainEnd,
    end: span.end / domainEnd,
  }));
}

function formatDuration(milliseconds: number | null): string {
  if (milliseconds == null) return '—';
  if (milliseconds < 1000) return `${Math.round(milliseconds)} ms`;
  const seconds = milliseconds / 1000;
  return `${seconds.toFixed(seconds < 10 ? 2 : 1)} s`;
}

function formatTime(timestamp: number | null): string {
  if (timestamp == null) return t('trajectory.notRecorded', '未记录');
  return new Date(timestamp).toLocaleString(undefined, {
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    fractionalSecondDigits: 3,
  });
}

function prettyValue(value: unknown): string {
  if (value == null) return '';
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return '';
    const parsed = parseJsonSafely(trimmed);
    return parsed == null ? trimmed : JSON.stringify(parsed, null, 2);
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function jsonDocument(text: string): JsonDocument | null {
  const trimmed = text.trim();
  if (
    trimmed.length < 2
    || trimmed.length > JSON_TREE_MAX_CHARACTERS
    || !((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']')))
  ) return null;
  const decoded = parseJsonSafely(trimmed);
  if (decoded == null || typeof decoded !== 'object') return null;

  const containerPaths = new Set<string>(['$']);
  const pending: Array<{ value: Record<string, unknown> | unknown[]; path: string; depth: number }> = [
    { value: decoded as Record<string, unknown> | unknown[], path: '$', depth: 0 },
  ];
  let nodes = 0;
  while (pending.length) {
    const current = pending.pop()!;
    if (current.depth > JSON_TREE_MAX_DEPTH) return null;
    const children = Array.isArray(current.value) ? current.value : Object.values(current.value);
    for (let index = 0; index < children.length; index += 1) {
      nodes += 1;
      if (nodes > JSON_TREE_MAX_NODES) return null;
      const child = children[index];
      if (
        child != null
        && typeof child === 'object'
        && (Array.isArray(child) ? child.length > 0 : Object.keys(child).length > 0)
      ) {
        const path = `${current.path}/${index}`;
        containerPaths.add(path);
        pending.push({
          value: child as Record<string, unknown> | unknown[],
          path,
          depth: current.depth + 1,
        });
      }
    }
  }
  return { value: decoded as Record<string, unknown> | unknown[], containerPaths };
}

function requestPayload(metadata: Record<string, unknown>): Record<string, unknown> {
  const raw = metadata.request_payload;
  if (typeof raw === 'string') {
    return recordOf(parseJsonSafely(raw));
  }
  return recordOf(raw);
}

function contentText(content: unknown): string {
  if (typeof content === 'string') return content.trim();
  if (!Array.isArray(content)) return textOf(content);
  return content.map((item) => {
    if (typeof item === 'string') return item.trim();
    const block = recordOf(item);
    return textOf(block.text ?? block.content);
  }).filter(Boolean).join('\n');
}

function systemPrompt(metadata: Record<string, unknown>): string {
  const messages = requestPayload(metadata).messages;
  if (Array.isArray(messages)) {
    const parts = messages.flatMap((item) => {
      const message = recordOf(item);
      return textOf(message.role).toLowerCase() === 'system' ? [contentText(message.content)] : [];
    }).filter(Boolean);
    if (parts.length) return parts.join('\n\n');
  }
  return textOf(metadata.composed_prompt_text);
}

function toolCatalog(metadata: Record<string, unknown>): string {
  return prettyValue(requestPayload(metadata).tools);
}

function requestOptions(metadata: Record<string, unknown>): string {
  const payload = { ...requestPayload(metadata) };
  delete payload.messages;
  delete payload.tools;
  return Object.keys(payload).length ? prettyValue(payload) : '';
}

function schemaText(metadata: Record<string, unknown>): string {
  for (const key of ['tool_schema', 'input_schema', 'parameters_schema', 'schema']) {
    if (metadata[key] != null) return prettyValue(metadata[key]);
  }
  return '';
}

function rawRecordText(record: TrajectoryRecord): string {
  if (record.kind === 'tool' || record.kind === 'subtool') {
    return [record.input, record.output].filter((value) => value.trim()).join('\n\n');
  }
  return record.thinking || record.output || record.input;
}

function searchableText(record: TrajectoryRecord): string {
  return [
    record.preview,
    record.input,
    record.output,
    record.thinking,
    record.toolName ?? '',
    record.callId ?? '',
  ].join('\n').toLowerCase();
}

function recordTabs(record: TrajectoryRecord): Array<[string, string]> {
  switch (record.kind) {
    case 'system':
      return [
        ['system-prompt', t('trajectory.tab.systemPrompt', 'System Prompt')],
        ['tools', t('trajectory.tab.tools', 'Tools')],
      ];
    case 'user':
    case 'context':
      return [
        ['summary', t('trajectory.tab.summary', 'Summary')],
        ['rendered', t('trajectory.tab.rendered', 'Rendered')],
        ['raw', t('trajectory.tab.raw', 'Raw')],
        ['source', t('trajectory.tab.source', 'Source')],
        ['timing', t('trajectory.tab.timing', 'Timing')],
      ];
    case 'assistant':
      return [
        ['summary', t('trajectory.tab.summary', 'Summary')],
        ['rendered', t('trajectory.tab.rendered', 'Rendered')],
        ['raw', t('trajectory.tab.raw', 'Raw')],
        ['options', t('trajectory.tab.options', 'Options')],
        ['usage', t('trajectory.tab.usage', 'Usage')],
        ['timing', t('trajectory.tab.timing', 'Timing')],
      ];
    case 'compacted':
      return [
        ['summary', t('trajectory.tab.summary', 'Summary')],
        ['raw', t('trajectory.tab.rawOutput', 'Raw Output')],
      ];
    case 'tool':
    case 'subtool':
      return [
        ['summary', t('trajectory.tab.summary', 'Summary')],
        ['input', t('trajectory.tab.input', 'Input')],
        ['output', t('trajectory.tab.output', 'Output')],
        ['schema', t('trajectory.tab.schema', 'Schema')],
        ['timing', t('trajectory.tab.timing', 'Timing')],
      ];
  }
}

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="11" cy="11" r="7" />
      <path d="m16.5 16.5 4 4" />
    </svg>
  );
}

function TrajectoryIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="6" cy="19" r="3" />
      <path d="M9 19h6.5a3.5 3.5 0 0 0 0-7h-8a3.5 3.5 0 0 1 0-7H15" />
      <circle cx="18" cy="5" r="3" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m6 6 12 12M18 6 6 18" />
    </svg>
  );
}

function TrajectoryTimeline({
  spans,
  range,
  selectedId,
  searchMatches,
  hasOlder,
  loadingOlder,
  onRangeChange,
  onSelect,
  onLoadOlder,
}: {
  spans: readonly TimelineSpan[];
  range: TimelineRange | null;
  selectedId: string | null;
  searchMatches: ReadonlySet<string> | null;
  hasOlder: boolean;
  loadingOlder: boolean;
  onRangeChange: (range: TimelineRange | null) => void;
  onSelect: (record: TrajectoryRecord) => void;
  onLoadOlder: () => Promise<void>;
}) {
  const trackRef = useRef<HTMLDivElement | null>(null);
  const [viewport, setViewport] = useState<TimelineRange>({ start: 0, end: 1 });
  const [hover, setHover] = useState<number | null>(null);
  const dragRef = useRef<{
    button: number;
    pointerId: number;
    startX: number;
    anchor: number;
    viewport: TimelineRange;
  } | null>(null);
  const suppressContextResetRef = useRef(false);

  useEffect(() => {
    setViewport({ start: 0, end: 1 });
    onRangeChange(null);
  }, [spans.length]);

  const fractionAt = useCallback((clientX: number): number => {
    const rect = trackRef.current?.getBoundingClientRect();
    if (!rect || rect.width <= 0) return viewport.start;
    const local = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
    return viewport.start + local * (viewport.end - viewport.start);
  }, [viewport]);

  const recordAt = useCallback((fraction: number): TrajectoryRecord | null => {
    const exact = spans.find((span) => fraction >= span.start && fraction <= span.end);
    if (exact) return exact.record;
    let nearest: TimelineSpan | null = null;
    let distance = Number.POSITIVE_INFINITY;
    for (const span of spans) {
      const center = (span.start + span.end) / 2;
      const nextDistance = Math.abs(center - fraction);
      if (nextDistance < distance) {
        nearest = span;
        distance = nextDistance;
      }
    }
    return nearest?.record ?? null;
  }, [spans]);

  const visibleWidth = viewport.end - viewport.start;
  const positionStyle = (start: number, end: number): JSX.CSSProperties => ({
    left: `${(start - viewport.start) / visibleWidth * 100}%`,
    width: `${Math.max(0.18, (end - start) / visibleWidth * 100)}%`,
  });
  const visibleRange = range == null ? null : {
    start: Math.max(viewport.start, range.start),
    end: Math.min(viewport.end, range.end),
  };

  return (
    <section class="oh-trajectory-timeline" aria-label={t('trajectory.timeline', '轨迹时间线')}>
      <div class="oh-trajectory-lane-labels" aria-hidden="true">
        <span>{t('trajectory.lane.input', '输入')}</span>
        <span>{t('trajectory.lane.model', '模型')}</span>
        <span>{t('trajectory.lane.tools', '工具')}</span>
      </div>
      <div
        ref={trackRef}
        class="oh-trajectory-track"
        tabIndex={0}
        onKeyDown={(event) => {
          if (event.key !== 'Escape') return;
          const hasTimelineAdjustment =
            viewport.start !== 0 || viewport.end !== 1 || range != null;
          if (!hasTimelineAdjustment) return;
          event.preventDefault();
          setViewport({ start: 0, end: 1 });
          onRangeChange(null);
        }}
        onContextMenu={(event) => {
          event.preventDefault();
          if (!suppressContextResetRef.current) {
            setViewport({ start: 0, end: 1 });
            onRangeChange(null);
          }
          suppressContextResetRef.current = false;
        }}
        onWheel={(event) => {
          event.preventDefault();
          const currentWidth = viewport.end - viewport.start;
          const zoom = event.deltaY > 0 ? 1.16 : 0.84;
          const nextWidth = Math.min(1, Math.max(MIN_TIMELINE_VIEW, currentWidth * zoom));
          const focus = fractionAt(event.clientX);
          const relative = currentWidth <= 0 ? 0.5 : (focus - viewport.start) / currentWidth;
          const start = Math.min(1 - nextWidth, Math.max(0, focus - nextWidth * relative));
          setViewport({ start, end: start + nextWidth });
        }}
        onPointerDown={(event) => {
          if (event.button !== 0 && event.button !== 2) return;
          event.currentTarget.setPointerCapture(event.pointerId);
          dragRef.current = {
            button: event.button,
            pointerId: event.pointerId,
            startX: event.clientX,
            anchor: fractionAt(event.clientX),
            viewport,
          };
          if (event.button === 2) suppressContextResetRef.current = false;
        }}
        onPointerMove={(event) => {
          setHover(fractionAt(event.clientX));
          const drag = dragRef.current;
          if (!drag || drag.pointerId !== event.pointerId) return;
          if (drag.button === 2) {
            const rect = trackRef.current?.getBoundingClientRect();
            if (!rect || rect.width <= 0) return;
            const width = drag.viewport.end - drag.viewport.start;
            const delta = -(event.clientX - drag.startX) / rect.width * width;
            if (Math.abs(event.clientX - drag.startX) >= TIMELINE_DRAG_THRESHOLD_PX) {
              suppressContextResetRef.current = true;
            }
            const start = Math.min(1 - width, Math.max(0, drag.viewport.start + delta));
            setViewport({ start, end: start + width });
            return;
          }
          const current = fractionAt(event.clientX);
          if (Math.abs(event.clientX - drag.startX) >= TIMELINE_DRAG_THRESHOLD_PX) {
            onRangeChange({ start: Math.min(drag.anchor, current), end: Math.max(drag.anchor, current) });
          }
        }}
        onPointerUp={(event) => {
          const drag = dragRef.current;
          dragRef.current = null;
          if (!drag || drag.pointerId !== event.pointerId || drag.button !== 0) return;
          if (Math.abs(event.clientX - drag.startX) < TIMELINE_DRAG_THRESHOLD_PX) {
            const record = recordAt(fractionAt(event.clientX));
            if (record) onSelect(record);
          }
        }}
        onPointerCancel={() => { dragRef.current = null; }}
        onPointerLeave={() => setHover(null)}
      >
        {hasOlder ? (
          <button
            type="button"
            class="oh-trajectory-earlier"
            disabled={loadingOlder}
            onPointerDown={(event) => event.stopPropagation()}
            onClick={() => void onLoadOlder()}
            title={loadingOlder
              ? t('trajectory.loadingOlder', '正在加载更早记录…')
              : t('trajectory.loadOlderHint', '点击加载更早记录')}
          >
            {loadingOlder ? <span class="oh-trajectory-spinner" /> : '…'}
          </button>
        ) : null}
        <div class="oh-trajectory-turn-boundaries" aria-hidden="true">
          {spans.filter((span, index) => index > 0 && span.record.turn !== spans[index - 1]?.record.turn).map((span) => (
            <i key={`turn-${span.record.id}`} style={{ left: `${(span.start - viewport.start) / visibleWidth * 100}%` }} />
          ))}
        </div>
        <div class="oh-trajectory-spans">
          {spans.map((span) => {
            if (span.end < viewport.start || span.start > viewport.end) return null;
            const match = searchMatches == null || searchMatches.has(span.record.id);
            return (
              <i
                key={span.record.id}
                class={`is-${span.record.kind}${span.record.error ? ' is-error' : ''}`}
                data-lane={laneOf(span.record.kind)}
                data-selected={selectedId === span.record.id ? 'true' : undefined}
                data-search-match={match ? 'true' : 'false'}
                style={positionStyle(Math.max(span.start, viewport.start), Math.min(span.end, viewport.end))}
              />
            );
          })}
        </div>
        {visibleRange && visibleRange.end >= visibleRange.start ? (
          <div
            class="oh-trajectory-selection"
            style={positionStyle(visibleRange.start, visibleRange.end)}
            aria-hidden="true"
          />
        ) : null}
        {hover != null ? (
          <i
            class="oh-trajectory-hover-line"
            style={{ left: `${(hover - viewport.start) / visibleWidth * 100}%` }}
            aria-hidden="true"
          />
        ) : null}
      </div>
    </section>
  );
}

function DetailRows({ rows }: { rows: Array<[string, string, boolean?]> }) {
  return (
    <dl class="oh-trajectory-metric-grid">
      {rows.map(([label, value, error]) => (
        <div key={label} data-error={error ? 'true' : undefined}>
          <dt>{label}</dt>
          <dd class={error ? 'is-error' : undefined}>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function EmptyDetail({ children }: { children: string }) {
  return <p class="oh-trajectory-detail-empty"><span aria-hidden="true">i</span>{children}</p>;
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="8" y="8" width="11" height="11" rx="2" />
      <path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" />
    </svg>
  );
}

function CheckIcon() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6" /></svg>;
}

function UnfoldIcon({ collapse }: { collapse: boolean }) {
  return collapse
    ? <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 10 5-5 5 5M7 14l5 5 5-5" /></svg>
    : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 8 5 5 5-5M7 16l5-5 5 5" /></svg>;
}

function jsonEntries(value: Record<string, unknown> | unknown[]): Array<[string, unknown]> {
  return Array.isArray(value)
    ? value.map((child, index) => [String(index), child])
    : Object.entries(value);
}

function JsonNode({
  name,
  value,
  path,
  expandedPaths,
  onToggle,
}: {
  name: string;
  value: unknown;
  path: string;
  expandedPaths: ReadonlySet<string>;
  onToggle: (path: string) => void;
}) {
  const container = value != null && typeof value === 'object';
  const entries = container ? jsonEntries(value as Record<string, unknown> | unknown[]) : [];
  const expandable = container && entries.length > 0;
  const expanded = expandable && expandedPaths.has(path);
  const valueClass = value === null ? 'is-null' : `is-${typeof value}`;
  const content = (
    <code>
      <span class="oh-trajectory-json-key">{JSON.stringify(name)}</span>
      <span class="oh-trajectory-json-punctuation">: </span>
      {container ? (
        <>
          <span class="oh-trajectory-json-punctuation">{
            Array.isArray(value)
              ? entries.length ? '[…]' : '[]'
              : entries.length ? '{…}' : '{}'
          }</span>
          {entries.length ? <span class="oh-trajectory-json-count">{entries.length}</span> : null}
        </>
      ) : (
        <span class={`oh-trajectory-json-value ${valueClass}`}>{JSON.stringify(value)}</span>
      )}
    </code>
  );
  return (
    <div class="oh-trajectory-json-node" role="treeitem" aria-expanded={expandable ? expanded : undefined}>
      {expandable ? (
        <button type="button" class="oh-trajectory-json-row" onClick={() => onToggle(path)}>
          <span class="oh-trajectory-json-chevron" aria-hidden="true">›</span>
          {content}
        </button>
      ) : (
        <div class="oh-trajectory-json-row is-leaf">
          <span class="oh-trajectory-json-bullet" aria-hidden="true" />
          {content}
        </div>
      )}
      {expandable ? (
        <div class={`oh-trajectory-json-children${expanded ? ' is-expanded' : ''}`}>
          <div role="group">
            {entries.map(([key, child], index) => (
              <JsonNode
                key={`${path}/${index}`}
                name={key}
                value={child}
                path={`${path}/${index}`}
                expandedPaths={expandedPaths}
                onToggle={onToggle}
              />
            ))}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function StructuredDetail({ text, empty, error = false }: { text: string; empty: string; error?: boolean }) {
  const document = useMemo(() => jsonDocument(text), [text]);
  const [expandedPaths, setExpandedPaths] = useState<Set<string>>(new Set(['$']));
  const {
    active: copied,
    trigger: showCopied,
    reset: resetCopied,
  } = useTransientFlag(COPY_FEEDBACK_MS);

  useEffect(() => {
    const initial = new Set<string>(['$']);
    for (const path of document?.containerPaths ?? []) {
      if (path !== '$' && path.split('/').length === 2) initial.add(path);
    }
    setExpandedPaths(initial);
    resetCopied();
  }, [document, resetCopied]);

  if (!text.trim()) return <EmptyDetail>{empty}</EmptyDetail>;
  const value = document?.value;
  const count = value == null ? 0 : Array.isArray(value) ? value.length : Object.keys(value).length;
  const description = document == null
    ? tFmt('trajectory.structured.text', { count: text.length }, `Text · ${text.length} characters`)
    : Array.isArray(value)
      ? tFmt('trajectory.structured.array', { count }, `Array · ${count} items`)
      : tFmt('trajectory.structured.object', { count }, `Object · ${count} fields`);
  const allExpanded = document != null
    && [...document.containerPaths].every((path) => expandedPaths.has(path));
  const rootEntries = document == null ? [] : jsonEntries(document.value);
  const copy = async () => {
    if (!await copyTextToClipboard(text)) return;
    showCopied();
  };
  const toggle = (path: string) => setExpandedPaths((current) => {
    const next = new Set(current);
    if (next.has(path)) next.delete(path); else next.add(path);
    return next;
  });

  return (
    <section class={`oh-trajectory-structured${error ? ' is-error' : ''}`}>
      <header>
        <span class="oh-trajectory-structured-type" aria-hidden="true">{document ? '{}' : 'T'}</span>
        <strong title={description}>{description}</strong>
        {document && document.containerPaths.size > 1 ? (
          <button
            type="button"
            title={allExpanded ? t('trajectory.structured.collapseAll', '全部收起') : t('trajectory.structured.expandAll', '全部展开')}
            aria-label={allExpanded ? t('trajectory.structured.collapseAll', '全部收起') : t('trajectory.structured.expandAll', '全部展开')}
            onClick={() => setExpandedPaths(allExpanded ? new Set(['$']) : new Set(document.containerPaths))}
          >
            <UnfoldIcon collapse={allExpanded} />
          </button>
        ) : null}
        <button
          type="button"
          title={copied
            ? t('trajectory.structured.copied', '已复制')
            : document
              ? t('trajectory.structured.copyJson', '复制 JSON')
              : t('trajectory.structured.copyText', '复制文本')}
          aria-label={copied
            ? t('trajectory.structured.copied', '已复制')
            : document
              ? t('trajectory.structured.copyJson', '复制 JSON')
              : t('trajectory.structured.copyText', '复制文本')}
          onClick={() => void copy()}
          data-copied={copied ? 'true' : undefined}
        >
          {copied ? <CheckIcon /> : <CopyIcon />}
        </button>
      </header>
      {document ? (
        <div class="oh-trajectory-json-tree" role="tree">
          {rootEntries.length ? rootEntries.map(([key, child], index) => (
              <JsonNode
                key={`$/${index}`}
                name={key}
                value={child}
                path={`$/${index}`}
                expandedPaths={expandedPaths}
                onToggle={toggle}
              />
            )) : <code class="oh-trajectory-json-empty">{Array.isArray(document.value) ? '[]' : '{}'}</code>}
        </div>
      ) : (
        <pre class="oh-trajectory-detail-text">{text}</pre>
      )}
    </section>
  );
}

function UsageDetail({ usage }: { usage: TrajectoryUsage | null }) {
  if (!usage) return <EmptyDetail>{t('trajectory.usageMissing', '未报告用量')}</EmptyDetail>;
  const contentTokens = usage.completionTokens != null && usage.reasoningTokens != null
    ? Math.max(0, usage.completionTokens - usage.reasoningTokens)
    : null;
  return (
    <DetailRows rows={[
      ...(usage.promptTokens == null ? [] : [[t('trajectory.usage.input', 'Input'), `${usage.promptTokens} tok`] as [string, string]]),
      ...(usage.cacheReadTokens == null ? [] : [[t('trajectory.usage.cached', 'Cached'), `${usage.cacheReadTokens} tok`] as [string, string]]),
      ...(usage.cacheCreationTokens == null ? [] : [[t('trajectory.usage.created', 'Cache created'), `${usage.cacheCreationTokens} tok`] as [string, string]]),
      ...(usage.completionTokens == null ? [] : [[t('trajectory.usage.output', 'Output'), `${usage.completionTokens} tok`] as [string, string]]),
      ...(usage.reasoningTokens == null ? [] : [[t('trajectory.usage.reasoning', 'Reasoning'), `${usage.reasoningTokens} tok`] as [string, string]]),
      ...(contentTokens == null ? [] : [[t('trajectory.usage.content', 'Content'), `${contentTokens} tok`] as [string, string]]),
      ...(usage.totalTokens == null ? [] : [[t('trajectory.usage.total', 'Total'), `${usage.totalTokens} tok`] as [string, string]]),
    ]} />
  );
}

function smoothPath(points: Array<{ x: number; y: number }>): string {
  if (!points.length) return '';
  if (points.length === 1) return `M ${points[0]!.x} ${points[0]!.y}`;
  let path = `M ${points[0]!.x} ${points[0]!.y}`;
  for (let index = 0; index < points.length - 1; index += 1) {
    const previous = points[index - 1] ?? points[index]!;
    const current = points[index]!;
    const next = points[index + 1]!;
    const following = points[index + 2] ?? next;
    const firstControlX = current.x + (next.x - previous.x) / 6;
    const firstControlY = current.y + (next.y - previous.y) / 6;
    const secondControlX = next.x - (following.x - current.x) / 6;
    const secondControlY = next.y - (following.y - current.y) / 6;
    path += ` C ${firstControlX} ${firstControlY}, ${secondControlX} ${secondControlY}, ${next.x} ${next.y}`;
  }
  return path;
}

function ThroughputTrend({
  samples,
  sampleIntervalMs,
  outputCharacters,
  outputTokens,
}: {
  samples: number[];
  sampleIntervalMs: number;
  outputCharacters: number | null;
  outputTokens: number | null;
}) {
  const width = 320;
  const height = 124;
  const inset = 5;
  const tokenRatio = outputCharacters != null && outputCharacters > 0 && outputTokens != null
    ? outputTokens / outputCharacters
    : null;
  const tokenSamples = tokenRatio == null ? [] : samples.map((value) => value * tokenRatio);
  const pointsFor = (values: number[]) => {
    const peak = Math.max(1, ...values);
    return values.map((value, index) => ({
      x: values.length === 1 ? width / 2 : index * width / (values.length - 1),
      y: height - inset - (height - inset * 2) * Math.min(1, value / peak),
    }));
  };
  const characterPoints = pointsFor(samples);
  const tokenPoints = pointsFor(tokenSamples);
  const characterPath = smoothPath(characterPoints);
  const tokenPath = smoothPath(tokenPoints);
  const areaPath = characterPoints.length > 1
    ? `${characterPath} L ${characterPoints.at(-1)!.x} ${height} L ${characterPoints[0]!.x} ${height} Z`
    : '';
  const peakCharacters = Math.max(0, ...samples);
  const peakTokens = tokenSamples.length ? Math.max(0, ...tokenSamples) : null;
  const intervalSeconds = Math.max(1, sampleIntervalMs) / 1000;
  return (
    <section class="oh-trajectory-throughput-chart">
      <header>
        <strong>{t('trajectory.timing.trend', '响应吞吐趋势')}</strong>
        <small>{tFmt('trajectory.timing.sampleSummary', {
          interval: Number.isInteger(intervalSeconds) ? intervalSeconds : intervalSeconds.toFixed(1),
          count: samples.length,
        }, '每 {interval} 秒采样 · {count} 个点')}</small>
      </header>
      <div class="oh-trajectory-throughput-legend">
        <span data-series="characters"><i />{tFmt('trajectory.timing.characterPeak', { value: peakCharacters.toFixed(1) }, '字符/秒 · 峰值 {value}')}</span>
        {peakTokens != null && <span data-series="tokens"><i />{tFmt('trajectory.timing.tokenPeak', { value: peakTokens.toFixed(1) }, '估算 Token/秒 · 峰值 {value}')}</span>}
      </div>
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" role="img" aria-label={t('trajectory.timing.trend', '响应吞吐趋势')}>
        {[0, 1, 2, 3].map((row) => <line key={row} x1="0" x2={width} y1={height * row / 3} y2={height * row / 3} />)}
        {areaPath && <path class="is-area" d={areaPath} />}
        {characterPoints.length === 1
          ? <circle class="is-characters" cx={characterPoints[0]!.x} cy={characterPoints[0]!.y} r="3" />
          : <path class="is-characters" d={characterPath} />}
        {tokenPoints.length === 1
          ? <circle class="is-tokens" cx={tokenPoints[0]!.x} cy={tokenPoints[0]!.y} r="2" />
          : tokenPath && <path class="is-tokens" d={tokenPath} />}
      </svg>
    </section>
  );
}

function TimingDetail({ record, metadata }: { record: TrajectoryRecord; metadata: Record<string, unknown> }) {
  const firstToken = firstTimestamp(metadata, ['first_token_at', 'first_token_time', 'first_visible_at']);
  const startedAt = firstTimestamp(metadata, ['request_started_at', 'started_at']) ?? record.startedAt;
  const totalDuration = firstNumber(metadata, ['total_duration_ms', 'duration_ms']) ?? record.durationMs;
  const ttft = firstNumber(metadata, ['ttft_ms'])
    ?? (startedAt != null && firstToken != null ? Math.max(0, firstToken - startedAt) : null);
  const generation = firstNumber(metadata, ['generation_duration_ms'])
    ?? (totalDuration != null && ttft != null ? Math.max(0, totalDuration - ttft) : null);
  const outputTokens = record.usage?.completionTokens ?? firstNumber(metadata, ['completion_tokens']);
  const outputCharacters = firstNumber(metadata, ['output_characters']);
  const tokensPerSecond = firstNumber(metadata, ['tokens_per_second'])
    ?? (outputTokens != null && generation != null && generation > 0 ? outputTokens / generation * 1000 : null);
  const charactersPerSecond = firstNumber(metadata, ['characters_per_second']);
  const streamEvents = firstNumber(metadata, ['stream_event_count']);
  const fallbackCount = firstNumber(metadata, ['request_fallback_count']);
  const finishReason = textOf(metadata.finish_reason);
  const responseStatus = textOf(metadata.response_status);
  const statusLabel = responseStatus === 'completed'
    ? t('trajectory.completed', '已完成')
    : responseStatus === 'cancelled'
      ? t('trajectory.timing.cancelled', '已取消')
      : responseStatus === 'failed'
        ? t('trajectory.failed', '失败')
        : '';
  const samples = numberList(metadata.stream_throughput_chars_per_second);
  const sampleIntervalMs = firstNumber(metadata, ['stream_throughput_sample_interval_ms']) ?? 1000;
  const notRecorded = t('trajectory.notRecorded', '未记录');
  return <>
    <DetailRows rows={[
    [t('trajectory.timing.started', 'Started'), formatTime(startedAt)],
    [t('trajectory.timing.total', 'Total duration'), formatDuration(totalDuration)],
    [t('trajectory.timing.firstToken', 'First response'), firstToken == null ? notRecorded : formatTime(firstToken)],
    ['TTFT', ttft == null ? t('trajectory.notRecorded', '未记录') : formatDuration(ttft)],
    [t('trajectory.timing.generation', 'Generation'), generation == null ? t('trajectory.notRecorded', '未记录') : formatDuration(generation)],
    [t('trajectory.timing.throughput', 'Throughput'), tokensPerSecond == null ? notRecorded : `${tokensPerSecond.toFixed(1)} tok/s`],
    ...(charactersPerSecond == null ? [] : [[t('trajectory.timing.characterThroughput', 'Character throughput'), `${charactersPerSecond.toFixed(1)} char/s`] as [string, string]]),
    ...(outputCharacters == null ? [] : [[t('trajectory.timing.outputCharacters', 'Output characters'), String(Math.round(outputCharacters))] as [string, string]]),
    ...(streamEvents == null ? [] : [[t('trajectory.timing.streamEvents', 'Stream events'), String(Math.round(streamEvents))] as [string, string]]),
    ...(fallbackCount == null ? [] : [[t('trajectory.timing.fallbacks', 'Request fallbacks'), String(Math.round(fallbackCount))] as [string, string]]),
    ...(finishReason ? [[t('trajectory.timing.finishReason', 'Finish reason'), finishReason] as [string, string]] : []),
    ...(statusLabel ? [[t('trajectory.timing.status', 'Response status'), statusLabel, responseStatus === 'failed'] as [string, string, boolean]] : []),
  ]} />
    {samples.length > 0 && <ThroughputTrend
      samples={samples}
      sampleIntervalMs={sampleIntervalMs}
      outputCharacters={outputCharacters}
      outputTokens={outputTokens}
    />}
  </>;
}

function DetailBody({
  record,
  metadata,
  tab,
}: {
  record: TrajectoryRecord;
  metadata: Record<string, unknown>;
  tab: string;
}) {
  if (tab === 'usage') return <UsageDetail usage={record.usage} />;
  if (tab === 'timing') return <TimingDetail record={record} metadata={metadata} />;
  if (tab === 'system-prompt') {
    const source = systemPrompt(metadata);
    return source ? <div class="oh-trajectory-markdown"><Markdown source={source} /></div> : <EmptyDetail>{t('trajectory.systemPromptMissing', '本次请求未记录系统提示词')}</EmptyDetail>;
  }
  if (tab === 'tools') return <StructuredDetail text={toolCatalog(metadata)} empty={t('trajectory.toolsMissing', '本次请求未记录工具目录')} />;
  if (tab === 'rendered') {
    const source = rawRecordText(record);
    return source ? <div class="oh-trajectory-markdown"><Markdown source={source} /></div> : <EmptyDetail>{t('trajectory.contentMissing', '无内容')}</EmptyDetail>;
  }
  if (tab === 'raw') return <StructuredDetail text={rawRecordText(record)} empty={t('trajectory.contentMissing', '无内容')} />;
  if (tab === 'source') return <StructuredDetail text={prettyValue({
    message_id: record.sourceMessageId,
    turn: record.turn,
    step: record.step,
    request_number: record.requestNumber,
    metadata,
  })} empty={t('trajectory.sourceMissing', '未记录来源')} />;
  if (tab === 'input') return <StructuredDetail text={record.input} empty={t('trajectory.inputMissing', '无输入载荷')} />;
  if (tab === 'output') return <StructuredDetail text={record.output} empty={record.running ? t('trajectory.pending', '等待中') : t('trajectory.outputMissing', '无输出载荷')} error={record.error} />;
  if (tab === 'schema') return <StructuredDetail text={schemaText(metadata)} empty={t('trajectory.schemaMissing', '未记录 Schema')} />;
  if (tab === 'options') return <StructuredDetail text={requestOptions(metadata)} empty={t('trajectory.optionsMissing', '未记录请求选项')} />;

  const status = record.error
    ? t('trajectory.failed', '失败')
    : record.running
      ? t('trajectory.pending', '等待中')
      : t('trajectory.completed', '已完成');
  const model = textOf(record.metadata.model ?? record.metadata.model_id ?? metadata.model ?? metadata.model_id);
  return (
    <div class="oh-trajectory-summary">
      <DetailRows rows={[
        [t('trajectory.status', 'Status'), status, record.error],
        ...(model ? [[t('trajectory.model', 'Model'), model] as [string, string]] : []),
        ...(record.toolName ? [[t('trajectory.tool', 'Tool'), record.toolName] as [string, string]] : []),
        ...(record.callId ? [[t('trajectory.callId', '调用 ID'), record.callId] as [string, string]] : []),
        ...(record.kind === 'assistant' ? [[t('trajectory.tokens', 'Tokens'), record.usage?.completionTokens == null ? '—' : `${record.usage.completionTokens} tok`] as [string, string]] : []),
        [t('trajectory.duration', 'Duration'), formatDuration(record.durationMs)],
      ]} />
      {rawRecordText(record) ? (
        <section>
          <h4>{record.kind === 'tool' ? t('trajectory.result', 'Result') : t('trajectory.preview', 'Preview')}</h4>
          <div class="oh-trajectory-summary-preview"><Markdown source={rawRecordText(record)} /></div>
        </section>
      ) : null}
      {record.kind === 'assistant' ? (
        <>
          <section><h4>{t('trajectory.tab.usage', 'Usage')}</h4><UsageDetail usage={record.usage} /></section>
          <section><h4>{t('trajectory.tab.timing', 'Timing')}</h4><TimingDetail record={record} metadata={metadata} /></section>
        </>
      ) : null}
    </div>
  );
}

function DetailsPanel({
  record,
  metadata,
  loading,
  activeTab,
  onTabChange,
  onClose,
}: {
  record: TrajectoryRecord;
  metadata: Record<string, unknown>;
  loading: boolean;
  activeTab: string;
  onTabChange: (tab: string) => void;
  onClose: () => void;
}) {
  const tabs = recordTabs(record);
  const effectiveTab = tabs.some(([key]) => key === activeTab) ? activeTab : tabs[0]?.[0] ?? 'summary';
  return (
    <aside class="oh-trajectory-details">
      <header>
        <span class={`oh-trajectory-kind is-${record.kind}`}>{kindLabel(record.kind)}</span>
        <strong>{record.turn > 0
          ? tFmt(
            'trajectory.turnStep',
            { turn: record.turn, step: record.step },
            `Turn ${record.turn} · Step ${record.step}`,
          )
          : record.preview}</strong>
        {loading ? <span class="oh-trajectory-spinner" /> : null}
        <button type="button" class="oh-trajectory-icon-button" onClick={onClose} title={t('trajectory.closeDetails', '关闭详情')}>
          <CloseIcon />
        </button>
      </header>
      <nav aria-label={t('trajectory.detailsTabs', '轨迹详情标签')}>
        {tabs.map(([key, label]) => (
          <button
            type="button"
            key={key}
            class={key === effectiveTab ? 'is-active' : undefined}
            onClick={() => onTabChange(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      <div class="oh-trajectory-detail-body">
        <DetailBody record={record} metadata={metadata} tab={effectiveTab} />
      </div>
    </aside>
  );
}

export function TrajectoryDialog({
  sessionId,
  sessionTitle,
  sessionCreatedAt,
  messages,
  messageWindowStart,
  messageTotal,
  hasOlder,
  loadingOlder = false,
  onLoadOlder,
  onClose,
}: TrajectoryDialogProps) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const snapshot = useMemo(() => buildSnapshot(messages, sessionCreatedAt), [messages, sessionCreatedAt]);
  const [actualDuration, setActualDuration] = useState(false);
  const [collapsedTurns, setCollapsedTurns] = useState<Set<number>>(() => new Set());
  const [collapsedCalls, setCollapsedCalls] = useState<Set<string>>(() => new Set());
  const [searchQuery, setSearchQuery] = useState('');
  const [timelineRange, setTimelineRange] = useState<TimelineRange | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState('summary');
  const [detailWidth, setDetailWidth] = useState(DETAIL_DEFAULT_WIDTH);
  const [hydratedMessages, setHydratedMessages] = useState<Map<string, SessionMessage>>(() => new Map());
  const [metadataLoading, setMetadataLoading] = useState(false);
  const tableRef = useRef<HTMLDivElement | null>(null);
  const resizeRef = useRef<{ startX: number; startWidth: number; pointerId: number } | null>(null);
  const loadingEarlierRef = useRef(false);
  const spans = useMemo(() => projectTimeline(snapshot.records, actualDuration), [snapshot.records, actualDuration]);
  const recordsByTurn = useMemo(() => {
    const grouped = new Map<number, TrajectoryRecord[]>();
    for (const record of snapshot.records) {
      if (record.turn <= 0) continue;
      const records = grouped.get(record.turn);
      if (records) records.push(record); else grouped.set(record.turn, [record]);
    }
    return grouped;
  }, [snapshot.records]);
  const selectedRecord = useMemo(
    () => snapshot.records.find((record) => record.id === selectedId) ?? null,
    [selectedId, snapshot.records],
  );
  const searchMatches = useMemo<Set<string> | null>(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) return null;
    return new Set(snapshot.records.filter((record) => searchableText(record).includes(query)).map((record) => record.id));
  }, [searchQuery, snapshot.records]);
  const timelineFocus = useMemo<Set<string> | null>(() => {
    if (!timelineRange) return null;
    return new Set(spans.filter((span) => span.end >= timelineRange.start && span.start <= timelineRange.end).map((span) => span.record.id));
  }, [spans, timelineRange]);
  const allTurnsCollapsed = snapshot.collapsibleTurns.size > 0
    && [...snapshot.collapsibleTurns].every((turn) => collapsedTurns.has(turn));
  const allCallsCollapsed = snapshot.callCounts.size > 0
    && [...snapshot.callCounts.keys()].every((id) => collapsedCalls.has(id));

  useEffect(() => {
    if (!selectedRecord) {
      setMetadataLoading(false);
      return;
    }
    setActiveTab(recordTabs(selectedRecord)[0]?.[0] ?? 'summary');
    const sourceId = selectedRecord.sourceMessageId;
    if (!sourceId || hydratedMessages.has(sourceId)) {
      setMetadataLoading(false);
      return;
    }
    const controller = new AbortController();
    setMetadataLoading(true);
    getSessionMessage(sessionId, sourceId, { signal: controller.signal })
      .then(({ message }) => {
        if (controller.signal.aborted) return;
        setHydratedMessages((current) => {
          const next = new Map(current);
          next.set(sourceId, message);
          return next;
        });
      })
      .catch(ignoreError)
      .finally(() => {
        if (!controller.signal.aborted) setMetadataLoading(false);
      });
    return () => controller.abort();
  }, [selectedRecord?.id, sessionId]);

  useEffect(() => {
    if (!selectedId) return;
    const element = tableRef.current?.querySelector<HTMLElement>(`[data-record-id="${CSS.escape(selectedId)}"]`);
    element?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }, [selectedId]);

  const selectRecord = useCallback((record: TrajectoryRecord) => {
    setSelectedId(record.id);
    setTimelineRange((current) => current && !timelineFocus?.has(record.id) ? null : current);
  }, [timelineFocus]);

  const loadEarlier = useCallback(async () => {
    if (!hasOlder || loadingOlder || loadingEarlierRef.current) return;
    const ledger = tableRef.current;
    const beforeHeight = ledger?.scrollHeight ?? 0;
    const beforeTop = ledger?.scrollTop ?? 0;
    loadingEarlierRef.current = true;
    try {
      await onLoadOlder();
      requestAnimationFrame(() => requestAnimationFrame(() => {
        if (!ledger) return;
        ledger.scrollTop = beforeTop + Math.max(0, ledger.scrollHeight - beforeHeight);
      }));
    } finally {
      loadingEarlierRef.current = false;
    }
  }, [hasOlder, loadingOlder, onLoadOlder]);

  const toggleAllTurns = () => {
    setCollapsedTurns(() => allTurnsCollapsed ? new Set() : new Set(snapshot.collapsibleTurns));
  };
  const toggleTurn = (turn: number) => {
    if (!snapshot.collapsibleTurns.has(turn)) return;
    setCollapsedTurns((current) => {
      const next = new Set(current);
      if (!next.delete(turn)) next.add(turn);
      return next;
    });
  };
  const toggleAllCalls = () => {
    setCollapsedCalls(() => allCallsCollapsed ? new Set() : new Set(snapshot.callCounts.keys()));
  };
  const selectedMetadata = selectedRecord
    ? recordOf(hydratedMessages.get(selectedRecord.sourceMessageId ?? '')?.metadata ?? selectedRecord.metadata)
    : {};
  const messageRangeEnd = messageWindowStart + messages.length;
  const messageRangeTotal = Math.max(messageTotal, messageRangeEnd);
  const messageRangeLabel = messages.length > 0
    ? `${messageWindowStart + 1}-${messageRangeEnd} / ${messageRangeTotal}`
    : `0 / ${messageRangeTotal}`;

  const renderedRows: JSX.Element[] = [];
  const renderedTurnIds = new Set<number>();
  for (let index = 0; index < snapshot.records.length; index += 1) {
    const record = snapshot.records[index]!;
    const turnRecords = recordsByTurn.get(record.turn) ?? [];
    const turnCollapsed = record.turn > 0 && collapsedTurns.has(record.turn);
    const visibleRecord = turnCollapsed
      ? turnRecords.find((candidate) => candidate.kind === 'user') ?? turnRecords[0]
      : record;
    if (turnCollapsed && record.id !== visibleRecord?.id) continue;
    const anchorId = snapshot.callAnchors.get(record.id);
    if (anchorId && collapsedCalls.has(anchorId)) continue;
    const turnStart = record.turn > 0 && !renderedTurnIds.has(record.turn);
    if (record.turn > 0) renderedTurnIds.add(record.turn);
    const callCount = snapshot.callCounts.get(record.id) ?? 0;
    const focused = timelineFocus == null || timelineFocus.has(record.id);
    const matched = searchMatches == null || searchMatches.has(record.id);
    renderedRows.push(
      <div
        role="button"
        tabIndex={0}
        key={record.id}
        data-record-id={record.id}
        data-selected={selectedId === record.id ? 'true' : undefined}
        data-focused={focused ? 'true' : 'false'}
        data-search-match={matched ? 'true' : 'false'}
        data-error={record.error ? 'true' : undefined}
        class="oh-trajectory-record-row"
        onClick={() => selectRecord(record)}
        onDblClick={record.kind === 'user' && snapshot.collapsibleTurns.has(record.turn)
          ? () => toggleTurn(record.turn)
          : undefined}
        onKeyDown={(event) => {
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            selectRecord(record);
          }
        }}
      >
        <span class="oh-trajectory-turn-cell">
          {turnStart ? (
            <span class="oh-trajectory-turn-label">
              {tFmt('trajectory.turn', { turn: record.turn }, `轮次 ${record.turn}`)}
              {snapshot.collapsibleTurns.has(record.turn) ? (
                <i
                  role="button"
                  tabIndex={0}
                  title={turnCollapsed
                    ? t('trajectory.expandTurn', '展开本轮')
                    : t('trajectory.collapseTurn', '折叠本轮')}
                  onClick={(event) => {
                    event.stopPropagation();
                    toggleTurn(record.turn);
                  }}
                  onDblClick={(event) => event.stopPropagation()}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter' || event.key === ' ') {
                      event.preventDefault();
                      event.currentTarget.click();
                    }
                  }}
                >{turnCollapsed ? '+' : '−'}</i>
              ) : null}
            </span>
          ) : null}
          {record.turn > 0 ? <i class="oh-trajectory-turn-dot" /> : null}
        </span>
        <span class="oh-trajectory-event-cell">
          <span class={`oh-trajectory-kind is-${record.kind}`}>{kindLabel(record.kind)}</span>
          {record.requestNumber > 0 && (record.kind === 'assistant' || record.kind === 'compacted') ? (
            <small title={tFmt('trajectory.request', { number: record.requestNumber }, `Request ${record.requestNumber}`)}>#{record.requestNumber}</small>
          ) : null}
        </span>
        <span class="oh-trajectory-content-cell">
          <span>{record.preview || t('trajectory.noContent', '无内容')}</span>
          {record.running ? <i class="oh-trajectory-running-dot" title={t('trajectory.running', '运行中')} /> : null}
          {callCount > 0 ? (
            <i
              role="button"
              tabIndex={0}
              class="oh-trajectory-call-toggle"
              onClick={(event) => {
                event.stopPropagation();
                setCollapsedCalls((current) => {
                  const next = new Set(current);
                  if (next.has(record.id)) next.delete(record.id); else next.add(record.id);
                  return next;
                });
              }}
              onDblClick={(event) => event.stopPropagation()}
              onKeyDown={(event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                  event.preventDefault();
                  event.currentTarget.click();
                }
              }}
            >
              {collapsedCalls.has(record.id) ? '+' : '−'} {tFmt(
                'trajectory.callsCount',
                { count: callCount },
                `${callCount} calls`,
              )}
            </i>
          ) : null}
        </span>
        <span class="oh-trajectory-duration-cell">{formatDuration(record.durationMs)}</span>
      </div>,
    );
    if (turnCollapsed) {
      const hiddenRecords = turnRecords.filter((candidate) => candidate.id !== record.id);
      const duration = hiddenRecords.reduce((sum, candidate) => sum + (candidate.durationMs ?? 0), 0);
      renderedRows.push(
        <button
          type="button"
          key={`collapsed-turn-${record.turn}`}
          class="oh-trajectory-collapsed-row"
          onClick={() => toggleTurn(record.turn)}
        >
          <span>{tFmt('trajectory.turn', { turn: record.turn }, `轮次 ${record.turn}`)}</span>
          <strong>{hiddenRecords.length} {t('trajectory.records', '条记录')}</strong>
          <small>{formatDuration(duration || null)}</small>
        </button>,
      );
    }
  }

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_CENTER_FLUSH_CLASS,
        overlay: {
          background: 'color-mix(in srgb, black 52%, transparent)',
          blurPx: 7,
        },
        overlayZIndex: DIALOG_OVERLAY_FOCUSED_Z_INDEX,
        panelClassName: 'oh-trajectory-dialog',
        panelBorder: 'none',
        panelSurface: {
          width: 'min(1480px, calc(100vw - 32px))',
          maxWidth: 'none',
          maxHeight: 'calc(100dvh - 32px)',
          overflow: 'hidden',
          boxShadow: 'var(--m3-elev-4)',
        },
      })}
      ariaLabel={t('trajectory.title', '轨迹')}
    >
      <div class="oh-trajectory-shell">
        <header class="oh-trajectory-titlebar">
          <span class="oh-trajectory-title-icon"><TrajectoryIcon /></span>
          <div>
            <h2>{t('trajectory.title', '轨迹')}</h2>
            <p title={sessionTitle}>{sessionTitle}</p>
          </div>
          <button type="button" class="oh-trajectory-icon-button" onClick={requestClose} title={t('common.close', '关闭')}>
            <CloseIcon />
          </button>
        </header>
        <div class="oh-trajectory-toolbar" role="toolbar" aria-label={t('trajectory.toolbar', '轨迹工具栏')}>
          <div class="oh-trajectory-toolbar-actions">
            <button
              type="button"
              class={actualDuration ? 'is-active' : undefined}
              aria-pressed={actualDuration}
              onClick={() => {
                setActualDuration((current) => !current);
                setTimelineRange(null);
              }}
              title={actualDuration ? t('trajectory.equalWidth', '使用等宽记录') : t('trajectory.actualDuration', '使用实际耗时')}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8" /><path d="M12 7v5l3 2" /></svg>
              {t('trajectory.duration', 'Duration')}
            </button>
            <button type="button" class={allTurnsCollapsed ? 'is-active' : undefined} onClick={toggleAllTurns}>
              <span>{allTurnsCollapsed ? '⊞' : '⊟'}</span>{t('trajectory.turns', 'Turns')}
            </button>
            <button type="button" class={allCallsCollapsed ? 'is-active' : undefined} onClick={toggleAllCalls}>
              <span>{allCallsCollapsed ? '⊞' : '⊟'}</span>{t('trajectory.calls', 'Calls')}
            </button>
          </div>
          <div class="oh-trajectory-toolbar-end">
            <span class="oh-trajectory-range">{messageRangeLabel}</span>
            <div class="oh-trajectory-search" role="search">
              <SearchIcon />
              <input
                type="search"
                value={searchQuery}
                onInput={(event) => setSearchQuery(event.currentTarget.value)}
                placeholder={t('trajectory.search', '搜索')}
                aria-label={t('trajectory.search', '搜索')}
              />
              {searchQuery ? (
                <>
                  <span>{searchMatches?.size ?? 0}</span>
                  <button
                    type="button"
                    class="oh-trajectory-search-clear"
                    title={t('trajectory.clearSearch', '清除搜索')}
                    aria-label={t('trajectory.clearSearch', '清除搜索')}
                    onClick={() => setSearchQuery('')}
                  >
                    <CloseIcon />
                  </button>
                </>
              ) : null}
            </div>
          </div>
        </div>
        <TrajectoryTimeline
          key={actualDuration ? 'duration' : 'equal'}
          spans={spans}
          range={timelineRange}
          selectedId={selectedId}
          searchMatches={searchMatches}
          hasOlder={hasOlder}
          loadingOlder={loadingOlder}
          onRangeChange={setTimelineRange}
          onSelect={selectRecord}
          onLoadOlder={loadEarlier}
        />
        <div class="oh-trajectory-workspace">
          <div
            ref={tableRef}
            class="oh-trajectory-ledger"
            onScroll={(event) => {
              if (event.currentTarget.scrollTop < 48) void loadEarlier();
            }}
          >
            <div class="oh-trajectory-table-head" aria-hidden="true">
              <span />
              <span>{t('trajectory.event', 'Event')}</span>
              <span>{t('trajectory.content', 'Content')}</span>
              <span>{t('trajectory.duration', 'Duration')}</span>
            </div>
            {loadingOlder ? <div class="oh-trajectory-history-loading"><span class="oh-trajectory-spinner" />{t('trajectory.loadingOlder', '正在加载更早记录…')}</div> : null}
            {hasOlder ? (
              <button type="button" class="oh-trajectory-load-row" disabled={loadingOlder} onClick={() => void loadEarlier()}>
                {loadingOlder ? <span class="oh-trajectory-spinner" /> : '↑'}
                {loadingOlder ? t('trajectory.loadingOlder', '正在加载更早记录…') : t('trajectory.loadOlder', '加载更早记录')}
              </button>
            ) : null}
            {renderedRows}
          </div>
          {selectedRecord ? (
            <>
              <div
                class="oh-trajectory-resizer"
                role="separator"
                aria-orientation="vertical"
                onPointerDown={(event) => {
                  event.currentTarget.setPointerCapture(event.pointerId);
                  resizeRef.current = { startX: event.clientX, startWidth: detailWidth, pointerId: event.pointerId };
                }}
                onPointerMove={(event) => {
                  const resize = resizeRef.current;
                  if (!resize || resize.pointerId !== event.pointerId) return;
                  setDetailWidth(Math.min(DETAIL_MAX_WIDTH, Math.max(DETAIL_MIN_WIDTH, resize.startWidth + resize.startX - event.clientX)));
                }}
                onPointerUp={() => { resizeRef.current = null; }}
                onPointerCancel={() => { resizeRef.current = null; }}
              />
              <div class="oh-trajectory-details-host" style={{ width: `${detailWidth}px` }}>
                <DetailsPanel
                  record={selectedRecord}
                  metadata={selectedMetadata}
                  loading={metadataLoading}
                  activeTab={activeTab}
                  onTabChange={setActiveTab}
                  onClose={() => setSelectedId(null)}
                />
              </div>
            </>
          ) : null}
        </div>
      </div>
    </DialogFrame>
  );
}
