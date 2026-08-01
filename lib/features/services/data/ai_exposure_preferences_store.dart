import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../model/ai_exposure_models.dart';

class AiExposurePreferencesStore {
  static const String _key = 'ai_exposure_preferences_v1';

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
      return AiExposurePreferences.fromJson(aiExposureJsonMap(decoded));
    } catch (error, stack) {
      silentLog('ai_exposure_preferences_store', '读取扫描服务设置', error, stack);
      return AiExposurePreferences.defaults();
    }
  }

  Future<void> save(AiExposurePreferences preferences) => _database.insert(
    'app_settings',
    <String, Object?>{'key': _key, 'value': jsonEncode(preferences.toJson())},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
