import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/platform_environment.dart';
import '../../../../shared/util/platform_shell.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../model/ai_deny_command_rule.dart';
import '../runtime/ai_tool_execution_registry.dart';
import '../sandbox/ai_sandbox_service.dart';

const Utf8Decoder _shellOutputDecoder = Utf8Decoder(allowMalformed: true);
const String _capturedOutputTruncatedMarker = '\n...[输出已截断]';

const String _kCmdStartMarkerPrefix = '__OPENHAND_CMD_START__';
const String _kExitMarkerPrefix = '__OPENHAND_EXIT__';
const String _kPwdEndMarkerPrefix = '__OPENHAND_PWD_END__';

void _appendCapturedOutput(
  StringBuffer buffer,
  String chunk,
  int maxCapturedCharacters,
) {
  if (maxCapturedCharacters <= buffer.length) return;
  final remaining = maxCapturedCharacters - buffer.length;
  if (chunk.length <= remaining) {
    buffer.write(chunk);
    return;
  }
  final markerLength = _capturedOutputTruncatedMarker.length < remaining
      ? _capturedOutputTruncatedMarker.length
      : remaining;
  final contentLength = safeUtf16PrefixCodeUnits(
    chunk,
    remaining - markerLength,
  );
  if (contentLength > 0) {
    buffer.write(chunk.substring(0, contentLength));
  }
  buffer.write(_capturedOutputTruncatedMarker.substring(0, markerLength));
}

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
/// 选择；`dismissed` 表示弹窗或远端确认被外部关闭，用户没有明示同意
/// 或拒绝；其余区分超时与会话级取消。把决策完整透传给 AI，让模型在
/// 后续动作中区分"用户拒绝"vs"用户没作答"。
enum BashCommandApprovalDecision {
  approved,
  rejected,
  dismissed,
  timedOut,
  cancelled,
}

String bashCommandApprovalDecisionValue(BashCommandApprovalDecision decision) {
  return switch (decision) {
    BashCommandApprovalDecision.approved => 'approved',
    BashCommandApprovalDecision.rejected => 'rejected',
    BashCommandApprovalDecision.dismissed => 'dismissed',
    BashCommandApprovalDecision.timedOut => 'timed_out',
    BashCommandApprovalDecision.cancelled => 'cancelled',
  };
}

Map<String, Object?> bashWriteConfirmationMetadata(
  Map<String, Object?> metadata,
  BashCommandApprovalDecision decision, {
  bool missingCallback = false,
}) {
  return <String, Object?>{
    ...metadata,
    'write_confirmation_decision': bashCommandApprovalDecisionValue(decision),
    if (decision == BashCommandApprovalDecision.rejected)
      'write_confirmation_rejected': true,
    if (decision == BashCommandApprovalDecision.dismissed)
      'write_confirmation_dismissed': true,
    if (decision == BashCommandApprovalDecision.timedOut)
      'write_confirmation_timed_out': true,
    if (decision == BashCommandApprovalDecision.cancelled)
      'write_confirmation_cancelled': true,
    if (missingCallback) 'write_confirmation_missing_callback': true,
  };
}

