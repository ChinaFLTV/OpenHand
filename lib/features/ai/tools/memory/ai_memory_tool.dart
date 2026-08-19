import 'dart:convert';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../memory/index.dart';
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

  /// 供自主学习调度器直接执行已解析的工具参数。
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
        return _failedResult(stopwatch, '记忆存储不可用。', action: action);
      }
      if (!await controller.ensureLoaded()) {
        return _failedResult(stopwatch, '无法加载记忆存储。', action: action);
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
        _ => throw StateError('无法到达的记忆操作：$action'),
      };
    } on _MemoryToolArgumentException catch (error) {
      return AiToolUtils.invalidResult(_toolName, error.message);
    } catch (error, stackTrace) {
      silentLog('ai_memory_tool', '执行/$action', error, stackTrace);
      return _failedResult(stopwatch, '记忆操作失败。', action: action);
    }
  }

  // 操作实现
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
      output: buffer.isEmpty ? '没有记忆条目。' : buffer.toString(),
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
      return _failedResult(sw, '无法追加记忆。', action: 'append');
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: '记忆已追加。',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: _mutationReason,
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
        '用户资料在本次执行期间已变化，已跳过更新。',
        action: 'upsert_profile',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'user_profile 已更新（id=${entry.id}）。',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: _mutationReason,
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
      return AiToolUtils.invalidResult(_toolName, '不存在 ID 为“$id”的记忆条目。');
    }
    if (target.isUserProfile) {
      return AiToolUtils.invalidResult(
        _toolName,
        'user_profile 只能通过 upsert_profile 修改。',
      );
    }
    final ok = await controller.updateMemory(
      target,
      content: request.content!,
      tags: request.tags,
      title: request.title,
    );
    if (!ok) {
      return _failedResult(sw, '无法更新记忆。', action: 'update');
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: '记忆已更新（id=$id）。',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: _mutationReason,
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
      return AiToolUtils.invalidResult(_toolName, '不存在 ID 为“$id”的记忆条目。');
    }
    if (target.isUserProfile) {
      return AiToolUtils.invalidResult(_toolName, '此工具不能删除 user_profile。');
    }
    final ok = await controller.deleteMemory(target);
    if (!ok) {
      return _failedResult(sw, '无法删除记忆。', action: 'delete');
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: '记忆已删除（id=$id）。',
      durationMs: sw.elapsedMilliseconds,
      isWriteCommand: true,
      writeAnalysisReason: _mutationReason,
      metadata: <String, Object?>{'action': 'delete', 'id': id},
    );
  }

  static const String _toolName = 'Memory';
  static const String _mutationReason = '记忆存储变更';
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
        '未知 action“$action”，可选值：${_actions.join(' | ')}。',
      );
    }
    final allowedArguments = _argumentNamesByAction[action]!;
    final irrelevant = args.keys
        .where((key) => !allowedArguments.contains(key))
        .toList(growable: false);
    if (irrelevant.isNotEmpty) {
      throw _MemoryToolArgumentException('${irrelevant.first} 不适用于 $action。');
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
      throw const _MemoryToolArgumentException('purpose 必须为字符串。');
    }

    if ((action == 'update' || action == 'delete') &&
        (id == null || id.isEmpty)) {
      throw _MemoryToolArgumentException('$action 需要非空 id。');
    }
    if ((action == 'append' ||
            action == 'upsert_profile' ||
            action == 'update') &&
        (content == null || content.trim().isEmpty)) {
      throw _MemoryToolArgumentException('$action 需要非空 content。');
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
      throw _MemoryToolArgumentException('$key 必须为非空字符串。');
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
      throw _MemoryToolArgumentException('$key 必须为字符串。');
    }
    if (value.length > maxCharacters) {
      throw _MemoryToolArgumentException('$key 超过 $maxCharacters 个字符上限。');
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
          'tags 超过 ${UserMemoryEntry.maxTags} 项上限。',
        );
      }
      if (raw.any((value) => value is! String)) {
        throw const _MemoryToolArgumentException('tags 只能包含字符串。');
      }
      values = raw.cast<String>();
    } else if (raw is String) {
      if (raw.length > _maxTagsTextCharacters) {
        throw const _MemoryToolArgumentException('tags 文本超过记忆限制。');
      }
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const <String>[];
      if (trimmed.startsWith('[')) {
        final Object? decoded;
        try {
          decoded = jsonDecode(trimmed);
        } on FormatException {
          throw const _MemoryToolArgumentException('tags JSON 必须为字符串数组。');
        }
        if (decoded is! List || decoded.any((value) => value is! String)) {
          throw const _MemoryToolArgumentException('tags JSON 必须为字符串数组。');
        }
        values = decoded.cast<String>();
      } else {
        if (trimmed.startsWith('{')) {
          throw const _MemoryToolArgumentException('tags 必须为字符串数组或逗号分隔文本。');
        }
        values = splitTrimmedNonEmpty(trimmed);
      }
    } else {
      throw const _MemoryToolArgumentException('tags 必须为字符串数组或逗号分隔文本。');
    }
    if (values.length > UserMemoryEntry.maxTags) {
      throw const _MemoryToolArgumentException(
        'tags 超过 ${UserMemoryEntry.maxTags} 项上限。',
      );
    }
    if (values.any((tag) => tag.length > UserMemoryEntry.maxTagCharacters)) {
      throw const _MemoryToolArgumentException(
        '存在 tag 超过 ${UserMemoryEntry.maxTagCharacters} 个字符上限。',
      );
    }
    final normalized = UserMemoryEntry.normalizeTags(values);
    if (normalized.length > UserMemoryEntry.maxTags ||
        normalized.any(
          (tag) => tag.length > UserMemoryEntry.maxTagCharacters,
        )) {
      throw const _MemoryToolArgumentException('tags 超过记忆限制。');
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
