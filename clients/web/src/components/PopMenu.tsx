// 通用 popover 菜单：触发器 + 弹出菜单项。点击外部 / Esc 自动关闭。
// 用 absolute 定位，相对最近 `position: relative` 的祖先；调用方负责确保父级
// 正确定位（通常是会话卡片右上角的小三点按钮）。

import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';

export interface PopMenuItem {
  key: string;
  label: string;
  onClick: () => void;
  /// 'danger' → 红色文字（删除等）。
  variant?: 'default' | 'danger';
  /// 禁用时按钮可见但不可点。
  disabled?: boolean;
}

export interface PopMenuProps {
  items: PopMenuItem[];
  /// 触发器；调用方控制其外观。
  trigger: (props: { open: boolean; toggle: () => void }) => ComponentChildren;
  /// 默认 'right'，菜单从触发器右上角弹出。
  align?: 'left' | 'right';
}

export function PopMenu({ items, trigger, align = 'right' }: PopMenuProps) {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (ev: MouseEvent) => {
      if (!wrapRef.current) return;
      if (!wrapRef.current.contains(ev.target as Node)) {
        setOpen(false);
      }
    };
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape') setOpen(false);
    };
    window.addEventListener('mousedown', onDown);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('mousedown', onDown);
      window.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div ref={wrapRef} class="relative inline-block">
      {trigger({ open, toggle: () => setOpen((v) => !v) })}
      {open ? (
        <div
          class="oh-popmenu-pop absolute z-30 mt-1 min-w-[160px] py-1 rounded-m3-md"
          style={{
            background: 'var(--m3-surface-container)',
            color: 'var(--m3-on-surface)',
            boxShadow: 'var(--m3-elev-3)',
            border: '1px solid var(--m3-outline)',
            top: '100%',
            ...(align === 'right' ? { right: 0 } : { left: 0 }),
          }}
          role="menu"
        >
          {items.map((item) => (
            <button
              type="button"
              key={item.key}
              role="menuitem"
              disabled={item.disabled}
              onClick={() => {
                if (item.disabled) return;
                setOpen(false);
                item.onClick();
              }}
              class="w-full text-left px-3 py-2 text-sm transition-colors disabled:opacity-50"
              style={{
                color: item.variant === 'danger' ? 'var(--m3-error)' : 'var(--m3-on-surface)',
                cursor: item.disabled ? 'not-allowed' : 'pointer',
                background: 'transparent',
              }}
              onMouseEnter={(e) => {
                if (item.disabled) return;
                (e.currentTarget as HTMLElement).style.background =
                  'color-mix(in srgb, var(--m3-on-surface) 6%, transparent)';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLElement).style.background = 'transparent';
              }}
            >
              {item.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
