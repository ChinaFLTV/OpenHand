import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../model/ai_model_catalog.dart';
import '../model/ai_model_config.dart';
import '../model/ai_one_million_context_policy.dart';

/// OpenRouter 模型档案的本地缓存。缓存独立于应用设置，避免设置 JSON 过大。
class OpenRouterModelProfileStore {
  OpenRouterModelProfileStore._();

  static final OpenRouterModelProfileStore instance =
      OpenRouterModelProfileStore._();

  final Map<String, AiModelProfile> _profiles = <String, AiModelProfile>{};
  Future<void>? _loading;
  bool _loaded = false;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final pending = _loading;
    if (pending != null) return pending;
    late final Future<void> loading;
    loading = _load().whenComplete(() {
      if (identical(_loading, loading)) _loading = null;
    });
    _loading = loading;
    return loading;
  }

  AiModelProfile? profileFor(String modelId) {
    final normalizedId = modelId.trim().toLowerCase();
    return _profiles[normalizedId] ??
        _profiles[AiOneMillionContextPolicy.stripModelIdSuffix(normalizedId)];
  }

  Future<void> _load() async {
    final rows = await DatabaseService.instance.database.query(
      'openrouter_model_profiles',
      columns: const <String>['model_id', 'profile_json'],
    );
    final loaded = <String, AiModelProfile>{};
    for (final row in rows) {
      final modelId = row['model_id'];
      final encoded = row['profile_json'];
      if (modelId is! String || encoded is! String) continue;
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) continue;
        final profile = AiModelProfile.fromJson(
          Map<String, Object?>.from(decoded),
        );
        loaded[modelId.toLowerCase()] = profile;
      } catch (_) {
        continue;
      }
    }
    _profiles
      ..clear()
      ..addAll(loaded);
    AiModelCatalog.registerExternalProfiles(loaded, replace: true);
    _loaded = true;
  }

  Future<void> upsertBatch(
    Iterable<MapEntry<String, AiModelProfile>> entries,
  ) async {
    final pending = _loading;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // 预热失败时仍尝试写入本次同步结果。
      }
    }
    final batchEntries = entries
        .where((entry) => entry.key.trim().isNotEmpty)
        .toList(growable: false);
    if (batchEntries.isEmpty) return;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final database = DatabaseService.instance.database;
    await database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final entry in batchEntries) {
        final modelId = entry.key.trim();
        batch.insert(
          'openrouter_model_profiles',
          <String, Object?>{
            'model_id': modelId,
            'profile_json': jsonEncode(entry.value.toJson()),
            'updated_at': updatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    final updates = <String, AiModelProfile>{
      for (final entry in batchEntries)
        entry.key.trim().toLowerCase(): entry.value,
    };
    _profiles.addAll(updates);
    AiModelCatalog.registerExternalProfiles(updates);
  }
}
