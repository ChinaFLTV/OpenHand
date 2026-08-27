// 媒体渲染: 将 message.metadata 中的附件/生成媒体路径转换为
// <img>/<video>/<audio>/通用文件 pill, 1:1 对齐 App 端
// _MessageMediaCard / _MessageImageBubble / _MessageVideoBubble / _MessageAudioBubble。
// 路径不直接发给 <img src=>: 走 /api/sessions/<id>/asset?path=...&token=...
// 由 service 端基于 session 消息 metadata 白名单放行。

import type { JSX } from 'preact';
import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { SessionMessage } from '../api/sessions';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { rollingHash31Base36 } from '../shared/util/hash';
import { normalizeMarkdownDestination } from '../shared/util/markdown';
import { clampNumber, finiteNumberFromText } from '../shared/util/number';
import { basenameFromPath } from '../shared/util/path';
import { strictStringFromUnknown } from '../shared/util/value';
import { copyBlobToClipboard, copyTextToClipboard } from '../utils/clipboard';
import { isAbortError } from '../shared/util/errors';
import {
  revokeObjectUrlQuietly,
  saveBlobWithPicker,
  type SaveBlobPickerType,
} from '../utils/save_blob';
import { buildSessionAssetUrl } from '../utils/session_asset';
import { createTimedAbortController } from '../utils/timed_abort';
import {
  cancelResponseBodyQuietly,
  fetchBlobBounded,
  readResponseBlobBounded,
} from '../utils/bounded_response';
import {
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';
import { showSnackbar } from './Snackbar';
import { MediaKindIcon } from './MediaKindIcon';
import { svgIconProps } from '../shared/ui/svg_icon';
import { CACHE_NAME_REMOTE_MEDIA } from '../shared/util/storage_keys';

type MediaKind = 'image' | 'video' | 'audio' | 'file';

export interface MediaItem {
  /// 原始本地绝对路径或网络 URL
  path: string;
  /// 仅供展示的文件名
  name: string;
  kind: MediaKind;
  /// 来自 metadata.attachments[].kind 等的语义标签
  hintLabel?: string;
  /// 标记该 item 的 path 是否为可直接访问的网络 URL (http/https),
  /// 为 true 时 MessageMedia 直接使用 path 作为 src, 不走 session asset 代理。
  isDirectUrl?: boolean;
}

interface MediaEntry {
  item: MediaItem;
  url: string;
  key: string;
}

const IMAGE_EXTS = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.svg'];
const VIDEO_EXTS = ['.mp4', '.webm', '.mov', '.m4v'];
const AUDIO_EXTS = ['.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac'];
const MEDIA_DOWNLOAD_TIMEOUT_MS = 120_000;
const MEDIA_CLIPBOARD_FETCH_TIMEOUT_MS = 30_000;
const REMOTE_MEDIA_CACHE_TIMEOUT_MS = 120_000;
const REMOTE_MEDIA_CACHE_MAX_BYTES: Record<MediaKind, number> = {
  image: 64 * 1024 * 1024,
  audio: 256 * 1024 * 1024,
  video: 512 * 1024 * 1024,
  file: 0,
};
const MEDIA_FILE_DOWNLOAD_MAX_BYTES = 512 * 1024 * 1024;
const PREVIEW_VIEWPORT_GAP = 16;
const PREVIEW_CONTENT_PADDING = 12;
const PREVIEW_HEADER_ESTIMATE = 66;
const PREVIEW_MIN_PANEL_WIDTH = 360;
const PREVIEW_FALLBACK_IMAGE_SIDE = 320;
const PREVIEW_FALLBACK_VIDEO_RATIO = 16 / 9;
const IMAGE_PREVIEW_MIN_SCALE = 1;
const IMAGE_PREVIEW_MAX_SCALE = 6;
const IMAGE_PREVIEW_WHEEL_SENSITIVITY = 0.0025;
const IMAGE_PREVIEW_TRANSITION = 'transform 120ms cubic-bezier(0.2, 0, 0, 1)';
const AUDIO_SEEK_STEP_SECONDS = 15;
const MARKDOWN_MEDIA_REF = /(!?)\[([^\]\n]{0,240})\]\(([^)\r\n]+)\)/g;
const HTML_MEDIA_SRC = /<(?:img|video|audio|source)\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi;
const INLINE_MEDIA_DIR = /(^|[\\/])openhand_media([\\/]|$)/i;
const MEDIA_METADATA_KIND_BY_KEY: Record<string, MediaKind> = {
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
const MEDIA_METADATA_KEYS = Object.keys(MEDIA_METADATA_KIND_BY_KEY);
const MEDIA_ATTACHMENT_SIGNATURE_KEYS = [
  'storage_path',
  'path',
  'file_path',
  'original_source_path',
  'kind',
  'type',
  'mime_type',
  'mime',
  'content_type',
  'name',
  'file_name',
  'original_name',
  'filename',
] as const;

interface PreviewNaturalSize {
  width: number;
  height: number;
}

interface PreviewViewportSize {
  width: number;
  height: number;
}

interface PreviewLayout {
  maxPanelWidth: number;
  maxPanelHeight: number;
  panelWidth: number;
  stageHeight?: number;
  contentWidth?: number;
  contentHeight?: number;
}

function readPreviewViewport(): PreviewViewportSize {
  if (typeof window === 'undefined') return { width: 1280, height: 800 };
  return {
    width: Math.max(1, window.innerWidth || 1),
    height: Math.max(1, window.innerHeight || 1),
  };
}

function usePreviewViewport(): PreviewViewportSize {
  const [viewport, setViewport] = useState<PreviewViewportSize>(() => readPreviewViewport());
  useEffect(() => {
    if (typeof window === 'undefined') return;
    let frame = 0;
    const update = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        setViewport(readPreviewViewport());
      });
    };
    window.addEventListener('resize', update);
    return () => {
      window.removeEventListener('resize', update);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, []);
  return viewport;
}

