import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../model/ai_deny_command_rule.dart';
import '../runtime/ai_tool_execution_registry.dart';
import '../sandbox/ai_sandbox_service.dart';

const Utf8Decoder _shellOutputDecoder = Utf8Decoder(allowMalformed: true);

enum BashToolExecutionStatus {
  success('success'),
  failed('failed'),
  cancelled('cancelled'),
  denied('denied'),
  rejected('rejected'),
  timedOut('timed_out'),
  invalidArguments('invalid_arguments');

  const BashToolExecutionStatus(this.storageValue);

  final String storageValue;
}

enum BashToolExecutionPhase { running, completed }

/// 用户对 bash 写命令的确认决策。`approved` 与 `rejected` 来自显式
/// 点击；`dismissed` 表示用户按 ESC（没明示同意也没明示拒绝，更像
/// "暂不决定"）；其余区分超时与会话级取消。把决策完整透传给 AI，
/// 让模型在后续动作中区分"用户拒绝"vs"用户没作答"。
enum BashCommandApprovalDecision {
  approved,
  rejected,
  dismissed,
  timedOut,
  cancelled;

  bool get isApproved => this == BashCommandApprovalDecision.approved;
}

class BashCommandApprovalRequest {
  const BashCommandApprovalRequest({
    required this.command,
    required this.workingDirectory,
    required this.isWriteCommand,
  });

  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
}

class BashToolExecutionUpdate {
  const BashToolExecutionUpdate({
    required this.phase,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.exitCode,
    this.stallWarning,
  });

  final BashToolExecutionPhase phase;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int durationMs;
  final int? exitCode;

  /// 命令长时间没有新增输出时附带的停滞提示。null 表示一切正常。
  /// 形如 `'45s 内无新输出，疑似在等待交互式输入：(y/n)'`。
  final String? stallWarning;
}

class BashToolExecutionResult {
  const BashToolExecutionResult({
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.exitCode,
    this.matchedRuleId,
    this.matchedRulePattern,
    this.isWriteCommand = false,
    this.writeAnalysisReason = '',
    this.sandboxMetadata = const <String, Object?>{},
  });

  final BashToolExecutionStatus status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int durationMs;
  final int? exitCode;
  final String? matchedRuleId;
  final String? matchedRulePattern;
  final bool isWriteCommand;
  final String writeAnalysisReason;
  final Map<String, Object?> sandboxMetadata;

  String toToolOutput() {
    final buffer = StringBuffer()
      ..writeln('status: ${status.storageValue}')
      ..writeln('command: $command')
      ..writeln('working_directory: $workingDirectory')
      ..writeln('duration_ms: $durationMs');
    if (exitCode != null) {
      buffer.writeln('exit_code: $exitCode');
    }
    if (matchedRuleId != null && matchedRulePattern != null) {
      buffer
        ..writeln('matched_rule_id: $matchedRuleId')
        ..writeln('matched_rule_pattern: $matchedRulePattern');
    }
    if (sandboxMetadata['sandbox_applied'] == true) {
      buffer
        ..writeln('sandbox: applied')
        ..writeln(
          'sandbox_backend: ${sandboxMetadata['sandbox_backend'] ?? ''}',
        );
    } else if (sandboxMetadata['sandbox_blocked'] == true) {
      buffer.writeln('sandbox: blocked');
    } else if (sandboxMetadata['sandbox_unavailable_reason'] != null) {
      buffer.writeln(
        'sandbox_unavailable_reason: ${sandboxMetadata['sandbox_unavailable_reason']}',
      );
    }
    if (sandboxMetadata['sandbox_proxy_enabled'] == true) {
      buffer.writeln(
        'sandbox_proxy: http=${sandboxMetadata['sandbox_proxy_http_port'] ?? ''}'
        '${sandboxMetadata['sandbox_proxy_socks_port'] == null ? '' : ', socks=${sandboxMetadata['sandbox_proxy_socks_port']}'}',
      );
    }
    final sandboxWarning =
        '${sandboxMetadata['sandbox_domain_filter_warning'] ?? ''}'.trim();
    if (sandboxWarning.isNotEmpty) {
      buffer.writeln('sandbox_warning: $sandboxWarning');
    }
    if (stdout.trim().isNotEmpty) {
      buffer
        ..writeln('stdout:')
        ..writeln(stdout.trimRight());
    }
    if (stderr.trim().isNotEmpty) {
      buffer
        ..writeln('stderr:')
        ..writeln(stderr.trimRight());
    }
    return buffer.toString().trim();
  }
}

class _WriteConfirmationOutcome {
  const _WriteConfirmationOutcome._({
    required this.decision,
    required this.cancelled,
  });

  const _WriteConfirmationOutcome.fromDecision(BashCommandApprovalDecision d)
    : this._(decision: d, cancelled: false);

  const _WriteConfirmationOutcome.cancelled()
    : this._(
        decision: BashCommandApprovalDecision.cancelled,
        cancelled: true,
      );

  final BashCommandApprovalDecision decision;
  final bool cancelled;

  bool get approved => decision == BashCommandApprovalDecision.approved;
}

class _PersistentBashCommandOutcome {
  const _PersistentBashCommandOutcome({
    required this.exitCode,
    required this.workingDirectory,
  });

  final int exitCode;
  final String workingDirectory;
}

class _PersistentBashExecution {
  _PersistentBashExecution({
    required this.command,
    required this.workingDirectory,
    required this.stdoutStartMarker,
    required this.stdoutExitMarker,
    required this.stdoutPwdEndMarker,
    required this.stopwatch,
    this.onUpdate,
  });

  final String command;
  final String workingDirectory;
  final String stdoutStartMarker;
  final String stdoutExitMarker;
  final String stdoutPwdEndMarker;
  final Stopwatch stopwatch;
  final void Function(BashToolExecutionUpdate update)? onUpdate;
  final StringBuffer stdoutBuffer = StringBuffer();
  final StringBuffer stderrBuffer = StringBuffer();
  final Completer<_PersistentBashCommandOutcome> outcome =
      Completer<_PersistentBashCommandOutcome>();

  String _stdoutLineBuffer = '';
  String? _resolvedWorkingDirectory;
  int? _exitCode;
  bool _awaitingPwdLine = false;
  int _lastRunningEmitMs = -1;

  /// 最近一次接收到 stdout/stderr 的时间戳（ms，相对 stopwatch）。
  /// 用于停滞检测：若 45s 内没有新增输出，且尾部内容匹配交互式 prompt
  /// 启发式正则，则向 onUpdate 发送一次 stallWarning。
  int _lastOutputAtMs = 0;
  bool _stallWarningEmitted = false;
  Timer? _stallTimer;

  /// 启发式：常见交互式提示词正则。匹配末尾 1024 字符的尾段。
  static final RegExp _interactivePromptHeuristic = RegExp(
    r'(\(y/[nN]\)|\(yes/no\)|Continue\??|password\s*:|Press [a-z ]+ to continue|>>> |\? .*$|\bare you sure\b|\bproceed\b\??)',
    caseSensitive: false,
    multiLine: true,
  );

  void startStallWatcher({
    Duration interval = const Duration(seconds: 5),
    Duration threshold = const Duration(seconds: 45),
  }) {
    _lastOutputAtMs = stopwatch.elapsedMilliseconds;
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(interval, (_) {
      if (outcome.isCompleted) {
        _stallTimer?.cancel();
        _stallTimer = null;
        return;
      }
      final now = stopwatch.elapsedMilliseconds;
      if (now - _lastOutputAtMs < threshold.inMilliseconds) return;
      if (_stallWarningEmitted) return;
      // 取尾部 1024 字符做 prompt 启发式匹配，避免大输出全量正则。
      final stdoutTail = _tailString(stdoutBuffer.toString(), 1024);
      final stderrTail = _tailString(stderrBuffer.toString(), 1024);
      final match =
          _interactivePromptHeuristic.firstMatch(stdoutTail)?.group(0) ??
          _interactivePromptHeuristic.firstMatch(stderrTail)?.group(0);
      final warning = match != null
          ? '已 ${(now - _lastOutputAtMs) ~/ 1000}s 无新输出，疑似在等待交互式输入：${match.trim()}'
          : '已 ${(now - _lastOutputAtMs) ~/ 1000}s 无新输出，命令可能已停滞';
      _stallWarningEmitted = true;
      final callback = onUpdate;
      if (callback != null) {
        callback(
          BashToolExecutionUpdate(
            phase: BashToolExecutionPhase.running,
            command: command,
            workingDirectory: workingDirectory,
            stdout: stdoutBuffer.toString(),
            stderr: stderrBuffer.toString(),
            durationMs: now,
            stallWarning: warning,
          ),
        );
      }
    });
  }

  void cancelStallWatcher() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  static String _tailString(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return text.substring(text.length - maxChars);
  }

  void appendStdoutChunk(String chunk, int maxCapturedCharacters) {
    if (chunk.isNotEmpty) {
      _lastOutputAtMs = stopwatch.elapsedMilliseconds;
      _stallWarningEmitted = false;
    }
    final normalized = chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _stdoutLineBuffer += normalized;
    while (true) {
      final lineEnding = _stdoutLineBuffer.indexOf('\n');
      if (lineEnding == -1) {
        break;
      }
      final line = _stdoutLineBuffer.substring(0, lineEnding);
      _stdoutLineBuffer = _stdoutLineBuffer.substring(lineEnding + 1);
      _handleStdoutLine('$line\n', maxCapturedCharacters);
    }
  }

  void finalizeStdout(int maxCapturedCharacters) {
    if (_stdoutLineBuffer.isEmpty) {
      return;
    }
    _handleStdoutLine(_stdoutLineBuffer, maxCapturedCharacters);
    _stdoutLineBuffer = '';
  }

  void appendStderrChunk(String chunk, int maxCapturedCharacters) {
    if (chunk.isNotEmpty) {
      _lastOutputAtMs = stopwatch.elapsedMilliseconds;
      _stallWarningEmitted = false;
    }
    _appendChunk(stderrBuffer, chunk, maxCapturedCharacters);
    emitUpdate(phase: BashToolExecutionPhase.running);
  }

  void emitUpdate({
    required BashToolExecutionPhase phase,
    bool force = false,
    int? exitCode,
  }) {
    final callback = onUpdate;
    if (callback == null) {
      return;
    }
    final durationMs = stopwatch.elapsedMilliseconds;
    if (phase == BashToolExecutionPhase.running &&
        !force &&
        _lastRunningEmitMs != -1 &&
        durationMs - _lastRunningEmitMs < 160) {
      return;
    }
    if (phase == BashToolExecutionPhase.running) {
      _lastRunningEmitMs = durationMs;
    }
    callback(
      BashToolExecutionUpdate(
        phase: phase,
        command: command,
        workingDirectory: workingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        durationMs: durationMs,
        exitCode: exitCode,
      ),
    );
  }

  void completeError(Object error, int maxCapturedCharacters) {
    if (!outcome.isCompleted) {
      final message = '$error'.trim();
      if (message.isNotEmpty) {
        _appendChunk(stderrBuffer, '$message\n', maxCapturedCharacters);
      }
      outcome.complete(
        _PersistentBashCommandOutcome(
          exitCode: -1,
          workingDirectory: _resolvedWorkingDirectory ?? workingDirectory,
        ),
      );
    }
  }

  void _handleStdoutLine(String line, int maxCapturedCharacters) {
    final normalizedLine = line.endsWith('\n')
        ? line.substring(0, line.length - 1)
        : line;
    if (normalizedLine == stdoutStartMarker) {
      return;
    }
    if (normalizedLine.startsWith(stdoutExitMarker)) {
      final exitCodeText = normalizedLine
          .substring(stdoutExitMarker.length)
          .trim();
      _exitCode = int.tryParse(exitCodeText) ?? -1;
      _awaitingPwdLine = true;
      return;
    }
    if (_awaitingPwdLine) {
      _resolvedWorkingDirectory = normalizedLine.trim().isEmpty
          ? workingDirectory
          : normalizedLine.trim();
      _awaitingPwdLine = false;
      return;
    }
    if (normalizedLine == stdoutPwdEndMarker) {
      if (!outcome.isCompleted) {
        outcome.complete(
          _PersistentBashCommandOutcome(
            exitCode: _exitCode ?? 0,
            workingDirectory: _resolvedWorkingDirectory ?? workingDirectory,
          ),
        );
      }
      return;
    }
    _appendChunk(stdoutBuffer, line, maxCapturedCharacters);
    emitUpdate(phase: BashToolExecutionPhase.running);
  }

