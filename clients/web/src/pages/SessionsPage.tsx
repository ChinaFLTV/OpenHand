// 会话列表页：分页拉取 + 悬浮 FAB（先选模板再配参数） + 卡片三点菜单（重命名/删除/导出）。
// 顶部条复用 TopBar；移除原本的"主题预览 / 可访问 URL"看板。
//
// 服务端契约：
//   GET    /api/sessions?page=&page_size=
//   POST   /api/sessions {template_id, mode, title?}
//   PATCH  /api/sessions/:id {title}
//   DELETE /api/sessions/:id
//   GET    /api/sessions/:id/export

import { useEffect, useRef, useState } from 'preact/hooks';
import { useLocation } from 'preact-iso';
import {
  createSession,
  deleteSession,
  exportSessionDownload,
  listSessions,
  renameSession,
  type CreateSessionInput,
  type SessionListResponse,
  type SessionSummary,
} from '../api/sessions';
import { ApiError, UnauthorizedError } from '../api/client';
import { t } from '../i18n';
import { useAuth } from '../state/auth';
import type { ApiMetaTemplate } from '../api/meta';
import { TopBar } from '../components/TopBar';
import { Appear } from '../components/Appear';
import { PopMenu } from '../components/PopMenu';
import { TemplateConfigDialog, TemplatePickerDialog } from '../components/TemplateDialogs';
import { PullIndicator } from '../components/PullIndicator';
import { usePullToRefresh } from '../hooks/usePullToRefresh';

const DEFAULT_PAGE_SIZE = 10;

function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  } catch {
    return iso;
  }
}

function modeLabel(mode: string): string {
  if (mode === 'plan') return t('sessions.mode.plan', 'Plan');
  if (mode === 'chat') return t('sessions.mode.chat', '对话');
  return mode;
}

interface RowState {
  draftTitle: string | null;
  pendingDelete: boolean;
  busy: boolean;
  error?: string;
  exporting?: boolean;
}

const emptyRow: RowState = { draftTitle: null, pendingDelete: false, busy: false };

