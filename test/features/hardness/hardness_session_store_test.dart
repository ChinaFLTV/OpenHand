import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/hardness/data/hardness_session_store.dart';
import 'package:openhand/features/hardness/model/hardness_role_config.dart';
import 'package:openhand/features/hardness/model/hardness_session_config.dart';
import 'package:openhand/features/hardness/model/hardness_session_record.dart';
import 'package:openhand/features/hardness/service/hardness_orchestrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late HardnessSessionStore store;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE hardness_sessions (
        id        TEXT PRIMARY KEY,
        data_json TEXT NOT NULL
      )
    ''');
    store = HardnessSessionStore(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('save loads the current record and removes stale rows', () async {
    await _replaceRawSession(db, id: 'stale', dataJson: '{}');

    final record = _record(
      id: 'session-1',
      status: HardnessOrchestratorStatus.running,
    );

    await store.save(record);

    final rows = await db.query('hardness_sessions');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'session-1');

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.id, 'session-1');
    expect(loaded.title, 'Hardness Task');
    expect(loaded.config.task, 'Improve reliability');
    expect(loaded.status, HardnessOrchestratorStatus.running);
    expect(loaded.createdAt, record.createdAt);
    expect(loaded.updatedAt, record.updatedAt);
  });

  test('load treats malformed or non-object JSON as missing record', () async {
    for (final dataJson in <String>['not-json', '[]', '']) {
      await db.delete('hardness_sessions');
      await _replaceRawSession(db, id: 'bad', dataJson: dataJson);

      expect(await store.load(), isNull);
    }
  });

  test('clear removes the persisted record', () async {
    await store.save(_record(id: 'session-1'));

    await store.clear();

    expect(await store.load(), isNull);
    expect(await db.query('hardness_sessions'), isEmpty);
  });
}

HardnessSessionRecord _record({
  required String id,
  HardnessOrchestratorStatus status = HardnessOrchestratorStatus.idle,
}) {
  return HardnessSessionRecord(
    id: id,
    title: 'Hardness Task',
    config: _config(),
    statusValue: status.name,
    createdAt: DateTime.utc(2026, 6, 28, 1, 2, 3),
    updatedAt: DateTime.utc(2026, 6, 28, 4, 5, 6),
  );
}

HardnessSessionConfig _config() {
  return HardnessSessionConfig(
    task: 'Improve reliability',
    workingDirectory: '/tmp/openhand',
    persistenceDirectory: '/tmp/openhand/.hardness',
    profilerConfig: _role('profiler'),
    readerConfig: _role('reader'),
    plannerConfig: _role('planner'),
    implementerConfig: _role('implementer'),
    reviewerConfig: _role('reviewer'),
  );
}

HardnessRoleConfig _role(String name) {
  return HardnessRoleConfig(cliName: name, modelId: '$name-model');
}

Future<void> _replaceRawSession(
  Database db, {
  required String id,
  required String dataJson,
}) {
  return db.insert('hardness_sessions', <String, Object?>{
    'id': id,
    'data_json': dataJson,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
