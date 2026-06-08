import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';

export function useDialogExitMotion(onClose: () => void, exitMs?: number) {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const timeoutRef = useRef<number | null>(null);

  const requestClose = useCallback(() => {
    if (closing) return;
    setClosing(true);
    const durationMs = exitMs ?? getDialogExitDurationMs();
    if (reduceMotion || durationMs <= 0 || typeof window === 'undefined') {
      onClose();
      return;
    }
    timeoutRef.current = window.setTimeout(() => {
      timeoutRef.current = null;
      onClose();
    }, durationMs);
  }, [closing, exitMs, onClose, reduceMotion]);

  useEffect(() => {
    return () => {
      if (timeoutRef.current != null) {
        window.clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  // 2026-06-08 — ESC 键统一收进 hook，所有使用 useDialogExitMotion 的弹窗
  // 自动获得 ESC-to-dismiss 能力，无需各自重复 keydown 监听。
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [requestClose]);

  return { closing, requestClose };
}