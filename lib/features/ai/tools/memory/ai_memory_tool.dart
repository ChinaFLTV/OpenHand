library;

import 'dart:convert';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../memory/index.dart';

/// Hermes Talker 专用 Memory 工具。
///
/// 提供给自我学习子 Agent 使用，将对话中的关键结论沉淀到 [MemoryController]
/// 管理的用户记忆存储。为了和 `SkillManager` 对齐，本工具名为 `Memory`，
/// 注册在 [AiBuiltinToolKind.memory] 下。
///
/// 支持的 action:
/// * `list`        — 列出最近的记忆（可按 tag 过滤）。
/// * `append`      — 追加一条普通记忆条目。
/// * `upsert_profile` — 更新/创建唯一的 user_profile 条目。
/// * `update`      — 修改指定 id 的条目。
/// * `delete`      — 删除指定 id 的条目。
///
/// 本工具仅在 Hermes Talker 自我学习场景注册；delete 仍受自我学习策略约束。

import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

typedef MemoryControllerProvider = MemoryController? Function();

class AiMemoryTool extends AiTool {
  AiMemoryTool({required this.memoryControllerProvider});

  /// 运行时查询 [MemoryController] 的回调。
  /// 通过函数间接注入以避免构造阶段的循环依赖。
  final MemoryControllerProvider memoryControllerProvider;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.memory;

  @override
  List<String> get aliases => const <String>['memory'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    return run(context.decodedArguments);
  }

  /// Package-private entry point used by tests to exercise the core logic
  /// without constructing a full [AiToolExecutionContext].
  Future<AiToolExecutionResult> run(
    Map<String, Object?> args, {
    bool requireUnchangedProfile = false,
    UserMemoryEntry? expectedUserProfile,
  }) async {
    final stopwatch = Stopwatch()..start();
    var action = 'unknown';

    try {
      final request = _parseRequest(args);
      action = request.action;
      final controller = memoryControllerProvider();
      if (controller == null) {
        return _failedResult(
          stopwatch,
          'Memory storage is unavailable.',
          action: action,
        );
      }
      if (!await controller.ensureLoaded()) {
        return _failedResult(
          stopwatch,
          'Memory storage could not be loaded.',
          action: action,
        );
      }
      return switch (action) {
        'list' => _list(controller, request, stopwatch),
        'append' => await _append(controller, request, stopwatch),
        'upsert_profile' => await _upsertProfile(
          controller,
          request,
          stopwatch,
          requireUnchangedProfile: requireUnchangedProfile,
          expectedUserProfile: expectedUserProfile,
        ),
        'update' => await _update(controller, request, stopwatch),
        'delete' => await _delete(controller, request, stopwatch),
        _ => throw StateError('Unreachable memory action: $action'),
      };
    } on _MemoryToolArgumentException catch (error) {
      return AiToolUtils.invalidResult(_toolName, error.message);
    } catch (error, stackTrace) {
      silentLog('ai_memory_tool', 'run/$action', error, stackTrace);
      return _failedResult(
        stopwatch,
        'Memory operation failed.',
        action: action,
      );
    }
  }

  // Actions
  AiToolExecutionResult _list(
    MemoryController controller,
    _MemoryToolRequest request,
    Stopwatch sw,
  ) {
    final tag = request.tag.trim();
    final entries = tag.isEmpty
        ? controller.entries
        : controller.memoriesWithTag(tag);
    final visibleEntries = entries
        .take(_maxListEntries)
        .toList(growable: false);
    final omitted = entries.length - visibleEntries.length;
    final buffer = StringBuffer();
    for (final entry in visibleEntries) {
      final tags = clipTextWithEllipsis(
        collapseInlineWhitespace(entry.tags.join(',')),
        _tagPreviewCharacters,
      );
      buffer.writeln(
        '- [${entry.type}] id=${entry.id} tags=$tags '
        'content="${_preview(entry.content)}"',
      );
    }
    if (omitted > 0) {
      buffer.writeln('[memory_entries_omitted: $omitted entries]');
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: buffer.isEmpty ? 'No memory entries.' : buffer.toString(),
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{
        'action': 'list',
        'count': entries.length,
        'returned_count': visibleEntries.length,
        'omitted_count': omitted,
        'limit': _maxListEntries,
        'quota_recovery_mode': controller.isQuotaRecoveryMode,
        'tag': tag,
        'memory_ids': visibleEntries.map((entry) => entry.id).toList(),
      },
    );
  }

