import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/mcp_loaded_tools_tracker.dart';
import 'package:openhand/features/mcp/service/tool_search_history_serializer.dart';

void main() {
  group('ToolSearchHistorySerializer.toCsv', () {
    test('empty entries still emits header row', () {
      final csv = ToolSearchHistorySerializer.toCsv(
        const <AiToolSearchLoadHistoryEntry>[],
      );
      expect(
        csv,
        'timestamp,source,query,added_count,total_deferred,added_names\n',
      );
    });

    test('escapes commas, double quotes, and newlines', () {
      final csv = ToolSearchHistorySerializer.toCsv(<AiToolSearchLoadHistoryEntry>[
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4, 1, 2, 3),
          query: 'has,comma "and quote"\nand newline',
          addedNames: const ['mcp__a__b', 'mcp__c__d'],
          totalDeferred: 7,
        ),
      ]);
      // Header + one row.
      final lines = csv.split('\n');
      expect(lines.first,
          'timestamp,source,query,added_count,total_deferred,added_names');
      // Quoted query field, doubled inner quotes, embedded newline kept as-is
      // inside the quoted cell.
      expect(
        csv,
        contains(
          '"has,comma ""and quote""\nand newline"',
        ),
      );
      // Names joined by `;` and unquoted (no special chars).
      expect(csv, contains('mcp__a__b;mcp__c__d'));
    });

    test('mixes AI and Hardness sources without dropping rows', () {
      final csv = ToolSearchHistorySerializer.toCsv(<AiToolSearchLoadHistoryEntry>[
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4),
          query: 'q1',
          addedNames: const ['mcp__a__b'],
          totalDeferred: 5,
        ),
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 5),
          query: 'q2',
          addedNames: const ['mcp__c__d'],
          totalDeferred: 5,
          source: AiToolSearchLoadSource.hardnessPhase,
        ),
      ]);
      // 1 header + 2 data rows + trailing newline => 4 lines after split.
      expect(csv.split('\n').length, 4);
      expect(csv, contains(',aiSession,'));
      expect(csv, contains(',hardnessPhase,'));
    });
  });

  group('ToolSearchHistorySerializer.toMarkdown', () {
    test('empty entries still emits header + separator rows', () {
      final md = ToolSearchHistorySerializer.toMarkdown(
        const <AiToolSearchLoadHistoryEntry>[],
      );
      expect(
        md,
        '| Timestamp | Source | Query | +Added / Deferred | Names |\n'
        '| --- | --- | --- | --- | --- |\n',
      );
    });

    test('escapes pipes and folds newlines so the table stays intact', () {
      final md =
          ToolSearchHistorySerializer.toMarkdown(<AiToolSearchLoadHistoryEntry>[
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4),
          query: 'q1|pipe\nwith newline',
          addedNames: const ['mcp__a|b__c'],
          totalDeferred: 3,
        ),
      ]);
      expect(md, contains(r'q1\|pipe with newline'));
      expect(md, contains(r'mcp__a\|b__c'));
      // Each row is on its own line; we expect exactly 1 header, 1 separator,
      // 1 data row, and trailing newline.
      expect(md.split('\n').length, 4);
    });

    test('renders +Added / Deferred summary column', () {
      final md =
          ToolSearchHistorySerializer.toMarkdown(<AiToolSearchLoadHistoryEntry>[
        AiToolSearchLoadHistoryEntry(
          timestamp: DateTime.utc(2026, 5, 4),
          query: 'q',
          addedNames: const ['a', 'b', 'c'],
          totalDeferred: 9,
        ),
      ]);
      expect(md, contains('+3 / 9'));
    });
  });

  group('ToolSearchHistorySerializer.toJson', () {
    test('empty entries emits version + empty entries array', () {
      final json = ToolSearchHistorySerializer.toJson(
        const <AiToolSearchLoadHistoryEntry>[],
      );
      expect(json, contains('"version": 1'));
      expect(json, contains('"entries": []'));
      expect(json, contains('"exported_at"'));
    });

    test('serializes a row with stable snake_case keys', () {
      final json = ToolSearchHistorySerializer.toJson(
        <AiToolSearchLoadHistoryEntry>[
          AiToolSearchLoadHistoryEntry(
            timestamp: DateTime.utc(2026, 5, 4, 1, 2, 3),
            query: 'has,comma "and quote"\nnl',
            addedNames: const ['mcp__a__b', 'mcp__c__d'],
            totalDeferred: 7,
          ),
        ],
      );
      // JSON is indent-2; check stable keys + that JSON-special chars survive.
      expect(json, contains('"timestamp": "2026-05-04T01:02:03.000Z"'));
      expect(json, contains('"query": "has,comma \\"and quote\\"\\nnl"'));
      expect(json, contains('"added_count": 2'));
      expect(json, contains('"total_deferred": 7'));
      expect(json, contains('"mcp__a__b"'));
      expect(json, contains('"mcp__c__d"'));
      expect(json, contains('"source": "aiSession"'));
    });

    test('preserves multi-source rows in original order', () {
      final json = ToolSearchHistorySerializer.toJson(
        <AiToolSearchLoadHistoryEntry>[
          AiToolSearchLoadHistoryEntry(
            timestamp: DateTime.utc(2026, 5, 4),
            query: 'q1',
            addedNames: const ['x'],
            totalDeferred: 3,
          ),
          AiToolSearchLoadHistoryEntry(
            timestamp: DateTime.utc(2026, 5, 5),
            query: 'q2',
            addedNames: const ['y'],
            totalDeferred: 4,
            source: AiToolSearchLoadSource.hardnessPhase,
          ),
        ],
      );
      // Source values appear in the same order as input entries.
      final firstAi = json.indexOf('"source": "aiSession"');
      final firstHardness = json.indexOf('"source": "hardnessPhase"');
      expect(firstAi >= 0 && firstHardness >= 0, isTrue);
      expect(firstAi, lessThan(firstHardness));
    });
  });
}
