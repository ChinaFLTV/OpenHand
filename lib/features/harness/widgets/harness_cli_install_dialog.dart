import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../service/harness_cli_catalog.dart';

/// Shows a dialog that runs the CLI install command and streams output in real time.
/// Pops with `true` when installation succeeds, `false` otherwise.
class HarnessCliInstallDialog extends StatefulWidget {
  const HarnessCliInstallDialog({super.key, required this.cli});

  final HarnessCli cli;

  @override
  State<HarnessCliInstallDialog> createState() =>
      _HarnessCliInstallDialogState();
}

class _HarnessCliInstallDialogState extends State<HarnessCliInstallDialog> {
  final List<String> _logLines = [];
  bool _running = true;
  bool _success = false;
  bool _cancelled = false;
  // Set to true when EACCES / permission-denied is detected in the output.
  bool _isPermissionError = false;
  // Set to true after the user has tried the elevated retry once.
  bool _elevatedRetryAttempted = false;
  Process? _process;
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();

  /// Pulses the green top-edge confirmation flash on successful install.
  final ValueNotifier<int> _successPulse = ValueNotifier<int>(0);

  /// Pulses the red top-edge flash on install failure.
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  /// Tracks whether we've already pulsed for this run, so the periodic
  /// rebuilds from streaming log appends don't re-trigger.
  bool _pulsedOutcome = false;
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  void _pulseOutcome() {
    if (_pulsedOutcome) return;
    _pulsedOutcome = true;
    if (_success) {
      _successPulse.value = _successPulse.value + 1;
    } else if (!_cancelled) {
      _errorPulse.value = _errorPulse.value + 1;
    }
  }

  @override
  void initState() {
    super.initState();
    // Defer to next frame so the dialog is fully built before async work starts.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInstall());
  }

