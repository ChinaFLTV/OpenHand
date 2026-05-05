// 监听浏览器的 prefers-reduced-motion 媒体查询 + localStorage 用户开关。
// 任一开启即视为「降低动效」，由 global.css 的 [data-motion='reduced'] 选择器统一关停。
//
// 与 Flutter 端 reduceMotion 设置之间是独立的：因为 Web 客户端可能被任意浏览器加载，
// 没法直接读 OpenHandApp 的 SettingsController。后续若希望联动，可走 /api/meta 注入。

import { useEffect, useState } from 'preact/hooks';

const STORAGE_KEY = 'openhand_web_reduce_motion';

function readUserPref(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === '1';
  } catch (_) {
    return false;
  }
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

/** 应用初始化时调用一次：把 OS 偏好同步到 root，避免首屏闪一帧动画。 */
export function initReducedMotionAttribute(): void {
  if (typeof window === 'undefined') return;
  const mql = window.matchMedia('(prefers-reduced-motion: reduce)');
  const userPref = readUserPref();
  syncRootAttribute(mql.matches || userPref);
}

/** 给业务组件用的 Hook：返回当前是否处于「降低动效」模式。 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches || readUserPref();
  });

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const mql = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => {
      const next = mql.matches || readUserPref();
      setReduced(next);
      syncRootAttribute(next);
    };
    update();
    mql.addEventListener('change', update);
    // 监听 localStorage 跨标签页变化。
    const onStorage = (ev: StorageEvent) => {
      if (ev.key === STORAGE_KEY) update();
    };
    window.addEventListener('storage', onStorage);
    return () => {
      mql.removeEventListener('change', update);
      window.removeEventListener('storage', onStorage);
    };
  }, []);

  return reduced;
}

/** 用户主动切换降低动效（例如在设置面板中）。 */
export function setUserReducedMotion(value: boolean): void {
  try {
    if (value) {
      localStorage.setItem(STORAGE_KEY, '1');
    } else {
      localStorage.removeItem(STORAGE_KEY);
    }
  } catch (_) {
    // ignore quota errors — 我们不阻塞 UI。
  }
  // 立刻同步 root 属性，避免页内其他组件等到 setState 触发的下个 tick。
  if (typeof window !== 'undefined') {
    const osPref = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    syncRootAttribute(osPref || value);
  }
}
