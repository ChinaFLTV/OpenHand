import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/mcp_keyword_index.dart';

void main() {
  group('McpToolRef.fromJson', () {
    test('normalizes scalar fields without throwing', () {
      final ref = McpToolRef.fromJson(<String, Object?>{
        's': 1,
        'i': true,
        'n': 'tool',
      });

      expect(ref.serverName, '1');
      expect(ref.toolId, 'true');
      expect(ref.toolName, 'tool');
    });
  });

  group('McpKeywordIndex.fromJson', () {
    test('normalizes dirty persisted buckets and counters', () {
      final builtAt = DateTime.utc(2026, 2, 3, 4, 5, 6);
      final index = McpKeywordIndex.fromJson(<String, Object?>{
        'totalTools': '2',
        'totalServers': -1,
        'builtAt': builtAt.toIso8601String(),
        'durationMs': '15',
        'byName': <Object?, Object?>{
          'alpha': <Object?>[
            <Object?, Object?>{'s': 'srv', 'i': 7, 'n': 'tool'},
            'ignored',
          ],
        },
        'byDescription': 'ignored',
        'bySearchHint': <String, Object?>{
          'hint': <Object?>[
            <String, Object?>{'s': 'srv', 'i': 'id', 'n': 'name'},
          ],
        },
      });

      expect(index, isNotNull);
      expect(index!.totalTools, 2);
      expect(index.totalServers, 0);
      expect(index.durationMs, 15);
      expect(index.builtAt, builtAt);
      expect(index.byDescription, isEmpty);
      expect(index.byName['alpha'], hasLength(1));
      expect(index.byName['alpha']!.single.toolId, '7');
      expect(index.bySearchHint['hint']!.single.toolName, 'name');
    });

    test('falls back for invalid dates and non-integral counters', () {
      final index = McpKeywordIndex.fromJson(<String, Object?>{
        'totalTools': '2.5',
        'totalServers': double.infinity,
        'builtAt': 'bad',
        'durationMs': -3,
      });

      expect(index, isNotNull);
      expect(index!.totalTools, 0);
      expect(index.totalServers, 0);
      expect(index.durationMs, 0);
      expect(
        index.builtAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });

  group('McpKeywordIndexService.loadFromDisk', () {
    test('loads dirty object roots and rejects non-object roots', () async {
      final dir = await Directory.systemTemp.createTemp('mcp_keyword_index_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final file = File('${dir.path}/keyword_index.json');
      final service = McpKeywordIndexService(storageDir: dir);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'totalTools': '1',
          'byName': <String, Object?>{
            'read': <Object?>[
              <String, Object?>{'s': 'fs', 'i': 'read', 'n': 'Read'},
            ],
          },
        }),
      );

      final loaded = await service.loadFromDisk();
      expect(loaded, isNotNull);
      expect(loaded!.totalTools, 1);
      expect(loaded.byName['read']!.single.serverName, 'fs');

      await file.writeAsString('[]');
      expect(await service.loadFromDisk(), isNull);
    });
  });
}
