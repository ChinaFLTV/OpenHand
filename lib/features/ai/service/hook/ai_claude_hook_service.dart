import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/model/hook_config.dart';
import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/platform_shell.dart';
import '../../../../shared/util/text_clip.dart';
import '../../model/ai_tool_execution_limit_policy.dart';

const int _maxAiHookCapturedOutputBytes = 4 * kBytesPerMiB;
const int _minAiHookCapturedOutputBytes = 16 * kBytesPerKiB;
const int _maxAiHookPayloadBytes = 4 * kBytesPerMiB;
const int _maxAiHookConfigBytes = 2 * kBytesPerMiB;
const int _maxAiHookPresenceCacheEntries = 128;
const int _maxAiHookCommandCharacters = 64 * 1024;
const int _maxAiHookResultItems = 64;
const int _maxAiHookResultCharacters = 4 * kBytesPerMiB;
const int _defaultMaxAiHookCommandsPerInvocation = 64;
const Duration _defaultAiHookInvocationTimeout = Duration(minutes: 2);

const String aiHookSystemRemindersMetadataKey = 'hook_system_reminders';
const String aiUserPromptHookFeedbackMetadataKey =
    'user_prompt_submit_hook_feedback';

/// 在用户消息元数据中保存显式技能选择，供会话气泡在时间戳下方渲染技能标签。
/// 数据结构：
///   { 'name': String, 'path': String, 'icon': String? }
const String aiUserSkillSelectionMetadataKey = 'user_skill_selection';

class AiClaudeHookInvocationResult {
  const AiClaudeHookInvocationResult({
    this.blocked = false,
    this.blockReason,
    this.userFeedback = const <String>[],
    this.systemReminders = const <String>[],
    this.executedHookCount = 0,
    this.executedCommands = const <String>[],
    this.loadedConfigPaths = const <String>[],
  });

  final bool blocked;
  final String? blockReason;
  final List<String> userFeedback;
  final List<String> systemReminders;
  final int executedHookCount;
  final List<String> executedCommands;
  final List<String> loadedConfigPaths;
}

