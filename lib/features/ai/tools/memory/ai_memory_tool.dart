library;

import '../../../../shared/util/input_value_parsing.dart';
import '../../../memory/index.dart';

/// Hermes Talker 专用 Memory 工具。
///
/// 提供给自我学习子 Agent 使用，将对话中的关键结论沉淀到 [MemoryController]
/// 管理的用户记忆存储。为了和 `SkillManager` 对齐，本工具名为 `Memory`，
/// 注册在 [AiBuiltinToolKind.memory] 下。
///
/// 支持的 action:
/// * `list`        — 列出当前所有记忆（可按 tag 过滤）。
/// * `append`      — 追加一条普通记忆条目。
/// * `upsert_profile` — 更新/创建唯一的 user_profile 条目。
/// * `update`      — 修改指定 id 的条目。
/// * `delete`      — 删除指定 id 的条目。
///
/// 与其它内置工具的区别：本工具**不是 destructive**（delete 是白名单内
/// 允许子 Agent 发起的行为），但仅在 Hermes Talker 自我学习场景下
/// 被注册到工具目录（由 registry 的 `memoryControllerProvider` 控制）。

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
  Future<AiToolExecutionResult> run(Map<String, Object?> args) async {
    final stopwatch = Stopwatch()..start();
    final action = '${args['action'] ?? ''}'.trim().toLowerCase();

    final controller = memoryControllerProvider();
    if (controller == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'Memory controller is not available in this session.',
      );
    }

    try {
      return switch (action) {
        'list' => _list(controller, args, stopwatch),
        'append' => await _append(controller, args, stopwatch),
        'upsert_profile' => await _upsertProfile(controller, args, stopwatch),
        'update' => await _update(controller, args, stopwatch),
        'delete' => await _delete(controller, args, stopwatch),
        _ => AiToolUtils.invalidResult(
          _toolName,
          'Unknown action "$action". Valid: list | append | upsert_profile | update | delete.',
        ),
      };
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: _toolName,
        workingDirectory: '',
        stdout: '',
        stderr: '$error',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failure\nerror: $error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  AiToolExecutionResult _list(
    MemoryController controller,
    Map<String, Object?> args,
    Stopwatch sw,
  ) {
    final tag = '${args['tag'] ?? ''}'.trim();
    final entries = tag.isEmpty
        ? controller.entries
        : controller.memoriesWithTag(tag);
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln(
        '- [${entry.type}] id=${entry.id} tags=${entry.tags.join(',')} '
        'content="${_preview(entry.content)}"',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: buffer.isEmpty ? 'No memory entries.' : buffer.toString(),
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{
        'action': 'list',
        'count': entries.length,
        'tag': tag,
      },
    );
  }

  Future<AiToolExecutionResult> _append(
    MemoryController controller,
    Map<String, Object?> args,
    Stopwatch sw,
  ) async {
    final content = '${args['content'] ?? ''}';
    final title = '${args['title'] ?? ''}';
    final rawTags = args['tags'];
    final tags = _readStringList(rawTags);
    if (content.trim().isEmpty) {
      return AiToolUtils.invalidResult(
        _toolName,
        'append requires non-empty "content".',
      );
    }
    final ok = await controller.createMemory(
      content: content,
      tags: tags,
      title: title,
    );
    if (!ok) {
      return AiToolUtils.invalidResult(
        _toolName,
        'createMemory returned false (empty content after normalization?).',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'Memory appended.',
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{'action': 'append'},
    );
  }

  Future<AiToolExecutionResult> _upsertProfile(
    MemoryController controller,
    Map<String, Object?> args,
    Stopwatch sw,
  ) async {
    final content = '${args['content'] ?? ''}';
    final tags = _readStringList(args['tags']);
    if (content.trim().isEmpty) {
      return AiToolUtils.invalidResult(
        _toolName,
        'upsert_profile requires non-empty "content".',
      );
    }
    final entry = await controller.upsertUserProfile(
      content: content,
      tags: tags,
    );
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'user_profile upserted (id=${entry.id}).',
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{'action': 'upsert_profile', 'id': entry.id},
    );
  }

  Future<AiToolExecutionResult> _update(
    MemoryController controller,
    Map<String, Object?> args,
    Stopwatch sw,
  ) async {
    final id = '${args['id'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';
    final tags = _readStringList(args['tags']);
    // 2026-04-25: title 是可选。传 null 表示保留原有标题，
    // 传空串 / 非空串表示显式覆盖。
    final titleArg = args['title'];
    final String? title = titleArg == null ? null : '$titleArg';
    if (id.isEmpty) {
      return AiToolUtils.invalidResult(_toolName, 'update requires "id".');
    }
    UserMemoryEntry? target;
    for (final entry in controller.entries) {
      if (entry.id == id) {
        target = entry;
        break;
      }
    }
    if (target == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'No memory entry with id="$id".',
      );
    }
    final ok = await controller.updateMemory(
      target,
      content: content,
      tags: tags,
      title: title,
    );
    if (!ok) {
      return AiToolUtils.invalidResult(
        _toolName,
        'updateMemory returned false.',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'Memory updated (id=$id).',
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{'action': 'update', 'id': id},
    );
  }

  Future<AiToolExecutionResult> _delete(
    MemoryController controller,
    Map<String, Object?> args,
    Stopwatch sw,
  ) async {
    final id = '${args['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      return AiToolUtils.invalidResult(_toolName, 'delete requires "id".');
    }
    UserMemoryEntry? target;
    for (final entry in controller.entries) {
      if (entry.id == id) {
        target = entry;
        break;
      }
    }
    if (target == null) {
      return AiToolUtils.invalidResult(
        _toolName,
        'No memory entry with id="$id".',
      );
    }
    final ok = await controller.deleteMemory(target);
    if (!ok) {
      return AiToolUtils.invalidResult(
        _toolName,
        'deleteMemory returned false.',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: _toolName,
      output: 'Memory deleted (id=$id).',
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{'action': 'delete', 'id': id},
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static const String _toolName = 'Memory';
  static const int _previewChars = 200;

  List<String> _readStringList(Object? raw) {
    return stringListFromValueOrJsonText(raw);
  }

  String _preview(String content) {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= _previewChars) return flat;
    return '${flat.substring(0, _previewChars)}…';
  }
}
