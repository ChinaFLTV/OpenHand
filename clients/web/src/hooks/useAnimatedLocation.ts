import { useLocation } from 'preact-iso';

type ViewTransitionDocument = Document & {
  startViewTransition?: (callback: () => Promise<void> | void) => {
    finished: Promise<void>;
    ready?: Promise<void>;
    updateCallbackDone?: Promise<void>;
  };
};

function shouldReduceMotion(): boolean {
  try {
    return (
      document.documentElement.dataset.motion === 'reduced' ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches
    );
  } catch {
    return true;
  }
}

function runWithRouteTransition(update: () => void): void {
  const doc = document as ViewTransitionDocument;
  if (typeof doc.startViewTransition !== 'function' || shouldReduceMotion()) {
    update();
    return;
  }
  document.documentElement.dataset.routeTransition = 'active';
  let cleaned = false;
  let updateStarted = false;
  let cleanupTimer: number | undefined;
  const cleanup = () => {
    if (cleaned) return;
    cleaned = true;
    if (cleanupTimer != null) window.clearTimeout(cleanupTimer);
    delete document.documentElement.dataset.routeTransition;
  };
  cleanupTimer = window.setTimeout(cleanup, 720);
  try {
    const transition = doc.startViewTransition(() => {
      updateStarted = true;
      update();
    });
    void transition.ready?.catch(() => undefined);
    void transition.updateCallbackDone?.catch(() => undefined);
    void transition.finished.catch(() => undefined).finally(cleanup);
  } catch {
    cleanup();
    if (!updateStarted) update();
  }
}

export function useAnimatedLocation() {
  const location = useLocation();
  return {
    ...location,
    route: (url: string, replace?: boolean) => {
      runWithRouteTransition(() => location.route(url, replace));
    },
  };
}
