// Markdown 高性能渲染组件 (基于 react-markdown + remark-gfm + rehype-highlight)。
//
// 设计要点:
// - 通过 @preact/preset-vite 默认 alias react/react-dom → preact/compat,
//   react-markdown 在 Preact 上零侵入运行.
// - 代码块走 rehype-highlight (内置 highlight.js 子集), 按需 lazy-load
//   主题样式; 主题样式由 components/markdown_styles.css 全局引入一次.
// - 长内容 (> CONTENT_TOO_BIG_BYTES) 跳过 markdown, 直接 pre 渲染原文,
//   避免 reactdom 在 200KB+ 树上花费百毫秒. 与 App 端
//   _SafeMarkdownBody 阈值语义对齐.
// - 表格 / 任务列表 / 删除线由 remark-gfm 提供.
// - 链接强制 target=_blank rel=noopener; 图片 lazy loading.
// - 阶段㉔: 全局帧节流 — 同一帧内多个 Markdown 同时挂载时, 队列
//   逐帧解析每帧最多一个非平凡组件, 避免 60+ 长会话首屏 N 个 react-markdown
//   并行 parse 卡死主线程; 1 KB 以下短消息保持同步, 减少视觉闪烁。

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { showSnackbar } from './Snackbar';

/// rehype-highlight 真正按需懒载：默认不在 entry / vendor 关键路径里拉，
/// 直到首次遇到 ``` 代码块的消息才发起 dynamic import (chunk 已经 split，
/// 浏览器拉 vendor-highlight.js 51KB gz)。整个进程内首次解析后插件被缓存，
/// 之后所有 Markdown 实例共享。
type RehypeHighlightPlugin = unknown;
let rehypeHighlightCache: RehypeHighlightPlugin | null = null;
let rehypeHighlightLoading: Promise<RehypeHighlightPlugin> | null = null;
function loadRehypeHighlight(): Promise<RehypeHighlightPlugin> {
  if (rehypeHighlightCache != null) return Promise.resolve(rehypeHighlightCache);
  if (rehypeHighlightLoading != null) return rehypeHighlightLoading;
  rehypeHighlightLoading = import('rehype-highlight').then((mod) => {
    const plugin = (mod as { default?: RehypeHighlightPlugin }).default ?? mod;
    rehypeHighlightCache = plugin;
    rehypeHighlightLoading = null;
    return plugin;
  }).catch((err) => {
    rehypeHighlightLoading = null;
    throw err;
  });
  return rehypeHighlightLoading;
}

