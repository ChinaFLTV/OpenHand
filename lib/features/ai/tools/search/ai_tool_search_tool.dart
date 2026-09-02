import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 内置 ToolSearch 固定网关。
///
/// 懒加载启用后，完整工具 Schema 从原生目录折叠到此工具的旁路数据中。
/// 模型先查询目标 Schema，再通过同一入口代理执行，避免轮次间改写缓存前缀。
/// 支持精确 `select:`、关键词和 `+必含词` 三种查询方式。
class AiToolSearchTool extends AiTool {
  static const int _defaultMaxResults = 5;
  static const int _minMaxResults = 1;
  static const int _maxMaxResults = 50;
  static const int _maxQueryTerms = 32;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.toolSearch;

  /// 当前延迟加载的 MCP 工具名；空列表表示应隐藏本工具。
  List<String> deferredToolNames = const <String>[];

  /// 按名称索引的延迟工具完整定义，用于组装结构化结果。
  Map<String, AiToolDefinition> deferredToolDefinitions =
      const <String, AiToolDefinition>{};

  void setDeferredToolSnapshot(
    Map<String, AiToolDefinition> definitionsByName,
  ) {
    final entries = definitionsByName.entries.toList(growable: false)
      ..sort((left, right) => _compareToolNames(left.key, right.key));
    deferredToolDefinitions = Map<String, AiToolDefinition>.unmodifiable(
      Map<String, AiToolDefinition>.fromEntries(entries),
    );
    deferredToolNames = List<String>.unmodifiable(
      entries.map((entry) => entry.key),
    );
  }

