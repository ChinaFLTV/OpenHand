// 单会话页专用顶部栏，对齐 OpenHand App 端首页顶部条：
// - 标题区: 返回按钮 + 可点击重命名的标题 + 模板/计数副标题
// - 工具区: 仅接收上层按 App 端顺序构造好的胶囊；会话模式 / 权限不在 TopBar 重复展示。
// - 更多菜单：重命名 / 删除 / 导出 / 复制 ID。

import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { t } from '../i18n';
import { useRafScheduler } from '../hooks/useRafScheduler';
import { useDelayedVisibility } from '../hooks/useDelayedVisibility';
import { useDismissibleOverlay } from '../hooks/useDismissibleOverlay';
import {
  DEFAULT_FLOATING_ANCHOR_GAP,
  DEFAULT_FLOATING_VIEWPORT_PADDING,
  computeAnchoredMenuPosition,
} from '../shared/ui/floating_position';
import { OverlayPortal } from './OverlayPortal';
import { copyTextWithFeedback, showSnackbar } from './Snackbar';
import { RollingText } from './RollingText';
import { AnimatedTitleText } from './AnimatedTitleText';
import { BrowserFullscreenButton, BrowserFullscreenIcon } from './BrowserFullscreenButton';
import { svgIconProps } from '../shared/ui/svg_icon';
import { SESSION_TITLE_MAX_CHARACTERS } from '../api/sessions';

export interface SessionToolbarCapsule {
  key: string;
  icon: SessionToolbarIconName;
  label: string;
  title?: string;
  tone?: 'neutral' | 'primary' | 'warning' | 'success' | 'muted';
  /** 胶囊右侧常驻徽标，用于展示缓存命中率等紧凑状态。 */
  badge?: {
    text: string;
    title?: string;
    tone?: 'success' | 'warning' | 'primary' | 'neutral';
  };
  /** 右侧环形进度，值域 0~1。 */
  progress?: {
    ratio: number;
    title?: string;
  };
  onClick?: () => void;
}

type SessionToolbarIconName =
  | 'mode'
  | 'goal'
  | 'runtime'
  | 'permission'
  | 'template'
  | 'files'
  | 'metadata'
  | 'audit'
  | 'tokens'
  | 'debug'
  | 'throttle';

type TopBarIconName = SessionToolbarIconName
  | 'back'
  | 'more'
  | 'check'
  | 'rename'
  | 'export'
  | 'trajectory'
  | 'fullscreen'
  | 'fullscreenExit'
  | 'copy'
  | 'trash';

function TopBarIcon({ name, size = 16 }: { name: TopBarIconName; size?: number }) {
  const common = svgIconProps({
    size,
    strokeWidth: 1.9,
    class: 'oh-topbar-icon-svg',
  });
  switch (name) {
    case 'back':
      return <svg {...common}><path d="m15 18-6-6 6-6" /></svg>;
    case 'more':
      return <svg {...common}><circle cx="5" cy="12" r="1.4" /><circle cx="12" cy="12" r="1.4" /><circle cx="19" cy="12" r="1.4" /></svg>;
    case 'check':
      return <svg {...common}><path d="m5 12 4 4 10-10" /></svg>;
    case 'mode':
      return <svg {...common}><path d="M5 6h14M7 12h10M5 18h14" /></svg>;
    case 'goal':
      return <svg {...common}><circle cx="12" cy="12" r="7" /><circle cx="12" cy="12" r="3" /><path d="M12 2v3M12 19v3M2 12h3M19 12h3" /></svg>;
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
    case 'debug':
      return <svg {...common}><rect x="6" y="9" width="12" height="10" rx="3" /><path d="M9 9V7a3 3 0 0 1 6 0v2" /><path d="M3 13h3M18 13h3M3 18l3-2M18 16l3 2M3 8l3 2M18 10l3-2" /></svg>;
    case 'throttle':
      return <svg {...common}><path d="M13 2 4 14h7l-1 8 9-12h-7l1-8z" /></svg>;
    case 'rename':
      return <svg {...common}><path d="M4 20h4.4L19 9.4a2.1 2.1 0 0 0-3-3L5.4 17H4z" /><path d="m14.8 7.6 1.6 1.6" /></svg>;
    case 'export':
      return <svg {...common}><path d="M12 4v10" /><path d="m8 10 4 4 4-4" /><path d="M5 19h14" /></svg>;
    case 'trajectory':
      return <svg {...common}><path d="M4 7h4M11 7h9M4 12h8M15 12h5M4 17h3M10 17h10" /><circle cx="9.5" cy="7" r="1.5" /><circle cx="13.5" cy="12" r="1.5" /><circle cx="8.5" cy="17" r="1.5" /></svg>;
    case 'fullscreen':
      return <BrowserFullscreenIcon active={false} size={size} className="oh-topbar-icon-svg" />;
    case 'fullscreenExit':
      return <BrowserFullscreenIcon active size={size} className="oh-topbar-icon-svg" />;
    case 'copy':
      return <svg {...common}><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M5 15V7a2 2 0 0 1 2-2h8" /></svg>;
    case 'trash':
      return <svg {...common}><path d="M4 7h16" /><path d="M10 11v6M14 11v6" /><path d="M6 7l1 14h10l1-14" /><path d="M9 7V4h6v3" /></svg>;
  }
}

