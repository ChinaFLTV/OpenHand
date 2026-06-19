import 'dart:convert';

import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// Built-in **ToolSearch** tool - analogous to Claude Code's `ToolSearchTool`.
///
/// When MCP or built-in tool lazy loading is active, the session controller
/// strips deferred tool schemas out of the per-turn catalog and leaves compact
/// names plus summaries in this tool's description. The model invokes
/// `ToolSearch` to fetch full JSON Schema for the tools it needs. Once a
/// schema appears in the result, the controller promotes that tool into the
/// session's exposed catalog for the next model request.
///
/// Query forms (mirrors Claude Code's three modes):
///   - `select:Read,Edit,Grep` — direct multi-select by exact name.
///   - `notebook jupyter`       — keyword search ranked by name/description.
///   - `+slack send`            — `+TERM` makes that term required.
///
/// The tool is invisible when there is nothing to defer, so weak models don't
/// see a useless extra entry.
class AiToolSearchTool extends AiTool {
  AiToolSearchTool();

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.toolSearch;

  /// Names of MCP tools currently deferred — set by [AiSessionController]
  /// before catalog resolution every turn. Empty ⇒ tool should be hidden.
  List<String> deferredToolNames = const <String>[];

  /// Full definitions of deferred runtime tools, keyed by name. Used to
  /// assemble the `<functions>` payload returned to the model.
  Map<String, AiToolDefinition> deferredToolDefinitions =
      const <String, AiToolDefinition>{};

  void setDeferredToolSnapshot(
    Map<String, AiToolDefinition> definitionsByName,
  ) {
    deferredToolDefinitions = Map<String, AiToolDefinition>.unmodifiable(
      definitionsByName,
    );
    deferredToolNames = List<String>.unmodifiable(definitionsByName.keys);
  }