function computePreviewLayout(
  kind: MediaKind,
  naturalSize: PreviewNaturalSize | null,
  viewport: PreviewViewportSize,
  headerHeight: number,
): PreviewLayout {
  const maxPanelWidth = Math.max(PREVIEW_MIN_PANEL_WIDTH, viewport.width - PREVIEW_VIEWPORT_GAP * 2);
  const maxPanelHeight = Math.max(220, viewport.height - PREVIEW_VIEWPORT_GAP * 2);
  const maxContentWidth = Math.max(1, maxPanelWidth - PREVIEW_CONTENT_PADDING * 2);
  const chromeHeight = Math.max(PREVIEW_HEADER_ESTIMATE, headerHeight);
  const maxContentHeight = Math.max(
    1,
    maxPanelHeight - chromeHeight - PREVIEW_CONTENT_PADDING * 2,
  );

  if (kind === 'image' || kind === 'video') {
    if (kind === 'image' && !naturalSize) {
      const side = Math.min(PREVIEW_FALLBACK_IMAGE_SIDE, maxContentWidth, maxContentHeight);
      return {
        maxPanelWidth,
        maxPanelHeight,
        panelWidth: clampNumber(
          side + PREVIEW_CONTENT_PADDING * 2,
          PREVIEW_MIN_PANEL_WIDTH,
          maxPanelWidth,
        ),
        stageHeight: side + PREVIEW_CONTENT_PADDING * 2,
        contentWidth: side,
        contentHeight: side,
      };
    }
    const fallbackRatio = kind === 'image' ? 1 : PREVIEW_FALLBACK_VIDEO_RATIO;
    const ratio = naturalSize && naturalSize.width > 0 && naturalSize.height > 0
      ? naturalSize.width / naturalSize.height
      : fallbackRatio;
    let contentWidth = maxContentWidth;
    let contentHeight = contentWidth / ratio;
    if (contentHeight > maxContentHeight) {
      contentHeight = maxContentHeight;
      contentWidth = contentHeight * ratio;
    }
    const panelWidth = clampNumber(
      contentWidth + PREVIEW_CONTENT_PADDING * 2,
      PREVIEW_MIN_PANEL_WIDTH,
      maxPanelWidth,
    );
    return {
      maxPanelWidth,
      maxPanelHeight,
      panelWidth,
      stageHeight: contentHeight + PREVIEW_CONTENT_PADDING * 2,
      contentWidth,
      contentHeight,
    };
  }

  const targetWidth = kind === 'audio' ? 680 : 640;
  const contentWidth = Math.min(targetWidth, maxContentWidth);
  return {
    maxPanelWidth,
    maxPanelHeight,
    panelWidth: clampNumber(
      contentWidth + PREVIEW_CONTENT_PADDING * 2,
      PREVIEW_MIN_PANEL_WIDTH,
      maxPanelWidth,
    ),
    contentWidth,
  };
}

function mediaKindFromPath(path: string, hintKind?: string): MediaKind {
  const lower = path.toLowerCase();
  if (hintKind) {
    const k = hintKind.toLowerCase();
    if (k === 'image' || k === 'img' || k === 'picture' || k === 'photo' || k.startsWith('image/')) return 'image';
    if (k === 'video' || k === 'movie' || k.startsWith('video/')) return 'video';
    if (k === 'audio' || k === 'sound' || k === 'voice' || k.startsWith('audio/')) return 'audio';
  }
  if (IMAGE_EXTS.some((e) => lower.endsWith(e))) return 'image';
  if (VIDEO_EXTS.some((e) => lower.endsWith(e))) return 'video';
  if (AUDIO_EXTS.some((e) => lower.endsWith(e))) return 'audio';
  return 'file';
}

function firstNonEmptyString(...values: unknown[]): string | undefined {
  for (const value of values) {
    const text = strictStringFromUnknown(value);
    if (text) return text;
  }
  return undefined;
}

