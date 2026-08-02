import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../model/ai_exposure_models.dart';

class AiExposurePreferencesStore {
  static const String _key = 'ai_exposure_preferences_v1';
  static const String _statisticsTable = 'ai_exposure_proxy_statistics';

  Database get _database => DatabaseService.instance.database;

  Future<AiExposurePreferences> load() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[_key],
        limit: 1,
      );
      if (rows.isEmpty) return AiExposurePreferences.defaults();
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) throw const FormatException('扫描服务设置格式无效。');
      final preferences = AiExposurePreferences.fromJson(
        aiExposureJsonMap(decoded),
      );
      if (preferences.proxyConfiguration.endpoints.isEmpty) return preferences;
      final statisticsRows = await _database.query(
        _statisticsTable,
        columns: const <String>['endpoint_url', 'statistics_json'],
      );
      final statisticsByUrl = <String, AiExposureProxyUsageStatistics>{};
      for (final row in statisticsRows) {
        final url = row['endpoint_url'] as String?;
        final encoded = row['statistics_json'] as String?;
        if (url == null || encoded == null) continue;
        try {
          statisticsByUrl[url] = AiExposureProxyUsageStatistics.fromJson(
            jsonDecode(encoded),
          );
        } catch (error, stack) {
          silentLog(
            'ai_exposure_preferences_store',
            '读取代理节点使用统计',
            error,
            stack,
          );
        }
      }
      final missingStatistics = <AiExposureProxyEndpoint>[];
      final endpoints = preferences.proxyConfiguration.endpoints
          .map((endpoint) {
            final stored = statisticsByUrl[endpoint.url];
            if (stored != null) return endpoint.copyWith(statistics: stored);
            if (endpoint.statistics.requests > 0 ||
                endpoint.statistics.successes > 0 ||
                endpoint.statistics.failures > 0 ||
                endpoint.statistics.timeouts > 0 ||
                endpoint.statistics.recentRequests.isNotEmpty) {
              missingStatistics.add(endpoint);
            }
            return endpoint;
          })
          .toList(growable: false);
      if (missingStatistics.isNotEmpty) {
        await saveProxyStatistics(missingStatistics);
      }
      if (statisticsByUrl.isEmpty) return preferences;
      return AiExposurePreferences(
        enabledSources: preferences.enabledSources,
        defaultConcurrency: preferences.defaultConcurrency,
        defaultValidationMode: preferences.defaultValidationMode,
        defaultGptAssisted: preferences.defaultGptAssisted,
        useBundledEngine: preferences.useBundledEngine,
        externalAddress: preferences.externalAddress,
        proxyConfiguration: preferences.proxyConfiguration.copyWith(
          endpoints: endpoints,
        ),
      );
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取扫描服务设置', error, stack);
      return AiExposurePreferences.defaults();
    }
  }

  Future<void> save(AiExposurePreferences preferences) async {
    await _database.transaction((transaction) async {
      await transaction.insert('app_settings', <String, Object?>{
        'key': _key,
        'value': jsonEncode(preferences.toJson(includeProxyStatistics: false)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final activeUrls = preferences.proxyConfiguration.endpoints
          .map((endpoint) => endpoint.url)
          .toSet();
      if (activeUrls.isEmpty) {
        await transaction.delete(_statisticsTable);
        return;
      }
      final rows = await transaction.query(
        _statisticsTable,
        columns: const <String>['endpoint_url'],
      );
      final storedUrls = rows
          .map((row) => row['endpoint_url'] as String?)
          .whereType<String>()
          .toSet();
      final batch = transaction.batch();
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      for (final endpoint in preferences.proxyConfiguration.endpoints) {
        if (storedUrls.contains(endpoint.url)) continue;
        batch.insert(_statisticsTable, <String, Object?>{
          'endpoint_url': endpoint.url,
          'statistics_json': jsonEncode(endpoint.statistics.toJson()),
          'updated_at': updatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final url in storedUrls.where((url) => !activeUrls.contains(url))) {
        batch.delete(
          _statisticsTable,
          where: 'endpoint_url = ?',
          whereArgs: <Object?>[url],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveProxyStatistics(
    List<AiExposureProxyEndpoint> endpoints,
  ) async {
    if (endpoints.isEmpty) return;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final batch = _database.batch();
    for (final endpoint in endpoints) {
      batch.insert(_statisticsTable, <String, Object?>{
        'endpoint_url': endpoint.url,
        'statistics_json': jsonEncode(endpoint.statistics.toJson()),
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
