import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/model/hook_config.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/system_proxy.dart';
import '../hooks_controller.dart';

/// Maximum characters to collect from hook script stdout / stderr.
const int _maxHookOutputCharacters = 4000;

/// Hard ceiling to prevent a misconfigured timeout from blocking indefinitely.
const int _maxHookTimeoutSeconds = 60;

/// Maximum size (bytes) of the context JSON written to the temp file.
/// Prevents a misconfigured or malicious payload from exhausting disk space.
const int _maxContextJsonBytes = 512 * 1024; // 512 KB

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
    this.stdoutFile,
    this.stderrFile,
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

  /// Path to file containing the full (non-truncated) stdout, if truncated.
  final String? stdoutFile;

  /// Path to file containing the full (non-truncated) stderr, if truncated.
  final String? stderrFile;
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

  bool hasEnabledHooksForEvent(HookEvent event) {
    return _controller.enabledHooksForEvent(event).isNotEmpty;
  }

  /// Maximum age of files left behind in the hooks temp directory. Files
  /// older than this are removed on startup to prevent unbounded growth from
  /// truncated-output saves and context files that leaked due to crashes.
  static const Duration _tmpFileMaxAge = Duration(days: 7);

  /// Best-effort cleanup of stale hook artifacts under
  /// `~/.openhand/hooks/tmp/`. Invoked once at application startup. The
  /// operation is tolerant of every IO failure mode — it never throws.
  static Future<void> pruneStaleTempFiles() async {
    try {
      final tmpDir = Directory(
        p.join(OpenHandPaths.homeDirectoryPath(), '.openhand', 'hooks', 'tmp'),
      );
      if (!await tmpDir.exists()) return;
      final cutoff = DateTime.now().subtract(_tmpFileMaxAge);
      await for (final entity in tmpDir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } on FileSystemException {
          // Best-effort — skip files we cannot stat or delete.
        }
      }
    } on FileSystemException {
      // Never propagate cleanup failures to the application.
    }
  }

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
          sessionId: sessionId,
          payload: effectivePayload,
        );
        stopwatch.stop();
        if (result.timedOut) {
          timedOutCount++;
          errors.add(
            'Hook "${hook.label}" timed out after ${hook.timeoutSeconds}s.',
          );
          hookResults.add(
            HookEntryResult(
              hookLabel: hook.label,
              hookEvent: hook.event,
              status: 'timed_out',
              elapsedMs: stopwatch.elapsedMilliseconds,
              stdout: result.stdout,
              stderr: result.stderr,
              stdoutFile: result.stdoutFile,
              stderrFile: result.stderrFile,
              scriptPath: hook.scriptPath,
              scriptContent: hook.scriptContent,
            ),
          );
          continue;
        }
        if (result.exitCode == 2) {
          failedCount++;
          blockReason = result.stdout.isNotEmpty
              ? result.stdout
              : 'Blocked by hook "${hook.label}".';
          hookResults.add(
            HookEntryResult(
              hookLabel: hook.label,
              hookEvent: hook.event,
              status: 'blocked',
              elapsedMs: stopwatch.elapsedMilliseconds,
              stdout: result.stdout,
              stderr: result.stderr,
              stdoutFile: result.stdoutFile,
              stderrFile: result.stderrFile,
              scriptPath: hook.scriptPath,
              scriptContent: hook.scriptContent,
            ),
          );
          break;
        }
        if (result.exitCode != null && result.exitCode != 0) {
          failedCount++;
          errors.add(
            'Hook "${hook.label}" exited with code ${result.exitCode}.'
            '${result.stderr.isNotEmpty ? ' stderr: ${result.stderr}' : ''}',
          );
          hookResults.add(
            HookEntryResult(
              hookLabel: hook.label,
              hookEvent: hook.event,
              status: 'failed',
              elapsedMs: stopwatch.elapsedMilliseconds,
              stdout: result.stdout,
              stderr: result.stderr,
              stdoutFile: result.stdoutFile,
              stderrFile: result.stderrFile,
              scriptPath: hook.scriptPath,
              scriptContent: hook.scriptContent,
            ),
          );
          continue;
        }
        successCount++;
        hookResults.add(
          HookEntryResult(
            hookLabel: hook.label,
            hookEvent: hook.event,
            status: 'success',
            elapsedMs: stopwatch.elapsedMilliseconds,
            stdout: result.stdout,
            stderr: result.stderr,
            stdoutFile: result.stdoutFile,
            stderrFile: result.stderrFile,
            scriptPath: hook.scriptPath,
            scriptContent: hook.scriptContent,
          ),
        );
      } catch (error) {
        stopwatch.stop();
        failedCount++;
        errors.add('Hook "${hook.label}" failed to start: $error');
        hookResults.add(
          HookEntryResult(
            hookLabel: hook.label,
            hookEvent: hook.event,
            status: 'failed',
            elapsedMs: stopwatch.elapsedMilliseconds,
            stderr: '$error',
            scriptPath: hook.scriptPath,
            scriptContent: hook.scriptContent,
          ),
        );
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
    required String sessionId,
    required Map<String, Object?> payload,
  }) async {
    final timeout = Duration(
      seconds: hook.timeoutSeconds.clamp(1, _maxHookTimeoutSeconds),
    );
    final shellCommand = _buildCommand(hook);
    final workingDirectory = OpenHandPaths.applicationDirectoryPath();

    // Serialize context JSON — gracefully degrade on failure.
    String contextJson;
    try {
      contextJson = jsonEncode(payload);
    } catch (_) {
      contextJson = '{}';
    }

    // Write context JSON to ~/.openhand/hooks/tmp/{session-id}-{hook-name}-{hook-id}.json
    // so scripts can safely read it via `jq . "$OPENHAND_HOOK_CONTEXT_FILE"`
    // without shell escaping issues.
    File? contextFile;
    try {
      final tmpDir = Directory(
        p.join(OpenHandPaths.homeDirectoryPath(), '.openhand', 'hooks', 'tmp'),
      );
      await tmpDir.create(recursive: true);
      final safeName = hook.label
          .replaceAll(RegExp(r'[^\w\-]'), '_')
          .toLowerCase();
      final truncatedSafeName = safeName.substring(
        0,
        safeName.length.clamp(0, 32),
      );
      final safeSessionId = sessionId.replaceAll(RegExp(r'[^\w\-]'), '-');
      final safeHookId = hook.id.replaceAll(RegExp(r'[^\w\-]'), '-');
      contextFile = File(
        p.join(
          tmpDir.path,
          '$safeSessionId-$truncatedSafeName-$safeHookId.json',
        ),
      );
      if (contextJson.length > _maxContextJsonBytes) {
        contextJson =
            '${contextJson.substring(0, _maxContextJsonBytes)}...[truncated]';
      }
      await contextFile.writeAsString(contextJson, flush: true);
    } catch (_) {
      // If file creation fails, scripts can still read from stdin.
      contextFile = null;
    }

    final environment = <String, String>{
      'OPENHAND_HOOK_CONTEXT': contextJson,
      if (contextFile != null) 'OPENHAND_HOOK_CONTEXT_FILE': contextFile.path,
    };

    try {
      final process = await startTrackedProcess(
        shellCommand.executable,
        shellCommand.arguments,
        workingDirectory: workingDirectory,
        environment: <String, String>{
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
          ...environment,
        },
      );

      final stdoutFuture = _collectOutput(process.stdout);
      final stderrFuture = _collectOutput(process.stderr);

      // Also write to stdin for scripts that prefer reading from pipe.
      try {
        process.stdin.write(contextJson);
        await process.stdin.close();
      } catch (_) {
        try {
          await process.stdin.close();
        } catch (_) {}
      }

      try {
        // Wait for the process exit code first, with a timeout that covers
        // the entire execution window. Output collection completes once the
        // process exits and its stdout/stderr streams close.
        final exitCode = await process.exitCode.timeout(timeout);

        // Process exited within the timeout – collect outputs.
        final stdoutOutput = await stdoutFuture;
        final stderrOutput = await stderrFuture;

        // Save full output to files when truncated.
        String? stdoutFile;
        String? stderrFile;
        if (stdoutOutput.wasTruncated && stdoutOutput.fullText != null) {
          stdoutFile = await _saveFullOutputFile(
            content: stdoutOutput.fullText!,
            sessionId: sessionId,
            hookLabel: hook.label,
            suffix: 'stdout.txt',
          );
        }
        if (stderrOutput.wasTruncated && stderrOutput.fullText != null) {
          stderrFile = await _saveFullOutputFile(
            content: stderrOutput.fullText!,
            sessionId: sessionId,
            hookLabel: hook.label,
            suffix: 'stderr.txt',
          );
        }

        return _HookScriptResult(
          exitCode: exitCode,
          stdout: stdoutOutput.text,
          stderr: stderrOutput.text,
          timedOut: false,
          stdoutFile: stdoutFile,
          stderrFile: stderrFile,
        );
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // Best-effort cleanup; the process may remain orphaned on some OSes.
        }

        // Collect whatever output was produced before the timeout.
        _CollectedOutput stdoutOutput;
        _CollectedOutput stderrOutput;
        try {
          final results = await Future.wait([
            stdoutFuture,
            stderrFuture,
          ]).timeout(const Duration(seconds: 2));
          stdoutOutput = results[0];
          stderrOutput = results[1];
        } on TimeoutException {
          stdoutOutput = const _CollectedOutput(text: '...[timed out]');
          stderrOutput = const _CollectedOutput(text: '');
        }

        return _HookScriptResult(
          exitCode: null,
          stdout: stdoutOutput.text,
          stderr: stderrOutput.text,
          timedOut: true,
        );
      }
    } finally {
      // Best-effort cleanup of the temp context file.
      if (contextFile != null) {
        try {
          if (await contextFile.exists()) {
            await contextFile.delete();
          }
        } catch (_) {}
      }
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

  Future<_CollectedOutput> _collectOutput(Stream<List<int>> stream) async {
    final truncatedBuffer = StringBuffer();
    final fullBuffer = StringBuffer();
    var collected = 0;
    var truncated = false;
    await for (final chunk in stream.transform(utf8.decoder)) {
      fullBuffer.write(chunk);
      if (truncated) continue;
      final remaining = _maxHookOutputCharacters - collected;
      if (remaining <= 0) {
        truncated = true;
        continue;
      }
      if (chunk.length <= remaining) {
        truncatedBuffer.write(chunk);
        collected += chunk.length;
      } else {
        truncatedBuffer.write(chunk.substring(0, remaining));
        collected += remaining;
        truncated = true;
      }
    }
    final fullText = fullBuffer.toString().trim();
    if (!truncated) {
      return _CollectedOutput(text: fullText);
    }
    final truncatedText = truncatedBuffer.toString().trim();
    final displayText = truncatedText.isEmpty
        ? '...[truncated]'
        : '$truncatedText\n...[truncated]';
    return _CollectedOutput(
      text: displayText,
      fullText: fullText,
      wasTruncated: true,
    );
  }

  /// Save [content] to a file in the hooks tmp directory and return the path.
  /// Returns `null` if the write fails.
  Future<String?> _saveFullOutputFile({
    required String content,
    required String sessionId,
    required String hookLabel,
    required String suffix,
  }) async {
    try {
      final tmpDir = Directory(
        p.join(OpenHandPaths.homeDirectoryPath(), '.openhand', 'hooks', 'tmp'),
      );
      await tmpDir.create(recursive: true);
      final safeName = hookLabel
          .replaceAll(RegExp(r'[^\w\-]'), '_')
          .toLowerCase();
      final truncatedSafeName = safeName.substring(
        0,
        safeName.length.clamp(0, 32),
      );
      final safeSessionId = sessionId.replaceAll(RegExp(r'[^\w\-]'), '-');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final file = File(
        p.join(
          tmpDir.path,
          'output-$safeSessionId-$truncatedSafeName-$ts.$suffix',
        ),
      );
      await file.writeAsString(content, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

class _HookScriptResult {
  const _HookScriptResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    this.stdoutFile,
    this.stderrFile,
  });

  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// Path to file containing full stdout when it was truncated.
  final String? stdoutFile;

  /// Path to file containing full stderr when it was truncated.
  final String? stderrFile;
}

class _ShellCommand {
  const _ShellCommand({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}

class _CollectedOutput {
  const _CollectedOutput({
    required this.text,
    this.fullText,
    this.wasTruncated = false,
  });

  /// Display text (truncated if necessary).
  final String text;

  /// Full text when truncation occurred; `null` if not truncated.
  final String? fullText;

  final bool wasTruncated;
}
