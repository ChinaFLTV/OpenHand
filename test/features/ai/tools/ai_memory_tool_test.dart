import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_memory_tool.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late MemoryController memoryController;
  late AiMemoryTool tool;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_memory_tool_test_');
    final dbPath = p.join(tempDir.path, 'openhand.db');
    await DatabaseService.initialize(databasePath: dbPath);
    memoryController = await MemoryController.create();
    tool = AiMemoryTool(memoryControllerProvider: () => memoryController);
  });

  tearDown(() async {
    memoryController.dispose();
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AiMemoryTool', () {
    test('list on empty store returns "No memory entries."', () async {
      final result = await tool.run(<String, Object?>{'action': 'list'});
      expect(result.stderr, isEmpty);
      expect(result.stdout, contains('No memory entries'));
    });

    test('append creates a new user memory entry', () async {
      final result = await tool.run(<String, Object?>{
        'action': 'append',
        'content': 'user hates dark mode',
        'tags': <String>['自主学习'],
      });
      expect(result.stdout, contains('Memory appended'));
      expect(memoryController.entries.length, 1);
      final entry = memoryController.entries.single;
      expect(entry.content, 'user hates dark mode');
      expect(entry.tags, contains('自主学习'));
      expect(entry.type, UserMemoryEntry.userType);
    });

    test(
      'upsert_profile creates then replaces the single user_profile',
      () async {
        final first = await tool.run(<String, Object?>{
          'action': 'upsert_profile',
          'content': 'prefers Flutter + Rust',
        });
        expect(first.stdout, contains('user_profile upserted'));
        expect(memoryController.userProfile, isNotNull);
        expect(memoryController.userProfile!.content, 'prefers Flutter + Rust');

        final second = await tool.run(<String, Object?>{
          'action': 'upsert_profile',
          'content': 'prefers Flutter + Rust; prefers CLI tools',
        });
        expect(second.stdout, contains('user_profile upserted'));
        final profiles = memoryController.entries
            .where((e) => e.type == UserMemoryEntry.userProfileType)
            .toList();
        expect(profiles.length, 1);
        expect(profiles.single.content, contains('CLI tools'));
      },
    );

    test('list filters by tag (case-insensitive)', () async {
      await tool.run(<String, Object?>{
        'action': 'append',
        'content': 'cares about performance',
        'tags': <String>['自主学习'],
      });
      await tool.run(<String, Object?>{
        'action': 'append',
        'content': 'uses macOS M1',
        'tags': <String>['profile'],
      });

      final filtered = await tool.run(<String, Object?>{
        'action': 'list',
        'tag': '自主学习',
      });
      expect(filtered.stdout, contains('cares about performance'));
      expect(filtered.stdout, isNot(contains('uses macOS M1')));
    });

    test('update by id replaces content + tags', () async {
      await tool.run(<String, Object?>{
        'action': 'append',
        'content': 'old content',
      });
      final id = memoryController.entries.single.id;

      final result = await tool.run(<String, Object?>{
        'action': 'update',
        'id': id,
        'content': 'new content',
        'tags': <String>['自主学习'],
      });
      expect(result.stdout, contains('Memory updated'));
      final updated = memoryController.entries.singleWhere((e) => e.id == id);
      expect(updated.content, 'new content');
      expect(updated.tags, contains('自主学习'));
    });

    test('delete by id removes the entry', () async {
      await tool.run(<String, Object?>{
        'action': 'append',
        'content': 'temporary',
      });
      final id = memoryController.entries.single.id;

      final result = await tool.run(<String, Object?>{
        'action': 'delete',
        'id': id,
      });
      expect(result.stdout, contains('Memory deleted'));
      expect(memoryController.entries, isEmpty);
    });

    test('missing action returns invalid result', () async {
      final result = await tool.run(<String, Object?>{});
      expect(result.stderr, isNotEmpty);
    });

    test('unknown action returns invalid result', () async {
      final result = await tool.run(<String, Object?>{'action': 'nope'});
      expect(result.stderr, isNotEmpty);
    });

    test('append with empty content is rejected', () async {
      final result = await tool.run(<String, Object?>{
        'action': 'append',
        'content': '   ',
      });
      expect(result.stderr, isNotEmpty);
      expect(memoryController.entries, isEmpty);
    });

    test('update with unknown id is rejected', () async {
      final result = await tool.run(<String, Object?>{
        'action': 'update',
        'id': 'does-not-exist',
        'content': 'something',
      });
      expect(result.stderr, isNotEmpty);
    });

    test(
      'returns invalid result when memoryControllerProvider yields null',
      () async {
        final detached = AiMemoryTool(memoryControllerProvider: () => null);
        final result = await detached.run(<String, Object?>{'action': 'list'});
        expect(result.stderr, contains('Memory controller is not available'));
      },
    );
  });
}
