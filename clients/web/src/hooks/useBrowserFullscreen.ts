// 浏览器全屏状态与切换。

import { useCallback, useEffect, useState } from 'preact/hooks';
import { showSnackbar } from '../components/Snackbar';
import { t } from '../i18n';

interface BrowserFullscreenController {
  active: boolean;
  toggle: () => Promise<void>;
}

export function useBrowserFullscreen(): BrowserFullscreenController {
  const [active, setActive] = useState(false);

  useEffect(() => {
    if (typeof document === 'undefined') return;
    const sync = () => setActive(Boolean(document.fullscreenElement));
    sync();
    document.addEventListener('fullscreenchange', sync);
    return () => document.removeEventListener('fullscreenchange', sync);
  }, []);

  const toggle = useCallback(async () => {
    if (typeof document === 'undefined') return;
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
        return;
      }
      // 全屏目标固定挂到 <html>：让 OverlayPortal 能把浮层放到 body 上，避开
      // .oh-page-fade 进场动画残留的 transform 形成的 containing block——否则
      // 全屏下点按钮弹不出 PopMenu / Dialog / Snackbar。
      const target = document.documentElement;
      if (!target.requestFullscreen) {
        showSnackbar(t('topbar.fullscreen.unsupported', '当前浏览器不支持全屏'), {
          tone: 'error',
        });
        return;
      }
      await target.requestFullscreen();
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      showSnackbar(
        `${t('topbar.fullscreen.failed', '切换全屏失败')}：${message}`,
        { tone: 'error' },
      );
    }
  }, []);

  return { active, toggle };
}
