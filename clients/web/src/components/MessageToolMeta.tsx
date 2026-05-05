// 工具调用 / 工具结果 / MCP / Skill / Hook / FileMutationSummary 等
// 元数据驱动型消息的"细节条":
// - 工具名 pill
// - 状态徽章 (running/success/error/streaming)
// - 文件路径 (file_mutation_path / read_file_path)
// - 写入原因 (file_mutation_write_reason 等)
// - 「构造中…」灰描边动画 (tool_arguments_streaming=true 时)
// 与 App 端 _ToolCallBody / _ToolConstructingBadge 视觉对齐。

import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';

interface ExtractedMeta {
  toolName: string;
  status: string;
  filePath: string;
  mutationKind: string;
  writeReason: string;
  command: string;
  argumentsStreaming: boolean;
  awaitingApproval: boolean;
  approved: boolean;
  recordCount: number;
  mcpServerName: string;
  mcpToolName: string;
  toolSource: string;
}

function asString(v: unknown): string {
  if (v == null) return '';
  return String(v).trim();
}

function asBool(v: unknown): boolean {
  return v === true || v === 'true' || v === 1 || v === '1';
}

function asNumber(v: unknown): number {
  if (typeof v === 'number') return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function extract(meta: Record<string, unknown> | undefined): ExtractedMeta {
  const m = meta ?? {};
  return {
    toolName: asString(m['tool_name'] ?? m['name']),
    status: asString(
      m['tool_execution_status'] ??
        m['tool_status'] ??
        m['status'],
    ),
    filePath: asString(m['file_mutation_path'] ?? m['read_file_path']),
    mutationKind: asString(m['file_mutation_kind']),
    writeReason: asString(
      m['file_mutation_write_reason'] ??
        m['write_analysis_reason'] ??
        m['tool_execution_write_analysis_reason'],
    ),
    command: asString(m['tool_execution_command']),
    argumentsStreaming: asBool(m['tool_arguments_streaming']),
    awaitingApproval: asBool(m['plan_mode_awaiting_approval']),
    approved: asBool(m['plan_mode_approved']),
    recordCount: asNumber(m['round_summary_record_count']),
    mcpServerName: asString(m['mcp_server_name']),
    mcpToolName: asString(m['mcp_tool_name']),
    toolSource: asString(m['tool_source']),
  };
}

function statusVisual(status: string): { color: string; label: string; icon: string } {
  const s = status.toLowerCase();
  if (s === 'running' || s === 'pending' || s === 'in_progress') {
    return {
      color: 'var(--m3-primary)',
      label: t('detail.tool.status.running', '运行中'),
      icon: '⟳',
    };
  }
  if (s === 'success' || s === 'ok' || s === 'completed') {
    return {
      color: 'var(--m3-secondary)',
      label: t('detail.tool.status.success', '成功'),
      icon: '✓',
    };
  }
  if (s === 'timed_out') {
    return {
      color: 'var(--m3-error)',
      label: t('detail.tool.status.timedOut', '已超时'),
      icon: 'TO',
    };
  }
  if (s === 'invalid_arguments') {
    return {
      color: 'var(--m3-error)',
      label: t('detail.tool.status.invalidArguments', '参数错误'),
      icon: '!',
    };
  }
  if (s === 'denied' || s === 'rejected' || s === 'blocked') {
    return {
      color: 'var(--m3-error)',
      label: t('detail.tool.status.blocked', '已拦截'),
      icon: '⊘',
    };
  }
  if (s === 'error' || s === 'failed' || s === 'failure') {
    return {
      color: 'var(--m3-error)',
      label: t('detail.tool.status.error', '失败'),
      icon: '✕',
    };
  }
  if (s === 'cancelled' || s === 'canceled' || s === 'aborted') {
    return {
      color: 'var(--m3-on-surface-variant)',
      label: t('detail.tool.status.cancelled', '已取消'),
      icon: '⌽',
    };
  }
  return {
    color: 'var(--m3-on-surface-variant)',
    label: status,
    icon: '·',
  };
}

function isTerminalStatus(status: string): boolean {
  const s = status.toLowerCase();
  return (
    s === 'success' ||
    s === 'ok' ||
    s === 'completed' ||
    s === 'failed' ||
    s === 'failure' ||
    s === 'error' ||
    s === 'denied' ||
    s === 'rejected' ||
    s === 'timed_out' ||
    s === 'invalid_arguments' ||
    s === 'cancelled' ||
    s === 'canceled' ||
    s === 'aborted' ||
    s === 'blocked'
  );
}

export function MessageToolMeta({ message }: { message: SessionMessage }) {
  const ex = extract(message.metadata as Record<string, unknown> | undefined);
  const kind = message.kind;
  const showCard =
    kind === 'tool_call' ||
    kind === 'tool' ||
    kind === 'mcp' ||
    kind === 'skill' ||
    kind === 'hook' ||
    kind === 'file_mutation_summary';
  if (!showCard) return null;

  const sv = ex.status ? statusVisual(ex.status) : null;
  const argumentsStreaming = ex.argumentsStreaming && !isTerminalStatus(ex.status);
  const isFileMutation = kind === 'file_mutation_summary';

  return (
    <div
      class="text-xs flex flex-wrap items-center gap-1.5 mb-2"
      style={{ color: 'var(--m3-on-surface-variant)' }}
    >
      {ex.toolName ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm font-mono"
          style={{
            background: 'color-mix(in srgb, var(--m3-primary) 14%, transparent)',
            color: 'var(--m3-primary)',
            fontWeight: 600,
          }}
          title={ex.toolName}
        >
          {ex.toolName}
        </span>
      ) : null}
      {(ex.mcpServerName || ex.mcpToolName) ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm font-mono"
          style={{
            background: 'color-mix(in srgb, var(--m3-tertiary) 14%, transparent)',
            color: 'var(--m3-tertiary)',
            fontWeight: 600,
          }}
          title={`MCP · ${ex.mcpServerName || '?'} / ${ex.mcpToolName || '?'}`}
        >
          🜲 {ex.mcpServerName || '?'}
          {ex.mcpToolName ? ` · ${ex.mcpToolName}` : ''}
        </span>
      ) : null}
      {ex.toolSource && ex.toolSource !== 'builtin' && !ex.mcpServerName ? (
        <span
          class="inline-flex items-center px-1.5 py-0.5 rounded-m3-sm text-[10px] uppercase tracking-wide"
          style={{
            background: 'color-mix(in srgb, var(--m3-on-surface-variant) 12%, transparent)',
            color: 'var(--m3-on-surface-variant)',
          }}
        >
          {ex.toolSource}
        </span>
      ) : null}
      {argumentsStreaming ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm oh-pulse-soft"
          style={{
            border: '1px dashed var(--m3-outline)',
            color: 'var(--m3-on-surface-variant)',
          }}
          title={t('detail.tool.streaming.hint', '参数构造中…')}
        >
          ⟳ {t('detail.tool.streaming', '构造中…')}
        </span>
      ) : null}
      {sv && !argumentsStreaming ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
          style={{
            border: `1px solid ${sv.color}`,
            color: sv.color,
            background: `color-mix(in srgb, ${sv.color} 10%, transparent)`,
          }}
        >
          <span aria-hidden>{sv.icon}</span>
          {sv.label}
        </span>
      ) : null}
      {ex.command ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm font-mono truncate max-w-[260px]"
          style={{
            border: '1px solid var(--m3-outline)',
            color: 'var(--m3-on-surface-variant)',
            background: 'var(--m3-surface)',
          }}
          title={ex.command}
        >
          $ {ex.command}
        </span>
      ) : null}
      {ex.filePath ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm font-mono truncate max-w-[320px]"
          style={{
            border: '1px solid var(--m3-outline)',
            color: 'var(--m3-on-surface)',
            background: 'var(--m3-surface)',
          }}
          title={ex.filePath}
        >
          {ex.filePath}
        </span>
      ) : null}
      {ex.mutationKind ? (
        <span
          class="inline-flex items-center px-1.5 py-0.5 rounded-m3-sm"
          style={{
            background: 'color-mix(in srgb, var(--m3-primary) 8%, transparent)',
            color: 'var(--m3-primary)',
            fontWeight: 600,
          }}
        >
          {ex.mutationKind}
        </span>
      ) : null}
      {ex.awaitingApproval ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
          style={{
            background: 'var(--m3-tertiary-container)',
            color: 'var(--m3-on-tertiary-container)',
            fontWeight: 600,
          }}
        >
          {t('detail.tool.awaitingApproval', '等待审批')}
        </span>
      ) : null}
      {ex.approved ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
          style={{
            background: 'var(--m3-secondary-container)',
            color: 'var(--m3-on-secondary-container)',
            fontWeight: 600,
          }}
        >
          ✓ {t('detail.tool.approved', '已审批')}
        </span>
      ) : null}
      {isFileMutation && ex.recordCount > 0 ? (
        <span
          class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
          style={{
            background: 'color-mix(in srgb, var(--m3-primary) 12%, transparent)',
            color: 'var(--m3-primary)',
            fontWeight: 600,
          }}
        >
          {t('detail.tool.fileMutationCount', '本轮变动 ')}
          {ex.recordCount}
          {t('detail.tool.records', ' 条')}
        </span>
      ) : null}
      {ex.writeReason ? (
        <span
          class="text-[11px] basis-full mt-1 italic truncate"
          style={{ color: 'var(--m3-on-surface-variant)' }}
          title={ex.writeReason}
        >
          {t('detail.tool.writeReason', '写入原因：')}
          {ex.writeReason}
        </span>
      ) : null}
    </div>
  );
}
