import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../app/model/cron_config.dart';
import '../../../app/support/app_runtime_context.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/exponential_backoff.dart';
import '../../../shared/util/text_clip.dart';

const int _maxCronOutputCharacters = 8000;
const int _maxCronOutputBytes = _maxCronOutputCharacters * 4;

/// Handle returned for a running cron execution.
class CronExecutionHandle {
  const CronExecutionHandle({required this.result, required this.cancel});

  final Future<CronExecutionRecord> result;
  final void Function() cancel;
}

/// Executes a single cron job script with timeout, retry, and resource cleanup.
class CronExecutor {
  CronExecutor._();

  static const Uuid _uuid = Uuid();

  /// Starts a cancellable cron execution.
  static CronExecutionHandle start(
    CronEntry entry, {
    String triggerType = 'scheduled',
    Map<String, String> runtimeContext = const <String, String>{},
  }) {
    final cancellationToken = _ExecutionCancelToken();
    final result = _executeInternal(
      entry,
      triggerType: triggerType,
      runtimeContext: runtimeContext,
      cancellationToken: cancellationToken,
    );
    return CronExecutionHandle(
      result: result,
      cancel: cancellationToken.cancel,
    );
  }

  static Future<CronExecutionRecord> _executeInternal(
    CronEntry entry, {
    required String triggerType,
    required Map<String, String> runtimeContext,
    required _ExecutionCancelToken cancellationToken,
  }) async {
    final id = _uuid.v4();
    final startedAt = DateTime.now();
    final effectiveTimeout = Duration(
      seconds: clampCronTimeoutSeconds(entry.timeoutSeconds),
    );
    final maxRetries = clampCronRetryCount(entry.retryCount);
    final appContext = <String, String>{
      ...AppRuntimeContext.captureContext(
        includeAppMetadata: entry.collectAppMetadata,
        includeHostMetadata: entry.collectHostMetadata,
      ),
      ...runtimeContext,
      'cron.id': entry.id,
      'cron.name': entry.name,
      'cron.trigger_type': triggerType,
      'cron.script_type': entry.scriptType.storageValue,
      'cron.timeout_seconds': '${entry.timeoutSeconds}',
      'cron.retry_count': '${entry.retryCount}',
    };
    final environmentSnapshot = entry.collectEnvironmentSnapshot
        ? AppRuntimeContext.captureEnvironmentSnapshot(entry.environment)
        : const <String, String>{};

    String lastStdout = '';
    String lastStderr = '';
    String? lastError;
    int? lastExitCode;
    int? lastPid;
    int attempt = 0;

    for (attempt = 0; attempt <= maxRetries; attempt++) {
      if (cancellationToken.isCancelled) {
        return _buildRecord(
          id: id,
          entry: entry,
          startedAt: startedAt,
          status: 'killed',
          stdout: lastStdout,
          stderr: lastStderr,
          errorMessage: 'Cancelled due to application shutdown',
          retryAttempt: attempt,
          exitCode: lastExitCode,
          pid: lastPid,
          triggerType: triggerType,
          appContext: appContext,
          environmentSnapshot: environmentSnapshot,
        );
      }

      if (attempt > 0) {
        // Exponential back-off with cap (shared with WebEngineBase via
        // [exponentialBackoffSeconds]; both keep a base=1 unit, cap=user/cap_max).
        final delay = Duration(
          seconds: exponentialBackoffSeconds(
            attempt: attempt,
            baseSeconds: 1,
            capSeconds: clampCronRetryDelaySeconds(entry.maxRetryDelaySeconds),
          ),
        );
        await delayUntilCancelled(
          delay,
          cancelSignal: cancellationToken.cancelled,
        );
        if (cancellationToken.isCancelled) {
          return _buildRecord(
            id: id,
            entry: entry,
            startedAt: startedAt,
            status: 'killed',
            stdout: lastStdout,
            stderr: lastStderr,
            errorMessage: 'Cancelled due to application shutdown',
            retryAttempt: attempt,
            exitCode: lastExitCode,
            pid: lastPid,
            triggerType: triggerType,
            appContext: appContext,
            environmentSnapshot: environmentSnapshot,
          );
        }
      }

      try {
        final result = await _runOnce(
          entry: entry,
          timeout: effectiveTimeout,
          cancellationToken: cancellationToken,
        );
        lastStdout = result.stdout;
        lastStderr = result.stderr;
        lastExitCode = result.exitCode;
        lastPid = result.pid;
        lastError = result.error;

        if (result.killed || cancellationToken.isCancelled) {
          return _buildRecord(
            id: id,
            entry: entry,
            startedAt: startedAt,
            status: 'killed',
            stdout: lastStdout,
            stderr: lastStderr,
            errorMessage: lastError ?? 'Cancelled due to application shutdown',
            retryAttempt: attempt,
            exitCode: lastExitCode,
            pid: lastPid,
            triggerType: triggerType,
            appContext: appContext,
            environmentSnapshot: environmentSnapshot,
          );
        }

        if (result.timedOut) {
          lastError ??= 'Timed out after ${entry.timeoutSeconds}s';
          // On timeout, attempt retry if allowed.
          if (attempt < maxRetries) continue;
          return _buildRecord(
            id: id,
            entry: entry,
            startedAt: startedAt,
            status: 'timed_out',
            stdout: lastStdout,
            stderr: lastStderr,
            errorMessage: lastError,
            retryAttempt: attempt,
            exitCode: lastExitCode,
            pid: lastPid,
            triggerType: triggerType,
            appContext: appContext,
            environmentSnapshot: environmentSnapshot,
          );
        }

        if (lastExitCode == 0) {
          return _buildRecord(
            id: id,
            entry: entry,
            startedAt: startedAt,
            status: 'success',
            stdout: lastStdout,
            stderr: lastStderr,
            retryAttempt: attempt,
            exitCode: 0,
            pid: lastPid,
            triggerType: triggerType,
            appContext: appContext,
            environmentSnapshot: environmentSnapshot,
          );
        }

        // Non-zero exit — retry if allowed.
        lastError ??= 'Exited with code $lastExitCode';
        if (attempt < maxRetries) continue;

        return _buildRecord(
          id: id,
          entry: entry,
          startedAt: startedAt,
          status: 'failed',
          stdout: lastStdout,
          stderr: lastStderr,
          errorMessage: lastError,
          retryAttempt: attempt,
          exitCode: lastExitCode,
          pid: lastPid,
          triggerType: triggerType,
          appContext: appContext,
          environmentSnapshot: environmentSnapshot,
        );
      } catch (e) {
        lastError = '$e';
        if (attempt < maxRetries) continue;
        return _buildRecord(
          id: id,
          entry: entry,
          startedAt: startedAt,
          status: 'failed',
          stdout: lastStdout,
          stderr: lastStderr,
          errorMessage: lastError,
          retryAttempt: attempt,
          exitCode: lastExitCode,
          pid: lastPid,
          triggerType: triggerType,
          appContext: appContext,
          environmentSnapshot: environmentSnapshot,
        );
      }
    }

    // Should not reach here, but just in case.
    return _buildRecord(
      id: id,
      entry: entry,
      startedAt: startedAt,
      status: 'failed',
      stdout: lastStdout,
      stderr: lastStderr,
      errorMessage: lastError ?? 'Unknown error',
      retryAttempt: attempt,
      exitCode: lastExitCode,
      pid: lastPid,
      triggerType: triggerType,
      appContext: appContext,
      environmentSnapshot: environmentSnapshot,
    );
  }

