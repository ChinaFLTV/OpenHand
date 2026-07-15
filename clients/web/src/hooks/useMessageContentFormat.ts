// 消息内容格式 hook (与 APP 端 AiMessageContentFormat 对齐)。
//
// 因为 web 端没有完整的 SettingsController, 暂用 localStorage 维护用户偏好,
// 由 SettingsPage 修改。其他订阅者 (MessageCard 等) 通过 hook 读取并响应
// 「storage」事件 / 自定义事件刷新。
import { useEffect, useState } from 'preact/hooks';
import { readBrowserStorage, writeBrowserStorage } from '../shared/util/browser_storage';

export type MessageContentFormat = 'markdown' | 'plain_text' | 'html';
type HtmlRenderFallback = 'markdown' | 'plain_text';

const FORMAT_KEY = 'openhand_message_content_format';
const FALLBACK_KEY = 'openhand_html_render_fallback';
const EVENT_NAME = 'openhand:message-content-format-changed';

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
  const v = readBrowserStorage(FORMAT_KEY);
  if (v && FORMATS.has(v as MessageContentFormat)) return v as MessageContentFormat;
  return 'markdown';
}

function readFallback(): HtmlRenderFallback {
  const v = readBrowserStorage(FALLBACK_KEY);
  if (v && FALLBACKS.has(v as HtmlRenderFallback)) return v as HtmlRenderFallback;
  return 'markdown';
}

export function setMessageContentFormat(value: MessageContentFormat): void {
  writeBrowserStorage(FORMAT_KEY, value);
  window.dispatchEvent(new CustomEvent(EVENT_NAME));
}

export function setHtmlRenderFallback(value: HtmlRenderFallback): void {
  writeBrowserStorage(FALLBACK_KEY, value);
  window.dispatchEvent(new CustomEvent(EVENT_NAME));
}

export function useMessageContentFormat(): {
  format: MessageContentFormat;
  htmlFallback: HtmlRenderFallback;
} {
  const [format, setFormat] = useState<MessageContentFormat>(readFormat);
  const [htmlFallback, setFallback] = useState<HtmlRenderFallback>(readFallback);
  useEffect(() => {
    const refresh = () => {
      setFormat(readFormat());
      setFallback(readFallback());
    };
    window.addEventListener(EVENT_NAME, refresh);
    window.addEventListener('storage', refresh);
    return () => {
      window.removeEventListener(EVENT_NAME, refresh);
      window.removeEventListener('storage', refresh);
    };
  }, []);
  return { format, htmlFallback };
}
