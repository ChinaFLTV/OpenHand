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

import { useMemo } from 'preact/hooks';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeHighlight from 'rehype-highlight';

const CONTENT_TOO_BIG_BYTES = 120 * 1024;
const LOCAL_MEDIA_EXT = /\.(?:png|jpe?g|gif|webp|bmp|heic|svg|mp4|webm|mov|m4v|mp3|wav|ogg|m4a|flac|aac)(?:[?#].*)?$/i;
const MARKDOWN_MEDIA_REF = /!?\[[^\]\n]{0,240}\]\(([^)\r\n]+)\)/g;

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
}

export function Markdown({ source, raw = false, mono = false }: MarkdownProps) {
  const content = source ?? '';
  const markdownContent = useMemo(() => stripLocalMediaReferences(content), [content]);
  const tooBig = content.length > CONTENT_TOO_BIG_BYTES;

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
        // react-markdown v10: detect block code by checking if parent is <pre>.
        // The `node` prop contains hast node; its parent info isn't directly
        // available, but block code always has className from rehype-highlight
        // OR is the direct child of a <pre> element. We use a more robust check:
        // if className exists (rehype-highlight always adds 'hljs' or 'language-X')
        // OR if the element has multiple lines, treat as block code.
        const { className, children, node, ...rest } = props;
        const textContent = typeof children === 'string'
          ? children
          : Array.isArray(children)
            ? children.filter((c: unknown) => typeof c === 'string').join('')
            : '';
        const hasClass = Boolean(className);
        const isMultiline = textContent.includes('\n');
        const isBlock = hasClass || isMultiline;
        if (isBlock) {
          const lang = className
            ?.split(' ')
            .find((c: string) => c.startsWith('language-'))
            ?.replace('language-', '') || null;
          return (
            <div style={{
              position: 'relative',
              borderRadius: '12px',
              overflow: 'hidden',
              border: '1px solid color-mix(in srgb, var(--m3-outline) 40%, transparent)',
              margin: '0.5rem 0',
              background: 'color-mix(in srgb, var(--m3-on-surface) 4%, transparent)',
            }}>
              <div style={{
                display: 'flex',
                alignItems: 'center',
                padding: '6px 12px',
                background: 'color-mix(in srgb, var(--m3-on-surface) 5%, transparent)',
                borderBottom: '1px solid color-mix(in srgb, var(--m3-outline) 30%, transparent)',
                gap: '8px',
              }}>
                {lang && (
                  <span style={{
                    fontSize: '0.78em',
                    fontWeight: 700,
                    color: 'var(--m3-on-surface-variant)',
                    padding: '2px 8px',
                    borderRadius: '999px',
                    background: 'color-mix(in srgb, var(--m3-primary) 8%, transparent)',
                  }}>{lang}</span>
                )}
                <span style={{ flex: 1 }} />
                <button
                  type="button"
                  onClick={() => {
                    const text = typeof children === 'string'
                      ? children
                      : (node?.children?.[0]?.value ?? textContent ?? '');
                    navigator.clipboard?.writeText(text);
                  }}
                  style={{
                    fontSize: '0.78em',
                    fontWeight: 700,
                    color: 'var(--m3-on-surface-variant)',
                    padding: '2px 8px',
                    borderRadius: '999px',
                    background: 'color-mix(in srgb, var(--m3-on-surface) 6%, transparent)',
                    border: 'none',
                    cursor: 'pointer',
                  }}
                >复制</button>
              </div>
              <code className={className} {...rest} style={{
                display: 'block',
                padding: '0.75rem 1rem',
                overflowX: 'auto',
                fontSize: '0.88em',
                background: 'transparent',
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
              background: 'color-mix(in srgb, var(--m3-on-surface) 8%, transparent)',
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
        // In react-markdown v10, <pre> wraps block <code>.
        // We make <pre> transparent since the code component handles styling.
        const { children, ...rest } = props;
        return (
          <pre {...rest} style={{
            background: 'transparent',
            margin: 0,
            padding: 0,
            overflow: 'visible',
          }}>
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

  if (raw || tooBig) {
    return (
      <pre
        class="whitespace-pre-wrap break-words text-sm"
        style={{ margin: 0, fontFamily }}
      >
        {content}
        {tooBig ? `\n\n[content truncated for performance — ${content.length} bytes]` : ''}
      </pre>
    );
  }

  return (
    <div class="oh-markdown text-sm" style={{ fontFamily }}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[rehypeHighlight]}
        components={components}
      >
        {markdownContent}
      </ReactMarkdown>
    </div>
  );
}
