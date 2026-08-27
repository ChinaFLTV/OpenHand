// M3 Expressive 下拉菜单（Web 端通用）。
// - 受控 / 非受控均可：传 value 受控，省略时内部托管
// - 触发器：M3 outlined "filled tonal" 视觉，圆角 m3-md，按下/悬停受压反馈
// - 弹层：自适应触发器宽度，圆角 m3-md，elevation-2，跟随全局弹窗动效设置进退场
// - 行为：点击外部 / Escape / 选中后自动关闭；上下键导航 + Enter 选中；首字母快速跳转
// - 可访问性：role=button + aria-haspopup + aria-expanded + role=listbox / option，键盘导航完整
// - 降低动效模式由 global.css 兜底（[data-motion='reduced']），此处无需额外判断
//
// 设计参考：M3 Expressive Menu / Filled Outlined Select Spec

import type { JSX } from 'preact';
import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'preact/hooks';
import { useDelayedVisibility } from '../hooks/useDelayedVisibility';
import { useDismissibleOverlay } from '../hooks/useDismissibleOverlay';
import { useRafScheduler } from '../hooks/useRafScheduler';
import {
  DEFAULT_FLOATING_ANCHOR_GAP,
  DEFAULT_FLOATING_VIEWPORT_PADDING,
  computeAnchoredMenuPosition,
} from '../shared/ui/floating_position';
import { OverlayPortal } from './OverlayPortal';

interface MenuOption<T extends string = string> {
  value: T;
  label: string;
  /** 可选副文本，渲染在 label 下方。 */
  description?: string;
  /** 设为 true 后该项不可选中。 */
  disabled?: boolean;
}

interface MenuSelectProps<T extends string = string> {
  options: ReadonlyArray<MenuOption<T>>;
  value: T;
  onChange: (next: T) => void;
  /** 触发器内左侧标签（可选）。例如「目标：」。 */
  label?: string;
  /** 触发器最小宽度（px）。默认 160。 */
  minWidth?: number;
  /** 弹层 max-height（px），超出滚动。默认 280。 */
  menuMaxHeight?: number;
  className?: string;
  ariaLabel?: string;
  /** disabled 时不可交互。 */
  disabled?: boolean;
}

interface MenuPosition {
  top: number;
  left: number;
  minWidth: number;
  maxHeight: number;
  transformOrigin: string;
}

const VIEWPORT_GAP = DEFAULT_FLOATING_VIEWPORT_PADDING;
const MENU_OFFSET = DEFAULT_FLOATING_ANCHOR_GAP;

