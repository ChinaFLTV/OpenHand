import { DecisionCard, DecisionRequestCard } from './DecisionCard';
import { DECISION_REQUEST, DECISION_RESULT, containsDecisionFence, decisionFenceLanguageLabel } from '../shared/util/decision';
// Markdown 渲染组件：按需加载插件，限制长内容解析，并为批量挂载分帧调度。

import { memo } from 'preact/compat';
import { MediaPreviewDialog } from './MessageMedia';
import { collectImageGallery, type ImageGalleryEntry } from './image_gallery';
import { richContentFrameScheduler } from '../shared/ui/rich_content_frame_scheduler';
import { BoundedTextCache } from '../shared/util/bounded_text_cache';
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { boundedFnv1aHashBase36 } from '../shared/util/hash';
import { ignoreError } from '../shared/util/errors';
import { normalizeMarkdownDestination } from '../shared/util/markdown';
import { truncateEndText } from '../shared/util/text';
import {
  isTranscriptScrollActive,
  scheduleAfterTranscriptScrollSettles,
} from '../shared/ui/transcript_scroll_activity';
import { showSnackbar } from './Snackbar';
import { MermaidView } from './MermaidView';
import { t } from '../i18n';
import {
  downloadBlobWithAnchor,
  revokeObjectUrlQuietly,
  scheduleObjectUrlRevoke,
} from '../utils/save_blob';
import { copyTextToClipboard } from '../utils/clipboard';
import { useTransientFlag } from '../hooks/useTransientFlag';
import { useTimeoutController } from '../hooks/useTimeoutController';
import { svgIconProps } from '../shared/ui/svg_icon';
import 'katex/dist/katex.min.css';

type RehypeHighlightPlugin = unknown;
type MarkdownPlugin = unknown;
type DomPurifyLike = {
  sanitize: (source: string, options?: Record<string, unknown>) => string;
};

interface LazyPluginState<T> {
  value: T | null;
  loading: Promise<T> | null;
}

function loadLazyPlugin<T>(
  state: LazyPluginState<T>,
  importer: () => Promise<unknown>,
): Promise<T> {
  if (state.value != null) return Promise.resolve(state.value);
  if (state.loading != null) return state.loading;
  state.loading = importer()
    .then((module) => (module as { default?: T }).default ?? (module as T))
    .then(
      (plugin) => {
        state.value = plugin;
        state.loading = null;
        return plugin;
      },
      (error: unknown) => {
        state.loading = null;
        throw error;
      },
    );
  return state.loading;
}

const rehypeHighlightState: LazyPluginState<RehypeHighlightPlugin> = {
  value: null,
  loading: null,
};
const remarkMathState: LazyPluginState<MarkdownPlugin> = {
  value: null,
  loading: null,
};
const rehypeKatexState: LazyPluginState<MarkdownPlugin> = {
  value: null,
  loading: null,
};
const domPurifyState: LazyPluginState<DomPurifyLike> = {
  value: null,
  loading: null,
};

function loadRehypeHighlight(): Promise<RehypeHighlightPlugin> {
  return loadLazyPlugin(rehypeHighlightState, () => import('rehype-highlight'));
}

function loadRemarkMath(): Promise<MarkdownPlugin> {
  return loadLazyPlugin(remarkMathState, () => import('remark-math'));
}

function loadRehypeKatex(): Promise<MarkdownPlugin> {
  return loadLazyPlugin(rehypeKatexState, () => import('rehype-katex'));
}

const CONTENT_TOO_BIG_CHARS = 120 * 1024;
const OVERSIZED_MARKDOWN_PREVIEW_MAX_CHARS = 12 * 1024;
/// 超过该阈值的 Markdown 首次挂载走分帧解析；历史卡片无论长短都走延迟路径。
const MARKDOWN_DEFERRED_PARSE_THRESHOLD = 8 * 1024;
const HTML_SNIFF_SCAN_CHARS = 8 * 1024;
const MARKDOWN_PENDING_PREVIEW_MAX_CHARS = 1200;
// 小增量流式更新合并到固定间隔，避免重复解析整棵 Markdown 树。
const MARKDOWN_STREAM_FLUSH_MS = 80;
const MARKDOWN_STREAM_FLUSH_DELTA = 64;
// 无围栏代码块时跳过高亮插件。
const FENCED_CODE_RE = /(^|\n)[ \t]*```/;
const MATH_DELIMITER_RE = /\\\(|\\\[|\$\$/;
const FENCED_CODE_LINE_RE = /^[ \t]{0,3}(`{3,}|~{3,})/;
const LOCAL_MEDIA_EXT = /\.(?:png|jpe?g|gif|webp|bmp|heic|svg|mp4|webm|mov|m4v|mp3|wav|ogg|m4a|flac|aac)(?:[?#].*)?$/i;
const MARKDOWN_MEDIA_REF = /!?\[[^\]\n]{0,240}\]\(([^)\r\n]+)\)/g;
const INLINE_DIFF_PREVIEW_LINE_LIMIT = 28;
const INLINE_DIFF_HUNK_HEADER_RE = /^@@\s+-(\d+)(?:,(\d+))?(?:\s+\+(\d+)(?:,(\d+))?)?/;

const HTML_SANITIZE_CACHE_LIMIT = 256;
const HTML_SANITIZE_CACHE_MAX_CHARS = 2 * 1024 * 1024;
const HTML_RENDER_PROFILE_CACHE_LIMIT = 256;
// 延迟挂载的 HTML 保持在视口附近，避免打开长会话时同时净化并渲染大量离屏卡片。
const HTML_DEFERRED_RENDER_ROOT_MARGIN = '120px 0px';
const HTML_PLACEHOLDER_MIN_HEIGHT_PX = 96;
const HTML_PLACEHOLDER_MAX_HEIGHT_PX = 520;
const HTML_PLACEHOLDER_CHARS_PER_LINE = 90;
const HTML_PLACEHOLDER_LINE_HEIGHT_PX = 24;
const HTML_COMPLEX_SOURCE_MIN_CHARS = 4 * 1024;
const HTML_COMPLEX_TAG_COUNT = 48;
const HTML_COMPLEX_RENDER_COST = 12;
const HTML_COMPLEX_PREVIEW_MAX_CHARS = 1400;
const HTML_COMPLEX_PREVIEW_SCAN_CHARS = 12 * 1024;
const HTML_LIKE_DETECT_CACHE_LIMIT = 512;

function contentCacheKey(prefix: string, content: string): string {
  return `${prefix}:${content.length}:${boundedFnv1aHashBase36(content)}`;
}

function rememberLru<K, V>(cache: Map<K, V>, key: K, value: V, limit: number): void {
  if (cache.has(key)) cache.delete(key);
  cache.set(key, value);
  while (cache.size > limit) {
    const first = cache.keys().next().value;
    if (first == null) break;
    cache.delete(first);
  }
}

const htmlSanitizeCache = new BoundedTextCache(HTML_SANITIZE_CACHE_LIMIT, HTML_SANITIZE_CACHE_MAX_CHARS);
const htmlRenderProfileCache = new Map<string, HtmlRenderProfile>();
const htmlLikeDetectCache = new Map<string, boolean>();

