import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../model/ai_deny_command_rule.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_execution_registry.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/sandbox/ai_sandbox_proxy_service.dart';
import '../../service/sandbox/ai_sandbox_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../android_reverse_adb_command_guard.dart';
import '../web_reverse_cdp_first_guard.dart';
import 'ai_bash_write_confirmation_gate.dart';

const Utf8Decoder _backgroundOutputDecoder = Utf8Decoder(allowMalformed: true);

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
  AiBashBackgroundTool({
    AiBashToolService? bashToolService,
    AiClaudeHookService? hookService,
    AiSandboxService? sandboxService,
  }) : _bashToolService = bashToolService ?? AiBashToolService(),
       _hookService = hookService ?? AiNoopClaudeHookService(),
       _sandboxService =
           sandboxService ??
           bashToolService?.sandboxService ??
           AiSandboxService();

  static const int _maxBufferBytes = 64 * 1024;
  static const int _maxConcurrentSessions = 8;
  static const int _defaultReadBytes = 8192;
  static const int _maxRetainedExitedSessions = 4;
  static const int _defaultTaskOutputTimeoutMs = 30000;
  static const int _maxTaskOutputTimeoutMs = 600000;
  static const int _taskOutputPollMs = 100;

  final Map<String, _BgSession> _sessions = <String, _BgSession>{};
  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final AiSandboxService _sandboxService;
  int _handleCounter = 0;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.bashBackground;

  @override
  List<String> get aliases => const <String>[
    'TaskOutput',
    'BashOutputTool',
    'AgentOutputTool',
    'TaskStop',
    'KillShell',
  ];

  @override
  bool get isDestructive => true;

  // 用户取消时不强杀后台进程，只取消当前 read 等待；后台进程靠 stop action 清理。
  @override
  AiToolInterruptBehavior get interruptBehavior =>
      AiToolInterruptBehavior.cancel;

  void dispose() {
    for (final session in _sessions.values.toList(growable: false)) {
      unawaited(session.close(kill: true));
    }
    _sessions.clear();
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final action = _resolveAction(context, args);
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
        return _write(context, args);
      case 'read':
        return _read(context, args, toolName: _taskAliasToolName(context));
      case 'stop':
        return _stop(args, toolName: _taskAliasToolName(context));
      case 'list':
        return _list();
      default:
        return AiToolUtils.invalidResult(
          'BashBackground',
          'Unsupported action "$action". Use: start | write | read | stop | list.',
        );
    }
  }

  String _resolveAction(
    AiToolExecutionContext context,
    Map<String, Object?> args,
  ) {
    final action = '${args['action'] ?? ''}'.trim().toLowerCase();
    if (action.isNotEmpty) return action;
    final toolName = _normalizedToolCallName(context.toolCall.name);
    if (toolName == 'taskoutput' ||
        toolName == 'bashoutputtool' ||
        toolName == 'agentoutputtool') {
      return 'read';
    }
    if (toolName == 'taskstop' || toolName == 'killshell') {
      return 'stop';
    }
    return '';
  }

  String _taskAliasToolName(AiToolExecutionContext context) {
    final toolName = _normalizedToolCallName(context.toolCall.name);
    if (toolName == 'taskoutput' ||
        toolName == 'bashoutputtool' ||
        toolName == 'agentoutputtool') {
      return 'TaskOutput';
    }
    if (toolName == 'taskstop' || toolName == 'killshell') {
      return 'TaskStop';
    }
    return 'BashBackground';
  }

  String _normalizedToolCallName(String value) {
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if ((code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A)) {
        buffer.writeCharCode(code | 0x20);
      }
    }
    return buffer.toString();
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
    final cwd = AiToolUtils.resolvePath(
      '${args['working_directory'] ?? args['cwd'] ?? ''}',
    );
    final cdpFirstDecision = WebReverseCdpFirstGuard.evaluateCommand(
      command: cmd,
      metadata: context.metadata,
    );
    if (cdpFirstDecision != null) {
      return _webReverseBashBackgroundCdpFirstBlock(
        decision: cdpFirstDecision,
        command: cmd,
        workingDirectory: cwd,
        action: 'start',
      );
    }
    final writeAnalysis = _bashToolService.analyzeWriteCommand(cmd);
    final forceWriteConfirmation =
        AndroidReverseAdbCommandGuard.requiresExplicitApproval(
          command: cmd,
          metadata: context.metadata,
        );
    _pruneExitedSessions();
    if (_activeSessionCount >= _maxConcurrentSessions) {
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
        isWriteCommand: writeAnalysis.isWrite,
        writeAnalysisReason: writeAnalysis.reason,
        resultText:
            'status: denied\nrule: ${denyRule.pattern}\nreason: matched deny rule',
      );
    }
    final launchSpec = await _prepareLaunchSpec(
      cmd: cmd,
      cwd: cwd,
      dangerouslyDisableSandbox:
          AiToolUtils.readBool(args['dangerouslyDisableSandbox']) == true,
    );
    if (launchSpec.blocked) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.denied,
        command: cmd,
        workingDirectory: cwd,
        stdout: '',
        stderr: launchSpec.reason,
        durationMs: 0,
        isWriteCommand: writeAnalysis.isWrite,
        writeAnalysisReason: writeAnalysis.reason,
        resultText: 'status: denied\nreason: ${launchSpec.reason}',
        metadata: launchSpec.metadata,
      );
    }
    var writeConfirmationMetadata = const <String, Object?>{};
    if (writeAnalysis.isWrite || forceWriteConfirmation) {
      final confirmationGate = AiBashWriteConfirmationGate(
        hookService: _hookService,
        sessionId: context.sessionId,
        toolName: 'BashBackground',
        userConfirmation: context.confirmWriteCommand,
      );
      final confirmationResult = await AiToolUtils.requestWriteConfirmation(
        toolName: 'BashBackground',
        operationDescription:
            'Start long-running shell process in $cwd\n'
            'reason: ${writeAnalysis.reason}\n'
            'cmd: $cmd',
        targetPath: _directoryConfirmationTarget(cwd),
        requireWriteConfirmation:
            context.requireWriteCommandConfirmation || forceWriteConfirmation,
        confirmWriteCommand: confirmationGate.callback,
        cancelSignal: context.cancelSignal,
        timeoutMs: context.metadata['write_confirmation_timeout_ms'] as int?,
        approvalCommand: cmd,
        approvalWorkingDirectory: cwd,
        resultCommand: cmd,
        writeAnalysisReason: writeAnalysis.reason,
      );
      if (confirmationResult != null) {
        await launchSpec.proxyLease?.close();
        return AiToolUtils.withMergedMetadata(confirmationResult, <
          String,
          Object?
        >{
          ...confirmationGate.metadata,
          if (forceWriteConfirmation) ...AndroidReverseAdbCommandGuard.metadata,
        });
      }
      writeConfirmationMetadata = <String, Object?>{
        ...confirmationGate.metadata,
        if (forceWriteConfirmation) ...AndroidReverseAdbCommandGuard.metadata,
      };
    }
    final startedAt = Stopwatch()..start();
    final Process process;
    try {
      process = await startTrackedProcessInNewGroup(
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
    final toolCallId = context.toolCall.id.trim();
    if (toolCallId.isNotEmpty) {
      AiToolExecutionRegistry.instance.attachPid(toolCallId, process.pid);
      AiToolExecutionRegistry.instance.attachKiller(toolCallId, () async {
        final removed = _sessions.remove(handle);
        await (removed ?? session).close(kill: true);
      });
    }
    session.stdoutSubscription = process.stdout
        .transform(_backgroundOutputDecoder)
        .listen(
          (data) => session.appendStdout(data, _maxBufferBytes),
          onError: (Object error, StackTrace stack) {
            silentLog('ai_bash_background', 'stdout $handle', error, stack);
          },
        );
    session.stderrSubscription = process.stderr
        .transform(_backgroundOutputDecoder)
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
        session.touch();
        unawaited(session.closeProxy());
        _pruneExitedSessions();
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
      isWriteCommand: writeAnalysis.isWrite || forceWriteConfirmation,
      writeAnalysisReason: writeAnalysis.reason,
      metadata: <String, Object?>{
        ...launchSpec.metadata,
        ...writeConfirmationMetadata,
        'bg_handle': handle,
        'bg_pid': process.pid,
        'bg_cmd': cmd,
        if (writeAnalysis.isWrite || forceWriteConfirmation)
          'file_mutation_kind': 'bash_background_write',
        if (writeAnalysis.isWrite || forceWriteConfirmation)
          'file_mutation_working_directory': launchSpec.workingDirectory,
        if (writeAnalysis.isWrite || forceWriteConfirmation)
          'file_mutation_command_char_count': cmd.length,
        if (writeAnalysis.isWrite || forceWriteConfirmation)
          'file_mutation_write_reason': writeAnalysis.reason,
      },
    );
  }

  Future<AiSandboxLaunchSpec> _prepareLaunchSpec({
    required String cmd,
    required String cwd,
    required bool dangerouslyDisableSandbox,
  }) {
    if (Platform.isWindows) {
      // Windows 也需要继承用户级代理 env（curl/git/ssh 等仍依赖标准变量）。
      final proxyEnv = SystemProxyResolver.instance
          .resolveSubprocessEnvironment();
      return Future<AiSandboxLaunchSpec>.value(
        AiSandboxLaunchSpec.unsandboxed(
          executable: 'cmd',
          arguments: <String>['/d', '/c', cmd],
          workingDirectory: cwd,
          environment: proxyEnv,
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
      dangerouslyDisableSandbox: dangerouslyDisableSandbox,
    );
  }

  Future<AiToolExecutionResult> _write(
    AiToolExecutionContext context,
    Map<String, Object?> args,
  ) async {
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
    final cdpFirstDecision = WebReverseCdpFirstGuard.evaluateCommand(
      command: input,
      metadata: context.metadata,
    );
    if (cdpFirstDecision != null) {
      return _webReverseBashBackgroundCdpFirstBlock(
        decision: cdpFirstDecision,
        command: input,
        workingDirectory: session.workingDirectory,
        action: 'write',
        handle: handle,
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
    AiToolExecutionContext context,
    Map<String, Object?> args, {
    required String toolName,
  }) async {
    final startedAt = Stopwatch()..start();
    final handle = _handleFromArgs(args);
    final maxBytes = _normalizeReadBytes(
      AiToolUtils.readInt(args['max_bytes']),
    );
    final session = _sessions[handle];
    if (session == null) {
      return AiToolUtils.invalidResult(
        toolName,
        handle.isEmpty
            ? '$toolName requires task_id or handle.'
            : 'Unknown handle "$handle".',
      );
    }
    final isTaskOutputAlias = toolName == 'TaskOutput';
    final block = _readBool(args['block'], defaultValue: isTaskOutputAlias);
    final timeoutMs = _normalizeTaskOutputTimeoutMs(
      AiToolUtils.readInt(args['timeout']) ??
          AiToolUtils.readInt(args['timeout_ms']),
    );
    var cancelled = false;
    if (block && session.alive) {
      cancelled = await _waitForSessionExit(
        session,
        timeoutMs: timeoutMs,
        cancelSignal: context.cancelSignal,
      );
    }
    if (cancelled) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: '$toolName $handle',
        workingDirectory: session.workingDirectory,
        stdout: '',
        stderr: 'TaskOutput wait cancelled.',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: cancelled\nhandle: $handle',
        metadata: <String, Object?>{
          'bg_handle': handle,
          'task_id': handle,
          'task_output_alias': isTaskOutputAlias,
          'task_output_cancelled': true,
        },
      );
    }
    session.touch();
    final stdout = session.drainStdout(maxBytes);
    final stderr = session.drainStderr(maxBytes);
    final retrievalStatus = block && session.alive
        ? 'timeout'
        : (!block && session.alive ? 'not_ready' : 'success');
    final out = StringBuffer();
    if (isTaskOutputAlias) {
      out
        ..writeln('retrieval_status: $retrievalStatus')
        ..writeln('task_id: $handle')
        ..writeln('task_type: local_bash');
    }
    out
      ..writeln('handle: $handle')
      ..writeln('alive: ${session.alive}')
      ..writeln('exit_code: ${session.exitCode ?? -1}')
      ..writeln('--- stdout (new) ---')
      ..writeln(stdout)
      ..writeln('--- stderr (new) ---')
      ..writeln(stderr);
    return AiToolUtils.simpleSuccessResult(
      command: isTaskOutputAlias
          ? '$toolName $handle'
          : 'BashBackground read $handle',
      output: out.toString().trimRight(),
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: session.workingDirectory,
      metadata: <String, Object?>{
        'bg_handle': handle,
        'bg_alive': session.alive,
        'bg_exit_code': session.exitCode,
        if (isTaskOutputAlias) ...<String, Object?>{
          'task_output_alias': true,
          'task_id': handle,
          'task_type': 'local_bash',
          'task_output_retrieval_status': retrievalStatus,
          'task_output_block': block,
          'task_output_timeout_ms': timeoutMs,
        },
      },
    );
  }

  Future<AiToolExecutionResult> _stop(
    Map<String, Object?> args, {
    required String toolName,
  }) async {
    final handle = _handleFromArgs(args);
    final session = _sessions.remove(handle);
    if (session == null) {
      return AiToolUtils.invalidResult(
        toolName,
        handle.isEmpty
            ? '$toolName requires task_id, shell_id, or handle.'
            : 'Unknown handle "$handle".',
      );
    }
    bool killed = false;
    try {
      killed = session.alive;
      await session.close(kill: true);
    } catch (error, stack) {
      silentLog('ai_bash_background', 'stop $handle', error, stack);
    }
    final isTaskStopAlias = toolName == 'TaskStop';
    final output = isTaskStopAlias
        ? 'status: ${killed ? "killed" : "already_exited"}\n'
              'handle: $handle\n'
              'task_id: $handle\n'
              'task_type: local_bash'
        : 'status: ${killed ? "killed" : "already_exited"}\nhandle: $handle';
    return AiToolUtils.simpleSuccessResult(
      command: isTaskStopAlias
          ? '$toolName $handle'
          : 'BashBackground stop $handle',
      output: output,
      durationMs: 0,
      workingDirectory: session.workingDirectory,
      metadata: <String, Object?>{
        'bg_handle': handle,
        'bg_killed': killed,
        if (isTaskStopAlias) ...<String, Object?>{
          'task_stop_alias': true,
          'task_id': handle,
          'task_type': 'local_bash',
        },
      },
    );
  }

  Future<AiToolExecutionResult> _list() async {
    _pruneExitedSessions();
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

  int get _activeSessionCount =>
      _sessions.values.where((session) => session.alive).length;

  int _normalizeReadBytes(int? value) {
    final raw = value ?? _defaultReadBytes;
    return raw.clamp(0, _maxBufferBytes).toInt();
  }

  String _handleFromArgs(Map<String, Object?> args) {
    for (final key in const <String>['handle', 'task_id', 'shell_id']) {
      final value = '${args[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _readBool(Object? rawValue, {required bool defaultValue}) {
    if (rawValue == null) return defaultValue;
    if (rawValue is bool) return rawValue;
    final normalized = '$rawValue'.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return defaultValue;
  }

  int _normalizeTaskOutputTimeoutMs(int? value) {
    final raw = value ?? _defaultTaskOutputTimeoutMs;
    return raw.clamp(0, _maxTaskOutputTimeoutMs).toInt();
  }

  Future<bool> _waitForSessionExit(
    _BgSession session, {
    required int timeoutMs,
    Future<void>? cancelSignal,
  }) async {
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    while (session.alive) {
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAtMs;
      final remainingMs = timeoutMs - elapsedMs;
      if (remainingMs <= 0) return false;
      var cancelled = false;
      final waitMs = remainingMs < _taskOutputPollMs
          ? remainingMs
          : _taskOutputPollMs;
      if (cancelSignal == null) {
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      } else {
        await Future.any(<Future<void>>[
          Future<void>.delayed(Duration(milliseconds: waitMs)),
          cancelSignal.then((_) {
            cancelled = true;
          }),
        ]);
      }
      if (cancelled) return true;
    }
    return false;
  }

  String _directoryConfirmationTarget(String directory) {
    final separator = Platform.pathSeparator;
    final suffix = directory.endsWith(separator) ? '.' : '$separator.';
    return '$directory$suffix';
  }

  void _pruneExitedSessions() {
    final exited =
        _sessions.values
            .where((session) => !session.alive)
            .toList(growable: false)
          ..sort((a, b) => b.lastTouchedAtMs.compareTo(a.lastTouchedAtMs));
    for (final session in exited.skip(_maxRetainedExitedSessions)) {
      if (_sessions.remove(session.handle) != null) {
        unawaited(session.close(kill: false));
      }
    }
  }
}

AiToolExecutionResult _webReverseBashBackgroundCdpFirstBlock({
  required WebReverseCdpFirstDecision decision,
  required String command,
  required String workingDirectory,
  required String action,
  String? handle,
}) {
  final message = decision.blockedMessage('BashBackground');
  return AiToolExecutionResult(
    status: BashToolExecutionStatus.denied,
    command: command.isEmpty ? 'BashBackground $action' : command,
    workingDirectory: workingDirectory.isEmpty
        ? AiToolUtils.defaultWorkingDirectory()
        : AiToolUtils.resolvePath(workingDirectory),
    stdout: _webReverseBashBackgroundCdpFirstStdout(
      decision: decision,
      action: action,
      handle: handle,
    ),
    stderr: message,
    durationMs: 0,
    resultText: 'status: denied\nerror: $message',
    metadata: <String, Object?>{
      'web_reverse_bash_background_blocked_action': action,
      'web_reverse_bash_background_blocked_command_char_count': command.length,
      if (handle != null && handle.isNotEmpty) 'bg_handle': handle,
      ...decision.metadata(
        requestedUrl: decision.requestedUri.toString(),
        blockedFlag: 'web_reverse_bash_background_blocked_for_cdp_first',
      ),
    },
  );
}

String _webReverseBashBackgroundCdpFirstStdout({
  required WebReverseCdpFirstDecision decision,
  required String action,
  String? handle,
}) {
  final out = StringBuffer()
    ..writeln('cdp_first_required: true')
    ..writeln('action: $action');
  if (handle != null && handle.isNotEmpty) {
    out.writeln('handle: $handle');
  }
  out
    ..writeln('target_origin: ${decision.targetOrigin}')
    ..writeln('requested_origin: ${decision.requestedOrigin}')
    ..writeln('cdp_route: ${decision.routeKind}')
    ..write('cdp_tools: ${decision.toolText}');
  return out.toString();
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
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  bool alive = true;
  int? exitCode;
  bool _proxyClosed = false;
  bool _closed = false;
  late int lastTouchedAtMs = startedAtMs;

  void touch() {
    lastTouchedAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> close({required bool kill}) async {
    if (_closed) return;
    _closed = true;
    if (kill && alive) {
      await terminateTrackedProcessTree(process);
      alive = false;
    }
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
    await closeProxy();
  }

  Future<void> closeProxy() async {
    if (_proxyClosed) return;
    _proxyClosed = true;
    await proxyLease?.close();
  }

  void appendStdout(String chunk, int maxBytes) {
    touch();
    _appendInto(_stdoutPending, chunk, maxBytes);
  }

  void appendStderr(String chunk, int maxBytes) {
    touch();
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
    if (maxBytes <= 0) return '';
    final pending = buffer.toString();
    buffer.clear();
    if (pending.length <= maxBytes) return pending;
    // Keep the tail (most recent output) when oversized.
    return pending.substring(pending.length - maxBytes);
  }
}
