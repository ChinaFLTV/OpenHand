// 模型选择弹窗 (1:1 对齐 App 端 lib/shared/ui/model_search_selector.dart):
// - 搜索框自动聚焦, 多空格 token 全部命中才匹配
// - 「最近使用」分组置顶 (持久化到 localStorage)
// - 按 provider+protocol 分组, 当前激活模型加 check/radio icon
// - Enter 直接选中第一个匹配
// - 弹窗 420×520, 无 footer, M3 风格

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel } from '../api/meta';
import { t } from '../i18n';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { OverlayPortal } from './OverlayPortal';

const RECENT_KEY = 'openhand.web.recent_models';
const RECENT_MAX = 6;

type ModelPickerIconName = 'close' | 'check' | 'search';

function ModelPickerIcon({ name, size = 16 }: { name: ModelPickerIconName; size?: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 2,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    focusable: 'false',
    'aria-hidden': true,
  };
  switch (name) {
    case 'close':
      return <svg {...common}><path d="M7 7l10 10M17 7 7 17" /></svg>;
    case 'check':
      return <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
    case 'search':
      return <svg {...common}><circle cx="11" cy="11" r="6" /><path d="m16 16 4 4" /></svg>;
  }
}

interface RecentEntry {
  key: string;
  ts: number;
}

function readRecent(): RecentEntry[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY);
    if (!raw) return [];
    const arr = JSON.parse(raw) as RecentEntry[];
    return Array.isArray(arr) ? arr : [];
  } catch {
    return [];
  }
}

export function pushRecentModel(modelKey: string): void {
  if (!modelKey) return;
  const next: RecentEntry[] = [
    { key: modelKey, ts: Date.now() },
    ...readRecent().filter((r) => r.key !== modelKey),
  ].slice(0, RECENT_MAX);
  try {
    localStorage.setItem(RECENT_KEY, JSON.stringify(next));
  } catch {
    // quota / private mode — ignore
  }
}

export interface ModelPickerDialogProps {
  models: ApiMetaModel[];
  selectedKey: string;
  onSelect(key: string): void;
  onClose(): void;
}