function isLocalMediaReference(raw: unknown): boolean {
  if (typeof raw !== 'string') return false;
  const value = normalizeMarkdownDestination(raw);
  if (!value || /^(?:https?:|data:|blob:|\/api\/sessions\/)/i.test(value)) return false;
  return value.includes('openhand_media') || LOCAL_MEDIA_EXT.test(value);
}

function stripLocalMediaReferences(source: string): string {
  return source
    .replace(MARKDOWN_MEDIA_REF, (match: string, destination: string) => (
      isLocalMediaReference(destination) ? '' : match
    ))
    .replace(/\n{3,}/g, '\n\n');
}

function replaceInlineLatexDelimiters(line: string): string {
  let result = '';
  let index = 0;
  while (index < line.length) {
    if (line.charCodeAt(index) === 0x60) {
      const start = index;
      while (index < line.length && line.charCodeAt(index) === 0x60) index += 1;
      const tickRun = line.slice(start, index);
      const end = line.indexOf(tickRun, index);
      if (end < 0) {
        result += line.slice(start);
        break;
      }
      result += line.slice(start, end + tickRun.length);
      index = end + tickRun.length;
      continue;
    }
    if (line.startsWith('\\(', index)) {
      const end = line.indexOf('\\)', index + 2);
      if (end > index + 2) {
        const tex = line.slice(index + 2, end);
        if (tex.trim()) {
          result += `$${tex}$`;
          index = end + 2;
          continue;
        }
      }
    }
    result += line[index];
    index += 1;
  }
  return result;
}

