import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/openhand_dialog_action_button.dart';
import 'hardness_cli_catalog.dart';

class HardnessCliLoginDialog extends StatefulWidget {
  const HardnessCliLoginDialog({super.key, required this.entry});

  final CliScanEntry entry;

  @override
  State<HardnessCliLoginDialog> createState() => _HardnessCliLoginDialogState();
}

class _HardnessCliLoginDialogState extends State<HardnessCliLoginDialog> {
  static const int _maxBufferedChars = 120000;

  final ScrollController _scrollController = ScrollController();
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

  HardnessCli get _cli => widget.entry.cli;
  String get _executable => widget.entry.resolvedPath ?? _cli.executable;
  List<String> get _loginArgs => _cli.loginArgs ?? const <String>[];
  String get _commandPreview =>
      formatHardnessCliCommandPreview(_executable, _loginArgs);

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
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
    }
    super.dispose();
  }

  Future<void> _startInteractiveLogin() async {
    try {
      final process = await startHardnessCliInteractiveProcess(
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
        _appendOutput('[stream error: $error]\n');
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
      _noOutputTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted || _output.isNotEmpty || _finished) return;
        _appendOutput(
          '[提示] CLI 尚未产生输出。可能正在初始化，或需要在外部浏览器中完成授权。\n'
          '[Hint] CLI has not produced output yet. It may be initialising, '
          'or waiting for browser-based authorisation.\n',
        );
      });

      final exitCode = await process.exitCode;
      _noOutputTimer?.cancel();
      if (!mounted) return;

      // If the process exited almost instantly with no output, it likely
      // crashed or was misconfigured.  Run diagnostics and display them.
      if (_output.isEmpty && exitCode != 0) {
        final diags = await collectHardnessCliFailureDiagnostics(_executable);
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
        _appendOutput(
          '[提示] 该 CLI 可能需要真实终端 (TTY) 才能完成交互式登录。\n'
          '请点击下方「在终端中打开」按钮，在系统终端中完成登录流程。\n'
          '[Hint] This CLI may require a real terminal (TTY) for interactive login.\n'
          'Use the "Open in Terminal" button below to complete login in the system terminal.\n',
        );
      }

      if (!mounted) return;
      setState(() {
        _finished = true;
        _exitCode = exitCode;
      });
    } on ProcessException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = '无法启动进程 / Failed to start process: ${error.message}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _starting = false;
        _finished = true;
        _errorMessage = '$error';
      });
    }
  }

  void _appendOutput(String chunk) {
    final normalized = stripHardnessCliTerminalSequences(
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
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
    await Clipboard.setData(ClipboardData(text: _commandPreview));
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
        await Process.run('osascript', [
          '-e',
          'tell application "Terminal"',
          '-e',
          'activate',
          '-e',
          'do script "$escapedCmd"',
          '-e',
          'end tell',
        ]);
      } else if (Platform.isLinux) {
        // Try common terminal emulators.
        final terminals = ['gnome-terminal', 'xterm', 'konsole'];
        for (final term in terminals) {
          try {
            await Process.start(term, ['--', 'bash', '-c', '$_commandPreview; exec bash']);
            break;
          } catch (_) {
            continue;
          }
        }
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'cmd', '/k', _commandPreview], runInShell: true);
      }
    } catch (e) {
      if (!mounted) return;
      _appendOutput('[Error opening terminal: $e]\n');
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final statusText = _errorMessage != null
        ? (isZh ? '启动失败' : 'Failed to launch')
        : _starting
        ? (isZh ? '正在启动登录流程...' : 'Starting login flow...')
        : _finished
        ? (isZh
              ? '流程已结束${_exitCode != null ? ' · 退出码 $_exitCode' : ''}'
              : 'Process finished${_exitCode != null ? ' · exit $_exitCode' : ''}')
        : (isZh ? '等待 CLI 交互...' : 'Waiting for CLI interaction...');

    return AlertDialog(
      title: Text(isZh ? '${_cli.name} 登录' : '${_cli.name} Login'),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isZh
                  ? '该弹窗会在应用内启动交互式 CLI 登录流程。过程中 CLI 可能会自动打开外部浏览器，请根据提示完成授权。'
                  : 'This dialog runs the CLI login flow in-app. The CLI may open your browser externally during authentication.',
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
                      tooltip: isZh ? '复制命令' : 'Copy command',
                      icon: const Icon(Icons.content_copy_rounded, size: 18),
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
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(
                      _errorMessage ??
                          (_output.isEmpty
                              ? (isZh
                                    ? '等待 CLI 输出...'
                                    : 'Waiting for CLI output...')
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: !_starting && !_finished && _errorMessage == null,
                    onSubmitted: (_) => _sendLine(),
                    decoration: InputDecoration(
                      labelText: isZh ? '发送输入' : 'Send input',
                      hintText: isZh
                          ? '输入内容后回车；留空可直接发送回车'
                          : 'Type a reply and press Enter; leave empty to send Enter',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: (!_starting && !_finished && _errorMessage == null)
                      ? _sendLine
                      : null,
                  icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                  label: Text(isZh ? '发送' : 'Send'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: (!_starting && !_finished && _errorMessage == null)
                      ? () => _sendControlCode(27)
                      : null,
                  icon: const Icon(Icons.keyboard_hide_rounded, size: 16),
                  label: Text(isZh ? '发送 Esc' : 'Send Esc'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_starting && !_finished && _errorMessage == null)
                      ? () => _sendControlCode(3)
                      : null,
                  icon: const Icon(Icons.cancel_rounded, size: 16),
                  label: const Text('Ctrl+C'),
                ),
                OutlinedButton.icon(
                  onPressed: _openInTerminal,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(isZh ? '在终端中打开' : 'Open in Terminal'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _closeDialog,
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }
}
