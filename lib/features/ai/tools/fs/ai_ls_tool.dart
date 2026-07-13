import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiLsTool extends AiTool {
  static const int _maxDirectoryEntries = 5000;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.ls;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawPath = AiToolUtils.readString(args['path']);
    final path = AiToolUtils.resolvePath(rawPath);
    final pathType = FileSystemEntity.typeSync(path);
    if (pathType == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult('LS', 'Directory does not exist: $path');
    }
    if (pathType != FileSystemEntityType.directory) {
      return AiToolUtils.invalidResult('LS', 'Path is not a directory: $path');
    }
    final directory = Directory(path);
    final ignorePatterns = stringListFromValueOrJsonText(args['ignore']);
    final listing = await listDirectoryBounded(
      directory,
      maxEntries: _maxDirectoryEntries,
    );
    final entries = listing.entries.toList(growable: false);
    entries.sort((left, right) => left.path.compareTo(right.path));
    final lines = <String>[];
    var ignoredCount = 0;
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (AiToolUtils.matchesAnyGlob(name, ignorePatterns) ||
          AiToolUtils.matchesAnyGlob(entry.path, ignorePatterns)) {
        ignoredCount += 1;
        continue;
      }
      final type = entry is Directory
          ? 'dir'
          : entry is Link
          ? 'link'
          : 'file';
      lines.add('$type\t$name');
    }
    var output = lines.isEmpty ? '(empty)' : lines.join('\n');
    if (listing.truncated) {
      output +=
          '\n(Directory listing truncated at $_maxDirectoryEntries entries.)';
    }
    if (output.length > AiToolUtils.maxSearchOutputCharacters) {
      output =
          '${output.substring(0, AiToolUtils.maxSearchOutputCharacters)}\n'
          '... (output truncated)';
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'LS $path',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: path,
      metadata: <String, Object?>{
        'ls_path': path,
        'ls_entry_count': lines.length,
        'ls_ignored_count': ignoredCount,
        'ls_truncated': listing.truncated,
        'ls_defaulted_to_working_directory': rawPath.isEmpty,
      },
    );
  }
}