function normalizeMarkdownMathDelimiters(source: string): string {
  if (!MATH_DELIMITER_RE.test(source)) return source;
  const lines = source.split('\n');
  const out: string[] = [];
  let fence: string | null = null;
  let pendingDisplay: {
    indent: string;
    rawLines: string[];
    bodyLines: string[];
  } | null = null;

  const flushPendingRaw = () => {
    if (pendingDisplay == null) return;
    out.push(...pendingDisplay.rawLines);
    pendingDisplay = null;
  };

  const flushPendingDisplay = (trailing: string) => {
    if (pendingDisplay == null) return;
    out.push(`${pendingDisplay.indent}$$`);
    out.push(...pendingDisplay.bodyLines);
    out.push(`${pendingDisplay.indent}$$`);
    pendingDisplay = null;
    if (trailing.trim()) {
      out.push(replaceInlineLatexDelimiters(trailing.trimStart()));
    }
  };

  for (const line of lines) {
    const fenceMatch = FENCED_CODE_LINE_RE.exec(line);
    if (fenceMatch != null) {
      if (fence == null) {
        flushPendingRaw();
        fence = fenceMatch[1][0];
      } else if (fenceMatch[1][0] === fence) {
        fence = null;
      }
      out.push(line);
      continue;
    }
    if (fence != null) {
      out.push(line);
      continue;
    }

    if (pendingDisplay != null) {
      pendingDisplay.rawLines.push(line);
      const end = line.indexOf('\\]');
      if (end >= 0) {
        const before = line.slice(0, end).trimEnd();
        if (before) pendingDisplay.bodyLines.push(before);
        flushPendingDisplay(line.slice(end + 2));
      } else {
        pendingDisplay.bodyLines.push(line);
      }
      continue;
    }

    const start = /^(\s*)\\\[\s*(.*)$/.exec(line);
    if (start != null) {
      const [, indent, rest] = start;
      const end = rest.indexOf('\\]');
      pendingDisplay = {
        indent,
        rawLines: [line],
        bodyLines: [],
      };
      if (end >= 0) {
        const tex = rest.slice(0, end).trim();
        if (tex) pendingDisplay.bodyLines.push(tex);
        flushPendingDisplay(rest.slice(end + 2));
      } else if (rest.trim()) {
        pendingDisplay.bodyLines.push(rest);
      }
      continue;
    }

    out.push(replaceInlineLatexDelimiters(line));
  }

  flushPendingRaw();
  return out.join('\n');
}

interface MarkdownProps {
  /// 原始 Markdown 文本.
  source: string;
  /// 是否禁用 markdown 解析 (例如 user 消息或工具输出原文需 mono 显示).
  raw?: boolean;
  /// 强制 mono 字体 (工具调用入参 / stdout 等).
  mono?: boolean;
  /// 内容格式 (与 APP 端 AiMessageContentFormat 对齐)：
  /// - 'markdown' (默认) → 原有 react-markdown 渲染路径
  /// - 'plain_text'      → 直接 pre 渲染原文 (跳过 markdown / 高亮)
  /// - 'html'            → 内容像 HTML 时 DOMPurify sanitize 后 innerHTML 渲染；
  ///                       不像 HTML 时按 htmlFallback 回退到 markdown 或 plain_text。
  format?: 'markdown' | 'plain_text' | 'html';
  /// HTML 模式下，内容不像 HTML 时的回退渲染。
  htmlFallback?: 'markdown' | 'plain_text';
  /// 父级消息正在流式追加内容。流式阶段保持渲染树稳定，避免占位态
  /// 与 Markdown 树来回切换造成卡片闪烁。
  streaming?: boolean;
  /// 历史消息重新进入虚拟窗口时，避免缓存命中绕过帧调度。
  deferInitialRender?: boolean;
}

const HTML_LIKELY_TAG_RE = /<\s*(?:!doctype|html|body|div|span|p|h[1-6]|ul|ol|li|table|thead|tbody|tfoot|tr|td|th|caption|col|colgroup|a|img|br|hr|pre|code|strong|em|b|i|u|s|del|ins|mark|small|sub|sup|abbr|cite|q|blockquote|section|article|header|footer|nav|main|aside|button|form|input|textarea|select|option|label|fieldset|legend|details|summary|figure|figcaption|time|progress|meter|style|script|link|meta|iframe|video|audio|canvas|svg|path|rect|circle|ellipse|line|polyline|polygon|text|g|defs|use|symbol)\b/i;

/// 宽松的 HTML 标签结构检测：识别任意 `<标签名>` 或 `</标签名>` 形式，
/// 用于捕获白名单外的有效 HTML 标签（如 `<del>`、`<kbd>`、`<dfn>` 等）。
/// 配合 `looksLikeHtml` 使用，避免 AI 输出的非常见标签被误判为纯文本。
const HTML_ANY_TAG_RE = /<\s*\/?[a-zA-Z][a-zA-Z0-9-]*\b[^>]*>/;

/// 剥掉内容中的围栏代码块（```...```），避免代码块内的 <br/>、<div>
/// 等标签被误判为 HTML 导致整条 Markdown 消息进入 HtmlBody 渲染路径。
function stripFencedCodeBlocks(value: string): string {
  if (!value.includes('```')) return value;
  // 匹配 ```language\n...content...\n``` 形式的围栏代码块。
  return value.replace(/(^|\n)```[^\n]*\n[\s\S]*?\n```/g, '');
}

/// 单次剥离围栏代码块后同时跑白名单与宽松结构检测，并按内容缓存判定结果。
/// 该判定在 Markdown / MessageCard 的多个渲染路径上被重复调用，未缓存时
/// 每次渲染都要为整条消息做一次全串复制 + 两轮正则扫描——长会话滚动时
/// 这是纯浪费。缓存后重复渲染只剩一次 FNV 哈希。
function looksLikeRenderableHtml(value: string): boolean {
  if (!value || !value.includes('<')) return false;
  const key = contentCacheKey('htmlish', value);
  const cached = htmlLikeDetectCache.get(key);
  if (cached != null) return cached;
  const sniffSource = value.length > HTML_SNIFF_SCAN_CHARS
    ? value.slice(0, HTML_SNIFF_SCAN_CHARS)
    : value;
  const stripped = stripFencedCodeBlocks(sniffSource);
  const result = HTML_LIKELY_TAG_RE.test(stripped) || HTML_ANY_TAG_RE.test(stripped);
  rememberLru(htmlLikeDetectCache, key, result, HTML_LIKE_DETECT_CACHE_LIMIT);
  return result;
}

export { looksLikeRenderableHtml };

interface HtmlRenderProfile {
  renderCost: number;
  complex: boolean;
  previewText: string;
}

const HTML_PROFILE_TAG_RE = /<\s*\/?\s*([a-zA-Z][a-zA-Z0-9:-]*)\b([^>]*)>/g;
const HTML_PREVIEW_BLOCK_BREAK_RE = /<\s*\/(?:p|div|section|article|header|footer|main|aside|nav|h[1-6]|li|tr|table|ul|ol|blockquote|pre)\s*>/gi;
const HTML_PREVIEW_DROP_RE = /<\s*(script|style|svg|canvas|iframe)\b[\s\S]*?<\s*\/\s*\1\s*>/gi;
const HTML_PREVIEW_TAG_RE = /<[^>]+>/g;
const HTML_PREVIEW_BR_RE = /<\s*br\s*\/?>/gi;

function decodeBasicHtmlEntities(value: string): string {
  return value.replace(/&(?:nbsp|amp|lt|gt|quot|apos|#(\d+)|#x([0-9a-fA-F]+));/g, (match, dec: string | undefined, hex: string | undefined) => {
    if (dec != null) {
      const code = Number.parseInt(dec, 10);
      return Number.isFinite(code) && code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : match;
    }
    if (hex != null) {
      const code = Number.parseInt(hex, 16);
      return Number.isFinite(code) && code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : match;
    }
    switch (match) {
      case '&nbsp;': return ' ';
      case '&amp;': return '&';
      case '&lt;': return '<';
      case '&gt;': return '>';
      case '&quot;': return '"';
      case '&apos;': return "'";
      default: return match;
    }
  });
}

function extractHtmlPreviewText(source: string): string {
  const previewSource = source.length > HTML_COMPLEX_PREVIEW_SCAN_CHARS
    ? source.slice(0, HTML_COMPLEX_PREVIEW_SCAN_CHARS)
    : source;
  const preview = decodeBasicHtmlEntities(previewSource)
    .replace(HTML_PREVIEW_DROP_RE, ' ')
    .replace(HTML_PREVIEW_BR_RE, '\n')
    .replace(HTML_PREVIEW_BLOCK_BREAK_RE, '\n')
    .replace(HTML_PREVIEW_TAG_RE, ' ')
    .replace(/[ \t\f\v\r]+/g, ' ')
    .replace(/\n[ \t]+/g, '\n')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  const text = preview || previewSource.replace(HTML_PREVIEW_TAG_RE, ' ').replace(/\s+/g, ' ').trim();
  if (text.length <= HTML_COMPLEX_PREVIEW_MAX_CHARS) return text;
  return truncateEndText(text, HTML_COMPLEX_PREVIEW_MAX_CHARS, {
    ellipsis: '...',
    trimEnd: true,
  });
}

function htmlRenderProfile(source: string): HtmlRenderProfile {
  const key = contentCacheKey('html-profile', source);
  const cached = htmlRenderProfileCache.get(key);
  if (cached != null) {
    rememberLru(htmlRenderProfileCache, key, cached, HTML_RENDER_PROFILE_CACHE_LIMIT);
    return cached;
  }

  const scanSource = source.length > 160 * 1024 ? source.slice(0, 160 * 1024) : source;
  let tagCount = 0;
  let layoutTagCount = 0;
  let mediaTagCount = 0;
  let interactiveTagCount = 0;
  let styleAttrCount = 0;
  let expensiveTagCount = 0;
  HTML_PROFILE_TAG_RE.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = HTML_PROFILE_TAG_RE.exec(scanSource)) != null) {
    tagCount += 1;
    const name = (match[1] ?? '').toLowerCase();
    const attrs = match[2] ?? '';
    if (/^(?:div|section|article|header|footer|main|aside|nav|ul|ol|li|table|thead|tbody|tfoot|tr|td|th|form)$/.test(name)) {
      layoutTagCount += 1;
    }
    if (/^(?:img|video|audio|picture|source|iframe|canvas|svg)$/.test(name)) {
      mediaTagCount += 1;
    }
    if (/^(?:button|input|textarea|select|option|label|details|summary|a)$/.test(name)) {
      interactiveTagCount += 1;
    }
    if (/^(?:script|style|link|meta|iframe|canvas|svg)$/.test(name)) {
      expensiveTagCount += 1;
    }
    if (/\sstyle\s*=/i.test(attrs)) {
      styleAttrCount += 1;
    }
    if (tagCount >= 1800) break;
  }

  const renderCost = Math.min(
    72,
    3 +
      Math.ceil(source.length / 5500) +
      Math.ceil(tagCount / 22) +
      Math.ceil(layoutTagCount / 20) +
      Math.ceil(styleAttrCount / 16) +
      mediaTagCount * 2 +
      interactiveTagCount +
      expensiveTagCount * 3,
  );
  const complex =
    (source.length >= HTML_COMPLEX_SOURCE_MIN_CHARS && renderCost >= 12) ||
    tagCount >= HTML_COMPLEX_TAG_COUNT ||
    renderCost >= HTML_COMPLEX_RENDER_COST ||
    mediaTagCount >= 5 ||
    expensiveTagCount >= 3;
  const profile = {
    renderCost,
    complex,
    previewText: complex ? extractHtmlPreviewText(source) : '',
  };
  rememberLru(htmlRenderProfileCache, key, profile, HTML_RENDER_PROFILE_CACHE_LIMIT);
  return profile;
}

/// 将一段 HTML 源码以 Blob URL 形式在新标签页打开。与 APP 端
/// `_HtmlPreviewDialog` 的 "在浏览器中打开" 功能对齐：APP 在 OS 默认浏览器
/// 中打开临时文件，Web 端直接借宿主浏览器 new tab 即可。
/// - 自动补 `<!DOCTYPE html>` / charset，避免片段在裸打开时编码异常。
/// - Blob URL 有效期挂在 tab 上，关闭标签自动 revoke；保险起见 60s 后主动
///   revoke 一次，避免短时间内大量预览造成 URL 泄漏。
export function openHtmlInNewTab(html: string): void {
  if (typeof window === 'undefined') return;
  const trimmed = (html ?? '').trim();
  if (!trimmed) return;
  const needsDocWrap = !/^<!doctype/i.test(trimmed) && !/^<html[\s>]/i.test(trimmed);
  const body = needsDocWrap
    ? `<!DOCTYPE html>\n<html><head><meta charset="utf-8"></head><body>${trimmed}</body></html>`
    : trimmed;
  let url = '';
  try {
    const blob = new Blob([body], { type: 'text/html;charset=utf-8' });
    url = URL.createObjectURL(blob);
    const opened = window.open(url, '_blank', 'noopener,noreferrer');
    if (!opened) {
      showSnackbar('浏览器已拦截新标签页，请允许弹窗后重试', { tone: 'error' });
      revokeObjectUrlQuietly(url);
      return;
    }
    showSnackbar('已在新标签页打开预览', { tone: 'success' });
    scheduleObjectUrlRevoke(url, 60_000);
  } catch (_e) {
    revokeObjectUrlQuietly(url);
    showSnackbar('打开浏览器预览失败', { tone: 'error' });
  }
}

