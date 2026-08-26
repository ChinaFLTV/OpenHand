// FilesPage —— 工作区文件浏览 / 读取 / 编辑。
//
// - 顶部面包屑 + 路径输入（手输跳转）
// - 左侧文件列表（含搜索 + type 过滤），右侧详情/编辑器
// - 浏览 / 读取始终开放；创建 / 保存 / 删除需后端 write_enabled=true，否则按钮禁用
// - 二进制 / 超大文件按 ApiError 文案优雅退化

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import {
  type WorkspaceItem,
  type WorkspaceListResponse,
  createWorkspaceDirectory,
  deleteWorkspaceFile,
  listWorkspaceFiles,
  readWorkspaceFile,
  writeWorkspaceFile,
} from '../../../api/workspace';
import { t, tBytes, tDateTime } from '../../../i18n';
import { MenuSelect } from '../../../components/MenuSelect';
import { CodeEditor } from '../../../components/CodeEditor';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import { showSnackbar } from '../../../components/Snackbar';
import { useReducedMotion } from '../../../hooks/useReducedMotion';
import { useTransientFlag } from '../../../hooks/useTransientFlag';
import { TopBar } from '../../../components/TopBar';
import { describeApiError } from '../../../utils/api_error';

const SAVE_OK_RESET_MS = 2_000;

function parentOf(path: string): string {
  const trimmed = path.replace(/\/+$/, '');
  const idx = trimmed.lastIndexOf('/');
  return idx <= 0 ? '' : trimmed.slice(0, idx);
}

