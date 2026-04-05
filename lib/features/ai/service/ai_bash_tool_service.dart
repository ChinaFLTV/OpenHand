import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/openhand_paths.dart';
import '../model/ai_deny_command_rule.dart';

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
  });

  final BashToolExecutionPhase phase;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int durationMs;
  final int? exitCode;
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
    required this.approved,
    required this.cancelled,
  });

  const _WriteConfirmationOutcome.approved()
    : this._(approved: true, cancelled: false);

  const _WriteConfirmationOutcome.rejected()
    : this._(approved: false, cancelled: false);

  const _WriteConfirmationOutcome.cancelled()
    : this._(approved: false, cancelled: true);

  final bool approved;
  final bool cancelled;
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

  void appendStdoutChunk(String chunk, int maxCapturedCharacters) {
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
  static const int defaultTimeoutMs = 120000;
  static const int maxCapturedCharacters = 32000;
  static const int _writeConfirmationTimeoutMs = 300000;
  static const int _fastPathWriteAnalysisThreshold = 512;
  final Map<String, _PersistentBashSession> _persistentSessions =
      <String, _PersistentBashSession>{};
  int _persistentMarkerCounter = 0;

  Future<BashToolExecutionResult> execute({
    required String command,
    String? sessionId,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = defaultTimeoutMs,
  }) async {
    final normalizedCommand = command.trim();
    final normalizedSessionId = (sessionId ?? '').trim();
    final shouldUsePersistentSession = normalizedSessionId.isNotEmpty;
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
    if (requireWriteConfirmation && isWriteCommand) {
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
                          const Duration(
                            milliseconds: _writeConfirmationTimeoutMs,
                          ),
                        ) ??
                    Future<bool>.value(false))
                .then<_WriteConfirmationOutcome>(
                  (approved) => approved
                      ? const _WriteConfirmationOutcome.approved()
                      : const _WriteConfirmationOutcome.rejected(),
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
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.rejected,
          command: normalizedCommand,
          workingDirectory: displayedWorkingDirectory,
          stdout: '',
          stderr:
              'The command confirmation timed out before the user approved execution.',
          durationMs: 0,
          isWriteCommand: isWriteCommand,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
      if (outcome.cancelled) {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.cancelled,
          command: normalizedCommand,
          workingDirectory: displayedWorkingDirectory,
          stdout: '',
          stderr:
              'The command execution was cancelled before confirmation completed.',
          durationMs: 0,
          isWriteCommand: isWriteCommand,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
      if (!outcome.approved) {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.rejected,
          command: normalizedCommand,
          workingDirectory: displayedWorkingDirectory,
          stdout: '',
          stderr:
              'The command was rejected because write-command confirmation was not granted by the user.',
          durationMs: 0,
          isWriteCommand: isWriteCommand,
          writeAnalysisReason: writeAnalysis.reason,
        );
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
      process = await _startProcess(
        normalizedCommand,
        normalizedWorkingDirectory,
      );
    } on ProcessException catch (error) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: normalizedCommand,
        workingDirectory: normalizedWorkingDirectory,
        stdout: '',
        stderr: error.message,
        durationMs: stopwatch.elapsedMilliseconds,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var lastRunningEmitMs = -1;

    void emitUpdate({
      required BashToolExecutionPhase phase,
      bool force = false,
      int? exitCode,
    }) {
      if (onUpdate == null) {
        return;
      }
      final durationMs = stopwatch.elapsedMilliseconds;
      if (phase == BashToolExecutionPhase.running &&
          !force &&
          lastRunningEmitMs != -1 &&
          durationMs - lastRunningEmitMs < 160) {
        return;
      }
      if (phase == BashToolExecutionPhase.running) {
        lastRunningEmitMs = durationMs;
      }
      onUpdate(
        BashToolExecutionUpdate(
          phase: phase,
          command: normalizedCommand,
          workingDirectory: normalizedWorkingDirectory,
          stdout: stdoutBuffer.toString(),
          stderr: stderrBuffer.toString(),
          durationMs: durationMs,
          exitCode: exitCode,
        ),
      );
    }

    emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    });
    final stdoutSubscription = process.stdout
        .transform(_shellOutputDecoder)
        .listen((chunk) {
          _appendChunk(stdoutBuffer, chunk);
          emitUpdate(phase: BashToolExecutionPhase.running);
        });
    final stderrSubscription = process.stderr
        .transform(_shellOutputDecoder)
        .listen((chunk) {
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
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      stopwatch.stop();
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
        workingDirectory: normalizedWorkingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString().isEmpty
            ? 'The command was cancelled by the user.'
            : stderrBuffer.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitCode: exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
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
        workingDirectory: normalizedWorkingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString().isEmpty
            ? 'The command timed out before completion.'
            : stderrBuffer.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitCode: exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
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
      workingDirectory: normalizedWorkingDirectory,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      durationMs: stopwatch.elapsedMilliseconds,
      exitCode: exitCode,
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: writeAnalysis.reason,
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
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      execution.emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    });

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
      if (identical(session.activeExecution, execution)) {
        session.activeExecution = null;
      }
    }
  }

  Future<Process> _startProcess(String command, String workingDirectory) {
    if (Platform.isWindows) {
      return Process.start(
        'cmd',
        <String>['/c', command],
        workingDirectory: workingDirectory,
      );
    }
    final shellExecutable = _resolveShellExecutable();
    return Process.start(
      shellExecutable,
      <String>['-lc', command],
      workingDirectory: workingDirectory,
    );
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
    final process = await Process.start(
      shellExecutable,
      shellArgs,
      workingDirectory: initialWorkingDirectory,
    );
    final session = _PersistentBashSession(
      process: process,
      currentWorkingDirectory: initialWorkingDirectory,
    );
    // For Unix shells, disable glob expansion so that commands containing
    // special characters (e.g. osascript with AppleScript strings that include
    // brackets, asterisks, question marks) don't trigger "bad pattern" errors.
    if (!Platform.isWindows) {
      process.stdin.write('set -o noglob 2>/dev/null || setopt noglob 2>/dev/null || true\n');
      // Flush so the shell processes the noglob setup before the first command.
      try {
        await process.stdin.flush();
      } catch (_) {}
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
      buffer
        ..writeln('cd /d "$workingDirectory" && (')
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
    // with the outer shell wrapper.
    if (command.contains("'\\'") ||
        command.contains('\'') && command.contains('"')) {
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
    final heredocTag = '__OPENHAND_SCRIPT_${markerToken}__';
    final tmpScriptPath = '/tmp/.openhand_cmd_$markerToken.sh';
    buffer
      ..writeln('cat > ${_quoteShellString(tmpScriptPath)} << ${_quoteShellString(heredocTag)}')
      ..writeln(command)
      ..writeln(heredocTag)
      ..writeln('chmod +x ${_quoteShellString(tmpScriptPath)}')
      // Run the script and immediately capture its exit code before any
      // cleanup commands can overwrite it.
      ..writeln('${_resolveShellExecutable()} ${_quoteShellString(tmpScriptPath)}')
      ..writeln(r'__OPENHAND_WRAP_RC=$?')
      ..writeln('rm -f ${_quoteShellString(tmpScriptPath)}')
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
    _killProcess(session.process);
    await session.stdoutSubscription?.cancel();
    await session.stderrSubscription?.cancel();
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
    if (command.length < _fastPathWriteAnalysisThreshold) {
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
    final sessionIds = _persistentSessions.keys.toList(growable: false);
    for (final sessionId in sessionIds) {
      final session = _persistentSessions.remove(sessionId);
      if (session == null) {
        continue;
      }
      _killProcess(session.process);
      session.stdoutSubscription?.cancel();
      session.stderrSubscription?.cancel();
    }
  }

  /// Kill a process in a platform-safe way.  On Windows, [ProcessSignal.sigkill]
  /// is not supported, so we fall back to the default [Process.kill] which
  /// calls `TerminateProcess`.
  static void _killProcess(Process process) {
    if (Platform.isWindows) {
      process.kill();
    } else {
      process.kill(ProcessSignal.sigkill);
    }
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
    'osascript',
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
      return BashWriteAnalysis.readOnly(
        'macOS open command $commandName',
      );
    }
    // `defaults read` is read-only; `defaults write/delete` mutates.
    if (commandName == 'defaults') {
      return _analyzeDefaultsInvocation(invocation);
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

  BashWriteAnalysis _analyzeDefaultsInvocation(List<_ShellToken> invocation) {
    for (final token in invocation.skip(1)) {
      final value = token.text;
      if (value == 'read' || value == 'read-type' || value == 'domains' ||
          value == 'find' || value == 'help') {
        return BashWriteAnalysis.readOnly('defaults $value is read-only');
      }
      if (value == 'write' || value == 'delete' || value == 'rename' ||
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
      return const BashWriteAnalysis.write('awk programs can write files and state');
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
