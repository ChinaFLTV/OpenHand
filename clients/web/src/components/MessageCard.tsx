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

import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { Markdown } from './Markdown';
import { MessageMedia } from './MessageMedia';
import { MessageToolMeta } from './MessageToolMeta';
import { ToolResultBody } from './ToolResultBody';
import { memo } from 'preact/compat';
import { useLayoutEffect, useRef, useState } from 'preact/hooks';
import { showSnackbar } from './Snackbar';
import { copyTextToClipboard } from '../utils/clipboard';

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

interface KindStyle {
  background: string;
  color: string;
  border?: string;
  label: string;
  icon: string;
  /// 标题区是否额外带图标徽章。
  badge?: boolean;
  /// pre-wrap 文字是否走 mono 字体（工具/json 适合）。
  mono?: boolean;
  /// 折叠超长内容（thinking / tool stdout 等）。
  collapsible?: boolean;
}

function styleForKind(kind: string, role: string): KindStyle {
  switch (kind) {
    case 'reasoning':
      return {
        background: 'var(--m3-inverse-surface)',
        color: 'var(--m3-inverse-on-surface)',
        label: t('detail.kind.reasoning', '思考'),
        icon: 'TH',
        badge: true,
        collapsible: true,
      };
    case 'tool_call':
      return {
        background: 'color-mix(in srgb, var(--m3-primary) 10%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-primary) 35%, transparent)',
        label: t('detail.kind.toolCall', '工具调用'),
        icon: 'TC',
        badge: true,
        mono: true,
      };
    case 'tool':
      return {
        background: 'var(--m3-surface)',
        color: 'var(--m3-on-surface)',
        border: '1px solid var(--m3-outline)',
        label: t('detail.kind.tool', '工具结果'),
        icon: '▣',
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
        icon: '⌬',
        badge: true,
        mono: true,
      };
    case 'skill':
      return {
        background: 'color-mix(in srgb, var(--m3-tertiary-container) 66%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-tertiary) 36%, transparent)',
        label: t('detail.kind.skill', '技能'),
        icon: 'SK',
        badge: true,
      };
    case 'hook':
      return {
        background: 'color-mix(in srgb, var(--m3-secondary-container) 66%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-secondary) 34%, transparent)',
        label: t('detail.kind.hook', 'Hook'),
        icon: 'HK',
        badge: true,
      };
    case 'self_learning':
      return {
        background: 'color-mix(in srgb, var(--m3-secondary-container) 76%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-secondary) 36%, transparent)',
        label: t('detail.kind.selfLearning', '自学习'),
        icon: '↻',
        badge: true,
      };
    case 'file_mutation_summary':
      return {
        background: 'color-mix(in srgb, var(--m3-primary) 8%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid var(--m3-outline)',
        label: t('detail.kind.fileMutation', '本轮文件变动汇总'),
        icon: 'FM',
        badge: true,
        mono: true,
      };
    case 'status':
      return {
        background: 'transparent',
        color: 'var(--m3-on-surface-variant)',
        border: '1px dashed var(--m3-outline)',
        label: t('detail.kind.status', '状态'),
        icon: 'ST',
        badge: true,
      };
    case 'compression_point':
      return {
        background: 'transparent',
        color: 'var(--m3-on-surface-variant)',
        border: '1px dashed var(--m3-outline)',
        label: t('detail.kind.compression', '压缩点'),
        icon: '↧',
        badge: true,
      };
    default:
      // user/assistant 等普通文本：按 role 区分 user 主色 / assistant 中性。
      if (role === 'user') {
        return {
          background: 'var(--m3-primary)',
          color: 'var(--m3-on-primary)',
          label: t('detail.role.user', '用户'),
          icon: '@',
        };
      }
      return {
        background: 'var(--m3-surface-container)',
        color: 'var(--m3-on-surface)',
        label: t('detail.role.assistant', '助手'),
        icon: 'AI',
      };
  }
}

// 自动 collapse 长正文（thinking / tool stdout）。阈值经验值，避免一屏被 5K 字符卡片占满。
const AUTO_COLLAPSE_CHAR_LIMIT = 1200;

export interface MessageCardProps {
  message: SessionMessage;
  /// 默认 false；调用方可设为 true 强制展开。
  forceExpanded?: boolean;
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
}

