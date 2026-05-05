// 媒体渲染: 将 message.metadata 中的附件/生成媒体路径转换为
// <img>/<video>/<audio>/通用文件 pill, 1:1 对齐 App 端
// _MessageMediaCard / _MessageImageBubble / _MessageVideoBubble / _MessageAudioBubble。
// 路径不直接发给 <img src=>: 走 /api/sessions/<id>/asset?path=...&token=...
// 由 service 端基于 session 消息 metadata 白名单放行。

import { useMemo } from 'preact/hooks';
import type { SessionMessage } from '../api/sessions';
import { readToken } from '../state/storage';
import { t } from '../i18n';

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

function collectMedia(message: SessionMessage): MediaItem[] {
  const meta = message.metadata as Record<string, unknown> | undefined;
  if (!meta) return [];
  const out: MediaItem[] = [];
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
        pushString(out, e['path'], hintKind);
        pushString(out, e['file_path'], hintKind);
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
  // 去重 (按 path)
  const seen = new Set<string>();
  return out.filter((m) => {
    if (seen.has(m.path)) return false;
    seen.add(m.path);
    return true;
  });
}

function buildAssetUrl(sessionId: string, path: string, token: string): string {
  const qs = new URLSearchParams();
  qs.set('path', path);
  if (token) qs.set('token', token);
  return `/api/sessions/${encodeURIComponent(sessionId)}/asset?${qs.toString()}`;
}

export interface MessageMediaProps {
  message: SessionMessage;
  sessionId: string;
}

export function MessageMedia({ message, sessionId }: MessageMediaProps) {
  const items = useMemo(() => collectMedia(message), [message]);
  if (items.length === 0) return null;
  const token = readToken() ?? '';

  return (
    <div class="mt-3 flex flex-col gap-2">
      {items.map((item, idx) => {
        const url = buildAssetUrl(sessionId, item.path, token);
        const key = `${item.path}:${idx}`;
        if (item.kind === 'image') {
          return (
            <a
              key={key}
              href={url}
              target="_blank"
              rel="noreferrer noopener"
              class="block rounded-md overflow-hidden oh-tap-press"
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
            </a>
          );
        }
        if (item.kind === 'video') {
          return (
            <div
              key={key}
              class="rounded-md overflow-hidden"
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
              <p
                class="text-xs px-2 py-1 truncate"
                style={{
                  color: 'var(--m3-on-surface-variant)',
                  background: 'var(--m3-surface)',
                }}
              >
                {item.name}
              </p>
            </div>
          );
        }
        if (item.kind === 'audio') {
          return (
            <div
              key={key}
              class="rounded-md px-3 py-2 flex flex-col gap-1"
              style={{
                border: '1px solid var(--m3-outline)',
                background: 'var(--m3-surface)',
                maxWidth: '480px',
              }}
            >
              <p
                class="text-xs truncate"
                style={{ color: 'var(--m3-on-surface)' }}
              >
                🎙 {item.name}
              </p>
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
            class="text-xs inline-flex items-center gap-2 px-3 py-1.5 rounded-md oh-tap-press"
            style={{
              border: '1px solid var(--m3-outline)',
              color: 'var(--m3-on-surface)',
              background: 'var(--m3-surface)',
              maxWidth: '480px',
            }}
            title={item.path}
          >
            <span aria-hidden>📎</span>
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
  );
}
