import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/silent_log.dart';
import '../model/ai_deny_command_rule.dart';
import '../service/ai_bash_tool_service.dart';
import '../service/ai_sandbox_proxy_service.dart';
import '../service/ai_sandbox_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 长跑后台 Shell 工具。把 `Process.start` 启动的常驻进程拆解为 5 个 action：
/// `start` / `write` / `read` / `stop` / `list`。
///
/// 用途：跑 dev server / REPL / 长任务等阻塞型命令，主 Bash 工具受单次超时
/// 限制无法承载。每个 handle 持有独立 Process + 64 KB 滚动输出缓冲；
/// 工具实例销毁（[dispose]）时统一 SIGKILL。
///
/// 设计原则：
/// - 出于安全考虑，仍受 [AiToolExecutionContext.denyCommandRules] 制约。
/// - read 是非阻塞拉取（自上次 read 以来的新输出 + 进程状态）。
/// - stdin 写入仅在进程存活时有效；进程已退出时返回 invalid_arguments。
class AiBashBackgroundTool extends AiTool {
  AiBashBackgroundTool({AiSandboxService? sandboxService})
    : _sandboxService = sandboxService ?? AiSandboxService();

  static const int _maxBufferBytes = 64 * 1024;
  static const int _maxConcurrentSessions = 8;

  final Map<String, _BgSession> _sessions = <String, _BgSession>{};
  final AiSandboxService _sandboxService;
  int _handleCounter = 0;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.bashBackground;

  @override
  bool get isDestructive => true;

  // 用户取消时不强杀后台进程，只取消当前 read 等待；后台进程靠 stop action 清理。
  @override
  AiToolInterruptBehavior get interruptBehavior =>
      AiToolInterruptBehavior.cancel;

