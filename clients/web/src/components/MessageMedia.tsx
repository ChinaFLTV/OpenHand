// 媒体渲染: 将 message.metadata 中的附件/生成媒体路径转换为
// <img>/<video>/<audio>/通用文件 pill, 1:1 对齐 App 端
// _MessageMediaCard / _MessageImageBubble / _MessageVideoBubble / _MessageAudioBubble。
// 路径不直接发给 <img src=>: 走 /api/sessions/<id>/asset?path=...&token=...
// 由 service 端基于 session 消息 metadata 白名单放行。

import { createPortal } from 'preact/compat';
import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { saveBlobWithPicker, type SaveBlobPickerType } from '../utils/save_blob';
import { buildSessionAssetUrl } from '../utils/session_asset';
import { showSnackbar } from './Snackbar';

type MediaKind = 'image' | 'video' | 'audio' | 'file';

interface MediaItem {
  /// 原始本地绝对路径
  path: string;
  /// 仅供展示的文件名
  name: string;
  kind: MediaKind;
  /// 来自 metadata.attachments[].kind 等的语义标签
  hintLabel?: string;
}

const IMAGE_EXTS = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.svg'];
const VIDEO_EXTS = ['.mp4', '.webm', '.mov', '.m4v'];
const AUDIO_EXTS = ['.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac'];
const MARKDOWN_MEDIA_REF = /(!?)\[([^\]\n]{0,240})\]\(([^)\r\n]+)\)/g;
const HTML_MEDIA_SRC = /<(?:img|video|audio|source)\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi;
const INLINE_MEDIA_DIR = /(^|[\\/])openhand_media([\\/]|$)/i;

function mediaKindFromPath(path: string, hintKind?: string): MediaKind {
  const lower = path.toLowerCase();
  if (hintKind) {
    const k = hintKind.toLowerCase();
    if (k === 'image' || k === 'img' || k === 'picture' || k === 'photo') return 'image';
    if (k === 'video' || k === 'movie') return 'video';
    if (k === 'audio' || k === 'sound' || k === 'voice') return 'audio';
  }
  if (IMAGE_EXTS.some((e) => lower.endsWith(e))) return 'image';
  if (VIDEO_EXTS.some((e) => lower.endsWith(e))) return 'video';
  if (AUDIO_EXTS.some((e) => lower.endsWith(e))) return 'audio';
  return 'file';
}

function basename(path: string): string {
  const i = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i >= 0 ? path.slice(i + 1) : path;
}

function pushString(out: MediaItem[], raw: unknown, hintKind?: string): void {
  if (typeof raw !== 'string') return;
  const path = raw.trim();
  if (!path) return;
  // Skip remote URLs — markdown layer renders them.
  if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
    return;
  }
  out.push({
    path,
    name: basename(path),
    kind: mediaKindFromPath(path, hintKind),
    hintLabel: hintKind,
  });
}

