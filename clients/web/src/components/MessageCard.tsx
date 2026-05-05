// 按 AiSessionMessage.kind 分发到不同视觉模板，与 OpenHand APP 端
// `_home_transcript.dart` / `tool_call_card.dart` / `reasoning_card.dart` 等
// 视觉语义对齐。
//
// 复刻范围（基于服务端 _messageJson 已经导出的字段）：
// - user / assistant / system / tool / reasoning
// - tool_call（解析 ```json``` 入参或纯文本）
// - mcp / skill / hook / self_learning / file_mutation_summary / status / compression_point
//
// 不复刻：流式 partial 卡片渐变、tool_call 内嵌 stdin/stdout 折叠（需要更多 metadata 字段）。
// 这些将在后续随服务端契约扩展再补。

import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { Markdown } from './Markdown';
import { MessageMedia } from './MessageMedia';
import { MessageToolMeta } from './MessageToolMeta';
import { ToolResultBody } from './ToolResultBody';
import { memo } from 'preact/compat';
import { useState } from 'preact/hooks';

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
        background: '#1f2024',
        color: '#e8e8ec',
        label: t('detail.kind.reasoning', '思考'),
        icon: '💭',
        badge: true,
        collapsible: true,
      };
    case 'tool_call':
      return {
        background: 'color-mix(in srgb, var(--m3-primary) 10%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, var(--m3-primary) 35%, transparent)',
        label: t('detail.kind.toolCall', '工具调用'),
        icon: '⚙',
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
        background: 'color-mix(in srgb, #6f4dff 12%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, #6f4dff 40%, transparent)',
        label: t('detail.kind.mcp', 'MCP'),
        icon: '⌬',
        badge: true,
        mono: true,
      };
    case 'skill':
      return {
        background: 'color-mix(in srgb, #f5a623 14%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, #f5a623 45%, transparent)',
        label: t('detail.kind.skill', '技能'),
        icon: '✦',
        badge: true,
      };
    case 'hook':
      return {
        background: 'color-mix(in srgb, #00bcd4 12%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, #00bcd4 38%, transparent)',
        label: t('detail.kind.hook', 'Hook'),
        icon: '⚓',
        badge: true,
      };
    case 'self_learning':
      return {
        background: 'color-mix(in srgb, #2ecc71 14%, var(--m3-surface-container))',
        color: 'var(--m3-on-surface)',
        border: '1px solid color-mix(in srgb, #2ecc71 40%, transparent)',
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
        icon: '🗎',
        badge: true,
        mono: true,
      };
    case 'status':
      return {
        background: 'transparent',
        color: 'var(--m3-on-surface-variant)',
        border: '1px dashed var(--m3-outline)',
        label: t('detail.kind.status', '状态'),
        icon: 'ℹ',
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
        icon: '★',
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
  const useToolBody =
    message.kind === 'tool' ||
    message.kind === 'tool_call' ||
    message.kind === 'mcp' ||
    message.kind === 'file_mutation_summary';
  const overflows =
    !useToolBody && style.collapsible && !forceExpanded && content.length > AUTO_COLLAPSE_CHAR_LIMIT;
  const visibleContent = overflows
    ? content.slice(0, AUTO_COLLAPSE_CHAR_LIMIT) + '…'
    : content;

  // 点击卡片切换 action bar 展开。对齐 APP 端 _home_message_bubble.dart 的
  // Listener-based onSelect/onDeselect：再次点击卡片或外部按钮可关闭。
  const [actionsOpen, setActionsOpen] = useState(false);
  const hasAnyAction = Boolean(onCopy || onDelete || onDeleteAfter || onEdit || onAudit);

  return (
    <article
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
        transition: 'outline-color 180ms ease-out',
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
      {message.kind === 'tool_call' || message.kind === 'mcp' ? (
        <ToolArgumentsBlock metadata={message.metadata} />
      ) : null}
      {useToolBody ? (
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