/// 流式期间 `looksLikeHtml` 会随内容长大反复在 true/false 之间翻转
/// (例：先到了 "我来回答你..." → markdown 路径，又拼到 "<div>" → HtmlBody 路径，
///  下一帧 markdownContent 又被剥离/换行，再次回弹)。两条渲染路径产物不同
/// (markdown <p> vs HtmlBody <div dangerouslySetInnerHTML>)，整棵子树
/// unmount/mount 一次 → 消息卡片视觉上 "突然显示突然隐藏" 抖一下。
/// 这里改用 sticky hook：一旦某条消息内容判定为 HTML，本组件生命周期内
/// 保持 HTML 渲染，避免流式增量再翻转。新消息 (source 长度回到 0) 重置。
///
/// 优先用白名单（`looksLikeHtml`）识别常见 HTML 标签；如果不在白名单但
/// 内容包含「<标签名>」形式的结构（宽松启发式 `hasHtmlTagStructure`），
/// 也视为 HTML。这能捕获 AI 输出中 `<del>` / `<kbd>` 等白名单外的有效标签，
/// 避免它们被误判为纯文本而显示原生标签字符。
function useStickyLooksLikeHtml(value: string): boolean {
  const stickyRef = useRef(false);
  if (!value) {
    stickyRef.current = false;
    return false;
  }
  if (stickyRef.current) return true;
  if (looksLikeRenderableHtml(value)) {
    stickyRef.current = true;
    return true;
  }
  return false;
}

function loadDomPurify(): Promise<DomPurifyLike> {
  return loadLazyPlugin(domPurifyState, () => import('dompurify'));
}

const HtmlBody = memo(function HtmlBody({ source, mono }: { source: string; mono: boolean }) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [purify, setPurify] = useState<DomPurifyLike | null>(() => domPurifyState.value);
  useEffect(() => {
    if (purify != null) return;
    let cancelled = false;
    let cancelRender: (() => void) | null = null;
    loadDomPurify().then((p) => {
      if (cancelled) return;
      cancelRender = richContentFrameScheduler.schedule(() => setPurify(() => p));
    }).catch(ignoreError);
    return () => {
      cancelled = true;
      cancelRender?.();
    };
  }, [purify]);
  const fontFamily = mono ? 'ui-monospace, SFMono-Regular, Menlo, monospace' : 'inherit';
  const safeHtml = useMemo(() => {
    if (purify == null) return '';
    const cached = htmlSanitizeCache.get(source);
    if (cached != null) {
      return cached;
    }
    const next = purify.sanitize(source, { USE_PROFILES: { html: true } });
    htmlSanitizeCache.set(source, next);
    return next;
  }, [purify, source]);
  useLayoutEffect(() => {
    const element = containerRef.current;
    if (element == null || purify == null) return;
    if (element.innerHTML !== safeHtml) {
      element.innerHTML = safeHtml;
    }
  }, [purify, safeHtml]);
  // HTML 模式必须尽量忠实呈现模型给出的界面结构。布局类声明（flex/grid）
  // 交给浏览器原生排版，外层只负责安全净化和溢出约束。
  if (purify == null) {
    return <MarkdownPendingPreview source={source} />;
  }
  return (
    <div
      ref={containerRef}
      class="oh-html-body text-sm"
      style={{ fontFamily }}
    />
  );
});

function estimateHtmlPlaceholderHeight(source: string): number {
  const lineCount = Math.ceil(Math.max(1, source.length) / HTML_PLACEHOLDER_CHARS_PER_LINE);
  return Math.max(
    HTML_PLACEHOLDER_MIN_HEIGHT_PX,
    Math.min(HTML_PLACEHOLDER_MAX_HEIGHT_PX, lineCount * HTML_PLACEHOLDER_LINE_HEIGHT_PX),
  );
}

function HtmlBodyPlaceholder({ source }: { source: string }) {
  return (
    <div
      class="oh-html-body-placeholder"
      aria-hidden="true"
      style={{ height: `${estimateHtmlPlaceholderHeight(source)}px` }}
    >
      <span />
      <span />
      <span />
      <span />
    </div>
  );
}

/** 离开视口时撤销尚未开始的解析，避免快速滚动把历史卡片排满队列。 */
function useRichContentMount(deferred: boolean) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const [ready, setReady] = useState(() => !deferred);
  useEffect(() => {
    if (ready) return;
    if (!deferred) {
      setReady(true);
      return;
    }
    const element = hostRef.current;
    if (!element) return;
    let cancelRender: (() => void) | null = null;
    const schedule = () => {
      cancelRender ??= richContentFrameScheduler.schedule(() => setReady(true));
    };
    if (typeof IntersectionObserver !== 'function') {
      schedule();
      return () => cancelRender?.();
    }
    const observer = new IntersectionObserver((entries) => {
      const entry = entries[entries.length - 1];
      if (entry?.isIntersecting) {
        schedule();
      } else {
        cancelRender?.();
        cancelRender = null;
      }
    }, { rootMargin: HTML_DEFERRED_RENDER_ROOT_MARGIN, threshold: 0 });
    observer.observe(element);
    return () => {
      observer.disconnect();
      cancelRender?.();
    };
  }, [deferred, ready]);
  return { hostRef, ready: ready || !deferred };
}

const DeferredHtmlBody = memo(function DeferredHtmlBody({
  source,
  mono,
}: {
  source: string;
  mono: boolean;
}) {
  const { hostRef, ready } = useRichContentMount(true);
  return (
    <div ref={hostRef} class="oh-html-body-deferred">
      {ready ? <HtmlBody source={source} mono={mono} /> : <MarkdownPendingPreview source={source} />}
    </div>
  );
});

function HtmlPreviewIcon({ name, size = 14 }: { name: 'render' | 'external'; size?: number }) {
  const common = svgIconProps({ size, strokeWidth: 1.9 });
  if (name === 'external') {
    return <svg {...common}><path d="M14 5h5v5" /><path d="m19 5-8 8" /><path d="M19 14v4a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h4" /></svg>;
  }
  return <svg {...common}><rect x="4" y="5" width="16" height="14" rx="2.5" /><path d="M8 9h8M8 13h5" /></svg>;
}

