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
}