  @override
  void dispose() {
    try {
      _process?.kill();
    } catch (error, stack) {
      silentLog(
        'harness_cli_install_dialog',
        'kill process on dispose',
        error,
        stack,
      );
    }
    _scrollController.dispose();
    _successPulse.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  void _appendLine(String line) {
    if (!mounted) return;
    // Detect permission / EACCES errors so we can offer the elevated retry.
    if (!_isPermissionError) {
      final lower = line.toLowerCase();
      if (lower.contains('eacces') ||
          lower.contains('permission denied') ||
          lower.contains('errno: -13') ||
          lower.contains('access denied')) {
        _isPermissionError = true;
      }
    }
    setState(() => _logLines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollGuard.followToBottom(
        _scrollController,
        animated: true,
        animationDuration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _startInstall() async {
    final cmd = widget.cli.installCommand!;
    _appendLine('> ${cmd.join(' ')}');
    _appendLine('');

    try {
      final process = await _spawnProcess(cmd);
      _process = process;

      // Stream stdout and stderr concurrently.
      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine)
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine)
          .asFuture<void>();

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);

      if (!mounted || _cancelled) return;
      setState(() {
        _running = false;
        _success = exitCode == 0;
      });
      _appendLine('');
      if (_success) {
        _appendLine(_l10n.harnessCliInstallLogSuccess);
      } else {
        _appendLine(_l10n.harnessCliInstallLogFailureExitCode(exitCode));
        _appendInstallHint(cmd[0], exitCode);
      }
    } on ProcessException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine(_l10n.harnessCliInstallLogStartProcessFailed(e.message));
      _appendInstallHint(cmd[0], null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine(_l10n.harnessCliInstallLogGenericError('$e'));
    }
  }

  /// Spawns the install process.
  /// On macOS/Linux: wraps command in an interactive login shell so user-managed
  /// runtimes such as nvm / pyenv / conda match the orchestrator runtime.
  /// On Windows: runs directly with runInShell=true.
  Future<Process> _spawnProcess(List<String> cmd) async {
    if (Platform.isWindows) {
      return startTrackedProcess(cmd[0], cmd.sublist(1), runInShell: true);
    }
    // Single-quote each arg to prevent word splitting.
    final cmdStr = cmd.map(_shellQuote).join(' ');
    return startTrackedProcess(
      resolveHarnessCliShellExecutable(),
      buildHarnessCliShellArgs(cmdStr),
    );
  }

  void _appendInstallHint(String installer, int? exitCode) {
    final l10n = _l10n;
    final installCommand = widget.cli.installCommand!.join(' ');
    if (installer == 'npm') {
      if (exitCode == 127 || exitCode == null) {
        _appendLine(l10n.harnessCliInstallHintInstallNode);
      } else if (_isPermissionError) {
        if (Platform.isMacOS) {
          _appendLine(l10n.harnessCliInstallHintRetryAdminButton);
        } else {
          _appendLine(l10n.harnessCliInstallHintTrySudo(installCommand));
        }
      } else {
        _appendLine(l10n.harnessCliInstallHintCheckNetworkDocs);
      }
    } else if (installer == 'pipx') {
      if (exitCode == 127 || exitCode == null) {
        _appendLine(l10n.harnessCliInstallHintInstallPipx);
        _appendLine(l10n.harnessCliInstallHintUsePipInstallUserAider);
      } else if (_isPermissionError) {
        if (Platform.isMacOS) {
          _appendLine(l10n.harnessCliInstallHintRetryAdminButton);
        } else {
          _appendLine(l10n.harnessCliInstallHintTrySudo(installCommand));
        }
      }
    } else if (installer == 'brew') {
      if (_isPermissionError) {
        _appendLine(l10n.harnessCliInstallHintHomebrewNoSudo);
        _appendLine(l10n.harnessCliInstallHintHomebrewFix);
      }
    } else if (installer == 'pip') {
      if (exitCode == null) {
        _appendLine(l10n.harnessCliInstallHintInstallPython);
      } else if (_isPermissionError) {
        _appendLine(
          l10n.harnessCliInstallHintPipInstallUser(
            widget.cli.installCommand!.last,
          ),
        );
      }
    }
    if (widget.cli.installDocUrl != null) {
      _appendLine(
        l10n.harnessCliInstallHintOfficialDocs(widget.cli.installDocUrl!),
      );
    }
  }

  void _cancel() {
    if (!_running) return;
    try {
      _process?.kill();
    } catch (error, stack) {
      silentLog(
        'harness_cli_install_dialog',
        'kill process on cancel',
        error,
        stack,
      );
    }
    setState(() {
      _cancelled = true;
      _running = false;
    });
    _appendLine('');
    _appendLine(_l10n.harnessCliInstallLogCancelled);
  }

  // ── Elevated install (macOS: osascript; others: display manual command) ─────

  Future<void> _retryWithAdminPrivileges() async {
    setState(() {
      _running = true;
      _success = false;
      _isPermissionError = false;
      _elevatedRetryAttempted = true;
      _logLines.clear();
    });

    final cmd = widget.cli.installCommand!;

    if (!Platform.isMacOS && !Platform.isLinux) {
      // Windows: just show the manual command.
      setState(() => _running = false);
      _appendLine(_l10n.harnessCliInstallWindowsAdminManual);
      _appendLine('  ${cmd.join(' ')}');
      return;
    }

    // ── Step 1: resolve full installer path via login shell ──────────────────
    String installerPath = cmd[0];
    try {
      final r = await runHarnessCliShellCommand(
        'command -v ${_shellQuote(cmd[0])}',
        timeout: const Duration(seconds: 5),
      );
      if (r.exitCode == 0) {
        final lines = '${r.stdout}'
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        if (lines.isNotEmpty) {
          installerPath = lines.last;
        }
      }
    } catch (error, stack) {
      silentLog(
        'harness_cli_install_dialog',
        'resolve installer path via shell',
        error,
        stack,
      );
    }

    final shellCmdStr = ([
      installerPath,
      ...cmd.sublist(1),
    ]).map(_shellQuote).join(' ');
    _appendLine(_l10n.harnessCliInstallAdminCommand(shellCmdStr));
    _appendLine('');

    if (Platform.isMacOS) {
      // ── macOS: AppleScript do shell script with administrator privileges ────
      // Append '; echo __EC__:$?' so the outer shell always exits 0
      // (otherwise AppleScript propagates the inner exit code as an error,
      // which prevents us from reading the captured output).
      final escapedCmd = shellCmdStr
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"');
      // \$? → literal $? at runtime (Dart escapes $ to prevent interpolation)
      // Note: '2>&1' must not be split; keep it as a raw string fragment.
      final appleScript =
          'do shell script "$escapedCmd 2>&'
          '1; echo __EC__:\$?" '
          'with administrator privileges';

      try {
        // Use the safe subprocess wrapper: `Process.run(...).timeout(...)`
        // is a TRAP — Future.timeout only abandons the Dart future while the
        // underlying osascript child keeps running and continues sending
        // Apple Events to other GUI apps. On macOS this corrupts the host
        // process's IMK input context, observed as "every TextField in the
        // app silently refuses input/paste" plus
        // `error messaging the mach port for IMKCFRunLoopWakeUpReliable`
        // console spam. The wrapper does Process.start + concurrent stdio
        // drain + hard SIGKILL on timeout so the child cannot leak.
        // Timeout is generous because `with administrator privileges` opens
        // the system auth prompt which the user may take a while to answer.
        final result = await runProcessWithTimeout(
          'osascript',
          ['-e', appleScript],
          timeout: const Duration(minutes: 5),
          tag: 'harness_cli_install_dialog',
        );

        if (!mounted || _cancelled) return;

        if (result == null) {
          // Timed out (child SIGKILLed) or failed to launch.
          setState(() {
            _running = false;
            _success = false;
          });
          _appendLine(_l10n.harnessCliInstallAdminTimeout);
          return;
        }

        final stdout = result.stdout as String;
        final stderr = (result.stderr as String).trim();

        if (result.exitCode != 0) {
          // osascript itself failed — most likely user cancelled the auth dialog.
          final lower = stderr.toLowerCase();
          if (lower.contains('user cancel') || lower.contains('user-cancel')) {
            setState(() {
              _running = false;
              _cancelled = true;
            });
            _appendLine(_l10n.harnessCliInstallUserCancelledAuth);
          } else {
            setState(() {
              _running = false;
              _success = false;
            });
            _appendLine(_l10n.harnessCliInstallAdminPermissionFailed);
            if (stderr.isNotEmpty) _appendLine('  $stderr');
            if (widget.cli.installDocUrl != null) {
              _appendLine(
                _l10n.harnessCliInstallHintOfficialDocs(
                  widget.cli.installDocUrl!,
                ),
              );
            }
          }
          return;
        }

        // Parse inner exit code and log output (strip the __EC__: marker line).
        int? innerExitCode;
        for (final line in stdout.split('\n')) {
          final m = RegExp(r'^__EC__:(\d+)$').firstMatch(line.trim());
          if (m != null) {
            innerExitCode = int.tryParse(m.group(1)!);
          } else if (line.isNotEmpty) {
            _appendLine(line);
          }
        }
        _appendLine('');

        // Re-probe to confirm the binary is now reachable in the login shell.
        final probe = await probeCliInstallation(widget.cli);
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = probe.installed;
        });

        if (probe.installed) {
          _appendLine(
            _l10n.harnessCliInstallLogSuccessWithPath(
              probe.resolvedPath ?? widget.cli.executable,
            ),
          );
        } else if (innerExitCode != null && innerExitCode != 0) {
          _appendLine(_l10n.harnessCliInstallLogFailureExitCode(innerExitCode));
          if (widget.cli.installDocUrl != null) {
            _appendLine(
              _l10n.harnessCliInstallHintOfficialDocs(
                widget.cli.installDocUrl!,
              ),
            );
          }
        } else {
          // Installed but not yet on PATH — might need a new shell session.
          _appendLine(
            _l10n.harnessCliInstallPathMissingWarning(widget.cli.executable),
          );
          _appendLine(_l10n.harnessCliInstallRestartPathHint);
          // Treat as success so the caller re-scans.
          if (mounted) setState(() => _success = true);
        }
      } on TimeoutException {
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine(_l10n.harnessCliInstallTimeoutManual);
        _appendLine('  sudo ${cmd.join(' ')}');
      } on ProcessException catch (e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine(_l10n.harnessCliInstallOsascriptStartFailed(e.message));
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine(_l10n.harnessCliInstallLogGenericError('$e'));
      }
    } else {
      // Linux: no GUI sudo helper — show manual command to copy.
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine(_l10n.harnessCliInstallLinuxSudoManual);
      _appendLine('  sudo ${cmd.join(' ')}');
      if (widget.cli.installDocUrl != null) {
        _appendLine(
          _l10n.harnessCliInstallHintOfficialDocs(widget.cli.installDocUrl!),
        );
      }
    }
  }

  /// Single-quotes a shell argument, escaping embedded single quotes.
  String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final statusColor = _running
        ? colorScheme.primary
        : _success
        ? const Color(0xFF4CAF50)
        : colorScheme.error;

    final statusIcon = _running
        ? Icons.downloading_rounded
        : _success
        ? Icons.check_circle_rounded
        : (_cancelled ? Icons.cancel_rounded : Icons.error_rounded);

    final statusLabel = _running
        ? l10n.harnessCliInstallStatusInstalling
        : _success
        ? l10n.harnessCliInstallStatusSuccess
        : _cancelled
        ? l10n.harnessCliInstallStatusCancelled
        : l10n.harnessCliInstallStatusFailed;

    if (!_running) {
      // Defer to next frame so the pulse fires after the build is committed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pulseOutcome();
      });
    }

    return buildOpenHandAlertDialog(
      title: Row(
        children: [
          Icon(Icons.download_rounded, size: 22, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.harnessCliInstallTitle(widget.cli.name))),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status row
                Row(
                  children: [
                    if (_running)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    else
                      Icon(statusIcon, size: 18, color: statusColor),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: statusColor,
                      ),
                    ),
                    const Spacer(),
                    if (widget.cli.installDocUrl != null)
                      // Copy doc URL to clipboard
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: widget.cli.installDocUrl!),
                        ),
                        icon: const Icon(Icons.link_rounded, size: 14),
                        label: Text(
                          l10n.harnessCliInstallCopyDocUrl,
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Log output area
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(8),
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
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _logLines.length,
                          itemBuilder: (context, index) {
                            return _LogLine(line: _logLines[index]);
                          },
                        ),
                      ),
                    ),
                  ),
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
        if (_running)
          OpenHandDialogActionButton.destructive(
            onPressed: _cancel,
            label: l10n.harnessCliInstallCancel,
          )
        else ...[
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            label: l10n.commonClose,
          ),
          // Show elevated-retry button when a permission error was detected
          // and we haven't already attempted an elevated install.
          if (!_success &&
              _isPermissionError &&
              !_elevatedRetryAttempted &&
              (Platform.isMacOS || Platform.isLinux))
            OpenHandDialogActionButton.destructive(
              onPressed: _retryWithAdminPrivileges,
              label: l10n.harnessCliInstallRetryAdmin,
            ),
          if (_success)
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(true),
              label: l10n.harnessCliInstallDoneContinue,
            ),
        ],
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final color = _colorForLine(line);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SelectableText(
        line.isEmpty ? ' ' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: color,
          height: 1.5,
        ),
      ),
    );
  }

  static Color _colorForLine(String line) {
    final lower = line.toLowerCase();
    if (line.startsWith('✓') || line.startsWith('>')) {
      return const Color(0xFF4CAF50);
    }
    if (line.startsWith('✗') ||
        lower.startsWith('error') ||
        lower.startsWith('err ') ||
        lower.contains(' error:')) {
      return const Color(0xFFEF5350);
    }
    if (line.startsWith('⚠') ||
        lower.startsWith('warn') ||
        lower.startsWith('warning')) {
      return const Color(0xFFFFA726);
    }
    if (line.startsWith('  →')) {
      return const Color(0xFF64B5F6);
    }
    return const Color(0xFFCDD9E5);
  }
}
