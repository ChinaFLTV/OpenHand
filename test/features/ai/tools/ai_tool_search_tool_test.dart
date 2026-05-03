// 2026-05-04 — Unit tests for AiToolSearchTool's matching/scoring core.
// Locks in select: direct selection, mcp__server prefix shortcut, keyword
// scoring (part-match 10/12 vs substring 5/6 vs full-form 3 vs description
// word boundary +2), and `+required` term gating.

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/tools/ai_tool_search_tool.dart';

AiToolDefinition _def(String name, {String description = ''}) {
  return AiToolDefinition(
    name: name,
    description: description,
    parameters: const <String, Object?>{'type': 'object'},
  );
}

AiToolSearchTool _tool({
  required List<String> names,
  Map<String, AiToolDefinition>? defs,
}) {
  final tool = AiToolSearchTool();
  tool.deferredToolNames = List<String>.unmodifiable(names);
  tool.deferredToolDefinitions =
      defs ?? <String, AiToolDefinition>{for (final n in names) n: _def(n)};
  return tool;
}

void main() {
  group('select: direct selection', () {
    test('returns names in the order requested, deduped, case-insensitive',
        () {
      final t = _tool(
        names: const ['mcp__alpha__one', 'mcp__beta__two', 'mcp__gamma__three'],
      );
      final hits = t.debugRunSearch(
        query: 'select:MCP__BETA__two, mcp__alpha__one, mcp__beta__two',
      );
      expect(hits, ['mcp__beta__two', 'mcp__alpha__one']);
    });

    test('drops names that are not present in deferred set', () {
      final t = _tool(names: const ['mcp__alpha__one']);
      final hits = t.debugRunSearch(query: 'select:mcp__nope__missing');
      expect(hits, isEmpty);
    });
  });

  group('mcp__server prefix shortcut', () {
    test('returns all tools sharing the prefix, capped by maxResults', () {
      final t = _tool(
        names: const [
          'mcp__alpha__one',
          'mcp__alpha__two',
          'mcp__alpha__three',
          'mcp__beta__one',
        ],
      );
      final hits = t.debugRunSearch(query: 'mcp__alpha', maxResults: 2);
      expect(hits, hasLength(2));
      expect(hits.every((n) => n.startsWith('mcp__alpha__')), isTrue);
    });
  });

  group('keyword ranking', () {
    test('part-match scores higher than substring than full-form', () {
      final t = _tool(
        names: const [
          // 'logs' is an EXACT part → MCP gets +12.
          'mcp__svr__logs',
          // 'logs' is only a SUBSTRING of the part 'fetchlogs' → +6.
          'mcp__svr__fetchlogs',
          // 'logs' nowhere in name parts; description hit only.
          'mcp__svr__unrelated',
        ],
        defs: {
          'mcp__svr__logs': _def('mcp__svr__logs', description: 'tail logs'),
          'mcp__svr__fetchlogs':
              _def('mcp__svr__fetchlogs', description: 'fetch'),
          'mcp__svr__unrelated':
              _def('mcp__svr__unrelated', description: 'logs from k8s pods'),
        },
      );
      final hits = t.debugRunSearch(query: 'logs');
      expect(hits.first, 'mcp__svr__logs',
          reason: 'exact part-match must win');
      expect(hits, contains('mcp__svr__fetchlogs'));
      expect(hits, contains('mcp__svr__unrelated'));
      // Sanity: substring beats description-only.
      expect(hits.indexOf('mcp__svr__fetchlogs'),
          lessThan(hits.indexOf('mcp__svr__unrelated')));
    });

    test('description word-boundary contributes +2 only for whole words', () {
      final t = _tool(
        names: const ['mcp__a__one', 'mcp__a__two'],
        defs: {
          // Word "logs" is present as a standalone word.
          'mcp__a__one': _def('mcp__a__one', description: 'pod logs reader'),
          // Substring inside "blogs" — must NOT be counted.
          'mcp__a__two': _def('mcp__a__two', description: 'tech blogs feed'),
        },
      );
      final hits = t.debugRunSearch(query: 'logs');
      expect(hits, ['mcp__a__one']);
    });
  });

  group('+required term gating', () {
    test('drops candidates that do not match the required term', () {
      final t = _tool(
        names: const [
          'mcp__github__list_issues',
          'mcp__slack__send_message',
          'mcp__github__get_repo',
        ],
        defs: {
          'mcp__github__list_issues': _def('mcp__github__list_issues',
              description: 'list issues from a github repo'),
          'mcp__slack__send_message':
              _def('mcp__slack__send_message', description: 'send slack msg'),
          'mcp__github__get_repo':
              _def('mcp__github__get_repo', description: 'get a repo'),
        },
      );
      // `+github` requires that token; `issues` is optional/scoring.
      final hits = t.debugRunSearch(query: '+github issues');
      expect(hits, isNotEmpty);
      expect(hits.every((n) => n.contains('github')), isTrue);
      expect(hits.first, 'mcp__github__list_issues',
          reason: 'github + issues both hit → highest score');
    });
  });

  group('edge cases', () {
    test('empty deferred set returns empty for any keyword', () {
      final t = _tool(names: const <String>[]);
      expect(t.debugRunSearch(query: 'anything'), isEmpty);
    });

    test('exact bare-name fast path returns only that one tool', () {
      final t = _tool(
        names: const ['mcp__svr__alpha', 'mcp__svr__beta'],
      );
      final hits = t.debugRunSearch(query: 'mcp__svr__alpha');
      expect(hits, ['mcp__svr__alpha']);
    });
  });
}
