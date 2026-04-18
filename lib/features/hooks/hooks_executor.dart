import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/model/hook_config.dart';
import '../../app/support/openhand_paths.dart';
import 'hooks_controller.dart';

/// Maximum characters to collect from hook script stdout / stderr.
const int _maxHookOutputCharacters = 4000;

/// Hard ceiling to prevent a misconfigured timeout from blocking indefinitely.
const int _maxHookTimeoutSeconds = 60;

/// Result of executing all hooks for a single event.
class HookExecutionResult {
  const HookExecutionResult({
    this.executedCount = 0,
    this.successCount = 0,
    this.failedCount = 0,
    this.timedOutCount = 0,
    this.blocked = false,
    this.blockReason,
    this.errors = const <String>[],
    this.hookResults = const <HookEntryResult>[],
  });

  final int executedCount;
  final int successCount;
  final int failedCount;
  final int timedOutCount;
  final bool blocked;
  final String? blockReason;
  final List<String> errors;
  final List<HookEntryResult> hookResults;

  bool get hasErrors => errors.isNotEmpty;
}

/// Detailed result for a single hook execution.
class HookEntryResult {
  const HookEntryResult({
    required this.hookLabel,
    required this.hookEvent,
    required this.status,
    required this.elapsedMs,
    this.stdout = '',
    this.stderr = '',
    this.scriptPath,
    this.scriptContent,
  });

  final String hookLabel;
  final HookEvent hookEvent;

  /// One of: 'success', 'failed', 'timed_out', 'blocked'.
  final String status;
  final int elapsedMs;
  final String stdout;
  final String stderr;
  final String? scriptPath;
  final String? scriptContent;
}

/// Public executor that runs hooks for a given event. Designed to be called
/// from AI session controllers and other orchestration layers.
///
/// This class is intentionally stateless — it reads the enabled hooks from the
/// [HooksController] each time [executeEvent] is called, ensuring it always
/// reflects the latest user configuration.
class HooksExecutor {
  const HooksExecutor({required HooksController controller})
      : _controller = controller;

  final HooksController _controller;

  /// Execute all enabled hooks for [event].
  ///
  /// [sessionId] and [payload] are forwarded to each hook script via stdin as
  /// a JSON object. Returns a summary result with execution counts and errors.
  ///
  /// Each hook is executed sequentially. If any hook exits with code 2, the
  /// remaining hooks are skipped and the result is marked as blocked (matching
  /// the existing AiClaudeHookService convention).
  Future<HookExecutionResult> executeEvent({
    required HookEvent event,
    required String sessionId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    final hooks = _controller.enabledHooksForEvent(event);
    if (hooks.isEmpty) {
      return const HookExecutionResult();
    }

    final errors = <String>[];
    var successCount = 0;
    var failedCount = 0;
    var timedOutCount = 0;
    String? blockReason;
    final hookResults = <HookEntryResult>[];

    final effectivePayload = <String, Object?>{
      'hook_event_name': event.storageValue,
      'session_id': sessionId,
      ...payload,
    };

    for (final hook in hooks) {
      final stopwatch = Stopwatch()..start();
      try {
        final result = await _runHookScript(
          hook: hook,
          payload: effectivePayload,
        );
        stopwatch.stop();
        if (result.timedOut) {
          timedOutCount++;
          errors.add(
            'Hook "${hook.label}" timed out after ${hook.timeoutSeconds}s.',
          );
          hookResults.add(HookEntryResult(
            hookLabel: hook.label,
            hookEvent: hook.event,
            status: 'timed_out',
            elapsedMs: stopwatch.elapsedMilliseconds,
            stdout: result.stdout,
            stderr: result.stderr,
            scriptPath: hook.scriptPath,
            scriptContent: hook.scriptContent,
          ));
          continue;
        }
        if (result.exitCode == 2) {
          failedCount++;
          blockReason = result.stdout.isNotEmpty
              ? result.stdout
              : 'Blocked by hook "${hook.label}".';
          hookResults.add(HookEntryResult(
            hookLabel: hook.label,
            hookEvent: hook.event,
            status: 'blocked',
            elapsedMs: stopwatch.elapsedMilliseconds,
            stdout: result.stdout,
            stderr: result.stderr,
            scriptPath: hook.scriptPath,
            scriptContent: hook.scriptContent,
          ));
          break;
        }
        if (result.exitCode != null && result.exitCode != 0) {
          failedCount++;
          errors.add(
            'Hook "${hook.label}" exited with code ${result.exitCode}.'
            '${result.stderr.isNotEmpty ? ' stderr: ${result.stderr}' : ''}',
          );
          hookResults.add(HookEntryResult(
            hookLabel: hook.label,
            hookEvent: hook.event,
            status: 'failed',
            elapsedMs: stopwatch.elapsedMilliseconds,
            stdout: result.stdout,
            stderr: result.stderr,
            scriptPath: hook.scriptPath,
            scriptContent: hook.scriptContent,
          ));
          continue;
        }
        successCount++;
        hookResults.add(HookEntryResult(
          hookLabel: hook.label,
          hookEvent: hook.event,
          status: 'success',
          elapsedMs: stopwatch.elapsedMilliseconds,
          stdout: result.stdout,
          stderr: result.stderr,
          scriptPath: hook.scriptPath,
          scriptContent: hook.scriptContent,
        ));
      } catch (error) {
        stopwatch.stop();
        failedCount++;
        errors.add('Hook "${hook.label}" failed to start: $error');
        hookResults.add(HookEntryResult(
          hookLabel: hook.label,
          hookEvent: hook.event,
          status: 'failed',
          elapsedMs: stopwatch.elapsedMilliseconds,
          stderr: '$error',
          scriptPath: hook.scriptPath,
          scriptContent: hook.scriptContent,
        ));
      }
    }

    return HookExecutionResult(
      executedCount: successCount + failedCount + timedOutCount,
      successCount: successCount,
      failedCount: failedCount,
      timedOutCount: timedOutCount,
      blocked: blockReason != null,
      blockReason: blockReason,
      errors: errors,
      hookResults: hookResults,
    );
  }

  Future<_HookScriptResult> _runHookScript({
    required HookEntry hook,
    required Map<String, Object?> payload,
  }) async {
    final timeout = Duration(
      seconds: hook.timeoutSeconds
          .clamp(1, _maxHookTimeoutSeconds),
    );
    final shellCommand = _buildCommand(hook);
    final workingDirectory = OpenHandPaths.applicationDirectoryPath();

    final process = await Process.start(
      shellCommand.executable,
      shellCommand.arguments,
      workingDirectory: workingDirectory,
    );

    final stdoutFuture = _collectTruncated(process.stdout);
    final stderrFuture = _collectTruncated(process.stderr);

    process.stdin.write(jsonEncode(payload));
    await process.stdin.close();

    try {
      final exitCode = await process.exitCode.timeout(timeout);
      return _HookScriptResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
        timedOut: false,
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Best-effort cleanup; the process may remain orphaned on some OSes.
      }
      return _HookScriptResult(
        exitCode: null,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
        timedOut: true,
      );
    }
  }

