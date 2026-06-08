import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';

export interface DialogExitMotionOptions {
  exitMs?: number;
  closeOnEscape?: boolean;
}

export function useDialogExitMotion(
  onClose: () => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
) {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const closingRef = useRef(false);
  const timeoutRef = useRef<number | null>(null);
  const exitMs =
    typeof optionsOrExitMs === 'number'
      ? optionsOrExitMs
      : optionsOrExitMs?.exitMs;
  const closeOnEscape =
    typeof optionsOrExitMs === 'object'
      ? optionsOrExitMs.closeOnEscape !== false
      : true;

  const requestClose = useCallback(() => {
    if (closingRef.current) return;
    closingRef.current = true;
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
  }, [exitMs, onClose, reduceMotion]);

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
    if (!closeOnEscape) return undefined;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [closeOnEscape, requestClose]);

  return { closing, requestClose };
}