interface SessionTopBarProps {
  title: string;
  subtitle?: string;
  titleGenerating?: boolean;
  onBack?: () => void;
  // 标题点击 → 进入重命名;
  onRename?: (next: string) => boolean | void | Promise<boolean | void>;

  // 操作
  onDelete?: () => void;
  onExport?: () => void;
  onGenerateTitle?: () => void;
  onOpenTrajectory?: () => void;
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
    titleGenerating = false,
    onBack,
    onRename,
    onDelete,
    onExport,
    onGenerateTitle,
    onOpenTrajectory,
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
  const moreMenuPanelRef = useRef<HTMLDivElement | null>(null);
  const moreMenuDismissTargets = useMemo(
    () => [moreMenuAnchorRef, moreMenuPanelRef],
    [],
  );
  const [renaming, setRenaming] = useState(false);
  const renamingRef = useRef(false);
  const cancelRenameBlurRef = useRef(false);
  const {
    open: moreMenuOpen,
    closing: closingMore,
    visible: moreMenuVisible,
    hide: requestCloseMoreMenu,
    toggle: toggleMoreMenu,
  } = useDelayedVisibility();

  useEffect(() => {
    if (!editing) setDraftTitle(title);
  }, [title, editing]);

  useEffect(() => {
    if (!editing) return;
    cancelRenameBlurRef.current = false;
    titleInputRef.current?.focus();
  }, [editing]);

  useDismissibleOverlay({
    active: moreMenuOpen && !closingMore,
    targets: moreMenuDismissTargets,
    onDismiss: requestCloseMoreMenu,
  });

  async function commitRename() {
    if (cancelRenameBlurRef.current) {
      cancelRenameBlurRef.current = false;
      return;
    }
    if (renamingRef.current) return;
    renamingRef.current = true;
    setEditing(false);
    const next = draftTitle.trim();
    if (next && next !== title && onRename) {
      setRenaming(true);
      try {
        const renamed = await onRename(next);
        if (renamed === false) setEditing(true);
      } catch {
        setEditing(true);
        showSnackbar(t('topbar.rename.failed', '重命名失败，请稍后重试'), {
          tone: 'error',
        });
      } finally {
        renamingRef.current = false;
        setRenaming(false);
      }
    } else {
      renamingRef.current = false;
      setDraftTitle(title);
    }
  }