  void clearDeferredToolSnapshot() {
    deferredToolNames = const <String>[];
    deferredToolDefinitions = const <String, AiToolDefinition>{};
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final stopwatch = Stopwatch()..start();
    final args = context.decodedArguments;
    final query = '${args['query'] ?? ''}'.trim();
    final maxResultsRaw = args['max_results'];
    final maxResults = maxResultsRaw is num
        ? maxResultsRaw.toInt().clamp(1, 50)
        : 5;
    if (query.isEmpty) {
      return AiToolUtils.invalidResult(
        'ToolSearch',
        'ToolSearch requires a non-empty `query` parameter. '
            'Use `select:Name1,Name2` for direct selection or keywords '
            '(e.g. `slack send`, `+github issues list`) for fuzzy search.',
      );
    }
    final catalogDefinitions = context.catalog
        .find('ToolSearch')
        ?.toolSearchDeferredToolDefinitions;
    final definitionsByName =
        catalogDefinitions == null || catalogDefinitions.isEmpty
        ? deferredToolDefinitions
        : catalogDefinitions;
    final deferred = definitionsByName.isEmpty
        ? deferredToolNames
        : definitionsByName.keys.toList(growable: false);
    if (deferred.isEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'ToolSearch query=$query',
        output:
            'No deferred runtime tools are available. Every callable tool is '
            'already loaded directly into this turn\'s catalog.',
        durationMs: stopwatch.elapsedMilliseconds,
        metadata: const <String, Object?>{
          'tool_search_loaded_names': <String>[],
          'tool_search_total_deferred': 0,
        },
      );
    }
    final List<String> matches = _runSearch(
      query: query,
      maxResults: maxResults,
      deferred: deferred,
      deferredDefinitions: definitionsByName,
    );
    final functions = _renderFunctionsBlock(matches, definitionsByName);
    final lines = <String>[];
    if (matches.isEmpty) {
      lines
        ..add(
          'ToolSearch matched 0 of ${deferred.length} deferred runtime tool(s).',
        )
        ..add('query: $query')
        ..add('')
        ..add(
          'No deferred tool matched. Try different keywords, or list a name '
          'explicitly via `select:NAME`.',
        );
    } else {
      lines
        ..add(
          'ToolSearch loaded ${matches.length} of ${deferred.length} '
          'deferred runtime tool(s).',
        )
        ..add('query: $query')
        ..add('loaded: ${matches.join(', ')}')
        ..add('')
        ..add(
          'The full JSONSchema of the matched tools is rendered below inside '
          'a <functions> block. Each tool is now callable by its exact name '
          'from the next model request onward.',
        )
        ..add('')
        ..add(functions);
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'ToolSearch query=$query',
      output: lines.join('\n'),
      durationMs: stopwatch.elapsedMilliseconds,
      metadata: <String, Object?>{
        'tool_search_loaded_names': matches,
        'tool_search_total_deferred': deferred.length,
        'tool_search_query': query,
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Search core (parallels Claude Code src/tools/ToolSearchTool/...)
  // ──────────────────────────────────────────────────────────────────────

  List<String> _runSearch({
    required String query,
    required int maxResults,
    required List<String> deferred,
    required Map<String, AiToolDefinition> deferredDefinitions,
  }) {
    final lower = query.toLowerCase();

    // 1) `select:NAME[,NAME...]` direct multi-select.
    if (lower.startsWith('select:')) {
      final requested = query
          .substring('select:'.length)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final byLower = <String, String>{
        for (final n in deferred) n.toLowerCase(): n,
      };
      final found = <String>[];
      for (final r in requested) {
        final hit = byLower[r.toLowerCase()];
        if (hit != null && !found.contains(hit)) found.add(hit);
        if (found.length >= maxResults) break;
      }
      return found;
    }

    // 2) Exact bare-name fast path.
    for (final n in deferred) {
      if (n.toLowerCase() == lower) return <String>[n];
    }

    // 3) `mcp__server` prefix shortcut.
    if (lower.startsWith('mcp__') && lower.length > 5) {
      final hits = deferred
          .where((n) => n.toLowerCase().startsWith(lower))
          .take(maxResults)
          .toList(growable: false);
      if (hits.isNotEmpty) return hits;
    }

    // 4) Keyword ranking with `+required` term support.
    final terms = lower.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final required = <String>[];
    final optional = <String>[];
    for (final t in terms) {
      if (t.startsWith('+') && t.length > 1) {
        required.add(t.substring(1));
      } else {
        optional.add(t);
      }
    }
    final allTerms = required.isEmpty
        ? optional
        : <String>[...required, ...optional];
    if (allTerms.isEmpty) return const <String>[];

    final scored = <_ScoredToolMatch>[];
    for (final name in deferred) {
      final parsed = _parseToolName(name);
      final descLower = (deferredDefinitions[name]?.description ?? '')
          .toLowerCase();
      // Required-term gate.
      var passesRequired = true;
      for (final r in required) {
        final hit =
            parsed.parts.contains(r) ||
            parsed.parts.any((p) => p.contains(r)) ||
            _matchesWord(descLower, r);
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
        if (_matchesWord(descLower, term)) score += 2;
      }
      if (score > 0) scored.add(_ScoredToolMatch(name, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(maxResults).map((s) => s.name).toList(growable: false);
  }

  static bool _matchesWord(String haystack, String term) {
    if (haystack.isEmpty || term.isEmpty) return false;
    final escaped = RegExp.escape(term);
    return RegExp('\\b$escaped\\b').hasMatch(haystack);
  }

  static _ParsedToolName _parseToolName(String name) {
    if (name.startsWith('mcp__')) {
      final stripped = name.substring(5).toLowerCase();
      final parts = stripped
          .split('__')
          .expand((p) => p.split('_'))
          .where((p) => p.isNotEmpty)
          .toList(growable: false);
      return _ParsedToolName(
        parts: parts,
        full: stripped.replaceAll('__', ' ').replaceAll('_', ' '),
        isMcp: true,
      );
    }
    final parts = name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        )
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    return _ParsedToolName(parts: parts, full: parts.join(' '), isMcp: false);
  }

  String _renderFunctionsBlock(
    List<String> names,
    Map<String, AiToolDefinition> definitionsByName,
  ) {
    if (names.isEmpty) return '';
    final buffer = StringBuffer('<functions>\n');
    for (final n in names) {
      final def = definitionsByName[n];
      if (def == null) continue;
      final entry = jsonEncode(<String, Object?>{
        'name': def.name,
        'description': def.description,
        'parameters': def.parameters,
      });
      buffer
        ..write('<function>')
        ..write(entry)
        ..writeln('</function>');
    }
    buffer.write('</functions>');
    return buffer.toString();
  }
}

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