function pushString(
  out: MediaItem[],
  raw: unknown,
  hintKind?: string,
  displayName?: string,
): void {
  if (typeof raw !== 'string') return;
  const path = raw.trim();
  if (!path) return;
  // 远程 URL 和 data URI 由 Markdown 层内联渲染并提供图片预览，此处跳过。
  if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
    return;
  }
  const name = displayName?.trim() || basenameFromPath(path);
  out.push({
    path,
    name,
    kind: mediaKindFromPath(`${path} ${name}`, hintKind),
    hintLabel: hintKind,
  });
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
  if (!content) return;
  // 收集 openhand_media 本地路径的媒体。
  if (content.includes('openhand_media')) {
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
  // 收集 markdown 中的网络媒体 URL (图片/视频/音频)。
  // 当 AI 生成图片首次下载失败时, markdown 中保留原始网络 URL,
  // 此处将其收集为 MediaItem 以便渲染为带文件名的媒体卡片。
  for (const match of content.matchAll(MARKDOWN_MEDIA_REF)) {
    const rawPath = normalizeMarkdownDestination(match[3] ?? '');
    if (!rawPath.startsWith('http://') && !rawPath.startsWith('https://')) continue;
    const label = (match[2] ?? '').trim();
    const kind = markdownMediaKind(rawPath, label, match[1] === '!');
    if (kind === 'file') continue; // 只收集图片/视频/音频, 跳过通用文件链接
    // 从 URL 中提取文件名。
    let name = label;
    if (!name) {
      try {
        const pathname = new URL(rawPath).pathname;
        const lastSlash = pathname.lastIndexOf('/');
        name = lastSlash >= 0 ? decodeURIComponent(pathname.slice(lastSlash + 1)) : 'media';
      } catch {
        name = 'media';
      }
    }
    // 如果文件名过长或不含扩展名, 生成友好名称。
    if (name.length > 60 || (!name.includes('.') && kind === 'image')) {
      const ext = kind === 'image' ? '.png' : kind === 'video' ? '.mp4' : '.mp3';
      // 使用 URL hash 作为稳定标识, 避免每次渲染生成不同名称。
      name = `${kind}_${rollingHash31Base36(rawPath)}${ext}`;
    }
    out.push({ path: rawPath, name, kind, isDirectUrl: true });
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
          const hintKind = firstNonEmptyString(
            e['kind'],
            e['type'],
            e['mime_type'],
            e['mime'],
            e['content_type'],
          );
          const displayName = firstNonEmptyString(
            e['name'],
            e['file_name'],
            e['original_name'],
            e['filename'],
          );
          pushString(
            out,
            e['storage_path'] ?? e['path'] ?? e['file_path'] ?? e['original_source_path'],
            hintKind,
            displayName,
          );
        } else if (typeof entry === 'string') {
          pushString(out, entry);
        }
      }
    }
    for (const key of MEDIA_METADATA_KEYS) {
      const v = meta[key];
      const kind = MEDIA_METADATA_KIND_BY_KEY[key];
      if (typeof v === 'string') pushString(out, v, kind);
      else if (Array.isArray(v)) for (const e of v) pushString(out, e, kind);
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

export function messageHasMultimedia(message: SessionMessage): boolean {
  return collectMedia(message).some((item) => (
    item.kind === 'image' || item.kind === 'video' || item.kind === 'audio'
  ));
}

function mediaMetadataSignature(meta: Record<string, unknown> | undefined): string {
  if (!meta) return '';
  const parts: unknown[] = [];
  const attachments = meta['attachments'];
  if (Array.isArray(attachments)) {
    parts.push([
      'attachments',
      attachments.map((entry) => {
        if (typeof entry === 'string') return entry;
        if (!entry || typeof entry !== 'object') return null;
        const record = entry as Record<string, unknown>;
        return MEDIA_ATTACHMENT_SIGNATURE_KEYS.map((key) => record[key] ?? null);
      }),
    ]);
  }
  for (const key of MEDIA_METADATA_KEYS) {
    if (Object.prototype.hasOwnProperty.call(meta, key)) {
      parts.push([key, meta[key]]);
    }
  }
  try {
    return JSON.stringify(parts);
  } catch {
    return parts.map((entry) => String(entry)).join('|');
  }
}

/// 从 markdown 内容中移除已被 collectMedia 收集为 MediaItem 的网络媒体引用,
/// 避免 Markdown 渲染器和 MessageMedia 组件重复展示同一张图片/视频/音频。
/// 仅移除 `![alt](https://...)` 格式的网络媒体, 本地路径不受影响 (浏览器
/// 无法直接加载本地路径, 不会产生重复)。
export function stripCollectedNetworkMedia(content: string): string {
  if (!content || (!content.includes('http://') && !content.includes('https://'))) {
    return content;
  }
  return content.replace(MARKDOWN_MEDIA_REF, (match, bang, _alt, dest) => {
    const path = normalizeMarkdownDestination(dest ?? '');
    if (!path.startsWith('http://') && !path.startsWith('https://')) return match;
    // 只移除图片语法 (![...]) 或明确为媒体类型的链接。
    if (bang === '!') return '';
    // 非图片语法的链接: 检查是否为媒体扩展名。
    const lower = path.toLowerCase();
    const isMedia = [...IMAGE_EXTS, ...VIDEO_EXTS, ...AUDIO_EXTS].some(
      (ext) => lower.includes(ext),
    );
    return isMedia ? '' : match;
  }).replace(/\n{3,}/g, '\n\n').trim();
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

async function saveMediaAsset(item: MediaItem, url: string, signal?: AbortSignal): Promise<void> {
  const blob = await fetchMediaBlob(item, url, signal);
  await saveBlobWithPicker(blob, item.name, pickerTypesForMedia(item));
}

async function fetchMediaBlob(
  item: MediaItem,
  url: string,
  signal?: AbortSignal,
): Promise<Blob> {
  return fetchBlobBounded(url, {
    credentials: 'same-origin',
    maxBytes: mediaDownloadMaxBytes(item.kind),
    signal,
  });
}

function mediaDownloadMaxBytes(kind: MediaKind): number {
  const cacheLimit = REMOTE_MEDIA_CACHE_MAX_BYTES[kind];
  return cacheLimit > 0 ? cacheLimit : MEDIA_FILE_DOWNLOAD_MAX_BYTES;
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

function canCacheRemoteMedia(item: MediaItem, url: string): boolean {
  if (!item.isDirectUrl || item.kind === 'file') return false;
  if (item.kind === 'audio') return false;
  if (!/^https?:\/\//i.test(url)) return false;
  return typeof window !== 'undefined' && typeof window.caches !== 'undefined';
}

function isCacheableMediaResponse(item: MediaItem, response: Response): boolean {
  const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
  if (contentType) {
    if (item.kind === 'image' && !contentType.startsWith('image/')) return false;
    if (item.kind === 'video' && !contentType.startsWith('video/')) return false;
    if (item.kind === 'audio' && !contentType.startsWith('audio/')) return false;
  }
  const rawLength = response.headers.get('content-length');
  const length = rawLength == null ? null : finiteNumberFromText(rawLength);
  if (length != null && length > REMOTE_MEDIA_CACHE_MAX_BYTES[item.kind]) {
    return false;
  }
  if (item.kind === 'video' && length == null) {
    return false;
  }
  return true;
}

async function objectUrlFromCachedResponse(
  item: MediaItem,
  response: Response,
  signal: AbortSignal,
): Promise<string | null> {
  const blob = await readResponseBlobBounded(response, {
    maxBytes: REMOTE_MEDIA_CACHE_MAX_BYTES[item.kind],
    signal,
  });
  if (blob.size <= 0 || blob.size > REMOTE_MEDIA_CACHE_MAX_BYTES[item.kind]) {
    return null;
  }
  return URL.createObjectURL(blob);
}

async function resolveBrowserCachedMediaUrl(
  item: MediaItem,
  url: string,
  signal: AbortSignal,
): Promise<string | null> {
  if (!canCacheRemoteMedia(item, url)) return null;
  const cache = await window.caches.open(CACHE_NAME_REMOTE_MEDIA);
  const cached = await cache.match(url);
  if (cached) {
    return objectUrlFromCachedResponse(item, cached, signal);
  }

  const response = await fetch(url, { credentials: 'same-origin', signal });
  if (!response.ok || !isCacheableMediaResponse(item, response)) {
    cancelResponseBodyQuietly(response, '媒体响应不可缓存。');
    return null;
  }
  const blob = await readResponseBlobBounded(response, {
    maxBytes: REMOTE_MEDIA_CACHE_MAX_BYTES[item.kind],
    signal,
  });
  if (signal.aborted || blob.size <= 0 || blob.size > REMOTE_MEDIA_CACHE_MAX_BYTES[item.kind]) {
    return null;
  }
  const headers = new Headers();
  headers.set('content-type', blob.type || response.headers.get('content-type') || 'application/octet-stream');
  headers.set('content-length', String(blob.size));
  headers.set('x-openhand-source-url', url);
  await cache.put(url, new Response(blob, { headers }));
  return URL.createObjectURL(blob);
}

interface ImagePreviewTransform {
  scale: number;
  x: number;
  y: number;
}

interface ImagePreviewPoint {
  x: number;
  y: number;
}

interface ImagePreviewDragStart {
  pointerId: number;
  x: number;
  y: number;
  transform: ImagePreviewTransform;
}

interface ImagePreviewPinchStart {
  distance: number;
  scale: number;
}

interface InteractiveImagePreviewProps {
  item: MediaItem;
  url: string;
  style: JSX.CSSProperties;
  onNaturalSize: (width: number, height: number) => void;
}

function clampPreviewTransform(
  transform: ImagePreviewTransform,
  viewport: HTMLElement,
): ImagePreviewTransform {
  const rect = viewport.getBoundingClientRect();
  const width = Math.max(1, rect.width || viewport.clientWidth || 1);
  const height = Math.max(1, rect.height || viewport.clientHeight || 1);
  const scale = clampNumber(
    transform.scale,
    IMAGE_PREVIEW_MIN_SCALE,
    IMAGE_PREVIEW_MAX_SCALE,
  );
  const maxX = Math.max(0, (width * scale - width) / 2);
  const maxY = Math.max(0, (height * scale - height) / 2);
  return {
    scale,
    x: clampNumber(transform.x, -maxX, maxX),
    y: clampNumber(transform.y, -maxY, maxY),
  };
}

function pointerCenterInViewport(
  viewport: HTMLElement,
  clientX: number,
  clientY: number,
): ImagePreviewPoint {
  const rect = viewport.getBoundingClientRect();
  return {
    x: clientX - rect.left - rect.width / 2,
    y: clientY - rect.top - rect.height / 2,
  };
}

function pointerDistance(points: ImagePreviewPoint[]): number {
  if (points.length < 2) return 0;
  return Math.hypot(points[0]!.x - points[1]!.x, points[0]!.y - points[1]!.y);
}

function InteractiveImagePreview({
  item,
  url,
  style,
  onNaturalSize,
}: InteractiveImagePreviewProps) {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const contentRef = useRef<HTMLDivElement | null>(null);
  const transformRef = useRef<ImagePreviewTransform>({ scale: 1, x: 0, y: 0 });
  const pointersRef = useRef<Map<number, ImagePreviewPoint>>(new Map());
  const dragStartRef = useRef<ImagePreviewDragStart | null>(null);
  const pinchStartRef = useRef<ImagePreviewPinchStart | null>(null);

  const applyTransform = useCallback((
    next: ImagePreviewTransform,
    options: { animated?: boolean; dragging?: boolean } = {},
  ) => {
    const viewport = viewportRef.current;
    const content = contentRef.current;
    if (!viewport || !content) return;
    const clamped = clampPreviewTransform(next, viewport);
    transformRef.current = clamped;
    content.style.transition = options.animated ? IMAGE_PREVIEW_TRANSITION : 'none';
    content.style.transform = `translate3d(${clamped.x}px, ${clamped.y}px, 0) scale(${clamped.scale})`;
    viewport.style.cursor = options.dragging
      ? 'grabbing'
      : clamped.scale > IMAGE_PREVIEW_MIN_SCALE + 0.01
        ? 'grab'
        : 'zoom-in';
  }, []);

  const resetTransform = useCallback((animated = true) => {
    applyTransform({ scale: 1, x: 0, y: 0 }, { animated });
  }, [applyTransform]);

  useEffect(() => {
    resetTransform(true);
  }, [item.path, resetTransform, style.height, style.width, url]);

  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return undefined;
    const pointers = pointersRef.current;

    const syncSinglePointerDragStart = (): void => {
      if (pointers.size !== 1) {
        dragStartRef.current = null;
        return;
      }
      const entry = Array.from(pointers.entries())[0];
      if (!entry) return;
      dragStartRef.current = {
        pointerId: entry[0],
        x: entry[1].x,
        y: entry[1].y,
        transform: { ...transformRef.current },
      };
    };

    const zoomAt = (
      nextScale: number,
      clientX: number,
      clientY: number,
    ): void => {
      const current = transformRef.current;
      const scale = clampNumber(
        nextScale,
        IMAGE_PREVIEW_MIN_SCALE,
        IMAGE_PREVIEW_MAX_SCALE,
      );
      const ratio = scale / Math.max(IMAGE_PREVIEW_MIN_SCALE, current.scale);
      const center = pointerCenterInViewport(viewport, clientX, clientY);
      applyTransform({
        scale,
        x: center.x - (center.x - current.x) * ratio,
        y: center.y - (center.y - current.y) * ratio,
      });
    };

    const startPinchIfReady = (): void => {
      if (pointers.size !== 2) {
        pinchStartRef.current = null;
        return;
      }
      const distance = pointerDistance(Array.from(pointers.values()));
      pinchStartRef.current = {
        distance: Math.max(1, distance),
        scale: transformRef.current.scale,
      };
    };

    const handlePointerDown = (event: PointerEvent): void => {
      if (event.button != null && event.button !== 0) return;
      event.preventDefault();
      try {
        viewport.setPointerCapture(event.pointerId);
      } catch {
        // 指针已取消时可能无法捕获。
      }
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.size === 2) {
        dragStartRef.current = null;
        startPinchIfReady();
        applyTransform(transformRef.current, { dragging: true });
        return;
      }
      if (pointers.size === 1) {
        syncSinglePointerDragStart();
        applyTransform(transformRef.current, {
          dragging: transformRef.current.scale > IMAGE_PREVIEW_MIN_SCALE + 0.01,
        });
      }
    };

    const handlePointerMove = (event: PointerEvent): void => {
      if (!pointers.has(event.pointerId)) return;
      event.preventDefault();
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.size === 2) {
        const pinchStart = pinchStartRef.current;
        const points = Array.from(pointers.values());
        if (pinchStart != null) {
          const distance = pointerDistance(points);
          const centerX = (points[0]!.x + points[1]!.x) / 2;
          const centerY = (points[0]!.y + points[1]!.y) / 2;
          zoomAt(
            pinchStart.scale * (distance / pinchStart.distance),
            centerX,
            centerY,
          );
        }
        return;
      }
      const dragStart = dragStartRef.current;
      if (pointers.size !== 1 || dragStart == null || dragStart.pointerId !== event.pointerId) {
        return;
      }
      applyTransform({
        scale: dragStart.transform.scale,
        x: dragStart.transform.x + event.clientX - dragStart.x,
        y: dragStart.transform.y + event.clientY - dragStart.y,
      }, { dragging: dragStart.transform.scale > IMAGE_PREVIEW_MIN_SCALE + 0.01 });
    };

    const handlePointerEnd = (event: PointerEvent): void => {
      pointers.delete(event.pointerId);
      try {
        viewport.releasePointerCapture(event.pointerId);
      } catch {
        // 浏览器可能已释放指针捕获。
      }
      if (pointers.size < 2) {
        pinchStartRef.current = null;
      }
      if (pointers.size === 1) {
        syncSinglePointerDragStart();
      } else if (pointers.size === 0) {
        dragStartRef.current = null;
        applyTransform(transformRef.current, { animated: true });
      }
    };

    const handleWheel = (event: WheelEvent): void => {
      if (!(event.ctrlKey || event.metaKey)) return;
      event.preventDefault();
      const current = transformRef.current;
      const delta = -event.deltaY * IMAGE_PREVIEW_WHEEL_SENSITIVITY;
      zoomAt(current.scale * (1 + delta), event.clientX, event.clientY);
    };

    const handleDoubleClick = (event: MouseEvent): void => {
      event.preventDefault();
      resetTransform(true);
    };

    viewport.addEventListener('pointerdown', handlePointerDown);
    viewport.addEventListener('pointermove', handlePointerMove);
    viewport.addEventListener('pointerup', handlePointerEnd);
    viewport.addEventListener('pointercancel', handlePointerEnd);
    viewport.addEventListener('lostpointercapture', handlePointerEnd);
    viewport.addEventListener('wheel', handleWheel, { passive: false });
    viewport.addEventListener('dblclick', handleDoubleClick);
    return () => {
      viewport.removeEventListener('pointerdown', handlePointerDown);
      viewport.removeEventListener('pointermove', handlePointerMove);
      viewport.removeEventListener('pointerup', handlePointerEnd);
      viewport.removeEventListener('pointercancel', handlePointerEnd);
      viewport.removeEventListener('lostpointercapture', handlePointerEnd);
      viewport.removeEventListener('wheel', handleWheel);
      viewport.removeEventListener('dblclick', handleDoubleClick);
      pointers.clear();
      dragStartRef.current = null;
      pinchStartRef.current = null;
    };
  }, [applyTransform, resetTransform]);

  return (
    <div
      ref={viewportRef}
      aria-label={item.name}
      style={{
        ...style,
        overflow: 'hidden',
        touchAction: 'none',
        userSelect: 'none',
        cursor: 'zoom-in',
      }}
    >
      <div
        ref={contentRef}
        style={{
          width: '100%',
          height: '100%',
          transform: 'translate3d(0, 0, 0) scale(1)',
          transformOrigin: 'center center',
          willChange: 'transform',
        }}
      >
        <img
          src={url}
          alt={item.name}
          decoding="async"
          draggable={false}
          onDragStart={(event) => event.preventDefault()}
          onLoad={(event) => {
            const img = event.currentTarget;
            onNaturalSize(img.naturalWidth, img.naturalHeight);
          }}
          style={{
            display: 'block',
            width: '100%',
            height: '100%',
            objectFit: 'contain',
            pointerEvents: 'none',
          }}
        />
      </div>
    </div>
  );
}