function normalizeMarkdownDestination(raw: string): string {
  let value = raw.trim();
  if (value.startsWith('<')) {
    const close = value.indexOf('>');
    if (close > 0) return value.slice(1, close).trim();
  }
  const title = value.match(/\s+(?:"[^"]*"|'[^']*'|\([^)]*\))\s*$/);
  if (title?.index != null) {
    value = value.slice(0, title.index).trim();
  }
  return value;
}

function isGeneratedInlineMediaPath(path: string): boolean {
  if (/^(?:https?:|data:|blob:)/i.test(path)) return false;
  return INLINE_MEDIA_DIR.test(path);
}

function markdownMediaKind(path: string, label: string, imageSyntax: boolean): MediaKind {
  const lowerLabel = label.toLowerCase();
  if (lowerLabel.includes('video') || label.includes('🎬')) return 'video';
  if (lowerLabel.includes('audio') || lowerLabel.includes('sound') || label.includes('🔊')) return 'audio';
  if (imageSyntax || lowerLabel.includes('image') || lowerLabel.includes('picture')) return 'image';
  return mediaKindFromPath(path);
}

function collectMarkdownMedia(message: SessionMessage, out: MediaItem[]): void {
  const content = message.content ?? '';
  if (!content || !content.includes('openhand_media')) return;
  for (const match of content.matchAll(MARKDOWN_MEDIA_REF)) {
    const path = normalizeMarkdownDestination(match[3] ?? '');
    if (!isGeneratedInlineMediaPath(path)) continue;
    const label = (match[2] ?? '').trim();
    pushString(out, path, markdownMediaKind(path, label, match[1] === '!'));
  }
  for (const match of content.matchAll(HTML_MEDIA_SRC)) {
    const path = (match[1] ?? '').trim();
    if (!isGeneratedInlineMediaPath(path)) continue;
    pushString(out, path);
  }
}

function collectMedia(message: SessionMessage): MediaItem[] {
  const meta = message.metadata as Record<string, unknown> | undefined;
  const out: MediaItem[] = [];
  if (meta) {
    const atts = meta['attachments'];
    if (Array.isArray(atts)) {
      for (const entry of atts) {
        if (entry && typeof entry === 'object') {
          const e = entry as Record<string, unknown>;
          const hintKind = typeof e['kind'] === 'string'
            ? (e['kind'] as string)
            : typeof e['type'] === 'string'
              ? (e['type'] as string)
              : undefined;
          pushString(
            out,
            e['storage_path'] ?? e['path'] ?? e['file_path'] ?? e['original_source_path'],
            hintKind,
          );
        } else if (typeof entry === 'string') {
          pushString(out, entry);
        }
      }
    }
    const KEY_MAP: Record<string, MediaKind> = {
      image_path: 'image',
      image_paths: 'image',
      generated_image_path: 'image',
      generated_image_paths: 'image',
      video_path: 'video',
      video_paths: 'video',
      generated_video_path: 'video',
      generated_video_paths: 'video',
      audio_path: 'audio',
      audio_paths: 'audio',
      generated_audio_path: 'audio',
      generated_audio_paths: 'audio',
      media_path: 'file',
      media_paths: 'file',
    };
    for (const key of Object.keys(KEY_MAP)) {
      const v = meta[key];
      if (typeof v === 'string') pushString(out, v, KEY_MAP[key]);
      else if (Array.isArray(v)) for (const e of v) pushString(out, e, KEY_MAP[key]);
    }
  }
  collectMarkdownMedia(message, out);
  // 去重 (按 path)
  const seen = new Set<string>();
  return out.filter((m) => {
    if (seen.has(m.path)) return false;
    seen.add(m.path);
    return true;
  });
}

function pickerTypesForMedia(item: MediaItem): SaveBlobPickerType[] | undefined {
  switch (item.kind) {
    case 'image':
      return [{ description: 'Image', accept: { 'image/*': IMAGE_EXTS } }];
    case 'video':
      return [{ description: 'Video', accept: { 'video/*': VIDEO_EXTS } }];
    case 'audio':
      return [{ description: 'Audio', accept: { 'audio/*': AUDIO_EXTS } }];
    default:
      return undefined;
  }
}

async function saveMediaAsset(item: MediaItem, url: string): Promise<void> {
  const res = await fetch(url, { credentials: 'same-origin' });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const blob = await res.blob();
  await saveBlobWithPicker(blob, item.name, pickerTypesForMedia(item));
}

function mediaKindLabel(kind: MediaKind): string {
  switch (kind) {
    case 'image':
      return t('detail.media.image', '图片');
    case 'video':
      return t('detail.media.video', '视频');
    case 'audio':
      return t('detail.media.audio', '音频');
    default:
      return t('detail.media.file', '文件');
  }
}

export interface MessageMediaProps {
  message: SessionMessage;
  sessionId: string;
}

interface MediaPreviewDialogProps {
  item: MediaItem;
  url: string;
  onClose: () => void;
}

function MediaPreviewDialog({ item, url, onClose }: MediaPreviewDialogProps) {
  const stageRef = useRef<HTMLDivElement | null>(null);
  const [saving, setSaving] = useState(false);
  const { closing, requestClose } = useDialogExitMotion(onClose);
  useEffect(() => {
    if (closing) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closing, requestClose]);
  const requestFullscreen = async () => {
    try {
      await stageRef.current?.requestFullscreen?.();
    } catch {
      showSnackbar(t('detail.media.fullscreenFailed', '无法进入全屏'), { tone: 'error' });
    }
  };
  const handleSave = async () => {
    if (saving) return;
    setSaving(true);
    try {
      await saveMediaAsset(item, url);
      showSnackbar(t('detail.media.saveOk', '已保存媒体文件'), { tone: 'success' });
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      showSnackbar(
        `${t('detail.media.saveFailed', '保存失败')}：${error instanceof Error ? error.message : String(error)}`,
        { tone: 'error' },
      );
    } finally {
      setSaving(false);
    }
  };

  if (typeof document === 'undefined') return null;
  return createPortal(
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center p-4`}
      style={{
        zIndex: 3000,
        background: 'color-mix(in srgb, black 58%, transparent)',
        backdropFilter: 'blur(10px)',
      }}
      role="dialog"
      aria-modal="true"
      aria-label={item.name}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) requestClose();
      }}
    >
      <section
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} w-full max-w-5xl rounded-m3-lg overflow-hidden`}
        style={{
          background: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          boxShadow: 'var(--m3-elev-4)',
          border: '1px solid var(--m3-outline)',
          maxHeight: '92vh',
          display: 'flex',
          flexDirection: 'column',
        }}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <header class="flex items-center gap-3 px-4 py-3" style={{ borderBottom: '1px solid var(--m3-outline-variant)' }}>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold truncate">{item.name}</p>
            <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {mediaKindLabel(item.kind)}
            </p>
          </div>
          <button
            type="button"
            onClick={requestFullscreen}
            class="oh-tap-press text-xs px-3 py-1.5 rounded-m3-sm"
            style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface-variant)' }}
          >
            {t('detail.media.fullscreen', '全屏')}
          </button>
          <button
            type="button"
            onClick={handleSave}
            disabled={saving}
            class="oh-tap-press text-xs px-3 py-1.5 rounded-m3-sm disabled:opacity-50"
            style={{ background: 'var(--m3-primary)', color: 'var(--m3-on-primary)' }}
          >
            {saving ? t('detail.media.saving', '保存中…') : t('detail.media.save', '保存')}
          </button>
          <button
            type="button"
            onClick={requestClose}
            class="oh-tap-press text-xs px-3 py-1.5 rounded-m3-sm"
            style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
          >
            {t('common.close', '关闭')}
          </button>
        </header>
        <div
          ref={stageRef}
          class="flex-1 min-h-0 flex items-center justify-center"
          style={{
            background: item.kind === 'audio' ? 'var(--m3-surface)' : 'black',
            padding: item.kind === 'audio' ? '32px' : '0',
          }}
        >
          {item.kind === 'image' ? (
            <img
              src={url}
              alt={item.name}
              decoding="async"
              style={{ maxWidth: '100%', maxHeight: '76vh', objectFit: 'contain' }}
            />
          ) : item.kind === 'video' ? (
            <video
              src={url}
              controls
              autoPlay
              preload="metadata"
              style={{ width: '100%', maxHeight: '76vh', background: 'black' }}
            />
          ) : item.kind === 'audio' ? (
            <div class="w-full max-w-2xl rounded-m3-md p-4" style={{ background: 'var(--m3-surface-container-high)' }}>
              <p class="text-sm font-medium truncate mb-3">{item.name}</p>
              <audio src={url} controls autoPlay preload="metadata" style={{ width: '100%' }} />
            </div>
          ) : null}
        </div>
      </section>
    </div>,
    document.body,
  );
}