  async function copySessionId() {
    if (!sessionId) return;
    await copyTextWithFeedback(
      sessionId,
      t('topbar.copyId.ok', '已复制会话 ID'),
      t('topbar.copyId.failed', '复制会话 ID 失败，请检查浏览器剪贴板权限'),
    );
  }

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
        <div class="oh-session-topbar-leading flex items-center gap-2 min-w-0 flex-none">
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
                maxLength={SESSION_TITLE_MAX_CHARACTERS}
                onInput={(e) => setDraftTitle((e.currentTarget as HTMLInputElement).value)}
                onBlur={commitRename}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    void commitRename();
                  }
                  if (e.key === 'Escape') {
                    e.preventDefault();
                    cancelRenameBlurRef.current = true;
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
                onClick={() => onRename && !titleGenerating && setEditing(true)}
                class="block w-full text-left truncate"
                disabled={!onRename || renaming || titleGenerating}
                title={titleGenerating
                  ? t('topbar.titleGenerating', '标题生成中…')
                  : onRename ? t('topbar.renameHint', '点击重命名') : undefined}
              >
                <span class="flex items-center gap-1.5 min-w-0">
                  <AnimatedTitleText
                    text={title}
                    className="block text-sm font-semibold truncate oh-text-body"
                  />
                  {titleGenerating ? (
                    <span class="oh-title-generating-spinner flex-none" aria-label={t('topbar.titleGenerating', '标题生成中…')}>
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" class="oh-spin" style={{ color: 'var(--m3-primary)', opacity: 0.7 }}>
                        <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
                      </svg>
                    </span>
                  ) : null}
                </span>
              </button>
            )}
            {subtitle ? (
              <p
                class="text-[11px] truncate mt-0.5 oh-text-muted"
              >
                {subtitle}
              </p>
            ) : null}
          </div>
        </div>

        {/* 胶囊紧贴右侧全屏按钮：左标题 / 右胶囊+操作，中间自然留白。 */}
        <div class="oh-session-topbar-trailing flex items-center gap-2 min-w-0 flex-1 justify-end">
          {capsules.length > 0 ? (
            <div class="oh-session-capsule-rail min-w-0 overflow-x-auto">
              <div class="flex items-center gap-1.5 w-max max-w-none py-0.5">
                {capsules.map((item) => (
                  <ToolbarCapsule key={item.key} capsule={item} />
                ))}
              </div>
            </div>
          ) : null}

          <div class="oh-session-topbar-actions flex items-center gap-2 flex-none">
            {onToggleFullscreen ? (
              <BrowserFullscreenButton
                active={fullscreenActive}
                onClick={onToggleFullscreen}
              />
            ) : null}

            <div ref={moreMenuAnchorRef} class="relative flex-none">
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
                <Menu
                  anchorRef={moreMenuAnchorRef}
                  menuRef={moreMenuPanelRef}
                  closing={closingMore}
                >
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
                  {onGenerateTitle ? (
                    <MenuItem icon="rename" onClick={() => { requestCloseMoreMenu(); onGenerateTitle(); }}>
                      {t('topbar.generateTitle', '获取 AI 摘要标题')}
                    </MenuItem>
                  ) : null}
                  {onOpenTrajectory ? (
                    <MenuItem icon="trajectory" onClick={() => { requestCloseMoreMenu(); onOpenTrajectory(); }}>
                      {t('topbar.trajectory', '轨迹')}
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
        : capsule.tone === 'muted'
          ? 'var(--m3-on-surface-variant)'
          : 'var(--m3-on-surface-variant)';
  const toneBackground = capsule.tone === 'primary'
    ? 'var(--m3-primary-container)'
    : capsule.tone === 'warning'
      ? 'var(--oh-full-access-container)'
      : capsule.tone === 'success'
        ? 'var(--m3-primary-container)'
        : capsule.tone === 'muted'
          ? 'var(--m3-surface-variant)'
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
      {capsule.label ? <span class="truncate"><RollingText text={capsule.label} /></span> : null}
      {capsule.badge ? <CapsuleBadge badge={capsule.badge} /> : null}
      {capsule.progress ? <CapsuleProgressRing progress={capsule.progress} /> : null}
    </>
  );
  if (!capsule.onClick) {
    return (
      <span
        class={baseClass}
        style={baseStyle}
        title={capsule.title ?? capsule.label}
        data-tone={capsule.tone ?? 'neutral'}
        data-capsule-key={capsule.key}
      >
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
      data-capsule-key={capsule.key}
    >
      {children}
    </button>
  );
}

function CapsuleProgressRing({
  progress,
}: {
  progress: NonNullable<SessionToolbarCapsule['progress']>;
}) {
  const ratio = Number.isFinite(progress.ratio)
    ? Math.min(1, Math.max(0, progress.ratio))
    : 0;
  const color = ratio >= 0.9
    ? 'var(--m3-error)'
    : ratio >= 0.7
      ? 'var(--m3-tertiary)'
      : 'var(--m3-primary)';
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 20 20"
      class="ml-0.5 shrink-0"
      role="img"
      aria-label={progress.title}
    >
      <circle
        cx="10"
        cy="10"
        r="7.25"
        fill="none"
        stroke="var(--m3-outline-variant)"
        stroke-width="2.6"
        opacity="0.62"
      />
      <circle
        cx="10"
        cy="10"
        r="7.25"
        fill="none"
        stroke={color}
        stroke-width="2.6"
        stroke-linecap="round"
        pathLength="1"
        stroke-dasharray="1"
        stroke-dashoffset={1 - ratio}
        transform="rotate(-90 10 10)"
        style={{
          transition: 'stroke-dashoffset 680ms cubic-bezier(.34, 1.56, .64, 1), stroke 240ms ease-out',
        }}
      />
    </svg>
  );
}