function attachmentLabel(item: MediaItem): string {
  return `${t('message.context.kind.attachment', '附件')} · ${mediaKindLabel(item.kind)}`;
}

function formatAudioTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '00:00';
  const total = Math.floor(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const rest = total % 60;
  const pad = (value: number) => String(value).padStart(2, '0');
  return hours > 0
    ? `${hours}:${pad(minutes)}:${pad(rest)}`
    : `${pad(minutes)}:${pad(rest)}`;
}

function audioTimeFromElement(audio: HTMLAudioElement): number {
  return Number.isFinite(audio.currentTime) && audio.currentTime >= 0
    ? audio.currentTime
    : 0;
}

function audioDurationFromElement(audio: HTMLAudioElement): number {
  return Number.isFinite(audio.duration) && audio.duration > 0
    ? audio.duration
    : 0;
}

function AudioControlIcon({ name }: { name: 'play' | 'pause' | 'rewind' | 'forward' }) {
  const common = svgIconProps({ size: 18, strokeWidth: 2.2 });
  switch (name) {
    case 'pause':
      return <svg {...common}><path d="M9 5v14M15 5v14" /></svg>;
    case 'rewind':
      return <svg {...common}><path d="m11 7-5 5 5 5V7Z" fill="currentColor" stroke="none" /><path d="m18 7-5 5 5 5V7Z" fill="currentColor" stroke="none" /></svg>;
    case 'forward':
      return <svg {...common}><path d="m6 7 5 5-5 5V7Z" fill="currentColor" stroke="none" /><path d="m13 7 5 5-5 5V7Z" fill="currentColor" stroke="none" /></svg>;
    case 'play':
    default:
      return <svg {...common}><path d="M8 5v14l11-7-11-7Z" fill="currentColor" stroke="none" /></svg>;
  }
}

