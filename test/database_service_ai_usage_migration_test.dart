import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('数据库升级会为 AI 请求追踪补齐诊断字段', () async {
    sqfliteFfiInit();
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-ai-usage-migration-test-',
    );
    final databasePath = '${temporaryDirectory.path}/openhand.db';
    final oldDatabase = await databaseFactoryFfiNoIsolate.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (database, _) => database.execute('''
          CREATE TABLE ai_usage_records (
            id TEXT PRIMARY KEY,
            error_type TEXT
          )
        '''),
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
      final names = columns.map((column) => column['name']).toSet();
      expect(
        names,
        containsAll(<String>{
          'error_message',
          'http_status_code',
          'timeout_ms',
          'timeout_phase',
        }),
      );
    } finally {
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      await temporaryDirectory.delete(recursive: true);
    }
  });
}