  void dispose() {
    for (final session in _sessions.values) {
      try {
        session.process.kill(ProcessSignal.sigkill);
      } catch (error, stack) {
        silentLog(
          'ai_bash_background',
          'kill session ${session.handle}',
          error,
          stack,
        );
      }
      unawaited(session.closeProxy());
    }
    _sessions.clear();
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final action = '${args['action'] ?? ''}'.trim().toLowerCase();
    if (action.isEmpty) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'BashBackground requires an action: start | write | read | stop | list.',
      );
    }
    switch (action) {
      case 'start':
        return _start(context, args);
      case 'write':
        return _write(args);
      case 'read':
        return _read(args, context.cancelSignal);
      case 'stop':
        return _stop(args);
      case 'list':
        return _list();
      default:
        return AiToolUtils.invalidResult(
          'BashBackground',
          'Unsupported action "$action". Use: start | write | read | stop | list.',
        );
    }
  }

  Future<AiToolExecutionResult> _start(
    AiToolExecutionContext context,
    Map<String, Object?> args,
  ) async {
    final cmd = '${args['cmd'] ?? args['command'] ?? ''}'.trim();
    if (cmd.isEmpty) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'start requires non-empty cmd.',
      );
    }
    if (_sessions.length >= _maxConcurrentSessions) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Too many active background sessions ($_maxConcurrentSessions). Stop one first.',
      );
    }
    final denyRule = _matchDenyRule(cmd, context.denyCommandRules);
    if (denyRule != null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.denied,
        command: cmd,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'Command denied by deny rule: ${denyRule.pattern}',
        durationMs: 0,
        matchedRuleId: denyRule.id,
        matchedRulePattern: denyRule.pattern,
        resultText:
            'status: denied\nrule: ${denyRule.pattern}\nreason: matched deny rule',
      );
    }
    final cwd = AiToolUtils.resolvePath(
      '${args['working_directory'] ?? args['cwd'] ?? ''}',
    );
    final launchSpec = await _prepareLaunchSpec(cmd: cmd, cwd: cwd);
    if (launchSpec.blocked) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.denied,
        command: cmd,
        workingDirectory: cwd,
        stdout: '',
        stderr: launchSpec.reason,
        durationMs: 0,
        resultText: 'status: denied\nreason: ${launchSpec.reason}',
        metadata: launchSpec.metadata,
      );
    }
    final startedAt = Stopwatch()..start();
    final Process process;
    try {
      process = await Process.start(
        launchSpec.executable,
        launchSpec.arguments,
        workingDirectory: launchSpec.workingDirectory,
        environment: launchSpec.environment.isEmpty
            ? null
            : launchSpec.environment,
      );
    } catch (error, stack) {
      await launchSpec.proxyLease?.close();
      silentLog('ai_bash_background', 'spawn $cmd', error, stack);
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Failed to spawn process: $error',
      );
    }
    _handleCounter += 1;
    final handle = 'bg_$_handleCounter';
    final session = _BgSession(
      handle: handle,
      command: cmd,
      workingDirectory: launchSpec.workingDirectory,
      process: process,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
      proxyLease: launchSpec.proxyLease,
    );
    _sessions[handle] = session;
    process.stdout
        .transform(utf8.decoder)
        .listen(
          (data) => session.appendStdout(data, _maxBufferBytes),
          onError: (Object error, StackTrace stack) {
            silentLog('ai_bash_background', 'stdout $handle', error, stack);
          },
        );
    process.stderr
        .transform(utf8.decoder)
        .listen(
          (data) => session.appendStderr(data, _maxBufferBytes),
          onError: (Object error, StackTrace stack) {
            silentLog('ai_bash_background', 'stderr $handle', error, stack);
          },
        );
    unawaited(
      process.exitCode.then((code) {
        session.exitCode = code;
        session.alive = false;
        unawaited(session.closeProxy());
      }),
    );
    final output = StringBuffer()
      ..writeln('status: started')
      ..writeln('handle: $handle')
      ..writeln('pid: ${process.pid}')
      ..writeln('cwd: ${launchSpec.workingDirectory}')
      ..writeln('cmd: $cmd');
    if (launchSpec.applied) {
      output
        ..writeln('sandbox: applied')
        ..writeln(
          'sandbox_backend: ${launchSpec.metadata['sandbox_backend'] ?? ''}',
        );
    }
    if (launchSpec.metadata['sandbox_proxy_enabled'] == true) {
      output.writeln(
        'sandbox_proxy: http=${launchSpec.metadata['sandbox_proxy_http_port'] ?? ''}'
        '${launchSpec.metadata['sandbox_proxy_socks_port'] == null ? '' : ', socks=${launchSpec.metadata['sandbox_proxy_socks_port']}'}',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'BashBackground start $handle',
      output: output.toString().trimRight(),
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: launchSpec.workingDirectory,
      metadata: <String, Object?>{
        ...launchSpec.metadata,
        'bg_handle': handle,
        'bg_pid': process.pid,
        'bg_cmd': cmd,
      },
    );
  }

  Future<AiSandboxLaunchSpec> _prepareLaunchSpec({
    required String cmd,
    required String cwd,
  }) {
    if (Platform.isWindows) {
      return Future<AiSandboxLaunchSpec>.value(
        AiSandboxLaunchSpec.unsandboxed(
          executable: 'cmd',
          arguments: <String>['/d', '/c', cmd],
          workingDirectory: cwd,
        ),
      );
    }
    final shell = Platform.environment['SHELL']?.trim().isNotEmpty == true
        ? Platform.environment['SHELL']!.trim()
        : '/bin/bash';
    return _sandboxService.prepareShellCommand(
      toolName: 'BashBackground',
      command: cmd,
      shellExecutable: shell,
      shellArguments: <String>['-lc', cmd],
      workingDirectory: cwd,
    );
  }

  Future<AiToolExecutionResult> _write(Map<String, Object?> args) async {
    final handle = '${args['handle'] ?? ''}'.trim();
    final input = '${args['input'] ?? ''}';
    final session = _sessions[handle];
    if (session == null) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Unknown handle "$handle". Call start first or list to enumerate.',
      );
    }
    if (!session.alive) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Handle "$handle" already exited (code ${session.exitCode}).',
      );
    }
    try {
      session.process.stdin.write(input);
      if (!input.endsWith('\n')) session.process.stdin.write('\n');
      await session.process.stdin.flush();
    } catch (error, stack) {
      silentLog('ai_bash_background', 'stdin write $handle', error, stack);
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Failed to write stdin: $error',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'BashBackground write $handle',
      output: 'status: ok\nhandle: $handle\nbytes_written: ${input.length}',
      durationMs: 0,
      workingDirectory: session.workingDirectory,
      metadata: <String, Object?>{'bg_handle': handle},
    );
  }

  Future<AiToolExecutionResult> _read(
    Map<String, Object?> args,
    Future<void>? cancelSignal,
  ) async {
    final handle = '${args['handle'] ?? ''}'.trim();
    final maxBytes = AiToolUtils.readInt(args['max_bytes']) ?? 8192;
    final session = _sessions[handle];
    if (session == null) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Unknown handle "$handle".',
      );
    }
    final stdout = session.drainStdout(maxBytes);
    final stderr = session.drainStderr(maxBytes);
    final out = StringBuffer()
      ..writeln('handle: $handle')
      ..writeln('alive: ${session.alive}')
      ..writeln('exit_code: ${session.exitCode ?? -1}')
      ..writeln('--- stdout (new) ---')
      ..writeln(stdout)
      ..writeln('--- stderr (new) ---')
      ..writeln(stderr);
    return AiToolUtils.simpleSuccessResult(
      command: 'BashBackground read $handle',
      output: out.toString().trimRight(),
      durationMs: 0,
      workingDirectory: session.workingDirectory,
      metadata: <String, Object?>{
        'bg_handle': handle,
        'bg_alive': session.alive,
        'bg_exit_code': session.exitCode,
      },
    );
  }

  Future<AiToolExecutionResult> _stop(Map<String, Object?> args) async {
    final handle = '${args['handle'] ?? ''}'.trim();
    final session = _sessions.remove(handle);
    if (session == null) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'Unknown handle "$handle".',
      );
    }
    bool killed = false;
    try {
      killed = session.process.kill(ProcessSignal.sigkill);
    } catch (error, stack) {
      silentLog('ai_bash_background', 'stop $handle', error, stack);
    }
    await session.closeProxy();
    return AiToolUtils.simpleSuccessResult(
      command: 'BashBackground stop $handle',
      output:
          'status: ${killed ? "killed" : "already_exited"}\nhandle: $handle',
      durationMs: 0,
      workingDirectory: session.workingDirectory,
      metadata: <String, Object?>{'bg_handle': handle, 'bg_killed': killed},
    );
  }

  Future<AiToolExecutionResult> _list() async {
    if (_sessions.isEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'BashBackground list',
        output: 'status: ok\nsessions: []',
        durationMs: 0,
      );
    }
    final lines = <String>['status: ok', 'sessions:'];
    for (final session in _sessions.values) {
      lines.add(
        '  - handle: ${session.handle}, pid: ${session.process.pid}, alive: ${session.alive}, '
        'exit_code: ${session.exitCode ?? -1}, cwd: ${session.workingDirectory}, cmd: ${session.command}',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'BashBackground list',
      output: lines.join('\n'),
      durationMs: 0,
    );
  }

  AiDenyCommandRule? _matchDenyRule(
    String command,
    List<AiDenyCommandRule> rules,
  ) {
    for (final rule in rules) {
      if (rule.matches(command)) return rule;
    }
    return null;
  }
}

