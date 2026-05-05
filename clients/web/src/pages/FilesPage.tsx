// FilesPage —— 工作区文件浏览 / 读取 / 编辑（受 service.workspaceFilesEnabled 控制）。
//
// 一比一对齐 legacy SPA：
// - 顶部面包屑 + 路径输入（手输跳转）
// - 左侧文件列表（含搜索 + type 过滤），右侧详情/编辑器
// - 写入需后端 write_enabled=true，否则保存按钮禁用
// - 二进制 / 超大文件按 ApiError 文案优雅退化

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useLocation } from 'preact-iso';
import { ApiError } from '../api/client';
import {
  WorkspaceItem,
  WorkspaceListResponse,
  listWorkspaceFiles,
  readWorkspaceFile,
  writeWorkspaceFile,
} from '../api/workspace';
import { t, tBytes, tDateTime } from '../i18n';
import { MenuSelect } from '../components/MenuSelect';

function parentOf(path: string): string {
  const trimmed = path.replace(/\/+$/, '');
  const idx = trimmed.lastIndexOf('/');
  return idx <= 0 ? '' : trimmed.slice(0, idx);
}

function describeApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const body = err.body as { error?: string } | null;
    return `HTTP ${err.status}${body?.error ? ` (${body.error})` : ''}`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
}

