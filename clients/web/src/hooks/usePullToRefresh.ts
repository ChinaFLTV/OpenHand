// 下拉刷新仅在所属手势正常结束时提交；取消、禁用和卸载均释放手势。

import { useLayoutEffect, useRef, useState } from 'preact/hooks';
import type { RefObject } from 'preact';
import { showSnackbar } from '../components/Snackbar';
import { isAbortError } from '../shared/util/errors';
import { clampNumber } from '../shared/util/number';
import { useEventCallback } from './useEventCallback';

const MIN_PULL_DELTA_PX = 12;
const PULL_RESISTANCE_EXPONENT = 0.85;
const DEFAULT_ACTIVATION_DISTANCE_PX = 80;
const DEFAULT_MAX_DISTANCE_PX = 140;
const MIN_ACTIVATION_DISTANCE_PX = 1;
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

interface PullToRefreshOptions {
  onRefresh: () => Promise<void> | void;
  /// 触发刷新的最小拖拽像素数。默认 80。
  activationDistance?: number;
  /// 上限：拉动不会无限制延伸。默认 140。
  maxDistance?: number;
  /// 关闭开关；切换页面时可临时禁用。默认 true。
  enabled?: boolean;
}

interface PullToRefreshState {
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
  const {
    onRefresh,
    activationDistance = DEFAULT_ACTIVATION_DISTANCE_PX,
    maxDistance = DEFAULT_MAX_DISTANCE_PX,
    enabled = true,
  } = opts;
  const safeActivationDistance = clampNumber(
    activationDistance,
    MIN_ACTIVATION_DISTANCE_PX,
    Number.MAX_SAFE_INTEGER,
  );
  const safeMaxDistance = clampNumber(
    maxDistance,
    safeActivationDistance,
    Number.MAX_SAFE_INTEGER,
  );
  const [pulled, setPulled] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const refreshingRef = useRef(false);
  const refresh = useEventCallback(onRefresh);
  const mountedRef = useRef(true);

  useLayoutEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  useLayoutEffect(() => {
    if (!enabled) return;
    const el = ref.current;
    if (!el) return;
    let startY: number | null = null;
    let activePointerId: number | null = null;
    let activeTouchId: number | null = null;
    let distance = 0;
    let tracking = false;

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
      distance = value;
      if (mountedRef.current) setPulled(value);
    };

    const resetGesture = () => {
      const pointerId = activePointerId;
      activePointerId = null;
      activeTouchId = null;
      startY = null;
      tracking = false;
      if (pointerId != null && el.hasPointerCapture(pointerId)) {
        el.releasePointerCapture(pointerId);
      }
    };

    const cancelPull = () => {
      resetGesture();
      if (!refreshingRef.current) updatePulled(0);
    };

    const beginPull = (y: number) => {
      startY = y;
      tracking = true;
    };

    const updatePull = (y: number) => {
      if (!tracking || refreshingRef.current || startY == null) return;
      const dy = y - startY;
      if (dy <= 0) {
        cancelPull();
        return;
      }
      if (dy < MIN_PULL_DELTA_PX) {
        updatePulled(0);
        return;
      }
      // 引入阻尼，越拉越慢，最大不过 safeMaxDistance。
      updatePulled(clampNumber(Math.pow(dy - MIN_PULL_DELTA_PX, PULL_RESISTANCE_EXPONENT), 0, safeMaxDistance));
    };

    const finishPull = async () => {
      if (!tracking || refreshingRef.current) return;
      const reached = distance >= safeActivationDistance;
      resetGesture();
      if (!reached) {
        updatePulled(0);
        return;
      }
      updatePulled(safeActivationDistance);
      refreshingRef.current = true;
      setRefreshing(true);
      try {
        await refresh();
      } catch (error) {
        if (mountedRef.current && !isAbortError(error)) {
          showSnackbar(error instanceof Error ? error.message : String(error), { tone: 'error' });
        }
      } finally {
        refreshingRef.current = false;
        if (mountedRef.current) {
          setRefreshing(false);
          updatePulled(0);
        }
      }
    };

    const onTouchStart = (ev: TouchEvent) => {
      if (ev.touches.length !== 1) {
        cancelPull();
        return;
      }
      if (refreshingRef.current || activePointerId != null) return;
      if (shouldIgnorePullTarget(ev.target) || !isAtTop()) return;
      activeTouchId = ev.touches[0].identifier;
      beginPull(ev.touches[0].clientY);
    };

    const onTouchMove = (ev: TouchEvent) => {
      if (activeTouchId == null) return;
      if (ev.touches.length !== 1 || ev.touches[0].identifier !== activeTouchId) {
        cancelPull();
        return;
      }
      updatePull(ev.touches[0].clientY);
    };

    const onTouchEnd = (ev: TouchEvent) => {
      if (Array.from(ev.changedTouches).some((touch) => touch.identifier === activeTouchId)) {
        void finishPull();
      }
    };

    const onPointerDown = (ev: PointerEvent) => {
      if (ev.pointerType !== 'pen' || !ev.isPrimary || tracking) return;
      if (shouldIgnorePullTarget(ev.target)) return;
      if (refreshingRef.current || ev.button !== 0 || !isAtTop()) return;
      activePointerId = ev.pointerId;
      beginPull(ev.clientY);
      try {
        el.setPointerCapture(ev.pointerId);
      } catch {
        // 非关键：部分浏览器/元素不支持 capture。
      }
    };

    const onPointerMove = (ev: PointerEvent) => {
      if (activePointerId !== ev.pointerId) return;
      updatePull(ev.clientY);
      if (distance > 0) ev.preventDefault();
    };

    const onPointerEnd = (ev: PointerEvent) => {
      if (activePointerId === ev.pointerId) void finishPull();
    };

    const onPointerCancel = (ev: PointerEvent) => {
      if (activePointerId === ev.pointerId) cancelPull();
    };

    el.addEventListener('touchstart', onTouchStart, { passive: true });
    el.addEventListener('touchmove', onTouchMove, { passive: true });
    el.addEventListener('touchend', onTouchEnd);
    el.addEventListener('touchcancel', cancelPull);
    el.addEventListener('pointerdown', onPointerDown);
    el.addEventListener('pointermove', onPointerMove, { passive: false });
    el.addEventListener('pointerup', onPointerEnd);
    el.addEventListener('pointercancel', onPointerCancel);
    el.addEventListener('lostpointercapture', onPointerCancel);
    return () => {
      el.removeEventListener('touchstart', onTouchStart);
      el.removeEventListener('touchmove', onTouchMove);
      el.removeEventListener('touchend', onTouchEnd);
      el.removeEventListener('touchcancel', cancelPull);
      el.removeEventListener('pointerdown', onPointerDown);
      el.removeEventListener('pointermove', onPointerMove);
      el.removeEventListener('pointerup', onPointerEnd);
      el.removeEventListener('pointercancel', onPointerCancel);
      el.removeEventListener('lostpointercapture', onPointerCancel);
      cancelPull();
    };
  }, [ref, refresh, safeActivationDistance, safeMaxDistance, enabled]);

  return { pulled, refreshing, willRelease: pulled >= safeActivationDistance };
}