class _BgSession {
  _BgSession({
    required this.handle,
    required this.command,
    required this.workingDirectory,
    required this.process,
    required this.startedAtMs,
    this.proxyLease,
  });

  final String handle;
  final String command;
  final String workingDirectory;
  final Process process;
  final int startedAtMs;
  final AiSandboxProxyLease? proxyLease;
  final StringBuffer _stdoutPending = StringBuffer();
  final StringBuffer _stderrPending = StringBuffer();
  bool alive = true;
  int? exitCode;
  bool _proxyClosed = false;

  Future<void> closeProxy() async {
    if (_proxyClosed) return;
    _proxyClosed = true;
    await proxyLease?.close();
  }

  void appendStdout(String chunk, int maxBytes) {
    _appendInto(_stdoutPending, chunk, maxBytes);
  }

  void appendStderr(String chunk, int maxBytes) {
    _appendInto(_stderrPending, chunk, maxBytes);
  }

  String drainStdout(int maxBytes) => _drain(_stdoutPending, maxBytes);
  String drainStderr(int maxBytes) => _drain(_stderrPending, maxBytes);

  static void _appendInto(StringBuffer buffer, String chunk, int maxBytes) {
    buffer.write(chunk);
    if (buffer.length > maxBytes * 2) {
      // Trim oldest half to keep memory bounded.
      final retained = buffer.toString();
      final cut = retained.length - maxBytes;
      final trimmed = cut > 0 ? retained.substring(cut) : retained;
      buffer
        ..clear()
        ..write(trimmed);
    }
  }

  static String _drain(StringBuffer buffer, int maxBytes) {
    final pending = buffer.toString();
    buffer.clear();
    if (pending.length <= maxBytes) return pending;
    // Keep the tail (most recent output) when oversized.
    return pending.substring(pending.length - maxBytes);
  }
}
