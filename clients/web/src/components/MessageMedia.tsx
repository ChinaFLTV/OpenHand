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
import { copyBlobToClipboard, copyTextToClipboard } from '../utils/clipboard';
import { saveBlobWithPicker, type SaveBlobPickerType } from '../utils/save_blob';
import { buildSessionAssetUrl } from '../utils/session_asset';
import { createTimedAbortController } from '../utils/timed_abort';
import {
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  createDialogOverlayStyle,
} from './DialogFrame';
import { showSnackbar } from './Snackbar';

export type MediaKind = 'image' | 'video' | 'audio' | 'file';

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
const PREVIEW_VIEWPORT_GAP = 16;
const PREVIEW_CONTENT_PADDING = 12;
const PREVIEW_HEADER_ESTIMATE = 66;
const PREVIEW_MIN_PANEL_WIDTH = 360;
const PREVIEW_FALLBACK_IMAGE_SIDE = 320;
const PREVIEW_FALLBACK_VIDEO_RATIO = 16 / 9;
const MARKDOWN_MEDIA_REF = /(!?)\[([^\]\n]{0,240})\]\(([^)\r\n]+)\)/g;
const HTML_MEDIA_SRC = /<(?:img|video|audio|source)\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi;
const INLINE_MEDIA_DIR = /(^|[\\/])openhand_media([\\/]|$)/i;

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