  static Future<_RunResult> _runOnce({
    required CronEntry entry,
    required Duration timeout,
    required _ExecutionCancelToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return const _RunResult(
        killed: true,
        error: 'Cancelled before process start',
      );
    }

    final cmd = _buildCommand(entry);
    final workDir =
        entry.workingDirectory ?? OpenHandPaths.applicationDirectoryPath();

    ProcessResult? result;
    int? pid;
    var timedOut = false;
    try {
      result = await runProcessWithTimeout(
        cmd.executable,
        cmd.arguments,
        workingDirectory: workDir,
        environment: <String, String>{
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
          if (entry.environment.isNotEmpty) ...entry.environment,
        },
        timeout: timeout,
        tag: 'cron_executor',
        maxStdoutBytes: _maxCronOutputBytes,
        maxStderrBytes: _maxCronOutputBytes,
        outputDecoder: const SystemEncoding().decoder,
        onProcessStarted: (process) {
          pid = process.pid;
          // The setter is retroactive: cancellation during spawn immediately
          // terminates the process tree once the handle becomes available.
          cancellationToken.onCancel = () {
            unawaited(terminateTrackedProcessTree(process));
          };
        },
        timeoutResultBuilder: (processId, stdout, stderr) {
          timedOut = true;
          return ProcessResult(processId, -1, stdout, stderr);
        },
      );
    } finally {
      cancellationToken.clearOnCancel();
    }

    final killed = cancellationToken.isCancelled;
    if (result == null) {
      return _RunResult(
        killed: killed,
        error: killed ? null : 'Failed to start cron process',
        pid: pid,
      );
    }
    final exitCode = result.exitCode;

    return _RunResult(
      exitCode: exitCode,
      stdout: clipText(
        result.stdout as String,
        _maxCronOutputCharacters,
        suffix: '',
      ),
      stderr: clipText(
        result.stderr as String,
        _maxCronOutputCharacters,
        suffix: '',
      ),
      timedOut: timedOut && !killed,
      killed: killed,
      pid: pid ?? (result.pid > 0 ? result.pid : null),
    );
  }

