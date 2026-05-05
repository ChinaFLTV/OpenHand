// 单会话页专用 TopBar (1:1 对齐 OpenHand App 端 home page 顶部条):
// - 标题区: 返回按钮 + 可点击重命名的标题 + 模板/计数副标题
// - 工具区:
//     模式 chip (普通/Plan/图像/视频/音频)
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

export interface SessionToolbarCapsule {
  key: string;
  icon: string;
  label: string;
  title?: string;
  tone?: 'neutral' | 'primary' | 'warning' | 'success';
  onClick?: () => void;
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
    sessionId,
    capsules = [],
    trailing,
  } = props;

  const [editing, setEditing] = useState(false);
  const [draftTitle, setDraftTitle] = useState(title);
  const titleInputRef = useRef<HTMLInputElement | null>(null);
  const moreMenuAnchorRef = useRef<HTMLDivElement | null>(null);
  const [showMore, setShowMore] = useState(false);
  const [renaming, setRenaming] = useState(false);

  useEffect(() => {
    if (!editing) setDraftTitle(title);
  }, [title, editing]);

  useEffect(() => {
    if (editing) titleInputRef.current?.focus();
  }, [editing]);

  // 任意菜单打开时, 点击外部关闭
  useEffect(() => {
    if (!showMore) return;
    function close(e: MouseEvent) {
      const t = e.target as HTMLElement;
      if (!t.closest('[data-topbar-menu]')) {
        setShowMore(false);
      }
    }
    window.addEventListener('mousedown', close);
    return () => window.removeEventListener('mousedown', close);
  }, [showMore]);

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
      class="oh-session-topbar rounded-xl px-3 py-2 flex items-center gap-2 flex-wrap"
      style={{
        background: 'var(--m3-surface-container)',
        boxShadow: 'var(--m3-elev-1)',
      }}
    >
      {onBack ? (
        <button
          type="button"
          onClick={onBack}
          class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm flex-none"
          style={{
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
          }}
          title={t('detail.backToList', '返回会话列表')}
        >
          ←
        </button>
      ) : null}

      <div class="flex-1 min-w-0">
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
            class="w-full text-sm font-semibold px-2 py-1 rounded-md"
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
              class="text-sm font-semibold"
              style={{ color: 'var(--m3-on-surface)' }}
            >
              {title}
            </span>
          </button>
        )}
        {capsules.length > 0 ? (
          <div class="mt-1 flex items-center gap-1.5 flex-wrap pb-0.5">
            {capsules.map((item) => (
              <ToolbarCapsule key={item.key} capsule={item} />
            ))}
          </div>
        ) : subtitle ? (
          <p
            class="text-xs truncate"
            style={{ color: 'var(--m3-on-surface-variant)' }}
          >
            {subtitle}
          </p>
        ) : null}
      </div>

      {isRunning && canStop && onStop ? (
        <button
          type="button"
          onClick={onStop}
          disabled={stopping}
          class="oh-tap-press text-xs px-2.5 py-1 rounded-m3-sm flex-none flex items-center gap-1.5 disabled:opacity-50"
          style={{
            border: '1px solid var(--m3-error)',
            color: 'var(--m3-error)',
          }}
          title={t('composer.stop', '停止响应')}
        >
          <span
            class="oh-pulse-soft inline-block"
            aria-hidden
            style={{
              width: 6,
              height: 6,
              borderRadius: '50%',
              background: 'var(--m3-error)',
            }}
          />
          {stopping ? t('composer.stopping', '正在停止…') : t('composer.stop', '停止')}
        </button>
      ) : null}

      <div ref={moreMenuAnchorRef} class="relative" data-topbar-menu>
        <button
          type="button"
          onClick={() => {
            setShowMore((v) => !v);
          }}
          class="oh-tap-press text-xs px-2 py-1 rounded-m3-sm"
          style={{
            color: 'var(--m3-on-surface-variant)',
            border: '1px solid var(--m3-outline)',
          }}
          title={t('topbar.more', '更多')}
        >
          ⋯
        </button>
        {showMore ? (
          <Menu anchorRef={moreMenuAnchorRef}>
            {onRename ? (
              <MenuItem onClick={() => { setShowMore(false); setEditing(true); }}>
                {t('topbar.rename', '重命名')}
              </MenuItem>
            ) : null}
            {onExport ? (
              <MenuItem onClick={() => { setShowMore(false); onExport(); }}>
                {t('topbar.export', '导出 JSON')}
              </MenuItem>
            ) : null}
            {sessionId ? (
              <MenuItem
                onClick={async () => {
                  setShowMore(false);
                  await copySessionId();
                }}
              >
                {t('topbar.copyId', '复制会话 ID')}
              </MenuItem>
            ) : null}
            {onDelete ? (
              <MenuItem
                tone="danger"
                onClick={() => { setShowMore(false); onDelete(); }}
              >
                {t('topbar.delete', '删除会话')}
              </MenuItem>
            ) : null}
          </Menu>
        ) : null}
      </div>

      {trailing}

    </header>
  );
}

function ToolbarCapsule({ capsule }: { capsule: SessionToolbarCapsule }) {
  const toneColor = capsule.tone === 'primary'
    ? 'var(--m3-primary)'
    : capsule.tone === 'warning'
      ? '#b45309'
      : capsule.tone === 'success'
        ? '#15803d'
        : 'var(--m3-on-surface-variant)';
  const baseClass = 'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] flex-none max-w-[240px]';
  const baseStyle = {
    background: 'var(--m3-surface)',
    color: toneColor,
    border: `1px solid color-mix(in srgb, ${toneColor} 28%, transparent)`,
    fontWeight: 600,
  };
  const children = (
    <>
      <span aria-hidden>{capsule.icon}</span>
      <span class="truncate">{capsule.label}</span>
    </>
  );
  if (!capsule.onClick) {
    return (
      <span class={baseClass} style={baseStyle} title={capsule.title ?? capsule.label}>
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
}: {
  children: ComponentChildren;
  anchorRef: { current: HTMLElement | null };
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
      class="fixed rounded-m3-sm py-1 oh-appear-up"
      style={{
        background: 'var(--m3-surface)',
        boxShadow: 'var(--m3-elev-2)',
        border: '1px solid var(--m3-outline)',
        minWidth: '180px',
        maxWidth: 'calc(100vw - 16px)',
        top: `${position.top}px`,
        left: `${position.left}px`,
        zIndex: 2300,
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
}: {
  children: ComponentChildren;
  onClick: () => void;
  active?: boolean;
  tone?: 'danger';
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      class="w-full text-left text-xs px-3 py-1.5 oh-tap-press flex items-center gap-1"
      style={{
        background: active
          ? 'color-mix(in srgb, var(--m3-primary) 10%, transparent)'
          : 'transparent',
        color: tone === 'danger'
          ? 'var(--m3-error)'
          : active
            ? 'var(--m3-primary)'
            : 'var(--m3-on-surface)',
        fontWeight: active ? 600 : 400,
      }}
    >
      {children}
      {active ? <span class="ml-auto">✓</span> : null}
    </button>
  );
}
