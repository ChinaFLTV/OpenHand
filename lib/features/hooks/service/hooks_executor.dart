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
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/user_failure_message.dart';
import '../hooks_controller.dart';

/// 钩子脚本以该退出码表示“拦截本次操作”，沿用 Claude Code 钩子约定。
const int kHookBlockExitCode = 2;

const int _maxHookOutputCharacters = 4000;
const int _maxHookCapturedOutputBytes = kBytesPerMiB;

const int _maxContextJsonBytes = 512 * 1024;
const int _maxContextEnvironmentBytes = 32 * 1024;
const int _maxHookTempLabelCharacters = 32;
const int _maxHookTempIdentifierCharacters = 64;
const int _maxHookTempCleanupEntries = 10000;
const Duration _hookTempFileOperationTimeout = Duration(seconds: 5);

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
    if (await file.exists().timeout(_hookTempFileOperationTimeout)) {
      await file.delete().timeout(_hookTempFileOperationTimeout);
    }
  } catch (error, stack) {
    silentLog('hooks_executor', '删除临时上下文文件', error, stack);
  }
}

/// 单个事件的全部 Hook 执行结果。
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

/// 单个 Hook 的详细执行结果。
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

  /// [kHookStatusSuccess] / [kHookStatusFailed] / [kHookStatusTimedOut] /
  /// [kHookStatusBlocked] 之一。
  final String status;
  final int elapsedMs;
  final String stdout;
  final String stderr;

  /// 预览被截断时，有界捕获的标准输出文件路径。
  final String? stdoutFile;

  /// 预览被截断时，有界捕获的标准错误文件路径。
  final String? stderrFile;
  final String? scriptPath;
  final String? scriptContent;
}

/// 执行指定事件 Hook 的无状态执行器；每次运行均读取最新启用配置。
class HooksExecutor {
  HooksExecutor({required HooksController controller})
    : _enabledHooksForEvent = controller.enabledHooksForEvent;

  static const Uuid _uuid = Uuid();
  final List<HookEntry> Function(HookEvent event) _enabledHooksForEvent;
  HookUsageRecorder? _usageRecorder;

  void configureUsageRecorder(HookUsageRecorder? recorder) {
    _usageRecorder = recorder;
  }

  bool hasEnabledHooksForEvent(HookEvent event) {
    return _enabledHooksForEvent(event).isNotEmpty;
  }

  /// Hook 临时目录中文件的最长保留时间。
  static const Duration _tmpFileMaxAge = Duration(days: 7);

