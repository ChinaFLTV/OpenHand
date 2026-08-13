// ToolResultBody —— 工具结果 / 工具调用 / MCP 等 mono 消息体的富展示块
//
// 功能:
// - 展开 / 折叠 (默认折叠到 600 字符以下不显示按钮; 超出则展示前 600 字符
//   + 「展开全部 (N 字符)」按钮; 展开后变为「折叠」)
// - 复制按钮 (统一剪贴板工具兜底, 短暂展示已复制状态)
// - 错误行红色高亮: 行内匹配 (?i)error|exception|traceback|fail|panic 时,
//   左竖条 + 文字偏红
// - 仍保持 pre-wrap mono 字体, word-break:break-all (避免长 URL 撑爆)

import { useMemo, useState } from 'preact/hooks';
import { t } from '../i18n';
import { showSnackbar } from './Snackbar';
import { copyTextToClipboard } from '../utils/clipboard';
import { useStickyBottom } from '../hooks/useStickyBottom';
import { useTransientFlag } from '../hooks/useTransientFlag';
import { truncateEndText } from '../shared/util/text';
import { svgIconProps } from '../shared/ui/svg_icon';

const AUTO_COLLAPSE_CHARS = 600;
const ERROR_LINE_PATTERN = /\b(error|exception|traceback|fail(?:ed|ure)?|panic|fatal)\b/i;
/// 展开时的分片行数：数万行的命令输出一次性建满 vnode/DOM 会造成数百 ms
/// 长任务，按片渐进展开，剩余部分由「继续展开」驱动。
const EXPAND_CHUNK_LINES = 400;

/// 取前 [maxLines] 行（按第 maxLines 个换行截断），不对全文 split 分配行数组。
function sliceLeadingLines(
  text: string,
  maxLines: number,
): { slice: string; hasMore: boolean } {
  let cursor = -1;
  let lines = 0;
  while (lines < maxLines) {
    const next = text.indexOf('\n', cursor + 1);
    if (next === -1) return { slice: text, hasMore: false };
    cursor = next;
    lines += 1;
  }
  return { slice: text.slice(0, cursor), hasMore: cursor < text.length - 1 };
}

interface ToolResultBodyProps {
  content: string;
  autoFollow?: boolean;
}

type ToolBodyIconName = 'copy' | 'check' | 'chevronDown' | 'chevronUp';

function ToolBodyIcon({ name, size = 13 }: { name: ToolBodyIconName; size?: number }) {
  const common = svgIconProps({ size });
  switch (name) {
    case 'copy':
      return <svg {...common}><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M5 15V7a2 2 0 0 1 2-2h8" /></svg>;
    case 'check':
      return <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
    case 'chevronDown':
      return <svg {...common}><path d="m7 10 5 5 5-5" /></svg>;
    case 'chevronUp':
      return <svg {...common}><path d="m7 14 5-5 5 5" /></svg>;
  }
}

interface RenderedLine {
  text: string;
  isError: boolean;
}

function classifyLines(text: string): RenderedLine[] {
  return text.split('\n').map((line) => ({
    text: line,
    isError: ERROR_LINE_PATTERN.test(line),
  }));
}