export function MenuSelect<T extends string = string>(props: MenuSelectProps<T>): JSX.Element {
  const {
    options, value, onChange, label, minWidth = 160, menuMaxHeight = 280,
    className, ariaLabel, disabled,
  } = props;

  const {
    open,
    closing,
    visible: menuVisible,
    show: showMenu,
    hide: hideMenu,
  } = useDelayedVisibility();
  const [highlight, setHighlight] = useState<number>(() =>
    Math.max(0, options.findIndex((o) => o.value === value)),
  );
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const dismissTargets = useMemo(() => [triggerRef, menuRef], []);
  const listboxId = useId();

  const current = useMemo(() => options.find((o) => o.value === value), [options, value]);
  const closeMenuAndFocusTrigger = useCallback(() => {
    hideMenu();
    triggerRef.current?.focus();
  }, [hideMenu]);

  const computeMenuPosition = useCallback((measuredHeight?: number): MenuPosition | null => {
    const trigger = triggerRef.current;
    if (!trigger) return null;
    const position = computeAnchoredMenuPosition({
      anchor: trigger,
      minWidth,
      measuredHeight,
      fallbackHeight: menuMaxHeight,
      maxHeight: menuMaxHeight,
      align: 'left',
      viewportPadding: VIEWPORT_GAP,
      gap: MENU_OFFSET,
    });
    return {
      top: position.top,
      left: position.left,
      minWidth: position.width,
      maxHeight: position.maxHeight,
      transformOrigin: position.placedAbove ? 'bottom center' : 'top center',
    };
  }, [minWidth, menuMaxHeight]);

  const updateMenuPosition = useCallback(() => {
    const measuredHeight = menuRef.current?.getBoundingClientRect().height;
    setMenuPosition(computeMenuPosition(measuredHeight));
  }, [computeMenuPosition]);
  const { schedule: scheduleMenuPosition, flush: updateMenuPositionNow, cancel: cancelMenuPosition } =
    useRafScheduler(updateMenuPosition);

  const openMenu = useCallback(() => {
    setMenuPosition(computeMenuPosition());
    showMenu();
  }, [computeMenuPosition, showMenu]);

  useEffect(() => {
    if (!open || closing) return;
    // 同步初始 highlight 到当前值。
    const idx = options.findIndex((o) => o.value === value);
    if (idx >= 0) setHighlight(idx);
  }, [open, closing, options, value]);

  useDismissibleOverlay({
    active: open && !closing,
    targets: dismissTargets,
    onDismiss: hideMenu,
    onEscape: closeMenuAndFocusTrigger,
  });

  useEffect(() => {
    if (!menuVisible) return;
    updateMenuPositionNow();
    scheduleMenuPosition();
    window.addEventListener('resize', scheduleMenuPosition);
    window.addEventListener('scroll', scheduleMenuPosition, true);
    return () => {
      window.removeEventListener('resize', scheduleMenuPosition);
      window.removeEventListener('scroll', scheduleMenuPosition, true);
      cancelMenuPosition();
    };
  }, [menuVisible, minWidth, menuMaxHeight, options.length, updateMenuPositionNow, scheduleMenuPosition, cancelMenuPosition]);

  useEffect(() => {
    if (menuVisible) return;
    setMenuPosition(null);
  }, [menuVisible]);

  useEffect(() => {
    if (!open || closing) return;
    const onKey = (ev: KeyboardEvent) => {
      if (options.length === 0) return;
      if (ev.key === 'ArrowDown') {
        ev.preventDefault();
        setHighlight((h) => stepHighlight(options, h, +1));
        return;
      }
      if (ev.key === 'ArrowUp') {
        ev.preventDefault();
        setHighlight((h) => stepHighlight(options, h, -1));
        return;
      }
      if (ev.key === 'Home') {
        ev.preventDefault();
        setHighlight(stepHighlight(options, -1, +1));
        return;
      }
      if (ev.key === 'End') {
        ev.preventDefault();
        setHighlight(stepHighlight(options, options.length, -1));
        return;
      }
      if (ev.key === 'Enter' || ev.key === ' ') {
        const opt = options[highlight];
        if (opt && !opt.disabled) {
          ev.preventDefault();
          onChange(opt.value);
          hideMenu();
          triggerRef.current?.focus();
        }
        return;
      }
      // 单字母快速跳转
      if (ev.key.length === 1) {
        const k = ev.key.toLowerCase();
        const start = (highlight + 1) % options.length;
        for (let i = 0; i < options.length; i += 1) {
          const idx = (start + i) % options.length;
          const opt = options[idx];
          if (!opt.disabled && opt.label.toLowerCase().startsWith(k)) {
            setHighlight(idx);
            break;
          }
        }
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
    };
  }, [open, closing, highlight, options, onChange, hideMenu]);

  const menuNode = menuVisible ? (
    <div
      ref={menuRef}
      id={listboxId}
      role="listbox"
      tabIndex={-1}
      class={`${closing ? 'oh-menu-pop-out' : 'oh-popmenu-pop'} fixed rounded-m3-md overflow-auto`}
      style={{
        top: menuPosition ? `${menuPosition.top}px` : '-9999px',
        left: menuPosition ? `${menuPosition.left}px` : '-9999px',
        minWidth: menuPosition?.minWidth ?? minWidth,
        maxWidth: `calc(100vw - ${VIEWPORT_GAP * 2}px)`,
        maxHeight: menuPosition?.maxHeight ?? menuMaxHeight,
        backgroundColor: 'var(--m3-surface)',
        border: '1px solid var(--m3-outline)',
        boxShadow: 'var(--m3-elev-3)',
        transformOrigin: menuPosition?.transformOrigin ?? 'top center',
        visibility: menuPosition ? 'visible' : 'hidden',
        zIndex: 2200,
      }}
    >
      {options.map((opt, idx) => {
        const selected = opt.value === value;
        const isHi = idx === highlight;
        return (
          <div
            key={opt.value}
            role="option"
            aria-selected={selected}
            aria-disabled={opt.disabled || undefined}
            onMouseEnter={() => !opt.disabled && setHighlight(idx)}
            onClick={() => {
              if (opt.disabled) return;
              onChange(opt.value);
              hideMenu();
              triggerRef.current?.focus();
            }}
            class="px-3 py-2 text-sm flex items-center gap-2"
            style={{
              cursor: opt.disabled ? 'not-allowed' : 'pointer',
              backgroundColor: selected
                ? 'var(--m3-primary-container)'
                : isHi
                  ? 'var(--m3-surface-container)'
                  : 'transparent',
              color: opt.disabled
                ? 'var(--m3-on-surface-variant)'
                : selected
                  ? 'var(--m3-on-primary-container)'
                  : 'var(--m3-on-surface)',
              opacity: opt.disabled ? 0.5 : 1,
              borderLeft: selected ? '3px solid var(--m3-primary)' : '3px solid transparent',
              transition: 'background-color 160ms var(--oh-motion-emphasized)',
            }}
          >
            <span class="flex-1 min-w-0">
              <span class="block truncate">{opt.label}</span>
              {opt.description && (
                <span
                  class="block text-xs truncate oh-text-muted"
                >
                  {opt.description}
                </span>
              )}
            </span>
            {selected && <Check />}
          </div>
        );
      })}
    </div>
  ) : null;

  return (
    <div class={`relative inline-block ${className ?? ''}`} style={{ minWidth }}>
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open && !closing}
        aria-label={ariaLabel ?? label ?? current?.label}
        aria-controls={open && !closing ? listboxId : undefined}
        disabled={disabled}
        onClick={() => {
          if (disabled) return;
          if (open && !closing) {
            hideMenu();
          } else {
            openMenu();
          }
        }}
        class="oh-tap-press w-full inline-flex items-center justify-between gap-2 px-3 py-2 rounded-m3-md text-sm"
        style={{
          backgroundColor: 'var(--m3-surface-container)',
          color: 'var(--m3-on-surface)',
          border: open && !closing ? '1.5px solid var(--m3-primary)' : '1px solid var(--m3-outline)',
          boxShadow: open && !closing ? 'var(--m3-elev-2)' : 'var(--m3-elev-1)',
          opacity: disabled ? 0.5 : 1,
          cursor: disabled ? 'not-allowed' : 'pointer',
        }}
      >
        <span class="flex items-center gap-1 min-w-0 truncate">
          {label && (
            <span class="text-xs oh-text-muted">{label}</span>
          )}
          <span class="truncate">{current?.label ?? '—'}</span>
        </span>
        <Caret open={open && !closing} />
      </button>
      {menuNode && <OverlayPortal>{menuNode}</OverlayPortal>}
    </div>
  );
}

function stepHighlight<T extends string>(options: ReadonlyArray<MenuOption<T>>, current: number, dir: 1 | -1): number {
  if (options.length === 0) return current;
  let next = current;
  for (let i = 0; i < options.length; i += 1) {
    next = (next + dir + options.length) % options.length;
    if (!options[next].disabled) return next;
  }
  return current;
}

function Caret({ open }: { open: boolean }): JSX.Element {
  return (
    <svg
      width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"
      style={{
        transform: open ? 'rotate(180deg)' : 'rotate(0deg)',
        transition: 'transform 220ms var(--oh-motion-emphasized)',
        flex: '0 0 auto',
        color: 'var(--m3-on-surface-variant)',
      }}
    >
      <path fill="currentColor" d="M7 10l5 5 5-5z" />
    </svg>
  );
}

function Check(): JSX.Element {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" style={{ color: 'currentColor' }}>
      <path fill="currentColor" d="M9 16.2 4.8 12l-1.4 1.4L9 19l12-12-1.4-1.4z" />
    </svg>
  );
}
