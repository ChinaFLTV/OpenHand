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
import type { ComponentChildren } from 'preact';
import { t } from '../i18n';
import { Markdown } from './Markdown';
import { MediaGeneratingPlaceholder } from './MediaGeneratingPlaceholder';
import { MessageMedia } from './MessageMedia';
import { MessageToolMeta } from './MessageToolMeta';
import { ToolResultBody } from './ToolResultBody';
import { memo } from 'preact/compat';
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { showSnackbar } from './Snackbar';
import { copyTextToClipboard } from '../utils/clipboard';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { getDialogMotionDurationMs } from '../hooks/useDialogMotionSettings';

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
  | 'attachmentText'
  | 'attachmentSpreadsheet'
  | 'attachmentPdf'
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
  | 'user'
  | 'assistant'
  | 'copy'
  | 'edit'
  | 'audit'
  | 'trash'
  | 'cascade'
  | 'chevronDown'
  | 'chevronUp'
  | 'write'
  | 'delete'
  | 'mutate';

function MessageIcon({ name, size = 16 }: { name: MessageIconName; size?: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.9,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    focusable: 'false',
    'aria-hidden': true,
  };
  switch (name) {
    case 'image':
      return <svg {...common}><rect x="4" y="5" width="16" height="14" rx="2.5" /><path d="m7 16 4-4 3 3 2-2 3 3" /><circle cx="9" cy="9" r="1.2" /></svg>;
    case 'video':
      return <svg {...common}><rect x="4" y="7" width="12" height="10" rx="2" /><path d="m16 11 4-2.5v7L16 13" /></svg>;
    case 'audio':
      return <svg {...common}><path d="M9 18V6l10-2v12" /><circle cx="7" cy="18" r="2" /><circle cx="17" cy="16" r="2" /></svg>;
    case 'deepResearch':
      return <svg {...common}><circle cx="11" cy="11" r="6" /><path d="m16 16 4 4" /><path d="M8.5 11h5M11 8.5v5" /></svg>;
    case 'attachmentText':
      return <svg {...common}><path d="M7 3h7l3 3v15H7z" /><path d="M14 3v4h4" /><path d="M9.5 12h5M9.5 16h4" /></svg>;
    case 'attachmentSpreadsheet':
      return <svg {...common}><rect x="5" y="4" width="14" height="16" rx="2" /><path d="M5 10h14M5 15h14M10 4v16M15 4v16" /></svg>;
    case 'attachmentPdf':
      return <svg {...common}><path d="M7 3h7l3 3v15H7z" /><path d="M14 3v4h4" /><path d="M9.5 16h5" /><path d="M9.5 12h1.5a1.5 1.5 0 0 1 0 3H9.5z" /></svg>;
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
    case 'trash':
      return <svg {...common}><path d="M4 7h16" /><path d="M10 11v6M14 11v6" /><path d="M6 7l1 14h10l1-14" /><path d="M9 7V4h6v3" /></svg>;
    case 'cascade':
      return <svg {...common}><path d="M5 6h14" /><path d="M8 12h8" /><path d="M10 18h4" /><path d="M18 6v5a7 7 0 0 1-7 7" /></svg>;
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
  }
}

