import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';

const String aiHookSystemRemindersMetadataKey = 'hook_system_reminders';
const String aiUserPromptHookFeedbackMetadataKey =
    'user_prompt_submit_hook_feedback';

/// Metadata key used to persist the user's explicit skill selection on a
/// user message, so the transcript bubble can render a skill capsule under
/// the timestamp similar to the creation-mode chip.  Value shape:
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

  bool get hasVisibleEffects {
    return blocked ||
        userFeedback.isNotEmpty ||
        systemReminders.isNotEmpty ||
        executedHookCount > 0;
  }
}

class AiNoopClaudeHookService extends AiClaudeHookService {
  AiNoopClaudeHookService();

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
  }) : _applicationDirectoryPath =
           applicationDirectoryPath ?? OpenHandPaths.applicationDirectoryPath,
       _homeDirectoryPath =
           homeDirectoryPath ?? OpenHandPaths.homeDirectoryPath,
       _commandTimeout = commandTimeout ?? const Duration(seconds: 12);

  static const int _maxHookTextCharacters = 4000;

  final String Function() _applicationDirectoryPath;
  final String Function() _homeDirectoryPath;
  final Duration _commandTimeout;

  Future<AiClaudeHookInvocationResult> runHooks({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    final workingDirectory = _normalizeDirectory(
      cwd ?? _applicationDirectoryPath(),
    );
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
    String? blockReason;
    var executedHookCount = 0;

    for (final entry in configuredHooks.entries) {
      executedHookCount += 1;
      executedCommands.add(entry.command);
      try {
        final commandResult = await _runCommand(
          command: entry.command,
          payload: effectivePayload,
          workingDirectory: workingDirectory,
        );
        final parsed = _parseHookCommandResult(
          commandResult: commandResult,
          eventName: eventName,
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
        systemReminders.add('Hook command failed to start: $error');
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

  Future<_AiHookCommandResult> _runCommand({
    required String command,
    required Map<String, Object?> payload,
    required String workingDirectory,
  }) async {
    final shellCommand = _resolveShellCommand(command);
    final process = await Process.start(
      shellCommand.executable,
      shellCommand.arguments,
      workingDirectory: workingDirectory,
    );
    final stdoutFuture = _collectTruncatedText(process.stdout);
    final stderrFuture = _collectTruncatedText(process.stderr);
    process.stdin.write(jsonEncode(payload));
    await process.stdin.close();
    try {
      final exitCode = await process.exitCode.timeout(_commandTimeout);
      return _AiHookCommandResult(
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
        // Ignore a second timeout while cleaning up a stuck hook process.
      }
      return _AiHookCommandResult(
        exitCode: null,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
        timedOut: true,
      );
    }
  }

  Future<_AiLoadedHooks> _loadHooks({
    required String eventName,
    required String? matcherValue,
    required String cwd,
  }) async {
    final loadedConfigPaths = <String>[];
    final entries = <_AiConfiguredHookEntry>[];
    for (final filePath in _candidateConfigPaths(cwd)) {
      final file = File(filePath);
      if (!await file.exists()) {
        continue;
      }
      try {
        final rawContent = await file.readAsString();
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
        for (final group in eventHooks) {
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
            if (hookItem is! Map) {
              continue;
            }
            final type = '${hookItem['type'] ?? ''}'.trim();
            final command = '${hookItem['command'] ?? ''}'.trim();
            if (type != 'command' || command.isEmpty) {
              continue;
            }
            entries.add(_AiConfiguredHookEntry(command: command));
          }
        }
      } on FileSystemException {
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

    final homeDirectory = _normalizeDirectory(_homeDirectoryPath());
    addPath(p.join(homeDirectory, '.claude', 'settings.json'));
    addPath(p.join(homeDirectory, '.claude', 'settings.local.json'));

    final directories = <String>[];
    var current = cwd;
    while (true) {
      directories.add(current);
      final parent = p.dirname(current);
      if (parent == current) {
        break;
      }
      current = parent;
    }
    for (final directory in directories.reversed) {
      addPath(p.join(directory, '.claude', 'settings.json'));
      addPath(p.join(directory, '.claude', 'settings.local.json'));
    }
    return paths;
  }

  bool _matcherMatches(String pattern, String value) {
    if (pattern.isEmpty) {
      return true;
    }
    try {
      return RegExp(pattern).hasMatch(value);
    } on FormatException {
      return pattern == value;
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
      systemReminders.add('Hook command timed out and was terminated.');
    } else if (commandResult.exitCode != null &&
        commandResult.exitCode != 0 &&
        blockReason == null) {
      if (commandResult.exitCode == 2) {
        blockReason = combinedText.isEmpty
            ? 'Blocked by hook command.'
            : combinedText;
      } else {
        systemReminders.add(
          combinedText.isEmpty
              ? 'Hook command failed with exit code ${commandResult.exitCode}.'
              : 'Hook command failed with exit code ${commandResult.exitCode}: $combinedText',
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
      return reason ?? 'Blocked by hook decision.';
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
          'Blocked by hook permission decision.';
    }

    final hookSpecificOutput = jsonPayload['hookSpecificOutput'];
    if (hookSpecificOutput is! Map) {
      return null;
    }
    final outputMap = Map<String, Object?>.from(hookSpecificOutput);
    final nestedDecision = '${outputMap['decision'] ?? ''}'.trim();
    if (nestedDecision.toLowerCase() == 'block') {
      return _firstNonEmptyString(<Object?>[
            outputMap['reason'],
            outputMap['message'],
          ]) ??
          'Blocked by hook decision.';
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
          'Blocked by hook permission decision.';
    }
    return null;
  }

  String? _extractReminderText(Map<String, Object?> jsonPayload) {
    final reminder = _firstNonEmptyString(<Object?>[
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
    final outputMap = Map<String, Object?>.from(hookSpecificOutput);
    return _firstNonEmptyString(<Object?>[
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
    final zsh = File('/bin/zsh');
    if (zsh.existsSync()) {
      return _AiShellCommand(
        executable: zsh.path,
        arguments: <String>['-lc', command],
      );
    }
    return _AiShellCommand(
      executable: '/bin/sh',
      arguments: <String>['-lc', command],
    );
  }

  String _normalizeDirectory(String rawPath) {
    final normalized = p.normalize(rawPath.trim());
    if (normalized.isEmpty) {
      return OpenHandPaths.applicationDirectoryPath();
    }
    final entityType = FileSystemEntity.typeSync(normalized);
    if (entityType == FileSystemEntityType.file) {
      return p.dirname(normalized);
    }
    return normalized;
  }

  Future<String> _collectTruncatedText(Stream<List<int>> stream) async {
    final buffer = StringBuffer();
    var collectedCharacters = 0;
    var truncated = false;
    await for (final chunk in stream.transform(utf8.decoder)) {
      if (truncated) {
        continue;
      }
      final remainingCharacters = _maxHookTextCharacters - collectedCharacters;
      if (remainingCharacters <= 0) {
        truncated = true;
        continue;
      }
      if (chunk.length <= remainingCharacters) {
        buffer.write(chunk);
        collectedCharacters += chunk.length;
        continue;
      }
      buffer.write(chunk.substring(0, remainingCharacters));
      collectedCharacters += remainingCharacters;
      truncated = true;
    }
    final trimmed = buffer.toString().trim();
    if (!truncated) {
      return trimmed;
    }
    if (trimmed.isEmpty) {
      return '...[truncated]';
    }
    return '$trimmed\n...[truncated]';
  }

  List<String> _deduplicate(List<String> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      result.add(trimmed);
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

class _AiConfiguredHookEntry {
  const _AiConfiguredHookEntry({required this.command});

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
