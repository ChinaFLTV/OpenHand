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
        // inline code: 短小; block code 由 <pre><code> 嵌套, 这里仅装饰行内.
        const { inline, className, children, ...rest } = props;
        if (inline === false) {
          return (
            <code className={className} {...rest}>
              {children}
            </code>
          );
        }
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
      pre: (props: any) => (
        <pre
          {...props}
          style={{
            background: 'color-mix(in srgb, var(--m3-on-surface) 6%, transparent)',
            borderRadius: '8px',
            padding: '0.75rem 1rem',
            overflowX: 'auto',
            fontSize: '0.88em',
          }}
        />
      ),
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
        {content}
      </ReactMarkdown>
    </div>
  );
}
