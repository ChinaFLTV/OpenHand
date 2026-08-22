import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../model/ai_model_proxy_models.dart';

class AiModelProxyStore {
  static const String _key = 'ai_model_proxy_settings_v1';

  Database get _database => DatabaseService.instance.database;

  Future<AiModelProxySettings> load() async {
    try {
      final rows = await _database.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[_key],
        limit: 1,
      );
      if (rows.isEmpty) return const AiModelProxySettings();
      final decoded = jsonDecode('${rows.first['value']}');
      return AiModelProxySettings.fromJson(decoded);
    } catch (error, stack) {
      silentLog('ai_model_proxy_store', '读取模型服务设置', error, stack);
      return const AiModelProxySettings();
    }
  }

  Future<void> save(AiModelProxySettings settings) async {
    await _database.insert('app_settings', <String, Object?>{
      'key': _key,
      'value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