function MessageCardImpl({
  message,
  forceExpanded = false,
  sessionId,
  onCopy,
  onDelete,
  onDeleteAfter,
  onEdit,
  onAudit,
}: MessageCardProps) {
  const style = styleForKind(message.kind, message.role);
  const content = message.content ?? '';
  const useStructuredToolBody =
    message.kind === 'tool' ||
    message.kind === 'tool_call' ||
    message.kind === 'mcp';
  const useToolBody = useStructuredToolBody || message.kind === 'file_mutation_summary';
  const overflows =
    !useToolBody && style.collapsible && !forceExpanded && content.length > AUTO_COLLAPSE_CHAR_LIMIT;
  const visibleContent = overflows
    ? content.slice(0, AUTO_COLLAPSE_CHAR_LIMIT) + '…'
    : content;

  // 点击卡片切换 action bar 展开。对齐 APP 端 _home_message_bubble.dart 的
  // Listener-based onSelect/onDeselect：再次点击卡片或外部按钮可关闭。
  const [actionsOpen, setActionsOpen] = useState(false);
  const hasAnyAction = Boolean(onCopy || onDelete || onDeleteAfter || onEdit || onAudit);
  const cardRef = useRef<HTMLElement | null>(null);
  const lastHeightRef = useRef<number | null>(null);

  useLayoutEffect(() => {
    const el = cardRef.current;
    if (!el || typeof window === 'undefined') return;
    const nextHeight = el.getBoundingClientRect().height;
    const previousHeight = lastHeightRef.current;
    lastHeightRef.current = nextHeight;
    const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
    if (reduceMotion || previousHeight == null || Math.abs(previousHeight - nextHeight) < 2) return;
    el.style.overflow = 'clip';
    const animation = el.animate([
      { height: `${previousHeight}px`, transform: 'scale(0.998)' },
      { height: `${nextHeight}px`, transform: 'scale(1.004)' },
      { height: `${nextHeight}px`, transform: 'scale(1)' },
    ], {
      duration: 360,
      easing: 'cubic-bezier(.2, .9, .2, 1)',
    });
    animation.onfinish = () => {
      el.style.overflow = '';
    };
    animation.oncancel = animation.onfinish;
    return () => animation.cancel();
  }, [visibleContent, content, actionsOpen, message.kind, message.metadata]);

  return (
    <article
      ref={cardRef}
      class="rounded-m3-md p-4 oh-appear-up"
      style={{
        background: style.background,
        color: style.color,
        boxShadow: style.border ? 'none' : 'var(--m3-elev-1)',
        border: style.border,
        cursor: hasAnyAction ? 'pointer' : 'default',
        outline: actionsOpen
          ? '2px solid color-mix(in srgb, var(--m3-primary) 60%, transparent)'
          : 'none',
        outlineOffset: '2px',
        transformOrigin: 'center top',
        transition: 'outline-color 180ms ease-out, box-shadow 220ms ease-out, border-color 220ms ease-out',
      }}
      onClick={(ev) => {
        if (!hasAnyAction) return;
        // 点击交互元素（按钮 / 链接 / 输入框）时不切换 selection。
        const target = ev.target as HTMLElement;
        if (target.closest('button,a,input,textarea,select,[role="button"]')) return;
        // 双击代码块选中文本时也不切换。
        const sel = typeof window !== 'undefined' ? window.getSelection() : null;
        if (sel && sel.toString().length > 0) return;
        setActionsOpen((v) => !v);
      }}
    >
      <header class="flex items-center justify-between gap-3 text-xs mb-2 opacity-90">
        <span class="flex items-center gap-2 min-w-0">
          {style.badge ? (
            <span
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
              style={{
                background: 'color-mix(in srgb, currentColor 14%, transparent)',
              }}
            >
              <span aria-hidden>{style.icon}</span>
              <span>{style.label}</span>
            </span>
          ) : (
            <span class="opacity-90">
              {roleLabel(message.role)}
              {message.kind && message.kind !== 'text' && message.kind !== 'user' && message.kind !== 'assistant'
                ? ` · ${message.kind}`
                : ''}
            </span>
          )}
          {message.model_label ? (
            <span class="truncate opacity-75">· {message.model_label}</span>
          ) : null}
        </span>
        <span class="opacity-75 flex-none">{formatTimestamp(message.created_at)}</span>
      </header>
      <MessageToolMeta message={message} />
      {message.kind === 'file_mutation_summary' ? (
        <FileMutationSummaryCard message={message} />
      ) : useStructuredToolBody ? (
        <ToolExecutionCard message={message} />
      ) : useToolBody ? (
        content.length > 0 ? <ToolResultBody content={content} /> : null
      ) : (
        <Markdown
          source={visibleContent}
          raw={style.mono === true || message.kind === 'reasoning'}
          mono={style.mono === true}
        />
      )}      {sessionId ? <MessageMedia message={message} sessionId={sessionId} /> : null}
      {overflows ? (
        <p class="text-xs mt-2 opacity-70">
          {t('detail.collapsed.hint', '内容已折叠（超过 1200 字符），点击下方刷新或加载更早可在控制台查看完整正文。')}
        </p>
      ) : null}
      {actionsOpen && hasAnyAction ? (
        <div
          class="oh-appear-up mt-3 pt-3 flex flex-wrap items-center gap-2 text-xs"
          style={{
            borderTop: '1px solid color-mix(in srgb, currentColor 18%, transparent)',
          }}
        >
          {onCopy ? (
            <ActionBtn label={t('common.copy')} onClick={() => onCopy(message)} />
          ) : null}
          {onEdit && message.role === 'user' ? (
            <ActionBtn label={t('common.edit')} onClick={() => onEdit(message)} />
          ) : null}
          {onAudit ? (
            <ActionBtn label={t('common.audit')} onClick={() => onAudit(message)} />
          ) : null}
          {onDelete ? (
            <ActionBtn
              label={t('common.delete')}
              variant="danger"
              onClick={() => onDelete(message)}
            />
          ) : null}
          {onDeleteAfter ? (
            <ActionBtn
              label={t('common.deleteAfter')}
              variant="danger"
              onClick={() => onDeleteAfter(message)}
            />
          ) : null}
        </div>
      ) : null}
    </article>
  );
}

