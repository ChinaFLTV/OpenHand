import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/web_engine/web_engine_quality.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 代码库搜索工具，提供接近 Cursor `codebase_search` 的语义搜索能力。
///
/// 实现策略：多信号加权搜索。
/// 1. 将用户自然语言查询拆解为关键词集合
/// 2. 执行三路搜索：
///    a) `ripgrep` 精确匹配（符号名、函数名、类名）
///    b) `ripgrep` 模糊匹配（关键词或组合）
///    c) 文件名通配符匹配（基于关键词生成文件名模式）
/// 3. 合并去重并按匹配权重排序
/// 4. 返回带上下文的代码片段（文件路径 + 行号 + 前后各 3 行）
///
/// 这种方式在无向量数据库的环境下，效果接近 Cursor 的嵌入式搜索，
/// 因为代码库中的语义信息大量存在于命名约定（函数名、类名、注释）中。
class AiCodebaseSearchTool extends AiTool {
  static const int _maxFileNameMatches = 15;
  static const int _maxFileNameMatchesPerKeyword = 5;
  static const Set<String> _ignoredDirectoryNames = <String>{
    'build',
    'node_modules',
  };

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
      return AiToolUtils.invalidResult('CodebaseSearch', '必须提供 query。');
    }

    final searchRoot = _resolveSearchRoot(args);
    final filePattern = AiToolUtils.readString(args['file_pattern']);
    final explanation = AiToolUtils.readString(args['explanation']);
    final rootType = await probeFileSystemEntityType(searchRoot);
    if (rootType == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult('CodebaseSearch', '搜索路径不存在：$searchRoot');
    }
    if (rootType != FileSystemEntityType.directory) {
      return AiToolUtils.invalidResult(
        'CodebaseSearch',
        '搜索路径不是目录：$searchRoot',
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
          output: '（未找到与“$query”相关的结果）',
          durationMs: startedAt.elapsedMilliseconds,
          workingDirectory: searchRoot,
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('CodebaseSearch 查询：“$query”');
      if (explanation.isNotEmpty) buffer.writeln('目的：$explanation');
      if (filePattern.isNotEmpty) {
        buffer.writeln('文件 pattern：$filePattern');
      }
      buffer.writeln('找到 ${results.length} 个相关片段：\n');

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
        resultText: 'status: failed\nerror: CodebaseSearch 执行失败：$error',
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
    // 从自然语言查询中提取有效关键词。
    final keywords = _extractKeywords(query);
    if (keywords.isEmpty) return const <_SearchResult>[];

    final allResults = <String, _SearchResult>{};

    // 信号一：逐个关键词精确搜索，权重最高。
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

    // 信号二：组合多个关键词搜索，权重居中。
    if (keywords.length >= 2) {
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

    // 信号三：单次目录扫描完成文件名匹配，命中多个关键词时累加权重。
    final fileMatches = await _findFilesByName(
      searchRoot,
      keywords.take(3),
      filePattern: filePattern,
    );
    for (final match in fileMatches) {
      final file = File(match.path);
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
      final key = '${match.path}:1';
      final bonusWeight = match.keywordMatches * 2;
      final existing = allResults[key];
      if (existing == null) {
        allResults[key] = _SearchResult(
          filePath: match.path,
          lineNumber: 1,
          context: preview,
          weight: bonusWeight,
        );
      } else {
        allResults[key] = existing.copyWith(
          weight: existing.weight + bonusWeight,
        );
      }
    }

    // 按权重降序返回最相关结果。
    final sorted = allResults.values.toList()
      ..sort((left, right) {
        final weight = right.weight.compareTo(left.weight);
        if (weight != 0) return weight;
        final path = left.filePath.compareTo(right.filePath);
        return path != 0 ? path : left.lineNumber.compareTo(right.lineNumber);
      });
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
            RegExp('([a-z])([A-Z])'),
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

    return _parseRipgrepJson(
      stdout,
      maxResults,
      searchRoot: searchRoot,
      contextLines: contextLines,
    );
  }

  List<_SearchResult> _parseRipgrepJson(
    String jsonOutput,
    int maxResults, {
    required String searchRoot,
    required int contextLines,
  }) {
    final results = <_SearchResult>[];
    final selectedKeys = <String>{};
    final lines = jsonOutput.split('\n');
    final recentLines =
        Queue<({String filePath, int lineNumber, String text})>();
    final pendingResults =
        <({String filePath, int lineNumber, StringBuffer buffer})>[];

    void completePending([String? filePath, int? lineNumber]) {
      var index = 0;
      while (index < pendingResults.length) {
        final pending = pendingResults[index];
        final completed =
            filePath == null ||
            lineNumber == null ||
            pending.filePath != filePath ||
            lineNumber > pending.lineNumber + contextLines;
        if (!completed) {
          index += 1;
          continue;
        }
        results.add(
          _SearchResult(
            filePath: pending.filePath,
            lineNumber: pending.lineNumber,
            context: pending.buffer.toString().trimRight(),
            weight: 1,
          ),
        );
        pendingResults.removeAt(index);
      }
    }

    for (final line in lines) {
      if (nullIfBlank(line) == null) continue;
      try {
        final decoded = tryDecodeJson(line);
        if (decoded is! Map) continue;
        final Map<String, dynamic> entry = Map<String, dynamic>.from(decoded);
        final type = entry['type'] as String? ?? '';

        if (type == 'begin' || type == 'end') {
          completePending();
          recentLines.clear();
          if (results.length >= maxResults) break;
          continue;
        }
        if (type != 'match' && type != 'context') continue;

        final data =
            entry['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final rawPath =
            (data['path'] as Map<String, dynamic>?)?['text'] as String? ?? '';
        final lineNum = data['line_number'] as int? ?? 0;
        if (rawPath.trim().isEmpty || lineNum <= 0) continue;
        final path = p.isAbsolute(rawPath)
            ? p.normalize(rawPath)
            : p.normalize(p.join(searchRoot, rawPath));
        final text =
            (data['lines'] as Map<String, dynamic>?)?['text'] as String? ?? '';

        completePending(path, lineNum);
        if (results.length >= maxResults && pendingResults.isEmpty) break;
        while (recentLines.isNotEmpty &&
            (recentLines.first.filePath != path ||
                recentLines.first.lineNumber < lineNum - contextLines)) {
          recentLines.removeFirst();
        }
        for (final pending in pendingResults) {
          if (pending.filePath == path &&
              lineNum > pending.lineNumber &&
              lineNum <= pending.lineNumber + contextLines) {
            pending.buffer.writeln('$lineNum: ${text.trimRight()}');
          }
        }
        if (type == 'match' &&
            results.length + pendingResults.length < maxResults &&
            selectedKeys.add('$path:$lineNum')) {
          final buffer = StringBuffer();
          for (final recent in recentLines) {
            if (recent.filePath == path && recent.lineNumber < lineNum) {
              buffer.writeln(
                '${recent.lineNumber}: ${recent.text.trimRight()}',
              );
            }
          }
          buffer.writeln('$lineNum: ${text.trimRight()}');
          pendingResults.add((
            filePath: path,
            lineNumber: lineNum,
            buffer: buffer,
          ));
        }
        recentLines.add((filePath: path, lineNumber: lineNum, text: text));
      } catch (_) {
        // 忽略损坏的输出行。
      }
    }

    completePending();

    return results;
  }

  Future<List<({String path, int keywordMatches})>> _findFilesByName(
    String searchRoot,
    Iterable<String> keywords, {
    required String filePattern,
  }) async {
    final seenKeywords = <String>{};
    final normalizedKeywords = keywords
        .map((keyword) => keyword.trim().toLowerCase())
        .where((keyword) => keyword.isNotEmpty && seenKeywords.add(keyword))
        .toList(growable: false);
    if (normalizedKeywords.isEmpty) {
      return const <({String path, int keywordMatches})>[];
    }

    final results = <({String path, int keywordMatches})>[];
    final matchCounts = <String, int>{
      for (final keyword in normalizedKeywords) keyword: 0,
    };
    final pending = Queue<Directory>()..add(Directory(searchRoot));
    final stopwatch = Stopwatch()..start();
    var scannedEntries = 0;

    try {
      while (pending.isNotEmpty &&
          results.length < _maxFileNameMatches &&
          matchCounts.values.any(
            (count) => count < _maxFileNameMatchesPerKeyword,
          )) {
        final remainingEntries =
            AiToolUtils.maxFileTreeScanEntries - scannedEntries;
        final remainingTime =
            AiToolUtils.fileTreeScanTotalTimeout - stopwatch.elapsed;
        if (remainingEntries <= 0 || remainingTime <= Duration.zero) break;
        final idleTimeout = remainingTime < AiToolUtils.fileTreeScanIdleTimeout
            ? remainingTime
            : AiToolUtils.fileTreeScanIdleTimeout;
        final listing = await listDirectoryBounded(
          pending.removeFirst(),
          maxEntries: remainingEntries,
          idleTimeout: idleTimeout,
          totalTimeout: remainingTime,
        );
        for (final entity in listing.entries) {
          scannedEntries += 1;
          final name = p.basename(entity.path);
          if (entity is Directory) {
            if (!_isIgnoredDirectoryName(name)) pending.add(entity);
            continue;
          }
          if (entity is! File || name.startsWith('.')) continue;
          if (!_matchesFilePattern(entity.path, searchRoot, filePattern)) {
            continue;
          }
          final basename = name.toLowerCase();
          var keywordMatches = 0;
          var hasAvailableKeyword = false;
          for (final keyword in normalizedKeywords) {
            if (!basename.contains(keyword)) continue;
            keywordMatches += 1;
            if (matchCounts[keyword]! < _maxFileNameMatchesPerKeyword) {
              hasAvailableKeyword = true;
            }
          }
          if (!hasAvailableKeyword) continue;
          results.add((path: entity.path, keywordMatches: keywordMatches));
          for (final keyword in normalizedKeywords) {
            if (!basename.contains(keyword)) continue;
            final count = matchCounts[keyword]!;
            if (count < _maxFileNameMatchesPerKeyword) {
              matchCounts[keyword] = count + 1;
            }
          }
          if (results.length >= _maxFileNameMatches ||
              matchCounts.values.every(
                (count) => count >= _maxFileNameMatchesPerKeyword,
              )) {
            break;
          }
        }
        if (listing.truncated) break;
      }
    } catch (error, stack) {
      silentLog('ai_codebase_search_tool', '遍历代码库条目执行关键词扫描', error, stack);
    } finally {
      stopwatch.stop();
    }

    return results;
  }

  bool _isIgnoredDirectoryName(String name) {
    return name.startsWith('.') ||
        _ignoredDirectoryNames.contains(name.toLowerCase());
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