const CONTENT_TOO_BIG_BYTES = 120 * 1024;
/// 1 KB 以上的内容首次挂载时走帧节流 deferred 路径 (首帧 plain text 占位
/// + 下一空闲帧补回 markdown), 避免会话打开时多卡片同步 parse 卡顿。
const MARKDOWN_DEFERRED_PARSE_THRESHOLD = 1024;
/// W1 流式节流：parseReady=true 后的内容变更，若增量很小且距上次 flush 不久，
/// 短期 coalesce 到一帧。覆盖 SSE 80ms 一 tick 期间内容追加只增几字符的场景，
/// 把"每 token 重 parse 整棵 react-markdown 树"压成最多 ~12 次/秒。
const MARKDOWN_STREAM_FLUSH_MS = 80;
const MARKDOWN_STREAM_FLUSH_DELTA = 64;
/// W2 跳过 highlight：无 ``` 代码块的消息没必要把 rehype-highlight (内置
/// highlight.js 子集) 跑一遍。大段中文/英文纯文本消息全跳过，主线程压力骤降。
const FENCED_CODE_RE = /(^|\n)[ \t]*```/;
const LOCAL_MEDIA_EXT = /\.(?:png|jpe?g|gif|webp|bmp|heic|svg|mp4|webm|mov|m4v|mp3|wav|ogg|m4a|flac|aac)(?:[?#].*)?$/i;
const MARKDOWN_MEDIA_REF = /!?\[[^\]\n]{0,240}\]\(([^)\r\n]+)\)/g;

/// 阶段㉔: 全局帧节流的 markdown 解析调度器。打开长会话时多张消息卡片
/// 在同一帧内全部 mount, 之前每张都同步走 react-markdown / rehype 解析,
/// 主线程一次性占用数百毫秒 (JS thread 卡死, 用户看到 white blank)。
/// 改为按帧节流, 每帧最多 1 个 markdown 升级渲染, 剩下的卡片以 plain
/// text 占位, 直到本帧完成后下一帧再升级。与 App 端
/// _MarkdownFrameScheduler 思路完全对齐。
const MARKDOWN_FRAME_BUDGET_PER_FRAME = 2;
class MarkdownFrameScheduler {
  private pending: Array<() => void> = [];
  private draining = false;

  schedule(task: () => void): () => void {
    let cancelled = false;
    const wrapped = () => {
      if (!cancelled) task();
    };
    this.pending.push(wrapped);
    if (!this.draining) {
      this.draining = true;
      this.scheduleDrain();
    }
    return () => {
      cancelled = true;
    };
  }

  private scheduleDrain(): void {
    // 优先使用 requestIdleCallback：在浏览器主线程空闲时再 drain，给用户输入
    // / 动画 / 滚动让位，长会话首屏批量解析不再与用户交互抢主线程。bound
    // timeout 100ms 防止持续繁忙时彻底拖延 markdown 升级。Safari 不支持 rIC，
    // 自动退化到 rAF；rAF 也没有时退到 setTimeout。
    const cb = () => {
      const batch = this.pending.splice(0, MARKDOWN_FRAME_BUDGET_PER_FRAME);
      for (const task of batch) {
        try {
          task();
        } catch (_e) {
          // 任务自身抛错不影响调度器继续 drain。
        }
      }
      if (this.pending.length > 0) {
        this.scheduleDrain();
      } else {
        this.draining = false;
      }
    };
    const ric = (globalThis as { requestIdleCallback?: (cb: () => void, opts?: { timeout?: number }) => unknown }).requestIdleCallback;
    if (typeof ric === 'function') {
      ric(cb, { timeout: 100 });
    } else if (typeof requestAnimationFrame === 'function') {
      requestAnimationFrame(cb);
    } else {
      setTimeout(cb, 16);
    }
  }
}
const markdownFrameScheduler = new MarkdownFrameScheduler();

export function normalizeMarkdownDestination(raw: string): string {
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

export function isLocalMediaReference(raw: unknown): boolean {
  if (typeof raw !== 'string') return false;
  const value = normalizeMarkdownDestination(raw);
  if (!value || /^(?:https?:|data:|blob:|\/api\/sessions\/)/i.test(value)) return false;
  return value.includes('openhand_media') || LOCAL_MEDIA_EXT.test(value);
}

export function stripLocalMediaReferences(source: string): string {
  return source
    .replace(MARKDOWN_MEDIA_REF, (match: string, destination: string) => (
      isLocalMediaReference(destination) ? '' : match
    ))
    .replace(/\n{3,}/g, '\n\n');
}

export interface MarkdownProps {
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
}

const HTML_LIKELY_TAG_RE = /<\s*(?:!doctype|html|body|div|span|p|h[1-6]|ul|ol|li|table|tr|td|th|a|img|br|hr|pre|code|strong|em|b|i|u|section|article|header|footer|nav|main|button|form|input|label|style|script|iframe|video|audio|svg)\b/i;

function looksLikeHtml(value: string): boolean {
  if (!value) return false;
  return HTML_LIKELY_TAG_RE.test(value);
}

// DOMPurify 懒载入：仅在首次遇到 html 内容时拉。
type DomPurifyLike = { sanitize: (s: string, opts?: Record<string, unknown>) => string };
let domPurifyCache: DomPurifyLike | null = null;
let domPurifyLoading: Promise<DomPurifyLike> | null = null;
function loadDomPurify(): Promise<DomPurifyLike> {
  if (domPurifyCache != null) return Promise.resolve(domPurifyCache);
  if (domPurifyLoading != null) return domPurifyLoading;
  domPurifyLoading = import('dompurify').then((mod) => {
    const purify = (mod as { default?: DomPurifyLike }).default ?? (mod as unknown as DomPurifyLike);
    domPurifyCache = purify;
    domPurifyLoading = null;
    return purify;
  }).catch((err) => {
    domPurifyLoading = null;
    throw err;
  });
  return domPurifyLoading;
}

function HtmlBody({ source, mono }: { source: string; mono: boolean }) {
  const [purify, setPurify] = useState<DomPurifyLike | null>(() => domPurifyCache);
  useEffect(() => {
    if (purify != null) return;
    let cancelled = false;
    loadDomPurify().then((p) => {
      if (!cancelled) setPurify(() => p);
    }).catch(() => {/* 失败时降级为纯文本 */});
    return () => { cancelled = true; };
  }, [purify]);
  const fontFamily = mono ? 'ui-monospace, SFMono-Regular, Menlo, monospace' : 'inherit';
  if (purify == null) {
    return (
      <pre class="whitespace-pre-wrap break-words text-sm" style={{ margin: 0, fontFamily }}>
        {source}
      </pre>
    );
  }
  const safeHtml = purify.sanitize(source, { USE_PROFILES: { html: true } });
  return (
    <div
      class="oh-html-body text-sm"
      style={{ fontFamily }}
      dangerouslySetInnerHTML={{ __html: safeHtml }}
    />
  );
}

export function Markdown({ source, raw = false, mono = false, format = 'markdown', htmlFallback = 'markdown' }: MarkdownProps) {
  const content = source ?? '';
  const markdownContent = useMemo(() => stripLocalMediaReferences(content), [content]);
  const tooBig = content.length > CONTENT_TOO_BIG_BYTES;

  // 阶段㉔: 帧节流 deferred 路径。raw / tooBig 已经走 plain text 路径，无需
  // 帧节流。中等以上内容 (> MARKDOWN_DEFERRED_PARSE_THRESHOLD) 首次挂载时
  // 先 plain text 占位, 把 react-markdown / rehype 解析推迟到下一空闲帧
  // (帧节流调度器), 避免长会话首屏多卡片同步 parse 撑爆主线程。
  const shouldDeferParse = !raw && !tooBig
    && content.length > MARKDOWN_DEFERRED_PARSE_THRESHOLD;
  const [parseReady, setParseReady] = useState(!shouldDeferParse);
  const lastSourceRef = useRef<string>(content);
  useEffect(() => {
    if (!shouldDeferParse) {
      if (!parseReady) setParseReady(true);
      lastSourceRef.current = content;
      return;
    }
    if (lastSourceRef.current === content && parseReady) return;
    lastSourceRef.current = content;
    // 内容变更后重新 defer 一次, 避免流式追加时立刻 parse 引发 jank。
    if (parseReady) return;
    const cancel = markdownFrameScheduler.schedule(() => {
      setParseReady(true);
    });
    return cancel;
  }, [shouldDeferParse, content, parseReady]);

  // W1 流式节流：parseReady=true 之后的内容变更走 coalesce —— 增量较小
  // 且距上次 flush 不到 80ms 时延迟到本批结束再 setState，避免 SSE 每 tick
  // 触发整棵 react-markdown re-parse。增量大 / 内容回退 / 距离够久立即 flush，
  // 保证视觉响应不延迟。非流式（不变更）路径完全无影响。
  const [renderedContent, setRenderedContent] = useState(markdownContent);
  const lastFlushAtRef = useRef<number>(0);
  useEffect(() => {
    if (!parseReady) {
      // 首次 parse 完成前由 deferred 占位托管，等 parseReady 切换时一次性同步。
      setRenderedContent(markdownContent);
      lastFlushAtRef.current = (typeof performance !== 'undefined' ? performance.now() : Date.now());
      return;
    }
    if (markdownContent === renderedContent) return;
    const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const ageMs = now - lastFlushAtRef.current;
    const delta = Math.abs(markdownContent.length - renderedContent.length);
    const shouldFlushNow =
      markdownContent.length < renderedContent.length // 内容回退/截断
      || delta >= MARKDOWN_STREAM_FLUSH_DELTA
      || ageMs >= MARKDOWN_STREAM_FLUSH_MS;
    if (shouldFlushNow) {
      lastFlushAtRef.current = now;
      setRenderedContent(markdownContent);
      return;
    }
    const wait = Math.max(0, MARKDOWN_STREAM_FLUSH_MS - ageMs);
    const handle = window.setTimeout(() => {
      lastFlushAtRef.current = typeof performance !== 'undefined' ? performance.now() : Date.now();
      setRenderedContent(markdownContent);
    }, wait);
    return () => window.clearTimeout(handle);
  }, [parseReady, markdownContent, renderedContent]);

  // W2 无 ``` 代码块直接跳过 rehype-highlight，省一次 hast 遍历 + highlight.js
  // auto-detect。中长文本（占绝大多数 AI 消息）受益最大。
  const hasFencedCode = useMemo(() => FENCED_CODE_RE.test(renderedContent), [renderedContent]);
  // 懒载入：消息含代码块时再 dynamic import；插件 module 加载完成前先空插件
  // 渲染 markdown（代码块降级为普通 pre），加载完成 setState 触发一次重渲。
  // 进程级共享缓存，多张含代码消息只触发一次网络请求。
  const [rehypeHighlightPlugin, setRehypeHighlightPlugin] = useState<RehypeHighlightPlugin | null>(
    () => rehypeHighlightCache,
  );
  useEffect(() => {
    if (!hasFencedCode || rehypeHighlightPlugin != null) return;
    let cancelled = false;
    loadRehypeHighlight().then((plugin) => {
      if (!cancelled) setRehypeHighlightPlugin(() => plugin);
    }).catch(() => {
      // 加载失败则放弃 highlight，markdown 仍渲染（降级为普通 pre）。
    });
    return () => { cancelled = true; };
  }, [hasFencedCode, rehypeHighlightPlugin]);
  const rehypePlugins = useMemo(
    () => (hasFencedCode && rehypeHighlightPlugin ? [rehypeHighlightPlugin as never] : []),
    [hasFencedCode, rehypeHighlightPlugin],
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
          style={{
            maxWidth: '100%',
            borderRadius: '6px',
            margin: '0.5rem 0',
          }}
        />
      ),
      code: (props: any) => {
        // Block code detection: rehype-highlight adds className to block code.
        // Also check if children contain React elements (spans from highlighting)
        // which indicates this is a processed block code element.
        const { className, children, node, ...rest } = props;
        const hasHljsClass = Boolean(className);
        const hasElementChildren = Array.isArray(children) && children.some(
          (c: unknown) => c != null && typeof c === 'object',
        );
        const isBlock = hasHljsClass || hasElementChildren;
        if (isBlock) {
          const lang = className
            ?.split(' ')
            .find((c: string) => c.startsWith('language-'))
            ?.replace('language-', '') || null;
          // Extract plain text for copy button
          const extractText = (nodes: unknown): string => {
            if (typeof nodes === 'string') return nodes;
            if (Array.isArray(nodes)) return nodes.map(extractText).join('');
            if (nodes != null && typeof nodes === 'object') {
              const n = nodes as any;
              if (n.props?.children) return extractText(n.props.children);
            }
            return '';
          };
          const plainText = extractText(children);
          return (
            <div class="oh-code-block">
              <div class="oh-code-block-header">
                {lang && <span class="oh-code-block-lang">{lang}</span>}
                <span style={{ flex: 1 }} />
                <button
                  type="button"
                  class="oh-code-block-copy"
                  onClick={async () => {
                    try {
                      await navigator.clipboard.writeText(plainText);
                      showSnackbar('代码已复制', { tone: 'success' });
                    } catch {
                      showSnackbar('复制失败，请检查浏览器权限', { tone: 'error' });
                    }
                  }}
                >复制</button>
              </div>
              <code className={className} {...rest} style={{
                display: 'block',
                padding: '0.75rem 1rem',
                overflowX: 'auto',
                fontSize: '0.86em',
                lineHeight: 1.6,
                background: 'transparent',
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
              }}>
                {children}
              </code>
            </div>
          );
        }
        // Inline code
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
        // <pre> wraps block <code>. Make it transparent — code component owns styling.
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
      blockquote: (props: any) => (
        <blockquote
          {...props}
          style={{
            borderLeft: '3px solid var(--m3-primary)',
            padding: '4px 12px',
            margin: '0.5rem 0',
            color: 'var(--m3-on-surface-variant)',
          }}
        />
      ),
    }),
    [],
  );

  if (raw) {
    return (
      <pre
        class="whitespace-pre-wrap break-words text-sm"
        style={{ margin: 0, fontFamily }}
      >
        {content}
      </pre>
    );
  }

  // 阶段㊵: 消息内容格式分派 (与 APP 端 _AssistantMessageBodyDispatcher 对齐)。
  // plain_text / html 分派置于 tooBig 守卫之前：两者渲染廉价（pre / DOMPurify），
  // 不需要也不应该被 tooBig 截断加「truncated for performance」提示。
  if (format === 'plain_text') {
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
    if (looksLikeHtml(content)) {
      return <HtmlBody source={content} mono={mono} />;
    }
    if (htmlFallback === 'plain_text') {
      return (
        <pre
          class="whitespace-pre-wrap break-words text-sm"
          style={{ margin: 0, fontFamily }}
        >
          {content}
        </pre>
      );
    }
    // fall through to markdown rendering
  }

  // tooBig 守卫仅针对 markdown（解析开销大）；plain_text/html 已在上方提前返回。
  if (tooBig) {
    return (
      <pre
        class="whitespace-pre-wrap break-words text-sm"
        style={{ margin: 0, fontFamily }}
      >
        {content}
        {`\n\n[content truncated for performance — ${content.length} bytes]`}
      </pre>
    );
  }

  // 阶段㉔: deferred parse 期间渲染 plain text 占位, 让首屏布局立刻完成。
  // 占位用与最终 markdown 相同的容器 (.oh-markdown), 避免 parse 完成后
  // 容器尺寸/主题色突变。
  if (!parseReady) {
    return (
      <div class="oh-markdown text-sm" style={{ fontFamily }}>
        <pre
          class="whitespace-pre-wrap break-words"
          style={{ margin: 0, fontFamily: 'inherit' }}
        >
          {markdownContent}
        </pre>
      </div>
    );
  }

  return (
    <div class="oh-markdown text-sm" style={{ fontFamily }}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={rehypePlugins}
        components={components}
      >
        {renderedContent}
      </ReactMarkdown>
    </div>
  );
}
