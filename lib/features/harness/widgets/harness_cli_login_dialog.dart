import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_text_buffer.dart';
import '../../../shared/util/timer_safety.dart';
import '../service/harness_cli_catalog.dart';

class HarnessCliLoginDialog extends StatefulWidget {
  const HarnessCliLoginDialog({super.key, required this.entry});

  final CliScanEntry entry;

  @override
  State<HarnessCliLoginDialog> createState() => _HarnessCliLoginDialogState();
}

class _HarnessCliLoginDialogState extends State<HarnessCliLoginDialog> {
  static const int _maxBufferedChars = 120000;
  static const Duration _noOutputHintDelay = Duration(seconds: 8);
  static const Duration _loginTimeout = Duration(minutes: 15);
  static const Duration _processStopGracePeriod = Duration(milliseconds: 500);
  static const Duration _streamDrainTimeout = Duration(milliseconds: 500);

  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final TextEditingController _inputController = TextEditingController();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _noOutputTimer;
  Timer? _outputFlushTimer;
  final BoundedTextBuffer _pendingOutput = BoundedTextBuffer(
    maxCharacters: _maxBufferedChars,
  );
  final BoundedTextBuffer _outputBuffer = BoundedTextBuffer(
    maxCharacters: _maxBufferedChars,
  );
  Future<void>? _shutdownFuture;
  int _runGeneration = 0;
  bool _disposed = false;
  bool _starting = true;
  bool _finished = false;
  int? _exitCode;
  String? _errorMessage;

  String get _output => _outputBuffer.text;

  /// Pulses the green top-edge confirmation flash on successful login
  /// completion (exit 0).
  final ValueNotifier<int> _successPulse = ValueNotifier<int>(0);

