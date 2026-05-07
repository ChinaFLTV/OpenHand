// 单会话页专用 TopBar (1:1 对齐 OpenHand App 端 home page 顶部条):
// - 标题区: 返回按钮 + 可点击重命名的标题 + 模板/计数副标题
// - 工具区:
//     模式 chip (聊天模式/计划模式/图像/视频/音频)
//     模型 chip (点击弹出 ModelPickerDialog)
//     权限 chip (默认 ask, App 端 normal/auto/ask 等)
//     停止按钮 (sendPhase != idle 时高亮)
//     More 菜单 (重命名 / 删除 / 导出 / 复制 ID)
// - 实时通道 badge (实时/轮询) 已在状态条; 此处不重复

import { useEffect, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { createPortal } from 'preact/compat';
import type { ApiMetaModel } from '../api/meta';
import { t } from '../i18n';
import { showSnackbar } from './Snackbar';

const TOPBAR_MENU_EXIT_MS = 180;

export interface SessionToolbarCapsule {
  key: string;
  icon: SessionToolbarIconName;
  label: string;
  title?: string;
  tone?: 'neutral' | 'primary' | 'warning' | 'success';
  onClick?: () => void;
}

export type SessionToolbarIconName =
  | 'mode'
  | 'runtime'
  | 'permission'
  | 'template'
  | 'files'
  | 'metadata'
  | 'audit'
  | 'tokens';

type TopBarIconName = SessionToolbarIconName
  | 'back'
  | 'more'
  | 'check'
  | 'rename'
  | 'export'
  | 'fullscreen'
  | 'fullscreenExit'
  | 'copy'
  | 'trash';

function TopBarIcon({ name, size = 16 }: { name: TopBarIconName; size?: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.9,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    focusable: 'false',
    'aria-hidden': true,
    class: 'oh-topbar-icon-svg',
  };
  switch (name) {
    case 'back':
      return <svg {...common}><path d="m15 18-6-6 6-6" /></svg>;
    case 'more':
      return <svg {...common}><circle cx="5" cy="12" r="1.4" /><circle cx="12" cy="12" r="1.4" /><circle cx="19" cy="12" r="1.4" /></svg>;
    case 'check':
      return <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
    case 'mode':
      return <svg {...common}><path d="M5 6h14M7 12h10M5 18h14" /></svg>;
    case 'runtime':
      return <svg {...common}><path d="M4 13a8 8 0 1 0 2.1-5.4" /><path d="M4 5v5h5" /><path d="M12 8v4l2.5 2" /></svg>;
    case 'permission':
      return <svg {...common}><path d="M12 3 5 6v5c0 4.4 2.8 8.4 7 10 4.2-1.6 7-5.6 7-10V6z" /><path d="m9.5 12 1.7 1.7 3.6-4" /></svg>;
    case 'template':
      return <svg {...common}><path d="M12 3 4 7l8 4 8-4z" /><path d="m4 12 8 4 8-4" /><path d="m4 17 8 4 8-4" /></svg>;
    case 'files':
      return <svg {...common}><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h4l2 2h5A2.5 2.5 0 0 1 20 8.5v7A2.5 2.5 0 0 1 17.5 18h-11A2.5 2.5 0 0 1 4 15.5z" /></svg>;
    case 'metadata':
      return <svg {...common}><ellipse cx="12" cy="5.5" rx="6" ry="2.5" /><path d="M6 5.5v6c0 1.4 2.7 2.5 6 2.5s6-1.1 6-2.5v-6" /><path d="M6 11.5v6c0 1.4 2.7 2.5 6 2.5s6-1.1 6-2.5v-6" /></svg>;
    case 'audit':
      return <svg {...common}><path d="M9 4h6l1 2h2v14H6V6h2z" /><path d="M9 12h3M9 16h6" /><path d="m14 11 1.2 1.2L18 9.5" /></svg>;
    case 'tokens':
      return <svg {...common}><ellipse cx="9" cy="7" rx="5" ry="2.5" /><path d="M4 7v5c0 1.4 2.2 2.5 5 2.5s5-1.1 5-2.5V7" /><path d="M10 17c.9.6 2.4 1 4 1 2.8 0 5-1.1 5-2.5V11" /><path d="M14 8.5c2.8 0 5 1.1 5 2.5s-2.2 2.5-5 2.5" /></svg>;
    case 'rename':
      return <svg {...common}><path d="M4 20h4.4L19 9.4a2.1 2.1 0 0 0-3-3L5.4 17H4z" /><path d="m14.8 7.6 1.6 1.6" /></svg>;
    case 'export':
      return <svg {...common}><path d="M12 4v10" /><path d="m8 10 4 4 4-4" /><path d="M5 19h14" /></svg>;
    case 'fullscreen':
      return <svg {...common}><path d="M8 4H4v4" /><path d="M4 4l6 6" /><path d="M16 4h4v4" /><path d="m20 4-6 6" /><path d="M8 20H4v-4" /><path d="m4 20 6-6" /><path d="M16 20h4v-4" /><path d="m20 20-6-6" /></svg>;
    case 'fullscreenExit':
      return <svg {...common}><path d="M10 4v6H4" /><path d="m10 10-6-6" /><path d="M14 4v6h6" /><path d="m14 10 6-6" /><path d="M10 20v-6H4" /><path d="m10 14-6 6" /><path d="M14 20v-6h6" /><path d="m14 14 6 6" /></svg>;
    case 'copy':
      return <svg {...common}><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M5 15V7a2 2 0 0 1 2-2h8" /></svg>;
    case 'trash':
      return <svg {...common}><path d="M4 7h16" /><path d="M10 11v6M14 11v6" /><path d="M6 7l1 14h10l1-14" /><path d="M9 7V4h6v3" /></svg>;
  }
}

export interface SessionTopBarProps {
  title: string;
  subtitle?: string;
  onBack?: () => void;
  // 标题点击 → 进入重命名;
  onRename?: (next: string) => Promise<void> | void;

  // 模式
  modes: string[]; // ['normal','plan','image','video','audio']
  mode: string;
  onModeChange(next: string): void;

  // 模型
  models: ApiMetaModel[];
  modelKey: string;
  onModelChange(next: string): void;

  // App 端 fullAccessPermission：默认权限 / 完全访问权限。
  fullAccessPermission: boolean;
  onFullAccessPermissionChange(next: boolean): void;

  // 状态
  sendPhase: string;
  canStop: boolean;
  stopping: boolean;
  onStop?: () => void;

  // 操作
  onDelete?: () => void;
  onExport?: () => void;
  onToggleFullscreen?: () => void;
  fullscreenActive?: boolean;
  sessionId?: string;
  capsules?: SessionToolbarCapsule[];

  trailing?: ComponentChildren;
}

export function SessionTopBar(props: SessionTopBarProps) {
  const {
    title,
    subtitle,
    onBack,
    onRename,
    sendPhase,
    canStop,
    stopping,
    onStop,
    onDelete,
    onExport,
    onToggleFullscreen,
    fullscreenActive = false,
    sessionId,
    capsules = [],
    trailing,
  } = props;

  const [editing, setEditing] = useState(false);
  const [draftTitle, setDraftTitle] = useState(title);
  const titleInputRef = useRef<HTMLInputElement | null>(null);
  const moreMenuAnchorRef = useRef<HTMLDivElement | null>(null);
  const [showMore, setShowMore] = useState(false);
  const [closingMore, setClosingMore] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const moreMenuCloseTimerRef = useRef<number | null>(null);

  const moreMenuVisible = showMore || closingMore;

  function clearMoreMenuCloseTimer() {
    if (moreMenuCloseTimerRef.current == null) return;
    window.clearTimeout(moreMenuCloseTimerRef.current);
    moreMenuCloseTimerRef.current = null;
  }

  function openMoreMenu() {
    clearMoreMenuCloseTimer();
    setClosingMore(false);
    setShowMore(true);
  }

  function requestCloseMoreMenu() {
    if (!showMore || closingMore) return;
    setClosingMore(true);
    clearMoreMenuCloseTimer();
    moreMenuCloseTimerRef.current = window.setTimeout(() => {
      setShowMore(false);
      setClosingMore(false);
      moreMenuCloseTimerRef.current = null;
    }, TOPBAR_MENU_EXIT_MS);
  }

  function toggleMoreMenu() {
    if (showMore && !closingMore) {
      requestCloseMoreMenu();
    } else {
      openMoreMenu();
    }
  }

  useEffect(() => {
    if (!editing) setDraftTitle(title);
  }, [title, editing]);

  useEffect(() => {
    if (editing) titleInputRef.current?.focus();
  }, [editing]);

  useEffect(() => () => clearMoreMenuCloseTimer(), []);

  // 任意菜单打开时, 点击外部关闭
  useEffect(() => {
    if (!showMore || closingMore) return;
    function close(e: MouseEvent) {
      const t = e.target as HTMLElement;
      if (!t.closest('[data-topbar-menu]')) {
        requestCloseMoreMenu();
      }
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') requestCloseMoreMenu();
    }
    window.addEventListener('mousedown', close);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('mousedown', close);
      window.removeEventListener('keydown', onKey);
    };
  }, [showMore, closingMore]);

  async function commitRename() {
    if (renaming) return;
    setEditing(false);
    const next = draftTitle.trim();
    if (next && next !== title && onRename) {
      setRenaming(true);
      try {
        await onRename(next);
      } catch {
        setEditing(true);
      } finally {
        setRenaming(false);
      }
    } else {
      setDraftTitle(title);
    }
  }

  async function copySessionId() {
    if (!sessionId) return;
    try {
      await Promise.race([
        navigator.clipboard.writeText(sessionId),
        new Promise<never>((_, reject) => {
          window.setTimeout(() => reject(new Error('timeout')), 2500);
        }),
      ]);
      showSnackbar(t('topbar.copyId.ok', '已复制会话 ID'), { tone: 'success' });
    } catch (error) {
      const timedOut = error instanceof Error && error.message === 'timeout';
      showSnackbar(
        timedOut
          ? t('topbar.copyId.timeout', '复制会话 ID 超时，请重试')
          : t('topbar.copyId.failed', '复制会话 ID 失败，请检查浏览器剪贴板权限'),
        { tone: 'error' },
      );
    }
  }

  const isRunning = sendPhase !== 'idle' && sendPhase !== '';

  return (
    <header
      class="oh-session-topbar rounded-m3-md px-2.5 py-2"
      style={{
        background: 'var(--m3-surface-container)',
        boxShadow: 'var(--m3-elev-1)',
        border: '1px solid var(--m3-outline-variant)',
      }}
    >
      <div class="oh-session-topbar-row flex items-center gap-2 min-w-0">
        {onBack ? (
          <button
            type="button"
            onClick={onBack}
            class="oh-tap-press oh-icon-button oh-session-back-button flex-none"
            style={{
              color: 'var(--m3-on-surface-variant)',
              border: '1px solid var(--m3-outline-variant)',
              background: 'var(--m3-surface)',
            }}
            title={t('detail.backToList', '返回会话列表')}
          >
            <TopBarIcon name="back" size={18} />
          </button>
        ) : null}

        <div class="oh-session-title-block min-w-0 flex-none">
          {editing ? (
            <input
              ref={titleInputRef}
              value={draftTitle}
              onInput={(e) => setDraftTitle((e.currentTarget as HTMLInputElement).value)}
              onBlur={commitRename}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void commitRename();
                if (e.key === 'Escape') {
                  setEditing(false);
                  setDraftTitle(title);
                }
              }}
              class="w-full text-sm font-semibold px-2 py-1 rounded-m3-sm"
              style={{
                background: 'var(--m3-surface)',
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-primary)',
              }}
            />
          ) : (
            <button
              type="button"
              onClick={() => onRename && setEditing(true)}
              class="block w-full text-left truncate"
              disabled={!onRename || renaming}
              title={onRename ? t('topbar.renameHint', '点击重命名') : undefined}
            >
              <span
                key={title}
                class="oh-title-spring block text-sm font-semibold truncate"
                style={{ color: 'var(--m3-on-surface)' }}
              >
                {title}
              </span>
            </button>
          )}
          {subtitle ? (
            <p
              class="text-[11px] truncate mt-0.5"
              style={{ color: 'var(--m3-on-surface-variant)' }}
            >
              {subtitle}
            </p>
          ) : null}
        </div>

        {capsules.length > 0 ? (
          <div class="oh-session-capsule-rail flex-1 min-w-0 overflow-x-auto">
            <div class="flex items-center gap-1.5 w-max max-w-none pr-1 py-0.5">
              {capsules.map((item) => (
                <ToolbarCapsule key={item.key} capsule={item} />
              ))}
            </div>
          </div>
        ) : null}

        {isRunning && canStop && onStop ? (
          <button
            type="button"
            onClick={onStop}
            disabled={stopping}
            class="oh-tap-press oh-session-stop-button text-xs px-2.5 py-1.5 rounded-m3-sm flex-none flex items-center gap-1.5 disabled:opacity-50"
            style={{
              border: '1px solid var(--m3-error)',
              color: 'var(--m3-error)',
              background: 'var(--m3-error-container)',
            }}
            title={t('composer.stop', '停止响应')}
          >
            <span
              class="oh-pulse-soft oh-session-stop-dot inline-block"
              aria-hidden
              style={{
                width: 6,
                height: 6,
                borderRadius: '50%',
                background: 'var(--m3-error)',
              }}
            />
            <span class="oh-session-stop-label">
              {stopping ? t('composer.stopping', '正在停止…') : t('composer.stop', '停止')}
            </span>
          </button>
        ) : null}

        <div class="oh-session-topbar-actions flex items-center gap-2 flex-none">
          <div ref={moreMenuAnchorRef} class="relative flex-none" data-topbar-menu>
            <button
              type="button"
              onClick={toggleMoreMenu}
              class="oh-tap-press oh-icon-button"
              style={{
                color: 'var(--m3-on-surface-variant)',
                border: '1px solid var(--m3-outline-variant)',
                background: 'var(--m3-surface)',
              }}
              title={t('topbar.more', '更多')}
            >
              <TopBarIcon name="more" size={17} />
            </button>
            {moreMenuVisible ? (
              <Menu anchorRef={moreMenuAnchorRef} closing={closingMore}>
                {onRename ? (
                  <MenuItem icon="rename" onClick={() => { requestCloseMoreMenu(); setEditing(true); }}>
                    {t('topbar.rename', '重命名')}
                  </MenuItem>
                ) : null}
                {onExport ? (
                  <MenuItem icon="export" onClick={() => { requestCloseMoreMenu(); onExport(); }}>
                    {t('topbar.export', '导出 JSON')}
                  </MenuItem>
                ) : null}
                {onToggleFullscreen ? (
                  <MenuItem
                    icon={fullscreenActive ? 'fullscreenExit' : 'fullscreen'}
                    onClick={() => { requestCloseMoreMenu(); onToggleFullscreen(); }}
                  >
                    {fullscreenActive
                      ? t('topbar.fullscreen.exit', '退出全屏')
                      : t('topbar.fullscreen.enter', '浏览器全屏')}
                  </MenuItem>
                ) : null}
                {sessionId ? (
                  <MenuItem
                    icon="copy"
                    onClick={async () => {
                      requestCloseMoreMenu();
                      await copySessionId();
                    }}
                  >
                    {t('topbar.copyId', '复制会话 ID')}
                  </MenuItem>
                ) : null}
                {onDelete ? (
                  <MenuItem
                    icon="trash"
                    tone="danger"
                    onClick={() => { requestCloseMoreMenu(); onDelete(); }}
                  >
                    {t('topbar.delete', '删除会话')}
                  </MenuItem>
                ) : null}
              </Menu>
            ) : null}
          </div>

          {trailing}
        </div>
      </div>

    </header>
  );
}

