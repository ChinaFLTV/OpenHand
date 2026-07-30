import { useLocation } from 'preact-iso';
import { ignoreError } from '../shared/util/errors';
import { normalizeDurationMs } from '../shared/util/number';

type ViewTransitionDocument = Document & {
  startViewTransition?: (callback: () => Promise<void> | void) => {
    finished: Promise<void>;
    ready?: Promise<void>;
    updateCallbackDone?: Promise<void>;
  };
};

const ROUTE_TRANSITION_CLEANUP_FALLBACK_MS = 720;
const ROUTE_TRANSITION_CLEANUP_MIN_MS = 120;
const ROUTE_TRANSITION_CLEANUP_MAX_MS = 3_000;
let routeTransitionGeneration = 0;

function routeTransitionCleanupDelayMs(): number {
  return normalizeDurationMs(ROUTE_TRANSITION_CLEANUP_FALLBACK_MS, {
    fallback: ROUTE_TRANSITION_CLEANUP_FALLBACK_MS,
    min: ROUTE_TRANSITION_CLEANUP_MIN_MS,
    max: ROUTE_TRANSITION_CLEANUP_MAX_MS,
  });
}

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
    routeTransitionGeneration += 1;
    delete document.documentElement.dataset.routeTransition;
    update();
    return;
  }
  const generation = ++routeTransitionGeneration;
  document.documentElement.dataset.routeTransition = 'active';
  let cleaned = false;
  let updateStarted = false;
  let cleanupTimer: number | undefined;
  const cleanup = () => {
    if (cleaned) return;
    cleaned = true;
    if (cleanupTimer != null) window.clearTimeout(cleanupTimer);
    if (generation === routeTransitionGeneration) {
      delete document.documentElement.dataset.routeTransition;
    }
  };
  cleanupTimer = window.setTimeout(cleanup, routeTransitionCleanupDelayMs());
  try {
    const transition = doc.startViewTransition(() => {
      updateStarted = true;
      update();
    });
    void transition.ready?.catch(ignoreError);
    void transition.updateCallbackDone?.catch(ignoreError);
    void transition.finished.catch(ignoreError).finally(cleanup);
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