  void clearDeferredToolSnapshot() {
    deferredToolNames = const <String>[];
    deferredToolDefinitions = const <String, AiToolDefinition>{};
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final stopwatch = Stopwatch()..start();
    final args = context.decodedArguments;
    final query = AiToolUtils.readString(args['query']);
    final toolName = AiToolUtils.readString(args['tool_name']);
    final maxResults = AiToolUtils.readClampedInt(
      args['max_results'],
      fallback: _defaultMaxResults,
      min: _minMaxResults,
      max: _maxMaxResults,
    );
    if (query.isEmpty) {
      return AiToolUtils.invalidResult(
        'ToolSearch',
        toolName.isEmpty
            ? 'ToolSearch 需要非空 `query`，或同时提供 `tool_name` 与 `arguments`。'
            : 'ToolSearch 网关调用未被运行时分发，请重试。',
      );
    }
    if (query.length > kAiToolSearchMaxQueryCharacters) {
      return AiToolUtils.invalidResult(
        'ToolSearch',
        'query 超过 $kAiToolSearchMaxQueryCharacters 个字符上限。',
      );
    }
    if (!query.toLowerCase().startsWith('select:') &&
        query
                .split(kInlineWhitespacePattern)
                .where((term) => term.isNotEmpty)
                .take(_maxQueryTerms + 1)
                .length >
            _maxQueryTerms) {
      return AiToolUtils.invalidResult(
        'ToolSearch',
        'query 超过 $_maxQueryTerms 个词项上限。',
      );
    }
    final catalogTool = context.catalog.find('ToolSearch');
    final definitionsByName = catalogTool == null
        ? deferredToolDefinitions
        : catalogTool.toolSearchDeferredToolDefinitions;
    final deferred =
        (definitionsByName.isEmpty && catalogTool == null
                ? deferredToolNames
                : definitionsByName.keys.toList(growable: false))
            .toList(growable: false)
          ..sort(_compareToolNames);
    final directMcpDefinitions = <String, AiToolDefinition>{
      for (final entry in context.catalog.toolsByName.entries)
        if (entry.value.source == AiRuntimeToolSource.mcp)
          entry.key: entry.value.definition,
    };
    if (deferred.isEmpty) {
      final directMatches = _runSearch(
        query: query,
        maxResults: maxResults,
        deferred: directMcpDefinitions.keys.toList(growable: false),
        deferredDefinitions: directMcpDefinitions,
      );
      final payload = _buildResultPayload(
        query: query,
        matches: directMatches,
        deferredTotal: 0,
        functions: _buildFunctionDefinitions(
          directMatches,
          directMcpDefinitions,
        ),
        message: directMatches.isEmpty
            ? '没有延迟加载的运行时工具，所有可调用工具均已加载。'
            : '以下 MCP 工具已直接加载；立即按 Schema 直接调用精确工具名，不要再次调用 ToolSearch。',
        direct: true,
      );
      return AiToolUtils.simpleSuccessResult(
        command: 'ToolSearch query=$query',
        output: _encodePayload(payload),
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: <String, Object?>{
          'tool_search_loaded_names': const <String>[],
          'tool_search_total_deferred': 0,
          if (directMatches.isNotEmpty)
            'tool_search_direct_names': directMatches,
        },
      );
    }
    final List<String> matches = _runSearch(
      query: query,
      maxResults: maxResults,
      deferred: deferred,
      deferredDefinitions: definitionsByName,
    );
    if (matches.isEmpty && directMcpDefinitions.isNotEmpty) {
      final directMatches = _runSearch(
        query: query,
        maxResults: maxResults,
        deferred: directMcpDefinitions.keys.toList(growable: false),
        deferredDefinitions: directMcpDefinitions,
      );
      if (directMatches.isNotEmpty) {
        final payload = _buildResultPayload(
          query: query,
          matches: directMatches,
          deferredTotal: deferred.length,
          functions: _buildFunctionDefinitions(
            directMatches,
            directMcpDefinitions,
          ),
          message: '以下 MCP 工具已直接加载；立即按 Schema 直接调用精确工具名，不要再次调用 ToolSearch。',
          direct: true,
        );
        return AiToolUtils.simpleSuccessResult(
          command: 'ToolSearch query=$query',
          output: _encodePayload(payload),
          durationMs: stopwatch.elapsedMilliseconds,
          metadata: <String, Object?>{
            'tool_search_loaded_names': const <String>[],
            'tool_search_total_deferred': deferred.length,
            'tool_search_query': query,
            'tool_search_direct_names': directMatches,
          },
        );
      }
    }
    final functions = _buildFunctionDefinitions(matches, definitionsByName);
    final payload = _buildResultPayload(
      query: query,
      matches: matches,
      deferredTotal: deferred.length,
      functions: functions,
      message: matches.isEmpty
          ? '没有匹配的延迟工具，请更换关键词或使用精确名称。'
          : '请再次调用 ToolSearch，将 tool_name 设为精确匹配名，并按其 Schema 提供 arguments。',
    );
    return AiToolUtils.simpleSuccessResult(
      command: 'ToolSearch query=$query',
      output: _encodePayload(payload),
      durationMs: stopwatch.elapsedMilliseconds,
      metadata: <String, Object?>{
        'tool_search_loaded_names': matches,
        'tool_search_total_deferred': deferred.length,
        'tool_search_query': query,
      },
    );
  }

