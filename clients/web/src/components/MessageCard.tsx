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
import { Markdown, looksLikeHtml, openHtmlInNewTab } from './Markdown';
import { MediaGeneratingPlaceholderTransition, type MediaGenerationMode } from './MediaGeneratingPlaceholder';
import { MediaPreviewDialog, MessageMedia, messageHasMultimedia, stripCollectedNetworkMedia } from './MessageMedia';
import type { MediaItem } from './MessageMedia';
import { MessageToolMeta } from './MessageToolMeta';
import { ToolResultBody } from './ToolResultBody';
import { memo } from 'preact/compat';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { showSnackbar } from './Snackbar';
import { copyTextToClipboard } from '../utils/clipboard';
import { useReducedMotion } from '../hooks/useReducedMotion';
import { useMessageContentFormat } from '../hooks/useMessageContentFormat';
import {
  stopTtsPlayback,
  toggleTtsPlayback,
  useTtsPlaybackState,
  useTtsSettings,
} from '../hooks/useTtsSettings';
import {
  useStreamingReveal,
  useStreamingStagedText,
} from '../hooks/useStreamingReveal';
import { getDialogMotionDurationMs } from '../hooks/useDialogMotionSettings';
import { useStickyBottom } from '../hooks/useStickyBottom';
import { useDelayedVisibility } from '../hooks/useDelayedVisibility';
import {
  booleanFromUnknown,
  finiteNumberOrNullFromUnknown,
  recordOrNullFromUnknown,
  stringFromUnknown,
} from '../shared/util/value';

function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
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
  | 'fork'
  | 'code'
  | 'codeOff'
  | 'trash'
  | 'cascade'
  | 'chevronDown'
  | 'chevronUp'
  | 'write'
  | 'delete'
  | 'mutate'
  | 'globe'
  | 'model'
  | 'clock'
  | 'speech'
  | 'stop';

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
    case 'fork':
      return <svg {...common}><path d="M4 7h4c3.5 0 5 5 8.2 5H20" /><path d="M4 17h4c2.2 0 3.8-2 5.4-3.4" /><path d="m17 9 3 3-3 3" /></svg>;
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
  }
}