  static void _appendChunk(
    StringBuffer buffer,
    String chunk,
    int maxCapturedCharacters,
  ) {
    if (buffer.length >= maxCapturedCharacters) {
      return;
    }
    final allowed = maxCapturedCharacters - buffer.length;
    if (chunk.length <= allowed) {
      buffer.write(chunk);
      return;
    }
    buffer
      ..write(chunk.substring(0, allowed))
      ..write('\n...[output truncated]');
  }
}

class _PersistentBashSession {
  _PersistentBashSession({
    required this.process,
    required this.currentWorkingDirectory,
  });

  final Process process;
  String currentWorkingDirectory;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  _PersistentBashExecution? activeExecution;
}

class _CancelledPersistentBashExecution implements Exception {
  const _CancelledPersistentBashExecution();
}

class AiBashToolService {
  AiBashToolService();

  static const int defaultTimeoutMs = 120000;
  // 2026-05 — `bashOutputMaxBytes` 设置项：从 SettingsController 注入。
  // 旧默认 32000；放宽到 200_000，与 snapshot.defaultBashOutputMaxBytes 对齐。
  int maxCapturedCharacters = 200000;
  int writeConfirmationTimeoutMs = 300000;
  int fastPathWriteAnalysisThreshold = 512;
  final AiSandboxService sandboxService = AiSandboxService();
  final Map<String, _PersistentBashSession> _persistentSessions =
      <String, _PersistentBashSession>{};
  int _persistentMarkerCounter = 0;
  int _lastSeenProxyRevision = SystemProxyResolver.instance.revision.value;
  bool _proxyListenerRegistered = false;

  /// Lazy 注册：仅当本实例真的会启动 shell 子进程（execute / 持久 session）
  /// 才订阅代理变更。`AiPromptBuilder._bashWriteAnalyzer` 这种只用 analyze
  /// 的纯静态用途无需订阅。
  void _ensureProxyListenerAttached() {
    if (_proxyListenerRegistered) return;
    SystemProxyResolver.instance.revision.addListener(_onProxyRevisionChanged);
    _proxyListenerRegistered = true;
  }

  void _onProxyRevisionChanged() {
    final next = SystemProxyResolver.instance.revision.value;
    if (next == _lastSeenProxyRevision) return;
    _lastSeenProxyRevision = next;
    // Snapshot keys：在异步关闭过程中可能新增 session。
    final ids = _persistentSessions.keys.toList(growable: false);
    for (final id in ids) {
      unawaited(_closePersistentSession(id));
    }
  }

