// 通用 popover 菜单：触发器 + 弹出菜单项。点击外部 / Esc 自动关闭。
//
// 实现要点：
// - 菜单项通过 `createPortal` 直接挂到 `document.body`，并使用 `position: fixed`
//   配合触发器的 `getBoundingClientRect()` 计算坐标，避免被祖先 transform / overflow
//   截断（之前用 `position: absolute` + z-30 在 `Appear` 包裹的 translateY 容器里
//   会被下一张卡片或 ListView 裁掉，导致菜单看起来"被遮挡"）。
// - 监听 scroll / resize / 卡片重新布局，让菜单坐标实时跟随触发器。
// - 默认 align='right' 时菜单右对齐到触发器右边，并在视口内自动收边避免溢出。

import { createPortal } from 'preact/compat';
import type { ComponentChildren } from 'preact';
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';

export interface PopMenuItem {
  key: string;
  label: string;
  onClick: () => void;
  /// 'danger' → 红色文字（删除等）。
  variant?: 'default' | 'danger';
  /// 禁用时按钮可见但不可点。
  disabled?: boolean;
  /// 当前选中项；禁用时仍保持主题选中态，避免看起来像普通不可用项。
  selected?: boolean;
}

export interface PopMenuProps {
  items: PopMenuItem[];
  /// 触发器；调用方控制其外观。
  trigger: (props: { open: boolean; toggle: () => void }) => ComponentChildren;
  /// Optional class for callers that need layout control over the trigger wrap.
  wrapperClassName?: string;
  /// 默认 'right'，菜单从触发器右上角弹出。
  align?: 'left' | 'right';
  /// 可选固定宽度，适合模式选择等短菜单，避免长禁用说明把菜单撑宽。
  width?: number;
}

interface MenuPos {
  top: number;
  left: number;
  width: number;
}

const VIEWPORT_PADDING = 8;
const MENU_GAP = 4;

function PopMenuCheckIcon() {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="m5 12 4 4 10-10" />
    </svg>
  );
}