class AiNoopClaudeHookService extends AiClaudeHookService {
  @override
  Future<AiClaudeHookInvocationResult> runHooks({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    return const AiClaudeHookInvocationResult();
  }
}

class AiClaudeHookService {
  AiClaudeHookService({
    String Function()? applicationDirectoryPath,
    String Function()? homeDirectoryPath,
    Duration? commandTimeout,
    Duration invocationTimeout = _defaultAiHookInvocationTimeout,
    int maxCommandsPerInvocation = _defaultMaxAiHookCommandsPerInvocation,
    Duration configPresenceCacheTtl = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _applicationDirectoryPath =
           applicationDirectoryPath ?? OpenHandPaths.applicationDirectoryPath,
       _homeDirectoryPath =
           homeDirectoryPath ?? OpenHandPaths.homeDirectoryPath,
       _commandTimeout = commandTimeout ?? const Duration(seconds: 12),
       _invocationTimeout = invocationTimeout,
       _maxCommandsPerInvocation = maxCommandsPerInvocation,
       _configPresenceCacheTtl = configPresenceCacheTtl,
       _clock = clock ?? DateTime.now {
    if (_commandTimeout <= Duration.zero ||
        _invocationTimeout <= Duration.zero ||
        _maxCommandsPerInvocation < 1) {
      throw ArgumentError('Hook 超时和单次命令上限必须大于零。');
    }
  }

  int maxHookTextCharacters = 4000;

  final String Function() _applicationDirectoryPath;
  final String Function() _homeDirectoryPath;
  final Duration _commandTimeout;
  final Duration _invocationTimeout;
  final int _maxCommandsPerInvocation;
  final Duration _configPresenceCacheTtl;
  final DateTime Function() _clock;
  final LifecycleLruCache<_AiCachedHookConfigPresence> _configPresenceCache =
      LifecycleLruCache<_AiCachedHookConfigPresence>(
        maxEntries: _maxAiHookPresenceCacheEntries,
      );
  HookUsageRecorder? _usageRecorder;

  void configureUsageRecorder(HookUsageRecorder? recorder) {
    _usageRecorder = recorder;
  }

  Future<AiClaudeHookInvocationResult> runHooks({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    final workingDirectory = await _normalizeDirectory(
      cwd ?? _applicationDirectoryPath(),
    );
    if (!await _hasAnyHookConfigFile(workingDirectory)) {
      return const AiClaudeHookInvocationResult();
    }
    final configuredHooks = await _loadHooks(
      eventName: eventName,
      matcherValue: matcherValue,
      cwd: workingDirectory,
    );
    if (configuredHooks.entries.isEmpty) {
      return AiClaudeHookInvocationResult(
        loadedConfigPaths: configuredHooks.loadedConfigPaths,
      );
    }

    final effectivePayload = <String, Object?>{
      'hook_event_name': eventName,
      'hookEventName': eventName,
      'session_id': sessionId,
      'sessionId': sessionId,
      'cwd': workingDirectory,
      ...payload,
    };
    final userFeedback = <String>[];
    final systemReminders = <String>[];
    final executedCommands = <String>[];
    final usageRecords = <HookUsageRecord>[];
    String? blockReason;
    var executedHookCount = 0;
    final deadline = MonotonicDeadline(
      _invocationTimeout,
      timeoutMessage: 'Hook 单次调用超过总时限。',
    );

    for (final entry in configuredHooks.entries) {
      final remaining = deadline.remainingOrNull();
      if (remaining == null) {
        systemReminders.add('Hook 执行达到单次总时限，剩余命令已跳过。');
        break;
      }
      executedHookCount += 1;
      executedCommands.add(entry.command);
      final stopwatch = Stopwatch()..start();
      try {
        final commandResult = await _runCommand(
          command: entry.command,
          payload: effectivePayload,
          workingDirectory: workingDirectory,
          timeout: remaining < _commandTimeout ? remaining : _commandTimeout,
        );
        final parsed = _parseHookCommandResult(
          commandResult: commandResult,
          eventName: eventName,
        );
        stopwatch.stop();
        usageRecords.add(
          HookUsageRecord(
            hookId: entry.id,
            eventName: eventName,
            status: commandResult.timedOut
                ? kHookStatusTimedOut
                : commandResult.exitCode != 0
                ? kHookStatusFailed
                : parsed.blockReason?.trim().isNotEmpty == true
                ? kHookStatusBlocked
                : kHookStatusSuccess,
            durationMs: stopwatch.elapsedMilliseconds,
            resultSummary: commandResult.stdout,
            errorSummary: commandResult.stderr,
          ),
        );
        if (parsed.userFeedback.isNotEmpty) {
          userFeedback.addAll(parsed.userFeedback);
        }
        if (parsed.systemReminders.isNotEmpty) {
          systemReminders.addAll(parsed.systemReminders);
        }
        if (parsed.blockReason?.trim().isNotEmpty ?? false) {
          blockReason = parsed.blockReason!.trim();
          break;
        }
      } catch (error) {
        stopwatch.stop();
        usageRecords.add(
          HookUsageRecord(
            hookId: entry.id,
            eventName: eventName,
            status: kHookStatusFailed,
            durationMs: stopwatch.elapsedMilliseconds,
            resultSummary: '',
            errorSummary: '$error',
          ),
        );
        systemReminders.add('Hook 命令启动失败：$error');
      }
    }
    deadline.stop();

    final recorder = _usageRecorder;
    if (recorder != null && usageRecords.isNotEmpty) {
      try {
        await recorder(sessionId, usageRecords);
      } catch (error, stack) {
        silentLog(
          'ai_claude_hook_service',
          '记录 Claude Hook 调用统计',
          error,
          stack,
        );
      }
    }
    return AiClaudeHookInvocationResult(
      blocked: blockReason != null,
      blockReason: blockReason,
      userFeedback: _deduplicate(userFeedback),
      systemReminders: _deduplicate(systemReminders),
      executedHookCount: executedHookCount,
      executedCommands: executedCommands,
      loadedConfigPaths: configuredHooks.loadedConfigPaths,
    );
  }

  Future<bool> _hasAnyHookConfigFile(String cwd) async {
    if (_configPresenceCacheTtl > Duration.zero) {
      final cached = _configPresenceCache.get(cwd);
      if (cached != null &&
          _clock().toUtc().difference(cached.cachedAt) <=
              _configPresenceCacheTtl) {
        return cached.hasConfig;
      }
      _configPresenceCache.remove(cwd);
    }
    var hasConfig = false;
    for (final filePath in _candidateConfigPaths(cwd)) {
      if (await isRegularFilePath(filePath, followLinks: true)) {
        hasConfig = true;
        break;
      }
    }
    if (_configPresenceCacheTtl > Duration.zero) {
      _configPresenceCache.put(
        cwd,
        _AiCachedHookConfigPresence(
          hasConfig: hasConfig,
          cachedAt: _clock().toUtc(),
        ),
      );
    }
    return hasConfig;
  }

  Future<_AiHookCommandResult> _runCommand({
    required String command,
    required Map<String, Object?> payload,
    required String workingDirectory,
    required Duration timeout,
  }) async {
    final shellCommand = _resolveShellCommand(command);
    final payloadBytes = _encodeBoundedHookPayload(payload);
    final previewCharacters =
        AiToolExecutionLimitPolicy.normalizeMaxHookTextCharacters(
          maxHookTextCharacters,
        );
    final captureBytes = (previewCharacters * 4).clamp(
      _minAiHookCapturedOutputBytes,
      _maxAiHookCapturedOutputBytes,
    );
    var timedOut = false;
    final processResult = await runProcessWithTimeout(
      shellCommand.executable,
      shellCommand.arguments,
      stdinBytes: payloadBytes,
      timeout: timeout,
      tag: 'ai_claude_hook_service',
      workingDirectory: workingDirectory,
      maxStdoutBytes: captureBytes,
      maxStderrBytes: captureBytes,
      timeoutResultBuilder: (pid, stdout, stderr) {
        timedOut = true;
        return ProcessResult(pid, 0, stdout, stderr);
      },
    );
    if (processResult == null) {
      throw ProcessException(
        shellCommand.executable,
        shellCommand.arguments,
        '无法安全执行 Hook 进程。',
      );
    }
    return _AiHookCommandResult(
      exitCode: timedOut ? null : processResult.exitCode,
      stdout: _formatCapturedText(
        processResult.stdout as String,
        previewCharacters: previewCharacters,
        captureBytes: captureBytes,
      ),
      stderr: _formatCapturedText(
        processResult.stderr as String,
        previewCharacters: previewCharacters,
        captureBytes: captureBytes,
      ),
      timedOut: timedOut,
    );
  }

  List<int> _encodeBoundedHookPayload(Map<String, Object?> payload) {
    final encoded = utf8.encode(jsonEncode(payload));
    if (encoded.length <= _maxAiHookPayloadBytes) return encoded;

    String? boundedValue(String key) {
      final value = payload[key];
      if (value == null) return null;
      return clipText('$value', 1024);
    }

    return utf8.encode(
      jsonEncode(<String, Object?>{
        for (final key in <String>[
          'hook_event_name',
          'hookEventName',
          'session_id',
          'sessionId',
          'cwd',
        ])
          if (boundedValue(key) case final value?) key: value,
        '_openhand_payload_truncated': true,
        '_openhand_original_utf8_bytes': encoded.length,
      }),
    );
  }

  Future<_AiLoadedHooks> _loadHooks({
    required String eventName,
    required String? matcherValue,
    required String cwd,
  }) async {
    final loadedConfigPaths = <String>[];
    final entries = <_AiConfiguredHookEntry>[];
    for (final filePath in _candidateConfigPaths(cwd)) {
      if (entries.length >= _maxCommandsPerInvocation) break;
      final file = File(filePath);
      if (!await isRegularFilePath(file.path, followLinks: true)) {
        continue;
      }
      try {
        final rawContent = await readBoundedFileString(
          file,
          maxBytes: _maxAiHookConfigBytes,
        );
        final decoded = jsonDecode(rawContent);
        if (decoded is! Map) {
          continue;
        }
        final hooks = decoded['hooks'];
        if (hooks is! Map) {
          continue;
        }
        loadedConfigPaths.add(filePath);
        final eventHooks = hooks[eventName];
        if (eventHooks is! List) {
          continue;
        }
        var entryIndex = 0;
        for (final group in eventHooks) {
          if (entries.length >= _maxCommandsPerInvocation) break;
          if (group is! Map) {
            continue;
          }
          final matcher = '${group['matcher'] ?? ''}'.trim();
          if (!_matcherMatches(matcher, matcherValue ?? '')) {
            continue;
          }
          final hookItems = group['hooks'];
          if (hookItems is! List) {
            continue;
          }
          for (final hookItem in hookItems) {
            if (entries.length >= _maxCommandsPerInvocation) break;
            if (hookItem is! Map) {
              continue;
            }
            final type = '${hookItem['type'] ?? ''}'.trim();
            final command = '${hookItem['command'] ?? ''}'.trim();
            if (type != 'command' ||
                command.isEmpty ||
                command.length > _maxAiHookCommandCharacters) {
              continue;
            }
            entries.add(
              _AiConfiguredHookEntry(
                id: '$filePath::$eventName::${entryIndex++}',
                command: command,
              ),
            );
          }
        }
      } on IOException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return _AiLoadedHooks(
      entries: entries,
      loadedConfigPaths: loadedConfigPaths,
    );
  }

  List<String> _candidateConfigPaths(String cwd) {
    final paths = <String>[];
    final seen = <String>{};

    void addPath(String filePath) {
      final normalized = p.normalize(filePath);
      if (seen.add(normalized)) {
        paths.add(normalized);
      }
    }

    final rawHomeDirectory = _homeDirectoryPath().trim();
    final homeDirectory = p.normalize(
      rawHomeDirectory.isEmpty ? _applicationDirectoryPath() : rawHomeDirectory,
    );
    addPath(p.join(homeDirectory, '.claude', 'settings.json'));
    addPath(p.join(homeDirectory, '.claude', 'settings.local.json'));

    for (final directory in ancestorDirectoriesFrom(cwd, rootFirst: true)) {
      addPath(p.join(directory, '.claude', 'settings.json'));
      addPath(p.join(directory, '.claude', 'settings.local.json'));
    }
    return paths;
  }

  bool _matcherMatches(String pattern, String value) {
    if (pattern.isEmpty) {
      return true;
    }
    final values = splitTrimmedNonEmpty(value, separator: '\n').toList();
    if (values.isEmpty) {
      values.add('');
    }
    try {
      final regex = RegExp(pattern);
      return values.any(regex.hasMatch);
    } on FormatException {
      return values.any((item) => pattern == item);
    }
  }

  _AiParsedHookCommandResult _parseHookCommandResult({
    required _AiHookCommandResult commandResult,
    required String eventName,
  }) {
    final stdout = commandResult.stdout.trim();
    final stderr = commandResult.stderr.trim();
    final combinedText = <String>[
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) stderr,
    ].join('\n');
    final jsonPayload = _tryParseJson(stdout) ?? _tryParseJson(combinedText);
    String? blockReason;
    final userFeedback = <String>[];
    final systemReminders = <String>[];

    if (jsonPayload is Map<String, Object?>) {
      final parsedBlockReason = _extractBlockReason(jsonPayload);
      if (parsedBlockReason != null) {
        blockReason = parsedBlockReason;
      }
      final reminderText = _extractReminderText(jsonPayload);
      if (reminderText != null) {
        if (eventName == 'UserPromptSubmit') {
          userFeedback.add(reminderText);
        } else {
          systemReminders.add(reminderText);
        }
      }
    } else if (combinedText.isNotEmpty) {
      if (eventName == 'UserPromptSubmit') {
        userFeedback.add(combinedText);
      } else {
        systemReminders.add(combinedText);
      }
    }

    if (commandResult.timedOut) {
      systemReminders.add('Hook 命令执行超时，已终止。');
    } else if (commandResult.exitCode != null &&
        commandResult.exitCode != 0 &&
        blockReason == null) {
      if (commandResult.exitCode == 2) {
        blockReason = combinedText.isEmpty ? 'Hook 命令已阻止本次操作。' : combinedText;
      } else {
        systemReminders.add(
          combinedText.isEmpty
              ? 'Hook 命令执行失败，退出码：${commandResult.exitCode}。'
              : 'Hook 命令执行失败，退出码：${commandResult.exitCode}：$combinedText',
        );
      }
    }

    return _AiParsedHookCommandResult(
      blockReason: blockReason,
      userFeedback: _deduplicate(userFeedback),
      systemReminders: _deduplicate(systemReminders),
    );
  }

  String? _extractBlockReason(Map<String, Object?> jsonPayload) {
    final topLevelDecision = '${jsonPayload['decision'] ?? ''}'.trim();
    if (topLevelDecision.toLowerCase() == 'block') {
      final reason = _firstNonEmptyString(<Object?>[
        jsonPayload['reason'],
        jsonPayload['message'],
      ]);
      return reason ?? 'Hook 决策已阻止本次操作。';
    }

    final permissionDecision = '${jsonPayload['permissionDecision'] ?? ''}'
        .trim()
        .toLowerCase();
    if (permissionDecision == 'deny' || permissionDecision == 'block') {
      return _firstNonEmptyString(<Object?>[
            jsonPayload['permissionDecisionReason'],
            jsonPayload['reason'],
            jsonPayload['message'],
          ]) ??
          'Hook 权限决策已阻止本次操作。';
    }

    final hookSpecificOutput = jsonPayload['hookSpecificOutput'];
    if (hookSpecificOutput is! Map) {
      return null;
    }
    final outputMap = stringKeyedMapFromValue(hookSpecificOutput);
    final nestedDecision = '${outputMap['decision'] ?? ''}'.trim();
    if (nestedDecision.toLowerCase() == 'block') {
      return _firstNonEmptyString(<Object?>[
            outputMap['reason'],
            outputMap['message'],
          ]) ??
          'Hook 决策已阻止本次操作。';
    }
    final nestedPermissionDecision = '${outputMap['permissionDecision'] ?? ''}'
        .trim()
        .toLowerCase();
    if (nestedPermissionDecision == 'deny' ||
        nestedPermissionDecision == 'block') {
      return _firstNonEmptyString(<Object?>[
            outputMap['permissionDecisionReason'],
            outputMap['reason'],
            outputMap['message'],
          ]) ??
          'Hook 权限决策已阻止本次操作。';
    }
    return null;
  }

  String? _extractReminderText(Map<String, Object?> jsonPayload) {
    final reminder = _firstNonEmptyString(<Object?>[
      jsonPayload['additionalContext'],
      jsonPayload['message'],
      jsonPayload['reason'],
    ]);
    if (reminder != null) {
      return reminder;
    }
    final hookSpecificOutput = jsonPayload['hookSpecificOutput'];
    if (hookSpecificOutput is! Map) {
      return null;
    }
    final outputMap = stringKeyedMapFromValue(hookSpecificOutput);
    return _firstNonEmptyString(<Object?>[
      outputMap['additionalContext'],
      outputMap['message'],
      outputMap['reason'],
      outputMap['permissionDecisionReason'],
    ]);
  }

  Object? _tryParseJson(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
  }

  _AiShellCommand _resolveShellCommand(String command) {
    if (Platform.isWindows) {
      return _AiShellCommand(
        executable: 'cmd.exe',
        arguments: <String>['/C', command],
      );
    }
    return _AiShellCommand(
      executable: preferredPosixShellExecutable(),
      arguments: <String>['-lc', command],
    );
  }

  Future<String> _normalizeDirectory(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return OpenHandPaths.applicationDirectoryPath();
    }
    final normalized = p.normalize(trimmed);
    final entityType = await probeFileSystemEntityType(
      normalized,
      followLinks: true,
    );
    if (entityType == FileSystemEntityType.file) {
      return p.dirname(normalized);
    }
    return normalized;
  }

  String _formatCapturedText(
    String capturedText, {
    required int previewCharacters,
    required int captureBytes,
  }) {
    final normalized = capturedText.trim();
    final preview = clipText(normalized, previewCharacters, suffix: '').trim();
    final captureReachedLimit =
        utf8.encode(capturedText).length >= captureBytes;
    if (preview == normalized && !captureReachedLimit) return normalized;
    return preview.isEmpty ? '...[已截断]' : '$preview\n...[已截断]';
  }

  List<String> _deduplicate(List<String> items) {
    final seen = <String>{};
    final result = <String>[];
    final perItemLimit =
        AiToolExecutionLimitPolicy.normalizeMaxHookTextCharacters(
          maxHookTextCharacters,
        );
    final totalLimit = (perItemLimit * 4)
        .clamp(perItemLimit, _maxAiHookResultCharacters)
        .toInt();
    var retainedCharacters = 0;
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      if (result.length >= _maxAiHookResultItems ||
          retainedCharacters >= totalLimit) {
        break;
      }
      final remaining = totalLimit - retainedCharacters;
      final retained = clipText(
        trimmed,
        remaining < perItemLimit ? remaining : perItemLimit,
        suffix: '',
      );
      if (retained.isEmpty) break;
      result.add(retained);
      retainedCharacters += retained.length;
    }
    return result;
  }

  String? _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final text = '$value'.trim();
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return null;
  }
}

class _AiLoadedHooks {
  const _AiLoadedHooks({
    required this.entries,
    required this.loadedConfigPaths,
  });

  final List<_AiConfiguredHookEntry> entries;
  final List<String> loadedConfigPaths;
}

class _AiCachedHookConfigPresence {
  const _AiCachedHookConfigPresence({
    required this.hasConfig,
    required this.cachedAt,
  });

  final bool hasConfig;
  final DateTime cachedAt;
}

class _AiConfiguredHookEntry {
  const _AiConfiguredHookEntry({required this.id, required this.command});

  final String id;
  final String command;
}

class _AiHookCommandResult {
  const _AiHookCommandResult({
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

class _AiParsedHookCommandResult {
  const _AiParsedHookCommandResult({
    this.blockReason,
    required this.userFeedback,
    required this.systemReminders,
  });

  final String? blockReason;
  final List<String> userFeedback;
  final List<String> systemReminders;
}

class _AiShellCommand {
  const _AiShellCommand({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}