class BashCommandApprovalRequest {
  const BashCommandApprovalRequest({
    required this.command,
    required this.workingDirectory,
    required this.isWriteCommand,
    this.requestedAt,
    this.expiresAt,
  });

  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
  final DateTime? requestedAt;
  final DateTime? expiresAt;
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
    this.metadata = const <String, Object?>{},
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
  final Map<String, Object?> metadata;

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
    final confirmationDecision =
        '${metadata['write_confirmation_decision'] ?? ''}'.trim();
    if (confirmationDecision.isNotEmpty) {
      buffer.writeln('write_confirmation_decision: $confirmationDecision');
    }
    for (final entry in const <String>[
      'write_confirmation_rejected',
      'write_confirmation_dismissed',
      'write_confirmation_timed_out',
      'write_confirmation_cancelled',
      'write_confirmation_missing_callback',
    ]) {
      if (metadata[entry] == true) {
        buffer.writeln('$entry: true');
      }
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
    : this._(decision: BashCommandApprovalDecision.cancelled, cancelled: true);

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

  StringBuffer _stdoutLineBuffer = StringBuffer();
  bool _stdoutLineTruncated = false;
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
    _stallTimer = startSafePeriodicTimer(interval, (_) {
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
    return text.substring(safeUtf16SuffixStart(text, text.length - maxChars));
  }

  void appendStdoutChunk(String chunk, int maxCapturedCharacters) {
    if (chunk.isNotEmpty) {
      _lastOutputAtMs = stopwatch.elapsedMilliseconds;
      _stallWarningEmitted = false;
    }
    final normalized = chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    var segmentStart = 0;
    while (segmentStart < normalized.length) {
      final lineEnding = normalized.indexOf('\n', segmentStart);
      if (lineEnding < 0) {
        _appendStdoutLineSegment(
          normalized.substring(segmentStart),
          maxCapturedCharacters,
        );
        return;
      }
      _appendStdoutLineSegment(
        normalized.substring(segmentStart, lineEnding),
        maxCapturedCharacters,
      );
      _flushStdoutLine(maxCapturedCharacters, includeNewline: true);
      segmentStart = lineEnding + 1;
    }
  }

  void finalizeStdout(int maxCapturedCharacters) {
    if (_stdoutLineBuffer.isEmpty && !_stdoutLineTruncated) {
      return;
    }
    _flushStdoutLine(maxCapturedCharacters, includeNewline: false);
  }

  void _appendStdoutLineSegment(String segment, int maxCapturedCharacters) {
    if (segment.isEmpty || _stdoutLineTruncated) return;
    // 协议标记很短，但即使关闭输出捕获或上限异常偏小，也必须保持可解析。
    // 单行缓冲始终有界，避免无换行输出持续占用内存或触发平方级字符串复制。
    const minimumProtocolLineCharacters = 512;
    final lineLimit = maxCapturedCharacters > minimumProtocolLineCharacters
        ? maxCapturedCharacters
        : minimumProtocolLineCharacters;
    final remaining = lineLimit - _stdoutLineBuffer.length;
    if (remaining <= 0) {
      _stdoutLineTruncated = true;
      return;
    }
    if (segment.length <= remaining) {
      _stdoutLineBuffer.write(segment);
      return;
    }
    _stdoutLineBuffer.write(
      segment.substring(0, safeUtf16PrefixCodeUnits(segment, remaining)),
    );
    _stdoutLineTruncated = true;
  }

  void _flushStdoutLine(
    int maxCapturedCharacters, {
    required bool includeNewline,
  }) {
    final line = _stdoutLineBuffer.toString();
    final wasTruncated = _stdoutLineTruncated;
    _stdoutLineBuffer = StringBuffer();
    _stdoutLineTruncated = false;
    _handleStdoutLine(includeNewline ? '$line\n' : line, maxCapturedCharacters);
    if (wasTruncated) {
      _appendCapturedOutput(
        stdoutBuffer,
        '\n...[单行输出已截断]\n',
        maxCapturedCharacters,
      );
      emitUpdate(phase: BashToolExecutionPhase.running);
    }
  }

  void appendStderrChunk(String chunk, int maxCapturedCharacters) {
    if (chunk.isNotEmpty) {
      _lastOutputAtMs = stopwatch.elapsedMilliseconds;
      _stallWarningEmitted = false;
    }
    _appendCapturedOutput(stderrBuffer, chunk, maxCapturedCharacters);
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
        _appendCapturedOutput(
          stderrBuffer,
          '$message\n',
          maxCapturedCharacters,
        );
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
      _exitCode = intFromValue(exitCodeText, fallback: -1);
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
    _appendCapturedOutput(stdoutBuffer, line, maxCapturedCharacters);
    emitUpdate(phase: BashToolExecutionPhase.running);
  }
}

class _PersistentBashSession {
  _PersistentBashSession({
    required this.process,
    required this.currentWorkingDirectory,
  });

  final Process process;
  String currentWorkingDirectory;
  int lastUsedSerial = 0;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  _PersistentBashExecution? activeExecution;
  Timer? idleTimer;
  Future<void>? cleanupFuture;
  bool starting = true;
  bool inUse = false;
}

class _CancelledPersistentBashExecution implements Exception {
  const _CancelledPersistentBashExecution();
}

class _PersistentBashSessionBusy implements Exception {
  const _PersistentBashSessionBusy();
}

class AiBashToolService {
  static const int defaultTimeoutMs = 120000;
  static const String _disposedMessage = 'Bash 工具服务已释放。';
  static const String _persistentSessionClosingMessage = '持久 Bash 会话正在关闭。';
  static const String _persistentSessionUnavailableMessage = '持久 Bash 会话已不可用。';
  static const String _persistentSessionBusyMessage = '该会话已有 Bash 命令正在运行。';
  static const Duration _processStartTimeout = Duration(seconds: 10);
  static const Duration _persistentStdinTimeout = Duration(seconds: 2);
  static const Duration _subscriptionCancelTimeout = Duration(seconds: 1);
  static const int _maxPersistentSessions = 8;
  static const Duration _persistentSessionIdleTimeout = Duration(minutes: 5);
  static const Duration _persistentShutdownTimeout = Duration(seconds: 5);
  int maxCapturedCharacters = 200000;
  int writeConfirmationTimeoutMs = 300000;
  int fastPathWriteAnalysisThreshold = 512;
  final AiSandboxService sandboxService = AiSandboxService();
  final Map<String, _PersistentBashSession> _persistentSessions =
      <String, _PersistentBashSession>{};
  final Map<String, Future<_PersistentBashSession>> _persistentSessionStarts =
      <String, Future<_PersistentBashSession>>{};
  final Map<String, Future<void>> _persistentSessionCloses =
      <String, Future<void>>{};
  int _persistentMarkerCounter = 0;
  int _persistentUsageSerial = 0;
  int _lastSeenProxyRevision = SystemProxyResolver.instance.revision.value;
  bool _proxyListenerRegistered = false;
  bool _disposed = false;
  Future<void>? _shutdownFuture;

  /// 按需注册：仅当本实例真的会启动 shell 子进程（execute / 持久 session）
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
    // 快照键：在异步关闭过程中可能新增 session。
    final ids = <String>{
      ..._persistentSessions.keys,
      ..._persistentSessionStarts.keys,
    };
    for (final id in ids) {
      unawaited(
        closeSession(id).catchError((Object error, StackTrace stack) {
          silentLog('ai_bash_tool_service', '代理变更后关闭持久会话', error, stack);
        }),
      );
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
    bool dangerouslyDisableSandbox = false,
    bool forceWriteConfirmation = false,
  }) async {
    if (_disposed) {
      throw StateError(_disposedMessage);
    }
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
        stderr: 'Bash 工具命令不能为空。',
        durationMs: 0,
        writeAnalysisReason: '命令为空',
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
    final isWriteCommand = writeAnalysis.isWrite || forceWriteConfirmation;
    final launchSpec = await _prepareLaunchSpec(
      command: normalizedCommand,
      workingDirectory: displayedWorkingDirectory,
      dangerouslyDisableSandbox: dangerouslyDisableSandbox,
    );
    Future<void> closeLaunchProxy() {
      final lease = launchSpec.proxyLease;
      if (lease == null) return Future<void>.value();
      return lease.closeBounded(
        logTag: 'ai_bash_tool_service',
        logWhere: '关闭 Bash 启动代理',
      );
    }

    var launchProxyTransferred = false;
    Future<T> runBeforeLaunchProxyTransfer<T>(
      FutureOr<T> Function() action,
    ) async {
      var completed = false;
      try {
        final result = await action();
        completed = true;
        return result;
      } finally {
        if (!completed && !launchProxyTransferred) {
          await closeLaunchProxy();
        }
      }
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
    if ((requireWriteConfirmation || forceWriteConfirmation) &&
        isWriteCommand) {
      final canSkipConfirmation =
          launchSpec.applied &&
          sandboxService.settings.autoAllowBashIfSandboxed &&
          !forceWriteConfirmation;
      if (!canSkipConfirmation) {
        final missingConfirmationCallback = confirmWriteCommand == null;
        late final _WriteConfirmationOutcome outcome;
        try {
          outcome = await runBeforeLaunchProxyTransfer(() async {
            final confirmationTimeout = Duration(
              milliseconds: writeConfirmationTimeoutMs,
            );
            final requestedAt = DateTime.now().toUtc();
            final approvalDecisionFuture = missingConfirmationCallback
                ? Future<BashCommandApprovalDecision>.value(
                    BashCommandApprovalDecision.rejected,
                  )
                : confirmWriteCommand(
                    BashCommandApprovalRequest(
                      command: normalizedCommand,
                      workingDirectory: displayedWorkingDirectory,
                      isWriteCommand: true,
                      requestedAt: requestedAt,
                      expiresAt: requestedAt.add(confirmationTimeout),
                    ),
                  );
            final approvalFuture = approvalDecisionFuture
                .timeout(confirmationTimeout)
                .then<_WriteConfirmationOutcome>(
                  _WriteConfirmationOutcome.fromDecision,
                );
            if (cancelSignal == null) {
              return approvalFuture;
            }
            return Future.any<_WriteConfirmationOutcome>([
              approvalFuture,
              cancelSignal.then(
                (_) => const _WriteConfirmationOutcome.cancelled(),
                onError: (Object _, StackTrace _) =>
                    const _WriteConfirmationOutcome.cancelled(),
              ),
            ]);
          });
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
            metadata: bashWriteConfirmationMetadata(
              const <String, Object?>{},
              BashCommandApprovalDecision.timedOut,
            ),
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
            metadata: bashWriteConfirmationMetadata(
              const <String, Object?>{},
              BashCommandApprovalDecision.cancelled,
            ),
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
              metadata: bashWriteConfirmationMetadata(
                const <String, Object?>{},
                BashCommandApprovalDecision.rejected,
                missingCallback: missingConfirmationCallback,
              ),
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
              metadata: bashWriteConfirmationMetadata(
                const <String, Object?>{},
                BashCommandApprovalDecision.dismissed,
              ),
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
              metadata: bashWriteConfirmationMetadata(
                const <String, Object?>{},
                BashCommandApprovalDecision.timedOut,
              ),
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
              metadata: bashWriteConfirmationMetadata(
                const <String, Object?>{},
                BashCommandApprovalDecision.cancelled,
              ),
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
      if (persistentResult != null) {
        final sessionExitedUnexpectedly =
            persistentResult.exitCode == -1 &&
            persistentResult.status == BashToolExecutionStatus.failed &&
            persistentResult.stderr.contains('持久 Bash 会话意外退出');
        if (!sessionExitedUnexpectedly) {
          return persistentResult;
        }
      }
    }

    final stopwatch = Stopwatch()..start();
    late final Process process;
    try {
      process = await runBeforeLaunchProxyTransfer(
        () => _startProcess(launchSpec),
      );
    } on TimeoutException {
      stopwatch.stop();
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: normalizedCommand,
        workingDirectory: launchSpec.workingDirectory,
        stdout: '',
        stderr:
            'The process did not start within '
            '${_processStartTimeout.inSeconds} seconds.',
        durationMs: stopwatch.elapsedMilliseconds,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
        sandboxMetadata: sandboxMetadata,
      );
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

    Timer? progressTimer;
    Timer? stallTimer;
    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    var launchSetupCompleted = false;
    try {
      // 子进程派生成功后，把 pid 与 killer 回填到执行登记中心，让 UI 可以显示
      // 真实 pid，并支持用户从工具卡片单独终止此次 Bash 调用。
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

      emitUpdate(phase: BashToolExecutionPhase.running, force: true);
      progressTimer = startSafePeriodicTimer(const Duration(seconds: 1), (_) {
        emitUpdate(phase: BashToolExecutionPhase.running, force: true);
      });
      stallTimer = startSafePeriodicTimer(const Duration(seconds: 5), (_) {
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
      stdoutSubscription = process.stdout.transform(_shellOutputDecoder).listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            lastOutputAtMs = stopwatch.elapsedMilliseconds;
            stallWarningEmitted = false;
          }
          _appendCapturedOutput(stdoutBuffer, chunk, maxCapturedCharacters);
          emitUpdate(phase: BashToolExecutionPhase.running);
        },
      );
      stderrSubscription = process.stderr.transform(_shellOutputDecoder).listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            lastOutputAtMs = stopwatch.elapsedMilliseconds;
            stallWarningEmitted = false;
          }
          _appendCapturedOutput(stderrBuffer, chunk, maxCapturedCharacters);
          emitUpdate(phase: BashToolExecutionPhase.running);
        },
      );
      launchSetupCompleted = true;
    } finally {
      if (!launchSetupCompleted) {
        progressTimer?.cancel();
        stallTimer?.cancel();
        await Future.wait<void>(<Future<void>>[
          _cancelProcessOutputSubscription(stdoutSubscription, 'stdout'),
          _cancelProcessOutputSubscription(stderrSubscription, 'stderr'),
        ]);
        await runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(process),
          onError: (error, stack) =>
              silentLog('ai_bash_tool_service', '清理未完成的 Bash 进程', error, stack),
        );
        stopwatch.stop();
        await closeLaunchProxy();
      }
    }

