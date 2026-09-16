import type { FitAddon } from '@xterm/addon-fit';
import type { Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';
import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  controlMachineTerminal,
  getMachineTerminal,
  writeMachineTerminal,
  type MachineTerminalSnapshot,
  type MachineTerminalWorkspace,
} from '../../../api/sessions';
import { ConfirmDialog } from '../../../components/ConfirmDialog';
import { DialogFooterActions } from '../../../components/DialogChrome';
import {
  DialogActionButton,
  DialogFrame,
  createStandardDialogFrameAppearance,
} from '../../../components/DialogFrame';
import {
  copyTextWithFeedback,
  showSnackbar,
} from '../../../components/Snackbar';
import { useAsyncPolling } from '../../../hooks/useAsyncPolling';
import { useDialogExitMotion } from '../../../hooks/useDialogExitMotion';
import { t } from '../../../i18n';
import {
  formatLocalDateTimeSecond,
  formatLocalTimeSecond,
} from '../../../shared/util/date_time';
import { isAbortError } from '../../../shared/util/errors';
import {
  ComposerIcon,
  type ComposerIconName,
} from './SessionComposerIcon';

const MACHINE_TERMINAL_XTERM_THEME = {
  background: '#0B0D10',
  foreground: '#E7ECF3',
  cursor: '#E6F6C3',
  selectionBackground: '#4D7CFF66',
  black: '#101217',
  red: '#FF6B6B',
  green: '#5FE3A1',
  yellow: '#E8D66B',
  blue: '#75A7FF',
  magenta: '#D98CFF',
  cyan: '#62DCE8',
  white: '#F4F7FB',
  brightBlack: '#6E7681',
  brightRed: '#FF8F86',
  brightGreen: '#7CF3B6',
  brightYellow: '#F4E58D',
  brightBlue: '#9DBDFF',
  brightMagenta: '#E7A8FF',
  brightCyan: '#8FEAF2',
  brightWhite: '#FFFFFF',
} as const;
const MACHINE_TERMINAL_POLL_INTERVAL_MS = 1200;
const MACHINE_TERMINAL_POLL_TIMEOUT_MS = 15_000;
const MACHINE_TERMINAL_WRITE_TIMEOUT_MS = 15_000;
const MACHINE_TERMINAL_CONTROL_TIMEOUT_MS = 15_000;
const MACHINE_TERMINAL_INPUT_CHUNK_CODE_UNITS = 32 * 1024;
const MACHINE_TERMINAL_MAX_BUFFERED_CODE_UNITS = 512 * 1024;
let machineTerminalRuntimePromise: Promise<{
  TerminalConstructor: typeof Terminal;
  FitAddonConstructor: typeof FitAddon;
}> | null = null;

function machineTerminalInputPrefixLength(value: string, maxCodeUnits: number): number {
  const end = Math.min(value.length, Math.max(0, maxCodeUnits));
  if (end === 0 || end >= value.length) return end;
  const previous = value.charCodeAt(end - 1);
  const next = value.charCodeAt(end);
  return previous >= 0xD800 && previous <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF
    ? end - 1
    : end;
}

function loadMachineTerminalRuntime() {
  if (machineTerminalRuntimePromise) return machineTerminalRuntimePromise;
  const loading = Promise.all([
    import('@xterm/xterm'),
    import('@xterm/addon-fit'),
  ])
    .then(([terminalModule, fitModule]) => ({
      TerminalConstructor: terminalModule.Terminal,
      FitAddonConstructor: fitModule.FitAddon,
    }))
    .catch((error) => {
      machineTerminalRuntimePromise = null;
      throw error;
    });
  machineTerminalRuntimePromise = loading;
  return loading;
}

