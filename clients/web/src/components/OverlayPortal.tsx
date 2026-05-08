import type { ComponentChildren } from 'preact';
import { createPortal } from 'preact/compat';
import { useEffect, useState } from 'preact/hooks';

export function getOverlayPortalTarget(): HTMLElement | null {
  if (typeof document === 'undefined') return null;
  const fullscreenElement = document.fullscreenElement;
  if (fullscreenElement instanceof HTMLElement) return fullscreenElement;
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
