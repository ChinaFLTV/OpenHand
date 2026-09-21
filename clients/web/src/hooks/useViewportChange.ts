import { useLayoutEffect } from 'preact/hooks';
import { useRafScheduler } from './useRafScheduler';

/** 浮层共用视口监听；滚动与缩放每帧最多测量一次，隐藏后取消待执行测量。 */
export function useViewportChange(active: boolean, update: () => void): () => void {
  const { schedule, flush, cancel } = useRafScheduler(update);
  useLayoutEffect(() => {
    if (!active || typeof window === 'undefined') return;
    const viewport = window.visualViewport;
    schedule();
    window.addEventListener('scroll', schedule, true);
    window.addEventListener('resize', schedule);
    viewport?.addEventListener('scroll', schedule);
    viewport?.addEventListener('resize', schedule);
    return () => {
      window.removeEventListener('scroll', schedule, true);
      window.removeEventListener('resize', schedule);
      viewport?.removeEventListener('scroll', schedule);
      viewport?.removeEventListener('resize', schedule);
      cancel();
    };
  }, [active, schedule, cancel]);
  return flush;
}
