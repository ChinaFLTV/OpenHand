import { useEffect, useMemo, useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { useTransientFlag } from '../hooks/useTransientFlag';
import { t, tFmt } from '../i18n';
import { parseJsonSafely } from '../shared/util/value';
import { copyTextToClipboard } from '../utils/clipboard';
import {
  DIALOG_OVERLAY_CENTER_CLASS,
  DIALOG_OVERLAY_TOP_Z_INDEX,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from './DialogFrame';

const JSON_TREE_MAX_CHARACTERS = 512 * 1024;
const JSON_TREE_MAX_NODES = 4096;
const JSON_TREE_MAX_DEPTH = 32;
const JSON_TREE_FULL_VIEW_MIN_CHARACTERS = 360;
const COPY_FEEDBACK_MS = 2000;

interface JsonDocument {
  value: Record<string, unknown> | unknown[];
  containerPaths: Set<string>;
}

export function StructuredJsonView({
  text,
  empty,
  error = false,
  label,
  enableFullView = true,
}: {
  text: string;
  empty?: string;
  error?: boolean;
  label?: string;
  enableFullView?: boolean;
}) {
  const document = useMemo(() => parseStructuredJsonDocument(text), [text]);
  const [expandedPaths, setExpandedPaths] = useState<Set<string>>(() => initialExpandedPaths(document));
  const [fullOpen, setFullOpen] = useState(false);
  const {
    active: copied,
    trigger: showCopied,
    reset: resetCopied,
  } = useTransientFlag(COPY_FEEDBACK_MS);
  const offersFullView = enableFullView && needsJsonFullView(text);

  useEffect(() => {
    setExpandedPaths(initialExpandedPaths(document));
    resetCopied();
  }, [document, resetCopied]);

  if (!text.trim()) {
    return empty ? <p class="oh-json-tree-empty"><span aria-hidden="true">i</span>{empty}</p> : null;
  }
  const value = document?.value;
  const count = value == null ? 0 : Array.isArray(value) ? value.length : Object.keys(value).length;
  const description = document == null
    ? tFmt('trajectory.structured.text', { count: text.length }, `Text · ${text.length} characters`)
    : Array.isArray(value)
      ? tFmt('trajectory.structured.array', { count }, `Array · ${count} items`)
      : tFmt('trajectory.structured.object', { count }, `Object · ${count} fields`);
  const allExpanded = document != null
    && [...document.containerPaths].every((path) => expandedPaths.has(path));
  const rootEntries = document == null ? [] : jsonEntries(document.value);
  const copy = async () => {
    if (!await copyTextToClipboard(text)) return;
    showCopied();
  };
  const toggle = (path: string) => setExpandedPaths((current) => {
    const next = new Set(current);
    if (next.has(path)) next.delete(path); else next.add(path);
    return next;
  });

  return (
    <section class={`oh-json-tree${error ? ' is-error' : ''}${label ? ' has-label' : ''}${offersFullView ? ' is-preview' : ''}`}>
      <header>
        <span class="oh-json-tree-type" aria-hidden="true">{document ? '{}' : 'T'}</span>
        {label ? <em class="oh-json-tree-label">{label}</em> : null}
        <strong title={description}>{description}</strong>
        {document && document.containerPaths.size > 1 ? (
          <button
            type="button"
            title={allExpanded ? t('trajectory.structured.collapseAll', '全部收起') : t('trajectory.structured.expandAll', '全部展开')}
            aria-label={allExpanded ? t('trajectory.structured.collapseAll', '全部收起') : t('trajectory.structured.expandAll', '全部展开')}
            onClick={() => setExpandedPaths(allExpanded ? new Set(['$']) : new Set(document.containerPaths))}
          >
            <UnfoldIcon collapse={allExpanded} />
          </button>
        ) : null}
        {offersFullView ? (
          <button
            type="button"
            title={t('trajectory.structured.showAll', '显示全部内容')}
            aria-label={t('trajectory.structured.showAll', '显示全部内容')}
            onClick={() => setFullOpen(true)}
          >
            <FullViewIcon />
          </button>
        ) : null}
        <button
          type="button"
          title={copied
            ? t('trajectory.structured.copied', '已复制')
            : document
              ? t('trajectory.structured.copyJson', '复制 JSON')
              : t('trajectory.structured.copyText', '复制文本')}
          aria-label={copied
            ? t('trajectory.structured.copied', '已复制')
            : document
              ? t('trajectory.structured.copyJson', '复制 JSON')
              : t('trajectory.structured.copyText', '复制文本')}
          onClick={() => void copy()}
          data-copied={copied ? 'true' : undefined}
        >
          {copied ? <CheckIcon /> : <CopyIcon />}
        </button>
      </header>
      {fullOpen ? (
        <StructuredJsonFullDialog
          text={text}
          label={label}
          error={error}
          onClose={() => setFullOpen(false)}
        />
      ) : null}
      {document ? (
        <div class="oh-json-tree-body" role="tree">
          {rootEntries.length ? rootEntries.map(([key, child], index) => (
              <JsonNode
                key={`$/${index}`}
                name={key}
                value={child}
                path={`$/${index}`}
                expandedPaths={expandedPaths}
                onToggle={toggle}
              />
            )) : <code class="oh-json-tree-empty-code">{Array.isArray(document.value) ? '[]' : '{}'}</code>}
        </div>
      ) : (
        <pre class="oh-json-tree-text">{text}</pre>
      )}
    </section>
  );
}

function needsJsonFullView(text: string): boolean {
  const trimmed = text.trim();
  if (trimmed.length >= JSON_TREE_FULL_VIEW_MIN_CHARACTERS) return true;
  return trimmed.endsWith('…') && trimmed.length >= 80;
}

function tryPrettyJsonText(text: string): string | null {
  const trimmed = text.trim();
  if (
    trimmed.length < 2
    || !((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']')))
  ) return null;
  const decoded = parseJsonSafely(trimmed);
  if (decoded == null) return null;
  try {
    return JSON.stringify(decoded, null, 2);
  } catch {
    return null;
  }
}

function StructuredJsonFullDialog({
  text,
  label,
  error = false,
  onClose,
}: {
  text: string;
  label?: string;
  error?: boolean;
  onClose: () => void;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const pretty = tryPrettyJsonText(text) ?? text;
  const title = label?.trim() || t('trajectory.structured.fullContent', '完整内容');
  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      {...createStandardDialogFrameAppearance({
        overlayClassName: DIALOG_OVERLAY_CENTER_CLASS,
        overlayTone: 'strong',
        overlayBlurPx: 5,
        overlayZIndex: DIALOG_OVERLAY_TOP_Z_INDEX,
        panelClassName: 'oh-json-full-dialog',
        panelBorder: 'outlineVariant',
        panelSurface: {
          width: 'min(880px, calc(100vw - 28px))',
          maxHeight: 'min(86dvh, 800px)',
          overflow: 'hidden',
        },
      })}
      ariaLabel={title}
    >
      <header class="oh-json-full-head">
        <span class="oh-json-full-head-icon" aria-hidden="true">{'{}'}</span>
        <div class="min-w-0 flex-1">
          <h2>{title}</h2>
          <p>{tFmt('trajectory.structured.fullHint', { count: text.trim().length }, `${text.trim().length} characters · scroll and copy`)}</p>
        </div>
        <button type="button" class="oh-json-full-close oh-tap-press" onClick={requestClose} aria-label={t('common.close', '关闭')}>
          <svg viewBox="0 0 24 24"><path d="m6 6 12 12M18 6 6 18" /></svg>
        </button>
      </header>
      <div class="oh-json-full-body oh-overlay-scroll">
        <StructuredJsonView text={pretty} error={error} label={label} enableFullView={false} />
      </div>
    </DialogFrame>
  );
}

function parseStructuredJsonDocument(text: string): JsonDocument | null {
  const trimmed = text.trim();
  if (
    trimmed.length < 2
    || trimmed.length > JSON_TREE_MAX_CHARACTERS
    || !((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']')))
  ) return null;
  const decoded = parseJsonSafely(trimmed);
  if (decoded == null || typeof decoded !== 'object') return null;

  const containerPaths = new Set<string>(['$']);
  const pending: Array<{ value: Record<string, unknown> | unknown[]; path: string; depth: number }> = [
    { value: decoded as Record<string, unknown> | unknown[], path: '$', depth: 0 },
  ];
  let nodes = 0;
  while (pending.length) {
    const current = pending.pop()!;
    if (current.depth > JSON_TREE_MAX_DEPTH) return null;
    const children = Array.isArray(current.value) ? current.value : Object.values(current.value);
    for (let index = 0; index < children.length; index += 1) {
      nodes += 1;
      if (nodes > JSON_TREE_MAX_NODES) return null;
      const child = children[index];
      if (
        child != null
        && typeof child === 'object'
        && (Array.isArray(child) ? child.length > 0 : Object.keys(child).length > 0)
      ) {
        const path = `${current.path}/${index}`;
        containerPaths.add(path);
        pending.push({
          value: child as Record<string, unknown> | unknown[],
          path,
          depth: current.depth + 1,
        });
      }
    }
  }
  return { value: decoded as Record<string, unknown> | unknown[], containerPaths };
}

