import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../service/hardness_cli_catalog.dart';

/// Shows a dialog that runs the CLI install command and streams output in real time.
/// Pops with `true` when installation succeeds, `false` otherwise.
class HardnessCliInstallDialog extends StatefulWidget {
  const HardnessCliInstallDialog({super.key, required this.cli});

  final HardnessCli cli;

  @override
  State<HardnessCliInstallDialog> createState() =>
      _HardnessCliInstallDialogState();
}

class _HardnessCliInstallDialogState extends State<HardnessCliInstallDialog> {
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
        'hardness_cli_install_dialog',
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
        _appendLine('✓ 安装成功');
      } else {
        _appendLine('✗ 安装失败（退出码：$exitCode）');
        _appendInstallHint(cmd[0], exitCode);
      }
    } on ProcessException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine('✗ 无法启动安装进程：${e.message}');
      _appendInstallHint(cmd[0], null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine('✗ 发生错误：$e');
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
      resolveHardnessCliShellExecutable(),
      buildHardnessCliShellArgs(cmdStr),
    );
  }

  void _appendInstallHint(String installer, int? exitCode) {
    if (installer == 'npm') {
      if (exitCode == 127 || exitCode == null) {
        _appendLine('  → 请先安装 Node.js：https://nodejs.org');
      } else if (_isPermissionError) {
        if (Platform.isMacOS) {
          _appendLine('  → 点击下方「以管理员权限重试」按钮');
        } else {
          _appendLine('  → 尝试：sudo ${widget.cli.installCommand!.join(' ')}');
        }
      } else {
        _appendLine('  → 请检查网络连接或查阅官方文档');
      }
    } else if (installer == 'pipx') {
      if (exitCode == 127 || exitCode == null) {
        _appendLine('  → 请先安装 pipx：https://pipx.pypa.io/stable/installation/');
        _appendLine('    或使用：pip install --user aider-chat');
      } else if (_isPermissionError) {
        if (Platform.isMacOS) {
          _appendLine('  → 点击下方「以管理员权限重试」按钮');
        } else {
          _appendLine('  → 尝试：sudo ${widget.cli.installCommand!.join(' ')}');
        }
      }
    } else if (installer == 'brew') {
      if (_isPermissionError) {
        _appendLine('  → Homebrew 通常不应以 sudo 安装，请检查目录权限');
        _appendLine(
          '  → 修复建议：https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed',
        );
      }
    } else if (installer == 'pip') {
      if (exitCode == null) {
        _appendLine('  → 请先安装 Python：https://www.python.org');
      } else if (_isPermissionError) {
        _appendLine(
          '  → 尝试：pip install --user ${widget.cli.installCommand!.last}',
        );
      }
    }
    if (widget.cli.installDocUrl != null) {
      _appendLine('  → 官方文档：${widget.cli.installDocUrl}');
    }
  }

  void _cancel() {
    if (!_running) return;
    try {
      _process?.kill();
    } catch (error, stack) {
      silentLog(
        'hardness_cli_install_dialog',
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
    _appendLine('⚠ 安装已被取消');
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
      _appendLine('请在管理员权限的 PowerShell 中手动执行：');
      _appendLine('  ${cmd.join(' ')}');
      return;
    }

    // ── Step 1: resolve full installer path via login shell ──────────────────
    String installerPath = cmd[0];
    try {
      final r = await runHardnessCliShellCommand(
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
        'hardness_cli_install_dialog',
        'resolve installer path via shell',
        error,
        stack,
      );
    }

    final shellCmdStr = ([
      installerPath,
      ...cmd.sublist(1),
    ]).map(_shellQuote).join(' ');
    _appendLine('> [管理员] $shellCmdStr');
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
          tag: 'hardness_cli_install_dialog',
        );

        if (!mounted || _cancelled) return;

        if (result == null) {
          // Timed out (child SIGKILLed) or failed to launch.
          setState(() {
            _running = false;
            _success = false;
          });
          _appendLine('✗ 管理员授权对话框超时或启动失败，已强制结束 osascript 子进程');
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
            _appendLine('⚠ 用户已取消授权');
          } else {
            setState(() {
              _running = false;
              _success = false;
            });
            _appendLine('✗ 无法获取管理员权限');
            if (stderr.isNotEmpty) _appendLine('  $stderr');
            if (widget.cli.installDocUrl != null) {
              _appendLine('  → 官方文档：${widget.cli.installDocUrl}');
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
            '✓ 安装成功（路径：${probe.resolvedPath ?? widget.cli.executable}）',
          );
        } else if (innerExitCode != null && innerExitCode != 0) {
          _appendLine('✗ 安装失败（退出码：$innerExitCode）');
          if (widget.cli.installDocUrl != null) {
            _appendLine('  → 官方文档：${widget.cli.installDocUrl}');
          }
        } else {
          // Installed but not yet on PATH — might need a new shell session.
          _appendLine('⚠ 安装完成，但未在当前 PATH 中检测到 ${widget.cli.executable}');
          _appendLine('  → 请尝试重新启动 OpenHand 或从终端启动以加载新 PATH');
          // Treat as success so the caller re-scans.
          if (mounted) setState(() => _success = true);
        }
      } on TimeoutException {
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine('✗ 安装超时（超过 5 分钟），请手动运行：');
        _appendLine('  sudo ${cmd.join(' ')}');
      } on ProcessException catch (e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine('✗ 无法启动 osascript：${e.message}');
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _success = false;
        });
        _appendLine('✗ 发生错误：$e');
      }
    } else {
      // Linux: no GUI sudo helper — show manual command to copy.
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('请在终端手动执行（需要 root 权限）：');
      _appendLine('  sudo ${cmd.join(' ')}');
      if (widget.cli.installDocUrl != null) {
        _appendLine('  → 官方文档：${widget.cli.installDocUrl}');
      }
    }
  }

  /// Single-quotes a shell argument, escaping embedded single quotes.
  String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
        ? (isZh ? '安装中...' : 'Installing...')
        : _success
        ? (isZh ? '安装成功' : 'Installed Successfully')
        : _cancelled
        ? (isZh ? '已取消' : 'Cancelled')
        : (isZh ? '安装失败' : 'Installation Failed');

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
          Expanded(
            child: Text(
              isZh ? '安装 ${widget.cli.name}' : 'Install ${widget.cli.name}',
            ),
          ),
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
                          isZh ? '复制文档链接' : 'Copy Doc URL',
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
            label: isZh ? '取消安装' : 'Cancel',
          )
        else ...[
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            label: isZh ? '关闭' : 'Close',
          ),
          // Show elevated-retry button when a permission error was detected
          // and we haven't already attempted an elevated install.
          if (!_success &&
              _isPermissionError &&
              !_elevatedRetryAttempted &&
              (Platform.isMacOS || Platform.isLinux))
            OpenHandDialogActionButton.destructive(
              onPressed: _retryWithAdminPrivileges,
              label: isZh ? '以管理员权限重试' : 'Retry with Admin',
            ),
          if (_success)
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(true),
              label: isZh ? '完成，继续' : 'Done',
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