  /// 启动时尽力清理 `~/.openhand/hooks/tmp/` 下的过期文件，不向外抛出异常。
  static Future<void> pruneStaleTempFiles() async {
    try {
      final tmpDir = Directory(
        OpenHandPaths.defaultHooksTemporaryDirectoryPath(),
      );
      if (!await tmpDir.exists().timeout(_hookTempFileOperationTimeout)) return;
      final cutoff = DateTime.now().subtract(_tmpFileMaxAge);
      final listing = await listDirectoryBounded(
        tmpDir,
        maxEntries: _maxHookTempCleanupEntries,
      );
      for (final entity in listing.entries) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat().timeout(
            _hookTempFileOperationTimeout,
          );
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete().timeout(_hookTempFileOperationTimeout);
          }
        } on FileSystemException {
          // 无法读取或删除的文件直接跳过。
        }
      }
    } on FileSystemException {
      // 清理失败不能影响应用启动。
    }
  }

  /// 执行 [event] 下全部已启用的 Hook。
  ///
  /// [sessionId] 与 [payload] 会作为 JSON 经标准输入传给每个 Hook 脚本。
  ///
  /// Hook 串行执行；任一 Hook 以退出码 2 结束时跳过剩余项并标记为已拦截。
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
      void record(String status, {_HookScriptResult? result, String? error}) {
        hookResults.add(
          HookEntryResult(
            hookLabel: hook.label,
            hookEvent: hook.event,
            status: status,
            elapsedMs: stopwatch.elapsedMilliseconds,
            stdout: result?.stdout ?? '',
            stderr: error ?? result?.stderr ?? '',
            stdoutFile: result?.stdoutFile,
            stderrFile: result?.stderrFile,
            scriptPath: hook.scriptPath,
            scriptContent: hook.scriptContent,
          ),
        );
      }

      try {
        final result = await _runHookScript(
          hook: hook,
          sessionId: sessionId,
          payload: effectivePayload,
        );
        stopwatch.stop();
        if (result.timedOut) {
          timedOutCount++;
          errors.add('Hook“${hook.label}”在 ${hook.timeoutSeconds} 秒后超时。');
          record(kHookStatusTimedOut, result: result);
          continue;
        }
        if (result.exitCode == kHookBlockExitCode) {
          failedCount++;
          blockReason = result.stdout.isNotEmpty
              ? result.stdout
              : '已被 Hook“${hook.label}”拦截。';
          record(kHookStatusBlocked, result: result);
          break;
        }
        if (result.exitCode != null && result.exitCode != 0) {
          failedCount++;
          errors.add(
            'Hook“${hook.label}”退出码为 ${result.exitCode}。'
            '${result.stderr.isNotEmpty ? ' 标准错误：${result.stderr}' : ''}',
          );
          record(kHookStatusFailed, result: result);
          continue;
        }
        successCount++;
        record(kHookStatusSuccess, result: result);
      } catch (error, stack) {
        stopwatch.stop();
        failedCount++;
        silentLog('hooks_executor', '启动 Hook', error, stack);
        final message = userFailureMessage(
          error,
          fallback: 'Hook 启动失败，请检查脚本与运行环境。',
        );
        errors.add('Hook“${hook.label}”启动失败：$message');
        record(kHookStatusFailed, error: message);
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
    } catch (error, stack) {
      silentLog('hooks_executor', '序列化 Hook 上下文', error, stack);
      contextJson = '{}';
    }
    final contextBytes = utf8.encode(contextJson);

    // 为偏好 jq 的脚本保留独立 JSON 上下文；UUID 防止并发 Hook 互相覆盖或删除文件。
    File? contextFile;
    try {
      final tmpDir = Directory(
        OpenHandPaths.defaultHooksTemporaryDirectoryPath(),
      );
      await tmpDir
          .create(recursive: true)
          .timeout(_hookTempFileOperationTimeout);
      final safeName = _safeHookTempLabel(hook.label);
      final safeSessionId = _safeHookTempIdentifier(sessionId);
      final safeHookId = _safeHookTempIdentifier(hook.id);
      contextFile = File(
        p.join(
          tmpDir.path,
          '$safeSessionId-$safeName-$safeHookId-${_uuid.v4()}.json',
        ),
      );
      await writeTemporaryFileTextBounded(
        contextFile,
        contextJson,
        timeout: _hookTempFileOperationTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('hooks_executor', '清理临时上下文文件', error, stack),
      );
    } catch (error, stack) {
      silentLog('hooks_executor', '创建 Hook 临时上下文文件', error, stack);
      // 文件创建失败时，脚本仍可从标准输入读取上下文。
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
    // 已配置脚本路径时直接执行该文件。
    if (hook.scriptPath != null && hook.scriptPath!.isNotEmpty) {
      return _buildFileCommand(hook.scriptPath!);
    }
    // 否则通过平台 Shell 执行内联脚本。
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
    // macOS / Linux 作为 Shell 脚本执行。
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
    final displayText = preview.isEmpty ? '…[已截断]' : '$preview\n…[已截断]';
    final persistedText = captureReachedLimit
        ? '$normalized\n…[捕获内容已限制为 $_maxHookCapturedOutputBytes 字节]'
        : normalized;
    return _CollectedOutput(
      text: displayText,
      capturedText: persistedText,
      wasTruncated: true,
    );
  }

  /// 保存有界捕获的输出并返回文件路径。
  Future<String?> _saveCapturedOutputFile({
    required String content,
    required String sessionId,
    required String hookLabel,
    required String suffix,
  }) async {
    try {
      final tmpDir = Directory(
        OpenHandPaths.defaultHooksTemporaryDirectoryPath(),
      );
      await tmpDir
          .create(recursive: true)
          .timeout(_hookTempFileOperationTimeout);
      final safeName = _safeHookTempLabel(hookLabel);
      final safeSessionId = _safeHookTempIdentifier(sessionId);
      final file = File(
        p.join(
          tmpDir.path,
          'output-$safeSessionId-$safeName-${_uuid.v4()}.$suffix',
        ),
      );
      await writeTemporaryFileTextBounded(
        file,
        content,
        timeout: _hookTempFileOperationTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('hooks_executor', '清理 Hook 输出文件', error, stack),
      );
      return file.path;
    } catch (error, stack) {
      silentLog('hooks_executor', '保存 Hook 捕获输出', error, stack);
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

  /// 预览被截断时，有界捕获的标准输出文件路径。
  final String? stdoutFile;

  /// 预览被截断时，有界捕获的标准错误文件路径。
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

  /// 用于展示的文本，必要时已截断。
  final String text;

  /// 预览被截断时有界捕获的完整文本。
  final String? capturedText;

  final bool wasTruncated;
}