export function MessageMedia({ message, sessionId }: MessageMediaProps) {
  const items = useMemo(() => collectMedia(message), [message]);
  const [preview, setPreview] = useState<{ item: MediaItem; url: string } | null>(null);
  if (items.length === 0) return null;
  const openPreview = (item: MediaItem, url: string) => {
    if (item.kind === 'file') return;
    setPreview({ item, url });
  };

  return (
    <>
    <div class="mt-3 flex flex-col gap-2">
      {items.map((item, idx) => {
        const url = buildSessionAssetUrl(sessionId, item.path);
        const key = `${item.path}:${idx}`;
        if (item.kind === 'image') {
          return (
            <button
              key={key}
              type="button"
              onClick={() => openPreview(item, url)}
              class="oh-media-card oh-media-image-card block rounded-md overflow-hidden oh-tap-press text-left"
              style={{
                border: '1px solid var(--m3-outline)',
                background: 'var(--m3-surface)',
                maxWidth: '480px',
              }}
              title={item.name}
            >
              <img
                src={url}
                alt={item.name}
                decoding="async"
                loading="lazy"
                style={{
                  display: 'block',
                  width: '100%',
                  maxHeight: '360px',
                  objectFit: 'contain',
                  background: 'var(--m3-surface-container)',
                }}
              />
              <p
                class="text-xs px-2 py-1 truncate"
                style={{ color: 'var(--m3-on-surface-variant)' }}
              >
                {item.name}
              </p>
            </button>
          );
        }
        if (item.kind === 'video') {
          return (
            <div
              key={key}
              class="oh-media-card rounded-md overflow-hidden"
              style={{
                border: '1px solid var(--m3-outline)',
                background: 'black',
                maxWidth: '560px',
              }}
            >
              <video
                src={url}
                controls
                preload="metadata"
                style={{
                  display: 'block',
                  width: '100%',
                  maxHeight: '420px',
                  background: 'black',
                }}
              />
              <div
                class="text-xs px-2 py-1 flex items-center gap-2"
                style={{
                  color: 'var(--m3-on-surface-variant)',
                  background: 'var(--m3-surface)',
                }}
              >
                <span class="truncate flex-1 min-w-0">{item.name}</span>
                <button
                  type="button"
                  onClick={() => openPreview(item, url)}
                  class="oh-tap-press px-2 py-1 rounded-m3-sm"
                  style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline-variant)' }}
                >
                  {t('detail.media.preview', '预览')}
                </button>
              </div>
            </div>
          );
        }
        if (item.kind === 'audio') {
          return (
            <div
              key={key}
              class="oh-media-card rounded-md px-3 py-2 flex flex-col gap-2"
              style={{
                border: '1px solid var(--m3-outline)',
                background: 'var(--m3-surface)',
                maxWidth: '480px',
              }}
            >
              <div class="flex items-center gap-2">
                <p
                  class="text-xs truncate flex-1 min-w-0"
                  style={{ color: 'var(--m3-on-surface)' }}
                >
                  {item.name}
                </p>
                <button
                  type="button"
                  onClick={() => openPreview(item, url)}
                  class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm"
                  style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline-variant)' }}
                >
                  {t('detail.media.preview', '预览')}
                </button>
              </div>
              <audio
                src={url}
                controls
                preload="metadata"
                style={{ width: '100%' }}
              />
            </div>
          );
        }
        // 通用文件 pill
        return (
          <a
            key={key}
            href={url}
            target="_blank"
            rel="noreferrer noopener"
            class="oh-media-card text-xs inline-flex items-center gap-2 px-3 py-1.5 rounded-md oh-tap-press"
            style={{
              border: '1px solid var(--m3-outline)',
              color: 'var(--m3-on-surface)',
              background: 'var(--m3-surface)',
              maxWidth: '480px',
            }}
            title={item.path}
          >
            <span class="truncate">{item.name}</span>
            {item.hintLabel ? (
              <span
                class="ml-auto text-[10px]"
                style={{ color: 'var(--m3-on-surface-variant)' }}
              >
                {t('detail.media.kind.' + item.hintLabel, item.hintLabel)}
              </span>
            ) : null}
          </a>
        );
      })}
    </div>
    {preview ? (
      <MediaPreviewDialog
        item={preview.item}
        url={preview.url}
        onClose={() => setPreview(null)}
      />
    ) : null}
    </>
  );
}
