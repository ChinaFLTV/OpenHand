import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late MemoryController controller;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await _createMemoryTable(db);
    var id = 0;
    var tick = 0;
    controller = await MemoryController.create(
      store: MemoryStore(database: db),
      idGenerator: () => 'memory-${++id}',
      clock: () => DateTime.utc(2026, 6, 28, 12, 0, tick++),
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('memory tool parses text and JSON tag lists', () async {
    final tool = AiMemoryTool(memoryControllerProvider: () => controller);

    final textTagsResult = await tool.run(<String, Object?>{
      'action': 'append',
      'content': 'remember alpha',
      'tags': ' Work, Profile ',
    });
    expect(textTagsResult.status, BashToolExecutionStatus.success);
    expect(controller.entries.single.tags, <String>['Work', 'Profile']);

    final jsonTagsResult = await tool.run(<String, Object?>{
      'action': 'append',
      'content': 'remember beta',
      'tags': '["Work", " extra "]',
    });
    expect(jsonTagsResult.status, BashToolExecutionStatus.success);
    expect(controller.entries.first.tags, <String>['Work', 'extra']);
    expect(controller.entries, hasLength(2));
  });
}

Future<void> _createMemoryTable(Database db) {
  return db.execute('''
    CREATE TABLE memories (
      id          TEXT PRIMARY KEY,
      type        TEXT NOT NULL DEFAULT 'user',
      created_at  TEXT NOT NULL,
      content     TEXT NOT NULL DEFAULT '',
      title       TEXT NOT NULL DEFAULT '',
      tags_json   TEXT NOT NULL DEFAULT '[]'
    )
  ''');
}