function ActionBtn({
  label,
  onClick,
  variant,
}: {
  label: string;
  onClick: () => void;
  variant?: 'danger';
}) {
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      class="oh-tap-press px-2.5 py-1 rounded-m3-sm transition-colors"
      style={{
        color: variant === 'danger' ? 'var(--m3-error)' : 'currentColor',
        border: '1px solid color-mix(in srgb, currentColor 28%, transparent)',
        background: 'transparent',
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLElement).style.background =
          'color-mix(in srgb, currentColor 8%, transparent)';
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLElement).style.background = 'transparent';
      }}
    >
      {label}
    </button>
  );
}

// 用 memo 包裹 MessageCard，跳过 props 等价时的重渲染——SSE 80ms snapshot 期间
// 只有"流式增量的最后一条"会真正变更引用，其余卡片直接命中 memo 缓存，
// 不再重做 markdown 解析 / 高亮 / 媒体解码，达到肉眼"逐字 / 逐 token 增长"。
// 我们仅依赖父级 mergeStream 已经保证不变前缀的引用稳定，因此默认 shallow compare 已足够。
export const MessageCard = memo(MessageCardImpl);

function ToolExecutionCard({ message }: { message: SessionMessage }) {
  const metadata = message.metadata ?? {};
  const stdout = asString(metadata['tool_execution_stdout']);
  const stderr = asString(metadata['tool_execution_stderr']);
  const result = asString(metadata['tool_execution_result'] ?? metadata['result_text']);
  const command = asString(metadata['tool_execution_command'] ?? metadata['command']);
  const workingDirectory = asString(metadata['tool_execution_working_directory'] ?? metadata['working_directory']);
  const status = asString(
    metadata['tool_execution_status'] ??
      metadata['tool_status'] ??
      metadata['status'],
  );
  const elapsedMs = asNumber(metadata['tool_execution_elapsed_ms'] ?? metadata['tool_execution_duration_ms']);
  const exitCode = asNumber(metadata['tool_execution_exit_code'] ?? metadata['exit_code']);
  const argumentsStreaming = asBool(metadata['tool_arguments_streaming']);
  const statusLower = status.toLowerCase();
  const terminalStatus =
    statusLower === 'success' ||
    statusLower === 'ok' ||
    statusLower === 'completed' ||
    statusLower === 'failed' ||
    statusLower === 'failure' ||
    statusLower === 'error' ||
    statusLower === 'denied' ||
    statusLower === 'rejected' ||
    statusLower === 'timed_out' ||
    statusLower === 'invalid_arguments' ||
    statusLower === 'cancelled' ||
    statusLower === 'canceled' ||
    statusLower === 'aborted' ||
    statusLower === 'blocked';
  const fallback = message.content ?? '';
  const hasStructuredOutput = stdout || stderr || result || command || workingDirectory;
  const constructing =
    (!terminalStatus && argumentsStreaming) ||
    (message.kind === 'tool_call' && !status && !hasStructuredOutput && fallback.trim().length === 0);

  return (
    <div class="flex flex-col gap-2">
      <div class="flex flex-wrap gap-1.5 text-[11px]">
        {status ? <MetaChip label={status} tone={status.toLowerCase().includes('error') ? 'danger' : 'neutral'} /> : null}
        {elapsedMs != null ? <MetaChip label={`${elapsedMs} ms`} /> : null}
        {exitCode != null ? <MetaChip label={`exit ${exitCode}`} tone={exitCode === 0 ? 'ok' : 'danger'} /> : null}
        {workingDirectory ? <MetaChip label={workingDirectory} mono /> : null}
        {constructing ? <ConstructingBadge /> : null}
      </div>
      <ToolArgumentsBlock metadata={metadata} />
      {command ? (
        <ToolSection title={t('detail.tool.command', '执行命令')} content={command} defaultExpanded />
      ) : null}
      {stdout ? (
        <ToolSection title={t('detail.tool.stdout', '标准输出 stdout')} content={stdout} />
      ) : null}
      {stderr ? (
        <ToolSection title={t('detail.tool.stderr', '标准错误 stderr')} content={stderr} danger defaultExpanded />
      ) : null}
      {result ? (
        <ToolSection title={t('detail.tool.result', '工具结果')} content={result} defaultExpanded={!stdout && !stderr} />
      ) : null}
      {!hasStructuredOutput && fallback.trim().length > 0 ? <ToolResultBody content={fallback} /> : null}
    </div>
  );
}