  List<String> _runSearch({
    required String query,
    required int maxResults,
    required List<String> deferred,
    required Map<String, AiToolDefinition> deferredDefinitions,
  }) {
    final lower = query.toLowerCase();

    // 1. `select:NAME[,NAME...]` 精确多选。
    if (lower.startsWith('select:')) {
      final requested = splitTrimmedNonEmpty(query.substring('select:'.length));
      final byLower = <String, String>{
        for (final n in deferred) n.toLowerCase(): n,
      };
      final found = <String>[];
      for (final r in requested) {
        final hit = byLower[r.toLowerCase()];
        if (hit != null && !found.contains(hit)) found.add(hit);
        if (found.length >= maxResults) break;
      }
      found.sort(_compareToolNames);
      return found;
    }

    // 2. 裸名称精确匹配。
    for (final n in deferred) {
      if (n.toLowerCase() == lower) return <String>[n];
    }

    // 3. `mcp__server` 前缀匹配。
    if (lower.startsWith('mcp__') && lower.length > 5) {
      final hits = deferred
          .where((n) => n.toLowerCase().startsWith(lower))
          .take(maxResults)
          .toList(growable: false);
      if (hits.isNotEmpty) return hits;
    }

    // 4. 关键词排序，支持 `+必含词`。
    final terms = lower
        .split(kInlineWhitespacePattern)
        .where((term) => term.isNotEmpty);
    final required = <String>[];
    final optional = <String>[];
    for (final t in terms) {
      if (t.startsWith('+') && t.length > 1) {
        required.add(t.substring(1));
      } else {
        optional.add(t);
      }
    }
    final allTerms =
        (required.isEmpty ? optional : <String>[...required, ...optional])
          ..retainWhere(<String>{}.add);
    if (allTerms.isEmpty) return const <String>[];
    final descriptionPatterns = <String, RegExp>{
      for (final term in allTerms)
        term: RegExp(
          _asciiWordTermPattern.hasMatch(term)
              ? '\\b${RegExp.escape(term)}\\b'
              : RegExp.escape(term),
        ),
    };

    final scored = <_ScoredToolMatch>[];
    for (final name in deferred) {
      final parsed = _parseToolName(name);
      final descLower = (deferredDefinitions[name]?.description ?? '')
          .toLowerCase();
      var passesRequired = true;
      for (final r in required) {
        final hit =
            parsed.parts.contains(r) ||
            parsed.parts.any((p) => p.contains(r)) ||
            descriptionPatterns[r]!.hasMatch(descLower);
        if (!hit) {
          passesRequired = false;
          break;
        }
      }
      if (!passesRequired) continue;

      var score = 0;
      for (final term in allTerms) {
        if (parsed.parts.contains(term)) {
          score += parsed.isMcp ? 12 : 10;
        } else if (parsed.parts.any((p) => p.contains(term))) {
          score += parsed.isMcp ? 6 : 5;
        } else if (parsed.full.contains(term) && score == 0) {
          score += 3;
        }
        if (descriptionPatterns[term]!.hasMatch(descLower)) score += 2;
      }
      if (score > 0) scored.add(_ScoredToolMatch(name, score));
    }
    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return _compareToolNames(a.name, b.name);
    });
    return scored.take(maxResults).map((s) => s.name).toList(growable: false);
  }

  static int _compareToolNames(String left, String right) {
    return compareToolNamesForAiRequest(left, right);
  }

  static _ParsedToolName _parseToolName(String name) {
    if (name.startsWith('mcp__')) {
      final stripped = name.substring(5).toLowerCase();
      final parts = stripped
          .split('__')
          .expand((p) => p.split(RegExp(r'[_-]+')))
          .where((p) => p.isNotEmpty)
          .toList(growable: false);
      return _ParsedToolName(
        parts: parts,
        full: stripped.replaceAll('__', ' ').replaceAll(RegExp(r'[_-]+'), ' '),
        isMcp: true,
      );
    }
    final parts = name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        )
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .toLowerCase()
        .split(kInlineWhitespacePattern)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    return _ParsedToolName(parts: parts, full: parts.join(' '), isMcp: false);
  }

  Map<String, Object?> _buildResultPayload({
    required String query,
    required List<String> matches,
    required int deferredTotal,
    required List<Map<String, Object?>> functions,
    required String message,
    bool direct = false,
  }) {
    return <String, Object?>{
      'tool': 'ToolSearch',
      'status': 'success',
      'query': query,
      'matched_count': matches.length,
      'deferred_total': deferredTotal,
      'loaded_tools': matches,
      if (direct) 'direct_tools': matches,
      'message': message,
      'functions': functions,
    };
  }

  String _encodePayload(Map<String, Object?> payload) {
    return prettyPrintJson(payload);
  }

  List<Map<String, Object?>> _buildFunctionDefinitions(
    List<String> names,
    Map<String, AiToolDefinition> definitionsByName,
  ) {
    if (names.isEmpty) return const <Map<String, Object?>>[];
    final functions = <Map<String, Object?>>[];
    for (final n in names) {
      final def = definitionsByName[n];
      if (def == null) continue;
      final stableDef = stableToolDefinitionForAiRequest(def);
      functions.add(<String, Object?>{
        'name': stableDef.name,
        'description': stableDef.description,
        'parameters': stableDef.parameters,
      });
    }
    return functions;
  }
}

final RegExp _asciiWordTermPattern = RegExp(r'^[a-z0-9_]+$');

class _ScoredToolMatch {
  const _ScoredToolMatch(this.name, this.score);
  final String name;
  final int score;
}

class _ParsedToolName {
  const _ParsedToolName({
    required this.parts,
    required this.full,
    required this.isMcp,
  });
  final List<String> parts;
  final String full;
  final bool isMcp;
}
