import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/platform_shell.dart';
import '../../../../shared/util/serial_task_queue.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
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
import 'ai_bash_specialized_tool_policy.dart';
import 'ai_bash_write_confirmation_gate.dart';

const Utf8Decoder _backgroundOutputDecoder = Utf8Decoder(allowMalformed: true);
const int _maxPendingBackgroundStdinWrites = 16;

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

  static const int _maxBufferBytes = 64 * kBytesPerKiB;
  static const int _maxStdinBytes = 64 * kBytesPerKiB;
  static const int _maxConcurrentSessions = 8;
  static const int _defaultReadBytes = 8192;
  static const int _maxRetainedExitedSessions = 4;
  static const int _defaultTaskOutputTimeoutMs = 30000;
  static const int _maxTaskOutputTimeoutMs = 600000;
  static const int _taskOutputPollMs = 100;
  static const Duration _processStartTimeout = Duration(seconds: 10);
  static const Duration _stdinFlushTimeout = Duration(seconds: 2);
  static const String _disposedError = 'BashBackground 已关闭。';

  final Map<String, _BgSession> _sessions = <String, _BgSession>{};
  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final AiSandboxService _sandboxService;
  int _handleCounter = 0;
  int _pendingStarts = 0;
  int _lifecycleGeneration = 0;
  bool _disposed = false;
  Future<void>? _disposeFuture;

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
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposed = true;
    _lifecycleGeneration += 1;
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    return _disposeFuture = Future.wait<void>(
      sessions.map((session) => session.close(kill: true)),
    );
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    if (_disposed) {
      return AiToolUtils.invalidResult('BashBackground', _disposedError);
    }
    final args = context.decodedArguments;
    final action = _resolveAction(context, args);
    if (action.isEmpty) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'BashBackground 缺少 action，可选值：start | write | read | stop | list。',
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
        return _stop(context, args, toolName: _taskAliasToolName(context));
      case 'list':
        return _list(context);
      default:
        return AiToolUtils.invalidResult(
          'BashBackground',
          '不支持 action“$action”，可选值：start | write | read | stop | list。',
        );
    }
  }

  String _resolveAction(
    AiToolExecutionContext context,
    Map<String, Object?> args,
  ) {
    final action = AiToolUtils.readString(args['action']).toLowerCase();
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
    return normalizeAsciiLookupKey(value);
  }

  Future<AiToolExecutionResult> _start(
    AiToolExecutionContext context,
    Map<String, Object?> args,
  ) async {
    final cmd = AiToolUtils.readFirstString(args, const <String>[
      'cmd',
      'command',
    ]);
    if (cmd.isEmpty) {
      return AiToolUtils.invalidResult('BashBackground', 'start 需要非空 cmd。');
    }
    final cwd = AiToolUtils.resolvePath(
      '${args['working_directory'] ?? args['cwd'] ?? ''}',
    );
    final specializedToolDecision = AiBashSpecializedToolPolicy.evaluate(
      command: cmd,
      catalog: context.catalog,
    );
    if (specializedToolDecision != null) {
      return specializedToolDecision.toResult(
        command: cmd,
        workingDirectory: cwd,
      );
    }
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
    final denyRule = _matchDenyRule(cmd, context.denyCommandRules);
    if (denyRule != null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.denied,
        command: cmd,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '命令被拒绝规则阻止：${denyRule.pattern}',
        durationMs: 0,
        matchedRuleId: denyRule.id,
        matchedRulePattern: denyRule.pattern,
        isWriteCommand: writeAnalysis.isWrite,
        writeAnalysisReason: writeAnalysis.reason,
        resultText: 'status: denied\nrule: ${denyRule.pattern}\nreason: 匹配拒绝规则',
      );
    }
    final launchSpec = await _prepareLaunchSpec(
      cmd: cmd,
      cwd: cwd,
      dangerouslyDisableSandbox:
          context.metadata['source'] != 'dingtalk_gateway' &&
          AiToolUtils.readBool(args['dangerouslyDisableSandbox']) == true,
    );
    Future<void> closeLaunchProxy(String reason) {
      final lease = launchSpec.proxyLease;
      if (lease == null) return Future<void>.value();
      return lease.closeBounded(
        logTag: 'ai_bash_background',
        logWhere: '关闭启动代理（$reason）',
      );
    }

    var launchProxyTransferred = false;
    Future<T> runBeforeLaunchProxyTransfer<T>(
      String cleanupReason,
      FutureOr<T> Function() action,
    ) async {
      var completed = false;
      try {
        final result = await action();
        completed = true;
        return result;
      } finally {
        if (!completed && !launchProxyTransferred) {
          await closeLaunchProxy(cleanupReason);
        }
      }
    }

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
      final confirmationResult = await runBeforeLaunchProxyTransfer(
        '确认写命令异常',
        () => AiToolUtils.requestWriteConfirmation(
          toolName: 'BashBackground',
          operationDescription:
              '在 $cwd 启动长时间运行的 Shell 进程\n'
              '原因：${writeAnalysis.reason}\n'
              'cmd: $cmd',
          targetPath: _directoryConfirmationTarget(cwd),
          requireWriteConfirmation:
              context.requireWriteCommandConfirmation || forceWriteConfirmation,
          confirmWriteCommand: confirmationGate.callback,
          cancelSignal: context.cancelSignal,
          timeoutMs: context.writeConfirmationTimeoutMs,
          approvalCommand: cmd,
          approvalWorkingDirectory: cwd,
          resultCommand: cmd,
          writeAnalysisReason: writeAnalysis.reason,
        ),
      );
      if (confirmationResult != null) {
        await closeLaunchProxy('写命令确认被拒绝');
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
    final reservationGeneration = _reserveStart();
    if (reservationGeneration == null) {
      await closeLaunchProxy('启动预留被拒绝');
      return AiToolUtils.invalidResult(
        'BashBackground',
        _disposed
            ? _disposedError
            : '活动后台会话过多，上限为 $_maxConcurrentSessions 个，请先停止一个会话。',
      );
    }
    var reservationHeld = true;
    void releaseStartReservation() {
      if (!reservationHeld) return;
      reservationHeld = false;
      _releaseStartReservation();
    }

    final startedAt = Stopwatch()..start();
    final Process process;
    try {
      process = await runBeforeLaunchProxyTransfer('启动进程异常', () async {
        return startTrackedProcessBounded(
          launchSpec.executable,
          launchSpec.arguments,
          timeout: _processStartTimeout,
          tag: 'ai_bash_background',
          startInNewProcessGroup: true,
          workingDirectory: launchSpec.workingDirectory,
          environment: launchSpec.environment.isEmpty
              ? null
              : launchSpec.environment,
        );
      });
    } on TimeoutException catch (error) {
      await closeLaunchProxy('启动超时');
      releaseStartReservation();
      return AiToolUtils.invalidResult('BashBackground', '进程启动超时：$error');
    } catch (error, stack) {
      releaseStartReservation();
      await closeLaunchProxy('创建进程失败');
      silentLog('ai_bash_background', '启动进程 $cmd', error, stack);
      return AiToolUtils.invalidResult('BashBackground', '创建进程失败：$error');
    }
    if (_disposed || reservationGeneration != _lifecycleGeneration) {
      releaseStartReservation();
      await Future.wait<void>(<Future<void>>[
        runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(process),
          onError: (error, stack) =>
              silentLog('ai_bash_background', '清理迟到后台进程', error, stack),
        ).then<void>((_) {}),
        closeLaunchProxy('迟到进程'),
      ]);
      return AiToolUtils.invalidResult(
        'BashBackground',
        '进程启动期间 BashBackground 已关闭。',
      );
    }
    releaseStartReservation();
    _handleCounter += 1;
    final handle = 'bg_$_handleCounter';
    late final _BgSession session;
    var sessionSetupCompleted = false;
    try {
      session = await runBeforeLaunchProxyTransfer('创建后台会话异常', () {
        final value = _BgSession(
          handle: handle,
          ownerSessionId: context.sessionId,
          command: cmd,
          workingDirectory: launchSpec.workingDirectory,
          process: process,
          startedAtMs: DateTime.now().millisecondsSinceEpoch,
          proxyLease: launchSpec.proxyLease,
        );
        _sessions[handle] = value;
        launchProxyTransferred = true;
        return value;
      });
      final toolCallId = context.toolCall.id.trim();
      if (toolCallId.isNotEmpty) {
        AiToolExecutionRegistry.instance.attachPid(toolCallId, process.pid);
        AiToolExecutionRegistry.instance.attachKiller(toolCallId, () async {
          final removed = _sessions.remove(handle);
          await (removed ?? session).close(kill: true);
        });
      }
      Future<void> finishExitedProcess() async {
        try {
          await terminateTrackedProcessTree(
            process,
            gracefulTimeout: Duration.zero,
          );
          await session.finishOutputAfterExit();
          session.touch();
          await session.closeProxy();
          _pruneExitedSessions();
        } catch (error, stack) {
          silentLog('ai_bash_background', '收尾后台进程 $handle', error, stack);
        }
      }

      session.stdoutSubscription = process.stdout
          .transform(_backgroundOutputDecoder)
          .listen(
            (data) => session.appendStdout(data, _maxBufferBytes),
            onError: (Object error, StackTrace stack) {
              session.markStdoutDone();
              silentLog('ai_bash_background', '读取标准输出 $handle', error, stack);
            },
            onDone: session.markStdoutDone,
          );
      session.stderrSubscription = process.stderr
          .transform(_backgroundOutputDecoder)
          .listen(
            (data) => session.appendStderr(data, _maxBufferBytes),
            onError: (Object error, StackTrace stack) {
              session.markStderrDone();
              silentLog('ai_bash_background', '读取标准错误 $handle', error, stack);
            },
            onDone: session.markStderrDone,
          );
      unawaited(
        process.exitCode.then<void>(
          (code) async {
            session.exitCode = code;
            await finishExitedProcess();
          },
          onError: (Object error, StackTrace stack) async {
            silentLog('ai_bash_background', '进程退出 $handle', error, stack);
            session.exitCode = -1;
            await finishExitedProcess();
          },
        ),
      );
      sessionSetupCompleted = true;
    } finally {
      if (!sessionSetupCompleted) {
        final createdSession = _sessions.remove(handle);
        if (createdSession == null) {
          await runAsyncCleanupBounded(
            () => terminateTrackedProcessTree(process),
            onError: (error, stack) =>
                silentLog('ai_bash_background', '清理未完成的后台进程', error, stack),
          );
        } else {
          await createdSession.close(kill: true);
        }
      }
    }
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
    final shell = preferredPosixShellExecutable(requireBashCompatible: true);
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
    final handle = AiToolUtils.readString(args['handle']);
    final input = '${args['input'] ?? ''}';
    final session = _sessionForOwner(handle, context.sessionId);
    if (session == null) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        '未知 handle“$handle”，请先调用 start，或调用 list 查看会话。',
      );
    }
    if (!session.alive) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'handle“$handle”对应的进程已退出，退出码：${session.exitCode}。',
      );
    }
    final inputBytes = utf8.encode(input);
    final appendNewline = !input.endsWith('\n');
    final bytesWritten = inputBytes.length + (appendNewline ? 1 : 0);
    if (bytesWritten > _maxStdinBytes) {
      return AiToolUtils.invalidResult(
        'BashBackground',
        'stdin 输入超过 $_maxStdinBytes 字节上限。',
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
      await session.writeInput(
        inputBytes,
        appendNewline: appendNewline,
        timeout: _stdinFlushTimeout,
      );
    } catch (error, stack) {
      silentLog('ai_bash_background', '写入标准输入 $handle', error, stack);
      final removed = _sessions.remove(handle);
      await (removed ?? session).close(kill: true);
      return AiToolUtils.invalidResult('BashBackground', '写入 stdin 失败：$error');
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'BashBackground write $handle',
      output: 'status: ok\nhandle: $handle\nbytes_written: $bytesWritten',
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
    final rawMaxBytes = AiToolUtils.readInt(args['max_bytes']);
    if (rawMaxBytes != null &&
        (rawMaxBytes < 0 || rawMaxBytes > _maxBufferBytes)) {
      return AiToolUtils.invalidResult(
        toolName,
        'max_bytes 必须在 0 到 $_maxBufferBytes 之间。',
      );
    }
    final rawTimeoutMs =
        AiToolUtils.readInt(args['timeout']) ??
        AiToolUtils.readInt(args['timeout_ms']);
    if (rawTimeoutMs != null &&
        (rawTimeoutMs < 0 || rawTimeoutMs > _maxTaskOutputTimeoutMs)) {
      return AiToolUtils.invalidResult(
        toolName,
        'timeout 必须在 0 到 $_maxTaskOutputTimeoutMs 毫秒之间。',
      );
    }
    final maxBytes = _normalizeReadBytes(rawMaxBytes);
    final timeoutMs = _normalizeTaskOutputTimeoutMs(rawTimeoutMs);
    final session = _sessionForOwner(handle, context.sessionId);
    if (session == null) {
      return AiToolUtils.invalidResult(
        toolName,
        handle.isEmpty
            ? '$toolName 需要 task_id 或 handle。'
            : '未知 handle“$handle”。',
      );
    }
    final isTaskOutputAlias = toolName == 'TaskOutput';
    final block = _readBool(args['block'], defaultValue: isTaskOutputAlias);
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
        stderr: 'TaskOutput 等待已取消。',
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
    AiToolExecutionContext context,
    Map<String, Object?> args, {
    required String toolName,
  }) async {
    final handle = _handleFromArgs(args);
    final ownedSession = _sessionForOwner(handle, context.sessionId);
    final session = ownedSession == null ? null : _sessions.remove(handle);
    if (session == null) {
      return AiToolUtils.invalidResult(
        toolName,
        handle.isEmpty
            ? '$toolName 需要 task_id、shell_id 或 handle。'
            : '未知 handle“$handle”。',
      );
    }
    bool killed = false;
    try {
      killed = session.alive;
      await session.close(kill: true);
    } catch (error, stack) {
      silentLog('ai_bash_background', '停止后台进程 $handle', error, stack);
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

  Future<AiToolExecutionResult> _list(AiToolExecutionContext context) async {
    _pruneExitedSessions();
    final sessions = _sessions.values
        .where((session) => session.ownerSessionId == context.sessionId)
        .toList(growable: false);
    if (sessions.isEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'BashBackground list',
        output: 'status: ok\nsessions: []',
        durationMs: 0,
      );
    }
    final lines = <String>['status: ok', 'sessions:'];
    for (final session in sessions) {
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

  _BgSession? _sessionForOwner(String handle, String sessionId) {
    final session = _sessions[handle];
    return session?.ownerSessionId == sessionId ? session : null;
  }

  int? _reserveStart() {
    _pruneExitedSessions();
    if (_disposed ||
        _activeSessionCount + _pendingStarts >= _maxConcurrentSessions) {
      return null;
    }
    _pendingStarts += 1;
    return _lifecycleGeneration;
  }

  void _releaseStartReservation() {
    if (_pendingStarts > 0) _pendingStarts -= 1;
  }

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
    return AiToolUtils.readBool(rawValue) ?? defaultValue;
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
    final stopwatch = Stopwatch()..start();
    while (session.alive) {
      final remainingMs = timeoutMs - stopwatch.elapsedMilliseconds;
      if (remainingMs <= 0) return false;
      final waitMs = remainingMs < _taskOutputPollMs
          ? remainingMs
          : _taskOutputPollMs;
      final cancelled = await delayUntilCancelled(
        Duration(milliseconds: waitMs),
        cancelSignal: cancelSignal,
      );
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
        unawaited(
          session.close(kill: false).catchError((error, stack) {
            silentLog('ai_bash_background', '回收已退出后台会话', error, stack);
          }),
        );
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
  return decision.diagnosticText(
    contextLines: <String>[
      'action: $action',
      if (handle != null && handle.isNotEmpty) 'handle: $handle',
    ],
  );
}

class _BgSession {
  _BgSession({
    required this.handle,
    required this.ownerSessionId,
    required this.command,
    required this.workingDirectory,
    required this.process,
    required this.startedAtMs,
    this.proxyLease,
  });

  final String handle;
  final String ownerSessionId;
  final String command;
  final String workingDirectory;
  final Process process;
  final int startedAtMs;
  final AiSandboxProxyLease? proxyLease;
  static const Duration _cleanupTimeout = Duration(seconds: 2);
  final StringBuffer _stdoutPending = StringBuffer();
  final StringBuffer _stderrPending = StringBuffer();
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();
  final SerialTaskQueue _stdinWrites = SerialTaskQueue(
    maxPendingTasks: _maxPendingBackgroundStdinWrites,
  );
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  bool alive = true;
  int? exitCode;
  Future<void>? _proxyCloseFuture;
  Future<void>? _closeFuture;
  late int lastTouchedAtMs = startedAtMs;

  void touch() {
    lastTouchedAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  void markStdoutDone() {
    if (!_stdoutDone.isCompleted) _stdoutDone.complete();
  }

  void markStderrDone() {
    if (!_stderrDone.isCompleted) _stderrDone.complete();
  }

  Future<void> finishOutputAfterExit() async {
    try {
      await Future.wait<void>([
        _stdoutDone.future,
        _stderrDone.future,
      ]).timeout(_cleanupTimeout);
    } on TimeoutException {
      // 子进程可能仍持有继承管道，超时后继续有界收尾。
    }
    alive = false;
  }

  Future<void> writeInput(
    List<int> bytes, {
    required bool appendNewline,
    required Duration timeout,
  }) {
    return _stdinWrites.enqueue(() async {
      if (!alive) throw StateError('后台进程已退出。');
      process.stdin.add(bytes);
      if (appendNewline) process.stdin.add(const <int>[10]);
      await process.stdin.flush().timeout(timeout);
    });
  }

  Future<void> close({required bool kill}) {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final cleanup = <Future<bool>>[];
    if (kill && alive) {
      alive = false;
      cleanup.add(
        runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(process),
          onError: (error, stack) =>
              silentLog('ai_bash_background', '终止后台进程', error, stack),
        ),
      );
    }
    final stdout = stdoutSubscription;
    final stderr = stderrSubscription;
    stdoutSubscription = null;
    stderrSubscription = null;
    cleanup.add(
      cancelStreamSubscriptionBounded<String>(
        stdout,
        onError: (error, stack) =>
            silentLog('ai_bash_background', '取消后台标准输出订阅', error, stack),
      ),
    );
    cleanup.add(
      cancelStreamSubscriptionBounded<String>(
        stderr,
        onError: (error, stack) =>
            silentLog('ai_bash_background', '取消后台标准错误订阅', error, stack),
      ),
    );
    cleanup.add(
      runAsyncCleanupBounded(
        () => _stdinWrites.idle,
        onError: (error, stack) =>
            silentLog('ai_bash_background', '排空后台标准输入队列', error, stack),
      ),
    );
    markStdoutDone();
    markStderrDone();
    cleanup.add(closeProxy().then<bool>((_) => true));
    return _closeFuture = Future.wait<bool>(cleanup).then<void>((_) {});
  }

  Future<void> closeProxy() {
    final existing = _proxyCloseFuture;
    if (existing != null) return existing;
    final lease = proxyLease;
    if (lease == null) return _proxyCloseFuture = Future<void>.value();
    return _proxyCloseFuture = lease.closeBounded(
      logTag: 'ai_bash_background',
      logWhere: '关闭后台代理',
    );
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
      // 丢弃最旧内容，限制内存占用。
      final retained = buffer.toString();
      final cut = retained.length - maxBytes;
      final trimmed = cut > 0
          ? retained.substring(safeUtf16SuffixStart(retained, cut))
          : retained;
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
    // 超限时保留最新输出。
    return pending.substring(
      safeUtf16SuffixStart(pending, pending.length - maxBytes),
    );
  }
}
