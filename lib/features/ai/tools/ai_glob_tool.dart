import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiGlobTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.glob;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final pattern = '${args['pattern'] ?? ''}'.trim();
    if (pattern.isEmpty) {
      return AiToolUtils.invalidResult('Glob', 'Glob requires pattern.');
    }
    final rootPath = AiToolUtils.resolvePath('${args['path'] ?? ''}'.trim());
    final rootEntity = FileSystemEntity.typeSync(rootPath);
    if (rootEntity == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult(
        'Glob',
        'Path does not exist: $rootPath',
      );
    }
    // Safety limit to prevent memory exhaustion on broad patterns.
    const maxMatches = 1000;
    var hitLimit = false;
    final matches = <String>[];
    if (rootEntity == FileSystemEntityType.file) {
      final filePath = p.normalize(rootPath);
      final relative = p.basename(filePath);
      if (AiToolUtils.globMatches(relative, pattern)) {
        matches.add(filePath);
      }
    } else {
      await for (final entity in Directory(
        rootPath,
      ).list(recursive: true, followLinks: false)) {
        final normalizedPath = p.normalize(entity.path);
        final relativePath = p
            .relative(normalizedPath, from: rootPath)
            .replaceAll('\\', '/');
        if (AiToolUtils.globMatches(relativePath, pattern)) {
          matches.add(normalizedPath);
          if (matches.length >= maxMatches) {
            hitLimit = true;
            break;
          }
        }
      }
    }
    final fileStats = <String, DateTime>{};
    for (final match in matches) {
      try {
        fileStats[match] = (await FileStat.stat(match)).modified;
      } catch (_) {
        fileStats[match] = DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    matches.sort((left, right) {
      final leftModified =
          fileStats[left] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightModified =
          fileStats[right] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final modifiedComparison = rightModified.compareTo(leftModified);
      if (modifiedComparison != 0) return modifiedComparison;
      return left.compareTo(right);
    });
    var output = matches.isEmpty ? '(no matches)' : matches.join('\n');
    if (hitLimit) {
      output += '\n... (results capped at $maxMatches matches)';
    }
    if (output.length > AiToolUtils.maxSearchOutputCharacters) {
      output =
          '${output.substring(0, AiToolUtils.maxSearchOutputCharacters)}\n'
          '... (output truncated)';
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'Glob $pattern',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: rootPath,
    );
  }
}