  _ShellCommand _buildCommand(HookEntry hook) {
    // If a script file path is set, execute that file directly.
    if (hook.scriptPath != null && hook.scriptPath!.isNotEmpty) {
      return _buildFileCommand(hook.scriptPath!);
    }
    // Otherwise, execute inline script content via the platform shell.
    final content = hook.scriptContent ?? '';
    if (Platform.isWindows) {
      return _ShellCommand(
        executable: 'cmd.exe',
        arguments: <String>['/C', content],
      );
    }
    final zsh = File('/bin/zsh');
    if (zsh.existsSync()) {
      return _ShellCommand(
        executable: zsh.path,
        arguments: <String>['-lc', content],
      );
    }
    return _ShellCommand(
      executable: '/bin/sh',
      arguments: <String>['-lc', content],
    );
  }

  _ShellCommand _buildFileCommand(String scriptPath) {
    if (Platform.isWindows) {
      final lowerPath = scriptPath.toLowerCase();
      if (lowerPath.endsWith('.ps1')) {
        return _ShellCommand(
          executable: 'powershell.exe',
          arguments: <String>[
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptPath,
          ],
        );
      }
      // .bat or .cmd
      return _ShellCommand(
        executable: 'cmd.exe',
        arguments: <String>['/C', scriptPath],
      );
    }
    // macOS / Linux — execute as shell script.
    final zsh = File('/bin/zsh');
    if (zsh.existsSync()) {
      return _ShellCommand(
        executable: zsh.path,
        arguments: <String>['-l', scriptPath],
      );
    }
    return _ShellCommand(
      executable: '/bin/sh',
      arguments: <String>[scriptPath],
    );
  }

  Future<String> _collectTruncated(Stream<List<int>> stream) async {
    final buffer = StringBuffer();
    var collected = 0;
    var truncated = false;
    await for (final chunk in stream.transform(utf8.decoder)) {
      if (truncated) continue;
      final remaining = _maxHookOutputCharacters - collected;
      if (remaining <= 0) {
        truncated = true;
        continue;
      }
      if (chunk.length <= remaining) {
        buffer.write(chunk);
        collected += chunk.length;
      } else {
        buffer.write(chunk.substring(0, remaining));
        collected += remaining;
        truncated = true;
      }
    }
    final text = buffer.toString().trim();
    if (!truncated) return text;
    return text.isEmpty ? '...[truncated]' : '$text\n...[truncated]';
  }
}

class _HookScriptResult {
  const _HookScriptResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });

  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
}

class _ShellCommand {
  const _ShellCommand({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}
