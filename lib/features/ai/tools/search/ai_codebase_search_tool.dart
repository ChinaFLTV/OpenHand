import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/web_engine/web_engine_quality.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// Codebase Search 工具 — 对标 Cursor 的 codebase_search 语义搜索。
///
/// 实现策略：多信号加权搜索（Multi-Signal Weighted Search）。
/// 1. 将用户自然语言 query 拆解为关键词集合
/// 2. 并行执行三路搜索：
///    a) ripgrep 精确匹配（符号名、函数名、类名）
///    b) ripgrep 模糊匹配（关键词 OR 组合）
///    c) 文件名 glob 匹配（基于关键词生成的文件名模式）
/// 3. 合并去重并按匹配权重排序
/// 4. 返回带上下文的代码片段（文件路径 + 行号 + 前后各 3 行）
///
/// 这种方式在无向量数据库的环境下，效果接近 Cursor 的嵌入式搜索，
/// 因为代码库中的语义信息大量存在于命名约定（函数名、类名、注释）中。
class AiCodebaseSearchTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.codebaseSearch;

  @override
  List<String> get aliases => const <String>['CodebaseSearch'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final query = AiToolUtils.readString(args['query']);
    if (query.isEmpty) {
      return AiToolUtils.invalidResult('CodebaseSearch', 'query is required.');
    }

    final searchRoot = _resolveSearchRoot(args);
    final filePattern = AiToolUtils.readString(args['file_pattern']);
    final explanation = AiToolUtils.readString(args['explanation']);
    FileSystemEntityType rootType;
    try {
      rootType = await FileSystemEntity.type(
        searchRoot,
        followLinks: false,
      ).timeout(AiToolUtils.fileTreeScanIdleTimeout);
    } on TimeoutException {
      return AiToolUtils.invalidResult(
        'CodebaseSearch',
        'Search path metadata lookup timed out: $searchRoot',
      );
    }
    if (rootType == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult(
        'CodebaseSearch',
        'Search path does not exist: $searchRoot',
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      return AiToolUtils.invalidResult(
        'CodebaseSearch',
        'Search path is not a directory: $searchRoot',
      );
    }

    try {
      final results = await _multiSignalSearch(
        query,
        searchRoot,
        filePattern: filePattern,
      );

      if (results.isEmpty) {
        return AiToolUtils.simpleSuccessResult(
          command: 'CodebaseSearch',
          output: '(no results for: $query)',
          durationMs: startedAt.elapsedMilliseconds,
          workingDirectory: searchRoot,
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('CodebaseSearch results for: "$query"');
      if (explanation.isNotEmpty) buffer.writeln('Purpose: $explanation');
      if (filePattern.isNotEmpty) {
        buffer.writeln('File pattern: $filePattern');
      }
      buffer.writeln('Found ${results.length} relevant chunk(s):\n');

      for (final result in results) {
        buffer.writeln('--- ${result.filePath}:${result.lineNumber} ---');
        buffer.writeln(result.context);
        buffer.writeln();
      }

      var output = buffer.toString().trimRight();
      output = AiToolUtils.truncateContent(
        output,
        AiToolUtils.maxSearchOutputCharacters,
        suffix: '\n...（搜索结果已截断）',
      );

      return AiToolUtils.simpleSuccessResult(
        command: 'CodebaseSearch',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: searchRoot,
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'CodebaseSearch',
        workingDirectory: searchRoot,
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: CodebaseSearch failed: $error',
      );
    }
  }

  String _resolveSearchRoot(Map<String, Object?> args) {
    final path = AiToolUtils.readString(args['path']);
    if (path.isNotEmpty) return AiToolUtils.resolvePath(path);
    final targetDirs = _parseTargetDirectories(args['target_directories']);
    return targetDirs.isNotEmpty
        ? AiToolUtils.resolvePath(targetDirs.first)
        : AiToolUtils.defaultWorkingDirectory();
  }

  List<String> _parseTargetDirectories(Object? value) {
    return stringListFromValueOrJsonText(value);
  }

  Future<List<_SearchResult>> _multiSignalSearch(
    String query,
    String searchRoot, {
    required String filePattern,
  }) async {
    // Extract meaningful keywords from the natural language query
    final keywords = _extractKeywords(query);
    if (keywords.isEmpty) return const <_SearchResult>[];

    final allResults = <String, _SearchResult>{};

    // Signal 1: Exact keyword grep (highest weight)
    // Try each keyword individually, then combined
    for (final keyword in keywords.take(5)) {
      final results = await _ripgrepSearch(
        searchRoot,
        keyword,
        maxResults: 10,
        filePattern: filePattern,
      );
      for (final r in results) {
        if (!_matchesFilePattern(r.filePath, searchRoot, filePattern)) {
          continue;
        }
        final key = '${r.filePath}:${r.lineNumber}';
        if (!allResults.containsKey(key)) {
          allResults[key] = r.copyWith(weight: r.weight + 3);
        } else {
          allResults[key] = allResults[key]!.copyWith(
            weight: allResults[key]!.weight + 2,
          );
        }
      }
    }

    // Signal 2: Combined pattern grep (medium weight)
    if (keywords.length >= 2) {
      // Search for files containing multiple keywords
      final pattern = keywords.take(4).join('|');
      final results = await _ripgrepSearch(
        searchRoot,
        pattern,
        maxResults: 15,
        filePattern: filePattern,
      );
      for (final r in results) {
        if (!_matchesFilePattern(r.filePath, searchRoot, filePattern)) {
          continue;
        }
        final key = '${r.filePath}:${r.lineNumber}';
        if (!allResults.containsKey(key)) {
          allResults[key] = r;
        } else {
          allResults[key] = allResults[key]!.copyWith(
            weight: allResults[key]!.weight + 1,
          );
        }
      }
    }

    // Signal 3: File name matching (bonus weight for files whose names match)
    for (final keyword in keywords.take(3)) {
      final fileResults = await _findFilesByName(
        searchRoot,
        keyword,
        filePattern: filePattern,
      );
      for (final filePath in fileResults) {
        // Read first 20 lines as context
        final file = File(filePath);
        String preview;
        try {
          final content = await readBoundedFileString(
            file,
            maxBytes: AiToolUtils.maxReadBytes,
          );
          preview = content.split('\n').take(20).join('\n');
        } on IOException {
          continue;
        } on FormatException {
          continue;
        }
        final result = _SearchResult(
          filePath: filePath,
          lineNumber: 1,
          context: preview,
          weight: 2,
        );
        final key = '$filePath:1';
        if (!allResults.containsKey(key)) {
          allResults[key] = result;
        } else {
          allResults[key] = allResults[key]!.copyWith(
            weight: allResults[key]!.weight + 2,
          );
        }
      }
    }

    // Sort by weight descending and return top results
    final sorted = allResults.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    return sorted.take(20).toList(growable: false);
  }

  bool _matchesFilePattern(
    String filePath,
    String searchRoot,
    String filePattern,
  ) {
    if (filePattern.isEmpty) return true;
    final absolutePath = p.isAbsolute(filePath)
        ? p.normalize(filePath)
        : p.normalize(p.join(searchRoot, filePath));
    final relativePath = p
        .relative(absolutePath, from: searchRoot)
        .replaceAll('\\', '/');
    return AiToolUtils.globMatches(relativePath, filePattern) ||
        AiToolUtils.globMatches(p.basename(absolutePath), filePattern);
  }

  List<String> _extractKeywords(String query) {
    final words = webQualityTerms(query, limit: 64, preserveCase: true);
    final fragments = <String>[];
    for (final word in words) {
      fragments.add(word);
      final camelParts = word
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (m) => '${m.group(1)} ${m.group(2)}',
          )
          .split(' ')
          .where((p) => p.length >= 3)
          .toList();
      if (camelParts.length > 1) fragments.addAll(camelParts);
      if (word.contains('_')) {
        fragments.addAll(word.split('_').where((p) => p.length >= 3));
      }
    }

    final seen = <String>{};
    return fragments.where((f) => seen.add(f.toLowerCase())).toList();
  }

  Future<List<_SearchResult>> _ripgrepSearch(
    String searchRoot,
    String pattern, {
    int contextLines = 3,
    int maxResults = 20,
    bool caseInsensitive = true,
    required String filePattern,
  }) async {
    final rgPath = await AiToolUtils.resolveRipgrepPath();
    if (rgPath == null) {
      return const <_SearchResult>[];
    }

    final args = <String>[
      '--json',
      '-C', '$contextLines',
      if (caseInsensitive) '-i',
      '--max-count', '5',
      '--type-add',
      'code:*.{dart,ts,tsx,js,jsx,py,go,rs,java,kt,swift,c,cpp,h,hpp,cs,rb,php,yaml,yml,json,toml,md}',
      '--type', 'code',
      if (filePattern.isNotEmpty) ...['--glob', filePattern],
      pattern,
      '.', // 在工作目录中搜索
    ];

    final result = await AiToolUtils.runProcessSafely(
      rgPath,
      args,
      workingDirectory: searchRoot,
    );

    if (result.exitCode != 0 && result.exitCode != 1) {
      return const <_SearchResult>[];
    }

    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) return const <_SearchResult>[];

    return _parseRipgrepJson(stdout, maxResults, searchRoot: searchRoot);
  }

  List<_SearchResult> _parseRipgrepJson(
    String jsonOutput,
    int maxResults, {
    required String searchRoot,
  }) {
    final results = <String, _SearchResult>{};
    final lines = jsonOutput.split('\n');

    String? currentFile;
    final contextBuffer = StringBuffer();
    int? matchLine;

    for (final line in lines) {
      if (nullIfBlank(line) == null) continue;
      try {
        final decoded = tryDecodeJson(line);
        if (decoded is! Map) continue;
        final Map<String, dynamic> entry = Map<String, dynamic>.from(decoded);
        final type = entry['type'] as String? ?? '';

        if (type == 'match') {
          final data =
              entry['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final rawPath =
              (data['path'] as Map<String, dynamic>?)?['text'] as String? ?? '';
          final path = p.isAbsolute(rawPath)
              ? p.normalize(rawPath)
              : p.normalize(p.join(searchRoot, rawPath));
          final lineNum = data['line_number'] as int? ?? 0;
          final text =
              (data['lines'] as Map<String, dynamic>?)?['text'] as String? ??
              '';

          if (currentFile != null && currentFile != path && matchLine != null) {
            final key = '$currentFile:$matchLine';
            if (!results.containsKey(key) && results.length < maxResults) {
              results[key] = _SearchResult(
                filePath: currentFile,
                lineNumber: matchLine,
                context: contextBuffer.toString().trimRight(),
                weight: 1,
              );
            }
            contextBuffer.clear();
          }

          currentFile = path;
          matchLine = lineNum;
          contextBuffer.writeln('$lineNum: ${text.trimRight()}');
        } else if (type == 'context') {
          final data =
              entry['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final lineNum = data['line_number'] as int? ?? 0;
          final text =
              (data['lines'] as Map<String, dynamic>?)?['text'] as String? ??
              '';
          contextBuffer.writeln('$lineNum: ${text.trimRight()}');
        }
      } catch (_) {
        // Skip malformed lines
      }
    }

    // Flush last result
    if (currentFile != null && matchLine != null) {
      final key = '$currentFile:$matchLine';
      if (!results.containsKey(key) && results.length < maxResults) {
        results[key] = _SearchResult(
          filePath: currentFile,
          lineNumber: matchLine,
          context: contextBuffer.toString().trimRight(),
          weight: 1,
        );
      }
    }

    return results.values.toList();
  }

  Future<List<String>> _findFilesByName(
    String searchRoot,
    String keyword, {
    required String filePattern,
  }) async {
    // Use glob-style file search
    final lowerKeyword = keyword.toLowerCase();
    final results = <String>[];
    final stopwatch = Stopwatch()..start();

    try {
      final dir = Directory(searchRoot);
      var scannedEntries = 0;
      await for (final entity
          in dir
              .list(recursive: true, followLinks: false)
              .timeout(AiToolUtils.fileTreeScanIdleTimeout)) {
        scannedEntries += 1;
        if (scannedEntries > AiToolUtils.maxFileTreeScanEntries ||
            stopwatch.elapsed >= AiToolUtils.fileTreeScanTotalTimeout) {
          break;
        }
        if (entity is File) {
          final basename = p.basename(entity.path).toLowerCase();
          // Skip hidden files, build artifacts, node_modules
          if (entity.path.contains('/.') ||
              entity.path.contains('/build/') ||
              entity.path.contains('/node_modules/') ||
              entity.path.contains('/.dart_tool/')) {
            continue;
          }
          if (!_matchesFilePattern(entity.path, searchRoot, filePattern)) {
            continue;
          }
          if (basename.contains(lowerKeyword)) {
            results.add(entity.path);
            if (results.length >= 5) break;
          }
        }
      }
    } on TimeoutException {
      return results;
    } catch (error, stack) {
      silentLog('ai_codebase_search_tool', '遍历代码库条目执行关键词扫描', error, stack);
    } finally {
      stopwatch.stop();
    }

    return results;
  }
}

class _SearchResult {
  const _SearchResult({
    required this.filePath,
    required this.lineNumber,
    required this.context,
    required this.weight,
  });

  final String filePath;
  final int lineNumber;
  final String context;
  final int weight;

  _SearchResult copyWith({int? weight}) {
    return _SearchResult(
      filePath: filePath,
      lineNumber: lineNumber,
      context: context,
      weight: weight ?? this.weight,
    );
  }
}
