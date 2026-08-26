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
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import { useBrowserFullscreen } from '../../../hooks/useBrowserFullscreen';
import {
  createSession,
  deleteSession,
  EXPORT_SESSION_TIMEOUT_ERROR,
  exportSessionDownload,
  listSessions,
  renameSession,
  SESSION_TITLE_MAX_CHARACTERS,
  type CreateSessionInput,
  type CreateSessionResponse,
  type SessionListResponse,
  type SessionMode,
  type SessionSummary,
} from '../../../api/sessions';
import { ApiError, UnauthorizedError } from '../../../api/client';
import { isAbortError } from '../../../shared/util/errors';
import { waitForDelayOrAbort } from '../../../utils/timed_abort';
import { t } from '../../../i18n';
import { useAuth } from '../../../state/auth';
import type { ApiMetaTemplate } from '../../../api/meta';
import { TopBar } from '../../../components/TopBar';
import { Appear } from '../../../components/Appear';
import { PopMenu } from '../../../components/PopMenu';
import { TemplateConfigDialog, TemplatePickerDialog } from '../../../components/TemplateDialogs';
import { PullIndicator } from '../../../components/PullIndicator';
import { usePullToRefresh } from '../../../hooks/usePullToRefresh';
import { writeBrowserStorage } from '../../../shared/util/browser_storage';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import { showSnackbar } from '../../../components/Snackbar';
import { BusyWaitDialog } from '../../../components/BusyWaitDialog';
import { AnimatedTitleText } from '../../../components/AnimatedTitleText';
import { BrowserFullscreenButton } from '../../../components/BrowserFullscreenButton';
import { formatLocalDateTimeMinute } from '../../../shared/util/date_time';
import {
  PAGE_SHELL_CLASS,
  SESSIONS_SHELL_CLASS,
} from '../../../shared/ui/layout';
import { STORAGE_KEY_LAST_MODEL } from '../../../shared/util/storage_keys';

const DEFAULT_PAGE_SIZE = 10;
const PULL_REFRESH_MIN_VISIBLE_MS = 180;

function modeLabel(mode: string): string {
  if (mode === 'plan') return t('sessions.mode.plan', '计划模式');
  if (mode === 'goal') return t('sessions.mode.goal', '目标模式');
  if (mode === 'chat') return t('sessions.mode.chat', '聊天模式');
  return mode;
}

interface RowState {
  draftTitle: string | null;
  busy: boolean;
  error?: string;
  exporting?: boolean;
}

const emptyRow: RowState = { draftTitle: null, busy: false };