export function FilesPage() {
  const location = useLocation();

  const [path, setPath] = useState('');
  const [pathInput, setPathInput] = useState('');
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | 'file' | 'directory'>('all');
  const [list, setList] = useState<WorkspaceListResponse | null>(null);
  const [listLoading, setListLoading] = useState(false);
  const [listError, setListError] = useState<string | null>(null);

  const [selected, setSelected] = useState<WorkspaceItem | null>(null);
  const [content, setContent] = useState('');
  const [contentLoading, setContentLoading] = useState(false);
  const [contentError, setContentError] = useState<string | null>(null);
  const [contentMeta, setContentMeta] = useState<{ size: number; modified_at: string } | null>(null);
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saveOk, setSaveOk] = useState(false);
  const reqIdRef = useRef(0);

  const refresh = async () => {
    setListLoading(true);
    setListError(null);
    try {
      const res = await listWorkspaceFiles({
        path,
        q: query.trim(),
        type: typeFilter,
      });
      setList(res);
    } catch (err) {
      setListError(describeApiError(err));
      setList(null);
    } finally {
      setListLoading(false);
    }
  };

  // 初次进入 + path/query/type 变化时拉列表
  useEffect(() => {
    void refresh();
    setPathInput(path);
  }, [path, query, typeFilter]);

  const onOpenItem = (item: WorkspaceItem) => {
    if (item.type === 'directory') {
      setPath(item.path);
      setSelected(null);
      return;
    }
    setSelected(item);
    void loadContent(item);
  };

  const loadContent = async (item: WorkspaceItem) => {
    const myReq = ++reqIdRef.current;
    setContentLoading(true);
    setContentError(null);
    setContent('');
    setContentMeta(null);
    setDirty(false);
    setSaveError(null);
    setSaveOk(false);
    try {
      const res = await readWorkspaceFile(item.path);
      if (myReq !== reqIdRef.current) return;
      setContent(res.content);
      setContentMeta({ size: res.size, modified_at: res.modified_at });
    } catch (err) {
      if (myReq !== reqIdRef.current) return;
      setContentError(describeApiError(err));
    } finally {
      if (myReq === reqIdRef.current) setContentLoading(false);
    }
  };

  const handleSave = async () => {
    if (!selected || !list?.write_enabled || !selected.editable) return;
    setSaving(true);
    setSaveError(null);
    setSaveOk(false);
    try {
      const res = await writeWorkspaceFile(selected.path, content);
      setContentMeta({ size: res.size, modified_at: res.modified_at });
      setDirty(false);
      setSaveOk(true);
      setTimeout(() => setSaveOk(false), 2000);
    } catch (err) {
      setSaveError(describeApiError(err));
    } finally {
      setSaving(false);
    }
  };

  const onPathSubmit = (ev: Event) => {
    ev.preventDefault();
    setPath(pathInput.trim());
    setSelected(null);
  };

  const breadcrumbs = useMemo(() => {
    if (!path) return [{ name: '/', path: '' }];
    const parts = path.split('/').filter((p) => p.length > 0);
    const acc: { name: string; path: string }[] = [{ name: '/', path: '' }];
    let curr = '';
    for (const p of parts) {
      curr = curr ? `${curr}/${p}` : p;
      acc.push({ name: p, path: curr });
    }
    return acc;
  }, [path]);

  const writeDisabled = !list?.write_enabled || !selected?.editable;

  return (
    <main class="min-h-screen p-4 sm:p-6">
      <div class="max-w-7xl mx-auto">
        {/* 顶部 toolbar */}
        <header class="flex items-center justify-between gap-3 mb-4 flex-wrap">
          <div class="flex items-center gap-3">
            <button
              type="button"
              onClick={() => location.route('/')}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              ← {t('files.backHome', '返回首页')}
            </button>
            <h1 class="text-xl font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
              {t('files.title', '工作区文件')}
            </h1>
            {list && (
              <span class="text-xs font-mono" style={{ color: 'var(--m3-on-surface-variant)' }}>
                root: {list.root}
              </span>
            )}
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              onClick={() => void refresh()}
              class="text-sm px-3 py-1.5 rounded-m3-sm"
              style={{ color: 'var(--m3-on-surface-variant)', border: '1px solid var(--m3-outline)' }}
            >
              {t('common.refresh', '刷新')}
            </button>
          </div>
        </header>

        {/* 面包屑 + 路径输入 */}
        <div
          class="rounded-m3-md p-3 mb-3 flex items-center gap-2 flex-wrap"
          style={{ backgroundColor: 'var(--m3-surface-container)' }}
        >
          {breadcrumbs.map((b, i) => (
            <span key={`${b.path}-${i}`} class="flex items-center gap-2">
              {i > 0 && <span style={{ color: 'var(--m3-on-surface-variant)' }}>/</span>}
              <button
                type="button"
                onClick={() => {
                  setPath(b.path);
                  setSelected(null);
                }}
                class="text-sm hover:underline"
                style={{ color: 'var(--m3-primary)' }}
              >
                {b.name}
              </button>
            </span>
          ))}
          <span class="flex-1" />
          <form onSubmit={onPathSubmit} class="flex items-center gap-2">
            <input
              type="text"
              value={pathInput}
              onInput={(ev) => setPathInput((ev.target as HTMLInputElement).value)}
              placeholder={t('files.path.placeholder', '直接输入相对路径…')}
              class="text-sm px-2 py-1 rounded-m3-sm"
              style={{
                backgroundColor: 'var(--m3-surface)',
                border: '1px solid var(--m3-outline)',
                color: 'var(--m3-on-surface)',
                minWidth: '220px',
              }}
            />
            <button
              type="submit"
              class="text-xs px-2 py-1 rounded-m3-sm"
              style={{ color: 'var(--m3-on-primary)', backgroundColor: 'var(--m3-primary)' }}
            >
              {t('files.path.go', '跳转')}
            </button>
          </form>
        </div>

        {/* 列表 + 详情 */}
        <div class="grid grid-cols-1 lg:grid-cols-[380px_1fr] gap-3">
          {/* 左：列表 */}
          <section class="oh-appear-up rounded-m3-md p-3"
            style={{ backgroundColor: 'var(--m3-surface-container)' }}
          >
            <div class="flex items-center gap-2 mb-3">
              <input
                type="text"
                value={query}
                onInput={(ev) => setQuery((ev.target as HTMLInputElement).value)}
                placeholder={t('files.search.placeholder', '按文件名搜索…')}
                class="flex-1 text-sm px-2 py-1 rounded-m3-sm"
                style={{
                  backgroundColor: 'var(--m3-surface)',
                  border: '1px solid var(--m3-outline)',
                  color: 'var(--m3-on-surface)',
                }}
              />
              <MenuSelect
                value={typeFilter}
                onChange={(v) => setTypeFilter(v as 'all' | 'file' | 'directory')}
                minWidth={120}
                options={[
                  { value: 'all', label: t('files.type.all', '全部') },
                  { value: 'directory', label: t('files.type.directory', '目录') },
                  { value: 'file', label: t('files.type.file', '文件') },
                ]}
              />
            </div>

            {path && (
              <button
                type="button"
                onClick={() => {
                  setPath(parentOf(path));
                  setSelected(null);
                }}
                class="block w-full text-left px-2 py-1.5 rounded-m3-sm text-sm mb-1"
                style={{ color: 'var(--m3-on-surface-variant)', backgroundColor: 'var(--m3-surface)' }}
              >
                ../  ({t('files.parent', '上级目录')})
              </button>
            )}

            {listLoading && (
              <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('common.loading')}
              </p>
            )}
            {listError && (
              <p class="text-sm" style={{ color: 'var(--m3-error)' }}>
                {listError}
              </p>
            )}
            {!listLoading && !listError && list && list.items.length === 0 && (
              <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('files.empty', '该目录暂无内容')}
              </p>
            )}

            <ul class="flex flex-col gap-0.5 max-h-[60vh] overflow-y-auto">
              {list?.items.map((it) => {
                const isActive = selected?.path === it.path;
                return (
                  <li key={it.path}>
                    <button
                      type="button"
                      onClick={() => onOpenItem(it)}
                      class="w-full text-left px-2 py-1.5 rounded-m3-sm text-sm flex items-center gap-2"
                      style={{
                        backgroundColor: isActive ? 'var(--m3-primary)' : 'transparent',
                        color: isActive ? 'var(--m3-on-primary)' : 'var(--m3-on-surface)',
                      }}
                      title={it.path}
                    >
                      <span style={{ width: '16px' }}>{it.type === 'directory' ? '📁' : '📄'}</span>
                      <span class="flex-1 truncate font-mono">{it.name}</span>
                      <span
                        class="text-xs"
                        style={{
                          color: isActive ? 'var(--m3-on-primary)' : 'var(--m3-on-surface-variant)',
                        }}
                      >
                        {it.type === 'file' ? tBytes(it.size) : ''}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>

            {list && (
              <p class="mt-3 text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('files.writeEnabled', '可写入：')}
                {list.write_enabled ? '✅' : '❌'} ·{' '}
                {t('files.maxBytes', '单文件上限：')}
                {tBytes(list.max_file_bytes)}
              </p>
            )}
          </section>

          {/* 右：详情/编辑器 */}
          <section class="oh-appear-up rounded-m3-md p-3 flex flex-col"
            style={{ backgroundColor: 'var(--m3-surface-container)', minHeight: '60vh' }}
          >
            {!selected ? (
              <div class="flex-1 flex items-center justify-center">
                <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {t('files.selectHint', '从左侧选择一个文件以查看 / 编辑')}
                </p>
              </div>
            ) : (
              <>
                <header class="flex items-center justify-between gap-2 mb-2">
                  <div class="min-w-0">
                    <p class="text-sm font-mono truncate" style={{ color: 'var(--m3-on-surface)' }}>
                      {selected.path}
                    </p>
                    {contentMeta && (
                      <p class="text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                        {tBytes(contentMeta.size)} · {tDateTime(contentMeta.modified_at)}
                      </p>
                    )}
                  </div>
                  <div class="flex items-center gap-2">
                    {dirty && (
                      <span class="text-xs" style={{ color: 'var(--m3-error)' }}>
                        {t('files.dirty', '未保存')}
                      </span>
                    )}
                    {saveOk && (
                      <span class="text-xs" style={{ color: 'var(--m3-primary)' }}>
                        ✓ {t('files.saveOk', '已保存')}
                      </span>
                    )}
                    <button
                      type="button"
                      onClick={() => void handleSave()}
                      disabled={writeDisabled || !dirty || saving}
                      class="text-sm px-3 py-1.5 rounded-m3-sm"
                      style={{
                        color: 'var(--m3-on-primary)',
                        backgroundColor: 'var(--m3-primary)',
                        opacity: writeDisabled || !dirty || saving ? 0.5 : 1,
                      }}
                      title={writeDisabled ? t('files.writeDisabledHint', '该文件不可写入') : undefined}
                    >
                      {saving ? t('files.saving', '保存中…') : t('files.save', '保存')}
                    </button>
                  </div>
                </header>

                {contentLoading && (
                  <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
                    {t('common.loading')}
                  </p>
                )}
                {contentError && (
                  <p class="text-sm" style={{ color: 'var(--m3-error)' }}>
                    {contentError}
                  </p>
                )}
                {saveError && (
                  <p class="text-sm" style={{ color: 'var(--m3-error)' }}>
                    {saveError}
                  </p>
                )}

                {!contentLoading && !contentError && (
                  <textarea
                    value={content}
                    onInput={(ev) => {
                      setContent((ev.target as HTMLTextAreaElement).value);
                      setDirty(true);
                      setSaveOk(false);
                    }}
                    disabled={writeDisabled}
                    spellcheck={false}
                    class="flex-1 w-full p-2 text-sm font-mono rounded-m3-sm resize-none"
                    style={{
                      backgroundColor: 'var(--m3-surface)',
                      color: 'var(--m3-on-surface)',
                      border: '1px solid var(--m3-outline)',
                      minHeight: '50vh',
                    }}
                  />
                )}
              </>
            )}
          </section>
        </div>
      </div>
    </main>
  );
}