function styleForKind(kind: string, role: string): KindStyle {
  switch (kind) {
    case 'reasoning':
      // 思考卡：用户实测 tertiary-container 弱饱和在 dark mode 仍带蓝调，
      // 与全局深色灰主题强对比割裂。改用 surface-container-high 微弱提亮
      // （比 assistant 卡略亮一档以保持类型区分）+ 细描边，与全局
      // 灰黑主题完全融合。
      return {
        background: 'var(--m3-surface-container-high, rgba(255,255,255,0.05))',
        color: 'var(--m3-on-surface-variant, #888)',
        border: '1px solid var(--m3-outline-variant, rgba(127,127,127,0.25))',
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

function nonEmptyString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function messageContextChips(message: SessionMessage): MessageContextChip[] {
  if (message.role !== 'user') return [];
  const meta = recordOrNullFromUnknown(message.metadata);
  if (!meta) return [];
  return [
    ...creationModeChips(meta),
    ...skillChips(meta),
    ...attachmentChips(meta),
  ];
}

function creationModeChips(meta: Record<string, unknown>): MessageContextChip[] {
  const request = recordOrNullFromUnknown(meta['creation_request']);
  const options = recordOrNullFromUnknown(request?.['options']);
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

function mediaGenerationModeFromMetadata(
  metadata: Record<string, unknown>,
): MediaGenerationMode | null {
  const creationRequest = recordOrNullFromUnknown(metadata['creation_request']);
  const mode = nonEmptyString(creationRequest?.['mode']) || nonEmptyString(metadata['conversation_mode']);
  return mode === 'image' || mode === 'video' || mode === 'audio' || mode === 'deep_research'
    ? mode
    : null;
}

function creationOptionDetail(options: Record<string, unknown> | null): string {
  if (!options) return '';
  const parts: string[] = [];
  const aspectRatio = nonEmptyString(options['aspect_ratio']);
  const size = nonEmptyString(options['size']);
  const quality = nonEmptyString(options['quality']);
  const style = nonEmptyString(options['style']);
  const outputFormat = nonEmptyString(options['output_format']);
  const background = nonEmptyString(options['background']);
  const resolution = nonEmptyString(options['resolution']);
  const mode = nonEmptyString(options['mode']);
  const voice = nonEmptyString(options['voice']);
  const duration = typeof options['duration_seconds'] === 'number'
    ? Math.round(options['duration_seconds'])
    : Number.parseInt(nonEmptyString(options['duration_seconds']), 10);
  const count = typeof options['count'] === 'number'
    ? Math.round(options['count'])
    : Number.parseInt(nonEmptyString(options['count']), 10);
  const frameRate = typeof options['frame_rate'] === 'number'
    ? Math.round(options['frame_rate'])
    : Number.parseInt(nonEmptyString(options['frame_rate']), 10);
  const numFrames = typeof options['num_frames'] === 'number'
    ? Math.round(options['num_frames'])
    : Number.parseInt(nonEmptyString(options['num_frames']), 10);
  const seed = typeof options['seed'] === 'number'
    ? Math.round(options['seed'])
    : Number.parseInt(nonEmptyString(options['seed']), 10);
  const speed = typeof options['speed'] === 'number'
    ? options['speed']
    : Number.parseFloat(nonEmptyString(options['speed']));
  const sampleRate = typeof options['sample_rate'] === 'number'
    ? Math.round(options['sample_rate'])
    : Number.parseInt(nonEmptyString(options['sample_rate']), 10);
  const bitrate = typeof options['bitrate'] === 'number'
    ? Math.round(options['bitrate'])
    : Number.parseInt(nonEmptyString(options['bitrate']), 10);
  if (aspectRatio) parts.push(aspectRatio);
  else if (size) parts.push(size);
  if (Number.isFinite(duration) && duration > 0) parts.push(`${duration}s`);
  if (resolution) parts.push(resolution);
  if (Number.isFinite(frameRate) && frameRate > 0) parts.push(`${frameRate}fps`);
  if (Number.isFinite(numFrames) && numFrames > 0) parts.push(`${numFrames}f`);
  if (quality) parts.push(quality);
  if (style) parts.push(style);
  if (outputFormat) parts.push(outputFormat);
  if (background) parts.push(background);
  if (mode) parts.push(mode);
  if (voice) parts.push(voice);
  if (Number.isFinite(speed) && speed > 0) parts.push(`${speed}x`);
  if (Number.isFinite(sampleRate) && sampleRate > 0) parts.push(`${sampleRate}Hz`);
  if (Number.isFinite(bitrate) && bitrate > 0) parts.push(`${Math.round(bitrate / 1000)}kbps`);
  if (Number.isFinite(seed) && seed > 0) parts.push(`seed ${seed}`);
  if (typeof options['prompt_enhance'] === 'boolean') parts.push(options['prompt_enhance'] ? 'prompt+' : 'prompt-');
  if (typeof options['watermark'] === 'boolean') parts.push(options['watermark'] ? 'watermark' : 'no wm');
  if (nonEmptyString(options['negative_prompt'])) parts.push('negative');
  if (Number.isFinite(count) && count > 1) parts.push(`x${count}`);
  return parts.join(' · ');
}

function skillChips(meta: Record<string, unknown>): MessageContextChip[] {
  const skill = recordOrNullFromUnknown(meta['user_skill_selection']) ?? recordOrNullFromUnknown(meta['selected_skill']);
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
  const record = recordOrNullFromUnknown(item);
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
    <span class="oh-message-context-capsule oh-soft-replace" title={chip.label}>
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

const messageActionSurfaceStyle = {
  color: 'currentColor',
  border: '1px solid color-mix(in srgb, currentColor 28%, transparent)',
  background: 'transparent',
};

// 自动 collapse 长正文（thinking / tool stdout）。阈值经验值，避免一屏被 5K 字符卡片占满。
const AUTO_COLLAPSE_CHAR_LIMIT = 1200;
// reasoning（思考）专用：超过 5-6 行文本即默认折叠到预览态。
// 以 14px 行高 + 1.55 line-height ≈ 22px / 行换算，5-6 行约 110-130 字符的单行长度；
// 保守取 6 行 + 一个字符容差 ≈ 260 字符作为「超长」阈值。
const REASONING_AUTO_COLLAPSE_CHAR_LIMIT = 260;
// 折叠预览容器 max-height，像素值。≈ 6 行 × 22px = 132px，多给 10px 呼吸量，
// 对应 APP 端 _MarkdownPreviewBody maxHeight: 142。
const REASONING_PREVIEW_MAX_HEIGHT_PX = 142;
const RESPONSE_PREVIEW_MAX_HEIGHT_PX = 240;
const SIZE_MOTION_MIN_DELTA_PX = 1.5;
const SIZE_MOTION_TEXT_BUCKET_CHARS = 48;
const STREAMING_SIZE_MOTION_BUCKET_CHARS = 16;
const STREAMING_DIFF_REVEAL_MAX_CHARS = 32 * 1024;
const MESSAGE_APPEAR_BATCH_WINDOW_MS = 90;
const MESSAGE_UI_STATE_CACHE_LIMIT = 500;
const MESSAGE_CARD_TAP_MAX_MS = 350;
const MESSAGE_CARD_TAP_MAX_DISTANCE_PX = 8;

// 已经完成入场动画的消息 id 集合。防止 SSE 流式更新导致 Preact 卸载/重挂时
// CSS 入场动画重播，从而引发消息列表"闪烁→消失→重现"的鬼畜抖动。
const appearedMessageIds = new Set<string>();
const responseExpandedOverridesByMessageId = new Map<string, boolean>();
const badgeCollapsedOverridesByMessageId = new Map<string, boolean>();
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

/// W3 优化：打开历史会话时一次性把已加载的全部 message id 标记为"已入场"。
/// 历史消息没必要再跑 CSS 入场动画 + useLayoutEffect 高度量动画，避免长会话
/// 首屏 N 张卡片并发 getBoundingClientRect / element.animate 撑爆主线程。
/// 仅"新到达"的消息（流式 / SSE 推送）会继续走入场。
export function markMessagesAsAppeared(ids: readonly string[]): void {
  for (const id of ids) {
    if (id) appearedMessageIds.add(id);
  }
  if (appearedMessageIds.size > 500) {
    const entries = [...appearedMessageIds];
    for (let i = 0; i < Math.min(250, entries.length - 250); i++) {
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

function isPlainConversationMessage(message: SessionMessage): boolean {
  if (message.role !== 'user' && message.role !== 'assistant') return false;
  return !message.kind ||
    message.kind === 'text' ||
    message.kind === message.role;
}

function selectedMessageInfoChips(message: SessionMessage): MessageContextChip[] {
  const chips: MessageContextChip[] = [];
  if (message.role !== 'user') {
    const modelLabel = nonEmptyString(message.model_label) || nonEmptyString(message.model_id);
    if (modelLabel) {
      chips.push({
        key: 'model',
        icon: 'model',
        label: modelLabel,
      });
    }
  }
  const sentAt = formatTimestamp(message.created_at);
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
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            setEverVisible(true);
            io.disconnect();
            return;
          }
        }
      },
      { rootMargin: '50px 0px 50px 0px' },
    );
    io.observe(element);
    return () => io.disconnect();
  }, [everVisible]);

  useLayoutEffect(() => {
    if (!everVisible) return;
    const element = ref.current;
    if (!element) return;

    if (!enabled) {
      animationRef.current?.cancel();
      animationRef.current = null;
      if (overflowBeforeAnimationRef.current != null) {
        element.style.overflow = overflowBeforeAnimationRef.current;
        overflowBeforeAnimationRef.current = null;
      }
      lastHeightRef.current = null;
      return;
    }

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
    if (previousHeight == null || typeof element.animate !== 'function') return;

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
  }, [enabled, signal, everVisible]);

  return ref;
}

function useRecentMessageActivity(
  signal: string,
  enabled: boolean,
  holdMs: number,
): boolean {
  const [active, setActive] = useState(false);
  const initializedRef = useRef(false);

  useEffect(() => {
    if (!enabled) {
      initializedRef.current = true;
      setActive(false);
      return;
    }
    if (!initializedRef.current) {
      initializedRef.current = true;
      return;
    }
    setActive(true);
    const handle = window.setTimeout(() => setActive(false), holdMs);
    return () => window.clearTimeout(handle);
  }, [signal, enabled, holdMs]);

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
  const { visibleContent, staging } = useStreamingStagedText(
    content,
    streaming,
    reduceMotion,
  );
  const sizeMotionRef = useMessageSizeMotion(
    textLayoutMotionSignal(
      visibleContent,
      STREAMING_SIZE_MOTION_BUCKET_CHARS,
    ),
    !reduceMotion && (streaming || staging),
  );
  const revealAllowed = visibleContent.length <= STREAMING_DIFF_REVEAL_MAX_CHARS;
  const { containerRef: streamingMaskRef, streamingClass } = useStreamingReveal(
    streaming && revealAllowed,
    visibleContent.length,
    visibleContent,
    reduceMotion,
  );

  return (
    <div ref={sizeMotionRef}>
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
}: {
  content: string;
  streaming: boolean;
  reduceMotion: boolean;
  raw: boolean;
  mono: boolean;
  format?: 'markdown' | 'plain_text' | 'html';
  htmlFallback?: 'markdown' | 'plain_text';
}) {
  const contentIsHtml = looksLikeHtml(content);
  const canStageContent = streaming && format !== 'html' && !contentIsHtml;
  const { visibleContent: renderContent, staging } = useStreamingStagedText(
    content,
    canStageContent,
    reduceMotion,
  );
  const sizeMotionRef = useMessageSizeMotion(
    textLayoutMotionSignal(
      renderContent,
      STREAMING_SIZE_MOTION_BUCKET_CHARS,
    ),
    !reduceMotion && (streaming || staging),
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
    <div ref={sizeMotionRef}>
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
        />
      </div>
    </div>
  );
}

export interface MessageCardProps {
  message: SessionMessage;
  /// 由详情页受控的点击选中态；只有选中的卡片显示操作栏。
  active?: boolean;
  /// 默认 false；调用方可设为 true 强制展开。
  forceExpanded?: boolean;
  /// 当前消息是否仍在流式增长；长正文在流式期间保持展开，结束后自动折叠。
  streaming?: boolean;
  /// 当前会话回合是否仍在运行；运行期间长正文/reasoning 卡片保持展开，避免
  /// 在同一回合中后续 reasoning/text 卡接管流式状态后，先前卡片瞬间自动折叠
  /// 造成「消息盒子剧烈滚动 + 卡片瞬隐」的观感。
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
  onActiveChange,
}: MessageCardProps) {
  const reduceMotion = useReducedMotion();
  const { format: contentFormat, htmlFallback: contentHtmlFallback } = useMessageContentFormat();
  const ttsSettings = useTtsSettings();
  const ttsPlayback = useTtsPlaybackState();
  const [showRawContent, setShowRawContent] = useState(false);
  const style = styleForKind(message.kind, message.role);
  const content = message.content ?? '';
  const isUserBubble = message.role === 'user';
  const useStructuredToolBody =
    message.kind === 'tool' ||
    message.kind === 'tool_call' ||
    message.kind === 'mcp';
  const useToolBody = useStructuredToolBody || message.kind === 'file_mutation_summary';
  const metadata = message.metadata ?? {};
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
  const inlineCreationMode =
    !isUserBubble && activelyStreaming && content.trim().length < 10
      ? mediaGenerationModeFromMetadata(metadata)
      : null;
  // 在同一回合内，即便此卡不再是「最新流式卡」，只要回合仍在运行，就保持展开。
  // 避免新 reasoning/text 卡接管流式后，先前的长 response/reasoning 卡瞬间折叠造成跳动。
  //
  // 关键去抖：服务器 send_phase 在 SSE / 2.5s phase guard / polling 三路之间
  // 存在竞态，turnActive 会瞬态 true → false → true 跳变 (~ 每隔几秒一次)，
  // 直接驱动 keepExpandedDuringTurn → 长正文卡的 collapsed 跟着跳变 → CSS
  // 360ms max-height (4000px ↔ 240px) 过渡每隔几秒跑一遍 → 视觉上正文
  // 区每隔几秒"消失再立刻显示"（卡片外框稳定，因 collapsed 只裁 body），
  // 同时撑高的工具卡在视窗中表现为"折叠 → 展开 → 折叠"。
  // 这里把 turnActive 的 false 沿做 12s 去抖：只有持续 12s false 才认为回合
  // 真正结束，覆盖慢速节流 / drain 间隔里的 idle 抖动。true 沿立即生效。
  const [stableTurnActive, setStableTurnActive] = useState(turnActive);
  useEffect(() => {
    if (turnActive) {
      setStableTurnActive(true);
      return;
    }
    const handle = window.setTimeout(() => setStableTurnActive(false), 12000);
    return () => window.clearTimeout(handle);
  }, [turnActive]);
  const keepExpandedDuringTurn =
    stableTurnActive && message.role === 'assistant' && !isReasoningMessage;
  const canCollapse =
    !useToolBody &&
    !forceExpanded &&
    (style.collapsible || isAssistantResponseMessage(message)) &&
    content.length > AUTO_COLLAPSE_CHAR_LIMIT;
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
  const expanded = forceExpanded || streamingContent || keepExpandedDuringTurn || expandedOverride === true || !canCollapse;
  const collapsed = canCollapse && !expanded;
  // 移除已被 MessageMedia 收集为卡片的网络媒体 markdown 引用, 避免重复展示。
  const strippedContent = useMemo(() => stripCollectedNetworkMedia(content), [content]);
  // 不再在内容层面截断：完整渲染后交由 CollapsibleBody 用 max-height + mask 动画过渡，
  // 避免「全多」↔「袪断+…」间的文字跳变在手动折叠/展开时生硬。
  const visibleContent = strippedContent;

  // ── 工具调用/思考类型消息的胶囊折叠/展开（与 APP 端 _ReasoningBody 对齐） ──
  // - 工具调用 / 工具结果 / hook / mcp / skill / reasoning：支持点击胶囊折叠
  // - 流式期间始终展开，便于实时观察
  // - 流式结束后，超过 5-6 行的 reasoning 默认折叠（用 max-height 预览态）
  // - 用户一旦手动切换，记住其选择，不被流式结束事件回撤
  const isToolCallKind = message.kind === 'tool_call' || message.kind === 'hook';
  const isToolResultKind = message.kind === 'tool' || message.kind === 'mcp' || message.kind === 'skill';
  const isCollapsibleByBadge = isToolCallKind || isToolResultKind || message.kind === 'reasoning';
  const isAssistantResponseBadgeMessage =
    isAssistantResponseMessage(message) && !isCollapsibleByBadge;
  const responseBadgeStreaming = isAssistantResponseBadgeMessage && activelyStreaming;
  const responseBadgeCanToggle =
    canCollapse && isAssistantResponseBadgeMessage && !activelyStreaming;
  const shouldRenderResponseBadge = responseBadgeStreaming || responseBadgeCanToggle;
  const reasoningBadgeSweeping = isActivelyStreamingReasoning;
  const badgeToggleClass =
    'oh-message-badge-toggle oh-tap-press inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm';
  const staticSweepingBadgeClass =
    'oh-message-badge-toggle is-static is-sweeping inline-flex items-center gap-1 px-1.5 py-0.5 rounded-m3-sm';
  const isLongReasoning = isReasoningMessage && isReasoningLong(content);
  const defaultBadgeCollapsed = isLongReasoning;
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
  const badgeBodyCollapsed = (isCollapsibleByBadge && badgeCollapsed) || collapsed;
  const reasoningPreviewCollapsed =
    isReasoningMessage && isCollapsibleByBadge && badgeCollapsed;

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

  const ttsPlaying = ttsPlayback.playing && ttsPlayback.messageId === message.id;
  const hasMultimediaContent = messageHasMultimedia(message);
  const canReadMessage = (
    ttsSettings.enabled &&
    !isUserBubble &&
    !hasMultimediaContent &&
    content.trim().length > 0
  );
  useEffect(() => {
    if (ttsPlaying && hasMultimediaContent) {
      stopTtsPlayback();
    }
  }, [hasMultimediaContent, ttsPlaying]);
  const hasAnyAction = Boolean(
    onCopy ||
    canReadMessage ||
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
  // 关键：卡片类型判定（是否为 HTML 卡）基于 metadata.content_format，
  // 优先级：metadata.content_format > global contentFormat。
  const effectiveFormat = (
    (typeof message.metadata?.['content_format'] === 'string'
      ? message.metadata['content_format']
      : null) ?? contentFormat
  ) as 'markdown' | 'plain_text' | 'html';
  const isHtmlAssistantCard =
    !isUserBubble &&
    !useToolBody &&
    !useStructuredToolBody &&
    message.kind !== 'reasoning' &&
    message.kind !== 'file_mutation_summary' &&
    effectiveFormat === 'html';
  const isWideSystemCard =
    useToolBody ||
    message.kind === 'reasoning' ||
    message.kind === 'system' ||
    message.role === 'system' ||
    message.role === 'tool';
  const bubbleMaxWidth = isWideSystemCard
    ? 'min(92%, 820px)'
    : isHtmlAssistantCard
      ? 'min(92%, 860px)'
      : isUserBubble
      ? 'min(78%, 640px)'
      : 'min(82%, 720px)';
  const contextChips = messageContextChips(message);
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
  const selectedInfoChips = selectedMessageInfoChips(message);
  const media = sessionId ? (
    <MessageMedia
      message={message}
      sessionId={sessionId}
      presentation={isUserBubble ? 'attachmentList' : 'preview'}
    />
  ) : null;
  const sizeMotionSignal = `${messageSizeMotionSignal(message)}|raw:${showRawContent ? 1 : 0}|tts:${ttsPlaying ? 1 : 0}|expanded:${expanded ? 1 : 0}|streaming:${streamingContent ? 1 : 0}|badgeCollapsed:${badgeCollapsed ? 1 : 0}`;
  // 正文卡片只承接折叠 / 展开 / 原始内容切换这类语义级尺寸变化。
  // 操作面板使用自己的布局槽动画，避免裁剪已加载的媒体节点。
  // 流式正文自身在 StreamingMarkdownReveal / StreamingPlainTextReveal 内
  // 用可见文本信号做局部高度 FLIP，避免整张卡被高频 WAAPI 裁剪。
  const cardRef = useMessageSizeMotion(
    sizeMotionSignal,
    !reduceMotion && !streamingContent && !keepExpandedDuringTurn,
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
    rememberMessageUiState(
      responseExpandedOverridesByMessageId,
      message.id,
      next,
    );
    setExpandedOverride(next);
  }, [expanded, message.id]);

  return (
    <>
      <div class={`oh-message-card-frame ${isUserBubble ? 'is-user' : 'is-other'}`}>
        <div
          ref={cardRef}
          class="oh-message-card-body-motion"
          style={{ transformOrigin: isUserBubble ? 'right top' : 'left top' }}
        >
          <article
            class={`oh-message-card ${isUserBubble ? 'is-user' : 'is-other'} ${isWideSystemCard ? 'is-wide' : 'is-plain'} ${streamingContent ? 'is-streaming-now' : ''} rounded-m3-md p-4${appearClass}`}
            style={{
              display: 'block',
              width: isHtmlAssistantCard ? bubbleMaxWidth : 'fit-content',
              maxWidth: bubbleMaxWidth,
              marginLeft: isUserBubble ? 'auto' : '0',
              marginRight: isUserBubble ? '0' : 'auto',
              background: style.background,
              color: style.color,
              boxShadow: style.border ? 'none' : 'var(--m3-elev-1)',
              border: style.border,
              cursor: hasAnyAction ? 'pointer' : 'default',
              overflowWrap: 'anywhere',
              transition: 'box-shadow 220ms ease-out, border-color 220ms ease-out',
            }}
            onPointerDown={(ev) => {
              if (!hasAnyAction) return;
              const target = ev.target as HTMLElement;
              if (
                target.closest(
                  'button,a,input,textarea,select,[role="button"],.oh-message-badge-toggle,[data-message-media-interactive="true"]',
                )
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
                target.closest(
                  'button,a,input,textarea,select,[role="button"],[data-message-media-interactive="true"],video,audio',
                )
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
              isCollapsibleByBadge ? (
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
      {isUserBubble ? media : null}
      <ReasoningCollapsibleBody
        collapsed={badgeBodyCollapsed}
        previewMaxHeight={
          isCollapsibleByBadge && badgeCollapsed
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
        ) : (
          // 思考卡在流式阶段强制使用纯文本，避免 Markdown/代码块逐 token
          // 成型时反复重排，把下方 pending tool-call 卡片顶上顶下。流式结束
          // 后再切回 Markdown 渲染；若内容超出 5-6 行，外层保持 142px 预览态。
          isActivelyStreamingReasoning ||
          (activelyStreaming && effectiveFormat === 'plain_text') ? (
            <StreamingPlainTextReveal
              content={visibleContent}
              streaming={!reasoningPreviewCollapsed}
              reduceMotion={reduceMotion}
              mono={style.mono === true}
            />
          ) : (
            <StreamingMarkdownReveal
              content={visibleContent}
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
              maxWidth: bubbleMaxWidth,
              marginLeft: isUserBubble ? 'auto' : '0',
              marginRight: isUserBubble ? '0' : 'auto',
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
                      onClick={() => {
                        void toggleTtsPlayback(message.id, content, ttsSettings);
                      }}
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
                  {!isUserBubble && !useToolBody && message.kind !== 'file_mutation_summary' ? (
                    <ActionBtn
                      icon={showRawContent ? 'codeOff' : 'code'}
                      label={showRawContent
                        ? t('message.showRendered', '显示渲染')
                        : t('message.showRaw', '显示原始')}
                      disabled={!actionPanelInteractive}
                      onClick={() => setShowRawContent((v) => !v)}
                    />
                  ) : null}
                  {!isUserBubble && !useToolBody && message.kind !== 'reasoning' && message.kind !== 'file_mutation_summary' && effectiveFormat === 'html' ? (
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
    </>
  );
}

function SelectedInfoChip({ chip }: { chip: MessageContextChip }) {
  return (
    <span
      class="oh-message-action-button oh-message-info-button oh-soft-replace"
      style={messageActionSurfaceStyle}
      title={chip.label}
    >
      {chip.emoji ? (
        <span class="oh-message-context-emoji" aria-hidden>{chip.emoji}</span>
      ) : chip.icon ? (
        <MessageIcon name={chip.icon} size={14} />
      ) : null}
      <span>{chip.label}</span>
    </span>
  );
}

function ActionBtn({
  icon,
  label,
  disabled = false,
  onClick,
}: {
  icon: MessageIconName;
  label: string;
  disabled?: boolean;
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
      class="oh-tap-press oh-message-action-button"
      style={messageActionSurfaceStyle}
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
  fadeBackground,
  children,
}: {
  collapsed: boolean;
  previewMaxHeight: number;
  fadeBackground: string;
  children: ComponentChildren;
}) {
  // 始终设置 max-height（展开态 = 充分大的上限），以便 CSS transition 生效。
  // 底部渐隐用 overlay 而不是 mask-image，避免和流式文本 reveal 的 inline
  // mask 叠加后让已稳定文本在折叠态反复明暗闪动。
  return (
    <div
      class="oh-reasoning-collapsible-body"
      data-collapsed={collapsed ? 'true' : 'false'}
      aria-expanded={collapsed ? 'false' : 'true'}
      style={{
        // 4000px 足以覆盖绝大多数长文本；超过部分不会被裁剪、不影响实际高度。
        maxHeight: collapsed ? `${previewMaxHeight}px` : '4000px',
        overflow: 'hidden',
      }}
    >
      {children}
      {collapsed ? (
        <div
          class="oh-reasoning-collapsible-fade"
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
  const elapsedMs = finiteNumberOrNullFromUnknown(metadata['tool_execution_elapsed_ms'] ?? metadata['tool_execution_duration_ms']);
  const exitCode = finiteNumberOrNullFromUnknown(metadata['tool_execution_exit_code'] ?? metadata['exit_code']);
  const sandboxApplied = booleanFromUnknown(metadata['sandbox_applied']);
  const sandboxBlocked = booleanFromUnknown(metadata['sandbox_blocked']);
  const sandboxBackend = stringFromUnknown(metadata['sandbox_backend']);
  const sandboxReason = stringFromUnknown(metadata['sandbox_unavailable_reason']);
  const sandboxProxyEnabled = booleanFromUnknown(metadata['sandbox_proxy_enabled']);
  const sandboxProxyHttpPort = finiteNumberOrNullFromUnknown(metadata['sandbox_proxy_http_port']);
  const sandboxProxySocksPort = finiteNumberOrNullFromUnknown(metadata['sandbox_proxy_socks_port']);
  const argumentsStreaming = booleanFromUnknown(metadata['tool_arguments_streaming']);
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
  const autoFollowToolOutput = autoFollow || !terminalStatus || booleanFromUnknown(metadata['streaming']);

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
  autoFollow = false,
}: {
  title: string;
  content: string;
  danger?: boolean;
  defaultExpanded?: boolean;
  autoFollow?: boolean;
}) {
  const long = content.length > 640 || content.split('\n').length > 10;
  const [expanded, setExpanded] = useState(defaultExpanded || !long);
  const preRef = useStickyBottom<HTMLPreElement>(content, autoFollow);
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
  const preRef = useStickyBottom<HTMLPreElement>(pretty, autoFollow);
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