interface MessageAudioResultCardProps {
  item: MediaItem;
  url: string;
  onPreview: () => void;
}

function MessageAudioResultCard({ item, url, onPreview }: MessageAudioResultCardProps) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [ready, setReady] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [error, setError] = useState(false);

  const syncFromElement = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;
    setDuration(audioDurationFromElement(audio));
    setPosition(audioTimeFromElement(audio));
    setReady(audio.readyState > 0 || audioDurationFromElement(audio) > 0);
    setPlaying(!audio.paused && !audio.ended);
    setError(false);
  }, []);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return undefined;
    let frame = 0;
    const scheduleSync = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        syncFromElement();
      });
    };
    const handleEnded = () => {
      setPlaying(false);
      scheduleSync();
    };
    const handleError = () => {
      setError(true);
      setPlaying(false);
    };
    audio.addEventListener('loadedmetadata', scheduleSync);
    audio.addEventListener('canplay', scheduleSync);
    audio.addEventListener('durationchange', scheduleSync);
    audio.addEventListener('timeupdate', scheduleSync);
    audio.addEventListener('play', scheduleSync);
    audio.addEventListener('pause', scheduleSync);
    audio.addEventListener('ended', handleEnded);
    audio.addEventListener('error', handleError);
    scheduleSync();
    return () => {
      audio.removeEventListener('loadedmetadata', scheduleSync);
      audio.removeEventListener('canplay', scheduleSync);
      audio.removeEventListener('durationchange', scheduleSync);
      audio.removeEventListener('timeupdate', scheduleSync);
      audio.removeEventListener('play', scheduleSync);
      audio.removeEventListener('pause', scheduleSync);
      audio.removeEventListener('ended', handleEnded);
      audio.removeEventListener('error', handleError);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, [syncFromElement, url]);

  useEffect(() => {
    setReady(false);
    setPlaying(false);
    setPosition(0);
    setDuration(0);
    setError(false);
  }, [url]);

  const seekTo = useCallback((seconds: number) => {
    const audio = audioRef.current;
    if (!audio || duration <= 0) return;
    const next = clampNumber(seconds, 0, duration);
    audio.currentTime = next;
    setPosition(next);
  }, [duration]);

  const seekBy = useCallback((delta: number) => {
    seekTo(position + delta);
  }, [position, seekTo]);

  const togglePlayback = useCallback(() => {
    const audio = audioRef.current;
    if (!audio || error) return;
    if (!audio.paused && !audio.ended) {
      audio.pause();
      setPlaying(false);
      return;
    }
    audio.play()
      .then(syncFromElement)
      .catch(() => {
        setPlaying(false);
        setError(true);
      });
  }, [error, syncFromElement]);

  const handleProgressInput = useCallback((event: JSX.TargetedEvent<HTMLInputElement, Event>) => {
    const value = finiteNumberFromText(event.currentTarget.value);
    if (value == null) return;
    seekTo(value);
  }, [seekTo]);

  const progress = duration > 0 ? clampNumber(position / duration, 0, 1) : 0;
  const canSeek = duration > 0 && !error;
  const playerLabel = error
    ? t('detail.media.audioError', '音频载入失败')
    : ready
      ? mediaKindLabel(item.kind)
      : t('detail.media.loading', '载入中');
  const progressStyle = {
    '--oh-audio-progress': `${Math.round(progress * 100)}%`,
  } as JSX.CSSProperties;

  return (
    <div
      data-message-media-interactive="true"
      onPointerDown={(ev) => { ev.stopPropagation(); }}
      onClick={(ev) => { ev.stopPropagation(); }}
      class="oh-media-card oh-media-result-card oh-audio-result-card"
      title={item.name}
    >
      <audio
        ref={audioRef}
        src={url}
        preload="metadata"
        aria-label={item.name}
        class="oh-audio-native-engine"
      />
      <div class="oh-audio-result-cover" aria-hidden>
        <MediaKindIcon kind="audio" size={22} />
      </div>
      <div class="oh-audio-result-main">
        <div class="oh-audio-result-header">
          <div class="oh-audio-result-title-block">
            <p class="oh-audio-result-title">{item.name}</p>
            <p class="oh-audio-result-subtitle">{playerLabel}</p>
          </div>
          <button
            type="button"
            onClick={(ev) => { ev.stopPropagation(); onPreview(); }}
            class="oh-tap-press oh-audio-preview-button"
          >
            {t('detail.media.preview', '预览')}
          </button>
        </div>
        <div class="oh-audio-result-controls">
          <button
            type="button"
            onClick={(ev) => { ev.stopPropagation(); seekBy(-AUDIO_SEEK_STEP_SECONDS); }}
            disabled={!canSeek}
            class="oh-tap-press oh-audio-icon-button"
            aria-label={t('detail.media.audioRewind', '后退')}
            title={t('detail.media.audioRewind', '后退')}
          >
            <AudioControlIcon name="rewind" />
          </button>
          <button
            type="button"
            onClick={(ev) => { ev.stopPropagation(); togglePlayback(); }}
            disabled={error}
            class="oh-tap-press oh-audio-icon-button is-primary"
            aria-label={playing ? t('detail.media.pause', '暂停') : t('detail.media.play', '播放')}
            title={playing ? t('detail.media.pause', '暂停') : t('detail.media.play', '播放')}
          >
            <AudioControlIcon name={playing ? 'pause' : 'play'} />
          </button>
          <button
            type="button"
            onClick={(ev) => { ev.stopPropagation(); seekBy(AUDIO_SEEK_STEP_SECONDS); }}
            disabled={!canSeek}
            class="oh-tap-press oh-audio-icon-button"
            aria-label={t('detail.media.audioForward', '前进')}
            title={t('detail.media.audioForward', '前进')}
          >
            <AudioControlIcon name="forward" />
          </button>
          <span class="oh-audio-time">{formatAudioTime(position)}</span>
          <input
            type="range"
            min="0"
            max={duration > 0 ? String(duration) : '0'}
            step="0.01"
            value={duration > 0 ? String(position) : '0'}
            disabled={!canSeek}
            onInput={handleProgressInput}
            class="oh-audio-progress"
            style={progressStyle}
            aria-label={t('detail.media.audioProgress', '音频进度')}
          />
          <span class="oh-audio-time">{formatAudioTime(duration)}</span>
        </div>
      </div>
    </div>
  );
}