function ToolbarCapsule({ capsule }: { capsule: SessionToolbarCapsule }) {
  const toneColor = capsule.tone === 'primary'
    ? 'var(--m3-primary)'
    : capsule.tone === 'warning'
      ? 'var(--oh-full-access)'
      : capsule.tone === 'success'
        ? 'var(--m3-primary)'
        : 'var(--m3-on-surface-variant)';
  const toneBackground = capsule.tone === 'primary'
    ? 'var(--m3-primary-container)'
    : capsule.tone === 'warning'
      ? 'var(--oh-full-access-container)'
      : capsule.tone === 'success'
        ? 'var(--m3-primary-container)'
        : 'var(--m3-surface)';
  const baseClass = 'oh-session-capsule oh-appear-pop inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] flex-none max-w-[240px]';
  const baseStyle = {
    background: toneBackground,
    color: toneColor,
    border: '1px solid var(--m3-outline-variant)',
    fontWeight: 600,
  };
  const children = (
    <>
      <span class="oh-session-capsule-icon" aria-hidden>
        <TopBarIcon name={capsule.icon} size={13.5} />
      </span>
      <span class="truncate">{capsule.label}</span>
    </>
  );
  if (!capsule.onClick) {
    return (
      <span class={baseClass} style={baseStyle} title={capsule.title ?? capsule.label} data-tone={capsule.tone ?? 'neutral'}>
        {children}
      </span>
    );
  }
  return (
    <button
      type="button"
      class={`oh-tap-press ${baseClass}`}
      style={baseStyle}
      onClick={capsule.onClick}
      title={capsule.title ?? capsule.label}
      data-tone={capsule.tone ?? 'neutral'}
    >
      {children}
    </button>
  );
}