  Future<AiToolExecutionResult> _append(
    MemoryController controller,
    _MemoryToolRequest request,
    Stopwatch sw,
  ) async {
    final entry = await controller.createMemoryEntry(
      content: request.content!,
      tags: request.tags ?? const <String>[],
      title: request.title ?? '',
    );
    if (entry == null) {
      return _failedResult(
        sw,
        'Memory could not be appended.',
        action: 'append',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'Memory appended.',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: 'memory store mutation',
      metadata: <String, Object?>{'action': 'append', 'id': entry.id},
    );
  }

  Future<AiToolExecutionResult> _upsertProfile(
    MemoryController controller,
    _MemoryToolRequest request,
    Stopwatch sw, {
    required bool requireUnchangedProfile,
    required UserMemoryEntry? expectedUserProfile,
  }) async {
    final entry = requireUnchangedProfile
        ? await controller.upsertUserProfileIfUnchanged(
            content: request.content!,
            tags: request.tags,
            expectedProfile: expectedUserProfile,
          )
        : await controller.upsertUserProfile(
            content: request.content!,
            tags: request.tags,
          );
    if (entry == null) {
      return _failedResult(
        sw,
        'User profile changed during this run; skip this update.',
        action: 'upsert_profile',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'user_profile upserted (id=${entry.id}).',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: 'memory store mutation',
      metadata: <String, Object?>{'action': 'upsert_profile', 'id': entry.id},
    );
  }

  Future<AiToolExecutionResult> _update(
    MemoryController controller,
    _MemoryToolRequest request,
    Stopwatch sw,
  ) async {
    final id = request.id!;
    final target = _entryById(controller, id);
    if (target == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'No memory entry with id="$id".',
      );
    }
    if (target.isUserProfile) {
      return AiToolUtils.invalidResult(
        _toolName,
        'user_profile can only be changed with upsert_profile.',
      );
    }
    final ok = await controller.updateMemory(
      target,
      content: request.content!,
      tags: request.tags,
      title: request.title,
    );
    if (!ok) {
      return _failedResult(
        sw,
        'Memory could not be updated.',
        action: 'update',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'Memory updated (id=$id).',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: 'memory store mutation',
      metadata: <String, Object?>{'action': 'update', 'id': id},
    );
  }

  Future<AiToolExecutionResult> _delete(
    MemoryController controller,
    _MemoryToolRequest request,
    Stopwatch sw,
  ) async {
    final id = request.id!;
    final target = _entryById(controller, id);
    if (target == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'No memory entry with id="$id".',
      );
    }
    if (target.isUserProfile) {
      return AiToolUtils.invalidResult(
        _toolName,
        'user_profile cannot be deleted by this tool.',
      );
    }
    final ok = await controller.deleteMemory(target);
    if (!ok) {
      return _failedResult(
        sw,
        'Memory could not be deleted.',
        action: 'delete',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'Memory deleted (id=$id).',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: 'memory store mutation',
      metadata: <String, Object?>{'action': 'delete', 'id': id},
    );
  }

  // Helpers
  static const String _toolName = 'Memory';
  static const Set<String> _actions = <String>{
    'list',
    'append',
    'upsert_profile',
    'update',
    'delete',
  };
  static const Map<String, Set<String>> _argumentNamesByAction =
      <String, Set<String>>{
        'list': <String>{'action', 'tag', 'purpose'},
        'append': <String>{'action', 'content', 'title', 'tags', 'purpose'},
        'upsert_profile': <String>{'action', 'content', 'tags', 'purpose'},
        'update': <String>{
          'action',
          'id',
          'content',
          'title',
          'tags',
          'purpose',
        },
        'delete': <String>{'action', 'id', 'purpose'},
      };
  static const int _maxListEntries = 100;
  static const int _previewChars = 200;
  static const int _tagPreviewCharacters = 320;
  static const int _maxTagsTextCharacters =
      UserMemoryEntry.maxTags * (UserMemoryEntry.maxTagCharacters + 1);

  _MemoryToolRequest _parseRequest(Map<String, Object?> args) {
    final action = _requiredString(
      args,
      'action',
      maxCharacters: 32,
    ).toLowerCase();
    if (!_actions.contains(action)) {
      throw _MemoryToolArgumentException(
        'Unknown action "$action". Valid: ${_actions.join(' | ')}.',
      );
    }
    final allowedArguments = _argumentNamesByAction[action]!;
    final irrelevant = args.keys
        .where((key) => !allowedArguments.contains(key))
        .toList(growable: false);
    if (irrelevant.isNotEmpty) {
      throw _MemoryToolArgumentException(
        '${irrelevant.first} is not valid for $action.',
      );
    }

    final id = _optionalString(
      args,
      'id',
      maxCharacters: UserMemoryEntry.maxIdCharacters,
    )?.trim();
    final content = _optionalString(
      args,
      'content',
      maxCharacters: UserMemoryEntry.maxContentCharacters,
    );
    final title = _optionalString(
      args,
      'title',
      maxCharacters: UserMemoryEntry.maxTitleLength,
    );
    final tag =
        _optionalString(
          args,
          'tag',
          maxCharacters: UserMemoryEntry.maxTagCharacters,
        ) ??
        '';
    final tags = _optionalTags(args);
    if (args.containsKey('purpose') && args['purpose'] is! String) {
      throw const _MemoryToolArgumentException('purpose must be a string.');
    }

    if ((action == 'update' || action == 'delete') &&
        (id == null || id.isEmpty)) {
      throw _MemoryToolArgumentException('$action requires a non-empty id.');
    }
    if ((action == 'append' ||
            action == 'upsert_profile' ||
            action == 'update') &&
        (content == null || content.trim().isEmpty)) {
      throw _MemoryToolArgumentException('$action requires non-empty content.');
    }

    return _MemoryToolRequest(
      action: action,
      id: id,
      content: content,
      title: title,
      tags: tags,
      tag: tag,
    );
  }

  String _requiredString(
    Map<String, Object?> args,
    String key, {
    required int maxCharacters,
  }) {
    final value = _optionalString(args, key, maxCharacters: maxCharacters);
    if (value == null || value.trim().isEmpty) {
      throw _MemoryToolArgumentException('$key must be a non-empty string.');
    }
    return value;
  }

  String? _optionalString(
    Map<String, Object?> args,
    String key, {
    required int maxCharacters,
  }) {
    if (!args.containsKey(key)) return null;
    final value = args[key];
    if (value is! String) {
      throw _MemoryToolArgumentException('$key must be a string.');
    }
    if (value.length > maxCharacters) {
      throw _MemoryToolArgumentException(
        '$key exceeds the $maxCharacters character limit.',
      );
    }
    return value;
  }

  List<String>? _optionalTags(Map<String, Object?> args) {
    if (!args.containsKey('tags')) return null;
    final raw = args['tags'];
    final List<String> values;
    if (raw is List) {
      if (raw.length > UserMemoryEntry.maxTags) {
        throw const _MemoryToolArgumentException(
          'tags exceed the ${UserMemoryEntry.maxTags} item limit.',
        );
      }
      if (raw.any((value) => value is! String)) {
        throw const _MemoryToolArgumentException(
          'tags must contain only strings.',
        );
      }
      values = raw.cast<String>();
    } else if (raw is String) {
      if (raw.length > _maxTagsTextCharacters) {
        throw const _MemoryToolArgumentException(
          'tags text exceeds the memory limit.',
        );
      }
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const <String>[];
      if (trimmed.startsWith('[')) {
        final Object? decoded;
        try {
          decoded = jsonDecode(trimmed);
        } on FormatException {
          throw const _MemoryToolArgumentException(
            'tags JSON must be a string array.',
          );
        }
        if (decoded is! List || decoded.any((value) => value is! String)) {
          throw const _MemoryToolArgumentException(
            'tags JSON must be a string array.',
          );
        }
        values = decoded.cast<String>();
      } else {
        if (trimmed.startsWith('{')) {
          throw const _MemoryToolArgumentException(
            'tags must be a string array or comma-separated text.',
          );
        }
        values = splitTrimmedNonEmpty(trimmed);
      }
    } else {
      throw const _MemoryToolArgumentException(
        'tags must be a string array or comma-separated text.',
      );
    }
    if (values.length > UserMemoryEntry.maxTags) {
      throw const _MemoryToolArgumentException(
        'tags exceed the ${UserMemoryEntry.maxTags} item limit.',
      );
    }
    if (values.any((tag) => tag.length > UserMemoryEntry.maxTagCharacters)) {
      throw const _MemoryToolArgumentException(
        'a tag exceeds the ${UserMemoryEntry.maxTagCharacters} character limit.',
      );
    }
    final normalized = UserMemoryEntry.normalizeTags(values);
    if (normalized.length > UserMemoryEntry.maxTags ||
        normalized.any(
          (tag) => tag.length > UserMemoryEntry.maxTagCharacters,
        )) {
      throw const _MemoryToolArgumentException('tags exceed memory limits.');
    }
    return normalized;
  }

  UserMemoryEntry? _entryById(MemoryController controller, String id) {
    for (final entry in controller.entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  AiToolExecutionResult _failedResult(
    Stopwatch stopwatch,
    String message, {
    required String action,
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: _toolName,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: message,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: 'status: failed\nerror: $message',
      metadata: <String, Object?>{'action': action},
    );
  }

  String _preview(String content) {
    final flat = collapseInlineWhitespace(content);
    return clipTextWithEllipsis(flat, _previewChars);
  }
}

class _MemoryToolArgumentException implements Exception {
  const _MemoryToolArgumentException(this.message);

  final String message;
}

class _MemoryToolRequest {
  const _MemoryToolRequest({
    required this.action,
    required this.id,
    required this.content,
    required this.title,
    required this.tags,
    required this.tag,
  });

  final String action;
  final String? id;
  final String? content;
  final String? title;
  final List<String>? tags;
  final String tag;
}