interface MessageMediaProps {
  message: SessionMessage;
  sessionId: string;
  presentation?: 'auto' | 'preview' | 'attachmentList';
}

interface MediaPreviewDialogProps {
  item: MediaItem;
  url: string;
  onClose: () => void;
}

export function MediaPreviewDialog({ item, url, onClose }: MediaPreviewDialogProps) {
  const headerRef = useRef<HTMLElement | null>(null);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const saveAbortRef = useRef<AbortController | null>(null);
  const copyAbortRef = useRef<AbortController | null>(null);
  const [saving, setSaving] = useState(false);
  const [copying, setCopying] = useState(false);
  const [naturalSize, setNaturalSize] = useState<PreviewNaturalSize | null>(null);
  const [headerHeight, setHeaderHeight] = useState(PREVIEW_HEADER_ESTIMATE);
  const viewport = usePreviewViewport();
  const layout = useMemo(
    () => computePreviewLayout(item.kind, naturalSize, viewport, headerHeight),
    [item.kind, naturalSize, viewport, headerHeight],
  );
  const rememberNaturalSize = useCallback((width: number, height: number) => {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    setNaturalSize((current) => {
      if (current && current.width === width && current.height === height) return current;
      return { width, height };
    });
  }, []);
  const abortSave = useCallback(() => {
    saveAbortRef.current?.abort();
    saveAbortRef.current = null;
  }, []);
  const abortCopy = useCallback(() => {
    copyAbortRef.current?.abort();
    copyAbortRef.current = null;
  }, []);
  const abortTransfers = useCallback(() => {
    abortSave();
    abortCopy();
  }, [abortCopy, abortSave]);
  const { closing, requestClose } = useDialogExitMotion(onClose, {
    onBeforeClose: abortTransfers,
  });
  useEffect(() => () => abortTransfers(), [abortTransfers]);
  useEffect(() => setNaturalSize(null), [item.kind, item.path, url]);
  useEffect(() => {
    const header = headerRef.current;
    if (!header) return;
    let frame = 0;
    const measure = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        const next = header.getBoundingClientRect().height;
        if (!Number.isFinite(next) || next <= 0) return;
        setHeaderHeight((current) => Math.abs(current - next) < 0.5 ? current : next);
      });
    };
    measure();
    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', measure);
      return () => {
        window.removeEventListener('resize', measure);
        if (frame) window.cancelAnimationFrame(frame);
      };
    }
    const observer = new ResizeObserver(measure);
    observer.observe(header);
    return () => {
      observer.disconnect();
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, []);
  const requestFullscreen = async () => {
    try {
      await stageRef.current?.requestFullscreen?.();
    } catch {
      showSnackbar(t('detail.media.fullscreenFailed', '无法进入全屏'), { tone: 'error' });
    }
  };
  const handleSave = async () => {
    if (saving) return;
    saveAbortRef.current?.abort();
    const timed = createTimedAbortController(MEDIA_DOWNLOAD_TIMEOUT_MS);
    saveAbortRef.current = timed.controller;
    setSaving(true);
    try {
      await saveMediaAsset(item, url, timed.controller.signal);
      if (timed.controller.signal.aborted) return;
      showSnackbar(t('detail.media.saveOk', '已保存媒体文件'), { tone: 'success' });
    } catch (error) {
      if (timed.timedOut) {
        const reason = timed.controller.signal.reason;
        showSnackbar(
          `${t('detail.media.saveFailed', '保存失败')}：${reason instanceof Error ? reason.message : t('detail.media.timeout', '操作超时')}`,
          { tone: 'error' },
        );
        return;
      }
      if (timed.controller.signal.aborted || isAbortError(error)) return;
      showSnackbar(
        `${t('detail.media.saveFailed', '保存失败')}：${error instanceof Error ? error.message : String(error)}`,
        { tone: 'error' },
      );
    } finally {
      timed.dispose();
      if (saveAbortRef.current === timed.controller) {
        saveAbortRef.current = null;
        setSaving(false);
      }
    }
  };
  const handleCopy = async () => {
    if (copying) return;
    copyAbortRef.current?.abort();
    const timed = createTimedAbortController(MEDIA_CLIPBOARD_FETCH_TIMEOUT_MS);
    copyAbortRef.current = timed.controller;
    setCopying(true);
    try {
      let richCopied = false;
      try {
        const blob = await fetchMediaBlob(item, url, timed.controller.signal);
        if (!timed.controller.signal.aborted) {
          richCopied = await copyBlobToClipboard(blob);
        }
      } catch (error) {
        if (timed.timedOut) {
          const reason = timed.controller.signal.reason;
          showSnackbar(
            `${t('detail.copy.failed', '复制失败')}：${reason instanceof Error ? reason.message : t('detail.media.timeout', '操作超时')}`,
            { tone: 'error' },
          );
          return;
        }
        if (timed.controller.signal.aborted || isAbortError(error)) return;
      }
      if (timed.controller.signal.aborted) return;
      if (richCopied) {
        showSnackbar(t('detail.media.copyOk', '已复制到剪贴板'), { tone: 'success' });
        return;
      }
      const sourceText = item.path.trim() || url;
      const textCopied = await copyTextToClipboard(sourceText);
      if (timed.controller.signal.aborted) return;
      showSnackbar(
        textCopied
          ? item.kind === 'file'
            ? t('detail.media.copyPathOk', '浏览器不支持直接复制该文件，已复制文件路径')
            : t('detail.media.copySourceOk', '已复制媒体来源')
          : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'),
        { tone: textCopied ? 'success' : 'error' },
      );
    } finally {
      timed.dispose();
      if (copyAbortRef.current === timed.controller) {
        copyAbortRef.current = null;
        setCopying(false);
      }
    }
  };

  if (typeof document === 'undefined') return null;
  const panelTransition =
    'width var(--oh-dialog-duration) var(--oh-dialog-curve), height var(--oh-dialog-duration) var(--oh-dialog-curve), max-height var(--oh-dialog-duration) var(--oh-dialog-curve)';
  const stageStyle: JSX.CSSProperties = {
    background: item.kind === 'audio' ? 'var(--m3-surface)' : 'var(--m3-surface-container)',
    padding: `${PREVIEW_CONTENT_PADDING}px`,
    flex: '0 0 auto',
    transition: panelTransition,
  };
  if (layout.stageHeight != null) {
    stageStyle.height = `${layout.stageHeight}px`;
  }
  const mediaBoxStyle: JSX.CSSProperties = {
    display: 'block',
    width: `${layout.contentWidth ?? 1}px`,
  };
  if (layout.contentHeight != null) {
    mediaBoxStyle.height = `${layout.contentHeight}px`;
  }
  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlay: {
          background: 'color-mix(in srgb, black 58%, transparent)',
          blurPx: 10,
        },
        overlayZIndex: DIALOG_OVERLAY_TOP_Z_INDEX,
        panelClassName: 'rounded-m3-lg overflow-hidden',
        panelBorder: 'outline',
        panelSurface: {
          width: `${layout.panelWidth}px`,
          maxWidth: `${layout.maxPanelWidth}px`,
          maxHeight: `${layout.maxPanelHeight}px`,
          boxShadow: 'var(--m3-elev-4)',
        },
        panelStyleOverrides: {
          display: 'flex',
          flexDirection: 'column',
          transition: panelTransition,
        },
      })}
      ariaLabel={item.name}
    >
      <header ref={headerRef} class="flex items-center gap-3 px-4 py-3" style={{ borderBottom: '1px solid var(--m3-outline-variant)' }}>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold truncate">{item.name}</p>
            <p class="text-xs oh-text-muted">
              {mediaKindLabel(item.kind)}
            </p>
          </div>
          {item.kind !== 'file' ? (
            <button
              type="button"
              onClick={requestFullscreen}
              class="oh-tap-press text-xs px-3 py-1.5 rounded-m3-sm"
              style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface-variant)' }}
            >
              {t('detail.media.fullscreen', '全屏')}
            </button>
          ) : null}
          <button
            type="button"
            onClick={() => void handleCopy()}
            disabled={copying}
            class="oh-tap-press text-xs px-3 py-1.5 rounded-m3-sm disabled:opacity-50"
            style={{ border: '1px solid var(--m3-outline)', color: 'var(--m3-on-surface)' }}
          >
            {copying ? t('detail.media.copying', '复制中…') : t('common.copy', '复制')}
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
          class="min-h-0 flex items-center justify-center"
          style={stageStyle}
        >
          {item.kind === 'image' ? (
            <InteractiveImagePreview
              item={item}
              url={url}
              style={mediaBoxStyle}
              onNaturalSize={rememberNaturalSize}
            />
          ) : item.kind === 'video' ? (
            <video
              src={url}
              controls
              autoPlay
              preload="metadata"
              onLoadedMetadata={(event) => {
                const video = event.currentTarget;
                rememberNaturalSize(video.videoWidth, video.videoHeight);
              }}
              style={{ ...mediaBoxStyle, objectFit: 'contain', background: 'black' }}
            />
          ) : item.kind === 'audio' ? (
            <div class="w-full rounded-m3-md p-4" style={{ background: 'var(--m3-surface-container-high)' }}>
              <p class="text-sm font-medium truncate mb-3">{item.name}</p>
              <audio src={url} controls autoPlay preload="metadata" style={{ width: '100%' }} />
            </div>
          ) : (
            <div class="w-full rounded-m3-md p-5" style={{ background: 'var(--m3-surface-container-high)' }}>
              <div class="flex items-start gap-3">
                <div
                  class="shrink-0 rounded-m3-md p-3"
                  style={{
                    color: 'var(--m3-primary)',
                    background: 'var(--m3-surface-container-highest)',
                  }}
                >
                  <MediaKindIcon kind="file" size={30} />
                </div>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-bold truncate">{item.name}</p>
                  <p class="mt-1 text-xs break-all oh-text-muted">
                    {item.path}
                  </p>
                  <div class="mt-4 flex flex-wrap gap-2">
                    <a
                      href={url}
                      target="_blank"
                      rel="noreferrer noopener"
                      class="oh-tap-press text-xs px-3 py-1.5 rounded-m3-sm"
                      style={{
                        background: 'var(--m3-primary)',
                        color: 'var(--m3-on-primary)',
                      }}
                    >
                      {t('detail.media.open', '打开')}
                    </a>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
    </DialogFrame>
  );
}