const MENU_MIN_WIDTH = 180;
const MENU_VIEWPORT_GAP = 8;
const MENU_OFFSET = 4;

interface TopBarMenuPosition {
  top: number;
  left: number;
}

function computeTopBarMenuPosition(
  anchor: HTMLElement | null,
  menuWidth = MENU_MIN_WIDTH,
  menuHeight = 0,
): TopBarMenuPosition {
  if (typeof window === 'undefined' || !anchor) {
    return { top: MENU_VIEWPORT_GAP, left: MENU_VIEWPORT_GAP };
  }
  const rect = anchor.getBoundingClientRect();
  const usableWidth = Math.max(MENU_MIN_WIDTH, window.innerWidth - MENU_VIEWPORT_GAP * 2);
  const width = Math.min(Math.max(menuWidth, MENU_MIN_WIDTH), usableWidth);
  let left = rect.right - width;
  left = Math.max(MENU_VIEWPORT_GAP, Math.min(left, window.innerWidth - width - MENU_VIEWPORT_GAP));

  let top = rect.bottom + MENU_OFFSET;
  if (
    menuHeight > 0 &&
    top + menuHeight > window.innerHeight - MENU_VIEWPORT_GAP &&
    rect.top - menuHeight - MENU_OFFSET >= MENU_VIEWPORT_GAP
  ) {
    top = rect.top - menuHeight - MENU_OFFSET;
  } else if (menuHeight > 0) {
    top = Math.min(top, window.innerHeight - menuHeight - MENU_VIEWPORT_GAP);
    top = Math.max(MENU_VIEWPORT_GAP, top);
  }
  return { top, left };
}

