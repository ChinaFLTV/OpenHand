import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late MemoryStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memory_store_test_');
    final dbPath = p.join(tempDir.path, 'openhand.db');
    await DatabaseService.initialize(databasePath: dbPath);
    store = MemoryStore();
  });

  tearDown(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MemoryStore', () {
    test('loadUserProfile returns null when no profile exists', () async {
      final profile = await store.loadUserProfile();
      expect(profile, isNull);
    });

    test('upsertUserProfile creates a profile with user_profile type',
        () async {
      final created = await store.upsertUserProfile(content: 'A');
      expect(created.type, UserMemoryEntry.userProfileType);
      expect(created.content, 'A');

      final loaded = await store.loadUserProfile();
      expect(loaded, isNotNull);
      expect(loaded!.type, UserMemoryEntry.userProfileType);
      expect(loaded.content, 'A');
    });

    test('upsertUserProfile twice keeps exactly one profile row with latest content',
        () async {
      await store.upsertUserProfile(content: 'first');
      await store.upsertUserProfile(content: 'second');

      final result = await store.load();
      final profiles = result.entries
          .where((e) => e.type == UserMemoryEntry.userProfileType)
          .toList();
      expect(profiles.length, 1);
      expect(profiles.single.content, 'second');
    });

    test('upsertUserProfile with whitespace-only content throws ArgumentError',
        () async {
      expect(
        () => store.upsertUserProfile(content: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('loadByTag returns only entries that carry the tag', () async {
      await store.insertEntry(
        UserMemoryEntry(
          id: 'm-with-tag',
          type: UserMemoryEntry.userType,
          createdAt: DateTime.utc(2026, 4, 25),
          content: 'tagged entry',
          tags: const [UserMemoryEntry.autoLearnedTag],
        ),
      );
      await store.insertEntry(
        UserMemoryEntry(
          id: 'm-without-tag',
          type: UserMemoryEntry.userType,
          createdAt: DateTime.utc(2026, 4, 25),
          content: 'untagged entry',
          tags: const ['manual'],
        ),
      );

      final matches = await store.loadByTag(UserMemoryEntry.autoLearnedTag);
      expect(matches.length, 1);
      expect(matches.single.id, 'm-with-tag');
    });

    test('loadByTag is case-insensitive', () async {
      await store.insertEntry(
        UserMemoryEntry(
          id: 'm-auto',
          type: UserMemoryEntry.userType,
          createdAt: DateTime.utc(2026, 4, 25),
          content: 'entry with lowercase auto tag',
          tags: const ['auto'],
        ),
      );

      final matches = await store.loadByTag('AUTO');
      expect(matches.length, 1);
      expect(matches.single.id, 'm-auto');
    });

    test('profile rows survive load() round-trip with type preserved',
        () async {
      await store.upsertUserProfile(
        content: 'a profile',
        tags: const ['profile-tag'],
      );

      final result = await store.load();
      final profile = result.entries.firstWhere(
        (e) => e.id == UserMemoryEntry.userProfileEntryId,
      );
      expect(profile.type, UserMemoryEntry.userProfileType);
      expect(profile.content, 'a profile');
      expect(profile.tags, contains('profile-tag'));
      expect(result.issue, isNull);
    });
  });
}