function FileMutationSummaryCard({ message }: { message: SessionMessage }) {
  const metadata = message.metadata ?? {};
  const paths = collectMutationPaths(metadata);
  const recordCount = asNumber(metadata['round_summary_record_count']);
  const kind = asString(metadata['file_mutation_kind']);
  const reason = asString(
    metadata['file_mutation_write_reason'] ??
      metadata['write_analysis_reason'] ??
      metadata['tool_execution_write_analysis_reason'],
  );
  return (
    <div
      class="rounded-m3-sm p-3"
      style={{
        background: 'var(--m3-surface)',
        border: '1px solid var(--m3-outline)',
      }}
    >
      <div class="flex items-center justify-between gap-2 mb-2">
        <div class="flex items-center gap-2 min-w-0">
          <span class="text-sm font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
            {t('detail.fileMutation.title', '文件变动')}
          </span>
          {kind ? <MetaChip label={kind} /> : null}
        </div>
        {recordCount != null ? (
          <span class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {recordCount} {t('detail.fileMutation.records', '条记录')}
          </span>
        ) : null}
      </div>
      {paths.length > 0 ? (
        <ul class="flex flex-col gap-1.5">
          {paths.map((path) => (
            <li
              key={path}
              class="flex items-center gap-2 text-xs rounded-m3-sm px-2 py-1.5"
              style={{
                background: 'var(--m3-surface-container)',
                color: 'var(--m3-on-surface)',
              }}
            >
              <span aria-hidden>{kind === 'delete' ? '−' : kind === 'write' ? '+' : '±'}</span>
              <span class="font-mono truncate" title={path}>{path}</span>
              <button
                type="button"
                class="oh-tap-press ml-auto text-[11px] px-1.5 py-0.5 rounded-m3-sm"
                style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
                onClick={(e) => {
                  e.stopPropagation();
                  void copyPathWithFeedback(path);
                }}
              >
                {t('common.copy', '复制')}
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
          {recordCount != null
            ? t('detail.fileMutation.summaryOnly', '本轮文件变动记录已归档，可在 App 端查看完整 diff 与撤销记录。')
            : t('detail.fileMutation.empty', '暂无可展示的文件路径。')}
        </p>
      )}
      {reason ? (
        <p class="text-xs mt-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
}: {
  title: string;
  content: string;
  danger?: boolean;
  defaultExpanded?: boolean;
}) {
  const long = content.length > 640 || content.split('\n').length > 10;
  const [expanded, setExpanded] = useState(defaultExpanded || !long);
  return (
    <section>
      <div class="flex items-center gap-2 mb-1 text-[11px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
        <span style={{ fontWeight: 600, color: danger ? 'var(--m3-error)' : undefined }}>{title}</span>
        {long ? (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setExpanded((v) => !v);
            }}
            class="px-1.5 py-0.5 rounded-m3-sm"
            style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface-variant)', background: 'var(--m3-surface)', fontSize: 10 }}
          >
            {expanded ? t('detail.tool.body.collapse', '折叠') : t('detail.tool.body.expand', '展开全部 ')}
          </button>
        ) : null}
      </div>
      <pre
        class="text-[11px] leading-snug whitespace-pre-wrap font-mono rounded-m3-sm p-2 m-0"
        style={{
          background: 'var(--m3-surface)',
          color: danger ? 'var(--m3-error)' : 'var(--m3-on-surface)',
          border: `1px solid ${danger ? 'color-mix(in srgb, var(--m3-error) 45%, transparent)' : 'var(--m3-outline)'}`,
          wordBreak: 'break-word',
          maxHeight: !expanded && long ? '160px' : undefined,
          overflow: !expanded && long ? 'hidden' : 'auto',
        }}
      >
        {content}
      </pre>
    </section>
  );
}

function MetaChip({ label, tone = 'neutral', mono }: { label: string; tone?: 'neutral' | 'ok' | 'danger'; mono?: boolean }) {
  const color = tone === 'danger' ? 'var(--m3-error)' : tone === 'ok' ? 'var(--m3-primary)' : 'var(--m3-on-surface-variant)';
  return (
    <span
      class="inline-flex items-center px-1.5 py-0.5 rounded-m3-sm"
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

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : value == null ? '' : String(value).trim();
}

function asNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asBool(value: unknown): boolean {
  return value === true || value === 'true' || value === 1 || value === '1';
}

/// 工具入参展示块：将 metadata.tool_arguments 渲染为可折叠的 JSON 代码块。
/// - 字符串 → 尝试 JSON.parse 后 pretty-print；解析失败按原文展示。
/// - 默认折叠到 4 行；点击「展开/折叠」切换。
/// - 与工具结果（ToolResultBody）共享视觉语言：mono 字体、surface 背景、outline 边框。
function ToolArgumentsBlock({ metadata }: { metadata: Record<string, unknown> | undefined }) {
  const raw = metadata?.['tool_arguments'];
  if (raw == null) return null;
  let pretty: string;
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (trimmed === '') return null;
    try {
      pretty = JSON.stringify(JSON.parse(trimmed), null, 2);
    } catch {
      pretty = trimmed;
    }
  } else {
    try {
      pretty = JSON.stringify(raw, null, 2);
    } catch {
      pretty = String(raw);
    }
  }
  const [expanded, setExpanded] = useState(false);
  const lineCount = pretty.split('\n').length;
  const overflow = lineCount > 4 || pretty.length > 200;
  return (
    <div class="mb-2">
      <div
        class="text-[11px] mb-1 flex items-center gap-2"
        style={{ color: 'var(--m3-on-surface-variant)' }}
      >
        <span style={{ fontWeight: 600 }}>{t('detail.tool.argumentsTitle', '工具入参')}</span>
        {overflow ? (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setExpanded((v) => !v);
            }}
            class="px-1.5 py-0.5 rounded-m3-sm"
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
        class="text-[11px] leading-snug whitespace-pre-wrap font-mono rounded-m3-sm p-2 m-0"
        style={{
          background: 'var(--m3-surface)',
          color: 'var(--m3-on-surface)',
          border: '1px solid var(--m3-outline)',
          wordBreak: 'break-word',
          maxHeight: !expanded && overflow ? '88px' : undefined,
          overflow: !expanded && overflow ? 'hidden' : 'auto',
        }}
      >
        {pretty}
      </pre>
    </div>
  );
}