  Future<BashToolExecutionResult> execute({
    required String command,
    String? sessionId,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<BashCommandApprovalDecision> Function(
      BashCommandApprovalRequest request,
    )?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = defaultTimeoutMs,
    String? toolCallId,
  }) async {
    _ensureProxyListenerAttached();
    final normalizedCommand = command.trim();
    final normalizedSessionId = (sessionId ?? '').trim();
    var shouldUsePersistentSession = normalizedSessionId.isNotEmpty;
    final rawWorkingDirectory = (workingDirectory ?? '').trim();
    final normalizedWorkingDirectory = rawWorkingDirectory.isEmpty
        ? (shouldUsePersistentSession
              ? ''
              : OpenHandPaths.applicationDirectoryPath())
        : OpenHandPaths.normalizePath(
            rawWorkingDirectory,
            defaultPath: OpenHandPaths.applicationDirectoryPath(),
          );
    final displayedWorkingDirectory = normalizedWorkingDirectory.isEmpty
        ? _persistentSessions[normalizedSessionId]?.currentWorkingDirectory ??
              OpenHandPaths.applicationDirectoryPath()
        : normalizedWorkingDirectory;
    if (normalizedCommand.isEmpty) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: normalizedCommand,
        workingDirectory: displayedWorkingDirectory,
        stdout: '',
        stderr: 'The bash tool requires a non-empty command.',
        durationMs: 0,
        writeAnalysisReason: 'empty command',
      );
    }

    final writeAnalysis = analyzeWriteCommand(normalizedCommand);

    for (final rule in denyRules) {
      if (rule.matches(normalizedCommand)) {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.denied,
          command: normalizedCommand,
          workingDirectory: displayedWorkingDirectory,
          stdout: '',
          stderr:
              'The command was blocked because it matched a deny rule configured by the user.',
          durationMs: 0,
          matchedRuleId: rule.id,
          matchedRulePattern: rule.pattern,
          isWriteCommand: writeAnalysis.isWrite,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
    }
    final isWriteCommand = writeAnalysis.isWrite;
    final launchSpec = await _prepareLaunchSpec(
      command: normalizedCommand,
      workingDirectory: displayedWorkingDirectory,
    );
    Future<void> closeLaunchProxy() async {
      await launchSpec.proxyLease?.close();
    }

    final sandboxMetadata = launchSpec.metadata;
    if (launchSpec.blocked) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.denied,
        command: normalizedCommand,
        workingDirectory: displayedWorkingDirectory,
        stdout: '',
        stderr: launchSpec.reason,
        durationMs: 0,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
        sandboxMetadata: sandboxMetadata,
      );
    }
    if (launchSpec.applied) {
      shouldUsePersistentSession = false;
    }
    if (requireWriteConfirmation && isWriteCommand) {
      if (launchSpec.applied &&
          sandboxService.settings.autoAllowBashIfSandboxed) {
        // The OS sandbox is active and the user explicitly allowed sandboxed
        // Bash to bypass the write-confirmation prompt.
      } else {
        late final _WriteConfirmationOutcome outcome;
        try {
          final approvalFuture =
              (confirmWriteCommand
                          ?.call(
                            BashCommandApprovalRequest(
                              command: normalizedCommand,
                              workingDirectory: displayedWorkingDirectory,
                              isWriteCommand: true,
                            ),
                          )
                          .timeout(
                            Duration(milliseconds: writeConfirmationTimeoutMs),
                          ) ??
                      Future<BashCommandApprovalDecision>.value(
                        BashCommandApprovalDecision.rejected,
                      ))
                  .then<_WriteConfirmationOutcome>(
                    (decision) =>
                        _WriteConfirmationOutcome.fromDecision(decision),
                  );
          if (cancelSignal == null) {
            outcome = await approvalFuture;
          } else {
            outcome = await Future.any<_WriteConfirmationOutcome>([
              approvalFuture,
              cancelSignal.then(
                (_) => const _WriteConfirmationOutcome.cancelled(),
              ),
            ]);
          }
        } on TimeoutException {
          await closeLaunchProxy();
          return BashToolExecutionResult(
            status: BashToolExecutionStatus.timedOut,
            command: normalizedCommand,
            workingDirectory: displayedWorkingDirectory,
            stdout: '',
            stderr:
                'The write-command confirmation prompt timed out before the user responded. '
                'The bash command was NOT executed. The user did not explicitly approve or reject. '
                'Re-issue the command only if you still need this side effect; otherwise propose a safer alternative.',
            durationMs: 0,
            isWriteCommand: isWriteCommand,
            writeAnalysisReason: writeAnalysis.reason,
            sandboxMetadata: sandboxMetadata,
          );
        }
        if (outcome.cancelled) {
          await closeLaunchProxy();
          return BashToolExecutionResult(
            status: BashToolExecutionStatus.cancelled,
            command: normalizedCommand,
            workingDirectory: displayedWorkingDirectory,
            stdout: '',
            stderr:
                'The bash command was cancelled at the session level (user pressed Stop or sent a new prompt) '
                'before the write-command confirmation prompt was answered. The command did NOT run.',
            durationMs: 0,
            isWriteCommand: isWriteCommand,
            writeAnalysisReason: writeAnalysis.reason,
            sandboxMetadata: sandboxMetadata,
          );
        }
        switch (outcome.decision) {
          case BashCommandApprovalDecision.approved:
            break;
          case BashCommandApprovalDecision.rejected:
            await closeLaunchProxy();
            return BashToolExecutionResult(
              status: BashToolExecutionStatus.rejected,
              command: normalizedCommand,
              workingDirectory: displayedWorkingDirectory,
              stdout: '',
              stderr:
                  'The user explicitly rejected the write-command confirmation. '
                  'The bash command was NOT executed. Do NOT retry without first '
                  'asking the user what they would prefer instead.',
              durationMs: 0,
              isWriteCommand: isWriteCommand,
              writeAnalysisReason: writeAnalysis.reason,
              sandboxMetadata: sandboxMetadata,
            );
          case BashCommandApprovalDecision.dismissed:
            await closeLaunchProxy();
            return BashToolExecutionResult(
              status: BashToolExecutionStatus.rejected,
              command: normalizedCommand,
              workingDirectory: displayedWorkingDirectory,
              stdout: '',
              stderr:
                  'The user dismissed the write-command confirmation prompt without choosing approve or reject (Esc / dialog dismissed). '
                  'Treat this as "decision deferred": the command did NOT run. Pause this branch and confirm intent before retrying.',
              durationMs: 0,
              isWriteCommand: isWriteCommand,
              writeAnalysisReason: writeAnalysis.reason,
              sandboxMetadata: sandboxMetadata,
            );
          case BashCommandApprovalDecision.timedOut:
            await closeLaunchProxy();
            return BashToolExecutionResult(
              status: BashToolExecutionStatus.timedOut,
              command: normalizedCommand,
              workingDirectory: displayedWorkingDirectory,
              stdout: '',
              stderr:
                  'The write-command confirmation prompt timed out before the user responded. '
                  'The bash command was NOT executed. The user neither approved nor rejected explicitly.',
              durationMs: 0,
              isWriteCommand: isWriteCommand,
              writeAnalysisReason: writeAnalysis.reason,
              sandboxMetadata: sandboxMetadata,
            );
          case BashCommandApprovalDecision.cancelled:
            await closeLaunchProxy();
            return BashToolExecutionResult(
              status: BashToolExecutionStatus.cancelled,
              command: normalizedCommand,
              workingDirectory: displayedWorkingDirectory,
              stdout: '',
              stderr:
                  'The bash command was cancelled before the write-command confirmation prompt was answered. The command did NOT run.',
              durationMs: 0,
              isWriteCommand: isWriteCommand,
              writeAnalysisReason: writeAnalysis.reason,
              sandboxMetadata: sandboxMetadata,
            );
        }
      }
    }

    if (shouldUsePersistentSession) {
      final persistentResult = await _executeWithPersistentSession(
        sessionId: normalizedSessionId,
        command: normalizedCommand,
        requestedWorkingDirectory: normalizedWorkingDirectory,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
        onUpdate: onUpdate,
        cancelSignal: cancelSignal,
        timeoutMs: timeoutMs,
        toolCallId: toolCallId,
      );
      // If the persistent session died unexpectedly, retry with a one-shot
      // subprocess so the user doesn't see a bare "bad state" error.
      if (persistentResult.exitCode == -1 &&
          persistentResult.status == BashToolExecutionStatus.failed &&
          persistentResult.stderr.contains(
            'persistent bash session exited unexpectedly',
          )) {
        // Fall through to the one-shot execution below.
      } else {
        return persistentResult;
      }
    }

    final stopwatch = Stopwatch()..start();
    late final Process process;
    try {
      process = await _startProcess(launchSpec);
    } on ProcessException catch (error) {
      await closeLaunchProxy();
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: normalizedCommand,
        workingDirectory: launchSpec.workingDirectory,
        stdout: '',
        stderr: error.message,
        durationMs: stopwatch.elapsedMilliseconds,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
        sandboxMetadata: sandboxMetadata,
      );
    }

    // 子进程派生成功后，把 pid 与 killer 回填到执行登记中心，让 UI 可以显示
    // 真实 pid，并支持用户从工具卡片单独终止此次 Bash 调用（SIGTERM →
    // 500ms 后 SIGKILL）。无 toolCallId 时跳过。
    final registeredToolCallId = toolCallId;
    if (registeredToolCallId != null && registeredToolCallId.isNotEmpty) {
      AiToolExecutionRegistry.instance.attachPid(
        registeredToolCallId,
        process.pid,
      );
      AiToolExecutionRegistry.instance.attachKiller(
        registeredToolCallId,
        () async => _killProcess(process),
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var lastRunningEmitMs = -1;
    var lastOutputAtMs = 0;
    var stallWarningEmitted = false;

    void emitUpdate({
      required BashToolExecutionPhase phase,
      bool force = false,
      int? exitCode,
      String? stallWarning,
    }) {
      if (onUpdate == null) {
        return;
      }
      final durationMs = stopwatch.elapsedMilliseconds;
      if (phase == BashToolExecutionPhase.running &&
          !force &&
          stallWarning == null &&
          lastRunningEmitMs != -1 &&
          durationMs - lastRunningEmitMs < 160) {
        return;
      }
      if (phase == BashToolExecutionPhase.running && stallWarning == null) {
        lastRunningEmitMs = durationMs;
      }
      onUpdate(
        BashToolExecutionUpdate(
          phase: phase,
          command: normalizedCommand,
          workingDirectory: launchSpec.workingDirectory,
          stdout: stdoutBuffer.toString(),
          stderr: stderrBuffer.toString(),
          durationMs: durationMs,
          exitCode: exitCode,
          stallWarning: stallWarning,
        ),
      );
    }

    emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    });
    final stallTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = stopwatch.elapsedMilliseconds;
      if (now - lastOutputAtMs < 45 * 1000) return;
      if (stallWarningEmitted) return;
      final stdoutTail = _PersistentBashExecution._tailString(
        stdoutBuffer.toString(),
        1024,
      );
      final stderrTail = _PersistentBashExecution._tailString(
        stderrBuffer.toString(),
        1024,
      );
      final match =
          _PersistentBashExecution._interactivePromptHeuristic
              .firstMatch(stdoutTail)
              ?.group(0) ??
          _PersistentBashExecution._interactivePromptHeuristic
              .firstMatch(stderrTail)
              ?.group(0);
      final warning = match != null
          ? '已 ${(now - lastOutputAtMs) ~/ 1000}s 无新输出，疑似在等待交互式输入：${match.trim()}'
          : '已 ${(now - lastOutputAtMs) ~/ 1000}s 无新输出，命令可能已停滞';
      stallWarningEmitted = true;
      emitUpdate(
        phase: BashToolExecutionPhase.running,
        force: true,
        stallWarning: warning,
      );
    });
    final stdoutSubscription = process.stdout
        .transform(_shellOutputDecoder)
        .listen((chunk) {
          if (chunk.isNotEmpty) {
            lastOutputAtMs = stopwatch.elapsedMilliseconds;
            stallWarningEmitted = false;
          }
          _appendChunk(stdoutBuffer, chunk);
          emitUpdate(phase: BashToolExecutionPhase.running);
        });
    final stderrSubscription = process.stderr
        .transform(_shellOutputDecoder)
        .listen((chunk) {
          if (chunk.isNotEmpty) {
            lastOutputAtMs = stopwatch.elapsedMilliseconds;
            stallWarningEmitted = false;
          }
          _appendChunk(stderrBuffer, chunk);
          emitUpdate(phase: BashToolExecutionPhase.running);
        });

    int? exitCode;
    var cancelled = false;
    var timedOut = false;
    try {
      final waitForExit = process.exitCode.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () async {
          timedOut = true;
          _killProcess(process);
          try {
            await process.exitCode.timeout(const Duration(seconds: 2));
          } catch (_) {
            // Ignore cleanup failures after forcing termination.
          }
          return -1;
        },
      );
      if (cancelSignal != null) {
        exitCode = await Future.any<int>([
          waitForExit,
          cancelSignal.then((_) async {
            cancelled = true;
            _killProcess(process);
            try {
              await process.exitCode.timeout(const Duration(seconds: 2));
            } catch (_) {
              // Ignore cleanup failures after forcing termination.
            }
            return -2;
          }),
        ]);
      } else {
        exitCode = await waitForExit;
      }
    } finally {
      progressTimer.cancel();
      stallTimer.cancel();
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      stopwatch.stop();
      await closeLaunchProxy();
    }

    if (cancelled) {
      emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: exitCode,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: normalizedCommand,
        workingDirectory: launchSpec.workingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString().isEmpty
            ? 'The command was cancelled by the user.'
            : stderrBuffer.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitCode: exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
        sandboxMetadata: sandboxMetadata,
      );
    }

    if (timedOut) {
      emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: exitCode,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: normalizedCommand,
        workingDirectory: launchSpec.workingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString().isEmpty
            ? 'The command timed out before completion.'
            : stderrBuffer.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitCode: exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
        sandboxMetadata: sandboxMetadata,
      );
    }

    emitUpdate(
      phase: BashToolExecutionPhase.completed,
      force: true,
      exitCode: exitCode,
    );
    return BashToolExecutionResult(
      status: exitCode == 0
          ? BashToolExecutionStatus.success
          : BashToolExecutionStatus.failed,
      command: normalizedCommand,
      workingDirectory: launchSpec.workingDirectory,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      durationMs: stopwatch.elapsedMilliseconds,
      exitCode: exitCode,
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: writeAnalysis.reason,
      sandboxMetadata: sandboxMetadata,
    );
  }

  Future<BashToolExecutionResult> _executeWithPersistentSession({
    required String sessionId,
    required String command,
    required String requestedWorkingDirectory,
    required bool isWriteCommand,
    required String writeAnalysisReason,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    required int timeoutMs,
    String? toolCallId,
  }) async {
    final fallbackWorkingDirectory = requestedWorkingDirectory.isEmpty
        ? OpenHandPaths.applicationDirectoryPath()
        : requestedWorkingDirectory;
    late final _PersistentBashSession session;
    try {
      session = await _ensurePersistentSession(
        sessionId: sessionId,
        initialWorkingDirectory: fallbackWorkingDirectory,
      );
    } on ProcessException catch (error) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: fallbackWorkingDirectory,
        stdout: '',
        stderr: error.message,
        durationMs: 0,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    }
    final effectiveWorkingDirectory = requestedWorkingDirectory.isEmpty
        ? session.currentWorkingDirectory
        : requestedWorkingDirectory;
    if (session.activeExecution != null) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: effectiveWorkingDirectory,
        stdout: '',
        stderr: 'Another bash command is already running for this session.',
        durationMs: 0,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    }

    final markerToken =
        'openhand_${DateTime.now().microsecondsSinceEpoch}_${_persistentMarkerCounter++}';
    final execution = _PersistentBashExecution(
      command: command,
      workingDirectory: effectiveWorkingDirectory,
      stdoutStartMarker: '__OPENHAND_CMD_START__$markerToken',
      stdoutExitMarker: '__OPENHAND_EXIT__$markerToken:',
      stdoutPwdEndMarker: '__OPENHAND_PWD_END__$markerToken',
      stopwatch: Stopwatch()..start(),
      onUpdate: onUpdate,
    );
    session.activeExecution = execution;
    execution.emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    execution.startStallWatcher();
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      execution.emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    });

    // 持久 session 路径接入登记中心：kill 时关闭整个 shell；下次同 sessionId 的
    // 调用会经 _ensurePersistentSession 自动重建，不影响后续执行。
    final registeredToolCallId = toolCallId;
    if (registeredToolCallId != null && registeredToolCallId.isNotEmpty) {
      AiToolExecutionRegistry.instance.attachPid(
        registeredToolCallId,
        session.process.pid,
      );
      AiToolExecutionRegistry.instance.attachKiller(
        registeredToolCallId,
        () async => _closePersistentSession(sessionId),
      );
    }

    try {
      session.process.stdin.write(
        _buildPersistentCommandScript(
          command: command,
          markerToken: markerToken,
          workingDirectory: requestedWorkingDirectory,
        ),
      );
      session.process.stdin.write('\n');
      // Flush the IOSink so the shell receives the script immediately.
      // Without an explicit flush the OS buffers may delay delivery under
      // low-throughput conditions, causing spurious marker timeouts.
      await session.process.stdin.flush();
      final waitForCompletion = execution.outcome.future.timeout(
        Duration(milliseconds: timeoutMs),
      );
      late final _PersistentBashCommandOutcome outcome;
      if (cancelSignal == null) {
        outcome = await waitForCompletion;
      } else {
        outcome = await Future.any<_PersistentBashCommandOutcome>([
          waitForCompletion,
          cancelSignal.then(
            (_) => throw const _CancelledPersistentBashExecution(),
          ),
        ]);
      }
      execution.finalizeStdout(maxCapturedCharacters);
      execution.stopwatch.stop();
      session.currentWorkingDirectory = outcome.workingDirectory;
      execution.emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: outcome.exitCode,
      );
      return BashToolExecutionResult(
        status: outcome.exitCode == 0
            ? BashToolExecutionStatus.success
            : BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: outcome.workingDirectory,
        stdout: execution.stdoutBuffer.toString(),
        stderr: execution.stderrBuffer.toString(),
        durationMs: execution.stopwatch.elapsedMilliseconds,
        exitCode: outcome.exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    } on TimeoutException {
      execution.finalizeStdout(maxCapturedCharacters);
      execution.stopwatch.stop();
      await _closePersistentSession(sessionId);
      execution.emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: -1,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: command,
        workingDirectory: effectiveWorkingDirectory,
        stdout: execution.stdoutBuffer.toString(),
        stderr: execution.stderrBuffer.toString().trim().isEmpty
            ? 'The command timed out before completion.'
            : execution.stderrBuffer.toString(),
        durationMs: execution.stopwatch.elapsedMilliseconds,
        exitCode: -1,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    } on _CancelledPersistentBashExecution {
      execution.finalizeStdout(maxCapturedCharacters);
      execution.stopwatch.stop();
      await _closePersistentSession(sessionId);
      execution.emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: -2,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: command,
        workingDirectory: effectiveWorkingDirectory,
        stdout: execution.stdoutBuffer.toString(),
        stderr: execution.stderrBuffer.toString().trim().isEmpty
            ? 'The command was cancelled by the user.'
            : execution.stderrBuffer.toString(),
        durationMs: execution.stopwatch.elapsedMilliseconds,
        exitCode: -2,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    } catch (error) {
      execution.finalizeStdout(maxCapturedCharacters);
      execution.stopwatch.stop();
      await _closePersistentSession(sessionId);
      execution.emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: effectiveWorkingDirectory,
        stdout: execution.stdoutBuffer.toString(),
        stderr: execution.stderrBuffer.toString().trim().isEmpty
            ? '$error'
            : execution.stderrBuffer.toString(),
        durationMs: execution.stopwatch.elapsedMilliseconds,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    } finally {
      progressTimer.cancel();
      execution.cancelStallWatcher();
      if (identical(session.activeExecution, execution)) {
        session.activeExecution = null;
      }
    }
  }

  Future<AiSandboxLaunchSpec> _prepareLaunchSpec({
    required String command,
    required String workingDirectory,
  }) {
    if (Platform.isWindows) {
      // Windows 一次性命令也注入用户级代理 env，让 curl/git/npm 等
      // 标准工具按系统设置走代理；sandbox 服务在 Windows 上目前不接管。
      final proxyEnv = SystemProxyResolver.instance
          .resolveSubprocessEnvironment();
      return Future<AiSandboxLaunchSpec>.value(
        AiSandboxLaunchSpec.unsandboxed(
          executable: 'cmd',
          arguments: <String>['/c', command],
          workingDirectory: workingDirectory,
          environment: proxyEnv,
        ),
      );
    }
    final shellExecutable = _resolveShellExecutable();
    return sandboxService.prepareShellCommand(
      toolName: 'Bash',
      shellExecutable: shellExecutable,
      shellArguments: <String>['-lc', command],
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  Future<Process> _startProcess(AiSandboxLaunchSpec launchSpec) {
    if (Platform.isWindows) {
      return Process.start(
        launchSpec.executable,
        launchSpec.arguments,
        workingDirectory: launchSpec.workingDirectory,
        environment: launchSpec.environment.isEmpty
            ? null
            : launchSpec.environment,
      );
    }
    return _spawnPosixProcess(
      executable: launchSpec.executable,
      arguments: launchSpec.arguments,
      workingDirectory: launchSpec.workingDirectory,
      environment: launchSpec.environment.isEmpty
          ? null
          : launchSpec.environment,
    );
  }

  /// 在 POSIX 平台上若发现 `setsid` 可用，则用其包裹 shell，进而把整个命令树
  /// 放进**新的进程组**。对该 pid 调用 [_killProcess] 时会顺带 `kill -KILL -pid`，
  /// 即按进程组发送信号，能彻底回收 shell 派生出的子孙进程（例如长跑的
  /// `flutter run`、`tail -f`、`ssh` 等），避免出现"按 Stop 后子孙仍在运行"的
  /// 僵尸场景。当 setsid 不可用（少数老版本 macOS / 自定义环境）时安静回退到
  /// 直接派生，行为与之前一致。
  Future<Process> _spawnPosixShell({
    required String shellExecutable,
    required List<String> shellArgs,
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    return _spawnPosixProcess(
      executable: shellExecutable,
      arguments: shellArgs,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  Future<Process> _spawnPosixProcess({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    final setsidPath = await _resolveSetsidPath();
    if (setsidPath != null) {
      final process = await Process.start(
        setsidPath,
        <String>[executable, ...arguments],
        workingDirectory: workingDirectory,
        environment: environment,
      );
      _processGroupLeaders.add(process.pid);
      // 进程退出后及时清理标记，避免长会话下集合无界增长。
      process.exitCode
          .whenComplete(() => _processGroupLeaders.remove(process.pid))
          .ignore();
      return process;
    }
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  /// 缓存 setsid 路径解析结果（一次进程内只探测一次）。
  static Future<String?>? _setsidProbe;
  static final Set<int> _processGroupLeaders = <int>{};

  static Future<String?> _resolveSetsidPath() {
    if (_setsidProbe != null) return _setsidProbe!;
    _setsidProbe = () async {
      if (Platform.isWindows) return null;
      // /usr/bin/setsid 在 GNU/Linux 与较新 macOS 都常见；自定义环境可能在
      // /usr/local/bin 或 /opt/homebrew/bin。逐一探测，找不到就返回 null。
      const candidates = <String>[
        '/usr/bin/setsid',
        '/usr/local/bin/setsid',
        '/opt/homebrew/bin/setsid',
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) return candidate;
      }
      // 最后兜底：通过 `command -v setsid` 在 PATH 里找。
      try {
        final result = await Process.run('/bin/sh', <String>[
          '-lc',
          'command -v setsid 2>/dev/null',
        ]).timeout(const Duration(seconds: 2));
        final stdout = (result.stdout as String).trim();
        if (stdout.isNotEmpty && File(stdout).existsSync()) return stdout;
      } catch (_) {}
      return null;
    }();
    return _setsidProbe!;
  }

  Future<_PersistentBashSession> _ensurePersistentSession({
    required String sessionId,
    required String initialWorkingDirectory,
  }) async {
    final existing = _persistentSessions[sessionId];
    if (existing != null) {
      return existing;
    }
    final shellExecutable = Platform.isWindows
        ? 'cmd'
        : _resolveShellExecutable();
    final shellArgs = Platform.isWindows
        ? const <String>['/Q']
        : const <String>[];
    // 持久 shell 是会话级长寿对象。启动时把当前用户级代理注入为环境变量，
    // 让会话内的 curl / wget / git / npm / pip 等命令默认走代理；切换代理
    // 设置时通过 _restartPersistentSessionForProxyChange 重启 shell。
    final proxyEnv = SystemProxyResolver.instance
        .resolveSubprocessEnvironment();
    final mergedEnvironment = proxyEnv.isEmpty
        ? null
        : <String, String>{
            ...Platform.environment,
            ...proxyEnv,
          };
    final process = Platform.isWindows
        ? await Process.start(
            shellExecutable,
            shellArgs,
            workingDirectory: initialWorkingDirectory,
            environment: mergedEnvironment,
          )
        : await _spawnPosixShell(
            shellExecutable: shellExecutable,
            shellArgs: shellArgs,
            workingDirectory: initialWorkingDirectory,
            environment: mergedEnvironment,
          );
    final session = _PersistentBashSession(
      process: process,
      currentWorkingDirectory: initialWorkingDirectory,
    );
    // For Unix shells, disable glob expansion so that commands containing
    // special characters (e.g. osascript with AppleScript strings that include
    // brackets, asterisks, question marks) don't trigger "bad pattern" errors.
    if (!Platform.isWindows) {
      process.stdin.write(
        'set -o noglob 2>/dev/null || setopt noglob 2>/dev/null || true\n',
      );
      // Flush so the shell processes the noglob setup before the first command.
      try {
        await process.stdin.flush();
      } catch (error, stack) {
        silentLog(
          'ai_bash_tool_service',
          'flush noglob setup to shell stdin',
          error,
          stack,
        );
      }
    }
    session.stdoutSubscription = process.stdout
        .transform(_shellOutputDecoder)
        .listen((chunk) {
          session.activeExecution?.appendStdoutChunk(
            chunk,
            maxCapturedCharacters,
          );
        });
    session.stderrSubscription = process.stderr
        .transform(_shellOutputDecoder)
        .listen((chunk) {
          session.activeExecution?.appendStderrChunk(
            chunk,
            maxCapturedCharacters,
          );
        });
    process.exitCode.then((_) {
      final activeExecution = session.activeExecution;
      if (activeExecution != null && !activeExecution.outcome.isCompleted) {
        activeExecution.completeError(
          StateError('The persistent bash session exited unexpectedly.'),
          maxCapturedCharacters,
        );
      }
      // Cancel subscriptions when process exits to avoid dangling listeners.
      unawaited(session.stdoutSubscription?.cancel());
      unawaited(session.stderrSubscription?.cancel());
      _persistentSessions.remove(sessionId);
    });
    _persistentSessions[sessionId] = session;
    return session;
  }

  String _buildPersistentCommandScript({
    required String command,
    required String markerToken,
    required String workingDirectory,
  }) {
    if (Platform.isWindows) {
      return _buildWindowsPersistentCommandScript(
        command: command,
        markerToken: markerToken,
        workingDirectory: workingDirectory,
      );
    }
    final startMarker = _quoteShellString('__OPENHAND_CMD_START__$markerToken');
    final exitMarker = _quoteShellString('__OPENHAND_EXIT__$markerToken');
    final pwdEndMarker = _quoteShellString('__OPENHAND_PWD_END__$markerToken');
    // Determine if the command needs special wrapping to avoid shell
    // mis-interpretation.  Commands that embed AppleScript, multi-line
    // strings, or heavy quoting are routed through a temporary script file
    // or eval-based wrapper so that zsh/bash doesn't choke on glob
    // patterns, unmatched quotes, or nested shell expansions.
    final needsSafeWrap = _commandNeedsSafeWrap(command);
    final buffer = StringBuffer()
      ..writeln("printf '%s\\n' $startMarker")
      ..writeln('__OPENHAND_EXIT_CODE=0');
    if (workingDirectory.trim().isNotEmpty) {
      buffer.writeln('if cd ${_quoteShellString(workingDirectory)}; then');
      if (needsSafeWrap) {
        _writeSafeWrappedCommand(buffer, command, markerToken);
      } else {
        buffer.writeln(command);
      }
      buffer
        ..writeln(r'  __OPENHAND_EXIT_CODE=$?')
        ..writeln('else')
        ..writeln(r'  __OPENHAND_EXIT_CODE=$?')
        ..writeln('fi');
    } else {
      if (needsSafeWrap) {
        _writeSafeWrappedCommand(buffer, command, markerToken);
      } else {
        buffer.writeln(command);
      }
      buffer.writeln(r'__OPENHAND_EXIT_CODE=$?');
    }
    buffer
      ..writeln("printf '\\n%s:%s\\n' $exitMarker \"\$__OPENHAND_EXIT_CODE\"")
      ..writeln('pwd')
      ..writeln("printf '%s\\n' $pwdEndMarker");
    return buffer.toString().trimRight();
  }

  /// Build the Windows-specific persistent command script using cmd markers.
  String _buildWindowsPersistentCommandScript({
    required String command,
    required String markerToken,
    required String workingDirectory,
  }) {
    final buffer = StringBuffer()
      ..writeln('echo __OPENHAND_CMD_START__$markerToken');
    if (workingDirectory.trim().isNotEmpty) {
      // Double-quote the path to prevent injection via shell metacharacters
      // (&, |, etc.) that may appear in directory names.
      final escapedWorkDir = workingDirectory.replaceAll('"', '""');
      buffer
        ..writeln('cd /d "$escapedWorkDir" && (')
        ..writeln(command)
        ..writeln(')')
        ..writeln('set __OPENHAND_EXIT_CODE=%errorlevel%');
    } else {
      buffer
        ..writeln(command)
        ..writeln('set __OPENHAND_EXIT_CODE=%errorlevel%');
    }
    buffer
      ..writeln('echo __OPENHAND_EXIT__$markerToken:%__OPENHAND_EXIT_CODE%')
      ..writeln('cd')
      ..writeln('echo __OPENHAND_PWD_END__$markerToken');
    return buffer.toString().trimRight();
  }

  /// Returns `true` if the command contains patterns that are likely to
  /// confuse the shell when injected directly into a persistent session
  /// stdin stream.  Such commands are routed through a temporary script
  /// file so that the shell processes them atomically.
  bool _commandNeedsSafeWrap(String command) {
    // Multi-line commands (embedded newlines beyond trailing)
    final trimmed = command.trimRight();
    if (trimmed.contains('\n')) {
      return true;
    }
    // Commands containing heavy quoting that is likely to interact badly
    // with the outer shell wrapper.  The parentheses around the second
    // clause make the grouping explicit — relying on `&&`-binds-tighter-
    // than-`||` precedence has tripped reviewers in the past and is easy
    // to break with a future refactor.
    if (command.contains("'\\'") ||
        (command.contains("'") && command.contains('"'))) {
      // Nested quoting patterns common in osascript invocations.
      return true;
    }
    // Commands starting with osascript, which commonly contain AppleScript
    // strings with special characters ([, ], *, ?).
    if (RegExp(r'^\s*(osascript|automator)\b').hasMatch(command)) {
      return true;
    }
    return false;
  }

  /// Writes a safely-wrapped version of [command] into [buffer].
  /// Uses a temporary script file approach: writes the command to a temp
  /// file, executes it with the appropriate shell, then removes the file.
  void _writeSafeWrappedCommand(
    StringBuffer buffer,
    String command,
    String markerToken,
  ) {
    // Use a heredoc with a single-quoted delimiter to write the command into
    // a temp script file.  The single-quoted heredoc tag ensures the shell
    // performs zero expansion on the script body, preserving all special
    // characters, quotes, variables, and glob patterns literally.
    //
    // To prevent heredoc injection (where the command body itself contains
    // the heredoc delimiter), we generate a unique tag that is guaranteed
    // not to appear in the command.  If by some chance the base tag exists
    // in the command, we append an incrementing suffix until a collision-
    // free tag is found.
    var heredocTag = '__OPENHAND_SCRIPT_${markerToken}__';
    var tagSuffix = 0;
    while (command.contains(heredocTag)) {
      tagSuffix += 1;
      heredocTag =
          '__OPENHAND_SCRIPT_${markerToken}_$tagSuffix'
          '__';
    }
    final tmpScriptPath = '/tmp/.openhand_cmd_$markerToken.sh';
    final quotedTmp = _quoteShellString(tmpScriptPath);
    buffer
      ..writeln('cat > $quotedTmp << ${_quoteShellString(heredocTag)}')
      ..writeln(command)
      ..writeln(heredocTag)
      ..writeln('chmod +x $quotedTmp')
      // Install a best-effort trap so the temp script is removed even when
      // the wrapper shell receives a signal before it reaches the explicit
      // `rm -f` below. The trap is local to the current shell context.
      ..writeln('trap "rm -f $quotedTmp" EXIT INT TERM HUP')
      // Run the script and immediately capture its exit code before any
      // cleanup commands can overwrite it.
      ..writeln('${_resolveShellExecutable()} $quotedTmp')
      ..writeln(r'__OPENHAND_WRAP_RC=$?')
      ..writeln('rm -f $quotedTmp')
      ..writeln('trap - EXIT INT TERM HUP')
      // Propagate the original exit code via a sub-shell exit.
      ..writeln(r'(exit $__OPENHAND_WRAP_RC)');
  }

  String _quoteShellString(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  Future<void> _closePersistentSession(String sessionId) async {
    final session = _persistentSessions.remove(sessionId);
    if (session == null) {
      return;
    }
    // Cancel subscriptions first to avoid reading from a killed process.
    await session.stdoutSubscription?.cancel();
    await session.stderrSubscription?.cancel();
    _killProcess(session.process);
  }

  String _resolveShellExecutable() {
    final environmentShell = Platform.environment['SHELL']?.trim() ?? '';
    if (environmentShell.isNotEmpty) {
      return environmentShell;
    }
    const shellCandidates = <String>['/bin/zsh', '/bin/bash', '/bin/sh'];
    for (final candidate in shellCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return '/bin/sh';
  }

  void _appendChunk(StringBuffer buffer, String chunk) {
    if (buffer.length >= maxCapturedCharacters) {
      return;
    }
    final allowed = maxCapturedCharacters - buffer.length;
    if (chunk.length <= allowed) {
      buffer.write(chunk);
      return;
    }
    buffer
      ..write(chunk.substring(0, allowed))
      ..write('\n...[output truncated]');
  }

  BashWriteAnalysis analyzeWriteCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) {
      return const BashWriteAnalysis.readOnly('empty command');
    }
    final fastPath = _fastPathWriteAnalysis(normalized);
    if (fastPath != null) {
      return fastPath;
    }
    if (Platform.isWindows) {
      return _CmdWriteCommandAnalyzer(normalized).analyze();
    }
    return _ShellWriteCommandAnalyzer(normalized).analyze();
  }

  bool isLikelyWriteCommand(String command) {
    return analyzeWriteCommand(command).isWrite;
  }

  BashWriteAnalysis? _fastPathWriteAnalysis(String command) {
    if (command.length < fastPathWriteAnalysisThreshold) {
      return null;
    }
    if (command.contains('<<')) {
      return const BashWriteAnalysis.write(
        'fast-path redirection or heredoc command',
      );
    }
    if (_containsPotentiallySafeRedirectionTarget(command)) {
      return null;
    }
    if (RegExp(r'(^|[;&|]\s*|\s)\d*(>|>>|>\||<>)\s+\S').hasMatch(command)) {
      return const BashWriteAnalysis.write(
        'fast-path redirection or heredoc command',
      );
    }
    return null;
  }

  bool _containsPotentiallySafeRedirectionTarget(String command) {
    return command.contains('/dev/null') ||
        command.contains('/dev/stdout') ||
        command.contains('/dev/stderr') ||
        command.contains('/dev/fd/') ||
        command.contains('/proc/self/fd/') ||
        command.contains('>&');
  }

  void dispose() {
    if (_proxyListenerRegistered) {
      SystemProxyResolver.instance.revision.removeListener(
        _onProxyRevisionChanged,
      );
      _proxyListenerRegistered = false;
    }
    final sessionIds = _persistentSessions.keys.toList(growable: false);
    for (final sessionId in sessionIds) {
      final session = _persistentSessions.remove(sessionId);
      if (session == null) {
        continue;
      }
      // Cancel subscriptions before killing process to avoid error callbacks.
      unawaited(session.stdoutSubscription?.cancel());
      unawaited(session.stderrSubscription?.cancel());
      _killProcess(session.process);
    }
  }

  /// Kill a process in a platform-safe way.
  ///
  /// On Windows, [ProcessSignal.sigkill] is not supported, so we fall back to
  /// the default [Process.kill] which calls `TerminateProcess`.
  ///
  /// On POSIX, prefer a graceful shutdown: send SIGTERM first to give the
  /// shell a chance to clean up its own children (importantly, GUI helpers
  /// like `osascript` that own input-method state — see
  /// `lib/app/support/safe_subprocess.dart` for the long story). After a
  /// short grace period, escalate to SIGKILL if the process is still alive.
  /// Both signals are best-effort; failures are intentionally swallowed
  /// because the process may already have exited.
  static void _killProcess(Process process) {
    if (Platform.isWindows) {
      try {
        process.kill();
      } catch (_) {
        // Process already exited; nothing to do.
      }
      return;
    }
    final pid = process.pid;
    final isGroupLeader = _processGroupLeaders.contains(pid);
    var graceful = false;
    try {
      // Default signal is SIGTERM on POSIX; spelt out via the default to keep
      // intent clear without tripping the redundant-argument lint.
      graceful = process.kill();
    } catch (_) {
      graceful = false;
    }
    // 对进程组 leader 同步发一次 `kill -TERM -pid`，把 shell 派生出来的子孙
    // 进程一并通知到，避免子孙残留。
    if (isGroupLeader) {
      _sendSignalToProcessGroup(pid, 'TERM');
    }
    if (!graceful) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // Process already exited.
      }
      if (isGroupLeader) {
        _sendSignalToProcessGroup(pid, 'KILL');
      }
      return;
    }
    // Race: if the child hasn't exited within the grace period, escalate.
    final escalation = Timer(const Duration(milliseconds: 500), () {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // Process already exited cleanly after SIGTERM.
      }
      if (isGroupLeader) {
        _sendSignalToProcessGroup(pid, 'KILL');
      }
    });
    // Cancel the escalation if the child exits cleanly first.
    process.exitCode.then((_) => escalation.cancel()).ignore();
  }

  /// 通过 `/bin/kill -SIG -PGID` 向进程组发送信号；本身不阻塞，失败静默。
  static void _sendSignalToProcessGroup(int pid, String signal) {
    if (Platform.isWindows) return;
    unawaited(() async {
      try {
        await Process.run('/bin/kill', <String>['-$signal', '-$pid']);
      } catch (error, stack) {
        silentLog('ai_bash_tool_service', 'kill -$signal -$pid', error, stack);
      }
    }());
  }
}

class BashWriteAnalysis {
  const BashWriteAnalysis._({required this.isWrite, required this.reason});

  const BashWriteAnalysis.readOnly(String reason)
    : this._(isWrite: false, reason: reason);

  const BashWriteAnalysis.write(String reason)
    : this._(isWrite: true, reason: reason);

  final bool isWrite;
  final String reason;
}

enum _ShellTokenKind { word, separator, redirection }

class _ShellToken {
  const _ShellToken.word(
    this.text, {
    this.nestedCommands = const <String>[],
    this.hasDynamicExpansion = false,
  }) : kind = _ShellTokenKind.word;

  const _ShellToken.separator(this.text)
    : kind = _ShellTokenKind.separator,
      nestedCommands = const <String>[],
      hasDynamicExpansion = false;

  const _ShellToken.redirection(this.text)
    : kind = _ShellTokenKind.redirection,
      nestedCommands = const <String>[],
      hasDynamicExpansion = false;

  final _ShellTokenKind kind;
  final String text;
  final List<String> nestedCommands;
  final bool hasDynamicExpansion;
}

class _TokenReadResult {
  const _TokenReadResult({required this.token, required this.nextIndex});

  final _ShellToken token;
  final int nextIndex;
}

class _ShellWriteCommandAnalyzer {
  _ShellWriteCommandAnalyzer(this.source);

  static const Set<String> _outputRedirections = <String>{
    '>',
    '>>',
    '>|',
    '>&',
    '<>',
  };

  static const Set<String> _controlKeywords = <String>{
    '!',
    'if',
    'then',
    'elif',
    'else',
    'do',
    'done',
    'fi',
    'esac',
    'in',
  };

  static const Set<String> _nonCommandKeywords = <String>{
    'for',
    'function',
    'case',
    'select',
  };

  static const Set<String> _readOnlyCommands = <String>{
    'pwd',
    'ls',
    'cat',
    'head',
    'tail',
    'less',
    'more',
    'grep',
    'egrep',
    'fgrep',
    'rg',
    'ag',
    'fd',
    'readlink',
    'realpath',
    'stat',
    'file',
    'du',
    'df',
    'uname',
    'whoami',
    'id',
    'printenv',
    'date',
    'which',
    'whereis',
    'basename',
    'dirname',
    'sort',
    'uniq',
    'cut',
    'tr',
    'wc',
    'comm',
    'join',
    'column',
    'printf',
    'echo',
    'true',
    'false',
    'sleep',
    'history',
    // macOS terminal automation commands – these talk to terminal apps but
    // don't mutate the local filesystem.  Machine-expert workflows rely on
    // osascript heavily for sending keystrokes and reading screen buffers.
    //
    // 2026-04-21 SECURITY FIX: `osascript` is NOT listed here because it can
    // execute arbitrary shell commands via `do shell script`, inject commands
    // into other terminal applications via `write text` / `do script` /
    // `keystroke`, and otherwise produce side effects indistinguishable from
    // running the wrapped command directly.  Treating it as a blanket
    // read-only verb lets machine-expert flows (and any other osascript
    // invocation) bypass the write-command confirmation gate.  osascript is
    // now handled separately in `_osascriptWriteAnalysis` below, which marks
    // any AppleScript body that contains write-like verbs as a write command.
    'pbpaste',
    'say',
    'afplay',
    // System inspection utilities commonly used by machine-expert tasks.
    'sysctl',
    'sw_vers',
    'system_profiler',
    'hostinfo',
    'ioreg',
    'diskutil',
    'vm_stat',
    'top',
    'ps',
    'lsof',
    'netstat',
    'ifconfig',
    'route',
    'arp',
    'nslookup',
    'dig',
    'host',
    'ping',
    'traceroute',
    'uptime',
    'last',
    'w',
    'finger',
    'groups',
    'env',
    'locale',
    'free',
    'vmstat',
    'iostat',
    'mpstat',
    'sar',
    'nproc',
    'lscpu',
    'lsblk',
    'lspci',
    'lsusb',
    'ip',
    'ss',
    'hostname',
    'dmesg',
    'journalctl',
    // Windows system inspection commands (when run through cmd /c).
    'systeminfo',
    'wmic',
    'ipconfig',
    'tasklist',
    'ver',
    'set',
    'vol',
    'chcp',
    'where',
    'findstr',
    'type',
    'dir',
  };

  static const Set<String> _alwaysWriteCommands = <String>{
    'rm',
    'mv',
    'cp',
    'touch',
    'mkdir',
    'rmdir',
    'chmod',
    'chown',
    'chgrp',
    'truncate',
    'install',
    'ln',
    'dd',
    'patch',
    'apply_patch',
    'rsync',
    'scp',
    'sftp',
    'wget',
    'kubectl',
    'helm',
    'terraform',
    'ansible-playbook',
    'docker',
    'podman',
    'make',
    'cmake',
    'ninja',
    'gradle',
    'mvn',
    'npm',
    'pnpm',
    'yarn',
    'bun',
    'cargo',
    'go',
    'flutter',
    'dart',
    'pip',
    'pip3',
    'uv',
    'poetry',
    'composer',
  };

  static const Set<String> _wrapperCommands = <String>{
    'sudo',
    'env',
    'command',
    'builtin',
    'noglob',
    'stdbuf',
    'chronic',
    'nice',
    'nohup',
    'time',
    'timeout',
  };

  static const Set<String> _shellCommands = <String>{
    'bash',
    'sh',
    'zsh',
    'ksh',
    'fish',
  };

  static const Set<String> _interpreterCommands = <String>{
    'python',
    'python3',
    'node',
    'ruby',
    'perl',
    'lua',
    'php',
    'deno',
    'awk',
  };

  final String source;

  BashWriteAnalysis analyze() {
    final tokens = _tokenize(source);
    if (tokens.isEmpty) {
      return const BashWriteAnalysis.readOnly('empty command');
    }

    for (final token in tokens) {
      for (final nestedCommand in token.nestedCommands) {
        final nestedAnalysis = _ShellWriteCommandAnalyzer(
          nestedCommand,
        ).analyze();
        if (nestedAnalysis.isWrite) {
          return BashWriteAnalysis.write(
            'nested shell expansion: ${nestedAnalysis.reason}',
          );
        }
      }
    }

    final segments = _splitSegments(tokens);
    for (final segment in segments) {
      final analysis = _analyzeSegment(segment);
      if (analysis.isWrite) {
        return analysis;
      }
    }

    return const BashWriteAnalysis.readOnly(
      'all parsed shell commands are read-only',
    );
  }

  List<_ShellToken> _tokenize(String input) {
    final tokens = <_ShellToken>[];
    var index = 0;
    while (index < input.length) {
      final char = input[index];
      if (_isWhitespace(char)) {
        if (char == '\n') {
          tokens.add(const _ShellToken.separator('\n'));
        }
        index++;
        continue;
      }
      if (char == '#') {
        index = _skipComment(input, index);
        continue;
      }
      final processSubstitution = _readProcessSubstitution(input, index);
      if (processSubstitution != null) {
        tokens.add(processSubstitution.token);
        index = processSubstitution.nextIndex;
        continue;
      }
      final separator = _readSeparator(input, index);
      if (separator != null) {
        tokens.add(separator.token);
        index = separator.nextIndex;
        continue;
      }
      final redirection = _readRedirection(input, index);
      if (redirection != null) {
        tokens.add(redirection.token);
        index = redirection.nextIndex;
        continue;
      }
      final word = _readWord(input, index);
      tokens.add(word.token);
      index = word.nextIndex;
    }
    return tokens;
  }

  List<List<_ShellToken>> _splitSegments(List<_ShellToken> tokens) {
    final segments = <List<_ShellToken>>[];
    var current = <_ShellToken>[];
    for (final token in tokens) {
      if (token.kind == _ShellTokenKind.separator) {
        if (current.isNotEmpty) {
          segments.add(current);
          current = <_ShellToken>[];
        }
        continue;
      }
      current.add(token);
    }
    if (current.isNotEmpty) {
      segments.add(current);
    }
    return segments;
  }

  BashWriteAnalysis _analyzeSegment(List<_ShellToken> segment) {
    final words = <_ShellToken>[];
    var skipRedirectionTarget = false;
    for (var index = 0; index < segment.length; index++) {
      final token = segment[index];
      if (token.kind == _ShellTokenKind.redirection) {
        skipRedirectionTarget = true;
        final target =
            index + 1 < segment.length &&
                segment[index + 1].kind == _ShellTokenKind.word
            ? segment[index + 1]
            : null;
        final redirectionAnalysis = _analyzeRedirection(token, target);
        if (redirectionAnalysis != null) {
          return redirectionAnalysis;
        }
        continue;
      }
      if (token.kind != _ShellTokenKind.word) {
        continue;
      }
      if (skipRedirectionTarget) {
        skipRedirectionTarget = false;
        continue;
      }
      words.add(token);
    }
    return _analyzeWords(words);
  }

  BashWriteAnalysis? _analyzeRedirection(
    _ShellToken operatorToken,
    _ShellToken? target,
  ) {
    final normalizedOperator = _normalizeRedirection(operatorToken.text);
    if (!_outputRedirections.contains(normalizedOperator)) {
      return null;
    }
    if (_isNonPersistentOutputTarget(target)) {
      return null;
    }
    if (normalizedOperator == '>&' && _isFileDescriptorTarget(target)) {
      return null;
    }
    return BashWriteAnalysis.write(
      'output redirection operator ${operatorToken.text}',
    );
  }

  BashWriteAnalysis _analyzeWords(List<_ShellToken> words) {
    if (words.isEmpty) {
      return const BashWriteAnalysis.readOnly(
        'segment without executable words',
      );
    }
    if (_nonCommandKeywords.contains(words.first.text)) {
      return BashWriteAnalysis.readOnly(
        'shell control keyword ${words.first.text}',
      );
    }

    var start = 0;
    while (start < words.length &&
        _controlKeywords.contains(words[start].text)) {
      start++;
    }
    while (start < words.length && _looksLikeAssignment(words[start].text)) {
      start++;
    }
    if (start >= words.length) {
      return const BashWriteAnalysis.readOnly(
        'only shell control tokens or assignments',
      );
    }

    final invocation = words.sublist(start);
    if (invocation.first.hasDynamicExpansion) {
      return BashWriteAnalysis.write(
        'dynamic command name ${invocation.first.text}',
      );
    }
    final commandName = _basename(invocation.first.text);

    if (_wrapperCommands.contains(commandName)) {
      return _analyzeWrapperCommand(commandName, invocation);
    }
    if (_shellCommands.contains(commandName)) {
      return _analyzeShellInvocation(commandName, invocation);
    }
    if (_interpreterCommands.contains(commandName)) {
      return _analyzeInterpreterInvocation(commandName, invocation);
    }
    if (_alwaysWriteCommands.contains(commandName)) {
      return BashWriteAnalysis.write('mutating command $commandName');
    }
    if (commandName == 'git') {
      return _analyzeGitInvocation(invocation);
    }
    if (commandName == 'find') {
      return _analyzeFindInvocation(invocation);
    }
    if (commandName == 'xargs') {
      return _analyzeXargsInvocation(invocation);
    }
    if (commandName == 'sed') {
      return _analyzeSedInvocation(invocation);
    }
    if (commandName == 'tar') {
      return _analyzeTarInvocation(invocation);
    }
    if (commandName == 'tee') {
      return _analyzeTeeInvocation(invocation);
    }
    if (commandName == 'curl') {
      return _analyzeCurlInvocation(invocation);
    }
    if (_readOnlyCommands.contains(commandName)) {
      return BashWriteAnalysis.readOnly('read-only command $commandName');
    }
    // macOS clipboard write and screenshot are safe-side-effect commands
    // (they write to clipboard/tmp, not to user files).
    if (commandName == 'pbcopy' || commandName == 'screencapture') {
      return BashWriteAnalysis.readOnly(
        'safe side-effect command $commandName',
      );
    }
    // `open` on macOS only launches apps / URLs — it doesn't mutate files
    // by itself.
    if (commandName == 'open' && Platform.isMacOS) {
      return BashWriteAnalysis.readOnly('macOS open command $commandName');
    }
    // `defaults read` is read-only; `defaults write/delete` mutates.
    if (commandName == 'defaults') {
      return _analyzeDefaultsInvocation(invocation);
    }
    // 2026-04-21 osascript / osacompile are powerful and can execute arbitrary
    // shell commands (`do shell script`), inject keystrokes into other apps
    // (`keystroke`, `key code`, `key down/up`), or drive terminal emulators
    // (`write text`, `do script`).  Treating every osascript invocation as a
    // write would nag the user for simple read-only `get` queries used for
    // locating windows, so we inspect the AppleScript body and only classify
    // as write when a known write-like verb appears.
    if (commandName == 'osascript' || commandName == 'osacompile') {
      return _analyzeOsascriptInvocation(invocation);
    }
    // Remote/cross-host execution commands effectively run arbitrary
    // instructions on another system — treat as write by default.
    if (commandName == 'ssh' || commandName == 'doas') {
      return BashWriteAnalysis.write('remote execution command $commandName');
    }
    // Cross-terminal injection via tmux/screen send-keys is a write operation
    // on another session, even though the local process itself is innocent.
    if (commandName == 'tmux' || commandName == 'screen') {
      return _analyzeMultiplexerInvocation(commandName, invocation);
    }
    // X11 / Wayland input injection tools drive arbitrary key/mouse events.
    if (commandName == 'xdotool' ||
        commandName == 'ydotool' ||
        commandName == 'wtype') {
      return _analyzeInputInjectionInvocation(commandName, invocation);
    }
    if (_looksLikeScriptPath(invocation.first.text)) {
      return BashWriteAnalysis.write(
        'script or executable path ${invocation.first.text}',
      );
    }
    return BashWriteAnalysis.write(
      'unclassified external command $commandName',
    );
  }

  /// Analyze an `osascript` / `osacompile` invocation.  Flags any AppleScript
  /// body that contains write-like verbs (arbitrary shell execution, keystroke
  /// injection, terminal command dispatch, process/file mutation, app quit,
  /// property assignment) as a write command.
  BashWriteAnalysis _analyzeOsascriptInvocation(List<_ShellToken> invocation) {
    // Concatenate every non-flag argument into a single buffer so we can look
    // for write-like verbs regardless of how the script is chunked across
    // multiple `-e` flags, inline script files, or here-strings.
    final bodyBuffer = StringBuffer();
    var dynamicScript = false;
    for (final token in invocation.skip(1)) {
      if (token.hasDynamicExpansion) {
        dynamicScript = true;
      }
      final text = token.text;
      // Skip short flag names themselves (like `-e`, `-s`, `-l`) but include
      // their VALUES, which are appended as separate tokens by the tokenizer.
      if (text.startsWith('-') && text.length <= 3) {
        continue;
      }
      bodyBuffer
        ..write(text)
        ..write('\n');
    }
    final body = bodyBuffer.toString();
    // If the AppleScript body is being assembled dynamically (e.g. via command
    // substitution `$(…)`), we can't inspect it safely — treat as write.
    if (dynamicScript) {
      return const BashWriteAnalysis.write(
        'osascript with dynamically-composed script body',
      );
    }
    if (body.trim().isEmpty) {
      return const BashWriteAnalysis.readOnly(
        'osascript without an inline script body',
      );
    }
    final lowered = body.toLowerCase();
    const writeVerbPatterns = <String>[
      r'\bdo\s+shell\s+script\b',
      r'\bdo\s+script\b',
      r'\bwrite\s+text\b',
      r'\bkeystroke\b',
      r'\bkey\s+code\b',
      r'\bkey\s+down\b',
      r'\bkey\s+up\b',
      r'\bset\s+(?:the\s+)?clipboard\b',
      r'\bmake\s+new\b',
      r'\bdelete\b',
      r'\bquit\b',
      r'\bactivate\b',
      r'\brestart\b',
      r'\bshut\s+down\b',
      r'\bopen\s+location\b',
      r'\bset\s+value\b',
      r'\bset\s+.+\s+to\b',
      r'\bempty\s+trash\b',
      r'\bperform\s+action\b',
      r'\bclick\b',
      r'\bmount\s+volume\b',
      r'\beject\b',
      r'\brename\b',
      r'\bmove\b',
      r'\bduplicate\b',
    ];
    for (final pattern in writeVerbPatterns) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(lowered);
      if (match != null) {
        return BashWriteAnalysis.write(
          'osascript body contains write-like verb `${match.group(0)?.trim()}`',
        );
      }
    }
    return const BashWriteAnalysis.readOnly(
      'osascript body only queries terminal/app state',
    );
  }

  /// Analyze `tmux`/`screen` invocations.  Subcommands that send keys, paste
  /// buffers, kill sessions, source new configs, or rename objects mutate
  /// the target session and must be confirmed.
  BashWriteAnalysis _analyzeMultiplexerInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    const writeSubcommands = <String>{
      'send-keys',
      'send',
      'paste-buffer',
      'load-buffer',
      'set-buffer',
      'kill-server',
      'kill-session',
      'kill-window',
      'kill-pane',
      'new-session',
      'new-window',
      'split-window',
      'source-file',
      'rename-session',
      'rename-window',
      'respawn-pane',
      'respawn-window',
      'run-shell',
      'set-option',
      'set-environment',
      'stuff', // `screen -X stuff "..."` — injects keys
    };
    for (final token in invocation.skip(1)) {
      final value = token.text.toLowerCase();
      if (value.startsWith('-')) {
        continue;
      }
      if (writeSubcommands.contains(value)) {
        return BashWriteAnalysis.write(
          '$commandName $value injects or mutates session state',
        );
      }
      break;
    }
    // Bare `tmux` / `screen` or read-only subcommands (list-sessions,
    // capture-pane, show-options, …) are safe.
    return BashWriteAnalysis.readOnly(
      '$commandName invocation appears read-only',
    );
  }

  /// Treat any invocation of an input-injection tool as a write operation —
  /// these drive arbitrary keyboard/mouse events on the host.
  BashWriteAnalysis _analyzeInputInjectionInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    for (final token in invocation.skip(1)) {
      final value = token.text.toLowerCase();
      if (value == 'search' ||
          value == 'getactivewindow' ||
          value == 'getwindowname' ||
          value == 'getmouselocation') {
        return BashWriteAnalysis.readOnly(
          '$commandName read-only subcommand $value',
        );
      }
      if (value.startsWith('-')) continue;
      break;
    }
    return BashWriteAnalysis.write('$commandName injects keyboard/mouse input');
  }

  BashWriteAnalysis _analyzeDefaultsInvocation(List<_ShellToken> invocation) {
    for (final token in invocation.skip(1)) {
      final value = token.text;
      if (value == 'read' ||
          value == 'read-type' ||
          value == 'domains' ||
          value == 'find' ||
          value == 'help') {
        return BashWriteAnalysis.readOnly('defaults $value is read-only');
      }
      if (value == 'write' ||
          value == 'delete' ||
          value == 'rename' ||
          value == 'import') {
        return BashWriteAnalysis.write('defaults $value mutates preferences');
      }
      // Skip options/flags
      if (value.startsWith('-')) continue;
      // First non-option non-subcommand argument – fall back to write.
      break;
    }
    return const BashWriteAnalysis.write('defaults with unclear subcommand');
  }

  BashWriteAnalysis _analyzeWrapperCommand(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    final innerWords = switch (commandName) {
      'env' => _unwrapEnv(invocation),
      'timeout' => _unwrapTimeout(invocation),
      'sudo' => _unwrapSudo(invocation),
      _ => _unwrapGenericWrapper(invocation),
    };
    if (innerWords.isEmpty) {
      return BashWriteAnalysis.readOnly('$commandName without inner command');
    }
    return _analyzeWords(innerWords);
  }

  BashWriteAnalysis _analyzeShellInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    final scriptToken = _findInlineScriptToken(invocation, const <String>{
      '-c',
    });
    if (scriptToken != null) {
      if (scriptToken.hasDynamicExpansion) {
        return BashWriteAnalysis.write(
          'dynamic inline shell script for $commandName',
        );
      }
      final nested = _ShellWriteCommandAnalyzer(scriptToken.text).analyze();
      if (nested.isWrite) {
        return BashWriteAnalysis.write(
          'inline shell script for $commandName: ${nested.reason}',
        );
      }
      return BashWriteAnalysis.readOnly(
        'inline shell script for $commandName is read-only',
      );
    }
    final scriptPath = _firstNonOption(invocation.sublist(1));
    if (scriptPath != null) {
      return BashWriteAnalysis.write(
        'shell script execution ${scriptPath.text}',
      );
    }
    return BashWriteAnalysis.write('interactive shell invocation $commandName');
  }

  BashWriteAnalysis _analyzeInterpreterInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    if (commandName == 'awk') {
      return const BashWriteAnalysis.write(
        'awk programs can write files and state',
      );
    }
    final inlineScriptToken = _findInlineScriptToken(invocation, const <String>{
      '-c',
      '-e',
      '--eval',
    });
    if (inlineScriptToken != null) {
      return BashWriteAnalysis.write(
        'inline interpreter code for $commandName',
      );
    }
    if (_firstNonOption(invocation.sublist(1)) != null) {
      return BashWriteAnalysis.write(
        'interpreter or script execution via $commandName',
      );
    }
    return BashWriteAnalysis.readOnly('$commandName without program input');
  }

  BashWriteAnalysis _analyzeGitInvocation(List<_ShellToken> invocation) {
    final subcommandIndex = _findGitSubcommandIndex(invocation);
    if (subcommandIndex == -1) {
      return const BashWriteAnalysis.readOnly('git without subcommand');
    }
    final subcommand = invocation[subcommandIndex].text;
    final args = invocation.sublist(subcommandIndex + 1);
    switch (subcommand) {
      case 'status':
      case 'diff':
      case 'log':
      case 'show':
      case 'grep':
      case 'rev-parse':
      case 'describe':
      case 'blame':
        return BashWriteAnalysis.readOnly('git $subcommand is read-only');
      case 'branch':
        if (_gitBranchIsReadOnly(args)) {
          return const BashWriteAnalysis.readOnly('git branch listing');
        }
        return const BashWriteAnalysis.write('git branch mutation');
      case 'tag':
        if (_gitTagIsReadOnly(args)) {
          return const BashWriteAnalysis.readOnly('git tag listing');
        }
        return const BashWriteAnalysis.write('git tag mutation');
      case 'stash':
        if (_gitStashIsReadOnly(args)) {
          return const BashWriteAnalysis.readOnly('git stash listing');
        }
        return const BashWriteAnalysis.write('git stash mutation');
      default:
        return BashWriteAnalysis.write(
          'git $subcommand mutates repository state',
        );
    }
  }

  BashWriteAnalysis _analyzeFindInvocation(List<_ShellToken> invocation) {
    final args = invocation.sublist(1);
    for (var index = 0; index < args.length; index++) {
      final value = args[index].text;
      if (value == '-delete' ||
          value == '-fprint' ||
          value == '-fprintf' ||
          value == '-fls') {
        return BashWriteAnalysis.write('find action $value');
      }
      if (value == '-exec' ||
          value == '-execdir' ||
          value == '-ok' ||
          value == '-okdir') {
        final nestedWords = <_ShellToken>[];
        for (
          var nestedIndex = index + 1;
          nestedIndex < args.length;
          nestedIndex++
        ) {
          final nestedValue = args[nestedIndex].text;
          if (nestedValue == ';' ||
              nestedValue == '+' ||
              nestedValue == r'\;') {
            break;
          }
          nestedWords.add(args[nestedIndex]);
        }
        if (nestedWords.isEmpty) {
          return BashWriteAnalysis.write(
            'find $value without explicit command',
          );
        }
        final nestedAnalysis = _analyzeWords(nestedWords);
        if (nestedAnalysis.isWrite) {
          return BashWriteAnalysis.write(
            'find $value launches mutating command: ${nestedAnalysis.reason}',
          );
        }
      }
    }
    return const BashWriteAnalysis.readOnly('find predicate scan only');
  }

  BashWriteAnalysis _analyzeXargsInvocation(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      final option = invocation[index].text;
      index++;
      if (option == '-I' ||
          option == '-i' ||
          option == '-L' ||
          option == '-l' ||
          option == '-n' ||
          option == '-P' ||
          option == '-s' ||
          option == '-E' ||
          option == '--replace' ||
          option == '--max-lines' ||
          option == '--max-args' ||
          option == '--max-procs' ||
          option == '--delimiter' ||
          option == '--eof') {
        if (index < invocation.length) {
          index++;
        }
      }
    }
    if (index >= invocation.length) {
      return const BashWriteAnalysis.readOnly(
        'xargs without explicit command defaults to echo',
      );
    }
    return _analyzeWords(invocation.sublist(index));
  }

  BashWriteAnalysis _analyzeSedInvocation(List<_ShellToken> invocation) {
    for (final token in invocation.skip(1)) {
      final value = token.text;
      if (value == '-i' || value.startsWith('-i') || value == '--in-place') {
        return const BashWriteAnalysis.write('sed in-place edit');
      }
    }
    return const BashWriteAnalysis.readOnly('sed stream transform only');
  }

  BashWriteAnalysis _analyzeTarInvocation(List<_ShellToken> invocation) {
    final args = invocation
        .skip(1)
        .map((token) => token.text)
        .toList(growable: false);
    final flags = StringBuffer();
    for (final arg in args) {
      if (arg.startsWith('--')) {
        if (arg == '--list') {
          continue;
        }
        if (arg == '--extract' ||
            arg == '--create' ||
            arg == '--append' ||
            arg == '--update' ||
            arg == '--delete' ||
            arg == '--concatenate') {
          return BashWriteAnalysis.write('tar option $arg');
        }
        continue;
      }
      if (arg.startsWith('-')) {
        flags.write(arg.substring(1));
        continue;
      }
      if (!arg.startsWith('-') && RegExp(r'^[ctxruA]').hasMatch(arg)) {
        flags.write(arg);
      }
    }
    final normalizedFlags = flags.toString();
    if (normalizedFlags.contains('x') ||
        normalizedFlags.contains('c') ||
        normalizedFlags.contains('r') ||
        normalizedFlags.contains('u') ||
        normalizedFlags.contains('A')) {
      return BashWriteAnalysis.write('tar flags $normalizedFlags');
    }
    return const BashWriteAnalysis.readOnly('tar listing or inspection');
  }

  BashWriteAnalysis _analyzeTeeInvocation(List<_ShellToken> invocation) {
    final hasFileTarget = invocation
        .skip(1)
        .any((token) => !_looksLikeOption(token.text));
    if (hasFileTarget) {
      return const BashWriteAnalysis.write('tee writes to file targets');
    }
    return const BashWriteAnalysis.readOnly('tee without file targets');
  }

  BashWriteAnalysis _analyzeCurlInvocation(List<_ShellToken> invocation) {
    for (var index = 1; index < invocation.length; index++) {
      final value = invocation[index].text;
      if (value == '-o' ||
          value == '-O' ||
          value == '-T' ||
          value == '--output' ||
          value == '--remote-name' ||
          value == '--upload-file' ||
          value == '--output-dir') {
        return BashWriteAnalysis.write('curl option $value');
      }
      if (value.startsWith('--output=') || value.startsWith('--upload-file=')) {
        return BashWriteAnalysis.write('curl option ${value.split('=').first}');
      }
    }
    return const BashWriteAnalysis.readOnly('curl without local output target');
  }

  List<_ShellToken> _unwrapEnv(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length) {
      final value = invocation[index].text;
      if (value == '--') {
        index++;
        break;
      }
      if (_looksLikeOption(value)) {
        index++;
        if (value == '-u' || value == '--unset') {
          index++;
        }
        continue;
      }
      if (_looksLikeAssignment(value)) {
        index++;
        continue;
      }
      break;
    }
    return invocation.sublist(index);
  }

  List<_ShellToken> _unwrapTimeout(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      final option = invocation[index].text;
      index++;
      if (option == '-k' ||
          option == '--kill-after' ||
          option == '-s' ||
          option == '--signal') {
        if (index < invocation.length) {
          index++;
        }
      }
    }
    if (index < invocation.length) {
      index++;
    }
    return invocation.sublist(index);
  }

  List<_ShellToken> _unwrapSudo(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      final option = invocation[index].text;
      index++;
      if (option == '-u' ||
          option == '-g' ||
          option == '-h' ||
          option == '-p' ||
          option == '-C' ||
          option == '-T' ||
          option == '-r' ||
          option == '-t') {
        if (index < invocation.length) {
          index++;
        }
      }
    }
    return invocation.sublist(index);
  }

  List<_ShellToken> _unwrapGenericWrapper(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      index++;
    }
    return invocation.sublist(index);
  }

  _ShellToken? _findInlineScriptToken(
    List<_ShellToken> invocation,
    Set<String> supportedFlags,
  ) {
    for (var index = 1; index < invocation.length; index++) {
      final value = invocation[index].text;
      if (value == '--') {
        break;
      }
      if (supportedFlags.contains(value) && index + 1 < invocation.length) {
        return invocation[index + 1];
      }
      if (value.startsWith('-') &&
          !value.startsWith('--') &&
          value.length > 2 &&
          supportedFlags.any((flag) => value.contains(flag.substring(1)))) {
        if (index + 1 < invocation.length) {
          return invocation[index + 1];
        }
      }
    }
    return null;
  }

  _ShellToken? _firstNonOption(List<_ShellToken> tokens) {
    for (final token in tokens) {
      if (!_looksLikeOption(token.text)) {
        return token;
      }
    }
    return null;
  }

  int _findGitSubcommandIndex(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length) {
      final value = invocation[index].text;
      if (value == '--') {
        return index + 1 < invocation.length ? index + 1 : -1;
      }
      if (!_looksLikeOption(value)) {
        return index;
      }
      index++;
      if (value == '-C' ||
          value == '--git-dir' ||
          value == '--work-tree' ||
          value == '--namespace' ||
          value == '-c' ||
          value == '--config-env') {
        index++;
      }
    }
    return -1;
  }

  bool _gitBranchIsReadOnly(List<_ShellToken> args) {
    if (args.isEmpty) {
      return true;
    }
    for (final arg in args) {
      final value = arg.text;
      if (value == '-d' ||
          value == '-D' ||
          value == '-m' ||
          value == '-M' ||
          value == '-c' ||
          value == '-C' ||
          value == '--delete' ||
          value == '--move' ||
          value == '--copy' ||
          value == '--set-upstream-to' ||
          value == '--unset-upstream') {
        return false;
      }
      if (!_looksLikeOption(value)) {
        return false;
      }
    }
    return true;
  }

  bool _gitTagIsReadOnly(List<_ShellToken> args) {
    if (args.isEmpty) {
      return true;
    }
    for (final arg in args) {
      final value = arg.text;
      if (value == '-d' ||
          value == '--delete' ||
          value == '-m' ||
          value == '-F') {
        return false;
      }
      if (!_looksLikeOption(value)) {
        return false;
      }
    }
    return true;
  }

  bool _gitStashIsReadOnly(List<_ShellToken> args) {
    if (args.isEmpty) {
      return false;
    }
    final subcommand = args.first.text;
    return subcommand == 'list' || subcommand == 'show';
  }

  _TokenReadResult? _readProcessSubstitution(String input, int index) {
    if (index + 1 >= input.length) {
      return null;
    }
    final leader = input[index];
    if ((leader != '<' && leader != '>') || input[index + 1] != '(') {
      return null;
    }
    final balanced = _readBalancedCommand(input, index + 2);
    return _TokenReadResult(
      token: _ShellToken.word(
        input.substring(index, balanced.nextIndex),
        nestedCommands: <String>[balanced.content],
      ),
      nextIndex: balanced.nextIndex,
    );
  }

  _TokenReadResult? _readSeparator(String input, int index) {
    for (final candidate in <String>[
      '&&',
      '||',
      ';',
      '|',
      '&',
      '(',
      ')',
      '{',
      '}',
    ]) {
      if (input.startsWith(candidate, index)) {
        return _TokenReadResult(
          token: _ShellToken.separator(candidate),
          nextIndex: index + candidate.length,
        );
      }
    }
    return null;
  }

  _TokenReadResult? _readRedirection(String input, int index) {
    final start = index;
    var cursor = index;
    while (cursor < input.length && _isDigit(input[cursor])) {
      cursor++;
    }
    for (final operator in <String>[
      '<<-',
      '<<<',
      '>>',
      '<<',
      '>|',
      '<>',
      '>&',
      '<&',
      '>',
      '<',
    ]) {
      if (input.startsWith(operator, cursor)) {
        return _TokenReadResult(
          token: _ShellToken.redirection(
            input.substring(start, cursor + operator.length),
          ),
          nextIndex: cursor + operator.length,
        );
      }
    }
    return null;
  }

  _TokenReadResult _readWord(String input, int index) {
    final buffer = StringBuffer();
    final nestedCommands = <String>[];
    var hasDynamicExpansion = false;
    var cursor = index;

    while (cursor < input.length) {
      final char = input[cursor];
      if (_isWhitespace(char) ||
          _readSeparator(input, cursor) != null ||
          _readRedirection(input, cursor) != null) {
        break;
      }
      final processSubstitution = _readProcessSubstitution(input, cursor);
      if (processSubstitution != null) {
        buffer.write(processSubstitution.token.text);
        nestedCommands.addAll(processSubstitution.token.nestedCommands);
        cursor = processSubstitution.nextIndex;
        continue;
      }
      if (char == '\'') {
        final closing = input.indexOf('\'', cursor + 1);
        if (closing == -1) {
          buffer.write(input.substring(cursor + 1));
          cursor = input.length;
        } else {
          buffer.write(input.substring(cursor + 1, closing));
          cursor = closing + 1;
        }
        continue;
      }
      if (char == '"') {
        final quoted = _readDoubleQuoted(input, cursor);
        buffer.write(quoted.text);
        nestedCommands.addAll(quoted.nestedCommands);
        hasDynamicExpansion = hasDynamicExpansion || quoted.hasDynamicExpansion;
        cursor = quoted.nextIndex;
        continue;
      }
      if (char == '`') {
        final nested = _readBacktickCommand(input, cursor);
        buffer.write('`${nested.content}`');
        nestedCommands.add(nested.content);
        hasDynamicExpansion = true;
        cursor = nested.nextIndex;
        continue;
      }
      if (char == r'$') {
        if (cursor + 1 < input.length && input[cursor + 1] == '(') {
          final nested = _readBalancedCommand(input, cursor + 2);
          buffer.write(r'$(${nested.content})');
          nestedCommands.add(nested.content);
          hasDynamicExpansion = true;
          cursor = nested.nextIndex;
          continue;
        }
        if (cursor + 1 < input.length && input[cursor + 1] == '{') {
          final closing = input.indexOf('}', cursor + 2);
          if (closing == -1) {
            buffer.write(input.substring(cursor));
            hasDynamicExpansion = true;
            cursor = input.length;
          } else {
            buffer.write(input.substring(cursor, closing + 1));
            hasDynamicExpansion = true;
            cursor = closing + 1;
          }
          continue;
        }
        final variableMatch = RegExp(
          r'^\$[A-Za-z_][A-Za-z0-9_]*',
        ).matchAsPrefix(input.substring(cursor));
        if (variableMatch != null) {
          buffer.write(variableMatch.group(0));
          hasDynamicExpansion = true;
          cursor += variableMatch.group(0)!.length;
          continue;
        }
      }
      if (char == r'\') {
        if (cursor + 1 < input.length) {
          buffer.write(input[cursor + 1]);
          cursor += 2;
          continue;
        }
        cursor++;
        break;
      }
      buffer.write(char);
      cursor++;
    }

    return _TokenReadResult(
      token: _ShellToken.word(
        buffer.toString(),
        nestedCommands: nestedCommands,
        hasDynamicExpansion: hasDynamicExpansion,
      ),
      nextIndex: cursor,
    );
  }

  _QuotedReadResult _readDoubleQuoted(String input, int index) {
    final buffer = StringBuffer();
    final nestedCommands = <String>[];
    var hasDynamicExpansion = false;
    var cursor = index + 1;
    while (cursor < input.length) {
      final char = input[cursor];
      if (char == '"') {
        return _QuotedReadResult(
          text: buffer.toString(),
          nextIndex: cursor + 1,
          nestedCommands: nestedCommands,
          hasDynamicExpansion: hasDynamicExpansion,
        );
      }
      if (char == r'\') {
        if (cursor + 1 < input.length) {
          buffer.write(input[cursor + 1]);
          cursor += 2;
          continue;
        }
        cursor++;
        break;
      }
      if (char == '`') {
        final nested = _readBacktickCommand(input, cursor);
        buffer.write('`${nested.content}`');
        nestedCommands.add(nested.content);
        hasDynamicExpansion = true;
        cursor = nested.nextIndex;
        continue;
      }
      if (char == r'$') {
        if (cursor + 1 < input.length && input[cursor + 1] == '(') {
          final nested = _readBalancedCommand(input, cursor + 2);
          buffer.write(r'$(${nested.content})');
          nestedCommands.add(nested.content);
          hasDynamicExpansion = true;
          cursor = nested.nextIndex;
          continue;
        }
        if (cursor + 1 < input.length && input[cursor + 1] == '{') {
          final closing = input.indexOf('}', cursor + 2);
          if (closing == -1) {
            buffer.write(input.substring(cursor));
            hasDynamicExpansion = true;
            cursor = input.length;
          } else {
            buffer.write(input.substring(cursor, closing + 1));
            hasDynamicExpansion = true;
            cursor = closing + 1;
          }
          continue;
        }
        final variableMatch = RegExp(
          r'^\$[A-Za-z_][A-Za-z0-9_]*',
        ).matchAsPrefix(input.substring(cursor));
        if (variableMatch != null) {
          buffer.write(variableMatch.group(0));
          hasDynamicExpansion = true;
          cursor += variableMatch.group(0)!.length;
          continue;
        }
      }
      buffer.write(char);
      cursor++;
    }
    return _QuotedReadResult(
      text: buffer.toString(),
      nextIndex: cursor,
      nestedCommands: nestedCommands,
      hasDynamicExpansion: hasDynamicExpansion,
    );
  }

  _BalancedReadResult _readBacktickCommand(String input, int index) {
    final buffer = StringBuffer();
    var cursor = index + 1;
    while (cursor < input.length) {
      final char = input[cursor];
      if (char == '`') {
        return _BalancedReadResult(
          content: buffer.toString(),
          nextIndex: cursor + 1,
        );
      }
      if (char == r'\' && cursor + 1 < input.length) {
        buffer.write(input[cursor + 1]);
        cursor += 2;
        continue;
      }
      buffer.write(char);
      cursor++;
    }
    return _BalancedReadResult(content: buffer.toString(), nextIndex: cursor);
  }

  _BalancedReadResult _readBalancedCommand(String input, int index) {
    final buffer = StringBuffer();
    var cursor = index;
    var depth = 1;
    while (cursor < input.length) {
      final char = input[cursor];
      if (char == '\'' || char == '"') {
        final quoted = char == '\''
            ? _readSingleQuotedSegment(input, cursor)
            : _readDoubleQuoted(input, cursor);
        buffer.write(input.substring(cursor, quoted.nextIndex));
        cursor = quoted.nextIndex;
        continue;
      }
      if (char == '`') {
        final nested = _readBacktickCommand(input, cursor);
        buffer.write('`${nested.content}`');
        cursor = nested.nextIndex;
        continue;
      }
      if (char == r'\' && cursor + 1 < input.length) {
        buffer.write(input.substring(cursor, cursor + 2));
        cursor += 2;
        continue;
      }
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          return _BalancedReadResult(
            content: buffer.toString(),
            nextIndex: cursor + 1,
          );
        }
      }
      buffer.write(char);
      cursor++;
    }
    return _BalancedReadResult(content: buffer.toString(), nextIndex: cursor);
  }

  _QuotedReadResult _readSingleQuotedSegment(String input, int index) {
    final closing = input.indexOf('\'', index + 1);
    if (closing == -1) {
      return _QuotedReadResult(
        text: input.substring(index + 1),
        nextIndex: input.length,
        nestedCommands: const <String>[],
        hasDynamicExpansion: false,
      );
    }
    return _QuotedReadResult(
      text: input.substring(index + 1, closing),
      nextIndex: closing + 1,
      nestedCommands: const <String>[],
      hasDynamicExpansion: false,
    );
  }

  int _skipComment(String input, int index) {
    var cursor = index;
    while (cursor < input.length && input[cursor] != '\n') {
      cursor++;
    }
    return cursor;
  }

  String _normalizeRedirection(String token) {
    final body = token.replaceFirst(RegExp(r'^\d+'), '');
    return body;
  }

  bool _looksLikeAssignment(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(value);
  }

  bool _looksLikeOption(String value) {
    return value.startsWith('-') && value != '-';
  }

  bool _looksLikeScriptPath(String value) {
    if (value.contains('/')) {
      return true;
    }
    return RegExp(
      r'\.(sh|bash|zsh|ksh|py|rb|pl|php|lua|js|ts)$',
    ).hasMatch(value);
  }

  String _basename(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return normalized;
    }
    final parts = normalized.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? normalized : parts.last;
  }

  bool _isWhitespace(String value) {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r';
  }

  bool _isDigit(String value) {
    return value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;
  }

  bool _isFileDescriptorTarget(_ShellToken? target) {
    if (target == null || target.hasDynamicExpansion) {
      return false;
    }
    final normalized = target.text.trim();
    return normalized == '-' || RegExp(r'^\d+$').hasMatch(normalized);
  }

  bool _isNonPersistentOutputTarget(_ShellToken? target) {
    if (target == null || target.hasDynamicExpansion) {
      return false;
    }
    final normalized = target.text.trim();
    return normalized == '/dev/null' ||
        normalized == '/dev/stdout' ||
        normalized == '/dev/stderr' ||
        RegExp(r'^/dev/fd/\d+$').hasMatch(normalized) ||
        RegExp(r'^/proc/self/fd/\d+$').hasMatch(normalized);
  }
}

class _CmdWriteCommandAnalyzer {
  const _CmdWriteCommandAnalyzer(this.source);

  final String source;

  BashWriteAnalysis analyze() {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      return const BashWriteAnalysis.readOnly('empty command');
    }
    if (RegExp(r'(^|[^<])>>?|>|>>').hasMatch(normalized)) {
      return const BashWriteAnalysis.write('cmd output redirection');
    }
    if (RegExp(
      r'(^|\s)(del|erase|move|copy|ren|rename|mkdir|rmdir|md|rd|attrib|type\s+.+>|powershell|pwsh|python|node)\b',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return const BashWriteAnalysis.write('cmd mutating command');
    }
    return const BashWriteAnalysis.readOnly('cmd command appears read-only');
  }
}

class _QuotedReadResult {
  const _QuotedReadResult({
    required this.text,
    required this.nextIndex,
    required this.nestedCommands,
    required this.hasDynamicExpansion,
  });

  final String text;
  final int nextIndex;
  final List<String> nestedCommands;
  final bool hasDynamicExpansion;
}

class _BalancedReadResult {
  const _BalancedReadResult({required this.content, required this.nextIndex});

  final String content;
  final int nextIndex;
}