function initialExpandedPaths(document: JsonDocument | null): Set<string> {
  const initial = new Set<string>(['$']);
  for (const path of document?.containerPaths ?? []) {
    if (path !== '$' && path.split('/').length === 2) initial.add(path);
  }
  return initial;
}

function jsonEntries(value: Record<string, unknown> | unknown[]): Array<[string, unknown]> {
  return Array.isArray(value)
    ? value.map((child, index) => [String(index), child])
    : Object.entries(value);
}

function JsonNode({
  name,
  value,
  path,
  expandedPaths,
  onToggle,
}: {
  name: string;
  value: unknown;
  path: string;
  expandedPaths: ReadonlySet<string>;
  onToggle: (path: string) => void;
}) {
  const container = value != null && typeof value === 'object';
  const entries = container ? jsonEntries(value as Record<string, unknown> | unknown[]) : [];
  const expandable = container && entries.length > 0;
  const expanded = expandable && expandedPaths.has(path);
  const valueClass = value === null ? 'is-null' : `is-${typeof value}`;
  const content = (
    <code>
      <span class="oh-json-tree-key">{JSON.stringify(name)}</span>
      <span class="oh-json-tree-punctuation">: </span>
      {container ? (
        <>
          <span class="oh-json-tree-punctuation">{
            Array.isArray(value)
              ? entries.length ? '[…]' : '[]'
              : entries.length ? '{…}' : '{}'
          }</span>
          {entries.length ? <span class="oh-json-tree-count">{entries.length}</span> : null}
        </>
      ) : (
        <span class={`oh-json-tree-value ${valueClass}`}>{stringifyJsonLeaf(value)}</span>
      )}
    </code>
  );
  return (
    <div class="oh-json-tree-node" role="treeitem" aria-expanded={expandable ? expanded : undefined}>
      {expandable ? (
        <button type="button" class="oh-json-tree-row" onClick={() => onToggle(path)}>
          <span class="oh-json-tree-chevron" aria-hidden="true">›</span>
          {content}
        </button>
      ) : (
        <div class="oh-json-tree-row is-leaf">
          <span class="oh-json-tree-bullet" aria-hidden="true" />
          {content}
        </div>
      )}
      {expandable ? (
        <div class={`oh-json-tree-children${expanded ? ' is-expanded' : ''}`}>
          <div role="group">
            {entries.map(([key, child], index) => (
              <JsonNode
                key={`${path}/${index}`}
                name={key}
                value={child}
                path={`${path}/${index}`}
                expandedPaths={expandedPaths}
                onToggle={onToggle}
              />
            ))}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function stringifyJsonLeaf(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return JSON.stringify(String(value));
  }
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="8" y="8" width="11" height="11" rx="2" />
      <path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" />
    </svg>
  );
}

function CheckIcon() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6" /></svg>;
}

function UnfoldIcon({ collapse }: { collapse: boolean }) {
  return collapse
    ? <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 10 5-5 5 5M7 14l5 5 5-5" /></svg>
    : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 8 5 5 5-5M7 16l5-5 5 5" /></svg>;
}

function FullViewIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M8 3H4v4M16 3h4v4M8 21H4v-4M16 21h4v-4" />
    </svg>
  );
}
