// FilesPage —— 工作区文件浏览 / 读取 / 编辑。
//
// 一比一对齐 legacy SPA：
// - 顶部面包屑 + 路径输入（手输跳转）
// - 左侧文件列表（含搜索 + type 过滤），右侧详情/编辑器
// - 浏览 / 读取始终开放；创建 / 保存 / 删除需后端 write_enabled=true，否则按钮禁用
// - 二进制 / 超大文件按 ApiError 文案优雅退化

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';
import { ApiError } from '../api/client';
import {
  WorkspaceItem,
  WorkspaceListResponse,
  createWorkspaceDirectory,
  deleteWorkspaceFile,
  listWorkspaceFiles,
  readWorkspaceFile,
  writeWorkspaceFile,
} from '../api/workspace';
import { t, tBytes, tDateTime } from '../i18n';
import { MenuSelect } from '../components/MenuSelect';
import { CodeEditor } from '../components/CodeEditor';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { showSnackbar } from '../components/Snackbar';

function parentOf(path: string): string {
  const trimmed = path.replace(/\/+$/, '');
  const idx = trimmed.lastIndexOf('/');
  return idx <= 0 ? '' : trimmed.slice(0, idx);
}

function describeApiError(err: unknown): string {
  if (err instanceof ApiError) {
    const body = err.body as { error?: string; message?: string } | null;
    if (body?.message) return body.message;
    return `HTTP ${err.status}${body?.error ? ` (${body.error})` : ''}`;
  }
  if (err instanceof Error) return err.message;
  return String(err);
}

