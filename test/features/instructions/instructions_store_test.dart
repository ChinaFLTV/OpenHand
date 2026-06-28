import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/instructions/data/instructions_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late InstructionsStore store;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE user_instructions (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL DEFAULT '',
        body            TEXT NOT NULL DEFAULT '',
        description     TEXT NOT NULL DEFAULT '',
        version         TEXT NOT NULL DEFAULT '1.0',
        apply_to        TEXT NOT NULL DEFAULT '',
        notes_json      TEXT NOT NULL DEFAULT '[]',
        task_types_json TEXT NOT NULL DEFAULT '[]',
        keywords_json   TEXT NOT NULL DEFAULT '[]',
        enabled         INTEGER NOT NULL DEFAULT 1,
        sort_order      INTEGER NOT NULL DEFAULT 0,
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
      )
    ''');
    store = InstructionsStore(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('loadAll normalizes dirty persisted instruction rows', () async {
    await db.insert('user_instructions', <String, Object?>{
      'id': 'instruction-1',
      'name': '  Build     Guardrails  ',
      'body': '  Keep responses concise.  ',
      'description': '  Line one\nline two  ',
      'version': '',
      'apply_to': '  coding\nreview  ',
      'notes_json': '[" note ", null, "", "another note"]',
      'task_types_json': '["Coding", "coding", null, ""]',
      'keywords_json': '["Dart", "dart", " Flutter "]',
      'enabled': 'yes',
      'sort_order': '7',
      'created_at': '2026-06-28T00:00:00Z',
      'updated_at': '',
    });

    final entries = await store.loadAll();

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.id, 'instruction-1');
    expect(entry.name, 'Build Guardrails');
    expect(entry.body, 'Keep responses concise.');
    expect(entry.description, 'Line one line two');
    expect(entry.version, '1.0');
    expect(entry.applyTo, 'coding review');
    expect(entry.notes, <String>['note', 'another note']);
    expect(entry.taskTypes, <String>['Coding']);
    expect(entry.keywords, <String>['Dart', 'Flutter']);
    expect(entry.enabled, isTrue);
    expect(entry.sortOrder, 7);
    expect(entry.updatedAt, entry.createdAt);
  });

  test('loadAll keeps recoverable rows with malformed scalar fields', () async {
    await db.insert('user_instructions', <String, Object?>{
      'id': 'instruction-2',
      'name': 'Fallback',
      'body': 'Body',
      'description': '',
      'version': '2.0',
      'apply_to': '',
      'notes_json': 'not-json',
      'task_types_json': '{"bad": true}',
      'keywords_json': '[]',
      'enabled': 'disabled',
      'sort_order': 'bad',
      'created_at': '2026-06-28T00:00:00Z',
      'updated_at': '2026-06-28T00:01:00Z',
    });

    final entries = await store.loadAll();

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.enabled, isFalse);
    expect(entry.sortOrder, 0);
    expect(entry.notes, isEmpty);
    expect(entry.taskTypes, isEmpty);
    expect(entry.keywords, isEmpty);
  });
}
