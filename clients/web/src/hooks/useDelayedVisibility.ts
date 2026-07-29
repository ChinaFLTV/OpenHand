import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { normalizeDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';
import { useTimeoutController } from './useTimeoutController';
import {
  MAX_BROWSER_TIMEOUT_MS,
  normalizeDurationMs,
} from '../shared/util/number';

interface DelayedVisibilityOptions {
  exitMs?: number;
  initiallyOpen?: boolean;
}

interface ControlledDelayedVisibilityOptions {
  enterDelayMs?: number;
  exitMs?: number;
}

interface DelayedVisibilityController {
  open: boolean;
  closing: boolean;
  visible: boolean;
  show: () => void;
  hide: () => void;
  toggle: () => void;
}

interface ControlledDelayedVisibilityState {
  visible: boolean;
  closing: boolean;
}

type VisibilityPhase = 'hidden' | 'visible' | 'closing';

function normalizeEnterDelayMs(value: number | undefined): number {
  return normalizeDurationMs(value, {
    fallback: 0,
    min: 0,
    max: MAX_BROWSER_TIMEOUT_MS,
  });
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
  const { clearTimer: clearCloseTimer, scheduleTimer: scheduleCloseTimer } =
    useTimeoutController();

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
    scheduleCloseTimer(() => {
      openRef.current = false;
      closingRef.current = false;
      setOpen(false);
      setClosing(false);
    }, closeMs);
  }, [clearCloseTimer, exitMs, reduceMotion, scheduleCloseTimer]);

  const toggle = useCallback(() => {
    if (openRef.current && !closingRef.current) {
      hide();
    } else {
      show();
    }
  }, [hide, show]);

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
  const [phase, setPhase] = useState<VisibilityPhase>(() => {
    const delayMs = reduceMotion ? 0 : normalizeEnterDelayMs(enterDelayMs);
    return open && delayMs <= 0 ? 'visible' : 'hidden';
  });
  const phaseRef = useRef<VisibilityPhase>(phase);
  const { clearTimer, scheduleTimer } = useTimeoutController();

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

      const reveal = () => {
        phaseRef.current = 'visible';
        setPhase('visible');
      };

      const safeEnterDelayMs = reduceMotion ? 0 : normalizeEnterDelayMs(enterDelayMs);
      if (safeEnterDelayMs <= 0 || typeof window === 'undefined') {
        reveal();
        return;
      }

      scheduleTimer(reveal, safeEnterDelayMs);
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
    scheduleTimer(() => {
      phaseRef.current = 'hidden';
      setPhase('hidden');
    }, closeMs);
  }, [clearTimer, enterDelayMs, exitMs, open, reduceMotion, scheduleTimer]);

  return {
    visible: phase !== 'hidden',
    closing: phase === 'closing',
  };
}