  /// Pulses the red top-edge flash on process startup / runtime failure
  /// or non-zero exit codes.
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  HarnessCli get _cli => widget.entry.cli;
  String get _executable => widget.entry.resolvedPath ?? _cli.executable;
  List<String> get _loginArgs => _cli.loginArgs ?? const <String>[];
  String get _commandPreview =>
      formatHarnessCliCommandPreview(_executable, _loginArgs);
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _startInteractiveLogin();
  }

  @override
  void dispose() {
    _disposed = true;
    _runGeneration += 1;
    _noOutputTimer?.cancel();
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    _pendingOutput.clear();
    unawaited(_shutdownProcess());
    _inputController.dispose();
    _scrollController.dispose();
    _successPulse.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  Future<void> _startInteractiveLogin() async {
    final generation = ++_runGeneration;
    Process? startedProcess;
    try {
      final process = await startHarnessCliInteractiveProcess(
        executable: _executable,
        args: _loginArgs,
      );
      startedProcess = process;
      if (!_isRunActive(generation)) {
        unawaited(_terminateProcess(process, '终止迟到的登录进程'));
        return;
      }

      _process = process;

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      void complete(Completer<void> completer) {
        if (!completer.isCompleted) completer.complete();
      }

      void onStreamError(Object error, Completer<void> done) {
        if (_isRunActive(generation)) {
          _appendOutput('${_l10n.harnessCliLoginStreamError('$error')}\n');
        }
        complete(done);
      }

      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            _appendOutput,
            onError: (Object error, StackTrace _) =>
                onStreamError(error, stdoutDone),
            onDone: () => complete(stdoutDone),
          );
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            _appendOutput,
            onError: (Object error, StackTrace _) =>
                onStreamError(error, stderrDone),
            onDone: () => complete(stderrDone),
          );

      if (!_isRunActive(generation)) {
        await _shutdownProcess();
        return;
      }

      setState(() {
        _starting = false;
      });

      // Watchdog: if no output arrives within 8 seconds, show a diagnostic
      // hint so the user is not left staring at a blank screen.
      _noOutputTimer = startSafeTimer(_noOutputHintDelay, () {
        if (!_isRunActive(generation) ||
            _output.isNotEmpty ||
            _pendingOutput.isNotEmpty ||
            _finished) {
          return;
        }
        _appendOutput(_l10n.harnessCliLoginNoOutputHint);
      });

      final exitCode = await process.exitCode.timeout(_loginTimeout);
      _noOutputTimer?.cancel();
      await _waitForOutputDrain(stdoutDone, stderrDone);
      if (identical(_process, process)) _process = null;
      if (!_isRunActive(generation)) return;
      _flushPendingOutput();

      // If the process exited almost instantly with no output, it likely
      // crashed or was misconfigured.  Run diagnostics and display them.
      if (_output.isEmpty && exitCode != 0) {
        final diags = await collectHarnessCliFailureDiagnostics(_executable);
        if (diags.isNotEmpty && _isRunActive(generation)) {
          _appendOutput(diags.join('\n'));
          _appendOutput('\n');
        }
      }

      // If the output contains typical "no stdin" warnings, hint the user
      // to try the external terminal approach instead.
      if (_output.contains('no stdin data received') ||
          _output.contains('Not logged in') ||
          (_output.contains('Please run /login') && exitCode != 0)) {
        _appendOutput('\n');
        _appendOutput(_l10n.harnessCliLoginTtyRequiredHint);
      }

      if (!_isRunActive(generation)) return;
      setState(() {
        _finished = true;
        _exitCode = exitCode;
      });
      if (exitCode == 0) {
        _successPulse.value = _successPulse.value + 1;
      } else {
        _errorPulse.value = _errorPulse.value + 1;
      }
    } on TimeoutException {
      if (!_isRunActive(generation)) return;
      await _shutdownProcess();
      if (!_isRunActive(generation)) return;
      final message = _l10n.harnessCliLoginTimedOut(_loginTimeout.inMinutes);
      _appendOutput('$message\n');
      _flushPendingOutput();
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = message;
      });
      _errorPulse.value = _errorPulse.value + 1;
    } on ProcessException catch (error) {
      if (startedProcess != null) await _shutdownProcess();
      if (!_isRunActive(generation)) return;
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = _l10n.harnessCliLoginFailedToStartProcess(
          error.message,
        );
      });
      _errorPulse.value = _errorPulse.value + 1;
    } catch (error) {
      if (!_isRunActive(generation)) return;
      await _shutdownProcess();
      if (!_isRunActive(generation)) return;
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = '$error';
      });
      _errorPulse.value = _errorPulse.value + 1;
    } finally {
      if (identical(_process, startedProcess) && _finished) _process = null;
    }
  }

  bool _isRunActive(int generation) {
    return mounted && !_disposed && generation == _runGeneration;
  }

  Future<void> _waitForOutputDrain(
    Completer<void> stdoutDone,
    Completer<void> stderrDone,
  ) async {
    try {
      await Future.wait<void>(<Future<void>>[
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(_streamDrainTimeout);
    } on TimeoutException {
      // A descendant can inherit the pipes after the login process exits.
    } finally {
      await _cancelOutputSubscriptions();
    }
  }

  Future<void> _cancelOutputSubscriptions() async {
    final stdoutSubscription = _stdoutSubscription;
    final stderrSubscription = _stderrSubscription;
    _stdoutSubscription = null;
    _stderrSubscription = null;
    await Future.wait<bool>(<Future<bool>>[
      cancelStreamSubscriptionBounded<String>(
        stdoutSubscription,
        onError: (error, stack) =>
            silentLog('harness_cli_login_dialog', '取消标准输出订阅', error, stack),
      ),
      cancelStreamSubscriptionBounded<String>(
        stderrSubscription,
        onError: (error, stack) =>
            silentLog('harness_cli_login_dialog', '取消标准错误订阅', error, stack),
      ),
    ]);
  }

  Future<void> _shutdownProcess() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;
    final process = _process;
    _process = null;
    _noOutputTimer?.cancel();
    _noOutputTimer = null;

    late final Future<void> shutdown;
    shutdown =
        () async {
          await Future.wait<void>(<Future<void>>[
            _cancelOutputSubscriptions(),
            if (process != null) ...<Future<void>>[
              runAsyncCleanupBounded(
                process.stdin.close,
                onError: (error, stack) => silentLog(
                  'harness_cli_login_dialog',
                  '关闭登录进程标准输入',
                  error,
                  stack,
                ),
              ).then((_) {}),
              _terminateProcess(process, '终止登录进程'),
            ],
          ]);
        }().whenComplete(() {
          if (identical(_shutdownFuture, shutdown)) _shutdownFuture = null;
        });
    _shutdownFuture = shutdown;
    return shutdown;
  }

  Future<void> _terminateProcess(Process process, String action) async {
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: _processStopGracePeriod,
      );
    } catch (error, stack) {
      silentLog('harness_cli_login_dialog', action, error, stack);
    }
  }

  void _appendOutput(String chunk) {
    if (!mounted || _disposed) return;
    final normalized = stripHarnessCliTerminalSequences(
      chunk,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.isEmpty) return;

    _pendingOutput.append(normalized);
    _outputFlushTimer ??= startSafeTimer(
      kOpenHandFramePeriodicTimerInterval,
      _flushPendingOutput,
      onError: (error, stack) =>
          silentLog('harness_cli_login_dialog', '刷新登录输出', error, stack),
    );
  }

  void _flushPendingOutput() {
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    if (!mounted || _disposed || _pendingOutput.isEmpty) return;
    final pending = _pendingOutput.text;
    _pendingOutput.clear();
    setState(() {
      _outputBuffer.append(pending);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollGuard.followToBottom(_scrollController);
    });
  }

  Future<void> _sendLine() async {
    final process = _process;
    if (process == null || _finished) {
      return;
    }
    try {
      process.stdin.write('${_inputController.text}\n');
      await process.stdin.flush();
    } catch (_) {
      // stdin may already be closed if the process exited.
    }
    _inputController.clear();
  }

  Future<void> _sendControlCode(int codePoint) async {
    final process = _process;
    if (process == null || _finished) {
      return;
    }
    try {
      process.stdin.add(<int>[codePoint]);
      await process.stdin.flush();
    } catch (_) {
      // stdin may already be closed if the process exited.
    }
  }

  Future<void> _copyCommand() async {
    await copyOpenHandTextToClipboard(
      logTag: 'harness',
      context: context,
      text: _commandPreview,
      successMessage: _l10n.commonCopiedToClipboard,
      logAction: '复制登录命令',
    );
  }

  /// Opens the system terminal with the login command pre-injected.
  /// This is more reliable for CLIs requiring a real TTY (e.g. Claude Code).
  Future<void> _openInTerminal() async {
    try {
      if (Platform.isMacOS) {
        // Use osascript to open Terminal.app and run the login command.
        final escapedCmd = _commandPreview
            .replaceAll('\\', '\\\\')
            .replaceAll('"', '\\"');
        // safe_subprocess: hard timeout + child kill avoids leaking an
        // osascript that could disrupt the host app's input-method context
        // (observed previously as TextFields refusing input/paste).
        await runProcessWithTimeout('osascript', [
          '-e',
          'tell application "Terminal"',
          '-e',
          'activate',
          '-e',
          'do script "$escapedCmd"',
          '-e',
          'end tell',
        ], tag: 'harness_cli_login_dialog');
      } else if (Platform.isLinux) {
        // Try common terminal emulators.
        final terminals = ['gnome-terminal', 'xterm', 'konsole'];
        for (final term in terminals) {
          try {
            await startTrackedProcess(term, [
              '--',
              'bash',
              '-c',
              '$_commandPreview; exec bash',
            ], mode: ProcessStartMode.detached);
            break;
          } catch (_) {
            continue;
          }
        }
      } else if (Platform.isWindows) {
        await startTrackedProcess(
          'cmd',
          ['/c', 'start', 'cmd', '/k', _commandPreview],
          runInShell: true,
          mode: ProcessStartMode.detached,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _appendOutput('${_l10n.harnessCliLoginOpenTerminalError('$e')}\n');
    }
  }

  Future<void> _closeDialog() async {
    if (!_finished) unawaited(_shutdownProcess());
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final statusText = _errorMessage != null
        ? l10n.harnessCliLoginStatusFailed
        : _starting
        ? l10n.harnessCliLoginStatusStarting
        : _finished
        ? (_exitCode == null
              ? l10n.harnessCliLoginStatusFinished
              : l10n.harnessCliLoginStatusFinishedWithExit(_exitCode!))
        : l10n.harnessCliLoginStatusWaiting;

    return buildOpenHandAlertDialog(
      title: Text(l10n.harnessCliLoginTitle(_cli.name)),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.harnessCliLoginDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _commandPreview,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _copyCommand,
                          tooltip: l10n.harnessCliLoginCopyCommandTooltip,
                          icon: const Icon(
                            Icons.content_copy_rounded,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _errorMessage != null
                          ? Icons.error_outline_rounded
                          : _finished
                          ? Icons.check_circle_outline_rounded
                          : Icons.terminal_rounded,
                      size: 16,
                      color: _errorMessage != null
                          ? colorScheme.error
                          : _finished
                          ? Colors.green.shade600
                          : colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: _errorMessage != null
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    child: OpenHandSafeScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _scrollGuard.handleNotification,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(14),
                          child: SelectableText(
                            _errorMessage ??
                                (_output.isEmpty
                                    ? l10n.harnessCliLoginEmptyOutput
                                    : _output),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              height: 1.55,
                              color: _errorMessage != null
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        enabled:
                            !_starting && !_finished && _errorMessage == null,
                        onSubmitted: (_) => _sendLine(),
                        decoration: InputDecoration(
                          labelText: l10n.harnessCliLoginInputLabel,
                          hintText: l10n.harnessCliLoginInputHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed:
                          (!_starting && !_finished && _errorMessage == null)
                          ? _sendLine
                          : null,
                      icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                      label: Text(l10n.harnessCliLoginSend),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          (!_starting && !_finished && _errorMessage == null)
                          ? () => _sendControlCode(27)
                          : null,
                      icon: const Icon(Icons.keyboard_hide_rounded, size: 16),
                      label: Text(l10n.harnessCliLoginSendEsc),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          (!_starting && !_finished && _errorMessage == null)
                          ? () => _sendControlCode(3)
                          : null,
                      icon: const Icon(Icons.cancel_rounded, size: 16),
                      label: const Text('Ctrl+C'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openInTerminal,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(l10n.harnessCliLoginOpenInTerminal),
                    ),
                  ],
                ),
              ],
            ),
            FeedbackHighlightPulseOverlay(
              successSignal: _successPulse,
              errorSignal: _errorPulse,
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _closeDialog,
          label: l10n.commonClose,
        ),
      ],
    );
  }
}
