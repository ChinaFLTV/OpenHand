import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/util/timer_safety.dart';
import '../service/harness_cli_catalog.dart';
import 'harness_dialog_utils.dart';

class HarnessCliLoginDialog extends StatefulWidget {
  const HarnessCliLoginDialog({super.key, required this.entry});

  final CliScanEntry entry;

  @override
  State<HarnessCliLoginDialog> createState() => _HarnessCliLoginDialogState();
}

class _HarnessCliLoginDialogState extends State<HarnessCliLoginDialog> {
  static const int _maxBufferedChars = 120000;
  static const Duration _noOutputHintDelay = Duration(seconds: 8);

  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final TextEditingController _inputController = TextEditingController();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _noOutputTimer;
  bool _starting = true;
  bool _finished = false;
  int? _exitCode;
  String? _errorMessage;
  String _output = '';

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
    _noOutputTimer?.cancel();
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _successPulse.dispose();
    _errorPulse.dispose();
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
    }
    super.dispose();
  }

  Future<void> _startInteractiveLogin() async {
    try {
      final process = await startHarnessCliInteractiveProcess(
        executable: _executable,
        args: _loginArgs,
      );
      if (!mounted) {
        process.kill();
        return;
      }

      _process = process;

      void onStreamError(Object error) {
        if (!mounted) return;
        _appendOutput('${_l10n.harnessCliLoginStreamError('$error')}\n');
      }

      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_appendOutput, onError: onStreamError);
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_appendOutput, onError: onStreamError);

      setState(() {
        _starting = false;
      });

      // Watchdog: if no output arrives within 8 seconds, show a diagnostic
      // hint so the user is not left staring at a blank screen.
      _noOutputTimer = startSafeTimer(_noOutputHintDelay, () {
        if (!mounted || _output.isNotEmpty || _finished) return;
        _appendOutput(_l10n.harnessCliLoginNoOutputHint);
      });

      final exitCode = await process.exitCode;
      _noOutputTimer?.cancel();
      if (!mounted) return;

      // If the process exited almost instantly with no output, it likely
      // crashed or was misconfigured.  Run diagnostics and display them.
      if (_output.isEmpty && exitCode != 0) {
        final diags = await collectHarnessCliFailureDiagnostics(_executable);
        if (diags.isNotEmpty && mounted) {
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

      if (!mounted) return;
      setState(() {
        _finished = true;
        _exitCode = exitCode;
      });
      if (exitCode == 0) {
        _successPulse.value = _successPulse.value + 1;
      } else {
        _errorPulse.value = _errorPulse.value + 1;
      }
    } on ProcessException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = _l10n.harnessCliLoginFailedToStartProcess(
          error.message,
        );
      });
      _errorPulse.value = _errorPulse.value + 1;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = '$error';
      });
      _errorPulse.value = _errorPulse.value + 1;
    }
  }

  void _appendOutput(String chunk) {
    final normalized = stripHarnessCliTerminalSequences(
      chunk,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.isEmpty) {
      return;
    }

    final nextOutput = _truncateOutput('$_output$normalized');
    if (!mounted) {
      _output = nextOutput;
      return;
    }

    setState(() {
      _output = nextOutput;
    });
    _scrollToBottom();
  }

  String _truncateOutput(String value) {
    if (value.length <= _maxBufferedChars) {
      return value;
    }
    return value.substring(value.length - _maxBufferedChars);
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
    await copyHarnessTextToClipboard(
      context: context,
      text: _commandPreview,
      successMessage: _l10n.commonCopiedToClipboard,
      logAction: 'copy login command',
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
            ]);
            break;
          } catch (_) {
            continue;
          }
        }
      } else if (Platform.isWindows) {
        await startTrackedProcess('cmd', [
          '/c',
          'start',
          'cmd',
          '/k',
          _commandPreview,
        ], runInShell: true);
      }
    } catch (e) {
      if (!mounted) return;
      _appendOutput('${_l10n.harnessCliLoginOpenTerminalError('$e')}\n');
    }
  }

  Future<void> _closeDialog() async {
    final process = _process;
    _process = null;
    if (process != null && !_finished) {
      process.kill();
    }
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _successPulse,
                  color: OpenHandStatusColors.success,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _errorPulse,
                  color: OpenHandStatusColors.error,
                ),
              ),
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