export function SessionsPage() {
  const auth = useAuth();
  const location = useLocation();

  const [page, setPage] = useState(1);
  const [pageSize] = useState(DEFAULT_PAGE_SIZE);
  const [data, setData] = useState<SessionListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rowStates, setRowStates] = useState<Record<string, RowState>>({});

  // 创建流程：先 picker（选模板），再 config（填参数）。
  const [pickerOpen, setPickerOpen] = useState(false);
  const [configTemplate, setConfigTemplate] = useState<ApiMetaTemplate | null>(null);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  const abortRef = useRef<AbortController | null>(null);

  const templates: ApiMetaTemplate[] = auth.meta?.templates ?? [];
  const allowedModes: string[] = auth.meta?.conversation_modes ?? ['chat'];
  const planEnabled =
    Boolean(auth.meta?.service?.plan_mode_enabled) && allowedModes.includes('plan');
  const sessionMgmtEnabled = auth.meta?.service?.session_management_enabled !== false;

  function refresh(targetPage: number = page): void {
    abortRef.current?.abort();
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    setLoading(true);
    setError(null);
    listSessions({ page: targetPage, pageSize })
      .then((res) => {
        if (ctrl.signal.aborted) return;
        setData(res);
        setLoading(false);
        if (res.items.length === 0 && targetPage > 1) {
          setPage(targetPage - 1);
        }
      })
      .catch((e: unknown) => {
        if (ctrl.signal.aborted) return;
        if (e instanceof UnauthorizedError) {
          location.route('/login', true);
          return;
        }
        setError(e instanceof Error ? e.message : String(e));
        setLoading(false);
      });
  }

  useEffect(() => {
    if (auth.loading) return;
    refresh(page);
    return () => abortRef.current?.abort();
  }, [auth.loading, page]);

  function patchRow(id: string, patch: Partial<RowState>): void {
    setRowStates((prev) => ({ ...prev, [id]: { ...emptyRow, ...prev[id], ...patch } }));
  }

  function openPicker(): void {
    setCreateError(null);
    setPickerOpen(true);
  }

  function onPickTemplate(tpl: ApiMetaTemplate): void {
    setPickerOpen(false);
    setConfigTemplate(tpl);
  }

  async function onConfigSubmit(params: { mode: 'chat' | 'plan'; title: string; modelKey: string }): Promise<void> {
    if (!configTemplate || creating) return;
    setCreating(true);
    setCreateError(null);
    try {
      const input: CreateSessionInput = {
        templateId: configTemplate.id,
        mode: params.mode,
        title: params.title || undefined,
      };
      const res = await createSession(input);
      // 模型偏好暂记 localStorage（服务端契约尚未承接 model_key），下次创建时复用。
      if (params.modelKey) {
        try {
          window.localStorage.setItem('openhand.web.lastModelKey', params.modelKey);
        } catch {
          /* 隐私模式或 quota 满 → 忽略 */
        }
      }
      setConfigTemplate(null);
      location.route(`/threads/${res.session.id}`);
    } catch (e: unknown) {
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return;
      }
      if (e instanceof ApiError) {
        setCreateError(t('sessions.create.error.api', 'HTTP ') + String(e.status));
      } else {
        setCreateError(e instanceof Error ? e.message : String(e));
      }
    } finally {
      setCreating(false);
    }
  }

  async function handleRenameSubmit(item: SessionSummary): Promise<void> {
    const draft = rowStates[item.id]?.draftTitle?.trim();
    if (!draft) {
      patchRow(item.id, { error: t('sessions.rename.empty', '标题不能为空') });
      return;
    }
    if (draft === item.title) {
      patchRow(item.id, { draftTitle: null, error: undefined });
      return;
    }
    patchRow(item.id, { busy: true, error: undefined });
    try {
      await renameSession(item.id, draft);
      patchRow(item.id, { draftTitle: null, busy: false });
      refresh();
    } catch (e: unknown) {
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return;
      }
      patchRow(item.id, { busy: false, error: e instanceof Error ? e.message : String(e) });
    }
  }

  async function handleDelete(item: SessionSummary): Promise<void> {
    const row = rowStates[item.id] ?? emptyRow;
    if (!row.pendingDelete) {
      patchRow(item.id, { pendingDelete: true });
      setTimeout(() => {
        setRowStates((prev) => {
          const cur = prev[item.id];
          if (!cur || !cur.pendingDelete) return prev;
          return { ...prev, [item.id]: { ...cur, pendingDelete: false } };
        });
      }, 4000);
      return;
    }
    patchRow(item.id, { busy: true, error: undefined });
    try {
      await deleteSession(item.id);
      patchRow(item.id, { busy: false, pendingDelete: false });
      refresh();
    } catch (e: unknown) {
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return;
      }
      patchRow(item.id, {
        busy: false,
        pendingDelete: false,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  async function handleExport(item: SessionSummary): Promise<void> {
    patchRow(item.id, { exporting: true, error: undefined });
    try {
      await exportSessionDownload(item.id, item.title || `session_${item.id}`);
      patchRow(item.id, { exporting: false });
    } catch (e: unknown) {
      if (e instanceof Error && e.message === 'UNAUTHORIZED') {
        location.route('/login', true);
        return;
      }
      patchRow(item.id, {
        exporting: false,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.page_size)) : 1;
  const items = data?.items ?? [];

  // 下拉刷新挂在 <main> 上：触摸设备体验对齐 APP 端线程列表。
  const mainRef = useRef<HTMLElement | null>(null);
  const pull = usePullToRefresh(mainRef, {
    onRefresh: async () => {
      await new Promise<void>((resolve) => {
        // refresh() 内部用 abort + Promise，调用即触发；用 setTimeout 给一个最小可见时长。
        refresh(page);
        setTimeout(resolve, 320);
      });
    },
    activationDistance: 80,
    maxDistance: 140,
  });

  return (
    <main
      ref={mainRef as unknown as preact.RefObject<HTMLElement>}
      class="min-h-screen px-6 py-8"
      style={{ background: 'var(--m3-surface)' }}
    >
      <div class="mx-auto max-w-3xl">
        <PullIndicator
          pulled={pull.pulled}
          refreshing={pull.refreshing}
          willRelease={pull.willRelease}
          activationDistance={80}
        />
        <TopBar
          title={t('app.brand')}
          subtitle={
            data
              ? t('sessions.subtitle.count', '共 ') +
                data.total +
                ' ' +
                t('sessions.subtitle.unit', '个会话') +
                (data.scope === 'current_device'
                  ? ' · ' + t('sessions.subtitle.scopeDevice', '仅本设备可见')
                  : '')
              : t('sessions.subtitle.loading', '加载中…')
          }
        />

        {/* 列表 */}
        {loading && !data ? (
          <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
            {t('sessions.loading', '加载中…')}
          </p>
        ) : error ? (
          <div
            class="rounded-md p-4 text-sm"
            style={{ background: 'var(--m3-surface-container)', color: 'var(--m3-error)' }}
          >
            {error}
            <button type="button" onClick={() => refresh()} class="ml-3 underline">
              {t('sessions.retry', '重试')}
            </button>
          </div>
        ) : items.length === 0 ? (
          <div
            class="text-center py-12 rounded-m3-md"
            style={{
              background: 'var(--m3-surface-container)',
              color: 'var(--m3-on-surface-variant)',
            }}
          >
            <p class="text-sm">
              {t('sessions.empty', '暂无会话，点击右下角加号创建一个吧。')}
            </p>
          </div>
        ) : (
          <ul class="flex flex-col gap-3">
            {items.map((item, idx) => {
              const row = rowStates[item.id] ?? emptyRow;
              const editing = row.draftTitle !== null;
              return (
                <Appear as="li" key={item.id} variant="up" index={Math.min(idx + 1, 12)}>
                  <div
                    class="rounded-m3-md p-4 oh-tap-press"
                    style={{
                      background: 'var(--m3-surface-container)',
                      boxShadow: 'var(--m3-elev-1)',
                      cursor: editing ? 'default' : 'pointer',
                    }}
                    role={editing ? undefined : 'button'}
                    tabIndex={editing ? undefined : 0}
                    onClick={(ev) => {
                      if (editing) return;
                      // 点击操作菜单 / 输入框等已经 stopPropagation；这里只接管"卡片本体"点击。
                      const target = ev.target as HTMLElement;
                      if (target.closest('button,input,[role="menu"]')) return;
                      location.route(`/threads/${item.id}`);
                    }}
                    onKeyDown={(ev) => {
                      if (editing) return;
                      if (ev.key === 'Enter' || ev.key === ' ') {
                        ev.preventDefault();
                        location.route(`/threads/${item.id}`);
                      }
                    }}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="flex-1 min-w-0">
                        {editing ? (
                          <div class="flex items-center gap-2">
                            <input
                              value={row.draftTitle ?? ''}
                              onInput={(e) =>
                                patchRow(item.id, {
                                  draftTitle: (e.currentTarget as HTMLInputElement).value,
                                })
                              }
                              disabled={row.busy}
                              class="flex-1 px-2 py-1 rounded-m3-sm text-sm"
                              style={{
                                background: 'var(--m3-surface)',
                                color: 'var(--m3-on-surface)',
                                border: '1px solid var(--m3-outline)',
                              }}
                              autoFocus
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.preventDefault();
                                  void handleRenameSubmit(item);
                                } else if (e.key === 'Escape') {
                                  patchRow(item.id, { draftTitle: null, error: undefined });
                                }
                              }}
                            />
                            <button
                              type="button"
                              onClick={() => handleRenameSubmit(item)}
                              disabled={row.busy}
                              class="text-xs px-2 py-1 rounded-m3-sm"
                              style={{
                                background: 'var(--m3-primary)',
                                color: 'var(--m3-on-primary)',
                              }}
                            >
                              {row.busy
                                ? t('sessions.rename.saving', '保存中…')
                                : t('sessions.rename.save', '保存')}
                            </button>
                            <button
                              type="button"
                              onClick={() =>
                                patchRow(item.id, { draftTitle: null, error: undefined })
                              }
                              disabled={row.busy}
                              class="text-xs px-2 py-1"
                              style={{ color: 'var(--m3-on-surface-variant)' }}
                            >
                              {t('common.cancel', '取消')}
                            </button>
                          </div>
                        ) : (
                          <span
                            class="text-base font-medium text-left truncate block w-full"
                            style={{ color: 'var(--m3-on-surface)' }}
                          >
                            {item.title || t('sessions.untitled', '未命名会话')}
                          </span>
                        )}
                        <p
                          class="text-xs mt-1 truncate"
                          style={{ color: 'var(--m3-on-surface-variant)' }}
                        >
                          {item.last_message_preview ||
                            t('sessions.previewEmpty', '尚无消息')}
                        </p>
                        <div
                          class="text-xs mt-2 flex flex-wrap gap-x-3 gap-y-1"
                          style={{ color: 'var(--m3-on-surface-variant)' }}
                        >
                          <span>{formatTimestamp(item.updated_at)}</span>
                          <span>· {modeLabel(item.mode)}</span>
                          <span>
                            · {t('sessions.template.label', '模板：')}
                            {item.template_name || item.template_id}
                          </span>
                          <span>
                            · {item.message_count} {t('sessions.messageUnit', '条消息')}
                          </span>
                        </div>
                        {row.error ? (
                          <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
                            {row.error}
                          </p>
                        ) : null}
                      </div>
                      {sessionMgmtEnabled && !editing ? (
                        <PopMenu
                          align="right"
                          trigger={({ open, toggle }) => (
                            <button
                              type="button"
                              onClick={(ev) => {
                                ev.stopPropagation();
                                toggle();
                              }}
                              class="oh-tap-press w-8 h-8 rounded-full flex items-center justify-center text-base"
                              style={{
                                background: open
                                  ? 'color-mix(in srgb, var(--m3-on-surface) 8%, transparent)'
                                  : 'transparent',
                                color: 'var(--m3-on-surface-variant)',
                                border: '1px solid var(--m3-outline)',
                              }}
                              aria-haspopup="menu"
                              aria-label={t('sessions.row.menu', '更多操作')}
                              title={t('sessions.row.menu', '更多操作')}
                            >
                              ⋯
                            </button>
                          )}
                          items={[
                            {
                              key: 'rename',
                              label: t('sessions.rename.action', '重命名'),
                              onClick: () =>
                                patchRow(item.id, {
                                  draftTitle: item.title,
                                  error: undefined,
                                }),
                            },
                            {
                              key: 'export',
                              label: row.exporting
                                ? t('sessions.export.busy', '正在导出…')
                                : t('sessions.export.action', '导出会话数据'),
                              onClick: () => void handleExport(item),
                              disabled: row.exporting,
                            },
                            {
                              key: 'delete',
                              label: row.busy
                                ? t('sessions.delete.deleting', '正在删除…')
                                : row.pendingDelete
                                  ? t('sessions.delete.confirm', '再次点击确认删除')
                                  : t('sessions.delete.action', '删除'),
                              onClick: () => void handleDelete(item),
                              variant: 'danger',
                              disabled: row.busy,
                            },
                          ]}
                        />
                      ) : null}
                    </div>
                  </div>
                </Appear>
              );
            })}
          </ul>
        )}

        {/* 分页器 */}
        {data && data.total > pageSize ? (
          <div class="flex items-center justify-center gap-3 mt-6 text-sm">
            <button
              type="button"
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1 || loading}
              class="px-3 py-1.5 rounded-m3-sm disabled:opacity-50"
              style={{
                border: '1px solid var(--m3-outline)',
                color: 'var(--m3-on-surface)',
              }}
            >
              {t('sessions.pager.prev', '上一页')}
            </button>
            <span style={{ color: 'var(--m3-on-surface-variant)' }}>
              {page} / {totalPages}
            </span>
            <button
              type="button"
              onClick={() => setPage((p) => p + 1)}
              disabled={!data.has_more || loading}
              class="px-3 py-1.5 rounded-m3-sm disabled:opacity-50"
              style={{
                border: '1px solid var(--m3-outline)',
                color: 'var(--m3-on-surface)',
              }}
            >
              {t('sessions.pager.next', '下一页')}
            </button>
          </div>
        ) : null}
      </div>

      {/* FAB：右下角悬浮加号，触发模板选择弹窗 */}
      {sessionMgmtEnabled ? (
        <button
          type="button"
          class="oh-fab"
          aria-label={t('sessions.fab.create', '新建会话')}
          title={t('sessions.fab.create', '新建会话')}
          onClick={openPicker}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="28"
            height="28"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden
          >
            <line x1="12" y1="5" x2="12" y2="19"></line>
            <line x1="5" y1="12" x2="19" y2="12"></line>
          </svg>
        </button>
      ) : null}

      {/* 模板选择 / 配置弹窗 */}
      {pickerOpen ? (
        <TemplatePickerDialog
          templates={templates}
          onPick={onPickTemplate}
          onClose={() => setPickerOpen(false)}
        />
      ) : null}
      {configTemplate ? (
        <TemplateConfigDialog
          template={configTemplate}
          models={auth.meta?.models ?? []}
          allowedModes={allowedModes}
          planEnabled={planEnabled}
          busy={creating}
          error={createError}
          onSubmit={onConfigSubmit}
          onClose={() => {
            if (creating) return;
            setConfigTemplate(null);
            setCreateError(null);
          }}
        />
      ) : null}
    </main>
  );
}
