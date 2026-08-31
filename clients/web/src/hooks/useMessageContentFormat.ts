// 消息内容格式 hook (与 APP 端 AiMessageContentFormat 对齐)。
//
// 因为 web 端没有完整的 SettingsController, 暂用 localStorage 维护用户偏好,
// 由 SettingsPage 修改。其他订阅者 (MessageCard 等) 通过共享快照响应变更，
// 其他标签页的修改通过「storage」事件同步。
import { useEffect, useState } from 'preact/hooks';
import { readBrowserStorage, writeBrowserStorage } from '../shared/util/browser_storage';
import {
  STORAGE_KEY_HTML_RENDER_FALLBACK,
  STORAGE_KEY_MESSAGE_CONTENT_FORMAT,
} from '../shared/util/storage_keys';

export type MessageContentFormat = 'markdown' | 'plain_text' | 'html';
type HtmlRenderFallback = 'markdown' | 'plain_text';

const FORMATS: ReadonlySet<MessageContentFormat> = new Set<MessageContentFormat>([
  'markdown',
  'plain_text',
  'html',
]);
const FALLBACKS: ReadonlySet<HtmlRenderFallback> = new Set<HtmlRenderFallback>([
  'markdown',
  'plain_text',
]);

function readFormat(): MessageContentFormat {
  const v = readBrowserStorage(STORAGE_KEY_MESSAGE_CONTENT_FORMAT);
  if (v && FORMATS.has(v as MessageContentFormat)) return v as MessageContentFormat;
  return 'markdown';
}

function readFallback(): HtmlRenderFallback {
  const v = readBrowserStorage(STORAGE_KEY_HTML_RENDER_FALLBACK);
  if (v && FALLBACKS.has(v as HtmlRenderFallback)) return v as HtmlRenderFallback;
  return 'markdown';
}

interface MessageContentFormatSnapshot {
  format: MessageContentFormat;
  htmlFallback: HtmlRenderFallback;
}

// 进程级快照 + 单一 window 监听。虚拟列表窗口里每张消息卡片都会调用这个
// hook：逐卡片注册两个 window 监听、各同步读两次 localStorage，在长会话里
// 是纯浪费。改为共享快照后，挂载只剩一次 Set 插入，设置项变更时也只重读一次。
let formatSnapshot: MessageContentFormatSnapshot | null = null;
const formatListeners = new Set<(value: MessageContentFormatSnapshot) => void>();
let formatStorageBound = false;

function currentFormatSnapshot(): MessageContentFormatSnapshot {
  formatSnapshot ??= { format: readFormat(), htmlFallback: readFallback() };
  return formatSnapshot;
}

function refreshFormatSnapshot(): void {
  const current = currentFormatSnapshot();
  const next: MessageContentFormatSnapshot = {
    format: readFormat(),
    htmlFallback: readFallback(),
  };
  if (current.format === next.format && current.htmlFallback === next.htmlFallback) return;
  formatSnapshot = next;
  for (const listener of formatListeners) listener(next);
}

function handleFormatStorageChange(event: StorageEvent): void {
  if (
    event.key != null
    && event.key !== STORAGE_KEY_MESSAGE_CONTENT_FORMAT
    && event.key !== STORAGE_KEY_HTML_RENDER_FALLBACK
  ) return;
  refreshFormatSnapshot();
}

function bindFormatStorageListener(): void {
  if (formatStorageBound || typeof window === 'undefined') return;
  formatStorageBound = true;
  window.addEventListener('storage', handleFormatStorageChange);
}

function unbindFormatStorageListenerIfIdle(): void {
  if (
    !formatStorageBound
    || formatListeners.size > 0
    || typeof window === 'undefined'
  ) return;
  window.removeEventListener('storage', handleFormatStorageChange);
  formatStorageBound = false;
}

export function setMessageContentFormat(value: MessageContentFormat): void {
  writeBrowserStorage(STORAGE_KEY_MESSAGE_CONTENT_FORMAT, value);
  refreshFormatSnapshot();
}

export function setHtmlRenderFallback(value: HtmlRenderFallback): void {
  writeBrowserStorage(STORAGE_KEY_HTML_RENDER_FALLBACK, value);
  refreshFormatSnapshot();
}

export function useMessageContentFormat(): MessageContentFormatSnapshot {
  const [snapshot, setSnapshot] = useState<MessageContentFormatSnapshot>(currentFormatSnapshot);
  useEffect(() => {
    formatListeners.add(setSnapshot);
    bindFormatStorageListener();
    setSnapshot(currentFormatSnapshot());
    return () => {
      formatListeners.delete(setSnapshot);
      unbindFormatStorageListenerIfIdle();
    };
  }, []);
  return snapshot;
}
