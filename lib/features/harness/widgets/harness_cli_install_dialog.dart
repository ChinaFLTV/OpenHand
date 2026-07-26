import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/buffered_console_log.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_console_log_view.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../service/harness_cli_catalog.dart';

/// 执行 CLI 安装命令并实时展示输出；安装成功时返回 `true`。
class HarnessCliInstallDialog extends StatefulWidget {
  const HarnessCliInstallDialog({super.key, required this.cli});

  final HarnessCli cli;

  @override
  State<HarnessCliInstallDialog> createState() =>
      _HarnessCliInstallDialogState();
}

class _HarnessCliInstallDialogState extends State<HarnessCliInstallDialog>
    with BufferedConsoleLogHost<HarnessCliInstallDialog> {
  @override
  String get consoleLogTag => 'harness_cli_install_dialog';

  @override
  Duration get consoleFollowDuration => const Duration(milliseconds: 100);

  static const Duration _installTimeout = Duration(minutes: 5);
  bool _running = true;
  bool _success = false;
  bool _cancelled = false;
  bool _isPermissionError = false;
  bool _elevatedRetryAttempted = false;
  final TrackedProcessSlot _processSlot = TrackedProcessSlot(
    logTag: 'harness_cli_install_dialog',
  );
  bool _disposed = false;

  final ValueNotifier<int> _successPulse = ValueNotifier<int>(0);
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

  /// 防止日志流触发的重建重复播放结果反馈。
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
    // 等弹窗首帧完成后再启动异步安装。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _startInstall();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _processSlot.abort('释放安装进程');
    _successPulse.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  void _appendLine(String line) {
    if (_disposed) return;
    if (!_isPermissionError) {
      final lower = line.toLowerCase();
      if (lower.contains('eacces') ||
          lower.contains('permission denied') ||
          lower.contains('errno: -13') ||
          lower.contains('access denied')) {
        _isPermissionError = true;
      }
    }
    appendConsoleLine(line);
  }

  bool _isRunActive(int generation) {
    return mounted &&
        !_disposed &&
        !_cancelled &&
        _processSlot.isCurrent(generation);
  }

  Future<void> _startInstall() async {
    final cmd = widget.cli.installCommand!;
    final generation = _processSlot.beginRun();
    _appendLine('> ${cmd.join(' ')}');
    _appendLine('');

    Process? startedProcess;
    try {
      final launch = _buildInstallLaunch(cmd);
      final result = await runTrackedProcessWithLineLogging(
        launch.executable,
        launch.arguments,
        timeout: _installTimeout,
        tag: 'harness_cli_install_dialog',
        runInShell: launch.runInShell,
        onStdoutLine: _appendLine,
        onStderrLine: _appendLine,
        onProcessStarted: (process) {
          startedProcess = process;
          _processSlot.claim(process, generation, staleAction: '终止迟到的安装进程');
        },
      );

      if (!_isRunActive(generation)) return;
      setState(() {
        _running = false;
        _success = !result.timedOut && result.exitCode == 0;
      });
      _appendLine('');
      if (result.timedOut) {
        _appendLine(_l10n.harnessCliInstallTimeoutManual);
        _appendLine('  ${cmd.join(' ')}');
      } else if (_success) {
        _appendLine(_l10n.harnessCliInstallLogSuccess);
      } else {
        _appendLine(_l10n.harnessCliInstallLogFailureExitCode(result.exitCode));
        _appendInstallHint(cmd[0], result.exitCode);
      }
    } on ProcessException catch (e) {
      if (!_isRunActive(generation)) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine(_l10n.harnessCliInstallLogStartProcessFailed(e.message));
      _appendInstallHint(cmd[0], null);
    } catch (e) {
      if (!_isRunActive(generation)) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine(_l10n.harnessCliInstallLogGenericError('$e'));
    } finally {
      _processSlot.release(startedProcess);
    }
  }

  /// macOS/Linux 使用交互式登录 Shell，确保能找到 nvm、pyenv、conda 等运行时。
  /// Windows 直接通过系统 Shell 执行。
  ({String executable, List<String> arguments, bool runInShell})
  _buildInstallLaunch(List<String> cmd) {
    if (Platform.isWindows) {
      return (executable: cmd[0], arguments: cmd.sublist(1), runInShell: true);
    }
    final cmdStr = cmd.map(_shellQuote).join(' ');
    return (
      executable: resolveHarnessCliShellExecutable(),
      arguments: buildHarnessCliShellArgs(cmdStr),
      runInShell: false,
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
    _processSlot.abort('取消安装进程');
    setState(() {
      _cancelled = true;
      _running = false;
    });
    _appendLine('');
    _appendLine(_l10n.harnessCliInstallLogCancelled);
  }

  // 提权安装：macOS 使用 osascript，其它平台展示手工命令。

  Future<void> _retryWithAdminPrivileges() async {
    final generation = _processSlot.beginRun();
    setState(() {
      resetConsoleLog();
      _running = true;
      _success = false;
      _cancelled = false;
      _isPermissionError = false;
      _elevatedRetryAttempted = true;
      _pulsedOutcome = false;
    });

    final cmd = widget.cli.installCommand!;

    if (!Platform.isMacOS && !Platform.isLinux) {
      setState(() => _running = false);
      _appendLine(_l10n.harnessCliInstallWindowsAdminManual);
      _appendLine('  ${cmd.join(' ')}');
      return;
    }

    // 先通过登录 Shell 解析安装器的完整路径。
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
      silentLog('harness_cli_install_dialog', '通过 Shell 解析安装器路径', error, stack);
    }
    if (!_isRunActive(generation)) return;

    final shellCmdStr = ([
      installerPath,
      ...cmd.sublist(1),
    ]).map(_shellQuote).join(' ');
    _appendLine(_l10n.harnessCliInstallAdminCommand(shellCmdStr));
    _appendLine('');

    if (Platform.isMacOS) {
      // 让外层 Shell 固定成功退出，避免 AppleScript 丢弃内部命令输出。
      final escapedCmd = shellCmdStr
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"');
      // `\$?` 在运行时还原为 `$?`；`2>&1` 必须保持为完整片段。
      final appleScript =
          'do shell script "$escapedCmd 2>&'
          '1; echo __EC__:\$?" '
          'with administrator privileges';

      Process? startedProcess;
      try {
        // Future.timeout 不会终止 osascript，泄漏的 Apple Events 会破坏 macOS
        // 输入法上下文。安全进程封装会并发排空输出，并在超时后强制终止子进程。
        // 授权弹窗可能等待用户操作，因此沿用完整安装超时。
        final result = await runProcessWithTimeout(
          'osascript',
          ['-e', appleScript],
          timeout: _installTimeout,
          tag: 'harness_cli_install_dialog',
          onProcessStarted: (process) {
            startedProcess = process;
            _processSlot.claim(process, generation, staleAction: '终止迟到的安装进程');
          },
        );

        if (!_isRunActive(generation)) return;

        if (result == null) {
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
          // osascript 自身失败时优先识别用户取消授权。
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

        // 提取内部退出码，标记行不进入用户日志。
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

        final probe = await probeCliInstallation(widget.cli);
        if (!_isRunActive(generation)) return;
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
          // 已安装但当前 PATH 尚未刷新；按成功返回，让调用方重新扫描。
          _appendLine(
            _l10n.harnessCliInstallPathMissingWarning(widget.cli.executable),
          );
          _appendLine(_l10n.harnessCliInstallRestartPathHint);
          if (mounted) setState(() => _success = true);
        }
      } on TimeoutException {
        if (!_isRunActive(generation)) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine(_l10n.harnessCliInstallTimeoutManual);
        _appendLine('  sudo ${cmd.join(' ')}');
      } on ProcessException catch (e) {
        if (!_isRunActive(generation)) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine(_l10n.harnessCliInstallOsascriptStartFailed(e.message));
      } catch (e) {
        if (!_isRunActive(generation)) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine(_l10n.harnessCliInstallLogGenericError('$e'));
      } finally {
        _processSlot.release(startedProcess);
      }
    } else {
      // Linux 没有统一的图形化提权入口，改为展示可复制的手工命令。
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

  /// 使用单引号安全包裹 Shell 参数。
  String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final statusColor = _running
        ? colorScheme.primary
        : _success
        ? OpenHandStatusColors.success
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
      // 等当前构建提交后再播放结果反馈。
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
                Row(
                  children: [
                    OpenHandBusyStatusIcon(
                      busy: _running,
                      icon: statusIcon,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: statusColor,
                      ),
                    ),
                    const Spacer(),
                    if (widget.cli.installDocUrl != null)
                      TextButton.icon(
                        onPressed: () async {
                          await copyOpenHandTextToClipboard(
                            logTag: 'harness',
                            context: context,
                            text: widget.cli.installDocUrl!,
                            successMessage: l10n.commonCopiedToClipboard,
                            logAction: '复制安装文档地址',
                          );
                        },
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
                Expanded(
                  child: OpenHandConsoleLogView(
                    controller: logScrollController,
                    onNotification: logScrollGuard.handleNotification,
                    itemCount: logLines.length,
                    itemBuilder: (_, index) => _LogLine(line: logLines[index]),
                  ),
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
          fontFamily: kOpenHandMonospaceFontFamily,
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
      return OpenHandStatusColors.success;
    }
    if (line.startsWith('✗') ||
        lower.startsWith('error') ||
        lower.startsWith('err ') ||
        lower.contains(' error:')) {
      return OpenHandStatusColors.error;
    }
    if (line.startsWith('⚠') ||
        lower.startsWith('warn') ||
        lower.startsWith('warning')) {
      return OpenHandStatusColors.warning;
    }
    if (line.startsWith('  →')) {
      return const Color(0xFF64B5F6);
    }
    return const Color(0xFFCDD9E5);
  }
}