// 胶囊右侧的常驻徽标。success/primary 跟随主题主色，warning 使用全局警示色，
// neutral 低对比度。专用于 token 胶囊上的「缓存收益 %」，未来也可承载其它即时统计指标。
function CapsuleBadge({
  badge,
}: {
  badge: NonNullable<SessionToolbarCapsule['badge']>;
}) {
  const tone = badge.tone ?? 'success';
  const fg = tone === 'success'
    ? 'var(--m3-primary)'
    : tone === 'warning'
      ? 'var(--oh-full-access)'
      : tone === 'primary'
        ? 'var(--m3-primary)'
        : 'var(--m3-on-surface-variant)';
  const bg = tone === 'success'
    ? 'color-mix(in srgb, var(--m3-primary) 18%, transparent)'
    : tone === 'warning'
      ? 'color-mix(in srgb, var(--oh-full-access) 22%, transparent)'
      : tone === 'primary'
        ? 'var(--m3-primary-container)'
        : 'var(--m3-surface-variant)';
  return (
    <span
      class="ml-1 inline-flex items-center gap-0.5 rounded-full px-1.5 py-[1px] text-[10px] font-bold tabular-nums"
      style={{ background: bg, color: fg }}
      title={badge.title ?? undefined}
    >
      {badge.text}
    </span>
  );
}

const MENU_MIN_WIDTH = 180;
const MENU_VIEWPORT_GAP = DEFAULT_FLOATING_VIEWPORT_PADDING;
const MENU_OFFSET = DEFAULT_FLOATING_ANCHOR_GAP;

interface TopBarMenuPosition {
  top: number;
  left: number;
}

function computeTopBarMenuPosition(
  anchor: HTMLElement | null,
  menuWidth = MENU_MIN_WIDTH,
  menuHeight = 0,
): TopBarMenuPosition {
  const position = computeAnchoredMenuPosition({
    anchor,
    preferredWidth: menuWidth,
    minWidth: MENU_MIN_WIDTH,
    measuredHeight: menuHeight,
    align: 'right',
    viewportPadding: MENU_VIEWPORT_GAP,
    gap: MENU_OFFSET,
  });
  return { top: position.top, left: position.left };
}

function Menu({
  children,
  anchorRef,
  menuRef,
  closing,
}: {
  children: ComponentChildren;
  anchorRef: { current: HTMLElement | null };
  menuRef: { current: HTMLDivElement | null };
  closing: boolean;
}) {
  const [position, setPosition] = useState<TopBarMenuPosition>(() => (
    computeTopBarMenuPosition(anchorRef.current)
  ));

  const update = useCallback(() => {
    setPosition(computeTopBarMenuPosition(
      anchorRef.current,
      menuRef.current?.offsetWidth ?? MENU_MIN_WIDTH,
      menuRef.current?.offsetHeight ?? 0,
    ));
  }, [anchorRef]);
  const { schedule: schedulePosition, flush: updatePositionNow, cancel: cancelPosition } = useRafScheduler(update);

  useEffect(() => {
    updatePositionNow();
    window.addEventListener('resize', schedulePosition);
    window.addEventListener('scroll', schedulePosition, true);
    return () => {
      window.removeEventListener('resize', schedulePosition);
      window.removeEventListener('scroll', schedulePosition, true);
      cancelPosition();
    };
  }, [updatePositionNow, schedulePosition, cancelPosition]);

  const node = (
    <div
      ref={menuRef}
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
  return <OverlayPortal>{node}</OverlayPortal>;
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
