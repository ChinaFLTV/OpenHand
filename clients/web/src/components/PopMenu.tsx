// 通用 popover 菜单：触发器 + 弹出菜单项。点击外部 / Esc 自动关闭。
// 面板挂载到当前全屏根节点，并随触发器布局与视口变化更新位置。

import type { ComponentChildren } from 'preact';
import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { useDelayedVisibility } from '../hooks/useDelayedVisibility';
import { useDismissibleOverlay } from '../hooks/useDismissibleOverlay';
import { useRafScheduler } from '../hooks/useRafScheduler';
import {
  DEFAULT_FLOATING_ANCHOR_GAP,
  DEFAULT_FLOATING_VIEWPORT_PADDING,
  computeAnchoredMenuPosition,
  type FloatingVerticalPlacement,
} from '../shared/ui/floating_position';
import { OverlayPortal } from './OverlayPortal';

interface PopMenuItem {
  key: string;
  label: string;
  onClick: () => void;
  /** 'danger' → 红色文字（删除等）。 */
  variant?: 'default' | 'danger';
  /** 禁用时按钮可见但不可点。 */
  disabled?: boolean;
  /** 当前选中项；禁用时仍保持主题选中态，避免看起来像普通不可用项。 */
  selected?: boolean;
}

interface PopMenuProps {
  items?: PopMenuItem[];
  /** 自定义面板内容；复用同一套锚定、外部关闭与全局进退场动画。 */
  content?: (actions: { close: () => void }) => ComponentChildren;
  /** 自定义面板的无障碍标签。 */
  ariaLabel?: string;
  /** 自定义面板样式钩子。 */
  panelClassName?: string;
  /** 触发器；调用方控制其外观。 */
  trigger: (props: { open: boolean; toggle: () => void }) => ComponentChildren;
  /** 触发器外层样式钩子。 */
  wrapperClassName?: string;
  /** 触发器不可用时由外层承载悬停提示。 */
  wrapperTitle?: string;
  /** 默认 'right'，菜单从触发器右上角弹出。 */
  align?: 'left' | 'right';
  /** 垂直方向首选位置；空间不足时自动回退到可用侧。 */
  verticalPlacement?: FloatingVerticalPlacement;
  /** 可选固定宽度，适合模式选择等短菜单，避免长禁用说明把菜单撑宽。 */
  width?: number;
}

interface MenuPos {
  top: number;
  left: number;
  width: number;
  maxHeight: number;
  placedAbove: boolean;
}

const VIEWPORT_PADDING = DEFAULT_FLOATING_VIEWPORT_PADDING;
const MENU_GAP = DEFAULT_FLOATING_ANCHOR_GAP;

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

export function PopMenu({
  items = [],
  content,
  ariaLabel,
  panelClassName = '',
  trigger,
  wrapperClassName = '',
  wrapperTitle,
  align = 'right',
  verticalPlacement = 'auto',
  width,
}: PopMenuProps) {
  const menuMotion = useDelayedVisibility();
  const { open, closing, visible: menuVisible, hide: hideMenu, toggle: toggleMenu } = menuMotion;
  const [pos, setPos] = useState<MenuPos | null>(null);
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);
  const dismissTargets = useMemo(() => [wrapRef, menuRef], []);

  useDismissibleOverlay({
    active: open && !closing,
    targets: dismissTargets,
    onDismiss: hideMenu,
  });

  // 计算菜单坐标：fixed 定位 + 视口内夹紧。
  const recompute = useCallback(() => {
    const trig = wrapRef.current;
    if (!trig) return;
    const r = trig.getBoundingClientRect();
    const desiredWidth = width ?? Math.max(r.width, 160);
    const position = computeAnchoredMenuPosition({
      anchor: trig,
      preferredWidth: desiredWidth,
      // offsetHeight 不受进场 scale 动画影响，避免测到缩放中的高度后
      // 把“上方显示”的菜单压回触发器区域。
      measuredHeight: menuRef.current?.offsetHeight,
      align,
      verticalPlacement,
      viewportPadding: VIEWPORT_PADDING,
      gap: MENU_GAP,
    });
    setPos({
      top: position.top,
      left: position.left,
      width: position.width,
      maxHeight: position.maxHeight,
      placedAbove: position.placedAbove,
    });
  }, [align, verticalPlacement, width]);
  const { schedule: scheduleRecompute, flush: recomputeNow, cancel: cancelRecompute } = useRafScheduler(recompute);

  useLayoutEffect(() => {
    if (!menuVisible) {
      cancelRecompute();
      setPos(null);
      return;
    }
    recomputeNow();
    const onScrollOrResize = () => scheduleRecompute();
    window.addEventListener('scroll', onScrollOrResize, true);
    window.addEventListener('resize', onScrollOrResize);
    return () => {
      window.removeEventListener('scroll', onScrollOrResize, true);
      window.removeEventListener('resize', onScrollOrResize);
      cancelRecompute();
    };
  }, [menuVisible, recompute, recomputeNow, scheduleRecompute, cancelRecompute]);

  // 第一次渲染拿到菜单实际尺寸后再校准一次，确保上方锚定不会因
  // 兜底高度与真实高度不同而压住触发器。
  useLayoutEffect(() => {
    if (!menuVisible || !pos || !menuRef.current) return;
    recomputeNow();
  }, [menuVisible, pos?.width, recomputeNow]);

  const menuNode = menuVisible
    ? (
      <OverlayPortal>
        <div
          ref={menuRef}
          class={`${closing ? 'oh-menu-pop-out' : 'oh-popmenu-pop'} ${panelClassName} fixed py-1 rounded-m3-md`}
          style={{
            top: pos ? `${pos.top}px` : '-9999px',
            left: pos ? `${pos.left}px` : '-9999px',
            width: pos ? `${pos.width}px` : width ? `${width}px` : '160px',
            maxWidth: 'calc(100vw - 16px)',
            maxHeight: pos
              ? `${pos.maxHeight}px`
              : `calc(100vh - ${VIEWPORT_PADDING * 2}px)`,
            overflowY: 'auto',
            zIndex: 2000,
            background: 'var(--m3-surface-container)',
            color: 'var(--m3-on-surface)',
            boxShadow: 'var(--m3-elev-3)',
            border: '1px solid var(--m3-outline)',
            visibility: pos ? 'visible' : 'hidden',
            transformOrigin: `${pos?.placedAbove ? 'bottom' : 'top'} ${align}`,
          }}
          role={content ? 'dialog' : 'menu'}
          aria-label={ariaLabel}
          onMouseDown={(e) => e.stopPropagation()}
          onClick={(e) => e.stopPropagation()}
        >
          {content ? content({ close: hideMenu }) : items.map((item) => (
            <button
              type="button"
              key={item.key}
              role="menuitem"
              disabled={item.disabled}
              onClick={(e) => {
                e.stopPropagation();
                if (item.disabled) return;
                hideMenu();
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
        </div>
      </OverlayPortal>
      )
    : null;

  return (
    <div
      ref={wrapRef}
      class={`relative inline-block ${wrapperClassName}`}
      title={wrapperTitle}
      onMouseDown={(e) => e.stopPropagation()}
      onClick={(e) => e.stopPropagation()}
    >
      {trigger({
        open: open && !closing,
        toggle: toggleMenu,
      })}
      {menuNode}
    </div>
  );
}
