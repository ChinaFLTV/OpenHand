import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../model/knowledge_base_settings.dart';

class KnowledgeBaseSettingsStore {
  KnowledgeBaseSettingsStore({Database? database})
    : _db = database ?? DatabaseService.instance.database;

  static const String settingsKey = 'knowledge_base_settings_json';

  final Database _db;

  Future<KnowledgeBaseSettings> load() async {
    final rows = await _db.query(
      'app_settings',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[settingsKey],
      limit: 1,
    );
    if (rows.isEmpty) return const KnowledgeBaseSettings();
    final value = '${rows.first['value'] ?? ''}';
    return KnowledgeBaseSettings.decode(value);
  }

  Future<void> save(KnowledgeBaseSettings settings) async {
    await _db.insert('app_settings', <String, Object?>{
      'key': settingsKey,
      'value': settings.encode(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
