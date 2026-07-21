import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('数据库升级会补齐缓存有效输入 Token', () async {
    sqfliteFfiInit();
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-cache-input-migration-test-',
    );
    final databasePath = '${temporaryDirectory.path}/openhand.db';
    final oldDatabase = await databaseFactoryFfiNoIsolate.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE ai_usage_records (
              id TEXT PRIMARY KEY,
              protocol TEXT NOT NULL DEFAULT '',
              prompt_tokens INTEGER NOT NULL DEFAULT 0,
              cache_read_tokens INTEGER NOT NULL DEFAULT 0,
              cache_creation_tokens INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.insert('ai_usage_records', <String, Object?>{
            'id': 'openai',
            'protocol': 'openai',
            'prompt_tokens': 100,
            'cache_read_tokens': 80,
            'cache_creation_tokens': 10,
          });
          await database.insert('ai_usage_records', <String, Object?>{
            'id': 'claude',
            'protocol': 'claude',
            'prompt_tokens': 10,
            'cache_read_tokens': 80,
            'cache_creation_tokens': 10,
          });
          await database.insert('ai_usage_records', <String, Object?>{
            'id': 'invalid',
            'protocol': 'claude',
            'prompt_tokens': -1,
            'cache_read_tokens': -2,
            'cache_creation_tokens': -3,
          });
        },
      ),
    );
    await oldDatabase.close();

    try {
      final service = await DatabaseService.initialize(
        databasePath: databasePath,
        useNoIsolateFactory: true,
      );
      final columns = await service.database.rawQuery(
        'PRAGMA table_info(ai_usage_records)',
      );
      expect(
        columns.map((column) => column['name']),
        contains('cache_input_tokens'),
      );

      final rows = await service.database.query(
        'ai_usage_records',
        columns: <String>['id', 'cache_input_tokens'],
        orderBy: 'id ASC',
      );
      expect(rows, <Map<String, Object?>>[
        <String, Object?>{'id': 'claude', 'cache_input_tokens': 100},
        <String, Object?>{'id': 'invalid', 'cache_input_tokens': 0},
        <String, Object?>{'id': 'openai', 'cache_input_tokens': 100},
      ]);
    } finally {
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      await temporaryDirectory.delete(recursive: true);
    }
  });
}