  static CronExecutionRecord _buildRecord({
    required String id,
    required CronEntry entry,
    required DateTime startedAt,
    required String status,
    required String stdout,
    required String stderr,
    required int retryAttempt,
    required String triggerType,
    required Map<String, String> appContext,
    required Map<String, String> environmentSnapshot,
    String? errorMessage,
    int? exitCode,
    int? pid,
  }) {
    return CronExecutionRecord(
      id: id,
      cronId: entry.id,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      status: status,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      errorMessage: errorMessage,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      retryAttempt: retryAttempt,
      runAsUser: entry.runAsUser,
      workingDirectory: entry.workingDirectory,
      environment: entry.environment,
      appContext: appContext,
      environmentSnapshot: environmentSnapshot,
      pid: pid,
      triggerType: triggerType,
    );
  }

  static _ShellCommand _buildCommand(CronEntry entry) {
    if (entry.scriptPath != null && entry.scriptPath!.isNotEmpty) {
      // File-based script.
      if (Platform.isWindows) {
        final ext = p.extension(entry.scriptPath!).toLowerCase();
        if (ext == '.ps1') {
          return _ShellCommand('powershell', [
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            entry.scriptPath!,
          ]);
        }
        return _ShellCommand('cmd', ['/c', entry.scriptPath!]);
      }
      if (entry.runAsUser != null && entry.runAsUser!.isNotEmpty) {
        return _ShellCommand('sudo', [
          '-u',
          entry.runAsUser!,
          'bash',
          entry.scriptPath!,
        ]);
      }
      return _ShellCommand('bash', [entry.scriptPath!]);
    }

    // Inline script / command.
    final content = entry.scriptContent ?? '';
    if (Platform.isWindows) {
      return _ShellCommand('powershell', ['-Command', content]);
    }
    if (entry.runAsUser != null && entry.runAsUser!.isNotEmpty) {
      return _ShellCommand('sudo', [
        '-u',
        entry.runAsUser!,
        'bash',
        '-c',
        content,
      ]);
    }
    return _ShellCommand('bash', ['-c', content]);
  }
}

class _ShellCommand {
  const _ShellCommand(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;
}

class _RunResult {
  const _RunResult({
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.killed = false,
    this.error,
    this.pid,
  });

  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool killed;
  final String? error;
  final int? pid;
}

class _ExecutionCancelToken {
  final Completer<void> _cancelCompleter = Completer<void>();
  void Function()? _onCancel;

  bool get isCancelled => _cancelCompleter.isCompleted;

  Future<void> get cancelled => _cancelCompleter.future;

  set onCancel(void Function() callback) {
    _onCancel = callback;
    if (isCancelled) {
      callback();
    }
  }

  void clearOnCancel() => _onCancel = null;

  void cancel() {
    if (isCancelled) return;
    _cancelCompleter.complete();
    _onCancel?.call();
  }
}