export function ModelPickerDialog({
  models,
  selectedKey,
  onSelect,
  onClose,
}: ModelPickerDialogProps) {
  const [query, setQuery] = useState('');
  const [highlightKey, setHighlightKey] = useState<string>(selectedKey);
  const [inputFocused, setInputFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const listRef = useRef<HTMLDivElement | null>(null);
  const { closing, requestClose } = useDialogExitMotion(onClose);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // ESC 关闭
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') requestClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [requestClose]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return models;
    const terms = q.split(/\s+/);
    return models.filter((m) => {
      const text = `${m.key} ${m.label} ${m.provider} ${m.protocol ?? ''} ${m.model_id}`.toLowerCase();
      return terms.every((t) => text.includes(t));
    });
  }, [query, models]);

  const grouped = useMemo(() => {
    const map = new Map<string, { label: string; items: ApiMetaModel[] }>();
    for (const m of filtered) {
      const protocol = m.protocol ?? '';
      const label = protocol ? `${m.provider}  (${protocol})` : m.provider;
      const key = `${m.provider}\u0000${protocol}`;
      const group = map.get(key) ?? { label, items: [] };
      group.items.push(m);
      map.set(key, group);
    }
    return [...map.entries()].map(([key, group]) => ({ key, ...group }));
  }, [filtered]);

  const recentKeys = useMemo(() => readRecent().map((r) => r.key), []);
  const recent = useMemo(() => {
    if (query.trim()) return [];
    return recentKeys
      .map((k) => filtered.find((m) => m.key === k))
      .filter((m): m is ApiMetaModel => !!m)
      .slice(0, RECENT_MAX);
  }, [filtered, recentKeys, query]);

  // 顺序：最近使用 → 各分组 (filtered)；用于键盘导航。
  const orderedKeys = useMemo(() => {
    const out: string[] = [];
    const seen = new Set<string>();
    for (const m of recent) {
      if (!seen.has(m.key)) {
        out.push(m.key);
        seen.add(m.key);
      }
    }
    for (const group of grouped) {
      for (const m of group.items) {
        if (!seen.has(m.key)) {
          out.push(m.key);
          seen.add(m.key);
        }
      }
    }
    return out;
  }, [recent, grouped]);

  // query 变化后高亮第一个候选；初始保持选中模型。
  useEffect(() => {
    if (!query.trim()) {
      setHighlightKey(selectedKey);
      return;
    }
    if (orderedKeys.length > 0 && !orderedKeys.includes(highlightKey)) {
      setHighlightKey(orderedKeys[0]!);
    }
  }, [query, orderedKeys, selectedKey, highlightKey]);

  function handleSelect(key: string) {
    pushRecentModel(key);
    onSelect(key);
    requestClose();
  }

  function handleSubmit() {
    const target = orderedKeys.includes(highlightKey)
      ? highlightKey
      : (orderedKeys[0] ?? '');
    if (target) handleSelect(target);
  }

  function moveHighlight(delta: 1 | -1) {
    if (orderedKeys.length === 0) return;
    const cur = orderedKeys.indexOf(highlightKey);
    const next =
      cur < 0
        ? (delta === 1 ? 0 : orderedKeys.length - 1)
        : (cur + delta + orderedKeys.length) % orderedKeys.length;
    const nextKey = orderedKeys[next]!;
    setHighlightKey(nextKey);
    requestAnimationFrame(() => {
      const el = listRef.current?.querySelector<HTMLButtonElement>(
        `[data-model-key="${CSS.escape(nextKey)}"]`,
      );
      el?.scrollIntoView({ block: 'nearest' });
    });
  }

  const node = (
    <div
      class={`${closing ? 'oh-dialog-fade-out' : 'oh-dialog-fade-in'} fixed inset-0 flex items-center justify-center`}
      style={{
        background: 'rgba(0, 0, 0, 0.38)',
        backdropFilter: 'blur(2px)',
        zIndex: 2800,
      }}
      onClick={(ev) => {
        if (ev.target === ev.currentTarget) requestClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} flex flex-col`}
        style={{
          width: 'min(420px, 92vw)',
          maxHeight: 'min(520px, 86vh)',
          background: 'var(--m3-surface-container)',
          borderRadius: '16px',
          boxShadow: 'var(--m3-elev-3)',
          overflow: 'hidden',
        }}
      >
        <div class="px-4 py-4">
          <div class="relative">
            <span
              aria-hidden
              class="absolute left-3 top-1/2 -translate-y-1/2 text-sm inline-flex items-center justify-center rounded-full"
              style={{
                width: 28,
                height: 28,
                color: inputFocused ? 'var(--m3-primary)' : 'var(--m3-on-surface-variant)',
                background: inputFocused
                  ? 'color-mix(in srgb, var(--m3-primary) 12%, transparent)'
                  : 'color-mix(in srgb, var(--m3-on-surface-variant) 8%, transparent)',
                transition: 'background-color 180ms var(--oh-motion-emphasized), color 180ms var(--oh-motion-emphasized)',
              }}
            >
              <ModelPickerIcon name="search" size={15} />
            </span>
            <input
              ref={inputRef}
              type="text"
              value={query}
              onInput={(e) => setQuery((e.currentTarget as HTMLInputElement).value)}
              onFocus={() => setInputFocused(true)}
              onBlur={() => setInputFocused(false)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handleSubmit();
                } else if (e.key === 'ArrowDown') {
                  e.preventDefault();
                  moveHighlight(1);
                } else if (e.key === 'ArrowUp') {
                  e.preventDefault();
                  moveHighlight(-1);
                }
              }}
              placeholder={t('modelPicker.search', '搜索模型…')}
              class="w-full text-base py-3 rounded-m3-md"
              style={{
                minHeight: 56,
                paddingLeft: '48px',
                paddingRight: query.trim() ? '44px' : '18px',
                background: inputFocused
                  ? 'var(--m3-surface)'
                  : 'color-mix(in srgb, var(--m3-surface) 82%, var(--m3-surface-container))',
                color: 'var(--m3-on-surface)',
                border: inputFocused
                  ? '2px solid var(--m3-primary)'
                  : '1px solid color-mix(in srgb, var(--m3-outline) 72%, transparent)',
                boxShadow: inputFocused
                  ? '0 0 0 4px color-mix(in srgb, var(--m3-primary) 14%, transparent)'
                  : 'inset 0 1px 0 rgba(255,255,255,0.42)',
                outline: 'none',
                transition: 'border-color 180ms var(--oh-motion-emphasized), box-shadow 220ms var(--oh-motion-emphasized), background-color 180ms var(--oh-motion-emphasized)',
              }}
            />
            {query.trim() ? (
              <button
                type="button"
                onClick={() => setQuery('')}
                class="oh-tap-press absolute right-3 top-1/2 -translate-y-1/2 w-8 h-8 rounded-full"
                style={{
                  color: 'var(--m3-on-surface-variant)',
                  background: 'color-mix(in srgb, var(--m3-on-surface-variant) 10%, transparent)',
                }}
                aria-label={t('common.clear', '清空')}
              >
                <ModelPickerIcon name="close" />
              </button>
            ) : null}
          </div>
          {query.trim() ? (
            <p
              class="text-xs mt-2"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {t('modelPicker.count', '匹配 ')}
              {filtered.length} / {models.length}
            </p>
          ) : null}
        </div>
        <div class="flex-1 overflow-y-auto pb-2" style={{ minHeight: 0 }} ref={listRef}>
          {models.length === 0 ? (
            <p
              class="text-sm text-center py-12 px-6"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {t('modelPicker.empty', '主控制台未配置模型')}
            </p>
          ) : filtered.length === 0 ? (
            <p
              class="text-sm text-center py-12 px-6"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {t('modelPicker.noMatch', '无匹配模型')}
            </p>
          ) : (
            <>
              {recent.length > 0 ? (
                <Section
                  label={t('modelPicker.recent', '最近使用')}
                  items={recent}
                  selectedKey={selectedKey}
                  highlightKey={highlightKey}
                  onPick={handleSelect}
                  onHover={setHighlightKey}
                  showProviderSubtitle
                />
              ) : null}
              {grouped.length > 0 ? (
                <p
                  class="text-xs px-4 pt-3 pb-0.5"
                  style={{
                    color: 'var(--m3-on-surface-variant)',
                    fontWeight: 700,
                    letterSpacing: 0,
                  }}
                >
                  {t('modelPicker.available', '可用模型')}
                </p>
              ) : null}
              {grouped.map((group) => (
                <Section
                  key={group.key}
                  label={group.label}
                  items={group.items}
                  selectedKey={selectedKey}
                  highlightKey={highlightKey}
                  onPick={handleSelect}
                  onHover={setHighlightKey}
                />
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  );

  return <OverlayPortal>{node}</OverlayPortal>;
}

function Section({
  label,
  items,
  selectedKey,
  highlightKey,
  onPick,
  onHover,
  showProviderSubtitle = false,
}: {
  label: string;
  items: ApiMetaModel[];
  selectedKey: string;
  highlightKey: string;
  onPick(key: string): void;
  onHover(key: string): void;
  /** 「最近使用」分组下显示 provider+protocol 副标题，避免不同服务商的同名模型混淆。 */
  showProviderSubtitle?: boolean;
}) {
  return (
    <div>
      <p
        class="text-xs px-4 pt-2 pb-0.5"
        style={{
          color: 'var(--m3-on-surface-variant)',
          fontWeight: 600,
          letterSpacing: 0,
        }}
      >
        {label}
      </p>
      {items.map((m) => {
        const active = m.key === selectedKey;
        const highlighted = m.key === highlightKey && !active;
        return (
          <button
            key={m.key}
            type="button"
            data-model-key={m.key}
            onClick={() => onPick(m.key)}
            onMouseEnter={() => onHover(m.key)}
            class="w-full text-left px-4 py-2 flex items-center gap-3 oh-tap-press"
            style={{
              background: active
                ? 'var(--m3-primary-container)'
                : highlighted
                  ? 'color-mix(in srgb, var(--m3-primary) 6%, transparent)'
                  : 'transparent',
              color: active ? 'var(--m3-on-primary-container)' : 'var(--m3-on-surface)',
              fontWeight: active ? 600 : 400,
            }}
          >
            <span
              aria-hidden
              style={{
                width: '20px',
                height: '20px',
                borderRadius: '50%',
                border: `2px solid ${active ? 'var(--m3-primary)' : 'var(--m3-outline)'}`,
                background: active ? 'var(--m3-primary)' : 'transparent',
                flex: 'none',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {active ? (
                <span
                  style={{
                    color: 'var(--m3-on-primary)',
                    fontSize: '12px',
                    lineHeight: 1,
                  }}
                >
                  <ModelPickerIcon name="check" size={12} />
                </span>
              ) : null}
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-sm truncate" style={{ fontWeight: active ? 600 : 500 }}>
                {m.model_id || m.label || m.key}
              </span>
              {showProviderSubtitle ? (
                <span
                  class="block text-[11px] truncate"
                  style={{
                    color: active
                      ? 'color-mix(in srgb, var(--m3-on-primary-container) 78%, transparent)'
                      : 'var(--m3-on-surface-variant)',
                    marginTop: 1,
                  }}
                >
                  {m.protocol ? `${m.provider}  (${m.protocol})` : m.provider}
                </span>
              ) : null}
            </span>
          </button>
        );
      })}
    </div>
  );
}
