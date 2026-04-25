import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-10 Codebase Search 工具 — 对标 Cursor 的 codebase_search 语义搜索。
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

    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) {
      return AiToolUtils.invalidResult('CodebaseSearch', 'query is required.');
    }

    final targetDirs = _parseTargetDirectories(args['target_directories']);
    final explanation = '${args['explanation'] ?? ''}'.trim();

    // Resolve search root
    final searchRoot = targetDirs.isNotEmpty
        ? AiToolUtils.resolvePath(targetDirs.first)
        : AiToolUtils.defaultWorkingDirectory();

    try {
      final results = await _multiSignalSearch(query, searchRoot);

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
      buffer.writeln('Found ${results.length} relevant chunk(s):\n');

      for (final result in results) {
        buffer.writeln('--- ${result.filePath}:${result.lineNumber} ---');
        buffer.writeln(result.context);
        buffer.writeln();
      }

      var output = buffer.toString().trimRight();
      if (output.length > AiToolUtils.maxSearchOutputCharacters) {
        output =
            '${output.substring(0, AiToolUtils.maxSearchOutputCharacters)}\n'
            '... (results truncated)';
      }

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

  List<String> _parseTargetDirectories(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  Future<List<_SearchResult>> _multiSignalSearch(
    String query,
    String searchRoot,
  ) async {
    // Extract meaningful keywords from the natural language query
    final keywords = _extractKeywords(query);
    if (keywords.isEmpty) return const <_SearchResult>[];

    final allResults = <String, _SearchResult>{};

    // Signal 1: Exact keyword grep (highest weight)
    // Try each keyword individually, then combined
    for (final keyword in keywords.take(5)) {
      final results = await _ripgrepSearch(searchRoot, keyword, maxResults: 10);
      for (final r in results) {
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
      final results = await _ripgrepSearch(searchRoot, pattern, maxResults: 15);
      for (final r in results) {
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
      final fileResults = await _findFilesByName(searchRoot, keyword);
      for (final filePath in fileResults) {
        // Read first 20 lines as context
        final file = File(filePath);
        if (!await file.exists()) continue;
        final lines = await file.readAsLines();
        final preview = lines.take(20).toList();
        final result = _SearchResult(
          filePath: filePath,
          lineNumber: 1,
          context: preview.join('\n'),
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

  List<String> _extractKeywords(String query) {
    // Remove common English stop words and extract meaningful terms
    const stopWords = <String>{
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
      'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'shall',
      'should', 'may', 'might', 'must', 'can', 'could', 'to', 'of', 'in',
      'for', 'on', 'with', 'at', 'by', 'from', 'as', 'into', 'through',
      'during', 'before', 'after', 'above', 'below', 'between', 'and', 'but',
      'or', 'not', 'no', 'nor', 'so', 'yet', 'both', 'either', 'neither',
      'each', 'every', 'all', 'any', 'few', 'more', 'most', 'other', 'some',
      'such', 'than', 'too', 'very', 'just', 'about', 'also', 'then',
      'this', 'that', 'these', 'those', 'it', 'its', 'i', 'we', 'you',
      'they', 'he', 'she', 'me', 'us', 'him', 'her', 'them', 'my', 'our',
      'your', 'their', 'what', 'which', 'who', 'whom', 'when', 'where',
      'why', 'how', 'if', 'up', 'out', 'off', 'over', 'under', 'again',
      // Common Chinese stop words
      '的', '了', '在', '是', '我', '有', '和', '就', '不', '人', '都', '一',
      '个', '上', '也', '很', '到', '说', '要', '去', '你', '会', '着',
      '没有', '看', '好', '自己', '这', '他', '她', '它', '们', '吗', '吧',
      '被', '让', '给', '把', '那', '些', '么', '什么', '怎么', '哪', '谁',
    };

    // Split on non-alphanumeric characters (keeping CJK, underscores)
    final words = query
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.length >= 2 && !stopWords.contains(w.toLowerCase()))
        .toList(growable: false);

    // Also extract camelCase/snake_case fragments
    final fragments = <String>[];
    for (final word in words) {
      fragments.add(word);
      // Split camelCase: "handleUserAuth" → ["handle", "User", "Auth"]
      final camelParts = word
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (m) => '${m.group(1)} ${m.group(2)}',
          )
          .split(' ')
          .where((p) => p.length >= 3)
          .toList();
      if (camelParts.length > 1) fragments.addAll(camelParts);
      // Split snake_case
      if (word.contains('_')) {
        fragments.addAll(word.split('_').where((p) => p.length >= 3));
      }
    }

    // Deduplicate while preserving order
    final seen = <String>{};
    return fragments.where((f) => seen.add(f.toLowerCase())).toList();
  }

  // 2026-04-13: 修复 rg 命令路径解析问题，使用共享工具方法
  Future<List<_SearchResult>> _ripgrepSearch(
    String searchRoot,
    String pattern, {
    int contextLines = 3,
    int maxResults = 20,
    bool caseInsensitive = true,
  }) async {
    // 先检查 ripgrep 是否可用
    final rgPath = await AiToolUtils.resolveRipgrepPath();
    if (rgPath == null) {
      // ripgrep 不可用，静默返回空结果（CodebaseSearch 有多个信号源）
      return const <_SearchResult>[];
    }

    final args = <String>[
      '--json',
      '-C', '$contextLines',
      if (caseInsensitive) '-i',
      '--max-count', '5', // max matches per file
      '--type-add',
      'code:*.{dart,ts,tsx,js,jsx,py,go,rs,java,kt,swift,c,cpp,h,hpp,cs,rb,php,yaml,yml,json,toml,md}',
      '--type', 'code',
      pattern,
      '.', // 在工作目录中搜索
    ];

    // 使用共享工具方法执行进程
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

    return _parseRipgrepJson(stdout, maxResults);
  }

  List<_SearchResult> _parseRipgrepJson(String jsonOutput, int maxResults) {
    final results = <String, _SearchResult>{};
    final lines = jsonOutput.split('\n');

    String? currentFile;
    final contextBuffer = StringBuffer();
    int? matchLine;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = _safeJsonDecode(line);
        if (decoded is! Map) continue;
        final Map<String, dynamic> entry = Map<String, dynamic>.from(decoded);
        final type = entry['type'] as String? ?? '';

        if (type == 'match') {
          final data =
              entry['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final path =
              (data['path'] as Map<String, dynamic>?)?['text'] as String? ?? '';
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

  Object? _safeJsonDecode(String input) {
    try {
      return _jsonCodec.decode(input);
    } catch (_) {
      return null;
    }
  }

  static const _jsonCodec = JsonCodec();

  Future<List<String>> _findFilesByName(
    String searchRoot,
    String keyword,
  ) async {
    // Use glob-style file search
    final lowerKeyword = keyword.toLowerCase();
    final results = <String>[];

    try {
      final dir = Directory(searchRoot);
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final basename = p.basename(entity.path).toLowerCase();
          // Skip hidden files, build artifacts, node_modules
          if (entity.path.contains('/.') ||
              entity.path.contains('/build/') ||
              entity.path.contains('/node_modules/') ||
              entity.path.contains('/.dart_tool/')) {
            continue;
          }
          if (basename.contains(lowerKeyword)) {
            results.add(entity.path);
            if (results.length >= 5) break;
          }
        }
      }
    } catch (_) {}

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