export function FilesPage() {
  const location = useAnimatedLocation();

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
  const [deleteTarget, setDeleteTarget] = useState<WorkspaceItem | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [creating, setCreating] = useState<null | 'file' | 'directory'>(null);
  const [createName, setCreateName] = useState('');
  const [createBusy, setCreateBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
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
      showSnackbar(`${t('files.saveOk', '已保存')}：${selected.path}`, { tone: 'success' });
      setTimeout(() => setSaveOk(false), 2000);
    } catch (err) {
      const message = describeApiError(err);
      setSaveError(message);
      showSnackbar(`${t('files.save.failed', '保存失败')}：${message}`, { tone: 'error' });
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
  const fileOperationsEnabled = Boolean(list?.operations_enabled ?? list?.write_enabled);

  const confirmDeleteTarget = async () => {
    const item = deleteTarget;
    if (!fileOperationsEnabled || !item || deleteBusy) return;
    setDeleteBusy(true);
    setActionError(null);
    try {
      await deleteWorkspaceFile(item.path);
      if (selected?.path === item.path) {
        setSelected(null);
        setContent('');
        setContentMeta(null);
      }
      setDeleteTarget(null);
      showSnackbar(`${t('files.delete.ok', '已删除')}：${item.path}`, { tone: 'success' });
      await refresh();
    } catch (err) {
      const message = describeApiError(err);
      setActionError(message);
      showSnackbar(`${t('files.delete.failed', '删除失败')}：${message}`, { tone: 'error' });
    } finally {
      setDeleteBusy(false);
    }
  };

  // 创建文件 / 目录：文件复用 PUT，目录走专用 mkdir API，避免 placeholder 文件污染。
  const handleCreate = async () => {
    if (!fileOperationsEnabled || !creating) return;
    const name = createName.trim();
    if (!name) return;
    setCreateBusy(true);
    setActionError(null);
    const createKind = creating;
    try {
      const targetPath = path ? `${path}/${name}` : name;
      if (createKind === 'directory') {
        await createWorkspaceDirectory(targetPath);
      } else {
        await writeWorkspaceFile(targetPath, '');
      }
      setCreating(null);
      setCreateName('');
      showSnackbar(
        `${
          createKind === 'directory'
            ? t('files.create.dirOk', '已创建目录')
            : t('files.create.fileOk', '已创建文件')
        }：${targetPath}`,
        { tone: 'success' },
      );
      await refresh();
    } catch (err) {
      const message = describeApiError(err);
      setActionError(message);
      showSnackbar(`${t('files.create.failed', '创建失败')}：${message}`, { tone: 'error' });
    } finally {
      setCreateBusy(false);
    }
  };

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
            {list ? (
              <span
                class="text-xs px-2 py-1 rounded-m3-sm"
                style={{
                  color: fileOperationsEnabled ? 'var(--m3-primary)' : 'var(--m3-on-surface-variant)',
                  border: '1px solid var(--m3-outline)',
                  background: 'var(--m3-surface)',
                }}
              >
                {fileOperationsEnabled
                  ? t('files.operations.enabled', '文件操作已开启')
                  : t('files.operations.readOnly', '只读浏览')}
              </span>
            ) : null}
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

            {/* 创建行：仅在 write_enabled 时显示。先点选 [文件]/[目录]，再输入名字回车 */}
            {fileOperationsEnabled ? (
              <div class="flex items-center gap-2 mb-2 flex-wrap">
                <button
                  type="button"
                  onClick={() => {
                    setCreating(creating === 'file' ? null : 'file');
                    setCreateName('');
                    setActionError(null);
                  }}
                  class="text-xs px-2 py-1 rounded-m3-sm"
                  style={{
                    color: creating === 'file' ? 'var(--m3-on-primary)' : 'var(--m3-primary)',
                    backgroundColor: creating === 'file' ? 'var(--m3-primary)' : 'transparent',
                    border: '1px solid var(--m3-primary)',
                  }}
                >
                  + {t('files.newFile', '新建文件')}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setCreating(creating === 'directory' ? null : 'directory');
                    setCreateName('');
                    setActionError(null);
                  }}
                  class="text-xs px-2 py-1 rounded-m3-sm"
                  style={{
                    color: creating === 'directory' ? 'var(--m3-on-primary)' : 'var(--m3-primary)',
                    backgroundColor: creating === 'directory' ? 'var(--m3-primary)' : 'transparent',
                    border: '1px solid var(--m3-primary)',
                  }}
                >
                  + {t('files.newDir', '新建目录')}
                </button>
                {creating && (
                  <form
                    onSubmit={(ev) => {
                      ev.preventDefault();
                      void handleCreate();
                    }}
                    class="flex-1 flex items-center gap-1 min-w-[160px]"
                  >
                    <input
                      type="text"
                      value={createName}
                      autoFocus
                      onInput={(ev) => setCreateName((ev.target as HTMLInputElement).value)}
                      placeholder={
                        creating === 'file'
                          ? t('files.newFile.placeholder', '新文件名…')
                          : t('files.newDir.placeholder', '新目录名…')
                      }
                      class="flex-1 text-xs px-2 py-1 rounded-m3-sm"
                      style={{
                        backgroundColor: 'var(--m3-surface)',
                        border: '1px solid var(--m3-outline)',
                        color: 'var(--m3-on-surface)',
                      }}
                    />
                    <button
                      type="submit"
                      disabled={createBusy || !createName.trim()}
                      class="text-xs px-2 py-1 rounded-m3-sm"
                      style={{
                        color: 'var(--m3-on-primary)',
                        backgroundColor: 'var(--m3-primary)',
                        opacity: createBusy || !createName.trim() ? 0.5 : 1,
                      }}
                    >
                      {createBusy ? t('files.creating', '创建中…') : t('files.create', '创建')}
                    </button>
                  </form>
                )}
              </div>
            ) : list ? (
              <div
                class="mb-2 rounded-m3-sm px-3 py-2 text-xs leading-snug"
                style={{
                  backgroundColor: 'var(--m3-surface)',
                  border: '1px solid var(--m3-outline)',
                  color: 'var(--m3-on-surface-variant)',
                }}
              >
                {t(
                  'files.operations.disabledHint',
                  '项目文件浏览与读取已开放；创建、保存、删除需要在 App 端 Web 通用消息平台里开启“是否支持操作文件”。',
                )}
              </div>
            ) : null}
            {actionError && (
              <p class="text-xs mb-2" style={{ color: 'var(--m3-error)' }}>
                {actionError}
              </p>
            )}

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
                  <li key={it.path} class="flex items-center gap-1">
                    <button
                      type="button"
                      onClick={() => onOpenItem(it)}
                      class="flex-1 min-w-0 text-left px-2 py-1.5 rounded-m3-sm text-sm flex items-center gap-2"
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
                    {fileOperationsEnabled && (
                      <button
                        type="button"
                        onClick={() => {
                          setActionError(null);
                          setDeleteTarget(it);
                        }}
                        disabled={deleteBusy}
                        title={t('files.delete', '删除')}
                        class="text-xs px-1.5 py-1 rounded-m3-sm shrink-0"
                        style={{
                          color: 'var(--m3-on-surface-variant)',
                          backgroundColor: 'transparent',
                          border: '1px solid var(--m3-outline)',
                          opacity: deleteBusy ? 0.55 : 1,
                        }}
                      >
                        🗑
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>

            {list && (
              <p class="mt-3 text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
                {t('files.writeEnabled', '可写入：')}
                {fileOperationsEnabled ? '✅' : '❌'} ·{' '}
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

                {!contentLoading && !contentError && selected && (
                  <div
                    class="flex-1 w-full"
                    style={{ minHeight: '50vh', display: 'flex' }}
                  >
                    <CodeEditor
                      key={selected.path}
                      value={content}
                      filename={selected.path}
                      readOnly={writeDisabled}
                      onChange={(next) => {
                        setContent(next);
                        setDirty(true);
                        setSaveOk(false);
                      }}
                    />
                  </div>
                )}
              </>
            )}
          </section>
        </div>
      </div>
      {deleteTarget ? (
        <ConfirmDialog
          title={t('files.delete.confirmTitle', '删除此项目?')}
          body={`${t('files.delete.confirmBody', '确定删除此文件或空目录?此操作不可恢复。')} ${deleteTarget.path}`}
          danger
          busy={deleteBusy}
          confirmLabel={deleteBusy ? t('files.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => {
            if (!deleteBusy) setDeleteTarget(null);
          }}
          onConfirm={confirmDeleteTarget}
        />
      ) : null}
    </main>
  );
}
