import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { normalizeDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';
import { normalizeDurationMs } from '../shared/util/number';

export interface DelayedVisibilityOptions {
  exitMs?: number;
  initiallyOpen?: boolean;
}

export interface ControlledDelayedVisibilityOptions {
  enterDelayMs?: number;
  exitMs?: number;
}

export interface DelayedVisibilityController {
  open: boolean;
  closing: boolean;
  visible: boolean;
  show: () => void;
  hide: () => void;
  toggle: () => void;
}

export interface ControlledDelayedVisibilityState {
  visible: boolean;
  closing: boolean;
}

type VisibilityPhase = 'hidden' | 'visible' | 'closing';

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
    const closeMs = reduceMotion ? 0 : normalizeDialogExitDurationMs(exitMs);
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

export function useControlledDelayedVisibility(
  open: boolean,
  {
    enterDelayMs = 0,
    exitMs,
  }: ControlledDelayedVisibilityOptions = {},
): ControlledDelayedVisibilityState {
  const reduceMotion = useReducedMotion();
  const [phase, setPhase] = useState<VisibilityPhase>(
    open ? 'visible' : 'hidden',
  );
  const phaseRef = useRef<VisibilityPhase>(phase);
  const timerRef = useRef<number | null>(null);

  const clearTimer = useCallback(() => {
    if (timerRef.current == null || typeof window === 'undefined') return;
    window.clearTimeout(timerRef.current);
    timerRef.current = null;
  }, []);

  useEffect(() => {
    phaseRef.current = phase;
  }, [phase]);

  useEffect(() => {
    clearTimer();
    if (open) {
      if (phaseRef.current !== 'hidden') {
        phaseRef.current = 'visible';
        setPhase('visible');
        return;
      }
      const delayMs = reduceMotion
        ? 0
        : normalizeDurationMs(enterDelayMs, { fallback: 0, min: 0 });
      if (delayMs <= 0 || typeof window === 'undefined') {
        phaseRef.current = 'visible';
        setPhase('visible');
        return;
      }
      timerRef.current = window.setTimeout(() => {
        timerRef.current = null;
        phaseRef.current = 'visible';
        setPhase('visible');
      }, delayMs);
      return;
    }

    if (phaseRef.current === 'hidden') return;
    phaseRef.current = 'closing';
    setPhase('closing');
    const closeMs = reduceMotion ? 0 : normalizeDialogExitDurationMs(exitMs);
    if (closeMs <= 0 || typeof window === 'undefined') {
      phaseRef.current = 'hidden';
      setPhase('hidden');
      return;
    }
    timerRef.current = window.setTimeout(() => {
      timerRef.current = null;
      phaseRef.current = 'hidden';
      setPhase('hidden');
    }, closeMs);
  }, [clearTimer, enterDelayMs, exitMs, open, reduceMotion]);

  useEffect(() => () => clearTimer(), [clearTimer]);

  return {
    visible: phase !== 'hidden',
    closing: phase === 'closing',
  };
}