const ProgressiveHtmlBody = memo(function ProgressiveHtmlBody({
  source,
  mono,
}: {
  source: string;
  mono: boolean;
}) {
  const profileKey = useMemo(() => contentCacheKey('html-profile', source), [source]);
  const profile = useMemo(() => htmlRenderProfile(source), [source]);
  const [expandedProfileKey, setExpandedProfileKey] = useState<string | null>(null);

  if (!profile.complex) return <HtmlBody source={source} mono={mono} />;

  if (expandedProfileKey === profileKey) {
    return (
      <DeferredHtmlBody
        source={source}
        mono={mono}
      />
    );
  }

  return (
    <div class="oh-html-progressive-preview">
      <div class="oh-html-progressive-preview-text">
        {profile.previewText || source.slice(0, HTML_COMPLEX_PREVIEW_MAX_CHARS)}
      </div>
      <div class="oh-html-progressive-actions">
        <button
          type="button"
          class="oh-html-progressive-button oh-tap-press"
          onClick={() => setExpandedProfileKey(profileKey)}
        >
          <HtmlPreviewIcon name="render" />
          <span>显示完整卡片</span>
        </button>
        <button
          type="button"
          class="oh-html-progressive-button oh-tap-press"
          onClick={() => openHtmlInNewTab(source)}
        >
          <HtmlPreviewIcon name="external" />
          <span>新标签页打开</span>
        </button>
      </div>
    </div>
  );
});

interface CodeBlockSurfaceProps {
  lang: string | null;
  plainText: string;
  codeClassName: string | undefined;
  codeRest: Record<string, unknown>;
  children: any;
}

function WrapLinesIcon({ wrapped }: { wrapped: boolean }) {
  const common = svgIconProps({ size: 16 });
  if (wrapped) {
    return (
      <svg {...common}>
        <path d="M3 6h18" />
        <path d="M3 12h15a3 3 0 1 1 0 6h-4" />
        <path d="m16 16-2 2 2 2" />
        <path d="M3 18h7" />
      </svg>
    );
  }
  return (
    <svg {...common}>
      <path d="M3 6h18" />
      <path d="M3 12h18" />
      <path d="M3 18h18" />
    </svg>
  );
}

function CodeBlockWrapButton({
  wrapLines,
  onToggle,
}: {
  wrapLines: boolean;
  onToggle: () => void;
}) {
  const label = wrapLines
    ? t('codeBlock.unwrap', '取消换行')
    : t('codeBlock.wrap', '自动换行');
  return (
    <button
      type="button"
      class={`oh-code-block-icon-btn oh-tap-press${wrapLines ? ' is-active' : ''}`}
      title={label}
      aria-label={label}
      aria-pressed={wrapLines}
      onClick={onToggle}
    >
      <WrapLinesIcon wrapped={wrapLines} />
    </button>
  );
}

type InlineDiffLineKind = 'context' | 'addition' | 'deletion' | 'folded';

interface InlineDiffLine {
  kind: InlineDiffLineKind;
  text: string;
  lineNumber?: number;
  foldedCount?: number;
}

function isDiffFenceLanguage(lang: string | null | undefined): boolean {
  const value = (lang ?? '').trim().toLowerCase();
  return value === 'diff'
    || value === 'patch'
    || value === 'udiff'
    || value === 'unified-diff'
    || value === 'unified_diff'
    || value.startsWith('diff-')
    || value.startsWith('patch-');
}

function looksLikeInlineDiffCodeBlock(lang: string | null, source: string): boolean {
  const trimmed = source.trim();
  if (!trimmed) return false;
  const lines = trimmed.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return false;

  let additions = 0;
  let deletions = 0;
  let structural = 0;
  let diffLike = 0;
  let other = 0;
  for (const line of lines) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      structural += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith('diff --git ') || line.startsWith('index ') || INLINE_DIFF_HUNK_HEADER_RE.test(line)) {
      structural += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith('+')) {
      additions += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith('-')) {
      deletions += 1;
      diffLike += 1;
      continue;
    }
    if (line.startsWith(' ')) {
      diffLike += 1;
      continue;
    }
    other += 1;
  }

  if (isDiffFenceLanguage(lang)) return additions + deletions + structural > 0;
  if (structural > 0) return additions + deletions > 0;
  if (additions === 0 || deletions === 0 || additions + deletions < 2) return false;
  const toleratedOtherLines = Math.max(1, Math.floor(lines.length * 0.25));
  return diffLike / lines.length >= 0.55 && other <= toleratedOtherLines;
}

function inlineDiffLines(source: string): InlineDiffLine[] {
  const rawLines = source.replace(/\n$/, '');
  if (!rawLines.trim()) return [];
  const lines = rawLines.split(/\r?\n/);
  const hasUnifiedStructure = lines.some((line) => (
    line.startsWith('diff --git ')
    || line.startsWith('index ')
    || line.startsWith('---')
    || line.startsWith('+++')
    || INLINE_DIFF_HUNK_HEADER_RE.test(line)
  ));
  if (!hasUnifiedStructure) {
    return lines.map((line) => {
      if (line.startsWith('+')) {
        return { kind: 'addition', text: line.length > 1 ? line.slice(1) : '' };
      }
      if (line.startsWith('-')) {
        return { kind: 'deletion', text: line.length > 1 ? line.slice(1) : '' };
      }
      return { kind: 'context', text: line.startsWith(' ') ? line.slice(1) : line };
    });
  }

  const out: InlineDiffLine[] = [];
  let oldLine = 1;
  let newLine = 1;
  let sawHunk = false;
  for (const rawLine of lines) {
    if (rawLine.startsWith('diff --git ') || rawLine.startsWith('index ')) continue;
    if (rawLine.startsWith('---') || rawLine.startsWith('+++')) continue;
    const hunkMatch = INLINE_DIFF_HUNK_HEADER_RE.exec(rawLine);
    if (hunkMatch != null) {
      const oldStart = Number.parseInt(hunkMatch[1] ?? '', 10);
      const newStart = Number.parseInt(hunkMatch[3] ?? '', 10);
      const hunkOldStart = Number.isFinite(oldStart) ? oldStart : oldLine;
      const hunkNewStart = Number.isFinite(newStart) ? newStart : hunkOldStart;
      if (sawHunk) {
        const folded = hunkOldStart - oldLine;
        if (folded > 0) out.push({ kind: 'folded', text: '', foldedCount: folded });
      }
      oldLine = hunkOldStart;
      newLine = hunkNewStart;
      sawHunk = true;
      continue;
    }
    if (rawLine.startsWith('+')) {
      out.push({
        kind: 'addition',
        lineNumber: sawHunk ? newLine : undefined,
        text: rawLine.length > 1 ? rawLine.slice(1) : '',
      });
      newLine += 1;
      continue;
    }
    if (rawLine.startsWith('-')) {
      out.push({
        kind: 'deletion',
        lineNumber: sawHunk ? oldLine : undefined,
        text: rawLine.length > 1 ? rawLine.slice(1) : '',
      });
      oldLine += 1;
      continue;
    }
    out.push({
      kind: 'context',
      lineNumber: sawHunk ? newLine : undefined,
      text: rawLine.startsWith(' ') ? rawLine.slice(1) : rawLine,
    });
    oldLine += 1;
    newLine += 1;
  }
  return out;
}

function downloadInlineDiff(source: string, lang: string | null): boolean {
  const normalized = (lang ?? '').trim().toLowerCase();
  const ext = normalized === 'patch' || normalized.startsWith('patch-') ? 'patch' : 'diff';
  try {
    const blob = new Blob([source], { type: 'text/x-diff;charset=utf-8' });
    downloadBlobWithAnchor(blob, `diff_block.${ext}`);
    showSnackbar(t('codeBlock.diffDownloaded', 'Diff 已下载'), { tone: 'success' });
    return true;
  } catch {
    showSnackbar(t('codeBlock.diffDownloadFailed', '下载 Diff 失败'), { tone: 'error' });
    return false;
  }
}

