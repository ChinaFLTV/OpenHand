// 会话列表页：分页拉取 + 新建 + 重命名 + 删除。
//
// 目标契约对齐 `web_message_platform_service.dart` 的：
//   GET    /api/sessions?page=&page_size=
//   POST   /api/sessions {template_id, mode, title?}
//   PATCH  /api/sessions/:id {title}
//   DELETE /api/sessions/:id
//
// 设计要点：
// 1. 不引入 query 库；每次过滤/分页变更直接重新 fetch。
// 2. 删除 / 重命名 / 创建后只刷新当前页，避免破坏用户正在浏览的位置。
// 3. inline 重命名 / 删除确认放进同一行卡片，不弹模态，避免重叠 mobile-friendly。

import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useLocation } from 'preact-iso';
import {
  createSession,
  deleteSession,
  listSessions,
  renameSession,
  type CreateSessionInput,
  type SessionListResponse,
  type SessionSummary,
} from '../api/sessions';
import { ApiError, UnauthorizedError } from '../api/client';
import { t } from '../i18n';
import { MenuSelect } from '../components/MenuSelect';
import { useAuth } from '../state/auth';
import type { ApiMetaTemplate } from '../api/meta';

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
  /// null 时不在编辑；否则是输入框文本
  draftTitle: string | null;
  /// true 时显示「再次点击删除以确认」
  pendingDelete: boolean;
  busy: boolean;
  error?: string;
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
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const [createTemplateId, setCreateTemplateId] = useState<string>('default');
  const [createMode, setCreateMode] = useState<'chat' | 'plan'>('chat');

  const abortRef = useRef<AbortController | null>(null);

  const templates = useMemo<ApiMetaTemplate[]>(
    () => auth.meta?.templates ?? [],
    [auth.meta],
  );
  const allowedModes = useMemo<string[]>(
    () => auth.meta?.conversation_modes ?? ['chat'],
    [auth.meta],
  );
  const planEnabled = Boolean(auth.meta?.service?.plan_mode_enabled) &&
    allowedModes.includes('plan');
  const sessionMgmtEnabled = auth.meta?.service?.session_management_enabled !== false;

  // 模板列表加载完后，把默认模板补成第一项（避免后端裁掉了 'default'）。
  useEffect(() => {
    if (templates.length === 0) return;
    if (!templates.some((tpl) => tpl.id === createTemplateId)) {
      setCreateTemplateId(templates[0]!.id);
    }
  }, [templates]);

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
        // 当前页已删空 → 自动回退一页
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

  async function handleCreate(ev: Event): Promise<void> {
    ev.preventDefault();
    if (creating) return;
    setCreating(true);
    setCreateError(null);
    try {
      const input: CreateSessionInput = {
        templateId: createTemplateId,
        mode: createMode,
      };
      const res = await createSession(input);
      // 直接跳到新会话详情页
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
      patchRow(item.id, {
        busy: false,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  async function handleDelete(item: SessionSummary): Promise<void> {
    const row = rowStates[item.id] ?? emptyRow;
    if (!row.pendingDelete) {
      patchRow(item.id, { pendingDelete: true });
      // 4s 后自动撤销 pending 状态，避免误触
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

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.page_size)) : 1;
  const items = data?.items ?? [];

  return (
    <main class="min-h-screen px-6 py-10" style={{ background: 'var(--m3-surface)' }}>
      <div class="mx-auto max-w-3xl">
        {/* 顶部条 */}
        <div class="flex items-center justify-between gap-3 mb-6 flex-wrap">
          <div>
            <h1
              class="text-2xl font-semibold"
              style={{ color: 'var(--m3-on-surface)' }}
            >
              {t('sessions.title', '会话列表')}
            </h1>
            <p class="text-sm mt-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {data
                ? t('sessions.subtitle.count', '共 ') + data.total + ' ' +
                  t('sessions.subtitle.unit', '个会话') +
                  (data.scope === 'current_device'
                    ? ' · ' + t('sessions.subtitle.scopeDevice', '仅本设备可见')
                    : '')
                : t('sessions.subtitle.loading', '加载中…')}
            </p>
          </div>
          <button
            type="button"
            onClick={() => location.route('/')}
            class="text-sm underline"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {t('sessions.backHome', '返回首页')}
          </button>
        </div>

        {/* 新建会话表单 */}
        <form
          onSubmit={handleCreate}
          class="rounded-xl p-5 mb-6"
          style={{
            background: 'var(--m3-surface-container)',
            boxShadow: 'var(--m3-elev-1)',
          }}
        >
          <h2
            class="text-base font-medium mb-3"
            style={{ color: 'var(--m3-on-surface)' }}
          >
            {t('sessions.create.title', '新建会话')}
          </h2>
          <div class="flex flex-wrap gap-3">
            <label class="flex flex-col text-xs gap-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('sessions.create.template', '模板')}
              <MenuSelect
                value={createTemplateId}
                onChange={setCreateTemplateId}
                disabled={creating || templates.length === 0}
                minWidth={200}
                options={
                  templates.length === 0
                    ? [{ value: 'default', label: 'default' }]
                    : templates.map((tpl) => ({ value: tpl.id, label: tpl.name || tpl.id }))
                }
              />
            </label>
            <label class="flex flex-col text-xs gap-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('sessions.create.mode', '模式')}
              <MenuSelect
                value={createMode}
                onChange={(v) => setCreateMode(v as 'chat' | 'plan')}
                disabled={creating}
                minWidth={140}
                options={[
                  { value: 'chat', label: t('sessions.mode.chat', '对话') },
                  ...(planEnabled
                    ? [{ value: 'plan', label: t('sessions.mode.plan', 'Plan') }]
                    : []),
                ]}
              />
            </label>
            <div class="flex items-end">
              <button
                type="submit"
                disabled={creating}
                class="px-4 py-2 rounded-md text-sm font-medium disabled:opacity-60"
                style={{
                  background: 'var(--m3-primary)',
                  color: 'var(--m3-on-primary)',
                }}
              >
                {creating
                  ? t('sessions.create.submitting', '正在创建…')
                  : t('sessions.create.submit', '创建并进入')}
              </button>
            </div>
          </div>
          {createError ? (
            <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
              {createError}
            </p>
          ) : null}
        </form>

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
            <button
              type="button"
              onClick={() => refresh()}
              class="ml-3 underline"
            >
              {t('sessions.retry', '重试')}
            </button>
          </div>
        ) : items.length === 0 ? (
          <p
            class="text-center py-12 text-sm"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {t('sessions.empty', '暂无会话，先在上方创建一个吧。')}
          </p>
        ) : (
          <ul class="flex flex-col gap-3">
            {items.map((item) => {
              const row = rowStates[item.id] ?? emptyRow;
              const editing = row.draftTitle !== null;
              return (
                <li
                  key={item.id}
                  class="rounded-xl p-4"
                  style={{
                    background: 'var(--m3-surface-container)',
                    boxShadow: 'var(--m3-elev-1)',
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
                            class="flex-1 px-2 py-1 rounded-md text-sm"
                            style={{
                              background: 'var(--m3-surface)',
                              color: 'var(--m3-on-surface)',
                              border: '1px solid var(--m3-outline)',
                            }}
                            autoFocus
                          />
                          <button
                            type="button"
                            onClick={() => handleRenameSubmit(item)}
                            disabled={row.busy}
                            class="text-xs px-2 py-1 rounded-md"
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
                        <button
                          type="button"
                          onClick={() => location.route(`/threads/${item.id}`)}
                          class="text-base font-medium hover:underline text-left truncate block w-full"
                          style={{ color: 'var(--m3-on-surface)' }}
                        >
                          {item.title || t('sessions.untitled', '未命名会话')}
                        </button>
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
                          · {item.message_count}{' '}
                          {t('sessions.messageUnit', '条消息')}
                        </span>
                      </div>
                      {row.error ? (
                        <p class="text-xs mt-2" style={{ color: 'var(--m3-error)' }}>
                          {row.error}
                        </p>
                      ) : null}
                    </div>
                    {sessionMgmtEnabled && !editing ? (
                      <div class="flex flex-col items-end gap-1">
                        <button
                          type="button"
                          onClick={() =>
                            patchRow(item.id, { draftTitle: item.title, error: undefined })
                          }
                          class="text-xs underline"
                          style={{ color: 'var(--m3-on-surface-variant)' }}
                        >
                          {t('sessions.rename.action', '重命名')}
                        </button>
                        <button
                          type="button"
                          onClick={() => handleDelete(item)}
                          disabled={row.busy}
                          class="text-xs underline"
                          style={{
                            color: row.pendingDelete ? 'var(--m3-error)' : 'var(--m3-on-surface-variant)',
                          }}
                        >
                          {row.busy
                            ? t('sessions.delete.deleting', '正在删除…')
                            : row.pendingDelete
                              ? t('sessions.delete.confirm', '再次点击确认删除')
                              : t('sessions.delete.action', '删除')}
                        </button>
                      </div>
                    ) : null}
                  </div>
                </li>
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
              class="px-3 py-1.5 rounded-md disabled:opacity-50"
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
              class="px-3 py-1.5 rounded-md disabled:opacity-50"
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
    </main>
  );
}
