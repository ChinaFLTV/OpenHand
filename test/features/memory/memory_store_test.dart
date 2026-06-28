import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late MemoryStore store;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE memories (
        id          TEXT PRIMARY KEY,
        type        TEXT NOT NULL DEFAULT 'user',
        created_at  TEXT NOT NULL,
        content     TEXT NOT NULL DEFAULT '',
        title       TEXT NOT NULL DEFAULT '',
        tags_json   TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    store = MemoryStore(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'load sanitizes dirty rows without dropping recoverable memories',
    () async {
      await _insertMemory(db, <String, Object?>{
        'id': 'memory-1',
        'type': 'unknown',
        'created_at': '2026-06-28T00:00:00Z',
        'content': '  keep this  ',
        'title': '  Title\nLine  ',
        'tags_json': '["Tag", " tag ", null, "", "Second"]',
      });
      await _insertMemory(db, <String, Object?>{
        'id': 'memory-2',
        'type': UserMemoryEntry.userType,
        'created_at': '2026-06-29T00:00:00Z',
        'content': 'keep invalid tags row',
        'title': '',
        'tags_json': '{"bad": true}',
      });
      await _insertMemory(db, <String, Object?>{
        'id': '',
        'type': UserMemoryEntry.userType,
        'created_at': '2026-06-30T00:00:00Z',
        'content': 'skip empty id',
        'title': '',
        'tags_json': '[]',
      });
      await _insertMemory(db, <String, Object?>{
        'id': 'bad-date',
        'type': UserMemoryEntry.userType,
        'created_at': 'not-a-date',
        'content': 'skip invalid date',
        'title': '',
        'tags_json': '[]',
      });
      await _insertMemory(db, <String, Object?>{
        'id': 'blank-content',
        'type': UserMemoryEntry.userType,
        'created_at': '2026-06-27T00:00:00Z',
        'content': '   ',
        'title': '',
        'tags_json': '[]',
      });

      final result = await store.load();

      expect(
        result.issue?.kind,
        MemoryPersistenceIssueKind.sanitizedInvalidContent,
      );
      expect(result.entries.map((entry) => entry.id), <String>[
        'memory-2',
        'memory-1',
      ]);
      expect(result.entries.first.tags, isEmpty);

      final recovered = result.entries.last;
      expect(recovered.type, UserMemoryEntry.userType);
      expect(recovered.content, 'keep this');
      expect(recovered.title, 'Title Line');
      expect(recovered.tags, <String>['Tag', 'Second']);
    },
  );

  test(
    'save round trips entries and supports case-insensitive tag lookup',
    () async {
      final older = UserMemoryEntry(
        id: 'older',
        type: UserMemoryEntry.userType,
        createdAt: DateTime.utc(2026, 6, 27),
        content: 'older memory',
        tags: const <String>['Work'],
        title: 'Older',
      );
      final newer = UserMemoryEntry(
        id: 'newer',
        type: UserMemoryEntry.userProfileType,
        createdAt: DateTime.utc(2026, 6, 28),
        content: 'newer memory',
        tags: const <String>['work', 'Profile'],
        title: 'Newer',
      );

      await store.save(<UserMemoryEntry>[older, newer]);

      final loaded = await store.load();
      expect(loaded.issue, isNull);
      expect(loaded.entries.map((entry) => entry.id), <String>[
        'newer',
        'older',
      ]);

      final tagged = await store.loadByTag('WORK');
      expect(tagged.map((entry) => entry.id), <String>['newer', 'older']);
    },
  );
}

Future<void> _insertMemory(Database db, Map<String, Object?> row) {
  return db.insert('memories', row);
}