export function ToolResultBody({ content, autoFollow = false }: ToolResultBodyProps) {
  // 0 = 折叠（600 字符预览）；>0 = 已展开的分片数，每片 EXPAND_CHUNK_LINES 行。
  const [expandedChunks, setExpandedChunks] = useState(0);
  const expanded = expandedChunks > 0;
  const { active: copied, trigger: showCopied } = useTransientFlag();

  const collapsedContent = truncateEndText(content, AUTO_COLLAPSE_CHARS);
  const overflow = collapsedContent !== content;
  const view = useMemo(() => {
    if (expandedChunks <= 0) {
      return { text: collapsedContent, hasMoreLines: false };
    }
    const { slice, hasMore } = sliceLeadingLines(
      content,
      expandedChunks * EXPAND_CHUNK_LINES,
    );
    return { text: slice, hasMoreLines: hasMore };
  }, [collapsedContent, content, expandedChunks]);
  const shown = view.text;
  const lines = useMemo(() => classifyLines(shown), [shown]);
  const preRef = useStickyBottom<HTMLPreElement>(shown, autoFollow);

  const handleCopy = async () => {
    const ok = await copyTextToClipboard(content);
    if (ok) {
      showCopied();
      showSnackbar(t('detail.tool.body.copied', '已复制工具结果'), { tone: 'success' });
    } else {
      showSnackbar(t('detail.tool.body.copyFailed', '复制工具结果失败'), { tone: 'error' });
    }
  };

  return (
    <div class="relative">
      <pre
        ref={preRef}
        class="oh-tool-result-pre text-xs leading-snug whitespace-pre-wrap font-mono rounded-m3-sm p-2 m-0"
        style={{
          background: 'var(--m3-surface)',
          color: 'var(--m3-on-surface)',
          border: '1px solid var(--m3-outline)',
          wordBreak: 'break-word',
          maxHeight: expanded ? 'min(70dvh, 720px)' : '420px',
          overflow: 'auto',
        }}
      >
        {lines.map((line, idx) => (
          <div
            key={idx}
            style={{
              borderLeft: line.isError
                ? '3px solid var(--m3-error)'
                : '3px solid transparent',
              paddingLeft: '6px',
              color: line.isError
                ? 'color-mix(in srgb, var(--m3-error) 78%, var(--m3-on-surface))'
                : undefined,
              background: line.isError
                ? 'color-mix(in srgb, var(--m3-error) 6%, transparent)'
                : undefined,
            }}
          >
            {line.text || '\u00A0'}
          </div>
        ))}
      </pre>
      <div class="oh-tool-result-actions flex items-center gap-2 mt-1.5 text-xs">
        {overflow ? (
          <button
            type="button"
            onClick={() => setExpandedChunks((v) => (v > 0 ? 0 : 1))}
            class="oh-tap-press oh-message-action-button oh-tool-toggle-button is-compact"
            style={{
              background: 'var(--m3-surface-container)',
              color: 'var(--m3-on-surface-variant)',
              border: '1px solid var(--m3-outline)',
            }}
          >
            <ToolBodyIcon name={expanded ? 'chevronUp' : 'chevronDown'} />
            {expanded
              ? t('detail.tool.body.collapse', '折叠')
              : t('detail.tool.body.expand', '展开全部 ') + `(${content.length} ${t('detail.tool.body.chars', '字符')})`}
          </button>
        ) : null}
        {expanded && view.hasMoreLines ? (
          <button
            type="button"
            onClick={() => setExpandedChunks((v) => v + 1)}
            class="oh-tap-press oh-message-action-button oh-tool-toggle-button is-compact"
            style={{
              background: 'var(--m3-surface-container)',
              color: 'var(--m3-on-surface-variant)',
              border: '1px solid var(--m3-outline)',
            }}
          >
            <ToolBodyIcon name="chevronDown" />
            {`${t('detail.tool.body.expandMore', '继续展开 ')}(${t('detail.tool.body.remaining', '剩余')} ${(content.length - shown.length).toLocaleString()} ${t('detail.tool.body.chars', '字符')})`}
          </button>
        ) : null}
        <button
          type="button"
          onClick={handleCopy}
          class="oh-tap-press oh-message-action-button is-compact ml-auto"
          style={{
            background: copied
              ? 'var(--m3-secondary-container)'
              : 'var(--m3-surface-container)',
            color: copied ? 'var(--m3-on-secondary-container)' : 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
            fontWeight: copied ? 600 : 400,
          }}
        >
          <ToolBodyIcon name={copied ? 'check' : 'copy'} />
          {copied
            ? t('detail.tool.body.copied', '已复制')
            : t('detail.tool.body.copy', '复制')}
        </button>
      </div>
    </div>
  );
}