function clampNumber(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
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

function basename(path: string): string {
  const i = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i >= 0 ? path.slice(i + 1) : path;
}

function firstNonEmptyString(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value.trim();
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
  // Skip remote URLs and data URIs — markdown layer renders them inline.
  // Remote images get click-to-preview via the Markdown component instead.
  if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
    return;
  }
  const name = displayName?.trim() || basename(path);
  out.push({
    path,
    name,
    kind: mediaKindFromPath(`${path} ${name}`, hintKind),
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
      // 使用 URL hash 的前 16 字符作为稳定标识, 避免每次渲染生成不同名称。
      let hash = 0;
      for (let i = 0; i < rawPath.length; i++) {
        hash = ((hash << 5) - hash + rawPath.charCodeAt(i)) | 0;
      }
      name = `${kind}_${(hash >>> 0).toString(36)}${ext}`;
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
  const res = await fetch(url, { credentials: 'same-origin', signal });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const blob = await res.blob();
  await saveBlobWithPicker(blob, item.name, pickerTypesForMedia(item));
}

async function fetchMediaBlob(url: string, signal?: AbortSignal): Promise<Blob> {
  const res = await fetch(url, { credentials: 'same-origin', signal });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  return res.blob();
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

function MediaKindIcon({ kind, size = 16 }: { kind: MediaKind; size?: number }) {
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
  switch (kind) {
    case 'image':
      return <svg {...common}><rect x="4" y="5" width="16" height="14" rx="2.5" /><path d="m7 16 4-4 3 3 2-2 3 3" /><circle cx="9" cy="9" r="1.2" /></svg>;
    case 'video':
      return <svg {...common}><rect x="4" y="7" width="12" height="10" rx="2" /><path d="m16 11 4-2.5v7L16 13" /></svg>;
    case 'audio':
      return <svg {...common}><path d="M9 18V6l10-2v12" /><circle cx="7" cy="18" r="2" /><circle cx="17" cy="16" r="2" /></svg>;
    default:
      return <svg {...common}><path d="M7 3h7l3 3v15H7z" /><path d="M14 3v4h4" /><path d="M9.5 12h5M9.5 16h4" /></svg>;
  }
}

function attachmentLabel(item: MediaItem): string {
  return `${t('message.context.kind.attachment', '附件')} · ${mediaKindLabel(item.kind)}`;
}

export interface MessageMediaProps {
  message: SessionMessage;
  sessionId: string;
  presentation?: 'auto' | 'preview' | 'attachmentList';
}

export interface MediaPreviewDialogProps {
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
      if (timed.controller.signal.aborted || (error instanceof DOMException && error.name === 'AbortError')) return;
      showSnackbar(
        `${t('detail.media.saveFailed', '保存失败')}：${error instanceof Error ? error.message : String(error)}`,
        { tone: 'error' },
      );
    } finally {
      timed.clear();
      if (saveAbortRef.current === timed.controller) {
        saveAbortRef.current = null;
        if (!timed.controller.signal.aborted) setSaving(false);
      }
    }
  };
  const handleCopy = async () => {
    if (copying) return;
    copyAbortRef.current?.abort();
    const timed = createTimedAbortController(MEDIA_CLIPBOARD_FETCH_TIMEOUT_MS);
    copyAbortRef.current = timed.controller;
    setCopying(true);
    let richCopied = false;
    try {
      const blob = await fetchMediaBlob(url, timed.controller.signal);
      if (!timed.controller.signal.aborted) {
        richCopied = await copyBlobToClipboard(blob);
      }
    } catch {
      richCopied = false;
    } finally {
      timed.clear();
    }
    if (timed.controller.signal.aborted) {
      if (copyAbortRef.current === timed.controller) copyAbortRef.current = null;
      setCopying(false);
      return;
    }
    if (richCopied) {
      showSnackbar(t('detail.media.copyOk', '已复制到剪贴板'), { tone: 'success' });
      if (copyAbortRef.current === timed.controller) copyAbortRef.current = null;
      setCopying(false);
      return;
    }
    const sourceText = item.path.trim() || url;
    const textCopied = await copyTextToClipboard(sourceText);
    showSnackbar(
      textCopied
        ? item.kind === 'file'
          ? t('detail.media.copyPathOk', '浏览器不支持直接复制该文件，已复制文件路径')
          : t('detail.media.copySourceOk', '已复制媒体来源')
        : t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'),
      { tone: textCopied ? 'success' : 'error' },
    );
    if (copyAbortRef.current === timed.controller) copyAbortRef.current = null;
    setCopying(false);
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
      overlayClassName="fixed inset-0 flex items-center justify-center p-4"
      overlayStyle={createDialogOverlayStyle({
        background: 'color-mix(in srgb, black 58%, transparent)',
        blurPx: 10,
        zIndex: DIALOG_OVERLAY_TOP_Z_INDEX,
      })}
      panelClassName="rounded-m3-lg overflow-hidden"
      panelStyle={{
        width: `${layout.panelWidth}px`,
        maxWidth: `${layout.maxPanelWidth}px`,
        background: 'var(--m3-surface-container)',
        color: 'var(--m3-on-surface)',
        boxShadow: 'var(--m3-elev-4)',
        border: '1px solid var(--m3-outline)',
        maxHeight: `${layout.maxPanelHeight}px`,
        display: 'flex',
        flexDirection: 'column',
        transition: panelTransition,
      }}
      ariaLabel={item.name}
    >
      <header ref={headerRef} class="flex items-center gap-3 px-4 py-3" style={{ borderBottom: '1px solid var(--m3-outline-variant)' }}>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold truncate">{item.name}</p>
            <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
            <img
              src={url}
              alt={item.name}
              decoding="async"
              onLoad={(event) => {
                const img = event.currentTarget;
                rememberNaturalSize(img.naturalWidth, img.naturalHeight);
              }}
              style={{ ...mediaBoxStyle, objectFit: 'contain' }}
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
                  <p class="mt-1 text-xs break-all" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
  const items = useMemo(() => collectMedia(message), [message]);
  const entries = useMemo<MediaEntry[]>(() => items.map((item, idx) => ({
    item,
    // 网络 URL 直接使用, 本地路径走 session asset 代理。
    url: item.isDirectUrl ? item.path : buildSessionAssetUrl(sessionId, item.path),
    key: `${item.path}:${idx}`,
  })), [items, sessionId]);
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
          {entries.map(({ item, url, key }) => {
            const label = attachmentLabel(item);
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
                onClick={() => openPreview(item, url)}
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
      {entries.map(({ item, url, key }) => {
        if (item.kind === 'image') {
          return (
            <button
              key={key}
              type="button"
              onClick={(ev) => { ev.stopPropagation(); openPreview(item, url); }}
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
                  onClick={(ev) => { ev.stopPropagation(); openPreview(item, url); }}
                  class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm"
                  style={{ color: 'var(--m3-primary)', border: '1px solid var(--m3-outline-variant)' }}
                >
                  {t('detail.media.preview', '预览')}
                </button>
              </div>
              <audio
                src={url}
                controls
                preload="none"
                style={{ width: '100%' }}
              />
            </div>
          );
        }
        // 通用文件 pill
        return (
          <button
            key={key}
            type="button"
            onClick={(ev) => { ev.stopPropagation(); openPreview(item, url); }}
            class="oh-media-card text-xs inline-flex items-center gap-2 px-3 py-1.5 rounded-md oh-tap-press"
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
                class="ml-auto text-[10px]"
                style={{ color: 'var(--m3-on-surface-variant)' }}
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