function InlineDiffBlock({ lang, plainText }: { lang: string | null; plainText: string }) {
  const [showFull, setShowFull] = useState(false);
  const [wrapLines, setWrapLines] = useState(false);
  const { active: copied, trigger: showCopied, reset: resetCopied } = useTransientFlag();
  const {
    active: downloaded,
    trigger: showDownloaded,
    reset: resetDownloaded,
  } = useTransientFlag();
  const lines = useMemo(() => inlineDiffLines(plainText), [plainText]);
  const visibleLines = !showFull && lines.length > INLINE_DIFF_PREVIEW_LINE_LIMIT
    ? lines.slice(0, INLINE_DIFF_PREVIEW_LINE_LIMIT)
    : lines;
  const hiddenCount = lines.length - visibleLines.length;
  const clipped = hiddenCount > 0;
  const showFooter = clipped || (showFull && lines.length > INLINE_DIFF_PREVIEW_LINE_LIMIT);

  useEffect(() => {
    resetCopied();
    resetDownloaded();
    setShowFull(false);
  }, [plainText, resetCopied, resetDownloaded]);

  return (
    <div class="oh-inline-diff-block">
      <div class="oh-inline-diff-header">
        <span class="oh-inline-diff-chip">diff</span>
        <span style={{ flex: 1 }} />
        <CodeBlockWrapButton
          wrapLines={wrapLines}
          onToggle={() => setWrapLines((value) => !value)}
        />
        <button
          type="button"
          class="oh-code-block-copy oh-tap-press"
          onClick={async () => {
            if (await copyTextToClipboard(plainText)) {
              showCopied();
              showSnackbar(t('codeBlock.diffCopied', 'Diff 内容已复制'), { tone: 'success' });
            } else {
              showSnackbar(t('codeBlock.diffCopyFailed', '复制 Diff 失败，请检查浏览器权限'), { tone: 'error' });
            }
          }}
        >{copied ? t('common.copied', '已复制') : t('common.copy', '复制')}</button>
        <button
          type="button"
          class="oh-code-block-copy oh-tap-press"
          onClick={() => {
            if (downloadInlineDiff(plainText, lang)) {
              showDownloaded();
            }
          }}
        >{downloaded ? t('codeBlock.downloaded', '已下载') : t('codeBlock.download', '下载')}</button>
      </div>
      {lines.length === 0 ? (
        <div class="oh-inline-diff-empty">内容相同或不可对比。</div>
      ) : (
        <div
          class={`oh-inline-diff-body${wrapLines ? ' is-wrap' : ''}`}
          data-expanded={showFull ? 'true' : 'false'}
        >
          {visibleLines.map((line, index) => (
            <div key={`${index}-${line.kind}-${line.lineNumber ?? ''}-${line.text}`} class={`oh-inline-diff-row is-${line.kind}`}>
              <span class="oh-inline-diff-accent" aria-hidden />
              <span class="oh-inline-diff-gutter">
                {line.kind === 'folded' ? '⋯' : line.lineNumber ?? ''}
              </span>
              <span class="oh-inline-diff-code">
                {line.kind === 'folded' ? `${line.foldedCount ?? 0} 行未修改` : line.text || ' '}
              </span>
            </div>
          ))}
        </div>
      )}
      {showFooter ? (
        <button
          type="button"
          class="oh-inline-diff-footer"
          onClick={() => setShowFull((value) => !value)}
        >
          {showFull ? '收起 Diff 预览' : `展开全部 Diff（还有 ${hiddenCount} 行）`}
        </button>
      ) : null}
    </div>
  );
}

/// 代码块外层 (header + body),承载 mermaid 视图/代码 toggle 与 HTML
/// 浏览器打开按钮。状态局部于本组件,跨消息实例完全独立;未在视图
/// 态时 MermaidView 不挂载,主线程不付出 mermaid 解析代价。
function CodeBlockSurface({
  lang,
  plainText,
  codeClassName,
  codeRest,
  children,
}: CodeBlockSurfaceProps) {
  const [mermaidViewActive, setMermaidViewActive] = useState(false);
  const [wrapLines, setWrapLines] = useState(false);
  const isMermaid = (lang ?? '').trim().toLowerCase() === 'mermaid';
  const isHtmlLang = lang != null && /^x?html\d?$/i.test(lang);
  const effectivePlainText = plainText.replace(/\n$/, '');
  if (looksLikeInlineDiffCodeBlock(lang, effectivePlainText)) {
    return <InlineDiffBlock lang={lang} plainText={effectivePlainText} />;
  }
  const bodyClass = [
    codeClassName,
    'oh-code-block-body',
    wrapLines ? 'is-wrap' : 'is-scroll',
  ].filter(Boolean).join(' ');
  return (
    <div class="oh-code-block">
      <div class="oh-code-block-header">
        {lang && <span class="oh-code-block-lang">{decisionFenceLanguageLabel(lang) ?? lang}</span>}
        <span style={{ flex: 1 }} />
        {isMermaid ? (
          <button
            type="button"
            class="oh-code-block-copy oh-tap-press"
            onClick={() => setMermaidViewActive((v) => !v)}
          >{mermaidViewActive ? t('codeBlock.code', '代码') : t('codeBlock.view', '视图')}</button>
        ) : null}
        {isHtmlLang ? (
          <button
            type="button"
            class="oh-code-block-copy oh-tap-press"
            onClick={() => openHtmlInNewTab(effectivePlainText)}
          >{t('codeBlock.openInBrowser', '浏览器打开')}</button>
        ) : null}
        <CodeBlockWrapButton
          wrapLines={wrapLines}
          onToggle={() => setWrapLines((value) => !value)}
        />
        <button
          type="button"
          class="oh-code-block-copy oh-tap-press"
          onClick={async () => {
            if (await copyTextToClipboard(effectivePlainText)) {
              showSnackbar(t('codeBlock.copySuccess', '代码已复制'), { tone: 'success' });
            } else {
              showSnackbar(t('codeBlock.copyFailed', '复制失败，请检查浏览器权限'), { tone: 'error' });
            }
          }}
        >{t('common.copy', '复制')}</button>
      </div>
      {isMermaid && mermaidViewActive ? (
        <MermaidView source={effectivePlainText} />
      ) : (
        <code
          {...(codeRest as any)}
          className={bodyClass}
        >
          {children}
        </code>
      )}
    </div>
  );
}

function extractMarkdownCodeText(nodes: unknown): string {
  if (nodes == null || typeof nodes === 'boolean') return '';
  if (typeof nodes === 'string' || typeof nodes === 'number') {
    return String(nodes);
  }
  if (Array.isArray(nodes)) {
    return nodes.map(extractMarkdownCodeText).join('');
  }
  if (typeof nodes !== 'object') return '';
  const record = nodes as Record<string, unknown>;
  if (typeof record.value === 'string' || typeof record.value === 'number') {
    return String(record.value);
  }
  if ('children' in record) {
    return extractMarkdownCodeText(record.children);
  }
  if ('props' in record) {
    const props = record.props as Record<string, unknown> | undefined;
    if (props != null && 'children' in props) {
      return extractMarkdownCodeText(props.children);
    }
  }
  return '';
}