function styleForKind(kind: string, role: string): KindStyle {
  switch (kind) {
    case 'reasoning':
      return {
        background: 'var(--m3-inverse-surface)',
        color: 'var(--m3-inverse-on-surface)',
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
        background: 'var(--m3-surface-container)',
        color: 'var(--m3-on-surface)',
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
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function nonEmptyString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function messageContextChips(message: SessionMessage): MessageContextChip[] {
  if (message.role !== 'user') return [];
  const meta = asRecord(message.metadata);
  if (!meta) return [];
  return [
    ...creationModeChips(meta),
    ...skillChips(meta),
    ...attachmentChips(meta),
  ];
}

function creationModeChips(meta: Record<string, unknown>): MessageContextChip[] {
  const request = asRecord(meta['creation_request']);
  const options = asRecord(request?.['options']);
  const mode = nonEmptyString(request?.['mode']) || nonEmptyString(meta['conversation_mode']);
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

function creationOptionDetail(options: Record<string, unknown> | null): string {
  if (!options) return '';
  const parts: string[] = [];
  const aspectRatio = nonEmptyString(options['aspect_ratio']);
  const size = nonEmptyString(options['size']);
  const duration = typeof options['duration_seconds'] === 'number'
    ? Math.round(options['duration_seconds'])
    : Number.parseInt(nonEmptyString(options['duration_seconds']), 10);
  const count = typeof options['count'] === 'number'
    ? Math.round(options['count'])
    : Number.parseInt(nonEmptyString(options['count']), 10);
  if (aspectRatio) parts.push(aspectRatio);
  else if (size) parts.push(size);
  if (Number.isFinite(duration) && duration > 0) parts.push(`${duration}s`);
  if (Number.isFinite(count) && count > 1) parts.push(`x${count}`);
  return parts.join(' · ');
}

function skillChips(meta: Record<string, unknown>): MessageContextChip[] {
  const skill = asRecord(meta['user_skill_selection']) ?? asRecord(meta['selected_skill']);
  const name = nonEmptyString(skill?.['name']);
  if (!name) return [];
  const emoji = nonEmptyString(skill?.['emoji']);
  return [{
    key: `skill:${name}`,
    icon: emoji ? undefined : 'skill',
    emoji: emoji || undefined,
    label: `${t('message.context.skill', '技能')} · ${name}`,
  }];
}

type AttachmentKind = 'image' | 'text' | 'spreadsheet' | 'pdf' | 'binary';

function attachmentChips(meta: Record<string, unknown>): MessageContextChip[] {
  const counts = new Map<AttachmentKind, number>();
  const attachments = meta['attachments'];
  if (Array.isArray(attachments)) {
    for (const item of attachments) {
      const kind = attachmentKindFor(item);
      counts.set(kind, (counts.get(kind) ?? 0) + 1);
    }
  }
  if (counts.size === 0) {
    const count = typeof meta['attachment_count'] === 'number'
      ? Math.max(0, Math.round(meta['attachment_count']))
      : Number.parseInt(nonEmptyString(meta['attachment_count']), 10);
    if (Number.isFinite(count) && count > 0) counts.set('binary', count);
  }
  const order: AttachmentKind[] = ['image', 'text', 'spreadsheet', 'pdf', 'binary'];
  return order.flatMap((kind) => {
    const count = counts.get(kind) ?? 0;
    if (count <= 0) return [];
    const data = attachmentKindData(kind);
    const attachmentPrefix = t('message.context.kind.attachment', '附件');
    const label = `${attachmentPrefix} · ${data.label}`;
    return [{
      key: `attachment:${kind}`,
      icon: data.icon,
      label: count > 1 ? `${label} · x${count}` : label,
    }];
  });
}

function attachmentKindFor(item: unknown): AttachmentKind {
  const record = asRecord(item);
  if (!record) return attachmentKindFromPath(nonEmptyString(item));
  const rawKind = nonEmptyString(record['kind'] ?? record['type']).toLowerCase();
  if (rawKind === 'image' || rawKind === 'text' || rawKind === 'spreadsheet' || rawKind === 'pdf') return rawKind;
  const mime = nonEmptyString(record['mime_type'] ?? record['mime']).toLowerCase();
  if (mime.startsWith('image/')) return 'image';
  if (mime.includes('pdf')) return 'pdf';
  if (mime.includes('spreadsheet') || mime.includes('excel') || mime.includes('csv')) return 'spreadsheet';
  if (mime.startsWith('text/') || mime.includes('json') || mime.includes('xml') || mime.includes('yaml')) return 'text';
  return attachmentKindFromPath(
    nonEmptyString(record['name']) ||
    nonEmptyString(record['storage_path']) ||
    nonEmptyString(record['path']) ||
    nonEmptyString(record['file_path']),
  );
}

function attachmentKindFromPath(path: string): AttachmentKind {
  const lower = path.toLowerCase();
  if (/\.(png|jpe?g|gif|webp|bmp|heic|svg)$/.test(lower)) return 'image';
  if (/\.(pdf)$/.test(lower)) return 'pdf';
  if (/\.(csv|tsv|xls|xlsx|ods)$/.test(lower)) return 'spreadsheet';
  if (/\.(txt|md|markdown|json|ya?ml|toml|xml|log|sql|dart|go|jsx?|tsx?|py|sh|rs|java|kt|swift|c|cc|cpp|h|hpp|css|html)$/.test(lower)) return 'text';
  return 'binary';
}

function attachmentKindData(kind: AttachmentKind): { icon: MessageIconName; label: string } {
  switch (kind) {
    case 'image':
      return { icon: 'image', label: t('message.context.attachment.image', '图片附件') };
    case 'text':
      return { icon: 'attachmentText', label: t('message.context.attachment.text', '文本附件') };
    case 'spreadsheet':
      return { icon: 'attachmentSpreadsheet', label: t('message.context.attachment.spreadsheet', '表格附件') };
    case 'pdf':
      return { icon: 'attachmentPdf', label: t('message.context.attachment.pdf', 'PDF 附件') };
    case 'binary':
      return { icon: 'attachmentFile', label: t('message.context.attachment.file', '文件附件') };
  }
}

function MessageContextCapsule({ chip }: { chip: MessageContextChip }) {
  return (
    <span class="oh-message-context-capsule oh-soft-replace">
      {chip.emoji ? (
        <span class="oh-message-context-emoji" aria-hidden>{chip.emoji}</span>
      ) : chip.icon ? (
        <span class="oh-message-context-icon" aria-hidden>
          <MessageIcon name={chip.icon} size={13} />
        </span>
      ) : null}
      <span class="truncate">{chip.label}</span>
    </span>
  );
}

// 自动 collapse 长正文（thinking / tool stdout）。阈值经验值，避免一屏被 5K 字符卡片占满。
const AUTO_COLLAPSE_CHAR_LIMIT = 1200;
// reasoning（思考）专用：超过 5-6 行文本即默认折叠到预览态。
// 以 14px 行高 + 1.55 line-height ≈ 22px / 行换算，5-6 行约 110-130 字符的单行长度；
// 保守取 6 行 + 一个字符容差 ≈ 260 字符作为「超长」阈值。
const REASONING_AUTO_COLLAPSE_CHAR_LIMIT = 260;
// 折叠预览容器 max-height，像素值。≈ 6 行 × 22px = 132px，多给 10px 呼吸量，
// 对应 APP 端 _MarkdownPreviewBody maxHeight: 142。
const REASONING_PREVIEW_MAX_HEIGHT_PX = 142;
const SIZE_MOTION_MIN_DELTA_PX = 1.5;
const SIZE_MOTION_TEXT_BUCKET_CHARS = 48;

// 已经完成入场动画的消息 id 集合。防止 SSE 流式更新导致 Preact 卸载/重挂时
// CSS 入场动画重播，从而引发消息列表"闪烁→消失→重现"的鬼畜抖动。
const appearedMessageIds = new Set<string>();

// 限制集合大小，防止长时间运行时内存泄漏。
// 当集合超过 500 条时，清除最早的一半。
function trackMessageAppeared(id: string): void {
  appearedMessageIds.add(id);
  if (appearedMessageIds.size > 500) {
    const entries = [...appearedMessageIds];
    for (let i = 0; i < 250; i++) {
      appearedMessageIds.delete(entries[i]!);
    }
  }
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

function isAssistantSideMessage(message: SessionMessage): boolean {
  return message.role !== 'user';
}

function isAssistantResponseMessage(message: SessionMessage): boolean {
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

function messageSizeMotionSignal(message: SessionMessage, actionsVisible: boolean): string {
  const metadata = message.metadata ?? {};
  return [
    message.id,
    message.role,
    message.kind,
    textLayoutMotionSignal(message.content ?? ''),
    numberLayoutMotionSignal(message.character_count),
    actionsVisible ? 1 : 0,
    asBool(metadata['tool_arguments_streaming']) ? 1 : 0,
    asString(metadata['tool_execution_status'] ?? metadata['tool_status'] ?? metadata['status']),
    textLayoutMotionSignal(asString(metadata['tool_execution_stdout'])),
    textLayoutMotionSignal(asString(metadata['tool_execution_stderr'])),
    textLayoutMotionSignal(asString(metadata['tool_execution_result'] ?? metadata['result_text'])),
    asString(metadata['file_mutation_kind']),
    asNumber(metadata['round_summary_record_count']) ?? '',
  ].join('|');
}

function textLayoutMotionSignal(value: string): string {
  let lineBreaks = 0;
  for (let index = 0; index < value.length; index += 1) {
    if (value.charCodeAt(index) === 10) lineBreaks += 1;
  }
  return `${lineBreaks}:${Math.floor(value.length / SIZE_MOTION_TEXT_BUCKET_CHARS)}`;
}

function numberLayoutMotionSignal(value: number | undefined): string {
  return value == null ? '' : String(Math.floor(value / SIZE_MOTION_TEXT_BUCKET_CHARS));
}

function useMessageSizeMotion(signal: string, enabled: boolean) {
  const ref = useRef<HTMLElement | null>(null);
  const lastHeightRef = useRef<number | null>(null);
  const animationRef = useRef<Animation | null>(null);
  const overflowBeforeAnimationRef = useRef<string | null>(null);

  useEffect(() => () => {
    animationRef.current?.cancel();
    animationRef.current = null;
  }, []);

  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;

    const activeAnimation = animationRef.current;
    const currentVisualHeight = activeAnimation
      ? element.getBoundingClientRect().height
      : null;
    activeAnimation?.cancel();
    animationRef.current = null;
    if (overflowBeforeAnimationRef.current != null) {
      element.style.overflow = overflowBeforeAnimationRef.current;
      overflowBeforeAnimationRef.current = null;
    }

    const nextHeight = element.getBoundingClientRect().height;
    const previousHeight = lastHeightRef.current;
    lastHeightRef.current = nextHeight;
    if (!enabled || previousHeight == null || typeof element.animate !== 'function') return;

    const fromHeight = currentVisualHeight ?? previousHeight;
    const delta = nextHeight - fromHeight;
    if (!Number.isFinite(fromHeight) || !Number.isFinite(nextHeight) || Math.abs(delta) < SIZE_MOTION_MIN_DELTA_PX) {
      return;
    }

    const growing = delta > 0;
    const overshoot = growing ? Math.min(10, Math.max(2, delta * 0.12)) : 0;
    // 高度动画节奏跟随全局弹窗设置：展开略长收一点弹性，折叠略短偏精准。
    const baseDuration = getDialogMotionDurationMs() || 280;
    const duration = growing
      ? Math.max(260, Math.min(420, Math.round(baseDuration * 1.15)))
      : Math.max(180, Math.min(300, Math.round(baseDuration * 0.8)));
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
        duration,
        easing: growing ? 'cubic-bezier(0.22, 1.22, 0.36, 1)' : 'cubic-bezier(0.2, 0, 0, 1)',
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
  }, [enabled, signal]);

  return ref;
}

export interface MessageCardProps {
  message: SessionMessage;
  /// 由详情页受控的点击选中态；只有选中的卡片显示操作栏。
  active?: boolean;
  /// 默认 false；调用方可设为 true 强制展开。
  forceExpanded?: boolean;
  /// 当前消息是否仍在流式增长；长正文在流式期间保持展开，结束后自动折叠。
  streaming?: boolean;
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
  onActiveChange?: (m: SessionMessage, active: boolean) => void;
}

function MessageCardImpl({
  message,
  active = false,
  forceExpanded = false,
  streaming = false,
  sessionId,
  onCopy,
  onDelete,
  onDeleteAfter,
  onEdit,
  onAudit,
  onActiveChange,
}: MessageCardProps) {
  const reduceMotion = useReducedMotion();
  const style = styleForKind(message.kind, message.role);
  const content = message.content ?? '';
  const useStructuredToolBody =
    message.kind === 'tool' ||
    message.kind === 'tool_call' ||
    message.kind === 'mcp';
  const useToolBody = useStructuredToolBody || message.kind === 'file_mutation_summary';
  const metadata = message.metadata ?? {};
  const streamingContent = streaming || asBool(metadata['streaming']);
  const canCollapse =
    !useToolBody &&
    !forceExpanded &&
    (style.collapsible || isAssistantResponseMessage(message)) &&
    content.length > AUTO_COLLAPSE_CHAR_LIMIT;
  const [expandedOverride, setExpandedOverride] = useState<boolean | null>(null);
  useEffect(() => {
    setExpandedOverride(null);
  }, [message.id]);
  const expanded = forceExpanded || streamingContent || expandedOverride === true || !canCollapse;
  const collapsed = canCollapse && !expanded;
  const visibleContent = collapsed
    ? content.slice(0, AUTO_COLLAPSE_CHAR_LIMIT) + '…'
    : content;

  // ── 工具调用/思考类型消息的胶囊折叠/展开（与 APP 端 _ReasoningBody 对齐） ──
  // - 工具调用 / 工具结果 / hook / mcp / skill / reasoning：支持点击胶囊折叠
  // - 流式期间始终展开，便于实时观察
  // - 流式结束后，超过 5-6 行的 reasoning 默认折叠（用 max-height 预览态）
  // - 用户一旦手动切换，记住其选择，不被流式结束事件回撤
  const isToolCallKind = message.kind === 'tool_call' || message.kind === 'hook';
  const isToolResultKind = message.kind === 'tool' || message.kind === 'mcp' || message.kind === 'skill';
  const isCollapsibleByBadge = isToolCallKind || isToolResultKind || message.kind === 'reasoning';
  const isLongReasoning =
    message.kind === 'reasoning' && isReasoningLong(content);
  const defaultBadgeCollapsed = !streamingContent && isLongReasoning;
  const [badgeCollapsedOverride, setBadgeCollapsedOverride] = useState<boolean | null>(null);
  useEffect(() => {
    setBadgeCollapsedOverride(null);
  }, [message.id]);
  const badgeCollapsed = badgeCollapsedOverride ?? defaultBadgeCollapsed;

  // ── 入场动画：仅首次挂载时播放，防止流式更新重播 ──
  const shouldAnimate = !appearedMessageIds.has(message.id);
  useEffect(() => {
    if (shouldAnimate) {
      trackMessageAppeared(message.id);
    }
  }, [message.id, shouldAnimate]);

  const hasAnyAction = Boolean(onCopy || onDelete || onDeleteAfter || onEdit || onAudit);
  const actionsVisible = hasAnyAction && active;
  const isUserBubble = message.role === 'user';
  const isWideSystemCard =
    useToolBody ||
    message.kind === 'reasoning' ||
    message.kind === 'system' ||
    message.role === 'system' ||
    message.role === 'tool';
  const bubbleMaxWidth = isWideSystemCard
    ? 'min(92%, 820px)'
    : isUserBubble
      ? 'min(78%, 640px)'
      : 'min(82%, 720px)';
  const contextChips = messageContextChips(message);
  const media = sessionId ? (
    <MessageMedia
      message={message}
      sessionId={sessionId}
      presentation={isUserBubble ? 'attachmentList' : 'preview'}
    />
  ) : null;
  const sizeMotionSignal = `${messageSizeMotionSignal(message, actionsVisible)}|expanded:${expanded ? 1 : 0}|streaming:${streamingContent ? 1 : 0}|badgeCollapsed:${badgeCollapsed ? 1 : 0}`;
  const cardRef = useMessageSizeMotion(
    sizeMotionSignal,
    !reduceMotion && isAssistantSideMessage(message),
  );

  const handleBadgeToggle = useCallback((e: Event) => {
    e.stopPropagation();
    setBadgeCollapsedOverride((current) => {
      const next = current == null ? !defaultBadgeCollapsed : !current;
      return next;
    });
  }, [defaultBadgeCollapsed]);

  return (
    <article
      ref={cardRef}
      class={`oh-message-card ${isUserBubble ? 'is-user' : 'is-other'} ${isWideSystemCard ? 'is-wide' : 'is-plain'} rounded-m3-md p-4${shouldAnimate ? ' oh-appear-up' : ''}`}
      style={{
        display: 'block',
        width: 'fit-content',
        maxWidth: bubbleMaxWidth,
        marginLeft: isUserBubble ? 'auto' : '0',
        marginRight: isUserBubble ? '0' : 'auto',
        background: style.background,
        color: style.color,
        boxShadow: style.border ? 'none' : 'var(--m3-elev-1)',
        border: style.border,
        cursor: hasAnyAction ? 'pointer' : 'default',
        overflowWrap: 'anywhere',
        transformOrigin: isUserBubble ? 'right top' : 'left top',
        transition: 'box-shadow 220ms ease-out, border-color 220ms ease-out',
      }}
      onClick={(ev) => {
        if (!hasAnyAction) return;
        // 点击交互元素（按钮 / 链接 / 输入框）时不切换 selection。
        const target = ev.target as HTMLElement;
        if (target.closest('button,a,input,textarea,select,[role="button"]')) return;
        // 双击代码块选中文本时也不切换。
        const sel = typeof window !== 'undefined' ? window.getSelection() : null;
        if (sel && sel.toString().length > 0) return;
        onActiveChange?.(message, !active);
      }}
    >
      <header class="oh-message-card-header flex items-center justify-between gap-3 text-xs mb-2 opacity-90">
        <span class="oh-message-card-meta flex items-center gap-2 min-w-0">
          {style.badge ? (
            isCollapsibleByBadge ? (
              <button
                type="button"
                class="oh-message-badge-toggle oh-tap-press inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm"
                style={{
                  background: 'color-mix(in srgb, currentColor 14%, transparent)',
                  border: 'none',
                  color: 'inherit',
                  cursor: 'pointer',
                  fontSize: 'inherit',
                  lineHeight: 'inherit',
                }}
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
          ) : (
            <span class="opacity-90">
              {roleLabel(message.role)}
              {message.kind && message.kind !== 'text' && message.kind !== 'user' && message.kind !== 'assistant'
                ? ` · ${message.kind}`
                : ''}
            </span>
          )}
          {message.model_label && message.role !== 'user' ? (
            <span class="oh-message-model-label truncate opacity-75">· {message.model_label}</span>
          ) : null}
        </span>
        <span class="oh-message-time opacity-75 flex-none">{formatTimestamp(message.created_at)}</span>
      </header>
      {!isUserBubble && contextChips.length > 0 ? (
        <div class={`oh-message-context-capsules ${isUserBubble ? 'is-user' : 'is-other'}`}>
          {contextChips.map((chip) => <MessageContextCapsule key={chip.key} chip={chip} />)}
        </div>
      ) : null}
      <MessageToolMeta message={message} />
      {isUserBubble ? media : null}
      <ReasoningCollapsibleBody
        collapsed={isCollapsibleByBadge && badgeCollapsed}
        previewMaxHeight={REASONING_PREVIEW_MAX_HEIGHT_PX}
      >
        {message.kind === 'file_mutation_summary' ? (
          <FileMutationSummaryCard message={message} />
        ) : useStructuredToolBody ? (
          <ToolExecutionCard message={message} />
        ) : useToolBody ? (
          content.length > 0 ? <ToolResultBody content={content} /> : null
        ) : (
          <Markdown
            source={visibleContent}
            raw={style.mono === true}
            mono={style.mono === true}
          />
        )}
      </ReasoningCollapsibleBody>
      {canCollapse && !streamingContent && !badgeCollapsed ? (
        <button
          type="button"
          class="oh-tap-press oh-message-collapse-button mt-2"
          aria-expanded={expanded ? 'true' : 'false'}
          onClick={(e) => {
            e.stopPropagation();
            setExpandedOverride((value) => (value === true ? false : true));
          }}
        >
          <MessageIcon name={expanded ? 'chevronUp' : 'chevronDown'} size={14} />
          <span>{expanded
            ? t('detail.tool.body.collapse', '折叠')
            : t('detail.tool.body.expand', '展开全部')}</span>
        </button>
      ) : null}
      {isUserBubble && contextChips.length > 0 ? (
        <div class="oh-message-context-capsules is-user is-after-content">
          {contextChips.map((chip) => <MessageContextCapsule key={chip.key} chip={chip} />)}
        </div>
      ) : null}
      {!isUserBubble ? media : null}
      {!isUserBubble && streamingContent && message.content.trim().length < 10 ? (() => {
        const creationRequest = metadata['creation_request'] as Record<string, unknown> | undefined;
        const creationMode = (creationRequest?.['mode'] as string) || (metadata['conversation_mode'] as string) || '';
        if (creationMode === 'image' || creationMode === 'video' || creationMode === 'audio' || creationMode === 'deep_research') {
          return <MediaGeneratingPlaceholder mode={creationMode as 'image' | 'video' | 'audio' | 'deep_research'} />;
        }
        return null;
      })() : null}
      {actionsVisible ? (
        <div
          class="mt-3 pt-3 flex flex-wrap items-center gap-2 text-xs"
          style={{
            borderTop: '1px solid color-mix(in srgb, currentColor 18%, transparent)',
          }}
        >
          {onCopy ? (
            <ActionBtn icon="copy" label={t('common.copy')} onClick={() => onCopy(message)} />
          ) : null}
          {onEdit && message.role === 'user' ? (
            <ActionBtn icon="edit" label={t('common.edit')} onClick={() => onEdit(message)} />
          ) : null}
          {onAudit ? (
            <ActionBtn icon="audit" label={t('common.audit')} onClick={() => onAudit(message)} />
          ) : null}
          {onDelete ? (
            <ActionBtn
              icon="trash"
              label={t('common.delete')}
              onClick={() => onDelete(message)}
            />
          ) : null}
          {onDeleteAfter ? (
            <ActionBtn
              icon="cascade"
              label={t('common.deleteAfter')}
              onClick={() => onDeleteAfter(message)}
            />
          ) : null}
        </div>
      ) : null}
    </article>
  );
}

function ActionBtn({
  icon,
  label,
  onClick,
}: {
  icon: MessageIconName;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      class="oh-tap-press oh-message-action-button"
      style={{
        color: 'currentColor',
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
      <MessageIcon name={icon} size={14} />
      <span>{label}</span>
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
  previewMaxHeight,
  children,
}: {
  collapsed: boolean;
  previewMaxHeight: number;
  children: ComponentChildren;
}) {
  return (
    <div
      class="oh-reasoning-collapsible-body"
      data-collapsed={collapsed ? 'true' : 'false'}
      aria-expanded={collapsed ? 'false' : 'true'}
      style={collapsed
        ? {
            maxHeight: `${previewMaxHeight}px`,
            overflow: 'hidden',
            // 底部渐隐：mask-image 让 65%-100% 的像素在垂直方向上
            // 由 100% 不透明渐变到 0%，保留文字原色，不额外叠气泡色。
            WebkitMaskImage:
              'linear-gradient(to bottom, #000 0, #000 65%, transparent 100%)',
            maskImage:
              'linear-gradient(to bottom, #000 0, #000 65%, transparent 100%)',
          }
        : undefined}
    >
      {children}
    </div>
  );
}

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
  const sandboxApplied = asBool(metadata['sandbox_applied']);
  const sandboxBlocked = asBool(metadata['sandbox_blocked']);
  const sandboxBackend = asString(metadata['sandbox_backend']);
  const sandboxReason = asString(metadata['sandbox_unavailable_reason']);
  const sandboxProxyEnabled = asBool(metadata['sandbox_proxy_enabled']);
  const sandboxProxyHttpPort = asNumber(metadata['sandbox_proxy_http_port']);
  const sandboxProxySocksPort = asNumber(metadata['sandbox_proxy_socks_port']);
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
    <div class="oh-tool-execution-card flex flex-col gap-2">
      <div class="oh-tool-execution-chip-row flex flex-wrap gap-1.5 text-[11px]">
        {elapsedMs != null ? <MetaChip label={`${elapsedMs} ms`} /> : null}
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
      <ToolArgumentsBlock metadata={metadata} />
      {command ? (
        <ToolSection title={t('detail.tool.command', '执行命令')} content={command} defaultExpanded />
      ) : null}
      {stdout ? (
        <ToolSection title={t('detail.tool.stdout', '标准输出')} content={stdout} />
      ) : null}
      {stderr ? (
        <ToolSection title={t('detail.tool.stderr', '标准错误 stderr')} content={stderr} danger defaultExpanded />
      ) : null}
      {sandboxReason ? (
        <ToolSection title={t('detail.tool.sandbox.reason', '沙盒状态')} content={sandboxReason} danger={sandboxBlocked} defaultExpanded />
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
    <section class="oh-tool-section">
      <div class="oh-tool-section-header flex items-center gap-2 mb-1 text-[11px]" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
        {content}
      </pre>
    </section>
  );
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
