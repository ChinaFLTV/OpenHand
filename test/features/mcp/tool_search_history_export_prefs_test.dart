import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/tool_search_history_export_prefs.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseService service;

  setUpAll(() async {
    service = await DatabaseService.initialize(
      databasePath: inMemoryDatabasePath,
      useNoIsolateFactory: true,
    );
  });

  tearDownAll(() async {
    await service.close();
  });

  setUp(() async {
    // Reset the KV row before each test so they're independent.
    await ToolSearchHistoryExportPrefs.clear();
  });

  group('ToolSearchHistoryExportPrefs', () {
    test('readLastDir returns null when nothing was written', () async {
      expect(await ToolSearchHistoryExportPrefs.readLastDir(), isNull);
    });

    test('writeLastDir then readLastDir round-trips a path', () async {
      await ToolSearchHistoryExportPrefs.writeLastDir('/tmp/exports');
      expect(
        await ToolSearchHistoryExportPrefs.readLastDir(),
        '/tmp/exports',
      );
    });

    test('writeLastDir overwrites previous value', () async {
      await ToolSearchHistoryExportPrefs.writeLastDir('/old');
      await ToolSearchHistoryExportPrefs.writeLastDir('/new');
      expect(await ToolSearchHistoryExportPrefs.readLastDir(), '/new');
    });

    test('writeLastDir trims surrounding whitespace', () async {
      await ToolSearchHistoryExportPrefs.writeLastDir('   /trimmed   ');
      expect(await ToolSearchHistoryExportPrefs.readLastDir(), '/trimmed');
    });

    test('writeLastDir with empty string is treated as clear', () async {
      await ToolSearchHistoryExportPrefs.writeLastDir('/something');
      await ToolSearchHistoryExportPrefs.writeLastDir('   ');
      expect(await ToolSearchHistoryExportPrefs.readLastDir(), isNull);
    });

    test('clear removes the persisted directory', () async {
      await ToolSearchHistoryExportPrefs.writeLastDir('/anywhere');
      expect(await ToolSearchHistoryExportPrefs.readLastDir(), '/anywhere');
      await ToolSearchHistoryExportPrefs.clear();
      expect(await ToolSearchHistoryExportPrefs.readLastDir(), isNull);
    });

    test('does not collide with the main settings KV row', () async {
      await ToolSearchHistoryExportPrefs.writeLastDir('/var/exports');
      // Smoke-check: writing a sibling KV row shouldn't disturb our key.
      final db = service.database;
      await db.insert(
        'app_settings',
        <String, Object?>{
          'key': 'app_settings_json',
          'value': '{"version":2}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(
        await ToolSearchHistoryExportPrefs.readLastDir(),
        '/var/exports',
      );
    });
  });
}
