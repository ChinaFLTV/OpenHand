import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { useDialogExitMotion } from './useDialogExitMotion';
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
  const [open, setOpen] = useState(initiallyOpen);
  const openRef = useRef(initiallyOpen);
  const closingRef = useRef(false);
  const { closing, requestClose, resetClosing } = useDialogExitMotion(() => {
    openRef.current = false;
    closingRef.current = false;
    setOpen(false);
    resetClosing();
  }, { exitMs });

  const show = useCallback(() => {
    resetClosing();
    openRef.current = true;
    closingRef.current = false;
    setOpen(true);
  }, [resetClosing]);

  const hide = useCallback(() => {
    if (!openRef.current || closingRef.current) return;
    closingRef.current = true;
    requestClose();
  }, [requestClose]);

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
  const delayMs = reduceMotion ? 0 : normalizeEnterDelayMs(enterDelayMs);
  const { visible, closing, show, hide } = useDelayedVisibility({
    initiallyOpen: open && delayMs === 0,
    exitMs,
  });
  const { clearTimer, scheduleTimer } = useTimeoutController();

  useEffect(() => {
    clearTimer();
    if (!open) {
      hide();
    } else if (visible) {
      show();
    } else {
      scheduleTimer(show, delayMs);
    }
    return clearTimer;
  }, [clearTimer, delayMs, hide, open, scheduleTimer, show, visible]);

  return { visible, closing };
}