function Menu({
  children,
  anchorRef,
  closing,
}: {
  children: ComponentChildren;
  anchorRef: { current: HTMLElement | null };
  closing: boolean;
}) {
  const menuRef = useRef<HTMLDivElement | null>(null);
  const [position, setPosition] = useState<TopBarMenuPosition>(() => (
    computeTopBarMenuPosition(anchorRef.current)
  ));

  useEffect(() => {
    const update = () => {
      setPosition(computeTopBarMenuPosition(
        anchorRef.current,
        menuRef.current?.offsetWidth ?? MENU_MIN_WIDTH,
        menuRef.current?.offsetHeight ?? 0,
      ));
    };
    update();
    window.addEventListener('resize', update);
    window.addEventListener('scroll', update, true);
    return () => {
      window.removeEventListener('resize', update);
      window.removeEventListener('scroll', update, true);
    };
  }, [anchorRef]);

  const node = (
    <div
      ref={menuRef}
      data-topbar-menu
      role="menu"
      class={`fixed rounded-m3-sm py-1 ${closing ? 'oh-menu-pop-out' : 'oh-popmenu-pop'}`}
      style={{
        background: 'var(--m3-surface)',
        boxShadow: 'var(--m3-elev-2)',
        border: '1px solid var(--m3-outline)',
        minWidth: '180px',
        maxWidth: 'calc(100vw - 16px)',
        top: `${position.top}px`,
        left: `${position.left}px`,
        zIndex: 2300,
        transformOrigin: 'top right',
      }}
    >
      {children}
    </div>
  );
  return typeof document === 'undefined' ? node : createPortal(node, document.body);
}

function MenuItem({
  children,
  onClick,
  active,
  tone,
  icon,
}: {
  children: ComponentChildren;
  onClick: () => void;
  active?: boolean;
  tone?: 'danger';
  icon?: TopBarIconName;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      class="w-full text-left text-xs px-3 py-1.5 oh-tap-press flex items-center gap-1"
      style={{
        background: active
          ? 'var(--m3-primary-container)'
          : 'transparent',
        color: tone === 'danger'
          ? 'var(--m3-error)'
          : active
            ? 'var(--m3-on-primary-container)'
            : 'var(--m3-on-surface)',
        fontWeight: active ? 600 : 400,
      }}
    >
      {icon ? <TopBarIcon name={icon} size={15} /> : null}
      {children}
      {active ? <span class="ml-auto"><TopBarIcon name="check" size={14} /></span> : null}
    </button>
  );
}
