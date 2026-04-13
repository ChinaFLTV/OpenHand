import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiLsTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.ls;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final path = AiToolUtils.requireAbsoluteDirectoryPath(
      '${args['path'] ?? ''}'.trim(),
    );
    if (path == null) {
      return AiToolUtils.invalidResult('LS', 'LS requires an absolute path.');
    }
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
