export const TRANSCRIPT_SCROLL_ACTIVITY_ATTR = 'data-transcript-scroll-active';
export const TRANSCRIPT_SCROLL_ACTIVITY_SETTLE_MS = 220;

let active = false;
let settleTimer: number | null = null;

function rootElement(): HTMLElement | null {
  return typeof document === 'undefined' ? null : document.documentElement;
}

function setRootActivity(value: boolean): void {
  active = value;
  const root = rootElement();
  if (!root) return;
  if (value) {
    root.setAttribute(TRANSCRIPT_SCROLL_ACTIVITY_ATTR, 'true');
  } else {
    root.removeAttribute(TRANSCRIPT_SCROLL_ACTIVITY_ATTR);
  }
}

export function isTranscriptScrollActive(): boolean {
  if (active) return true;
  return rootElement()?.getAttribute(TRANSCRIPT_SCROLL_ACTIVITY_ATTR) === 'true';
}

export function markTranscriptScrollActivity(
  durationMs = TRANSCRIPT_SCROLL_ACTIVITY_SETTLE_MS,
): void {
  if (typeof window === 'undefined') return;
  setRootActivity(true);
  if (settleTimer != null) {
    window.clearTimeout(settleTimer);
  }
  const safeDuration = Math.max(80, Math.min(1000, durationMs));
  settleTimer = window.setTimeout(() => {
    settleTimer = null;
    setRootActivity(false);
  }, safeDuration);
}

export function clearTranscriptScrollActivity(): void {
  if (typeof window !== 'undefined' && settleTimer != null) {
    window.clearTimeout(settleTimer);
  }
  settleTimer = null;
  setRootActivity(false);
}

export function scheduleAfterTranscriptScrollSettles(task: () => void): () => void {
  if (typeof window === 'undefined') {
    task();
    return () => {};
  }
  let cancelled = false;
  let timer: number | null = null;

  const run = () => {
    timer = null;
    if (cancelled) return;
    if (isTranscriptScrollActive()) {
      timer = window.setTimeout(run, TRANSCRIPT_SCROLL_ACTIVITY_SETTLE_MS);
      return;
    }
    task();
  };

  run();
  return () => {
    cancelled = true;
    if (timer != null) {
      window.clearTimeout(timer);
      timer = null;
    }
  };
}