export function PopMenu({ items, trigger, wrapperClassName = '', align = 'right', width }: PopMenuProps) {
  const [open, setOpen] = useState(false);
  const [closing, setClosing] = useState(false);
  const [pos, setPos] = useState<MenuPos | null>(null);
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<number | null>(null);
  const menuVisible = open || closing;

  const clearCloseTimer = () => {
    if (closeTimerRef.current == null) return;
    window.clearTimeout(closeTimerRef.current);
    closeTimerRef.current = null;
  };

  const openMenu = () => {
    clearCloseTimer();
    setClosing(false);
    setOpen(true);
  };

  const requestClose = () => {
    if (!open || closing) return;
    setClosing(true);
    clearCloseTimer();
    closeTimerRef.current = window.setTimeout(() => {
      setOpen(false);
      setClosing(false);
      closeTimerRef.current = null;
    }, 180);
  };

  useEffect(() => () => clearCloseTimer(), []);

  // 关闭：点击外部 / Esc。
  useEffect(() => {
    if (!open || closing) return;
    const onDown = (ev: MouseEvent) => {
      const target = ev.target as Node | null;
      if (!target) return;
      if (wrapRef.current?.contains(target)) return;
      if (menuRef.current?.contains(target)) return;
      requestClose();
    };
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape') requestClose();
    };
    window.addEventListener('mousedown', onDown);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('mousedown', onDown);
      window.removeEventListener('keydown', onKey);
    };
  }, [open, closing]);

  // 计算菜单坐标：fixed 定位 + 视口内夹紧。
  const recompute = () => {
    const trig = wrapRef.current;
    if (!trig) return;
    const r = trig.getBoundingClientRect();
    const menuEl = menuRef.current;
    const menuRect = menuEl?.getBoundingClientRect();
    const desiredWidth = width ?? Math.max(r.width, 160);
    const menuWidth = menuRect?.width ?? desiredWidth;
    const menuHeight = menuRect?.height ?? 160;
    let left = align === 'right' ? r.right - menuWidth : r.left;
    let top = r.bottom + MENU_GAP;
    // 右侧夹紧。
    const maxLeft = window.innerWidth - menuWidth - VIEWPORT_PADDING;
    if (left > maxLeft) left = maxLeft;
    if (left < VIEWPORT_PADDING) left = VIEWPORT_PADDING;
    // 底部不够时翻到触发器上方。
    if (top + menuHeight > window.innerHeight - VIEWPORT_PADDING) {
      const above = r.top - menuHeight - MENU_GAP;
      if (above >= VIEWPORT_PADDING) top = above;
    }
    setPos({ top, left, width: desiredWidth });
  };

  useLayoutEffect(() => {
    if (!menuVisible) {
      setPos(null);
      return;
    }
    recompute();
    const onScrollOrResize = () => recompute();
    window.addEventListener('scroll', onScrollOrResize, true);
    window.addEventListener('resize', onScrollOrResize);
    return () => {
      window.removeEventListener('scroll', onScrollOrResize, true);
      window.removeEventListener('resize', onScrollOrResize);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [menuVisible]);

  // 第一次渲染拿到菜单实际尺寸后再校准一次（避免 minWidth 估算偏差）。
  useLayoutEffect(() => {
    if (!menuVisible || !pos || !menuRef.current) return;
    const r = menuRef.current.getBoundingClientRect();
    const desiredLeft = align === 'right'
      ? (wrapRef.current?.getBoundingClientRect().right ?? 0) - r.width
      : pos.left;
    if (Math.abs(desiredLeft - pos.left) > 1) {
      setPos((prev) => (prev ? { ...prev, left: Math.max(VIEWPORT_PADDING, desiredLeft) } : prev));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [menuVisible, pos?.width]);

  const menuNode = menuVisible && typeof document !== 'undefined'
    ? createPortal(
        <div
          ref={menuRef}
          class={`${closing ? 'oh-menu-pop-out' : 'oh-popmenu-pop'} fixed py-1 rounded-m3-md`}
          style={{
            top: pos ? `${pos.top}px` : '-9999px',
            left: pos ? `${pos.left}px` : '-9999px',
            width: pos ? `${pos.width}px` : width ? `${width}px` : '160px',
            maxWidth: 'calc(100vw - 16px)',
            zIndex: 2000,
            background: 'var(--m3-surface-container)',
            color: 'var(--m3-on-surface)',
            boxShadow: 'var(--m3-elev-3)',
            border: '1px solid var(--m3-outline)',
            visibility: pos ? 'visible' : 'hidden',
            transformOrigin: align === 'right' ? 'top right' : 'top left',
          }}
          role="menu"
          onMouseDown={(e) => e.stopPropagation()}
          onClick={(e) => e.stopPropagation()}
        >
          {items.map((item) => (
            <button
              type="button"
              key={item.key}
              role="menuitem"
              disabled={item.disabled}
              onClick={(e) => {
                e.stopPropagation();
                if (item.disabled) return;
                requestClose();
                item.onClick();
              }}
              class="w-full text-left px-3 py-2 text-sm transition-colors flex items-center justify-between gap-2"
              style={{
                color: item.variant === 'danger'
                  ? 'var(--m3-error)'
                  : item.selected
                    ? 'var(--m3-on-primary-container)'
                    : 'var(--m3-on-surface)',
                cursor: item.disabled ? 'not-allowed' : 'pointer',
                background: item.selected ? 'var(--m3-primary-container)' : 'transparent',
                fontWeight: item.selected ? 700 : 500,
                opacity: item.disabled && !item.selected ? 0.5 : 1,
              }}
              onMouseEnter={(e) => {
                if (item.disabled) return;
                (e.currentTarget as HTMLElement).style.background =
                  item.selected
                    ? 'color-mix(in srgb, var(--m3-primary-container) 84%, var(--m3-primary) 16%)'
                    : 'color-mix(in srgb, var(--m3-on-surface) 6%, transparent)';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLElement).style.background = item.selected
                  ? 'var(--m3-primary-container)'
                  : 'transparent';
              }}
            >
              <span>{item.label}</span>
              {item.selected ? <PopMenuCheckIcon /> : null}
            </button>
          ))}
        </div>,
        document.body,
      )
    : null;

  return (
    <div
      ref={wrapRef}
      class={`relative inline-block ${wrapperClassName}`}
      onMouseDown={(e) => e.stopPropagation()}
      onClick={(e) => e.stopPropagation()}
    >
      {trigger({
        open: open && !closing,
        toggle: () => {
          if (open && !closing) {
            requestClose();
          } else {
            openMenu();
          }
        },
      })}
      {menuNode}
    </div>
  );
}
