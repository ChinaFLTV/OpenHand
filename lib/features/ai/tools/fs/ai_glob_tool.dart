import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiGlobTool extends AiTool {
  static const int _maxMatches = 100;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.glob;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final pattern = AiToolUtils.readString(args['pattern']);
    if (pattern.isEmpty) {
      return AiToolUtils.invalidResult('Glob', 'Glob requires pattern.');
    }
    final rootPath = AiToolUtils.resolvePath(
      AiToolUtils.readString(args['path']),
    );
    final rootEntity = FileSystemEntity.typeSync(rootPath);
    if (rootEntity == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult(
        'Glob',
        'Directory does not exist: $rootPath',
      );
    }
    if (rootEntity != FileSystemEntityType.directory) {
      return AiToolUtils.invalidResult(
        'Glob',
        'Path is not a directory: $rootPath',
      );
    }
    var hitLimit = false;
    var hitScanLimit = false;
    var scannedEntries = 0;
    final matches = <_GlobMatch>[];
    final scanStopwatch = Stopwatch()..start();
    try {
      await for (final entity
          in Directory(rootPath)
              .list(recursive: true, followLinks: false)
              .timeout(AiToolUtils.fileTreeScanIdleTimeout)) {
        scannedEntries += 1;
        if (scannedEntries > AiToolUtils.maxFileTreeScanEntries ||
            scanStopwatch.elapsed >= AiToolUtils.fileTreeScanTotalTimeout) {
          hitScanLimit = true;
          break;
        }
        if (entity is! File) {
          continue;
        }
        final normalizedPath = p.normalize(entity.path);
        final relativePath = p
            .relative(normalizedPath, from: rootPath)
            .replaceAll('\\', '/');
        if (AiToolUtils.globMatches(relativePath, pattern)) {
          DateTime modified;
          try {
            modified = (await FileStat.stat(normalizedPath)).modified;
          } catch (_) {
            modified = DateTime.fromMillisecondsSinceEpoch(0);
          }
          matches.add(_GlobMatch(path: normalizedPath, modified: modified));
          if (matches.length > _maxMatches) {
            hitLimit = true;
            matches.sort(_compareGlobMatches);
            matches.removeLast();
          }
        }
      }
    } on TimeoutException {
      hitScanLimit = true;
    } finally {
      scanStopwatch.stop();
    }
    matches.sort(_compareGlobMatches);
    final workingDirectory = AiToolUtils.defaultWorkingDirectory();
    final outputPaths = matches
        .map((match) => p.relative(match.path, from: workingDirectory))
        .map((match) => match.replaceAll('\\', '/'))
        .toList(growable: false);
    var output = outputPaths.isEmpty ? '(no matches)' : outputPaths.join('\n');
    if (hitLimit) {
      output +=
          '\n(Results are truncated. Consider using a more specific path or pattern.)';
    }
    if (hitScanLimit) {
      output +=
          '\n(Directory scan reached its safety limit. Use a narrower path.)';
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
      metadata: <String, Object?>{
        'glob_root_path': rootPath,
        'glob_result_count': outputPaths.length,
        'glob_result_truncated': hitLimit,
        'glob_scan_truncated': hitScanLimit,
        'glob_scanned_entries': scannedEntries,
        'glob_result_relative_to': workingDirectory,
        'glob_max_results': _maxMatches,
      },
    );
  }

  static int _compareGlobMatches(_GlobMatch left, _GlobMatch right) {
    final modifiedComparison = right.modified.compareTo(left.modified);
    if (modifiedComparison != 0) return modifiedComparison;
    return left.path.compareTo(right.path);
  }
}

class _GlobMatch {
  const _GlobMatch({required this.path, required this.modified});

  final String path;
  final DateTime modified;
}