    int? exitCode;
    var cancelled = false;
    var timedOut = false;
    try {
      // 执行阶段的 finally 从此处接管代理和进程输出资源。
      launchProxyTransferred = true;
      final waitForExit = process.exitCode.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () async {
          timedOut = true;
          _killProcess(process);
          try {
            await process.exitCode.timeout(const Duration(seconds: 2));
          } catch (_) {
            // 强制终止后的清理失败不覆盖原始结果。
          }
          return -1;
        },
      );
      if (cancelSignal != null) {
        Future<int> cancelAndKillProcess() async {
          cancelled = true;
          _killProcess(process);
          try {
            await process.exitCode.timeout(const Duration(seconds: 2));
          } catch (_) {
            // 强制终止后的清理失败不覆盖原始结果。
          }
          return -2;
        }

        exitCode = await Future.any<int>([
          waitForExit,
          cancelSignal.then<int>(
            (_) => cancelAndKillProcess(),
            onError: (Object _, StackTrace _) => cancelAndKillProcess(),
          ),
        ]);
      } else {
        exitCode = await waitForExit;
      }
    } finally {
      progressTimer.cancel();
      stallTimer.cancel();
      await Future.wait<void>(<Future<void>>[
        _cancelProcessOutputSubscription(stdoutSubscription, 'stdout'),
        _cancelProcessOutputSubscription(stderrSubscription, 'stderr'),
      ]);
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

  Future<BashToolExecutionResult?> _executeWithPersistentSession({
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
    final _PersistentBashSession? claimedSession;
    try {
      claimedSession = await _ensurePersistentSession(
        sessionId: sessionId,
        initialWorkingDirectory: fallbackWorkingDirectory,
      );
    } on _PersistentBashSessionBusy {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: fallbackWorkingDirectory,
        stdout: '',
        stderr: _persistentSessionBusyMessage,
        durationMs: 0,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
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
    } on StateError catch (error) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: command,
        workingDirectory: fallbackWorkingDirectory,
        stdout: '',
        stderr: '$error',
        durationMs: 0,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysisReason,
      );
    }
    if (claimedSession == null) return null;
    final session = claimedSession;
    final effectiveWorkingDirectory = requestedWorkingDirectory.isEmpty
        ? session.currentWorkingDirectory
        : requestedWorkingDirectory;
    if (session.activeExecution != null) {
      _releasePersistentSession(sessionId, session);
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: effectiveWorkingDirectory,
        stdout: '',
        stderr: _persistentSessionBusyMessage,
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
      stdoutStartMarker: '$_kCmdStartMarkerPrefix$markerToken',
      stdoutExitMarker: '$_kExitMarkerPrefix$markerToken:',
      stdoutPwdEndMarker: '$_kPwdEndMarkerPrefix$markerToken',
      stopwatch: Stopwatch()..start(),
      onUpdate: onUpdate,
    );
    Timer? progressTimer;
    try {
      session.activeExecution = execution;
      execution.emitUpdate(phase: BashToolExecutionPhase.running, force: true);
      execution.startStallWatcher();
      progressTimer = startSafePeriodicTimer(const Duration(seconds: 1), (_) {
        execution.emitUpdate(
          phase: BashToolExecutionPhase.running,
          force: true,
        );
      });

      final registeredToolCallId = toolCallId;
      if (registeredToolCallId != null && registeredToolCallId.isNotEmpty) {
        AiToolExecutionRegistry.instance.attachPid(
          registeredToolCallId,
          session.process.pid,
        );
        AiToolExecutionRegistry.instance.attachKiller(
          registeredToolCallId,
          () async => _closePersistentSession(sessionId, expected: session),
        );
      }

      session.process.stdin.write(
        _buildPersistentCommandScript(
          command: command,
          markerToken: markerToken,
          workingDirectory: requestedWorkingDirectory,
        ),
      );
      session.process.stdin.write('\n');
      // 立即刷新输入流，避免低吞吐时系统缓冲导致标记误超时。
      await session.process.stdin.flush().timeout(_persistentStdinTimeout);
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
            onError: (Object _, StackTrace _) =>
                throw const _CancelledPersistentBashExecution(),
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
      await _closePersistentSession(sessionId, expected: session);
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
      await _closePersistentSession(sessionId, expected: session);
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
      await _closePersistentSession(sessionId, expected: session);
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
      progressTimer?.cancel();
      execution.cancelStallWatcher();
      if (identical(session.activeExecution, execution)) {
        session.activeExecution = null;
      }
      _releasePersistentSession(sessionId, session);
    }
  }

  Future<AiSandboxLaunchSpec> _prepareLaunchSpec({
    required String command,
    required String workingDirectory,
    required bool dangerouslyDisableSandbox,
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
      dangerouslyDisableSandbox: dangerouslyDisableSandbox,
    );
  }

  Future<Process> _startProcess(AiSandboxLaunchSpec launchSpec) {
    if (Platform.isWindows) {
      return startTrackedProcessBounded(
        launchSpec.executable,
        launchSpec.arguments,
        timeout: _processStartTimeout,
        tag: 'ai_bash_tool_service',
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
  Future<Process> _spawnPosixProcess({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    return startTrackedProcessBounded(
      executable,
      arguments,
      timeout: _processStartTimeout,
      tag: 'ai_bash_tool_service',
      startInNewProcessGroup: true,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  Future<_PersistentBashSession?> _ensurePersistentSession({
    required String sessionId,
    required String initialWorkingDirectory,
  }) async {
    if (_disposed) {
      throw StateError(_disposedMessage);
    }
    if (_persistentSessionCloses.containsKey(sessionId)) {
      throw StateError(_persistentSessionClosingMessage);
    }
    final session = await _getOrStartPersistentSession(
      sessionId: sessionId,
      initialWorkingDirectory: initialWorkingDirectory,
    );
    if (session == null) return null;
    if (_disposed ||
        _persistentSessionCloses.containsKey(sessionId) ||
        !identical(_persistentSessions[sessionId], session)) {
      throw StateError(_persistentSessionUnavailableMessage);
    }
    if (session.inUse) throw const _PersistentBashSessionBusy();
    session
      ..starting = false
      ..inUse = true
      ..lastUsedSerial = ++_persistentUsageSerial;
    session.idleTimer?.cancel();
    session.idleTimer = null;
    return session;
  }

  Future<_PersistentBashSession?> _getOrStartPersistentSession({
    required String sessionId,
    required String initialWorkingDirectory,
  }) async {
    final existing = _persistentSessions[sessionId];
    if (existing != null) {
      return existing;
    }
    final inFlight = _persistentSessionStarts[sessionId];
    if (inFlight != null) {
      return inFlight;
    }
    _PersistentBashSession? evicted;
    if (_persistentSessions.length + _persistentSessionStarts.length >=
        _maxPersistentSessions) {
      evicted = _oldestIdlePersistentSession();
      if (evicted == null) return null;
      _persistentSessions.removeWhere((_, value) => identical(value, evicted));
      evicted.idleTimer?.cancel();
      evicted.idleTimer = null;
    }
    final sessionToEvict = evicted;
    final startFuture = () async {
      if (sessionToEvict != null) {
        await _disposePersistentSession(sessionToEvict);
      }
      if (_disposed || _persistentSessionCloses.containsKey(sessionId)) {
        throw StateError(_persistentSessionClosingMessage);
      }
      return _startPersistentSession(
        sessionId: sessionId,
        initialWorkingDirectory: initialWorkingDirectory,
      );
    }();
    _persistentSessionStarts[sessionId] = startFuture;
    try {
      return await startFuture;
    } finally {
      if (identical(_persistentSessionStarts[sessionId], startFuture)) {
        unawaited(_persistentSessionStarts.remove(sessionId));
      }
    }
  }

  _PersistentBashSession? _oldestIdlePersistentSession() {
    _PersistentBashSession? oldest;
    for (final session in _persistentSessions.values) {
      if (session.starting ||
          session.inUse ||
          session.activeExecution != null) {
        continue;
      }
      if (oldest == null || session.lastUsedSerial < oldest.lastUsedSerial) {
        oldest = session;
      }
    }
    return oldest;
  }

  Future<_PersistentBashSession> _startPersistentSession({
    required String sessionId,
    required String initialWorkingDirectory,
  }) async {
    final shellExecutable = Platform.isWindows
        ? 'cmd'
        : _resolveShellExecutable();
    final shellArgs = Platform.isWindows
        ? const <String>['/Q']
        : const <String>[];
    // 持久 shell 是会话级长寿对象。启动时把当前用户级代理注入为环境变量，
    // 让会话内的 curl / wget / git / npm / pip 等命令默认走代理；切换代理
    // 设置变化时关闭现有 shell，下一条命令会按新代理环境重建。
    final proxyEnv = SystemProxyResolver.instance
        .resolveSubprocessEnvironment();
    final mergedEnvironment = proxyEnv.isEmpty
        ? null
        : mergePlatformEnvironment(proxyEnv);
    final process = await startTrackedProcessBounded(
      shellExecutable,
      shellArgs,
      timeout: _processStartTimeout,
      tag: 'ai_bash_tool_service',
      workingDirectory: initialWorkingDirectory,
      environment: mergedEnvironment,
      startInNewProcessGroup: !Platform.isWindows,
    );
    final session = _PersistentBashSession(
      process: process,
      currentWorkingDirectory: initialWorkingDirectory,
    );
    try {
      if (_disposed || _persistentSessionCloses.containsKey(sessionId)) {
        throw StateError('Bash 工具服务在 Shell 启动期间已释放。');
      }
      // Unix Shell 禁用 glob，避免命令在包装器执行前被元字符展开破坏。
      if (!Platform.isWindows) {
        process.stdin.write(
          'set -o noglob 2>/dev/null || setopt noglob 2>/dev/null || true\n',
        );
        // 刷新失败说明 Shell 传输不可用，按启动失败回收半初始化进程。
        await process.stdin.flush().timeout(_persistentStdinTimeout);
      }

      void handleStreamError(Object error, StackTrace stack) {
        silentLog('ai_bash_tool_service', '持久 Shell 传输', error, stack);
        session.activeExecution?.completeError(error, maxCapturedCharacters);
        unawaited(_closePersistentSession(sessionId, expected: session));
      }

      session.stdoutSubscription = process.stdout
          .transform(_shellOutputDecoder)
          .listen(
            (chunk) {
              session.activeExecution?.appendStdoutChunk(
                chunk,
                maxCapturedCharacters,
              );
            },
            onError: handleStreamError,
            cancelOnError: true,
          );
      session.stderrSubscription = process.stderr
          .transform(_shellOutputDecoder)
          .listen(
            (chunk) {
              session.activeExecution?.appendStderrChunk(
                chunk,
                maxCapturedCharacters,
              );
            },
            onError: handleStreamError,
            cancelOnError: true,
          );
      void handleSessionExit({Object? error, StackTrace? stack}) {
        try {
          final exitError = error ?? StateError('持久 Bash 会话意外退出。');
          final activeExecution = session.activeExecution;
          if (activeExecution != null && !activeExecution.outcome.isCompleted) {
            activeExecution.completeError(exitError, maxCapturedCharacters);
          }
          if (error != null) {
            silentLog('ai_bash_tool_service', '监听持久 Shell 退出', error, stack);
          }
          // 同时终止继承 Shell 管道的子孙进程。
          unawaited(
            _disposePersistentSession(session).catchError((
              Object cleanupError,
              StackTrace cleanupStack,
            ) {
              silentLog(
                'ai_bash_tool_service',
                '清理退出的持久 Shell',
                cleanupError,
                cleanupStack,
              );
            }),
          );
          if (identical(_persistentSessions[sessionId], session)) {
            _persistentSessions.remove(sessionId);
          }
        } catch (exitError, exitStack) {
          silentLog(
            'ai_bash_tool_service',
            '处理持久 Shell 退出',
            exitError,
            exitStack,
          );
        }
      }

      unawaited(
        process.exitCode.then<void>(
          (_) => handleSessionExit(),
          onError: (Object error, StackTrace stack) =>
              handleSessionExit(error: error, stack: stack),
        ),
      );
      if (_disposed || _persistentSessionCloses.containsKey(sessionId)) {
        throw StateError('Bash 工具服务在 Shell 启动期间已释放。');
      }
      _persistentSessions[sessionId] = session;
      return session;
    } catch (_) {
      await _disposePersistentSession(session);
      rethrow;
    }
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
    final startMarker = posixShellQuote('$_kCmdStartMarkerPrefix$markerToken');
    final exitMarker = posixShellQuote('$_kExitMarkerPrefix$markerToken');
    final pwdEndMarker = posixShellQuote('$_kPwdEndMarkerPrefix$markerToken');
    // 多行、复杂引号或 AppleScript 命令改用临时脚本，避免 Shell 误解析。
    final needsSafeWrap = _commandNeedsSafeWrap(command);
    final buffer = StringBuffer()
      ..writeln("printf '%s\\n' $startMarker")
      ..writeln('__OPENHAND_EXIT_CODE=0');
    if (workingDirectory.trim().isNotEmpty) {
      buffer.writeln('if cd ${posixShellQuote(workingDirectory)}; then');
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

  /// 使用 cmd 标记构建 Windows 持久命令脚本。
  String _buildWindowsPersistentCommandScript({
    required String command,
    required String markerToken,
    required String workingDirectory,
  }) {
    final buffer = StringBuffer()
      ..writeln('echo $_kCmdStartMarkerPrefix$markerToken');
    if (workingDirectory.trim().isNotEmpty) {
      // 路径使用双引号，避免目录名中的 Shell 元字符注入。
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
      ..writeln('echo $_kExitMarkerPrefix$markerToken:%__OPENHAND_EXIT_CODE%')
      ..writeln('cd')
      ..writeln('echo $_kPwdEndMarkerPrefix$markerToken');
    return buffer.toString().trimRight();
  }

  /// 判断命令是否需要通过临时脚本原子执行。
  bool _commandNeedsSafeWrap(String command) {
    // 多行命令。
    final trimmed = command.trimRight();
    if (trimmed.contains('\n')) {
      return true;
    }
    // 复杂引号可能与外层 Shell 包装冲突。
    if (command.contains("'\\'") ||
        (command.contains("'") && command.contains('"'))) {
      // osascript 常见嵌套引号。
      return true;
    }
    // osascript 常携带包含特殊字符的 AppleScript。
    if (RegExp(r'^\s*(osascript|automator)\b').hasMatch(command)) {
      return true;
    }
    return false;
  }

  /// 将命令写入临时脚本执行，并在完成后删除脚本。
  void _writeSafeWrappedCommand(
    StringBuffer buffer,
    String command,
    String markerToken,
  ) {
    // 使用命令正文中不存在的单引号 heredoc 标记，阻止展开与分隔符注入。
    var heredocTag = '__OPENHAND_SCRIPT_${markerToken}__';
    var tagSuffix = 0;
    while (command.contains(heredocTag)) {
      tagSuffix += 1;
      heredocTag =
          '__OPENHAND_SCRIPT_${markerToken}_$tagSuffix'
          '__';
    }
    // 临时脚本必须落在 mktemp -d 现开的私有目录（0700、名字不可预测），
    // 不能用 /tmp 下按时间戳拼出的固定名。/tmp 是 1777 世界可写，而
    // markerToken 由 microsecondsSinceEpoch + 自增计数器构成、可预测；
    // `cat >` 会跟随符号链接，本地攻击者预置一个同名软链指向 ~/.zshrc
    // 之类的文件，就能让命令正文覆盖目标并被加上执行位。
    final dirVar = '__OPENHAND_WRAP_DIR_$markerToken';
    final scriptPath = '"\$$dirVar/cmd.sh"';
    buffer
      // macOS 的 BSD mktemp 需要模板参数，GNU mktemp 直接支持 -d；两种都覆盖。
      ..writeln(
        '$dirVar=\$(mktemp -d 2>/dev/null) || '
        '$dirVar=\$(mktemp -d -t openhand_cmd)',
      )
      ..writeln('cat > $scriptPath << ${posixShellQuote(heredocTag)}')
      ..writeln(command)
      ..writeln(heredocTag)
      ..writeln('chmod +x $scriptPath')
      // 当前 Shell 收到信号时尽力删除临时目录。
      ..writeln('trap \'rm -rf "\$$dirVar"\' EXIT INT TERM HUP')
      // 清理前立即保存原始退出码。
      ..writeln('${_resolveShellExecutable()} $scriptPath')
      ..writeln(r'__OPENHAND_WRAP_RC=$?')
      ..writeln('rm -rf "\$$dirVar"')
      ..writeln('trap - EXIT INT TERM HUP')
      // 透传原始退出码。
      ..writeln(r'(exit $__OPENHAND_WRAP_RC)');
  }

  void _releasePersistentSession(
    String sessionId,
    _PersistentBashSession session,
  ) {
    session
      ..inUse = false
      ..lastUsedSerial = ++_persistentUsageSerial;
    if (_disposed || !identical(_persistentSessions[sessionId], session)) {
      return;
    }
    session.idleTimer?.cancel();
    session.idleTimer = startSafeTimer(_persistentSessionIdleTimeout, () async {
      session.idleTimer = null;
      if (_disposed ||
          session.inUse ||
          session.activeExecution != null ||
          !identical(_persistentSessions[sessionId], session)) {
        return;
      }
      await _closePersistentSession(sessionId, expected: session).catchError((
        Object error,
        StackTrace stack,
      ) {
        silentLog('ai_bash_tool_service', '关闭空闲持久会话', error, stack);
      });
    });
  }

  Future<void> closeSession(String sessionId) {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) return Future<void>.value();
    final active = _persistentSessionCloses[normalizedSessionId];
    if (active != null) return active;
    late final Future<void> closeFuture;
    closeFuture = _closeSessionResources(normalizedSessionId).whenComplete(() {
      if (identical(
        _persistentSessionCloses[normalizedSessionId],
        closeFuture,
      )) {
        _persistentSessionCloses.remove(normalizedSessionId);
      }
    });
    _persistentSessionCloses[normalizedSessionId] = closeFuture;
    return closeFuture;
  }

  Future<void> _closeSessionResources(String sessionId) async {
    final session = _persistentSessions.remove(sessionId);
    session?.idleTimer?.cancel();
    final start = _persistentSessionStarts[sessionId];
    await Future.wait<void>(<Future<void>>[
      if (session != null) _disposePersistentSession(session),
      if (start != null)
        start.then<void>(
          _disposePersistentSession,
          onError: (Object _, StackTrace _) {},
        ),
    ]);
  }

  Future<void> _closePersistentSession(
    String sessionId, {
    _PersistentBashSession? expected,
  }) async {
    final session = _persistentSessions[sessionId];
    if (session == null ||
        (expected != null && !identical(session, expected))) {
      return;
    }
    _persistentSessions.remove(sessionId);
    session.idleTimer?.cancel();
    await _disposePersistentSession(session);
  }

  Future<void> _disposePersistentSession(_PersistentBashSession session) {
    session.idleTimer?.cancel();
    session.idleTimer = null;
    final activeCleanup = session.cleanupFuture;
    if (activeCleanup != null) return activeCleanup;
    final cleanup = _performPersistentSessionCleanup(session);
    session.cleanupFuture = cleanup;
    return cleanup;
  }

  Future<void> _performPersistentSessionCleanup(
    _PersistentBashSession session,
  ) async {
    await Future.wait<void>(<Future<void>>[
      _cancelProcessOutputSubscription(session.stdoutSubscription, 'stdout'),
      _cancelProcessOutputSubscription(session.stderrSubscription, 'stderr'),
    ]);
    await runAsyncCleanupBounded(
      () => terminateTrackedProcessTree(session.process),
      timeout: _persistentShutdownTimeout,
      onError: (error, stack) =>
          silentLog('ai_bash_tool_service', '终止持久 Shell 进程树', error, stack),
    );
  }

  Future<void> _cancelProcessOutputSubscription(
    StreamSubscription<String>? subscription,
    String streamName,
  ) async {
    await cancelStreamSubscriptionBounded<String>(
      subscription,
      timeout: _subscriptionCancelTimeout,
      onError: (error, stack) => silentLog(
        'ai_bash_tool_service',
        '取消进程 $streamName 流订阅',
        error,
        stack,
      ),
    );
  }

  String _resolveShellExecutable() {
    return preferredPosixShellExecutable();
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

  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _disposed = true;
    if (_proxyListenerRegistered) {
      SystemProxyResolver.instance.revision.removeListener(
        _onProxyRevisionChanged,
      );
      _proxyListenerRegistered = false;
    }
    final sessions = _persistentSessions.values.toList(growable: false);
    _persistentSessions.clear();
    final starts = _persistentSessionStarts.values.toList(growable: false);
    final closes = _persistentSessionCloses.values.toList(growable: false);
    for (final session in sessions) {
      session.idleTimer?.cancel();
    }
    return _shutdownFuture =
        Future.wait<void>(<Future<void>>[
              for (final session in sessions)
                _disposePersistentSession(session),
              ...closes,
              for (final start in starts)
                start.then<void>(
                  _disposePersistentSession,
                  onError: (Object _, StackTrace _) {},
                ),
            ])
            .timeout(_persistentShutdownTimeout, onTimeout: () => <void>[])
            .then<void>((_) {});
  }

  void dispose() {
    unawaited(
      shutdown().catchError((Object error, StackTrace stack) {
        silentLog('ai_bash_tool_service', '关闭 Bash 工具服务', error, stack);
      }),
    );
  }

  /// 跨平台终止进程：Windows 使用默认终止，POSIX 先 SIGTERM 后 SIGKILL。
  static void _killProcess(Process process) {
    unawaited(
      runAsyncCleanupBounded(
        () => terminateTrackedProcessTree(process),
        onError: (error, stack) =>
            silentLog('ai_bash_tool_service', '终止 Bash 进程树', error, stack),
      ),
    );
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

  /// `$VAR` 形式的变量展开；提到静态字段避免逐字符重编译正则。
  static final RegExp _shellVariablePattern = RegExp(
    r'^\$[A-Za-z_][A-Za-z0-9_]*',
  );

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
    // osascript 不属于只读命令，必须由专用分析器检查脚本正文。
    'pbpaste',
    'say',
    'afplay',
    // 系统检查工具。
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
    // 通过 cmd /c 执行的 Windows 系统检查命令。
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
    // 多用途系统工具要先按子命令判：它们的查询形态只读，但都带有会改系统
    // 状态的子命令，无条件当只读会让这些子命令跳过写命令二次确认。
    if (commandName == 'diskutil' ||
        commandName == 'sysctl' ||
        _systemToolWriteSubcommands.containsKey(commandName)) {
      return _analyzeSystemToolInvocation(commandName, invocation);
    }
    if (_readOnlyCommands.contains(commandName)) {
      return BashWriteAnalysis.readOnly('read-only command $commandName');
    }
    // 剪贴板写入与截图不会修改用户文件。
    if (commandName == 'pbcopy' || commandName == 'screencapture') {
      return BashWriteAnalysis.readOnly(
        'safe side-effect command $commandName',
      );
    }
    // macOS open 仅启动应用或打开 URL。
    if (commandName == 'open' && Platform.isMacOS) {
      return BashWriteAnalysis.readOnly('macOS open command $commandName');
    }
    // defaults 仅在 read 子命令下只读。
    if (commandName == 'defaults') {
      return _analyzeDefaultsInvocation(invocation);
    }
    // AppleScript 可执行命令或注入输入，需检查正文中的写操作动词。
    if (commandName == 'osascript' || commandName == 'osacompile') {
      return _analyzeOsascriptInvocation(invocation);
    }
    // 远程执行可产生任意副作用，默认按写操作处理。
    if (commandName == 'ssh' || commandName == 'doas') {
      return BashWriteAnalysis.write('remote execution command $commandName');
    }
    // tmux/screen 可向其他会话注入输入。
    if (commandName == 'tmux' || commandName == 'screen') {
      return _analyzeMultiplexerInvocation(commandName, invocation);
    }
    // X11 / Wayland 输入注入工具默认按写操作处理。
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

  /// 分析 AppleScript 正文是否包含命令执行、输入注入或状态修改。
  BashWriteAnalysis _analyzeOsascriptInvocation(List<_ShellToken> invocation) {
    // 合并非参数标记内容，统一匹配写操作动词。
    final bodyBuffer = StringBuffer();
    var dynamicScript = false;
    for (final token in invocation.skip(1)) {
      if (token.hasDynamicExpansion) {
        dynamicScript = true;
      }
      final text = token.text;
      // 跳过短参数名，保留分词器拆出的参数值。
      if (text.startsWith('-') && text.length <= 3) {
        continue;
      }
      bodyBuffer
        ..write(text)
        ..write('\n');
    }
    final body = bodyBuffer.toString();
    // 动态拼装的脚本无法可靠检查，按写操作处理。
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

  /// 分析 tmux/screen 是否会修改目标会话。
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
    // 未命中写子命令时按只读处理。
    return BashWriteAnalysis.readOnly(
      '$commandName invocation appears read-only',
    );
  }

  /// 分析输入注入工具；未知子命令按写操作处理。
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

  /// 多用途系统工具：查询形态只读，但都带有会改系统状态的子命令。
  ///
  /// 值是「会改状态」的子命令/开关集合，命中即按写操作处理，走二次确认；
  /// 其余形态（`ip addr`、`sysctl -a`、`diskutil list`）仍判为只读。
  static const Map<String, Set<String>> _systemToolWriteSubcommands =
      <String, Set<String>>{
        // ip link set … down / ip addr del / ip route flush
        'ip': <String>{
          'set',
          'add',
          'change',
          'replace',
          'append',
          'del',
          'delete',
          'flush',
        },
        // route add / delete 改路由表
        'route': <String>{'add', 'delete', 'del', 'change', 'flush'},
        // ifconfig en0 down / alias 会断网或改地址
        'ifconfig': <String>{
          'up',
          'down',
          'add',
          'delete',
          'alias',
          '-alias',
          'mtu',
          'netmask',
          'plumb',
          'unplumb',
        },
        // arp -d 删表项、-s 增静态项
        'arp': <String>{'-d', '-s', '-f'},
        // dmesg -C/--clear 清内核环形缓冲
        'dmesg': <String>{'-c', '-C', '--clear', '--read-clear'},
        // journalctl --vacuum-*/--rotate/--flush 会删日志
        'journalctl': <String>{
          '--rotate',
          '--flush',
          '--sync',
          '--vacuum-size',
          '--vacuum-time',
          '--vacuum-files',
        },
        // wmic … call/set/delete 能终止进程、改系统对象
        'wmic': <String>{'call', 'set', 'delete', 'create'},
      };

  /// diskutil 只有这几个动词是查询，其余（eraseDisk / unmountDisk / repairVolume
  /// / partitionDisk 等）都可能毁数据或卸载卷，故反过来白名单。
  static const Set<String> _diskutilReadOnlyVerbs = <String>{
    'list',
    'info',
    'activity',
    'verifydisk',
    'verifyvolume',
  };

  BashWriteAnalysis _analyzeSystemToolInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    if (commandName == 'diskutil') {
      for (final token in invocation.skip(1)) {
        final value = token.text.toLowerCase();
        if (value.startsWith('-')) continue;
        return _diskutilReadOnlyVerbs.contains(value)
            ? BashWriteAnalysis.readOnly('diskutil $value is read-only')
            : BashWriteAnalysis.write('diskutil $value mutates disks');
      }
      // 裸 diskutil 只打印用法。
      return const BashWriteAnalysis.readOnly('diskutil without subcommand');
    }
    // sysctl 的赋值形态：`sysctl -w k=v` 与 `sysctl k=v` 都会写内核参数。
    if (commandName == 'sysctl') {
      for (final token in invocation.skip(1)) {
        if (token.text == '-w' || token.text.contains('=')) {
          return BashWriteAnalysis.write(
            'sysctl ${token.text} writes kernel parameters',
          );
        }
      }
      return const BashWriteAnalysis.readOnly('sysctl query is read-only');
    }
    final writeSubcommands = _systemToolWriteSubcommands[commandName];
    if (writeSubcommands != null) {
      for (final token in invocation.skip(1)) {
        final value = token.text.toLowerCase();
        if (writeSubcommands.contains(value)) {
          return BashWriteAnalysis.write(
            '$commandName $value mutates system state',
          );
        }
      }
    }
    return BashWriteAnalysis.readOnly('read-only command $commandName');
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
      // 跳过选项。
      if (value.startsWith('-')) continue;
      // 首个未知位置参数按写操作处理。
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
      if (!arg.startsWith('-') && RegExp('^[ctxruA]').hasMatch(arg)) {
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
      final expansionEnd = _readShellExpansion(
        input,
        cursor,
        buffer: buffer,
        nestedCommands: nestedCommands,
      );
      if (expansionEnd != null) {
        hasDynamicExpansion = true;
        cursor = expansionEnd;
        continue;
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

  /// 读取一段 shell 展开：反引号、`$(...)`、`${...}` 与 `$VAR`。
  ///
  /// 未引用词与双引号串对这四种展开的处理规则完全一致，故共用本实现。
  /// 命中时把展开后的文本写入 [buffer]、把嵌套命令登记到 [nestedCommands]，
  /// 并返回新的游标——命中即意味着存在动态展开，由调用方置位对应标记。
  /// 当前字符不是展开起点（如裸 `$` 后跟空格）时返回 null，交回调用方按
  /// 普通字符处理。
  int? _readShellExpansion(
    String input,
    int index, {
    required StringBuffer buffer,
    required List<String> nestedCommands,
  }) {
    final char = input[index];
    if (char == '`') {
      final nested = _readBacktickCommand(input, index);
      buffer.write('`${nested.content}`');
      nestedCommands.add(nested.content);
      return nested.nextIndex;
    }
    if (char != r'$') return null;
    if (index + 1 < input.length && input[index + 1] == '(') {
      final nested = _readBalancedCommand(input, index + 2);
      buffer.write(r'$(${nested.content})');
      nestedCommands.add(nested.content);
      return nested.nextIndex;
    }
    if (index + 1 < input.length && input[index + 1] == '{') {
      final closing = input.indexOf('}', index + 2);
      if (closing == -1) {
        buffer.write(input.substring(index));
        return input.length;
      }
      buffer.write(input.substring(index, closing + 1));
      return closing + 1;
    }
    final variableMatch = _shellVariablePattern.matchAsPrefix(
      input.substring(index),
    );
    if (variableMatch == null) return null;
    buffer.write(variableMatch.group(0));
    return index + variableMatch.group(0)!.length;
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
      final expansionEnd = _readShellExpansion(
        input,
        cursor,
        buffer: buffer,
        nestedCommands: nestedCommands,
      );
      if (expansionEnd != null) {
        hasDynamicExpansion = true;
        cursor = expansionEnd;
        continue;
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
    return RegExp('^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(value);
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
    if (RegExp('(^|[^<])>>?|>|>>').hasMatch(normalized)) {
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
