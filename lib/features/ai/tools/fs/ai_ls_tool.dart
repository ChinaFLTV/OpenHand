import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiLsTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.ls;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawPath = '${args['path'] ?? ''}'.trim();
    if (rawPath.isEmpty) {
      return AiToolUtils.invalidResult(
        'LS',
        'LS requires a non-empty path.',
      );
    }
    // 2026-04-28: 与 Read/Write/Edit 等其它工具对齐 —— 模型经常传相对路径
    // （如 "."、"src/"），原本的 requireAbsoluteDirectoryPath 会硬拒并返回
    // invalid_arguments，让模型陷入“参数明明对、却被反复拒”的死循环。
    // 改用 resolvePath，相对路径自动按当前工作目录展开为绝对路径。
    final path = AiToolUtils.resolvePath(rawPath);
    final directory = Directory(path);
    if (!await directory.exists()) {
      return AiToolUtils.invalidResult('LS', 'Directory does not exist: $path');
    }
    final ignorePatterns = args['ignore'] is List
        ? (args['ignore'] as List)
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final entries = await directory.list().toList();
    entries.sort((left, right) => left.path.compareTo(right.path));
    final lines = <String>[];
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (AiToolUtils.matchesAnyGlob(name, ignorePatterns) ||
          AiToolUtils.matchesAnyGlob(entry.path, ignorePatterns)) {
        continue;
      }
      final type = entry is Directory
          ? 'dir'
          : entry is Link
          ? 'link'
          : 'file';
      lines.add('$type\t$name');
    }
    final output = lines.isEmpty ? '(empty)' : lines.join('\n');
    return AiToolUtils.simpleSuccessResult(
      command: 'LS $path',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: path,
    );
  }
}
