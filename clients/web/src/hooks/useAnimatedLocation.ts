import { useLocation } from 'preact-iso';

type ViewTransitionDocument = Document & {
  startViewTransition?: (callback: () => Promise<void> | void) => {
    finished: Promise<void>;
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
  const transition = doc.startViewTransition(() => {
    update();
    return new Promise<void>((resolve) => {
      requestAnimationFrame(() => resolve());
    });
  });
  transition.finished.finally(() => {
    delete document.documentElement.dataset.routeTransition;
  });
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
