import type { ComponentChildren } from 'preact';
import { createPortal } from 'preact/compat';
import { useEffect, useState } from 'preact/hooks';

export function getOverlayPortalTarget(): HTMLElement | null {
  if (typeof document === 'undefined') return null;
  const fullscreenElement = document.fullscreenElement;
  if (fullscreenElement instanceof HTMLElement) {
    // 当浏览器全屏锁定到根元素 (documentElement) 时，body 仍然是它的后代，
    // 此时优先把浮层挂到 body，可以避开页面入场动画 (.oh-page-fade) 残留的
    // transform: matrix(...) 形成的 containing block——否则 dialog/menu/snackbar
    // 的 `position: fixed` 会被锁定到那个变换层，造成全屏下点击无效或定位错乱。
    if (fullscreenElement.contains(document.body)) return document.body;
    return fullscreenElement;
  }
  return document.body;
}

function useOverlayPortalTarget(): HTMLElement | null {
  const [target, setTarget] = useState<HTMLElement | null>(() => getOverlayPortalTarget());

  useEffect(() => {
    if (typeof document === 'undefined') return;
    const syncTarget = () => setTarget(getOverlayPortalTarget());
    syncTarget();
    document.addEventListener('fullscreenchange', syncTarget);
    document.addEventListener('webkitfullscreenchange', syncTarget);
    return () => {
      document.removeEventListener('fullscreenchange', syncTarget);
      document.removeEventListener('webkitfullscreenchange', syncTarget);
    };
  }, []);

  return target;
}

export function OverlayPortal({ children }: { children: ComponentChildren }) {
  const target = useOverlayPortalTarget();
  if (!target) return <>{children}</>;
  return createPortal(children, target);
}
