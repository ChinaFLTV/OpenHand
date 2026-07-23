import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../app/model/hook_config.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/text_clip.dart';
import '../hooks_controller.dart';

const int _maxHookOutputCharacters = 4000;
const int _maxHookCapturedOutputBytes = 1024 * 1024;

const int _maxContextJsonBytes = 512 * 1024;
const int _maxContextEnvironmentBytes = 32 * 1024;
const int _maxHookTempLabelCharacters = 32;
const int _maxHookTempIdentifierCharacters = 64;
const int _maxHookTempCleanupEntries = 10000;

final RegExp _unsafeHookTempFileSegmentPattern = RegExp(r'[^\w\-]');

String _safeHookTempLabel(String label) {
  final safeName = label
      .replaceAll(_unsafeHookTempFileSegmentPattern, '_')
      .toLowerCase();
  return safeName.substring(
    0,
    safeName.length.clamp(0, _maxHookTempLabelCharacters),
  );
}

String _safeHookTempIdentifier(String value) {
  final safeValue = value.replaceAll(_unsafeHookTempFileSegmentPattern, '-');
  return safeValue.substring(
    0,
    safeValue.length.clamp(0, _maxHookTempIdentifierCharacters),
  );
}

Future<void> _deleteHookTempContextFile(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (error, stack) {
    silentLog('hooks_executor', '删除临时上下文文件', error, stack);
  }
}

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

  /// Path to bounded captured stdout when the preview is truncated.
  final String? stdoutFile;

  /// Path to bounded captured stderr when the preview is truncated.
  final String? stderrFile;
  final String? scriptPath;
  final String? scriptContent;
}

class HookUsageRecord {
  const HookUsageRecord({
    required this.hookId,
    required this.eventName,
    required this.status,
    required this.durationMs,
    required this.resultSummary,
    required this.errorSummary,
  });

  final String hookId;
  final String eventName;
  final String status;
  final int durationMs;
  final String resultSummary;
  final String errorSummary;
}

/// Public executor that runs hooks for a given event. Designed to be called
/// from AI session controllers and other orchestration layers.
///
/// This class is intentionally stateless — it reads the enabled hooks from the
/// [HooksController] each time [executeEvent] is called, ensuring it always
/// reflects the latest user configuration.
class HooksExecutor {
  HooksExecutor({required HooksController controller})
    : _enabledHooksForEvent = controller.enabledHooksForEvent;

  static const Uuid _uuid = Uuid();
  final List<HookEntry> Function(HookEvent event) _enabledHooksForEvent;
  Future<void> Function(String sessionId, Iterable<HookUsageRecord> records)?
  _usageRecorder;

  void configureUsageRecorder(
    Future<void> Function(String sessionId, Iterable<HookUsageRecord> records)?
    recorder,
  ) {
    _usageRecorder = recorder;
  }

