// 模型选择弹窗 (1:1 对齐 App 端 lib/shared/widgets/model_search_selector.dart):
// - 搜索框自动聚焦, 多空格 token 全部命中才匹配
// - 「最近使用」分组置顶 (持久化到 localStorage)
// - 按 provider+protocol 分组, 当前激活模型加 check icon
// - Enter 直接选中第一个匹配
// - 弹窗 420×520, 圆角 16, M3 风格

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ApiMetaModel } from '../api/meta';
import { t } from '../i18n';

const RECENT_KEY = 'openhand.web.recent_models';
const RECENT_MAX = 6;

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
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // ESC 关闭
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return models;
    const terms = q.split(/\s+/);
    return models.filter((m) => {
      const text = `${m.key} ${m.label} ${m.provider}`.toLowerCase();
      return terms.every((t) => text.includes(t));
    });
  }, [query, models]);

  const grouped = useMemo(() => {
    const map = new Map<string, ApiMetaModel[]>();
    for (const m of filtered) {
      const k = m.provider;
      const arr = map.get(k) ?? [];
      arr.push(m);
      map.set(k, arr);
    }
    return [...map.entries()];
  }, [filtered]);

  const recentKeys = useMemo(() => readRecent().map((r) => r.key), []);
  const recent = useMemo(() => {
    if (query.trim()) return [];
    return recentKeys
      .map((k) => filtered.find((m) => m.key === k))
      .filter((m): m is ApiMetaModel => !!m)
      .slice(0, RECENT_MAX);
  }, [filtered, recentKeys, query]);

  function handleSelect(key: string) {
    pushRecentModel(key);
    onSelect(key);
    onClose();
  }

  function handleSubmit() {
    if (filtered.length > 0) handleSelect(filtered[0]!.key);
  }

  return (
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      style={{
        background: 'rgba(0, 0, 0, 0.42)',
      }}
      onClick={(ev) => {
        if (ev.target === ev.currentTarget) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        class="oh-appear-up flex flex-col"
        style={{
          width: 'min(440px, 92vw)',
          maxHeight: 'min(560px, 86vh)',
          background: 'var(--m3-surface)',
          borderRadius: '16px',
          boxShadow: 'var(--m3-elev-3)',
          overflow: 'hidden',
        }}
      >
        <div class="px-4 pt-4 pb-2">
          <input
            ref={inputRef}
            type="text"
            value={query}
            onInput={(e) => setQuery((e.currentTarget as HTMLInputElement).value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                handleSubmit();
              }
            }}
            placeholder={t('modelPicker.search', '搜索模型…')}
            class="w-full text-sm px-3 py-2 rounded-md"
            style={{
              background: 'var(--m3-surface-container)',
              color: 'var(--m3-on-surface)',
              border: '1px solid var(--m3-outline)',
            }}
          />
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
        <div class="flex-1 overflow-y-auto pb-2" style={{ minHeight: 0 }}>
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
                  onPick={handleSelect}
                />
              ) : null}
              {grouped.map(([groupName, items]) => (
                <Section
                  key={groupName}
                  label={groupName}
                  items={items}
                  selectedKey={selectedKey}
                  onPick={handleSelect}
                />
              ))}
            </>
          )}
        </div>
        <footer
          class="flex justify-end gap-2 px-4 py-3"
          style={{ borderTop: '1px solid var(--m3-outline)' }}
        >
          <button
            type="button"
            onClick={onClose}
            class="oh-tap-press text-sm px-3 py-1.5 rounded-m3-sm"
            style={{
              color: 'var(--m3-on-surface-variant)',
              border: '1px solid var(--m3-outline)',
            }}
          >
            {t('common.cancel', '取消')}
          </button>
        </footer>
      </div>
    </div>
  );
}

function Section({
  label,
  items,
  selectedKey,
  onPick,
}: {
  label: string;
  items: ApiMetaModel[];
  selectedKey: string;
  onPick(key: string): void;
}) {
  return (
    <div>
      <p
        class="text-xs px-4 pt-2 pb-0.5 uppercase tracking-wide"
        style={{
          color: 'var(--m3-on-surface-variant)',
          fontWeight: 600,
          letterSpacing: '0.04em',
        }}
      >
        {label}
      </p>
      {items.map((m) => {
        const active = m.key === selectedKey;
        return (
          <button
            key={m.key}
            type="button"
            onClick={() => onPick(m.key)}
            class="w-full text-left px-4 py-2 flex items-center gap-3 oh-tap-press"
            style={{
              background: active
                ? 'color-mix(in srgb, var(--m3-primary) 12%, transparent)'
                : 'transparent',
              color: active ? 'var(--m3-primary)' : 'var(--m3-on-surface)',
              fontWeight: active ? 600 : 400,
            }}
          >
            <span
              aria-hidden
              style={{
                width: '18px',
                height: '18px',
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
                  ✓
                </span>
              ) : null}
            </span>
            <span class="flex-1 truncate text-sm">{m.label || m.key}</span>
            <span
              class="text-xs flex-none"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {m.provider}
            </span>
          </button>
        );
      })}
    </div>
  );
}
