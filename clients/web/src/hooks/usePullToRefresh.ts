// 触摸下拉刷新 hook：监听容器顶部的 touchstart/touchmove/touchend，
// 当滚动条已经处于顶部且用户向下拖拽 ≥ 阈值时调用 onRefresh()。
// 仅在触摸设备生效，鼠标场景不影响（用桌面顶部的传统按钮即可）。
//
// 设计：
// - 不修改任何 CSS scroll 行为；仅返回 `{ pulled, refreshing }` 让调用方
//   渲染顶部进度指示。
// - 拉动 < activationDistance 时只显示松手刷新提示；松手后归零。
// - 拉动 ≥ activationDistance 时调用 onRefresh()，期间 refreshing=true，
//   pulled 锁在阈值不再随手指变化，避免抖动。
// - 防止同一手势重复触发：refreshing 期间忽略后续 touch。

import { useEffect, useRef, useState } from 'preact/hooks';
import type { RefObject } from 'preact';

export interface PullToRefreshOptions {
  onRefresh: () => Promise<void> | void;
  /// 触发刷新的最小拖拽像素数。默认 80。
  activationDistance?: number;
  /// 上限：拉动不会无限制延伸。默认 140。
  maxDistance?: number;
  /// 关闭开关；切换页面时可临时禁用。默认 true。
  enabled?: boolean;
}

export interface PullToRefreshState {
  /// 当前下拉位移（0 ~ maxDistance）。
  pulled: number;
  /// onRefresh 执行期间为 true。
  refreshing: boolean;
  /// pulled >= activationDistance 时为 true，提示"松开即可刷新"。
  willRelease: boolean;
}

export function usePullToRefresh<E extends HTMLElement>(
  ref: RefObject<E>,
  opts: PullToRefreshOptions,
): PullToRefreshState {
  const { onRefresh, activationDistance = 80, maxDistance = 140, enabled = true } = opts;
  const [pulled, setPulled] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const startY = useRef<number | null>(null);
  const tracking = useRef(false);

  useEffect(() => {
    if (!enabled) return;
    const el = ref.current;
    if (!el) return;

    const isAtTop = (): boolean => {
      // 优先看 window 滚动；若调用方传的是局部滚动容器则看其 scrollTop。
      const scroller: Element | null = el.scrollHeight > el.clientHeight ? el : document.scrollingElement;
      if (!scroller) return window.scrollY <= 0;
      return scroller.scrollTop <= 0;
    };

    const onTouchStart = (ev: TouchEvent) => {
      if (refreshing) return;
      if (!isAtTop()) return;
      if (ev.touches.length !== 1) return;
      startY.current = ev.touches[0].clientY;
      tracking.current = true;
    };

    const onTouchMove = (ev: TouchEvent) => {
      if (!tracking.current || refreshing || startY.current == null) return;
      const dy = ev.touches[0].clientY - startY.current;
      if (dy <= 0) {
        // 改为向上：取消追踪。
        setPulled(0);
        tracking.current = false;
        return;
      }
      // 引入阻尼，越拉越慢，最大不过 maxDistance。
      const damped = Math.min(maxDistance, Math.pow(dy, 0.85));
      setPulled(damped);
    };

    const onTouchEnd = async () => {
      if (!tracking.current) return;
      tracking.current = false;
      const reached = pulled >= activationDistance;
      startY.current = null;
      if (!reached) {
        setPulled(0);
        return;
      }
      setPulled(activationDistance);
      setRefreshing(true);
      try {
        await onRefresh();
      } finally {
        setRefreshing(false);
        setPulled(0);
      }
    };

    el.addEventListener('touchstart', onTouchStart, { passive: true });
    el.addEventListener('touchmove', onTouchMove, { passive: true });
    el.addEventListener('touchend', onTouchEnd);
    el.addEventListener('touchcancel', onTouchEnd);
    return () => {
      el.removeEventListener('touchstart', onTouchStart);
      el.removeEventListener('touchmove', onTouchMove);
      el.removeEventListener('touchend', onTouchEnd);
      el.removeEventListener('touchcancel', onTouchEnd);
    };
    // pulled 在闭包里被 onTouchEnd 读取，不能漏；其他依赖固定。
  }, [ref, onRefresh, activationDistance, maxDistance, enabled, refreshing, pulled]);

  return { pulled, refreshing, willRelease: pulled >= activationDistance };
}
