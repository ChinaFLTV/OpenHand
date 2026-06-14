import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { getDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';

export interface DelayedVisibilityOptions {
  exitMs?: number;
  initiallyOpen?: boolean;
}

export interface DelayedVisibilityController {
  open: boolean;
  closing: boolean;
  visible: boolean;
  show: () => void;
  hide: () => void;
  toggle: () => void;
}

function normalizeExitMs(value: number | undefined): number {
  if (value == null) return getDialogExitDurationMs();
  if (!Number.isFinite(value)) return getDialogExitDurationMs();
  return Math.max(0, Math.round(value));
}

export function useDelayedVisibility({
  exitMs,
  initiallyOpen = false,
}: DelayedVisibilityOptions = {}): DelayedVisibilityController {
  const reduceMotion = useReducedMotion();
  const [open, setOpen] = useState(initiallyOpen);
  const [closing, setClosing] = useState(false);
  const openRef = useRef(initiallyOpen);
  const closingRef = useRef(false);
  const closeTimerRef = useRef<number | null>(null);

  const clearCloseTimer = useCallback(() => {
    if (closeTimerRef.current == null || typeof window === 'undefined') return;
    window.clearTimeout(closeTimerRef.current);
    closeTimerRef.current = null;
  }, []);

  const show = useCallback(() => {
    clearCloseTimer();
    openRef.current = true;
    closingRef.current = false;
    setClosing(false);
    setOpen(true);
  }, [clearCloseTimer]);

  const hide = useCallback(() => {
    if (!openRef.current || closingRef.current) return;
    clearCloseTimer();
    const closeMs = reduceMotion ? 0 : normalizeExitMs(exitMs);
    if (closeMs <= 0 || typeof window === 'undefined') {
      openRef.current = false;
      closingRef.current = false;
      setOpen(false);
      setClosing(false);
      return;
    }
    closingRef.current = true;
    setClosing(true);
    closeTimerRef.current = window.setTimeout(() => {
      closeTimerRef.current = null;
      openRef.current = false;
      closingRef.current = false;
      setOpen(false);
      setClosing(false);
    }, closeMs);
  }, [clearCloseTimer, exitMs, reduceMotion]);

  const toggle = useCallback(() => {
    if (openRef.current && !closingRef.current) {
      hide();
    } else {
      show();
    }
  }, [hide, show]);

  useEffect(() => () => clearCloseTimer(), [clearCloseTimer]);

  return {
    open,
    closing,
    visible: open || closing,
    show,
    hide,
    toggle,
  };
}