export function SessionsPage() {
  const auth = useAuth();
  const location = useAnimatedLocation();

  const [page, setPage] = useState(1);
  const [pageSize] = useState(DEFAULT_PAGE_SIZE);
  const [data, setData] = useState<SessionListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rowStates, setRowStates] = useState<Record<string, RowState>>({});
  const [deleteTarget, setDeleteTarget] = useState<SessionSummary | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const browserFullscreen = useBrowserFullscreen();

  // 创建流程：先 picker（选模板），再 config（填参数）。
  const [pickerOpen, setPickerOpen] = useState(false);
  const [configTemplate, setConfigTemplate] = useState<ApiMetaTemplate | null>(null);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const creatingRef = useRef(false);

  const pageRootRef = useRef<HTMLElement | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const pullRefreshDelayAbortRef = useRef<AbortController | null>(null);

  const templates: ApiMetaTemplate[] = auth.meta?.templates ?? [];
  const planEnabled = Boolean(auth.meta?.service?.plan_mode_enabled);
  const sessionMgmtEnabled = auth.meta?.service?.session_management_enabled !== false;


  async function refresh(targetPage: number = page): Promise<void> {
    abortRef.current?.abort();
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    setLoading(true);
    setError(null);
    try {
      const res = await listSessions({
        page: targetPage,
        pageSize,
        signal: ctrl.signal,
      });
      if (ctrl.signal.aborted) return;
      setData(res);
      setLoading(false);
      if (res.items.length === 0 && targetPage > 1) {
        setPage(targetPage - 1);
      }
    } catch (e) {
      if (ctrl.signal.aborted) return;
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return;
      }
      setError(e instanceof Error ? e.message : String(e));
      setLoading(false);
    }
  }

  useEffect(() => {
    if (auth.loading) return;
    void refresh(page);
    return () => abortRef.current?.abort();
  }, [auth.loading, page]);

  useEffect(() => {
    return () => {
      pullRefreshDelayAbortRef.current?.abort();
      pullRefreshDelayAbortRef.current = null;
    };
  }, []);

  function patchRow(id: string, patch: Partial<RowState>): void {
    setRowStates((prev) => ({ ...prev, [id]: { ...emptyRow, ...prev[id], ...patch } }));
  }

  function prependCreatedSession(session: SessionSummary): void {
    setData((prev) => {
      if (!prev) return prev;
      const existed = prev.items.some((item) => item.id === session.id);
      return {
        ...prev,
        items: [
          session,
          ...prev.items.filter((item) => item.id !== session.id),
        ].slice(0, prev.page_size),
        total: prev.total + (existed ? 0 : 1),
      };
    });
  }

  function openPicker(): void {
    setCreateError(null);
    setPickerOpen(true);
  }

  function onPickTemplate(tpl: ApiMetaTemplate): void {
    setPickerOpen(false);
    if (tpl.id === 'machine_expert') {
      void createDirectTemplateSession(tpl);
      return;
    }
    setConfigTemplate(tpl);
  }

  function createFailureMessage(error: unknown): string {
    if (!(error instanceof ApiError)) {
      return error instanceof Error ? error.message : String(error);
    }
    const body = error.body;
    const code = body != null && typeof body === 'object' && 'error' in body
      ? String((body as { error?: unknown }).error ?? '')
      : '';
    switch (code) {
      case 'session_management_disabled':
        return t('sessions.create.error.managementDisabled', '当前服务已禁用会话管理');
      case 'template_not_allowed':
        return t('sessions.create.error.template', '当前服务不允许使用该模板');
      case 'plan_mode_disabled':
        return t('sessions.create.error.planDisabled', '当前服务未启用计划模式');
      case 'goal_mode_not_available':
        return t('sessions.create.error.goalUnavailable', '该模板不支持目标模式');
      case 'model_not_configured':
        return t('sessions.create.error.model', '所选模型不可用，请重新选择');
      case 'title_too_long':
        return t('sessions.create.error.titleTooLong', '会话标题不能超过 200 个字符');
      case 'create_failed':
        return t('sessions.create.error.failed', '服务端未能保存新会话');
      default:
        return `${t('sessions.create.error.request', '请求失败')}（HTTP ${error.status}）`;
    }
  }

  function reportCreationWarnings(result: CreateSessionResponse): void {
    if (!result.warnings?.length) return;
    showSnackbar(
      t('sessions.create.warning', '会话已创建，但部分初始化未完成，可进入会话后重试'),
      { tone: 'warning' },
    );
  }

  function openCreatedSession(session: SessionSummary): void {
    setConfigTemplate(null);
    showSnackbar(t('sessions.create.ok', '已创建会话'), { tone: 'success' });
    location.route(`/threads/${encodeURIComponent(session.id)}`);
  }

  async function createDirectTemplateSession(tpl: ApiMetaTemplate): Promise<void> {
    if (creatingRef.current) return;
    creatingRef.current = true;
    setCreating(true);
    setCreateError(null);
    try {
      const res = await createSession({
        templateId: tpl.id,
        mode: 'chat',
      });
      prependCreatedSession(res.session);
      reportCreationWarnings(res);
      openCreatedSession(res.session);
    } catch (e: unknown) {
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return;
      }
      const message = createFailureMessage(e);
      setCreateError(message);
      showSnackbar(`${t('sessions.create.failed', '创建会话失败')}：${message}`, { tone: 'error' });
    } finally {
      creatingRef.current = false;
      setCreating(false);
    }
  }

  async function onConfigSubmit(params: {
    mode: SessionMode;
    title: string;
    modelKey: string;
  }): Promise<SessionSummary | null> {
    if (!configTemplate || creatingRef.current) return null;
    creatingRef.current = true;
    setCreating(true);
    setCreateError(null);
    try {
      const input: CreateSessionInput = {
        templateId: configTemplate.id,
        mode: params.mode,
        title: params.title || undefined,
        modelKey: params.modelKey || undefined,
      };
      const res = await createSession(input);
      prependCreatedSession(res.session);
      // 模型偏好仍写一份本地缓存；服务端也会保存到会话 last-used model。
      if (params.modelKey) {
        writeBrowserStorage(STORAGE_KEY_LAST_MODEL, params.modelKey);
      }
      reportCreationWarnings(res);
      return res.session;
    } catch (e: unknown) {
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return null;
      }
      const message = createFailureMessage(e);
      setCreateError(message);
      showSnackbar(`${t('sessions.create.failed', '创建会话失败')}：${message}`, { tone: 'error' });
      return null;
    } finally {
      creatingRef.current = false;
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
      const result = await renameSession(item.id, draft);
      setData((prev) => prev
        ? {
            ...prev,
            items: prev.items.map((entry) =>
              entry.id === item.id ? result.session : entry,
            ),
          }
        : prev,
      );
      patchRow(item.id, { draftTitle: null, busy: false });
      showSnackbar(t('topbar.rename.ok', '已重命名会话'), { tone: 'success' });
    } catch (e: unknown) {
      reportRowActionError(item, e, t('topbar.rename.failed', '重命名失败'));
    }
  }

  async function confirmDeleteTarget(): Promise<boolean> {
    const item = deleteTarget;
    if (!item || deleteBusy) return false;
    setDeleteBusy(true);
    patchRow(item.id, { busy: true, error: undefined });
    try {
      await deleteSession(item.id);
      patchRow(item.id, { busy: false });
      showSnackbar(t('topbar.delete.ok', '已删除会话'), { tone: 'success' });
      void refresh();
      return true;
    } catch (e: unknown) {
      reportRowActionError(item, e, t('topbar.delete.failed', '删除会话失败'));
      return false;
    } finally {
      setDeleteBusy(false);
    }
  }

  function reportRowActionError(
    item: SessionSummary,
    error: unknown,
    failureLabel: string,
  ): void {
    if (error instanceof UnauthorizedError) {
      location.route('/login', true);
      return;
    }
    const message = error instanceof Error ? error.message : String(error);
    patchRow(item.id, { busy: false, error: message });
    showSnackbar(`${failureLabel}：${message}`, { tone: 'error' });
  }

  async function handleExport(item: SessionSummary): Promise<void> {
    patchRow(item.id, { exporting: true, error: undefined });
    try {
      showSnackbar(t('topbar.export.started', '正在导出会话数据…'));
      const result = await exportSessionDownload(item.id, item.title || `session_${item.id}`);
      patchRow(item.id, { exporting: false });
      showSnackbar(`${t('topbar.export.ok', '已保存导出文件')}：${result.filename}`, { tone: 'success' });
    } catch (e: unknown) {
      if (isAbortError(e)) {
        patchRow(item.id, { exporting: false });
        return;
      }
      if (e instanceof UnauthorizedError) {
        location.route('/login', true);
        return;
      }
      const message = e instanceof Error && e.message === EXPORT_SESSION_TIMEOUT_ERROR
        ? t('topbar.export.timeout', '导出会话超时，请稍后重试')
        : e instanceof Error
          ? e.message
          : String(e);
      patchRow(item.id, {
        exporting: false,
        error: message,
      });
      showSnackbar(`${t('topbar.export.failed', '导出会话失败')}：${message}`, { tone: 'error' });
    }
  }

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.page_size)) : 1;
  const items = data?.items ?? [];

  const openSession = (id: string) => {
    location.route(`/threads/${id}`);
  };

  // 下拉刷新挂在 <main> 上：触摸设备体验对齐 APP 端线程列表。
  const mainRef = useRef<HTMLElement | null>(null);
  const pull = usePullToRefresh(mainRef, {
    onRefresh: async () => {
      pullRefreshDelayAbortRef.current?.abort();
      const delayCtrl = new AbortController();
      pullRefreshDelayAbortRef.current = delayCtrl;
      try {
        await refresh(page);
        await waitForDelayOrAbort(
          PULL_REFRESH_MIN_VISIBLE_MS,
          delayCtrl.signal,
        );
      } finally {
        if (pullRefreshDelayAbortRef.current === delayCtrl) {
          pullRefreshDelayAbortRef.current = null;
        }
      }
    },
    activationDistance: 80,
    maxDistance: 140,
  });

  return (
    <main
      ref={pageRootRef}
      class={`oh-sessions-page ${PAGE_SHELL_CLASS} h-screen overflow-hidden flex flex-col`}
      style={{ background: 'var(--m3-surface)' }}
    >
      <div class={`${SESSIONS_SHELL_CLASS} w-full flex-1 min-h-0 flex flex-col`}>
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
          actionSlot={(
            <BrowserFullscreenButton
              active={browserFullscreen.active}
              onClick={() => void browserFullscreen.toggle()}
            />
          )}
        />

        <div class="mb-3 flex items-center justify-between gap-2 text-xs oh-text-muted">
          <span>{t('sessions.refresh.hint', '下拉列表或点击刷新同步本设备会话')}</span>
          <button
            type="button"
            onClick={() => void refresh()}
            disabled={loading || pull.refreshing}
            class="oh-tap-press px-3 py-1.5 rounded-m3-sm disabled:opacity-50"
            style={{
              border: '1px solid var(--m3-outline)',
              background: 'var(--m3-surface-container)',
              color: 'var(--m3-on-surface)',
            }}
          >
            {loading || pull.refreshing ? t('sessions.refreshing', '刷新中…') : t('common.refresh', '刷新')}
          </button>
        </div>

        <section
          ref={mainRef as unknown as preact.RefObject<HTMLElement>}
          class="flex-1 min-h-0 overflow-y-auto pr-1 pb-24"
        >
          {/* 列表 */}
        {loading && !data ? (
          <p class="text-sm oh-text-muted">
            {t('sessions.loading', '加载中…')}
          </p>
        ) : error ? (
          <div
            class="rounded-md p-4 text-sm"
            style={{ background: 'var(--m3-surface-container)', color: 'var(--m3-error)' }}
          >
            {error}
            <button type="button" onClick={() => void refresh()} class="ml-3 underline">
              {t('sessions.retry', '重试')}
            </button>
          </div>
        ) : items.length === 0 ? (
          <div class="oh-session-empty-state oh-sessions-empty">
            <span class="oh-session-empty-icon" aria-hidden>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
              </svg>
            </span>
            <p class="text-sm">
              {t('sessions.empty', '暂无会话，点击右下角加号创建一个吧。')}
            </p>
          </div>
        ) : (
          <ul class="oh-sessions-list flex flex-col gap-3 w-full min-w-0">
            {items.map((item, idx) => {
              const row = rowStates[item.id] ?? emptyRow;
              const editing = row.draftTitle !== null;
              return (
                <Appear as="li" key={item.id} variant="up" index={Math.min(idx + 1, 12)}>
                  <div
                    class="oh-sessions-card rounded-m3-md p-4 oh-tap-press"
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
                      if (target.closest('button,input,textarea,select,a,[role="menu"]')) return;
                      openSession(item.id);
                    }}
                    onKeyDown={(ev) => {
                      if (editing) return;
                      if (ev.key === 'Enter' || ev.key === ' ') {
                        ev.preventDefault();
                        openSession(item.id);
                      }
                    }}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="flex-1 min-w-0">
                        <AnimatedTitleText
                          text={
                            item.title ||
                            t('sessions.untitled', '未命名会话')
                          }
                          className="text-base font-medium text-left truncate w-full"
                          style={{
                            color: 'var(--m3-on-surface)',
                            display: editing ? 'none' : 'block',
                          }}
                        />
                        {editing ? (
                          <div class="flex items-center gap-2">
                            <input
                              value={row.draftTitle ?? ''}
                              maxLength={SESSION_TITLE_MAX_CHARACTERS}
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
                              class="text-xs px-2 py-1 oh-text-muted"
                            >
                              {t('common.cancel', '取消')}
                            </button>
                          </div>
                        ) : null}
                        <p
                          class="text-xs mt-1 truncate oh-text-muted"
                        >
                          {item.last_message_preview ||
                            t('sessions.previewEmpty', '尚无消息')}
                        </p>
                        <div
                          class="text-xs mt-2 flex flex-wrap gap-x-3 gap-y-1 oh-text-muted"
                        >
                          <span>{formatLocalDateTimeMinute(item.updated_at)}</span>
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
                          <p class="text-xs mt-2 oh-text-error">
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
                              onMouseDown={(ev) => ev.stopPropagation()}
                              onClick={(ev) => {
                                ev.stopPropagation();
                                ev.preventDefault();
                                toggle();
                              }}
                              class="oh-tap-press w-10 h-10 rounded-full flex items-center justify-center text-base"
                              style={{
                                background: open
                                  ? 'color-mix(in srgb, var(--m3-on-surface) 10%, transparent)'
                                  : 'transparent',
                                color: 'var(--m3-on-surface-variant)',
                                border: open ? '1px solid var(--m3-outline)' : '1px solid transparent',
                                marginRight: '-8px',
                                marginTop: '-4px',
                              }}
                              aria-haspopup="menu"
                              aria-label={t('sessions.row.menu', '更多操作')}
                              title={t('sessions.row.menu', '更多操作')}
                            >
                              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
                                <circle cx="5" cy="12" r="1.4" />
                                <circle cx="12" cy="12" r="1.4" />
                                <circle cx="19" cy="12" r="1.4" />
                              </svg>
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
                                : t('sessions.delete.action', '删除'),
                              onClick: () => setDeleteTarget(item),
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
            <span class="oh-text-muted">
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
        </section>
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
          defaultModelKey={auth.meta?.active_model_key ?? ''}
          planEnabled={planEnabled}
          busy={creating}
          error={createError}
          onSubmit={onConfigSubmit}
          onCreated={openCreatedSession}
          onClose={() => {
            setConfigTemplate(null);
            setCreateError(null);
          }}
        />
      ) : null}
      <BusyWaitDialog
        open={creating}
        title={t('sessions.create.wait.title', '正在新建会话')}
        body={t('sessions.create.wait.body', '正在创建线程并准备会话上下文，请稍候。')}
      />
      {deleteTarget ? (
        <ConfirmDialog
          title={t('topbar.deleteConfirmTitle', '删除该会话?')}
          body={t('topbar.deleteConfirm', '确定删除该会话?此操作不可恢复')}
          danger
          busy={deleteBusy}
          confirmBeforeClose
          confirmLabel={deleteBusy ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setDeleteTarget(null)}
          onConfirm={confirmDeleteTarget}
          onConfirmSuccess={() => setDeleteTarget(null)}
        />
      ) : null}
    </main>
  );
}
