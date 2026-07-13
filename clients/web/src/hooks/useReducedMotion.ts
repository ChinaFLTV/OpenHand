// 监听浏览器的 prefers-reduced-motion 媒体查询 + localStorage 用户开关 + App 端 reduceMotion。
// 任一开启即视为「降低动效」，由 global.css 的 [data-motion='reduced'] 选择器统一关停。

import { useEffect, useState } from 'preact/hooks';
import { readBrowserStorage } from '../shared/util/browser_storage';

const STORAGE_KEY = 'openhand_web_reduce_motion';
let remoteReducedMotion: boolean | null = null;
type ReducedMotionListener = (reduced: boolean) => void;

const reducedMotionListeners = new Set<ReducedMotionListener>();
let reducedMotionMediaQuery: MediaQueryList | null = null;
let reducedMotionSourcesAttached = false;

function readUserPref(): boolean {
  return readBrowserStorage(STORAGE_KEY) === '1';
}

/** 让 root 元素带上 data-motion='reduced'，让 CSS 全树关闭动画。 */
function syncRootAttribute(reduced: boolean): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  if (reduced) {
    root.setAttribute('data-motion', 'reduced');
  } else {
    root.removeAttribute('data-motion');
  }
}

function readOsPref(): boolean {
  if (
    typeof window === 'undefined'
    || typeof window.matchMedia !== 'function'
  ) return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function resolveReducedMotion(): boolean {
  return readOsPref() || readUserPref() || remoteReducedMotion === true;
}

function publishReducedMotion(): void {
  const reduced = resolveReducedMotion();
  syncRootAttribute(reduced);
  for (const listener of [...reducedMotionListeners]) {
    listener(reduced);
  }
}

function handleReducedMotionSourceChange(): void {
  publishReducedMotion();
}

function handleReducedMotionStorageChange(event: StorageEvent): void {
  if (event.key === STORAGE_KEY || event.key == null) {
    publishReducedMotion();
  }
}

function attachReducedMotionSources(): void {
  if (reducedMotionSourcesAttached || typeof window === 'undefined') return;
  reducedMotionMediaQuery =
    typeof window.matchMedia === 'function'
      ? window.matchMedia('(prefers-reduced-motion: reduce)')
      : null;
  reducedMotionMediaQuery?.addEventListener(
    'change',
    handleReducedMotionSourceChange,
  );
  window.addEventListener('storage', handleReducedMotionStorageChange);
  reducedMotionSourcesAttached = true;
}

function detachReducedMotionSourcesIfIdle(): void {
  if (
    !reducedMotionSourcesAttached
    || reducedMotionListeners.size > 0
    || typeof window === 'undefined'
  ) return;
  reducedMotionMediaQuery?.removeEventListener(
    'change',
    handleReducedMotionSourceChange,
  );
  window.removeEventListener('storage', handleReducedMotionStorageChange);
  reducedMotionMediaQuery = null;
  reducedMotionSourcesAttached = false;
}

function subscribeReducedMotion(listener: ReducedMotionListener): () => void {
  reducedMotionListeners.add(listener);
  attachReducedMotionSources();
  listener(resolveReducedMotion());
  return () => {
    reducedMotionListeners.delete(listener);
    detachReducedMotionSourcesIfIdle();
  };
}

/** 应用初始化时调用一次：把 OS 偏好同步到 root，避免首屏闪一帧动画。 */
export function initReducedMotionAttribute(): void {
  if (typeof window === 'undefined') return;
  syncRootAttribute(resolveReducedMotion());
}

/** 给业务组件用的 Hook：返回当前是否处于「降低动效」模式。 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false;
    return resolveReducedMotion();
  });

  useEffect(() => subscribeReducedMotion(setReduced), []);

  return reduced;
}

/** /api/meta 与 /api/settings/preferences 注入的 App 端 reduceMotion。 */
export function setRemoteReducedMotion(value: boolean): void {
  remoteReducedMotion = value;
  publishReducedMotion();
}
