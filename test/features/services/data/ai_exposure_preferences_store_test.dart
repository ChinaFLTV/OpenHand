import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/data/ai_exposure_preferences_store.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('代理统计独立持久化并随节点删除清理', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'openhand-proxy-statistics-',
    );
    final databasePath = p.join(directory.path, 'openhand.db');
    addTearDown(() async {
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final endpoint =
        AiExposureProxyEndpoint.parse(
          'http://user:password@127.0.0.1:8080',
        ).copyWith(
          statistics: const AiExposureProxyUsageStatistics(
            requests: 9,
            successes: 6,
            failures: 2,
            timeouts: 1,
            totalResponseTimeMs: 900,
          ),
        );
    final defaults = AiExposurePreferences.defaults();
    final preferences = AiExposurePreferences(
      enabledSources: defaults.enabledSources,
      defaultConcurrency: defaults.defaultConcurrency,
      defaultValidationMode: defaults.defaultValidationMode,
      defaultGptAssisted: defaults.defaultGptAssisted,
      useBundledEngine: defaults.useBundledEngine,
      externalAddress: defaults.externalAddress,
      proxyConfiguration: defaults.proxyConfiguration.copyWith(
        endpoints: <AiExposureProxyEndpoint>[endpoint],
      ),
    );

    final legacyDatabase = await databaseFactoryFfiNoIsolate.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (database, _) => database.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        '''),
      ),
    );
    await legacyDatabase.insert('app_settings', <String, Object?>{
      'key': 'ai_exposure_preferences_v1',
      'value': jsonEncode(preferences.toJson()),
    });
    await legacyDatabase.close();
    await DatabaseService.initialize(
      databasePath: databasePath,
      useNoIsolateFactory: true,
    );

    final store = AiExposurePreferencesStore();
    final migrated = await store.load();
    expect(migrated.proxyConfiguration.endpoints.single.statistics.requests, 9);
    expect(
      await DatabaseService.instance.database.query(
        'ai_exposure_proxy_statistics',
      ),
      hasLength(1),
    );
    await store.save(preferences);

    final settings = await DatabaseService.instance.database.query(
      'app_settings',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>['ai_exposure_preferences_v1'],
    );
    final encodedPreferences = jsonDecode(settings.single['value'] as String);
    final encodedEndpoint =
        (encodedPreferences['proxy']['endpoints'] as List).single as Map;
    expect(encodedEndpoint.containsKey('statistics'), isFalse);

    final loaded = await store.load();
    expect(loaded.proxyConfiguration.endpoints.single.statistics.requests, 9);
    expect(loaded.proxyConfiguration.endpoints.single.statistics.successes, 6);

    await store.save(
      AiExposurePreferences(
        enabledSources: defaults.enabledSources,
        defaultConcurrency: defaults.defaultConcurrency,
        defaultValidationMode: defaults.defaultValidationMode,
        defaultGptAssisted: defaults.defaultGptAssisted,
        useBundledEngine: defaults.useBundledEngine,
        externalAddress: defaults.externalAddress,
        proxyConfiguration: defaults.proxyConfiguration,
      ),
    );
    final statisticsRows = await DatabaseService.instance.database.query(
      'ai_exposure_proxy_statistics',
    );
    expect(statisticsRows, isEmpty);
  });
}