export function MessageMedia({ message, sessionId, presentation = 'auto' }: MessageMediaProps) {
  const metadataSignature = useMemo(
    () => mediaMetadataSignature(message.metadata),
    [message.metadata],
  );
  const items = useMemo(
    () => collectMedia(message),
    [message.id, message.content, metadataSignature],
  );
  const entries = useMemo<MediaEntry[]>(() => items.map((item, idx) => ({
    item,
    // 网络 URL 直接使用, 本地路径走 session asset 代理。
    url: item.isDirectUrl ? item.path : buildSessionAssetUrl(sessionId, item.path),
    key: `${item.path}:${idx}`,
  })), [items, sessionId]);
  const [cachedEntryUrls, setCachedEntryUrls] = useState<Record<string, string>>({});
  const browserObjectUrlsRef = useRef<Record<string, string>>({});
  useEffect(() => () => {
    for (const objectUrl of Object.values(browserObjectUrlsRef.current)) {
      revokeObjectUrlQuietly(objectUrl);
    }
    browserObjectUrlsRef.current = {};
  }, []);
  useEffect(() => {
    if (entries.length === 0) {
      setCachedEntryUrls({});
      return;
    }
    let disposed = false;
    const timedControllers: ReturnType<typeof createTimedAbortController>[] = [];
    setCachedEntryUrls({});
    for (const entry of entries) {
      if (!canCacheRemoteMedia(entry.item, entry.url)) continue;
      const timed = createTimedAbortController(REMOTE_MEDIA_CACHE_TIMEOUT_MS);
      timedControllers.push(timed);
      resolveBrowserCachedMediaUrl(entry.item, entry.url, timed.controller.signal)
        .then((objectUrl) => {
          timed.dispose();
          if (!objectUrl) return;
          if (disposed) {
            revokeObjectUrlQuietly(objectUrl);
            return;
          }
          const previous = browserObjectUrlsRef.current[entry.key];
          if (previous && previous !== objectUrl) {
            revokeObjectUrlQuietly(previous);
          }
          browserObjectUrlsRef.current[entry.key] = objectUrl;
          setCachedEntryUrls((current) => (
            current[entry.key] === objectUrl
              ? current
              : { ...current, [entry.key]: objectUrl }
          ));
        })
        .catch(() => {
          timed.dispose();
        });
    }
    return () => {
      disposed = true;
      for (const timed of timedControllers) {
        timed.abort();
        timed.dispose();
      }
      for (const objectUrl of Object.values(browserObjectUrlsRef.current)) {
        revokeObjectUrlQuietly(objectUrl);
      }
      browserObjectUrlsRef.current = {};
    };
  }, [entries]);
  const effectiveEntries = useMemo<MediaEntry[]>(() => entries.map((entry) => ({
    ...entry,
    url: cachedEntryUrls[entry.key] ?? entry.url,
  })), [cachedEntryUrls, entries]);
  const [preview, setPreview] = useState<{ item: MediaItem; url: string } | null>(null);
  if (items.length === 0) return null;
  const resolvedPresentation = presentation === 'auto'
    ? message.role === 'user' ? 'attachmentList' : 'preview'
    : presentation;
  const openPreview = (item: MediaItem, url: string) => {
    setPreview({ item, url });
  };

  if (resolvedPresentation === 'attachmentList') {
    return (
      <>
        <div
          class="oh-user-attachment-list"
          aria-label={t('message.context.kind.attachment', '附件')}
        >
          {effectiveEntries.map(({ item, url, key }) => {
            const label = attachmentLabel(item);
            if (item.kind === 'image') {
              return (
                <button
                  key={key}
                  type="button"
                  onClick={(event) => {
                    event.stopPropagation();
                    openPreview(item, url);
                  }}
                  class="oh-user-attachment-thumbnail oh-tap-press"
                  title={`${item.name} · ${label}`}
                  aria-label={`${item.name} · ${label}`}
                >
                  <span class="oh-user-attachment-thumbnail-fallback" aria-hidden>
                    <MediaKindIcon kind="image" size={26} />
                  </span>
                  <img
                    src={url}
                    alt=""
                    loading="lazy"
                    decoding="async"
                    draggable={false}
                    onError={(event) => {
                      event.currentTarget.hidden = true;
                    }}
                  />
                </button>
              );
            }
            const content = (
              <>
                <span class="oh-user-attachment-leading" aria-hidden>
                  <MediaKindIcon kind={item.kind} size={15} />
                </span>
                <span class="oh-user-attachment-name truncate">{item.name}</span>
                <span class="oh-user-attachment-kind truncate">{label}</span>
              </>
            );
            return (
              <button
                key={key}
                type="button"
                onClick={(event) => {
                  event.stopPropagation();
                  openPreview(item, url);
                }}
                class="oh-user-attachment-pill oh-tap-press"
                title={`${item.name} · ${label}`}
              >
                {content}
              </button>
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

  return (
    <>
    <div class="mt-3 flex flex-col gap-2">
      {effectiveEntries.map(({ item, url, key }) => {
        if (item.kind === 'image') {
          return (
            <button
              key={key}
              type="button"
              onClick={(ev) => { ev.stopPropagation(); openPreview(item, url); }}
              class="oh-media-card oh-media-result-card oh-media-image-card block rounded-md overflow-hidden oh-tap-press text-left"
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
                class="text-xs px-2 py-1 truncate oh-text-muted"
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
              data-message-media-interactive="true"
              onPointerDown={(ev) => { ev.stopPropagation(); }}
              onClick={(ev) => { ev.stopPropagation(); }}
              class="oh-media-card oh-media-result-card rounded-md overflow-hidden"
              style={{
                border: '1px solid var(--m3-outline)',
                background: 'black',
                maxWidth: '560px',
              }}
            >
              <video
                src={url}
                controls
                preload="none"
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
                  onClick={(ev) => { ev.stopPropagation(); openPreview(item, url); }}
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
            <MessageAudioResultCard
              key={key}
              item={item}
              url={url}
              onPreview={() => openPreview(item, url)}
              />
          );
        }
        // 通用文件 pill
        return (
          <button
            key={key}
            type="button"
            onClick={(ev) => { ev.stopPropagation(); openPreview(item, url); }}
            class="oh-media-card oh-media-result-card text-xs inline-flex items-center gap-2 px-3 py-1.5 rounded-md oh-tap-press"
            style={{
              border: '1px solid var(--m3-outline)',
              color: 'var(--m3-on-surface)',
              background: 'var(--m3-surface)',
              maxWidth: '480px',
            }}
            title={item.path}
          >
            <MediaKindIcon kind="file" size={15} />
            <span class="truncate">{item.name}</span>
            {item.hintLabel ? (
              <span
                class="ml-auto text-[10px] oh-text-muted"
              >
                {t('detail.media.kind.' + item.hintLabel, item.hintLabel)}
              </span>
            ) : null}
          </button>
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
