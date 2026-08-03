import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { useEventCallback } from './useEventCallback';
import { normalizeDialogExitDurationMs } from './useDialogMotionSettings';
import { useReducedMotion } from './useReducedMotion';
import { useTimeoutController } from './useTimeoutController';

interface DialogExitMotionOptions {
  exitMs?: number;
  closeOnEscape?: boolean;
  active?: boolean;
  onBeforeClose?: (reason?: string) => void;
}

interface DialogExitMotionController<Reason extends string = string> {
  closing: boolean;
  requestClose: () => void;
  requestCloseWithReason: (reason?: Reason) => void;
  resetClosing: () => void;
}

interface DialogEscapeStackEntry {
  readonly id: number;
  readonly closeOnEscape: () => boolean;
  readonly requestEscapeClose: () => void;
}

let nextDialogEscapeEntryId = 1;
let dialogEscapeStack: DialogEscapeStackEntry[] = [];
let dialogEscapeListenerAttached = false;

function topDialogEscapeEntry(): DialogEscapeStackEntry | undefined {
  return dialogEscapeStack[dialogEscapeStack.length - 1];
}

function handleGlobalDialogEscape(event: KeyboardEvent): void {
  if (event.defaultPrevented || event.key !== 'Escape') return;
  const entry = topDialogEscapeEntry();
  if (!entry) return;
  event.preventDefault();
  event.stopPropagation();
  if (entry.closeOnEscape()) {
    entry.requestEscapeClose();
  }
}

function ensureDialogEscapeListener(): void {
  if (dialogEscapeListenerAttached || typeof window === 'undefined') return;
  window.addEventListener('keydown', handleGlobalDialogEscape, true);
  dialogEscapeListenerAttached = true;
}

function detachDialogEscapeListenerIfIdle(): void {
  if (
    !dialogEscapeListenerAttached ||
    dialogEscapeStack.length > 0 ||
    typeof window === 'undefined'
  ) {
    return;
  }
  window.removeEventListener('keydown', handleGlobalDialogEscape, true);
  dialogEscapeListenerAttached = false;
}

function registerDialogEscapeEntry(entry: DialogEscapeStackEntry): () => void {
  dialogEscapeStack = dialogEscapeStack.filter((item) => item.id !== entry.id);
  dialogEscapeStack.push(entry);
  ensureDialogEscapeListener();
  return () => {
    dialogEscapeStack = dialogEscapeStack.filter((item) => item.id !== entry.id);
    detachDialogEscapeListenerIfIdle();
  };
}

export function useDialogExitMotion(
  onClose: () => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
): DialogExitMotionController;
export function useDialogExitMotion<Reason extends string>(
  onClose: (reason?: Reason) => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
): DialogExitMotionController<Reason>;
export function useDialogExitMotion<Reason extends string = string>(
  onClose: (reason?: Reason) => void,
  optionsOrExitMs?: number | DialogExitMotionOptions,
): DialogExitMotionController<Reason> {
  const reduceMotion = useReducedMotion();
  const [closing, setClosing] = useState(false);
  const options =
    typeof optionsOrExitMs === 'object' && optionsOrExitMs != null
      ? optionsOrExitMs
      : undefined;
  const escapeEntryIdRef = useRef(0);
  const closingRef = useRef(false);
  const closeReasonRef = useRef<Reason | undefined>(undefined);
  const { clearTimer, scheduleTimer } = useTimeoutController();
  const exitMs =
    typeof optionsOrExitMs === 'number' ? optionsOrExitMs : options?.exitMs;
  const closeOnEscape = options?.closeOnEscape !== false;
  const active = options?.active !== false;
  const onBeforeClose = options?.onBeforeClose as
    | ((reason?: Reason) => void)
    | undefined;

  const finishClose = useEventCallback(() => {
    const reason = closeReasonRef.current;
    closeReasonRef.current = undefined;
    onClose(reason);
  });

  const requestCloseWithReason = useEventCallback((reason?: Reason) => {
    if (closingRef.current) return;
    closeReasonRef.current = reason;
    try {
      onBeforeClose?.(reason);
    } finally {
      closingRef.current = true;
      setClosing(true);
      const durationMs = reduceMotion
        ? 0
        : normalizeDialogExitDurationMs(exitMs);
      scheduleTimer(finishClose, durationMs);
    }
  });
  const canCloseOnEscape = useEventCallback(() => closeOnEscape);

  const requestClose = useCallback(() => {
    requestCloseWithReason();
  }, [requestCloseWithReason]);

  const resetClosing = useCallback(() => {
    clearTimer();
    closingRef.current = false;
    closeReasonRef.current = undefined;
    setClosing(false);
  }, [clearTimer]);

  useEffect(() => {
    if (!active || typeof window === 'undefined') return undefined;
    if (escapeEntryIdRef.current === 0) {
      escapeEntryIdRef.current = nextDialogEscapeEntryId++;
    }
    const entry: DialogEscapeStackEntry = {
      id: escapeEntryIdRef.current,
      closeOnEscape: canCloseOnEscape,
      requestEscapeClose: () => {
        requestCloseWithReason('escape' as Reason);
      },
    };
    return registerDialogEscapeEntry(entry);
  }, [active, canCloseOnEscape, requestCloseWithReason]);

  return { closing, requestClose, requestCloseWithReason, resetClosing };
}