export function FilesPage() {
  const location = useAnimatedLocation();
  const reduceMotion = useReducedMotion();

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
  const {
    active: saveOk,
    trigger: showSaveOk,
    reset: resetSaveOk,
  } = useTransientFlag(SAVE_OK_RESET_MS);
  const [deleteTarget, setDeleteTarget] = useState<WorkspaceItem | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [creating, setCreating] = useState<null | 'file' | 'directory'>(null);
  const [createName, setCreateName] = useState('');
  const [createBusy, setCreateBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const reqIdRef = useRef(0);
  const detailSectionRef = useRef<HTMLElement | null>(null);
  const detailScrollFrameRef = useRef<number | null>(null);

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

  useEffect(() => () => {
    if (detailScrollFrameRef.current != null) {
      window.cancelAnimationFrame(detailScrollFrameRef.current);
      detailScrollFrameRef.current = null;
    }
  }, []);

  const onOpenItem = (item: WorkspaceItem) => {
    if (item.type === 'directory') {
      setPath(item.path);
      setSelected(null);
      return;
    }
    setSelected(item);
    void loadContent(item);
    if (typeof window !== 'undefined' && !window.matchMedia('(min-width: 1024px)').matches) {
      if (detailScrollFrameRef.current != null) {
        window.cancelAnimationFrame(detailScrollFrameRef.current);
      }
      detailScrollFrameRef.current = window.requestAnimationFrame(() => {
        detailScrollFrameRef.current = null;
        detailSectionRef.current?.scrollIntoView({
          behavior: reduceMotion ? 'auto' : 'smooth',
          block: 'start',
        });
      });
    }
  };

  const loadContent = async (item: WorkspaceItem) => {
    const myReq = ++reqIdRef.current;
    setContentLoading(true);
    setContentError(null);
    setContent('');
    setContentMeta(null);
    setDirty(false);
    setSaveError(null);
    resetSaveOk();
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
    resetSaveOk();
    try {
      const res = await writeWorkspaceFile(selected.path, content);
      setContentMeta({ size: res.size, modified_at: res.modified_at });
      setDirty(false);
      showSaveOk();
      showSnackbar(`${t('files.saveOk', '已保存')}：${selected.path}`, { tone: 'success' });
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

  const confirmDeleteTarget = async (): Promise<boolean> => {
    const item = deleteTarget;
    if (!fileOperationsEnabled || !item || deleteBusy) return false;
    setDeleteBusy(true);
    setActionError(null);
    try {
      await deleteWorkspaceFile(item.path);
      if (selected?.path === item.path) {
        setSelected(null);
        setContent('');
        setContentMeta(null);
      }
      showSnackbar(`${t('files.delete.ok', '已删除')}：${item.path}`, { tone: 'success' });
      await refresh();
      return true;
    } catch (err) {
      const message = describeApiError(err);
      setActionError(message);
      showSnackbar(`${t('files.delete.failed', '删除失败')}：${message}`, { tone: 'error' });
      return false;
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
    <main class="oh-files-page min-h-screen p-4 sm:p-6">
      <div class="max-w-7xl mx-auto">
        <TopBar
          title={t('files.title', '工作区文件')}
          subtitle={list ? `root: ${list.root}` : t('files.subtitle.loading', '正在加载工作区根目录…')}
          hideNav
          leadingSlot={(
            <button
              type="button"
              onClick={() => location.route('/')}
              class="oh-tap-press oh-topbar-action text-sm rounded-m3-sm px-3 py-1.5"
            >
              ← {t('files.backHome', '返回首页')}
            </button>
          )}
          actionSlot={(
            <>
              {list ? (
                <span
                  class={`oh-files-mode-pill${fileOperationsEnabled ? ' is-writeable' : ''}`}
                >
                  {fileOperationsEnabled
                    ? t('files.operations.enabled', '文件操作已开启')
                    : t('files.operations.readOnly', '只读浏览')}
                </span>
              ) : null}
              <button
                type="button"
                onClick={() => void refresh()}
                class="oh-tap-press oh-topbar-action text-sm rounded-m3-sm px-3 py-1.5"
              >
                {t('common.refresh', '刷新')}
              </button>
            </>
          )}
        />

        {/* 面包屑 + 路径输入 */}
        <div class="oh-files-path-card mb-3">
          {breadcrumbs.map((b, i) => (
            <span key={`${b.path}-${i}`} class="flex items-center gap-2">
              {i > 0 && <span class="oh-files-path-separator">/</span>}
              <button
                type="button"
                onClick={() => {
                  setPath(b.path);
                  setSelected(null);
                }}
                class="oh-files-breadcrumb"
              >
                {b.name}
              </button>
            </span>
          ))}
          <span class="flex-1" />
          <form onSubmit={onPathSubmit} class="oh-files-path-form">
            <input
              type="text"
              value={pathInput}
              onInput={(ev) => setPathInput((ev.target as HTMLInputElement).value)}
              placeholder={t('files.path.placeholder', '直接输入相对路径…')}
              class="oh-files-input"
            />
            <button
              type="submit"
              class="oh-tap-press oh-files-primary-button"
            >
              {t('files.path.go', '跳转')}
            </button>
          </form>
        </div>

        {/* 列表 + 详情 */}
        <div class="grid grid-cols-1 lg:grid-cols-[380px_1fr] gap-3">
          {/* 左：列表 */}
          <section class="oh-appear-up oh-files-panel">
            <div class="oh-files-panel-heading">
              <span>{t('files.list.heading', '当前目录')}</span>
              {list ? <span>{list.items.length}</span> : null}
            </div>
            <div class="flex items-center gap-2 mb-3">
              <input
                type="text"
                value={query}
                onInput={(ev) => setQuery((ev.target as HTMLInputElement).value)}
                placeholder={t('files.search.placeholder', '按文件名搜索…')}
                class="oh-files-input flex-1"
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
              <div class="oh-files-create-row">
                <button
                  type="button"
                  onClick={() => {
                    setCreating(creating === 'file' ? null : 'file');
                    setCreateName('');
                    setActionError(null);
                  }}
                  class={`oh-tap-press oh-files-secondary-button${creating === 'file' ? ' is-active' : ''}`}
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
                  class={`oh-tap-press oh-files-secondary-button${creating === 'directory' ? ' is-active' : ''}`}
                >
                  + {t('files.newDir', '新建目录')}
                </button>
                {creating && (
                  <form
                    onSubmit={(ev) => {
                      ev.preventDefault();
                      void handleCreate();
                    }}
                    class="flex-1 flex items-center gap-2 min-w-[180px]"
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
                      class="oh-files-input flex-1"
                    />
                    <button
                      type="submit"
                      disabled={createBusy || !createName.trim()}
                      class="oh-tap-press oh-files-primary-button"
                    >
                      {createBusy ? t('files.creating', '创建中…') : t('files.create', '创建')}
                    </button>
                  </form>
                )}
              </div>
            ) : list ? (
              <div class="oh-files-notice">
                {t(
                  'files.operations.disabledHint',
                  '项目文件浏览与读取已开放；创建、保存、删除需要在 App 端 Web 通用消息平台里开启“是否支持操作文件”。',
                )}
              </div>
            ) : null}
            {actionError && (
              <p class="text-xs mb-2 oh-text-error">
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
                class="oh-files-parent-row"
              >
                ../  ({t('files.parent', '上级目录')})
              </button>
            )}

            {listLoading && (
              <p class="text-sm oh-text-muted">
                {t('common.loading')}
              </p>
            )}
            {listError && (
              <p class="text-sm oh-text-error">
                {listError}
              </p>
            )}
            {!listLoading && !listError && list && list.items.length === 0 && (
              <p class="text-sm oh-text-muted">
                {t('files.empty', '该目录暂无内容')}
              </p>
            )}

            <ul class="oh-files-list">
              {list?.items.map((it) => {
                const isActive = selected?.path === it.path;
                return (
                  <li key={it.path} class="oh-files-list-item">
                    <button
                      type="button"
                      onClick={() => onOpenItem(it)}
                      class={`oh-files-row${isActive ? ' is-active' : ''}`}
                      title={it.path}
                    >
                      <span class="oh-files-kind">{it.type === 'directory' ? 'DIR' : 'FILE'}</span>
                      <span class="oh-files-name">{it.name}</span>
                      <span class="oh-files-size">
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
                        class="oh-tap-press oh-files-delete-button"
                      >
                        {t('files.delete', '删除')}
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>

            {list && (
              <p class="oh-files-footnote">
                {t('files.writeEnabled', '可写入：')}
                {fileOperationsEnabled ? t('common.on', '开启') : t('common.off', '关闭')} ·{' '}
                {t('files.maxBytes', '单文件上限：')}
                {tBytes(list.max_file_bytes)}
              </p>
            )}
          </section>

          {/* 右：详情/编辑器 */}
          <section ref={detailSectionRef} class="oh-appear-up oh-files-panel oh-files-detail-panel">
            {!selected ? (
              <div class="oh-files-empty-detail">
                <p class="oh-files-empty-mark">/</p>
                <p>
                  {t('files.selectHint', '从左侧选择一个文件以查看 / 编辑')}
                </p>
              </div>
            ) : (
              <>
                <header class="oh-files-detail-header">
                  <div class="min-w-0">
                    <p class="oh-files-detail-path">
                      {selected.path}
                    </p>
                    {contentMeta && (
                      <p class="oh-files-detail-meta">
                        {tBytes(contentMeta.size)} · {tDateTime(contentMeta.modified_at)}
                      </p>
                    )}
                  </div>
                  <div class="flex items-center gap-2">
                    {dirty && (
                      <span class="oh-files-status is-dirty">
                        {t('files.dirty', '未保存')}
                      </span>
                    )}
                    {saveOk && (
                      <span class="oh-files-status is-saved">
                        ✓ {t('files.saveOk', '已保存')}
                      </span>
                    )}
                    <button
                      type="button"
                      onClick={() => void handleSave()}
                      disabled={writeDisabled || !dirty || saving}
                      class="oh-tap-press oh-files-primary-button"
                      title={writeDisabled ? t('files.writeDisabledHint', '该文件不可写入') : undefined}
                    >
                      {saving ? t('files.saving', '保存中…') : t('files.save', '保存')}
                    </button>
                  </div>
                </header>

                {contentLoading && (
                  <p class="text-sm oh-text-muted">
                    {t('common.loading')}
                  </p>
                )}
                {contentError && (
                  <p class="text-sm oh-text-error">
                    {contentError}
                  </p>
                )}
                {saveError && (
                  <p class="text-sm oh-text-error">
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
                        resetSaveOk();
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
          confirmBeforeClose
          confirmLabel={deleteBusy ? t('files.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setDeleteTarget(null)}
          onConfirm={confirmDeleteTarget}
          onConfirmSuccess={() => setDeleteTarget(null)}
        />
      ) : null}
    </main>
  );
}