  bool hasEnabledHooksForEvent(HookEvent event) {
    return _enabledHooksForEvent(event).isNotEmpty;
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
      final listing = await listDirectoryBounded(
        tmpDir,
        maxEntries: _maxHookTempCleanupEntries,
      );
      for (final entity in listing.entries) {
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
    final hooks = _enabledHooksForEvent(event);
    if (hooks.isEmpty) {
      return const HookExecutionResult();
    }

    final errors = <String>[];
    var successCount = 0;
    var failedCount = 0;
    var timedOutCount = 0;
    String? blockReason;
    final hookResults = <HookEntryResult>[];
    final executedHookIds = <String>[];

    final effectivePayload = <String, Object?>{
      'hook_event_name': event.storageValue,
      'session_id': sessionId,
      ...payload,
    };

    for (final hook in hooks) {
      executedHookIds.add(hook.id);
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

    final recorder = _usageRecorder;
    if (recorder != null && hookResults.isNotEmpty) {
      try {
        await recorder(sessionId, <HookUsageRecord>[
          for (
            var index = 0;
            index < hookResults.length && index < executedHookIds.length;
            index++
          )
            HookUsageRecord(
              hookId: executedHookIds[index],
              eventName: hookResults[index].hookEvent.storageValue,
              status: hookResults[index].status,
              durationMs: hookResults[index].elapsedMs,
              resultSummary: hookResults[index].stdout,
              errorSummary: hookResults[index].stderr,
            ),
        ]);
      } catch (error, stack) {
        silentLog('hooks_executor', '记录 Hook 调用统计', error, stack);
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
      seconds: HookEntry.normalizeTimeoutSeconds(hook.timeoutSeconds),
    );
    final shellCommand = _buildCommand(hook);
    final workingDirectory = OpenHandPaths.applicationDirectoryPath();

    String contextJson;
    var originalContextBytes = 0;
    try {
      contextJson = jsonEncode(payload);
      originalContextBytes = utf8.encode(contextJson).length;
      if (originalContextBytes > _maxContextJsonBytes) {
        contextJson = _contextSummaryJson(
          payload,
          originalBytes: originalContextBytes,
          truncated: true,
        );
      }
    } catch (_) {
      contextJson = '{}';
    }
    final contextBytes = utf8.encode(contextJson);

    // Keep a unique, valid JSON context file for scripts that prefer jq. The
    // UUID prevents concurrent invocations of the same hook from overwriting
    // and then deleting each other's context.
    File? contextFile;
    try {
      final tmpDir = Directory(
        p.join(OpenHandPaths.homeDirectoryPath(), '.openhand', 'hooks', 'tmp'),
      );
      await tmpDir.create(recursive: true);
      final safeName = _safeHookTempLabel(hook.label);
      final safeSessionId = _safeHookTempIdentifier(sessionId);
      final safeHookId = _safeHookTempIdentifier(hook.id);
      contextFile = File(
        p.join(
          tmpDir.path,
          '$safeSessionId-$safeName-$safeHookId-${_uuid.v4()}.json',
        ),
      );
      await contextFile.writeAsString(contextJson, flush: true);
    } catch (_) {
      // If file creation fails, scripts can still read from stdin.
      contextFile = null;
    }

    final environmentContext =
        contextBytes.length <= _maxContextEnvironmentBytes
        ? contextJson
        : _contextSummaryJson(
            payload,
            originalBytes: originalContextBytes,
            externalized: true,
            fileAvailable: contextFile != null,
          );
    final environment = <String, String>{
      'OPENHAND_HOOK_CONTEXT': environmentContext,
      if (contextFile != null) 'OPENHAND_HOOK_CONTEXT_FILE': contextFile.path,
    };

    try {
      var timedOut = false;
      final processResult = await runProcessWithTimeout(
        shellCommand.executable,
        shellCommand.arguments,
        stdinBytes: contextBytes,
        timeout: timeout,
        tag: 'hooks_executor',
        workingDirectory: workingDirectory,
        environment: <String, String>{
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
          ...environment,
        },
        maxStderrBytes: _maxHookCapturedOutputBytes,
        timeoutResultBuilder: (pid, stdout, stderr) {
          timedOut = true;
          return ProcessResult(pid, 0, stdout, stderr);
        },
      );
      if (processResult == null) {
        throw ProcessException(
          shellCommand.executable,
          shellCommand.arguments,
          'Hook process could not be executed safely.',
        );
      }

      final stdoutOutput = _prepareCollectedOutput(
        processResult.stdout as String,
      );
      final stderrOutput = _prepareCollectedOutput(
        processResult.stderr as String,
      );

      String? stdoutFile;
      String? stderrFile;
      if (!timedOut &&
          stdoutOutput.wasTruncated &&
          stdoutOutput.capturedText != null) {
        stdoutFile = await _saveCapturedOutputFile(
          content: stdoutOutput.capturedText!,
          sessionId: sessionId,
          hookLabel: hook.label,
          suffix: 'stdout.txt',
        );
      }
      if (!timedOut &&
          stderrOutput.wasTruncated &&
          stderrOutput.capturedText != null) {
        stderrFile = await _saveCapturedOutputFile(
          content: stderrOutput.capturedText!,
          sessionId: sessionId,
          hookLabel: hook.label,
          suffix: 'stderr.txt',
        );
      }

      return _HookScriptResult(
        exitCode: timedOut ? null : processResult.exitCode,
        stdout: stdoutOutput.text,
        stderr: stderrOutput.text,
        timedOut: timedOut,
        stdoutFile: stdoutFile,
        stderrFile: stderrFile,
      );
    } finally {
      if (contextFile != null) await _deleteHookTempContextFile(contextFile);
    }
  }

  String _contextSummaryJson(
    Map<String, Object?> payload, {
    required int originalBytes,
    bool truncated = false,
    bool externalized = false,
    bool fileAvailable = false,
  }) {
    String? boundedValue(String key) {
      final value = payload[key];
      if (value == null) return null;
      return clipText('$value', 256);
    }

    return jsonEncode(<String, Object?>{
      if (boundedValue('hook_event_name') case final value?)
        'hook_event_name': value,
      if (boundedValue('session_id') case final value?) 'session_id': value,
      if (truncated) '_openhand_context_truncated': true,
      if (externalized) '_openhand_context_externalized': true,
      if (fileAvailable) '_openhand_context_file_available': true,
      '_openhand_original_utf8_bytes': originalBytes,
    });
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
    return _ShellCommand(
      executable: preferredPosixShellExecutable(),
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
    return _ShellCommand(
      executable: preferredPosixShellExecutable(),
      arguments: <String>[scriptPath],
    );
  }

  _CollectedOutput _prepareCollectedOutput(String capturedText) {
    final normalized = capturedText.trim();
    final preview = clipText(
      normalized,
      _maxHookOutputCharacters,
      suffix: '',
    ).trim();
    final captureReachedLimit =
        utf8.encode(capturedText).length >= _maxHookCapturedOutputBytes;
    if (preview == normalized && !captureReachedLimit) {
      return _CollectedOutput(text: normalized);
    }
    final displayText = preview.isEmpty
        ? '...[truncated]'
        : '$preview\n...[truncated]';
    final persistedText = captureReachedLimit
        ? '$normalized\n...[capture capped at $_maxHookCapturedOutputBytes bytes]'
        : normalized;
    return _CollectedOutput(
      text: displayText,
      capturedText: persistedText,
      wasTruncated: true,
    );
  }

  /// Saves bounded captured output and returns its path.
  Future<String?> _saveCapturedOutputFile({
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
      final safeName = _safeHookTempLabel(hookLabel);
      final safeSessionId = _safeHookTempIdentifier(sessionId);
      final file = File(
        p.join(
          tmpDir.path,
          'output-$safeSessionId-$safeName-${_uuid.v4()}.$suffix',
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

  /// Path to bounded captured stdout when the preview was truncated.
  final String? stdoutFile;

  /// Path to bounded captured stderr when the preview was truncated.
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
    this.capturedText,
    this.wasTruncated = false,
  });

  /// Display text (truncated if necessary).
  final String text;

  /// Bounded captured text when the preview is truncated.
  final String? capturedText;

  final bool wasTruncated;
}