/** 等待帧预算时先显示正文，预览长度与布局开销均有上限。 */
function MarkdownPendingPreview({ source }: { source: string }) {
  const preview = looksLikeRenderableHtml(source)
    ? extractHtmlPreviewText(source)
    : source;
  return (
    <div class="oh-markdown-pending-preview text-sm">
      {truncateEndText(preview, MARKDOWN_PENDING_PREVIEW_MAX_CHARS, { ellipsis: '' })}
    </div>
  );
}

/// memo 是长会话的关键护栏：react-markdown 内部不缓存 AST，组件体每执行
/// 一次就是一整条 remark → rehype → highlight/katex 管线。父级（会话页）
/// 任意 state 变更都会波及窗口内全部卡片，未 memo 时等于每次都全量重解析。
const MarkdownBody = memo(function MarkdownBody({ source, raw = false, mono = false, format = 'markdown', htmlFallback = 'markdown', streaming = false }: MarkdownProps) {
  const [imageGallery, setImageGallery] = useState<{ images: ImageGalleryEntry[]; index: number } | null>(null);
  const openImage = (event: MouseEvent) => {
    if (!(event.target instanceof HTMLImageElement) || !(event.currentTarget instanceof HTMLElement)) return;
    event.preventDefault();
    event.stopPropagation();
    const gallery = collectImageGallery(event.currentTarget, event.target);
    if (gallery.index >= 0) setImageGallery(gallery);
  };
  const content = source ?? '';
  const tooBig = content.length > CONTENT_TOO_BIG_CHARS;
  const markdownContent = useMemo(
    () => tooBig ? '' : stripLocalMediaReferences(content),
    [content, tooBig],
  );
  const oversizedMarkdownPreview = useMemo(
    () => tooBig
      ? truncateEndText(content, OVERSIZED_MARKDOWN_PREVIEW_MAX_CHARS, { ellipsis: '' })
      : '',
    [content, tooBig],
  );
  const {
    clearTimer: clearStreamFlushTimer,
    scheduleTimer: scheduleStreamFlushTimer,
  } = useTimeoutController();
  // 流式 HTML 渲染稳态：必须在所有 hook 入口前调用，避免条件 hook。
  const stickyLooksHtml = useStickyLooksLikeHtml(content);

  // 挂载已取得帧预算；流式更新只合并内容，避免重复排队与解析。
  const [renderedMarkdownContent, setRenderedMarkdownContent] = useState(markdownContent);
  const lastFlushAtRef = useRef<number>(0);
  useEffect(() => {
    if (markdownContent === renderedMarkdownContent) return;
    const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const ageMs = now - lastFlushAtRef.current;
    const delta = Math.abs(markdownContent.length - renderedMarkdownContent.length);
    const shouldFlushNow =
      markdownContent.length < renderedMarkdownContent.length // 内容回退/截断
      || delta >= MARKDOWN_STREAM_FLUSH_DELTA
      || ageMs >= MARKDOWN_STREAM_FLUSH_MS;
    const flush = () => {
      lastFlushAtRef.current = typeof performance !== 'undefined' ? performance.now() : Date.now();
      setRenderedMarkdownContent(markdownContent);
    };
    if (isTranscriptScrollActive()) {
      return scheduleAfterTranscriptScrollSettles(flush);
    }
    if (shouldFlushNow) {
      flush();
      return;
    }
    const wait = Math.max(0, MARKDOWN_STREAM_FLUSH_MS - ageMs);
    let cancelAfterSettle: (() => void) | null = null;
    scheduleStreamFlushTimer(() => {
      if (isTranscriptScrollActive()) {
        cancelAfterSettle = scheduleAfterTranscriptScrollSettles(flush);
        return;
      }
      flush();
    }, wait);
    return () => {
      clearStreamFlushTimer();
      cancelAfterSettle?.();
    };
  }, [
    clearStreamFlushTimer,
    markdownContent,
    renderedMarkdownContent,
    scheduleStreamFlushTimer,
  ]);
  const renderedContent = useMemo(
    () => normalizeMarkdownMathDelimiters(streaming ? renderedMarkdownContent : markdownContent),
    [streaming, renderedMarkdownContent, markdownContent],
  );

  // 无 ``` 代码块直接跳过 rehype-highlight，省一次 hast 遍历 + highlight.js
  // auto-detect。中长文本（占绝大多数 AI 消息）受益最大。
  const hasFencedCode = useMemo(() => FENCED_CODE_RE.test(renderedContent), [renderedContent]);
  const hasMath = useMemo(() => MATH_DELIMITER_RE.test(markdownContent), [markdownContent]);
  // 懒载入：消息含代码块时再 dynamic import；插件 module 加载完成前先空插件
  // 渲染 markdown（代码块降级为普通 pre），加载完成 setState 触发一次重渲。
  // 进程级共享缓存，多张含代码消息只触发一次网络请求。
  const [rehypeHighlightPlugin, setRehypeHighlightPlugin] = useState<RehypeHighlightPlugin | null>(
    () => rehypeHighlightState.value,
  );
  useEffect(() => {
    if (!hasFencedCode || rehypeHighlightPlugin != null) return;
    let cancelled = false;
    let cancelRender: (() => void) | null = null;
    loadRehypeHighlight().then((plugin) => {
      if (cancelled) return;
      cancelRender = richContentFrameScheduler.schedule(() => setRehypeHighlightPlugin(() => plugin));
    }).catch(ignoreError);
    return () => {
      cancelled = true;
      cancelRender?.();
    };
  }, [hasFencedCode, rehypeHighlightPlugin]);
  const [remarkMathPlugin, setRemarkMathPlugin] = useState<MarkdownPlugin | null>(
    () => remarkMathState.value,
  );
  const [rehypeKatexPlugin, setRehypeKatexPlugin] = useState<MarkdownPlugin | null>(
    () => rehypeKatexState.value,
  );
  useEffect(() => {
    if (!hasMath || (remarkMathPlugin != null && rehypeKatexPlugin != null)) return;
    let cancelled = false;
    let cancelRender: (() => void) | null = null;
    Promise.all([loadRemarkMath(), loadRehypeKatex()]).then(([math, katex]) => {
      if (cancelled) return;
      // 两个公式插件一起提交，避免同一卡片连续重跑两次解析管线。
      cancelRender = richContentFrameScheduler.schedule(() => {
        setRemarkMathPlugin(() => math);
        setRehypeKatexPlugin(() => katex);
      });
    }).catch(ignoreError);
    return () => {
      cancelled = true;
      cancelRender?.();
    };
  }, [hasMath, remarkMathPlugin, rehypeKatexPlugin]);
  const remarkPlugins = useMemo(
    () => (hasMath && remarkMathPlugin ? [remarkGfm, remarkMathPlugin as never] : [remarkGfm]),
    [hasMath, remarkMathPlugin],
  );
  const rehypePlugins = useMemo(
    () => {
      const plugins: never[] = [];
      if (hasFencedCode && rehypeHighlightPlugin) {
        plugins.push(rehypeHighlightPlugin as never);
      }
      if (hasMath && rehypeKatexPlugin) {
        plugins.push(rehypeKatexPlugin as never);
      }
      return plugins;
    },
    [hasFencedCode, hasMath, rehypeHighlightPlugin, rehypeKatexPlugin],
  );

  const fontFamily = mono
    ? 'ui-monospace, SFMono-Regular, Menlo, monospace'
    : 'inherit';

  const components = useMemo(
    () => ({
      a: (props: any) => (
        <a
          {...props}
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: 'var(--m3-primary)', textDecoration: 'underline' }}
        />
      ),
      img: (props: any) => (
        <img
          {...props}
          loading="lazy"
          tabIndex={0}
          role="button"
          onKeyDown={(event: KeyboardEvent) => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault();
              (event.currentTarget as HTMLImageElement).click();
            }
          }}
          style={{
            cursor: 'zoom-in',
            maxWidth: '100%',
            borderRadius: '6px',
            margin: '0.5rem 0',
          }}
        />
      ),
      code: (props: any) => {
        // rehype-highlight 会为块级代码添加 className；高亮产生的子元素也可用于识别已处理的代码块。
        const { className, children, node, ...rest } = props;
        const hasHljsClass = Boolean(className);
        const parentTag = typeof node?.tagName === 'string' ? String(node.tagName).toLowerCase() : '';
        const hasElementChildren = Array.isArray(children) && children.some(
          (c: unknown) => c != null && typeof c === 'object',
        );
        const isBlock = parentTag === 'code' && (hasHljsClass || hasElementChildren);
        if (isBlock) {
          const lang = className
            ?.split(' ')
            .find((c: string) => c.startsWith('language-'))
            ?.replace('language-', '') || null;
          const plainText = extractMarkdownCodeText(children);
          if (lang === DECISION_RESULT) return <DecisionCard text={plainText} />;
          if (lang === DECISION_REQUEST) return <DecisionRequestCard text={plainText} />;
          return (
            <CodeBlockSurface
              lang={lang}
              plainText={plainText}
              codeClassName={className}
              codeRest={rest}
            >
              {children}
            </CodeBlockSurface>
          );
        }
        // 行内代码。
        return (
          <code
            className={className}
            style={{
              padding: '1px 5px',
              borderRadius: '4px',
              background: 'rgba(127,127,127,0.1)',
              fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
              fontSize: '0.92em',
            }}
            {...rest}
          >
            {children}
          </code>
        );
      },
      pre: (props: any) => {
        // <pre> 仅包裹块级 <code>，具体样式由代码组件负责。
        const { children, ...rest } = props;
        return (
          <pre {...rest} style={{ background: 'transparent', margin: 0, padding: 0, overflow: 'visible' }}>
            {children}
          </pre>
        );
      },
      table: (props: any) => (
        <div style={{ overflowX: 'auto', margin: '0.75rem 0' }}>
          <table
            {...props}
            style={{
              borderCollapse: 'collapse',
              width: '100%',
            }}
          />
        </div>
      ),
      th: (props: any) => (
        <th
          {...props}
          style={{
            border: '1px solid var(--m3-outline)',
            padding: '6px 10px',
            background: 'var(--m3-surface-container)',
            textAlign: 'left',
          }}
        />
      ),
      td: (props: any) => (
        <td
          {...props}
          style={{
            border: '1px solid var(--m3-outline)',
            padding: '6px 10px',
          }}
        />
      ),
    }),
    [],
  );

  // 稳定 vnode：流式逐字揭示会让本组件以 ~60fps 重渲染，而 react-markdown
  // 在渲染期同步执行整条 remark→rehype 管线且无内部缓存。renderedContent
  // 与插件未变时复用同一元素引用，Preact 直接跳过该子树 diff——全量重解析
  // 从每帧一次降到每次 flush（约 12.5 次/秒）一次。vnode 创建本身极廉价，
  // 未走 markdown 分支时不会触发解析。
  const markdownTree = useMemo(
    () => (
      <ReactMarkdown
        remarkPlugins={remarkPlugins}
        rehypePlugins={rehypePlugins}
        components={components}
      >
        {renderedContent}
      </ReactMarkdown>
    ),
    [components, rehypePlugins, remarkPlugins, renderedContent],
  );

  const renderAsPlainText = raw
    || format === 'plain_text'
    || (
      format === 'html'
      && !streaming
      && !stickyLooksHtml
      && htmlFallback === 'plain_text'
    );
  if (renderAsPlainText) {
    return (
      <pre
        class="whitespace-pre-wrap break-words text-sm"
        style={{ margin: 0, fontFamily }}
      >
        {content}
      </pre>
    );
  }
  if (format === 'html') {
    if (streaming) {
      return <HtmlBodyPlaceholder source={content || ' '} />;
    }
    if (stickyLooksHtml) {
      return <ProgressiveHtmlBody source={content} mono={mono} />;
    }
    // 继续按 Markdown 渲染。
  }

  // 自适应：WEB 端 contentFormat 由本机 localStorage 控制，可能与 APP 端
  // 实际设置不同步——若用户在 APP 把输出格式切到 HTML，AI 已经返回 HTML 内容，
  // 而 WEB 此时 format 仍是 'markdown' 时，会把 <h2>...</h2> 当作纯文本展示
  // (markdown 不会主动解析裸 HTML 标签作为渲染指令)。这里在 markdown 路径上
  // 检测内容是否像 HTML，自动升级到 HtmlBody 渲染，使 WEB 端对 AI 输出
  // 自愈，无需用户手动切设置项。sticky 与 'html' 分支共用同一 hook 结果。
  if (format === 'markdown' && stickyLooksHtml) {
    if (streaming) {
      return <HtmlBodyPlaceholder source={content || ' '} />;
    }
    return <ProgressiveHtmlBody source={content} mono={mono} />;
  }

  // tooBig 守卫仅针对 markdown（解析开销大）；plain_text/html 已在上方提前返回。
  if (tooBig) {
    return (
      <pre
        class="whitespace-pre-wrap break-words text-sm"
        style={{ margin: 0, fontFamily }}
      >
        {oversizedMarkdownPreview}
        {`\n\n[内容过长，已为保证性能仅显示前 ${OVERSIZED_MARKDOWN_PREVIEW_MAX_CHARS} 个字符；可通过消息操作复制完整内容。原文长度：${content.length}]`}
      </pre>
    );
  }

  return (
    <div class="oh-markdown text-sm" style={{ fontFamily }} onClick={openImage}>
      {markdownTree}
      {imageGallery && imageGallery.images[imageGallery.index] ? <MediaPreviewDialog
        item={imageGallery.images[imageGallery.index].item} url={imageGallery.images[imageGallery.index].url}
        gallery={imageGallery.images} initialIndex={imageGallery.index} onClose={() => setImageGallery(null)} /> : null}
    </div>
  );
});

/** 历史正文先进入视口再做格式检测、预处理和插件加载。 */
export const Markdown = memo(function Markdown(props: MarkdownProps) {
  const source = props.source ?? '';
  // 决策卡片直接按真实结构布局，避免虚拟窗口重挂载时占位高度反复变化。
  const deferred = !props.streaming && !props.raw && props.format !== 'plain_text'
    && props.deferInitialRender !== false
    && !containsDecisionFence(source)
    && (Boolean(props.deferInitialRender)
      || source.length > MARKDOWN_DEFERRED_PARSE_THRESHOLD
      || FENCED_CODE_RE.test(source)
      || MATH_DELIMITER_RE.test(source));
  const { hostRef, ready } = useRichContentMount(deferred);
  return (
    <div ref={hostRef} class="oh-rich-content-host">
      {ready ? <MarkdownBody {...props} /> : <MarkdownPendingPreview source={source} />}
    </div>
  );
});
