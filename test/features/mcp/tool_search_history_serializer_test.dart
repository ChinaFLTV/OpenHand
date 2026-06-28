import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/mcp/service/tool_search_history_serializer.dart';

void main() {
  group('ToolSearchHistorySerializer.fromJson', () {
    test('normalizes dirty export rows', () {
      final timestamp = DateTime.utc(2026, 3, 4, 5, 6, 7);
      final entries = ToolSearchHistorySerializer.fromJson(
        jsonEncode(<String, Object?>{
          'version': '1',
          'entries': <Object?>[
            <Object?, Object?>{
              'timestamp': timestamp.toIso8601String(),
              'source': 'unknown',
              'query': 42,
              'added_names': <Object?>[' Read ', 7, '', null, 'Write'],
              'total_deferred': '3',
            },
            <String, Object?>{
              'timestamp': timestamp
                  .add(const Duration(minutes: 1))
                  .toIso8601String(),
              'source': AiToolSearchLoadSource.hardnessPhase.name,
              'query': ' tools ',
              'added_names': 'Glob, Grep',
              'total_deferred': -1,
            },
          ],
        }),
      );

      expect(entries, hasLength(2));
      expect(entries.first.timestamp, timestamp);
      expect(entries.first.source, AiToolSearchLoadSource.aiSession);
      expect(entries.first.query, isEmpty);
      expect(entries.first.addedNames, <String>['Read', '7', 'Write']);
      expect(entries.first.totalDeferred, 3);
      expect(entries.last.source, AiToolSearchLoadSource.hardnessPhase);
      expect(entries.last.query, ' tools ');
      expect(entries.last.addedNames, <String>['Glob', 'Grep']);
      expect(entries.last.totalDeferred, 0);
    });

    test('rejects malformed roots and entries explicitly', () {
      expect(
        () => ToolSearchHistorySerializer.fromJson('[]'),
        throwsFormatException,
      );
      expect(
        () => ToolSearchHistorySerializer.fromJson(
          jsonEncode(<String, Object?>{'version': 2, 'entries': <Object?>[]}),
        ),
        throwsFormatException,
      );
      expect(
        () => ToolSearchHistorySerializer.fromJson(
          jsonEncode(<String, Object?>{'version': 1, 'entries': 'bad'}),
        ),
        throwsFormatException,
      );
      expect(
        () => ToolSearchHistorySerializer.fromJson(
          jsonEncode(<String, Object?>{
            'version': 1,
            'entries': <Object?>['bad'],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => ToolSearchHistorySerializer.fromJson(
          jsonEncode(<String, Object?>{
            'version': 1,
            'entries': <Object?>[
              <String, Object?>{'timestamp': 'bad'},
            ],
          }),
        ),
        throwsFormatException,
      );
    });

    test('round-trips exported history json', () {
      final entry = AiToolSearchLoadHistoryEntry(
        timestamp: DateTime.utc(2026),
        query: 'read files',
        addedNames: const <String>['Read', 'Glob'],
        totalDeferred: 8,
      );

      final parsed = ToolSearchHistorySerializer.fromJson(
        ToolSearchHistorySerializer.toJson(<AiToolSearchLoadHistoryEntry>[
          entry,
        ]),
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.timestamp, entry.timestamp);
      expect(parsed.single.query, entry.query);
      expect(parsed.single.addedNames, entry.addedNames);
      expect(parsed.single.totalDeferred, entry.totalDeferred);
      expect(parsed.single.source, entry.source);
    });
  });
}
