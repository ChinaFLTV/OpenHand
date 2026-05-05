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
}

export function MessageCard({ message, forceExpanded = false }: MessageCardProps) {
  const style = styleForKind(message.kind, message.role);
  const content = message.content ?? '';
  const overflows = style.collapsible && !forceExpanded && content.length > AUTO_COLLAPSE_CHAR_LIMIT;
  const visibleContent = overflows
    ? content.slice(0, AUTO_COLLAPSE_CHAR_LIMIT) + '…'
    : content;

  return (
    <article
      class="rounded-m3-md p-4 oh-appear-up"
      style={{
        background: style.background,
        color: style.color,
        boxShadow: style.border ? 'none' : 'var(--m3-elev-1)',
        border: style.border,
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
      <Markdown
        source={visibleContent}
        raw={style.mono === true || message.kind === 'tool_call' || message.kind === 'tool' || message.kind === 'reasoning'}
        mono={style.mono === true}
      />
      {overflows ? (
        <p class="text-xs mt-2 opacity-70">
          {t('detail.collapsed.hint', '内容已折叠（超过 1200 字符），点击下方刷新或加载更早可在控制台查看完整正文。')}
        </p>
      ) : null}
    </article>
  );
}
