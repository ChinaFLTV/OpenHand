// 下拉刷新 hook：监听容器顶部的 touch/pointer 拖拽，
// 当滚动条已经处于顶部且用户向下拖拽 ≥ 阈值时调用 onRefresh()。
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

const MIN_PULL_DELTA_PX = 12;
const PULL_TO_REFRESH_INTERACTIVE_SELECTOR = [
  'button',
  'a',
  'input',
  'textarea',
  'select',
  '[role="button"]',
  '[data-message-action-panel="true"]',
  '[data-message-scrollable-body="true"]',
  '[data-pull-refresh-ignore="true"]',
].join(',');

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
  const activePointerId = useRef<number | null>(null);
  const pulledRef = useRef(0);
  const tracking = useRef(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

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

    const shouldIgnorePullTarget = (target: EventTarget | null): boolean => {
      if (!(target instanceof Element)) return false;
      const ignored = target.closest(PULL_TO_REFRESH_INTERACTIVE_SELECTOR);
      return ignored != null && el.contains(ignored);
    };

    const updatePulled = (value: number) => {
      pulledRef.current = value;
      setPulled(value);
    };

    const beginPull = (y: number) => {
      startY.current = y;
      tracking.current = true;
    };

    const updatePull = (y: number) => {
      if (!tracking.current || refreshing || startY.current == null) return;
      const dy = y - startY.current;
      if (dy <= 0) {
        updatePulled(0);
        tracking.current = false;
        return;
      }
      if (dy < MIN_PULL_DELTA_PX) {
        updatePulled(0);
        return;
      }
      // 引入阻尼，越拉越慢，最大不过 maxDistance。
      updatePulled(Math.min(maxDistance, Math.pow(dy - MIN_PULL_DELTA_PX, 0.85)));
    };

    const finishPull = async () => {
      if (!tracking.current) return;
      tracking.current = false;
      activePointerId.current = null;
      const reached = pulledRef.current >= activationDistance;
      startY.current = null;
      if (!reached) {
        updatePulled(0);
        return;
      }
      updatePulled(activationDistance);
      setRefreshing(true);
      try {
        await onRefresh();
      } finally {
        if (!mountedRef.current) return;
        setRefreshing(false);
        updatePulled(0);
      }
    };

    const onTouchStart = (ev: TouchEvent) => {
      if (refreshing) return;
      if (shouldIgnorePullTarget(ev.target)) return;
      if (!isAtTop()) return;
      if (ev.touches.length !== 1) return;
      beginPull(ev.touches[0].clientY);
    };

    const onTouchMove = (ev: TouchEvent) => {
      updatePull(ev.touches[0].clientY);
    };

    const onPointerDown = (ev: PointerEvent) => {
      if (ev.pointerType !== 'pen') return;
      if (shouldIgnorePullTarget(ev.target)) return;
      if (refreshing || ev.button !== 0 || !isAtTop()) return;
      activePointerId.current = ev.pointerId;
      beginPull(ev.clientY);
      try {
        el.setPointerCapture(ev.pointerId);
      } catch {
        // 非关键：部分浏览器/元素不支持 capture。
      }
    };

    const onPointerMove = (ev: PointerEvent) => {
      if (activePointerId.current !== ev.pointerId) return;
      updatePull(ev.clientY);
      if (pulledRef.current > 0) ev.preventDefault();
    };

    const onPointerEnd = () => {
      void finishPull();
    };

    el.addEventListener('touchstart', onTouchStart, { passive: true });
    el.addEventListener('touchmove', onTouchMove, { passive: true });
    el.addEventListener('touchend', onPointerEnd);
    el.addEventListener('touchcancel', onPointerEnd);
    el.addEventListener('pointerdown', onPointerDown);
    el.addEventListener('pointermove', onPointerMove, { passive: false });
    el.addEventListener('pointerup', onPointerEnd);
    el.addEventListener('pointercancel', onPointerEnd);
    return () => {
      el.removeEventListener('touchstart', onTouchStart);
      el.removeEventListener('touchmove', onTouchMove);
      el.removeEventListener('touchend', onPointerEnd);
      el.removeEventListener('touchcancel', onPointerEnd);
      el.removeEventListener('pointerdown', onPointerDown);
      el.removeEventListener('pointermove', onPointerMove);
      el.removeEventListener('pointerup', onPointerEnd);
      el.removeEventListener('pointercancel', onPointerEnd);
    };
  }, [ref, onRefresh, activationDistance, maxDistance, enabled, refreshing]);

  return { pulled, refreshing, willRelease: pulled >= activationDistance };
}
