import { useLocation } from 'preact-iso';
import { ignoreError } from '../shared/util/errors';
import { isReducedMotion } from './useReducedMotion';

type ViewTransitionDocument = Document & {
  startViewTransition?: (callback: () => Promise<void> | void) => {
    finished: Promise<void>;
    ready?: Promise<void>;
    updateCallbackDone?: Promise<void>;
  };
};

const ROUTE_TRANSITION_CLEANUP_TIMEOUT_MS = 720;
let routeTransitionGeneration = 0;

function runWithRouteTransition(update: () => void): void {
  const doc = document as ViewTransitionDocument;
  if (typeof doc.startViewTransition !== 'function' || isReducedMotion()) {
    routeTransitionGeneration += 1;
    delete document.documentElement.dataset.routeTransition;
    update();
    return;
  }
  const generation = ++routeTransitionGeneration;
  document.documentElement.dataset.routeTransition = 'active';
  let cleaned = false;
  let updateStarted = false;
  const commitUpdate = () => {
    if (updateStarted || generation !== routeTransitionGeneration) return;
    updateStarted = true;
    update();
  };
  let cleanupTimer: number | undefined;
  const cleanup = () => {
    if (cleaned) return;
    cleaned = true;
    if (cleanupTimer != null) window.clearTimeout(cleanupTimer);
    if (generation === routeTransitionGeneration) {
      delete document.documentElement.dataset.routeTransition;
    }
  };
  cleanupTimer = window.setTimeout(cleanup, ROUTE_TRANSITION_CLEANUP_TIMEOUT_MS);
  try {
    const transition = doc.startViewTransition(commitUpdate);
    void transition.ready?.catch(ignoreError);
    void transition.updateCallbackDone?.catch(ignoreError);
    void transition.finished.catch(ignoreError).finally(cleanup);
  } catch {
    cleanup();
    commitUpdate();
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