export function MachineTerminalPanel({ sessionId }: { sessionId: string }) {
  const shellRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const lastAnsiOutputRef = useRef('');
  const writeErrorShownRef = useRef(false);
  const activeTerminalIdRef = useRef<string | undefined>(undefined);
  const lastResizeRef = useRef('');
  const resizeFrameRef = useRef<number | null>(null);
  const requestTerminalFitRef = useRef<(() => void) | null>(null);
  const mountedRef = useRef(true);
  const sessionIdRef = useRef(sessionId);
  const busyActionRef = useRef<string | null>(null);
  const actionAbortRef = useRef<AbortController | null>(null);
  const historyRefreshingRef = useRef(false);
  const historyAbortRef = useRef<AbortController | null>(null);
  const [workspace, setWorkspace] = useState<MachineTerminalWorkspace | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [historyRefreshing, setHistoryRefreshing] = useState(false);
  const [detailTerminalId, setDetailTerminalId] = useState<string | null>(null);
  const active = workspace?.active_terminal ?? null;
  const detailTerminal = detailTerminalId == null
    ? null
    : workspace?.terminals.find(
        (terminal) => terminal.terminal_id === detailTerminalId,
      ) ?? null;
  const historyDetailsActive = historyOpen || detailTerminalId != null;
  sessionIdRef.current = sessionId;

  useEffect(() => {
    if (
      detailTerminalId != null &&
      workspace != null &&
      detailTerminal == null
    ) {
      setDetailTerminalId(null);
    }
  }, [detailTerminal, detailTerminalId, workspace]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      actionAbortRef.current?.abort();
      historyAbortRef.current?.abort();
    };
  }, []);

  useEffect(() => {
    actionAbortRef.current?.abort();
    historyAbortRef.current?.abort();
    actionAbortRef.current = null;
    historyAbortRef.current = null;
    busyActionRef.current = null;
    historyRefreshingRef.current = false;
    setBusyAction(null);
    setHistoryRefreshing(false);
    setHistoryOpen(false);
    setDetailTerminalId(null);
    setWorkspace(null);
  }, [sessionId]);

  useEffect(() => {
    activeTerminalIdRef.current = active?.terminal_id || undefined;
    lastResizeRef.current = '';
    requestTerminalFitRef.current?.();
  }, [active?.terminal_id]);

  const fetchTerminal = useCallback(async (
    start = true,
    options: { includeHistory?: boolean; signal?: AbortSignal } = {},
  ) => {
    const res = await getMachineTerminal(sessionId, {
      start,
      includeHistory: options.includeHistory,
      signal: options.signal,
    });
    return res.terminal;
  }, [sessionId]);

  useEffect(() => {
    const root = shellRef.current;
    if (!root) return;
    let disposed = false;
    let terminal: Terminal | null = null;
    let dataDisposable: { dispose: () => void } | null = null;
    let resizeObserver: ResizeObserver | null = null;
    let scheduleResize: (() => void) | null = null;
    let pendingInputs: Array<{ data: string; terminalId?: string }> = [];
    let bufferedInputCodeUnits = 0;
    let writingInput = false;
    let inputOverflowShown = false;
    let pendingResize: {
      key: string;
      terminalId?: string;
      columns: number;
      rows: number;
    } | null = null;
    let resizing = false;
    const terminalRequestAbortController = new AbortController();

    void loadMachineTerminalRuntime()
      .then(({ TerminalConstructor, FitAddonConstructor }) => {
        if (disposed) return;
        terminal = new TerminalConstructor({
          allowProposedApi: false,
          convertEol: true,
          cursorBlink: true,
          cursorStyle: 'block',
          fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", monospace',
          fontSize: 13,
          lineHeight: 1.18,
          scrollback: 5000,
          theme: MACHINE_TERMINAL_XTERM_THEME,
        });
        const fit = new FitAddonConstructor();
        terminal.loadAddon(fit);
        terminal.open(root);
        try {
          fit.fit();
        } catch {
          // 布局稳定后由下方定时调整重试。
        }
        terminal.focus();
        terminalRef.current = terminal;
        const flushInput = async () => {
          if (writingInput || disposed) return;
          writingInput = true;
          try {
            while (!disposed && pendingInputs.length > 0) {
              const pending = pendingInputs[0];
              const chunkLength = machineTerminalInputPrefixLength(
                pending.data,
                MACHINE_TERMINAL_INPUT_CHUNK_CODE_UNITS,
              );
              const data = pending.data.slice(0, chunkLength);
              const terminalId = pending.terminalId;
              pending.data = pending.data.slice(chunkLength);
              bufferedInputCodeUnits -= chunkLength;
              if (!pending.data) pendingInputs.shift();
              if (bufferedInputCodeUnits < MACHINE_TERMINAL_MAX_BUFFERED_CODE_UNITS / 2) {
                inputOverflowShown = false;
              }
              const res = await writeMachineTerminal(
                sessionId,
                { data, terminalId },
                {
                  signal: terminalRequestAbortController.signal,
                  timeoutMs: MACHINE_TERMINAL_WRITE_TIMEOUT_MS,
                },
              );
              if (disposed) return;
              writeErrorShownRef.current = false;
              if (res.terminal) setWorkspace(res.terminal);
            }
          } catch (error) {
            pendingInputs = [];
            bufferedInputCodeUnits = 0;
            if (disposed || isAbortError(error)) return;
            if (!writeErrorShownRef.current) {
              writeErrorShownRef.current = true;
              const message = error instanceof Error ? error.message : String(error);
              showSnackbar(`${t('terminal.write.failed', '终端写入失败')}：${message}`, { tone: 'error' });
            }
          } finally {
            writingInput = false;
            if (!disposed && pendingInputs.length > 0) void flushInput();
          }
        };
        dataDisposable = terminal.onData((data) => {
          if (disposed || !data) return;
          const remaining = MACHINE_TERMINAL_MAX_BUFFERED_CODE_UNITS - bufferedInputCodeUnits;
          const acceptedLength = machineTerminalInputPrefixLength(data, remaining);
          if (acceptedLength > 0) {
            const terminalId = activeTerminalIdRef.current;
            const last = pendingInputs[pendingInputs.length - 1];
            if (last && last.terminalId === terminalId) {
              last.data += data.slice(0, acceptedLength);
            } else {
              pendingInputs.push({ data: data.slice(0, acceptedLength), terminalId });
            }
            bufferedInputCodeUnits += acceptedLength;
          }
          if (acceptedLength < data.length && !inputOverflowShown) {
            inputOverflowShown = true;
            showSnackbar(
              t('terminal.write.bufferFull', '终端输入缓冲区已满，超出部分未发送。'),
              { tone: 'error' },
            );
          }
          void flushInput();
        });
        const flushResize = async () => {
          if (resizing || disposed) return;
          resizing = true;
          try {
            while (!disposed && pendingResize) {
              const resize = pendingResize;
              pendingResize = null;
              try {
                await controlMachineTerminal(
                  sessionId,
                  {
                    action: 'resize',
                    terminalId: resize.terminalId,
                    columns: resize.columns,
                    rows: resize.rows,
                  },
                  {
                    signal: terminalRequestAbortController.signal,
                    timeoutMs: MACHINE_TERMINAL_CONTROL_TIMEOUT_MS,
                  },
                );
              } catch (error) {
                if (disposed || isAbortError(error)) return;
                if (lastResizeRef.current === resize.key) lastResizeRef.current = '';
              }
            }
          } finally {
            resizing = false;
            if (!disposed && pendingResize) void flushResize();
          }
        };
        const publishResize = () => {
          if (disposed || !terminal || root.clientWidth <= 0 || root.clientHeight <= 0) return;
          try {
            fit.fit();
          } catch {
            return;
          }
          const columns = terminal.cols;
          const rows = terminal.rows;
          if (!Number.isFinite(columns) || !Number.isFinite(rows) || columns <= 0 || rows <= 0) return;
          const key = `${activeTerminalIdRef.current || ''}:${columns}x${rows}`;
          if (lastResizeRef.current === key) return;
          lastResizeRef.current = key;
          pendingResize = {
            key,
            terminalId: activeTerminalIdRef.current,
            columns,
            rows,
          };
          void flushResize();
        };

        scheduleResize = () => {
          if (resizeFrameRef.current != null) {
            window.cancelAnimationFrame(resizeFrameRef.current);
          }
          resizeFrameRef.current = window.requestAnimationFrame(() => {
            resizeFrameRef.current = window.requestAnimationFrame(() => {
              resizeFrameRef.current = null;
              publishResize();
            });
          });
        };

        resizeObserver = typeof ResizeObserver === 'undefined'
          ? null
          : new ResizeObserver(scheduleResize);
        requestTerminalFitRef.current = scheduleResize;
        resizeObserver?.observe(root);
        if (root.parentElement) resizeObserver?.observe(root.parentElement);
        window.addEventListener('resize', scheduleResize);
        scheduleResize();
      })
      .catch((error) => {
        if (disposed) return;
        const message = error instanceof Error ? error.message : String(error);
        showSnackbar(`${t('terminal.load.failed', '终端组件加载失败')}：${message}`, { tone: 'error' });
      });

    return () => {
      disposed = true;
      pendingInputs = [];
      pendingResize = null;
      bufferedInputCodeUnits = 0;
      terminalRequestAbortController.abort();
      dataDisposable?.dispose();
      resizeObserver?.disconnect();
      if (scheduleResize) window.removeEventListener('resize', scheduleResize);
      if (resizeFrameRef.current != null) {
        window.cancelAnimationFrame(resizeFrameRef.current);
        resizeFrameRef.current = null;
      }
      terminal?.dispose();
      terminalRef.current = null;
      requestTerminalFitRef.current = null;
      lastAnsiOutputRef.current = '';
    };
  }, [sessionId]);

  useAsyncPolling(
    async (isActive, signal) => {
      const next = await fetchTerminal(true, {
        includeHistory: historyDetailsActive,
        signal,
      });
      if (!isActive()) return;
      setWorkspace(next);
      const activeTerminal = next.active_terminal ?? null;
      const ansiOutput = activeTerminal?.ansi_output ?? activeTerminal?.output ?? '';
      const terminal = terminalRef.current;
      if (!terminal) return;
      const previous = lastAnsiOutputRef.current;
      if (ansiOutput.startsWith(previous)) {
        const delta = ansiOutput.slice(previous.length);
        if (delta) terminal.write(delta);
      } else {
        terminal.reset();
        if (ansiOutput) terminal.write(ansiOutput);
      }
      lastAnsiOutputRef.current = ansiOutput;
    },
    {
      intervalMs: MACHINE_TERMINAL_POLL_INTERVAL_MS,
      taskTimeoutMs: MACHINE_TERMINAL_POLL_TIMEOUT_MS,
    },
  );

  async function runControl(
    action: string,
    terminalId?: string,
    options: { includeHistory?: boolean; throwOnError?: boolean } = {},
  ): Promise<void> {
    if (busyActionRef.current) return;
    const requestSessionId = sessionId;
    const controller = new AbortController();
    busyActionRef.current = action;
    actionAbortRef.current = controller;
    setBusyAction(action);
    try {
      const res = await controlMachineTerminal(
        requestSessionId,
        {
          action,
          terminalId,
          includeHistory: options.includeHistory,
        },
        {
          signal: controller.signal,
          timeoutMs: MACHINE_TERMINAL_CONTROL_TIMEOUT_MS,
        },
      );
      if (!mountedRef.current || sessionIdRef.current !== requestSessionId) return;
      setWorkspace(res.terminal);
      if (action === 'clear' || action === 'select' || action === 'new' || action === 'duplicate' || action === 'close' || action === 'restore' || action === 'delete') {
        lastAnsiOutputRef.current = '';
        terminalRef.current?.reset();
        const nextActive = res.terminal.active_terminal ?? null;
        const output = nextActive?.ansi_output ?? nextActive?.output ?? '';
        if (output) terminalRef.current?.write(output);
        lastAnsiOutputRef.current = output;
      }
      terminalRef.current?.focus();
    } catch (error) {
      if (controller.signal.aborted || isAbortError(error)) {
        if (options.throwOnError) throw error;
        return;
      }
      const message = error instanceof Error ? error.message : String(error);
      if (mountedRef.current && sessionIdRef.current === requestSessionId) {
        showSnackbar(`${t('terminal.control.failed', '终端操作失败')}：${message}`, { tone: 'error' });
      }
      if (options.throwOnError) throw error;
    } finally {
      const ownsRequest = actionAbortRef.current === controller;
      if (ownsRequest) {
        actionAbortRef.current = null;
        busyActionRef.current = null;
      }
      if (ownsRequest && mountedRef.current && sessionIdRef.current === requestSessionId) {
        setBusyAction(null);
      }
    }
  }

  async function openHistoryDialog(): Promise<void> {
    if (historyRefreshingRef.current) return;
    const requestSessionId = sessionId;
    const controller = new AbortController();
    historyRefreshingRef.current = true;
    historyAbortRef.current = controller;
    setHistoryOpen(true);
    setHistoryRefreshing(true);
    try {
      const next = await fetchTerminal(false, {
        includeHistory: true,
        signal: controller.signal,
      });
      if (!mountedRef.current || sessionIdRef.current !== requestSessionId) return;
      setWorkspace(next);
    } catch (error) {
      if (controller.signal.aborted || isAbortError(error)) return;
      const message = error instanceof Error ? error.message : String(error);
      if (mountedRef.current && sessionIdRef.current === requestSessionId) {
        showSnackbar(`${t('terminal.history.sync.failed', '同步终端历史失败')}：${message}`, { tone: 'error' });
      }
    } finally {
      const ownsRequest = historyAbortRef.current === controller;
      if (ownsRequest) {
        historyAbortRef.current = null;
        historyRefreshingRef.current = false;
      }
      if (ownsRequest && mountedRef.current && sessionIdRef.current === requestSessionId) {
        setHistoryRefreshing(false);
      }
    }
  }

  const tabs = (workspace?.terminals ?? []).filter(terminalAttached);
  const status = active?.status ?? 'starting';
  return (
    <>
      <aside class="oh-machine-terminal-panel">
        <div class="oh-machine-terminal-header">
          <div class="oh-machine-terminal-title">
            <span class="oh-machine-terminal-glyph" aria-hidden>
              <ComposerIcon name="mode" size={18} />
            </span>
            <span class="min-w-0">
              <span class="oh-machine-terminal-title-text">{t('terminal.title', '机器终端')}</span>
              <span class="oh-machine-terminal-subtitle">{active?.identity || t('terminal.starting', '正在启动')}</span>
            </span>
          </div>
          <button
            type="button"
            class="oh-machine-terminal-icon oh-tap-press"
            title={t('terminal.copyId', '复制终端 ID')}
            disabled={!active?.terminal_id}
            onClick={() => active?.terminal_id
              ? void copyTextWithFeedback(
                active.terminal_id,
                t('terminal.copyId.ok', '终端 ID 已复制'),
                t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'),
              )
              : undefined}
          >
            <ComposerIcon name="copy" size={16} />
          </button>
        </div>

        <div class="oh-machine-terminal-chips">
          <span class={`oh-machine-terminal-chip is-${status}`}>{terminalStatusLabel(status)}</span>
          <span class="oh-machine-terminal-chip">{active?.terminal_id || '-'}</span>
          <span class="oh-machine-terminal-chip">PID {active?.pid ?? '-'}</span>
          <span class="oh-machine-terminal-chip">{active ? `${active.columns}x${active.rows}` : '-'}</span>
        </div>

        <div class="oh-machine-terminal-actions">
          <button type="button" title={t('terminal.new', '新建终端')} onClick={() => void runControl('new')} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction)}>
            <ComposerIcon name="plus" size={16} />
          </button>
          <button type="button" title={t('terminal.duplicate', '复制终端')} onClick={() => void runControl('duplicate', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="copy" size={16} />
          </button>
          <button type="button" title={t('terminal.start', '启动')} onClick={() => void runControl('start', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || status === 'running')}>
            <ComposerIcon name="play" size={16} />
          </button>
          <button type="button" title={t('terminal.stop', '停止')} onClick={() => void runControl('stop', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || status !== 'running')}>
            <ComposerIcon name="stop" size={16} />
          </button>
          <button type="button" title={t('terminal.restart', '重启')} onClick={() => void runControl('restart', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="refresh" size={16} />
          </button>
          <button type="button" title={t('terminal.clear', '清屏')} onClick={() => void runControl('clear', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="spark" size={16} />
          </button>
          <button type="button" title={t('terminal.history', '执行历史')} onClick={() => void openHistoryDialog()} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(!workspace || historyRefreshing)}>
            <ComposerIcon name="history" size={16} />
          </button>
          <button type="button" title={t('terminal.close', '关闭终端')} onClick={() => void runControl('close', active?.terminal_id)} class="oh-machine-terminal-icon oh-tap-press" disabled={Boolean(busyAction || !active)}>
            <ComposerIcon name="close" size={16} />
          </button>
        </div>

        <div class="oh-machine-terminal-tabs" role="tablist">
          {tabs.map((terminal) => {
            const selected = terminal.terminal_id === workspace?.active_terminal_id;
            return (
              <button
                key={terminal.terminal_id}
                type="button"
                role="tab"
                aria-selected={selected}
                class={`oh-machine-terminal-tab ${selected ? 'is-active' : ''}`}
                onClick={() => selected ? undefined : void runControl('select', terminal.terminal_id)}
              >
                <span class={`oh-machine-terminal-dot is-${terminal.status}`} />
                <span class="truncate">{terminal.terminal_id}</span>
              </button>
            );
          })}
        </div>

        <div class="oh-machine-terminal-viewport" ref={shellRef} />

        <div class="oh-machine-terminal-meta">
          <span class="truncate">{active?.working_directory || '-'}</span>
          <span>{active ? formatLocalTimeSecond(active.updated_at) : '-'}</span>
        </div>
      </aside>
      {historyOpen && workspace ? (
        <MachineTerminalHistoryDialog
          workspace={workspace}
          busyAction={historyRefreshing ? 'history' : busyAction}
          onClose={() => setHistoryOpen(false)}
          onOpenDetails={(terminal) => setDetailTerminalId(terminal.terminal_id)}
          onRestore={(terminalId) => runControl('restore', terminalId, { includeHistory: true, throwOnError: true })}
          onDelete={(terminalId) => runControl('delete', terminalId, { includeHistory: true, throwOnError: true })}
        />
      ) : null}
      {detailTerminal ? (
        <MachineTerminalHistoryDetailDialog
          terminal={detailTerminal}
          onClose={() => setDetailTerminalId(null)}
        />
      ) : null}
    </>
  );
}

function MachineTerminalHistoryDialog({
  workspace,
  busyAction,
  onClose,
  onOpenDetails,
  onRestore,
  onDelete,
}: {
  workspace: MachineTerminalWorkspace;
  busyAction: string | null;
  onClose: () => void;
  onOpenDetails: (terminal: MachineTerminalSnapshot) => void;
  onRestore: (terminalId: string) => Promise<void>;
  onDelete: (terminalId: string) => Promise<void>;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [restoringId, setRestoringId] = useState<string | null>(null);
  const [pendingDeleteTerminal, setPendingDeleteTerminal] = useState<MachineTerminalSnapshot | null>(null);
  const terminals = workspace.terminals ?? [];
  const attachedCount = terminals.filter(terminalAttached).length;
  const commandTotal = terminals.reduce((total, item) => total + terminalCommandCount(item), 0);
  const outputTotal = terminals.reduce((total, item) => total + terminalHistoryOutputCharacters(item), 0);

  async function confirmDeleteTerminal(): Promise<boolean> {
    const terminal = pendingDeleteTerminal;
    if (!terminal || deletingId || busyAction) return false;
    const terminalId = terminal.terminal_id;
    setDeletingId(terminalId);
    try {
      await onDelete(terminalId);
      showSnackbar(t('terminal.history.delete.ok', '终端会话已删除'), { tone: 'success' });
      return true;
    } catch {
      // runControl 已报告具体错误。
      return false;
    } finally {
      setDeletingId(null);
    }
  }

  async function restoreTerminal(terminal: MachineTerminalSnapshot): Promise<void> {
    if (terminalAttached(terminal) || restoringId || deletingId || busyAction) return;
    const terminalId = terminal.terminal_id;
    setRestoringId(terminalId);
    try {
      await onRestore(terminalId);
      showSnackbar(t('terminal.history.restore.ok', '终端会话已恢复到面板'), { tone: 'success' });
    } catch {
      // runControl 已报告具体错误。
    } finally {
      setRestoringId(null);
    }
  }

  return (
    <>
      <DialogFrame
        closing={closing}
        onRequestClose={requestClose}
        ariaLabel={t('terminal.history.title', '终端执行历史')}
        {...createStandardDialogFrameAppearance({
          overlayTone: 'strong',
          overlayBlurPx: 4,
          panelClassName: 'oh-machine-terminal-history-dialog',
          panelSurface: {
            width: 'min(1180px, calc(100vw - 24px))',
            maxHeight: 'min(86vh, 740px)',
            overflow: 'hidden',
            background: 'var(--m3-surface)',
          },
        })}
      >
        <div class="oh-machine-terminal-dialog-head">
          <span class="oh-machine-terminal-dialog-icon" aria-hidden>
            <ComposerIcon name="history" size={20} />
          </span>
          <div class="min-w-0 flex-1">
            <h2>{t('terminal.history.title', '终端执行历史')}</h2>
            <p>
              {t('terminal.history.subtitle', '当前线程关联终端会话')} {terminals.length} · {t('terminal.history.panelCount', '面板')} {attachedCount} · {t('terminal.history.active', '当前')} {workspace.active_terminal_id || '-'}
            </p>
          </div>
          <button type="button" class="oh-machine-terminal-dialog-close oh-tap-press" onClick={requestClose} title={t('common.close', '关闭')}>
            <ComposerIcon name="close" size={16} />
          </button>
        </div>

        <div class="oh-machine-terminal-history-metrics">
          <MachineTerminalHistoryMetric icon="mode" label={t('terminal.history.metric.terminals', '终端数量')} value={`${terminals.length}`} />
          <MachineTerminalHistoryMetric icon="plan" label={t('terminal.history.metric.commands', '命令记录')} value={`${commandTotal}`} />
          <MachineTerminalHistoryMetric icon="file" label={t('terminal.history.metric.output', '历史输出')} value={formatTerminalHistorySize(outputTotal)} />
        </div>

        <div class="oh-machine-terminal-history-table-shell">
          {terminals.length === 0 ? (
            <div class="oh-machine-terminal-history-empty">{t('terminal.history.empty', '暂无终端会话历史。')}</div>
          ) : (
            <table class="oh-machine-terminal-history-table">
              <colgroup>
                <col class="oh-machine-terminal-history-col-terminal" />
                <col class="oh-machine-terminal-history-col-status" />
                <col class="oh-machine-terminal-history-col-pid" />
                <col class="oh-machine-terminal-history-col-size" />
                <col class="oh-machine-terminal-history-col-commands" />
                <col class="oh-machine-terminal-history-col-output" />
                <col class="oh-machine-terminal-history-col-started" />
                <col class="oh-machine-terminal-history-col-updated" />
                <col class="oh-machine-terminal-history-col-actions" />
              </colgroup>
              <thead>
                <tr>
                  <th>{t('terminal.history.col.terminal', '终端')}</th>
                  <th>{t('terminal.history.col.status', '状态')}</th>
                  <th>PID</th>
                  <th>{t('terminal.history.col.size', '尺寸')}</th>
                  <th>{t('terminal.history.col.commands', '命令')}</th>
                  <th>{t('terminal.history.col.output', '输出')}</th>
                  <th>{t('terminal.history.col.started', '启动时间')}</th>
                  <th>{t('terminal.history.col.updated', '更新时间')}</th>
                  <th class="text-right">{t('terminal.history.col.actions', '操作')}</th>
                </tr>
              </thead>
              <tbody>
                {terminals.map((terminal) => {
                  const active = terminal.terminal_id === workspace.active_terminal_id;
                  const deleting = deletingId === terminal.terminal_id;
                  const restoring = restoringId === terminal.terminal_id;
                  const attached = terminalAttached(terminal);
                  const actionDisabled = Boolean(deleting || restoring || busyAction);
                  return (
                    <tr
                      key={terminal.terminal_id}
                      class={`${active ? 'is-active ' : ''}is-clickable`}
                      tabIndex={actionDisabled ? -1 : 0}
                      title={t('terminal.history.viewDetails', '查看详情')}
                      onClick={() => actionDisabled ? undefined : onOpenDetails(terminal)}
                      onKeyDown={(event) => {
                        if (actionDisabled || (event.key !== 'Enter' && event.key !== ' ')) return;
                        event.preventDefault();
                        onOpenDetails(terminal);
                      }}
                    >
                      <td>
                        <span class="oh-machine-terminal-history-terminal">
                          <span class={`oh-machine-terminal-dot is-${terminal.status}`} />
                          <span class="truncate">{terminal.terminal_id}</span>
                          {active ? <span class="oh-machine-terminal-history-active">{t('terminal.history.active', '当前')}</span> : null}
                          {!attached ? <span class="oh-machine-terminal-history-active is-closed">{t('terminal.history.closed', '已关闭')}</span> : null}
                        </span>
                      </td>
                      <td><span class={`oh-machine-terminal-history-status is-${terminal.status}`}>{terminalStatusLabel(terminal.status)}</span></td>
                      <td class="tabular-nums">{terminal.pid ?? '-'}</td>
                      <td class="tabular-nums">{terminal.columns}x{terminal.rows}</td>
                      <td class="tabular-nums">{terminalCommandCount(terminal)}</td>
                      <td>{formatTerminalHistorySize(terminalHistoryOutputCharacters(terminal))}</td>
                      <td class="oh-machine-terminal-history-time tabular-nums">{formatLocalDateTimeSecond(terminal.started_at)}</td>
                      <td class="oh-machine-terminal-history-time tabular-nums">{formatLocalDateTimeSecond(terminal.updated_at)}</td>
                      <td>
                        <div class="oh-machine-terminal-history-actions">
                          <button
                            type="button"
                            class="oh-machine-terminal-history-action oh-tap-press"
                            onClick={(event) => {
                              event.stopPropagation();
                              onOpenDetails(terminal);
                            }}
                            title={t('terminal.history.viewDetails', '查看详情')}
                            disabled={actionDisabled}
                          >
                            <ComposerIcon name="file" size={15} />
                          </button>
                          <button
                            type="button"
                            class="oh-machine-terminal-history-action oh-tap-press"
                            onClick={(event) => {
                              event.stopPropagation();
                              void restoreTerminal(terminal);
                            }}
                            title={attached ? t('terminal.history.restore.attached', '已在终端面板中') : t('terminal.history.restore', '恢复到终端面板')}
                            disabled={actionDisabled || attached}
                          >
                            <ComposerIcon name={restoring ? 'refresh' : 'restore'} size={15} />
                          </button>
                          <button
                            type="button"
                            class="oh-machine-terminal-history-action is-danger oh-tap-press"
                            onClick={(event) => {
                              event.stopPropagation();
                              setPendingDeleteTerminal(terminal);
                            }}
                            title={t('terminal.history.delete', '删除')}
                            disabled={actionDisabled}
                          >
                            <ComposerIcon name={deleting ? 'refresh' : 'trash'} size={15} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        <DialogFooterActions className="oh-machine-terminal-dialog-footer">
          <DialogActionButton onClick={requestClose} tone="ghost">
            <ComposerIcon name="close" size={14} />
            {t('common.close', '关闭')}
          </DialogActionButton>
        </DialogFooterActions>
      </DialogFrame>
      {pendingDeleteTerminal ? (
        <ConfirmDialog
          title={t('terminal.history.delete.confirmTitle', '删除终端历史?')}
          body={t(
            'terminal.history.delete.confirmBody',
            `将删除 ${pendingDeleteTerminal.terminal_id} 的会话、命令记录和历史输出，此操作不可恢复。`,
          )}
          danger
          busy={deletingId === pendingDeleteTerminal.terminal_id}
          confirmBeforeClose
          confirmLabel={deletingId === pendingDeleteTerminal.terminal_id ? t('sessions.delete.deleting', '正在删除…') : t('common.delete', '删除')}
          cancelLabel={t('common.cancel', '取消')}
          onCancel={() => setPendingDeleteTerminal(null)}
          onConfirm={confirmDeleteTerminal}
          onConfirmSuccess={() => setPendingDeleteTerminal(null)}
        />
      ) : null}
    </>
  );
}

function MachineTerminalHistoryMetric({
  icon,
  label,
  value,
}: {
  icon: ComposerIconName;
  label: string;
  value: string;
}) {
  return (
    <div class="oh-machine-terminal-history-metric">
      <span aria-hidden><ComposerIcon name={icon} size={17} /></span>
      <span class="truncate">{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function MachineTerminalHistoryDetailDialog({
  terminal,
  onClose,
}: {
  terminal: MachineTerminalSnapshot;
  onClose: () => void;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [view, setView] = useState<'commands' | 'replay'>(
    () => (terminal.command_history?.length ? 'commands' : 'replay'),
  );

  useEffect(() => {
    setView(terminal.command_history?.length ? 'commands' : 'replay');
  }, [terminal.terminal_id, terminal.command_history?.length]);

  async function copyDetails(): Promise<void> {
    await copyTextWithFeedback(
      terminalHistoryPlainText(terminal),
      t('terminal.history.copy.ok', '终端历史详情已复制'),
      t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'),
    );
  }

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      ariaLabel={t('terminal.detail.title', '终端历史详情')}
      {...createStandardDialogFrameAppearance({
        overlayTone: 'strong',
        overlayBlurPx: 4,
        panelClassName: 'oh-machine-terminal-detail-dialog',
        panelSurface: {
          width: 'min(980px, calc(100vw - 32px))',
          maxHeight: 'min(88vh, 780px)',
          overflow: 'hidden',
          background: 'var(--m3-surface)',
        },
      })}
    >
      <div class="oh-machine-terminal-dialog-head">
        <span class="oh-machine-terminal-dialog-icon" aria-hidden>
          <ComposerIcon name="file" size={20} />
        </span>
        <div class="min-w-0 flex-1">
          <h2>{t('terminal.detail.title', '终端历史详情')}</h2>
          <p>
            {terminal.terminal_id} · {formatTerminalHistorySize(terminalHistoryOutputCharacters(terminal))} · {terminalCommandCount(terminal)} {t('terminal.detail.commands', '条命令')}
          </p>
        </div>
        <button type="button" class="oh-machine-terminal-dialog-close oh-tap-press" onClick={() => void copyDetails()} title={t('terminal.history.copy', '复制详情')}>
          <ComposerIcon name="copy" size={16} />
        </button>
        <button type="button" class="oh-machine-terminal-dialog-close oh-tap-press" onClick={requestClose} title={t('common.close', '关闭')}>
          <ComposerIcon name="close" size={16} />
        </button>
      </div>

      <div class="oh-machine-terminal-replay-meta">
        <span class={`oh-machine-terminal-history-status is-${terminal.status}`}>{terminalStatusLabel(terminal.status)}</span>
        <span>{terminal.columns}x{terminal.rows}</span>
        <span>{formatLocalDateTimeSecond(terminal.updated_at)}</span>
      </div>
      <div class="oh-machine-terminal-detail-body">
        <div class="oh-machine-terminal-detail-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={view === 'commands'}
            class={`oh-machine-terminal-detail-tab ${view === 'commands' ? 'is-active' : ''}`}
            onClick={() => setView('commands')}
          >
            <ComposerIcon name="plan" size={15} />
            {t('terminal.detail.tab.commands', '命令输出')}
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={view === 'replay'}
            class={`oh-machine-terminal-detail-tab ${view === 'replay' ? 'is-active' : ''}`}
            onClick={() => setView('replay')}
          >
            <ComposerIcon name="mode" size={15} />
            {t('terminal.detail.tab.replay', '终端回放')}
          </button>
        </div>
        <div class="oh-machine-terminal-detail-pane">
          {view === 'commands'
            ? <MachineTerminalCommandHistoryList terminal={terminal} />
            : <MachineTerminalReplayViewport terminal={terminal} />}
        </div>
      </div>
    </DialogFrame>
  );
}

function MachineTerminalCommandHistoryList({ terminal }: { terminal: MachineTerminalSnapshot }) {
  const commands = terminal.command_history ?? [];
  if (commands.length === 0) {
    return <div class="oh-machine-terminal-history-empty">{t('terminal.detail.commands.empty', '暂无结构化命令记录。')}</div>;
  }
  return (
    <div class="oh-machine-terminal-command-list">
      {commands.map((entry, index) => (
        <article key={entry.id || `${entry.terminal_id}-${index}`} class="oh-machine-terminal-command-card">
          <header class="oh-machine-terminal-command-card-head">
            <span class={`oh-machine-terminal-command-state ${terminalCommandSucceeded(entry) ? 'is-success' : 'is-error'}`}>
              {terminalCommandSucceeded(entry) ? t('terminal.detail.command.ok', '完成') : t('terminal.detail.command.failed', '异常')}
            </span>
            <code>{entry.command}</code>
            <button
              type="button"
              class="oh-machine-terminal-history-action oh-tap-press"
              title={t('terminal.detail.command.copy', '复制输出')}
              onClick={() => {
                void copyTextWithFeedback(
                  terminalCommandPlainText(entry),
                  t('terminal.detail.command.copy.ok', '命令输出已复制'),
                  t('detail.copy.failed', '复制失败，请检查浏览器剪贴板权限'),
                );
              }}
            >
              <ComposerIcon name="copy" size={14} />
            </button>
          </header>
          <div class="oh-machine-terminal-command-meta">
            <span>#{index + 1}</span>
            <span>exit {entry.exit_code ?? '-'}</span>
            <span>{entry.duration_ms}ms</span>
            <span>{formatLocalDateTimeSecond(entry.completed_at)}</span>
            {entry.timed_out ? <span>{t('terminal.detail.command.timeout', '超时')}</span> : null}
          </div>
          <pre class="oh-machine-terminal-command-output">{terminalCommandOutput(entry)}</pre>
        </article>
      ))}
    </div>
  );
}

function MachineTerminalReplayViewport({ terminal }: { terminal: MachineTerminalSnapshot }) {
  const shellRef = useRef<HTMLDivElement | null>(null);
  const replayRef = useRef<Terminal | null>(null);
  const replayOutput = terminalReplayAnsiOutput(terminal);
  const replayOutputRef = useRef(replayOutput);
  const lastReplayOutputRef = useRef('');
  replayOutputRef.current = replayOutput;

  useEffect(() => {
    const root = shellRef.current;
    if (!root) return;
    let disposed = false;
    let renderFrame = 0;
    let resizeObserver: ResizeObserver | null = null;

    void loadMachineTerminalRuntime()
      .then(({ TerminalConstructor, FitAddonConstructor }) => {
        if (disposed) return;
        const replay = new TerminalConstructor({
          allowProposedApi: false,
          convertEol: true,
          cursorBlink: false,
          disableStdin: true,
          fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", monospace',
          fontSize: 13,
          lineHeight: 1.18,
          scrollback: 10000,
          theme: MACHINE_TERMINAL_XTERM_THEME,
        });
        const fit = new FitAddonConstructor();
        replay.loadAddon(fit);
        replay.open(root);
        replayRef.current = replay;

        const fitReplay = () => {
          if (disposed || root.clientWidth <= 0 || root.clientHeight <= 0) {
            return;
          }
          try {
            fit.fit();
          } catch {
            return;
          }
        };
        const scheduleFit = () => {
          if (renderFrame) cancelAnimationFrame(renderFrame);
          renderFrame = requestAnimationFrame(() => {
            renderFrame = requestAnimationFrame(() => {
              renderFrame = 0;
              fitReplay();
            });
          });
        };

        resizeObserver = typeof ResizeObserver === 'undefined'
          ? null
          : new ResizeObserver(scheduleFit);
        resizeObserver?.observe(root);
        fitReplay();
        const initialOutput = replayOutputRef.current;
        lastReplayOutputRef.current = initialOutput;
        replay.write(initialOutput, () => {
          if (!disposed) replay.scrollToTop();
        });
      })
      .catch((error) => {
        if (disposed) return;
        const message = error instanceof Error ? error.message : String(error);
        showSnackbar(`${t('terminal.load.failed', '终端组件加载失败')}：${message}`, { tone: 'error' });
      });

    return () => {
      disposed = true;
      if (renderFrame) cancelAnimationFrame(renderFrame);
      resizeObserver?.disconnect();
      replayRef.current?.dispose();
      replayRef.current = null;
      lastReplayOutputRef.current = '';
    };
  }, [terminal.terminal_id]);

  useEffect(() => {
    const replay = replayRef.current;
    if (!replay) return;
    const previous = lastReplayOutputRef.current;
    if (replayOutput.startsWith(previous)) {
      const delta = replayOutput.slice(previous.length);
      if (delta) replay.write(delta);
    } else {
      replay.reset();
      if (replayOutput) replay.write(replayOutput);
    }
    lastReplayOutputRef.current = replayOutput;
  }, [replayOutput]);

  return <div class="oh-machine-terminal-replay-viewport" ref={shellRef} />;
}

function terminalCommandCount(terminal: MachineTerminalSnapshot): number {
  return terminal.command_count ?? terminal.command_history?.length ?? 0;
}

function terminalAttached(terminal: MachineTerminalSnapshot): boolean {
  return terminal.attached !== false;
}

function terminalHistoryOutputCharacters(terminal: MachineTerminalSnapshot): number {
  return terminal.history_output_characters ?? terminal.output_characters ?? 0;
}

type MachineTerminalCommandEntry = NonNullable<MachineTerminalSnapshot['command_history']>[number];

function terminalCommandSucceeded(entry: MachineTerminalCommandEntry): boolean {
  return !entry.timed_out && !entry.error && (entry.exit_code ?? 0) === 0;
}

function terminalCommandOutput(entry: MachineTerminalCommandEntry): string {
  const output = entry.output.trimEnd();
  const error = entry.error?.trim();
  if (output && error) return `${output}\n\nerror: ${error}`;
  if (output) return output;
  if (error) return `error: ${error}`;
  return '(no output)';
}

function terminalCommandPlainText(entry: MachineTerminalCommandEntry): string {
  return [
    `$ ${entry.command}`,
    `terminal_id: ${entry.terminal_id}`,
    `started_at: ${entry.started_at}`,
    `completed_at: ${entry.completed_at}`,
    `duration_ms: ${entry.duration_ms}`,
    `exit_code: ${entry.exit_code ?? '-'}`,
    `timed_out: ${entry.timed_out}`,
    ...(entry.error?.trim() ? [`error: ${entry.error.trim()}`] : []),
    'output:',
    terminalCommandOutput(entry),
  ].join('\n');
}

function terminalHistoryPlainText(terminal: MachineTerminalSnapshot): string {
  const lines = [
    `terminal_id: ${terminal.terminal_id}`,
    `identity: ${terminal.identity}`,
    `status: ${terminal.status}`,
    `shell: ${terminal.shell}`,
    `working_directory: ${terminal.working_directory}`,
    `size: ${terminal.columns}x${terminal.rows}`,
    `attached: ${terminalAttached(terminal)}`,
    `pid: ${terminal.pid ?? '-'}`,
    `started_at: ${terminal.started_at}`,
    `updated_at: ${terminal.updated_at}`,
    `command_count: ${terminalCommandCount(terminal)}`,
    `history_output_characters: ${terminalHistoryOutputCharacters(terminal)}`,
  ];
  const commands = terminal.command_history ?? [];
  if (commands.length > 0) {
    lines.push('', 'commands:');
    for (const entry of commands) {
      lines.push('', `--- ${entry.id} ---`, terminalCommandPlainText(entry));
    }
  }
  const history = (terminal.history_output ?? terminal.output ?? '').trimEnd();
  if (history) {
    lines.push('', 'terminal_output:', history);
  }
  return lines.join('\n').trimEnd();
}

function formatTerminalHistorySize(characters: number): string {
  if (!Number.isFinite(characters) || characters <= 0) return '0';
  if (characters < 1024) return `${Math.round(characters)} chars`;
  const units = ['KB', 'MB', 'GB'];
  let value = characters / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value >= 10 ? value.toFixed(1) : value.toFixed(2)} ${units[unitIndex]}`;
}

function terminalReplayAnsiOutput(terminal: MachineTerminalSnapshot): string {
  const history = (terminal.history_ansi_output ?? '').trimEnd();
  if (history) return history;
  const live = (terminal.ansi_output ?? terminal.output ?? '').trimEnd();
  if (live) return live;
  const commandHistory = terminal.command_history ?? [];
  if (commandHistory.length > 0) {
    return commandHistory.map((entry) => {
      const output = entry.output.trimEnd();
      return [
        `\x1b[38;5;75m$ ${entry.command}\x1b[0m`,
        output,
        `\x1b[38;5;244mexit=${entry.exit_code ?? '-'} timeout=${entry.timed_out} duration=${entry.duration_ms}ms\x1b[0m`,
      ].filter(Boolean).join('\r\n');
    }).join('\r\n\r\n');
  }
  return '\x1b[38;5;245mNo terminal history recorded.\x1b[0m\r\n';
}

function terminalStatusLabel(status: string): string {
  if (status === 'running') return t('terminal.status.running', '运行中');
  if (status === 'starting') return t('terminal.status.starting', '启动中');
  if (status === 'stopped') return t('terminal.status.stopped', '已停止');
  if (status === 'failed') return t('terminal.status.failed', '异常');
  return t('terminal.status.idle', '待机');
}
