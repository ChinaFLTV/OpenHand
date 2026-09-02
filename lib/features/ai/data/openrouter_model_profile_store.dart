import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/ai_model_catalog.dart';
import '../model/ai_model_config.dart';
import '../model/ai_one_million_context_policy.dart';

const int _maxOpenRouterProfileCount = 10000;
const int _maxOpenRouterProfileBatchCount = 5000;
const int _maxOpenRouterModelIdCharacters = 1024;
const int _maxOpenRouterProfileBytes = 512 * kBytesPerKiB;
const int _maxOpenRouterProfileTotalBytes = 64 * kBytesPerMiB;

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
    final database = DatabaseService.instance.database;
    await _validateStorageScale(database);
    final rows = await database.query(
      'openrouter_model_profiles',
      columns: const <String>['model_id', 'profile_json'],
      limit: _maxOpenRouterProfileCount + 1,
    );
    if (rows.length > _maxOpenRouterProfileCount) {
      throw const FormatException('OpenRouter 模型档案数量超过安全上限。');
    }
    final loaded = <String, AiModelProfile>{};
    for (final row in rows) {
      final modelId = row['model_id'];
      final encoded = row['profile_json'];
      if (modelId is! String ||
          modelId.isEmpty ||
          modelId.trim() != modelId ||
          modelId.length > _maxOpenRouterModelIdCharacters ||
          encoded is! String ||
          utf8ByteLength(encoded) > _maxOpenRouterProfileBytes) {
        throw const FormatException('OpenRouter 模型档案字段无效。');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw FormatException('OpenRouter 模型档案必须为对象：$modelId');
      }
      final source = stringKeyedMapFromValue(decoded);
      final profile = AiModelProfile.fromJson(source);
      validateCanonicalJsonSubset(
        source,
        profile.toJson(),
        path: 'openrouter_model_profiles.$modelId',
        maxDepth: 16,
        maxContainerItems: 4096,
        maxTotalNodes: 32768,
      );
      final normalizedId = modelId.toLowerCase();
      if (loaded.containsKey(normalizedId)) {
        throw FormatException('OpenRouter 模型档案 ID 重复：$modelId');
      }
      loaded[normalizedId] = profile;
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
    await ensureLoaded();
    final batchEntries = entries
        .take(_maxOpenRouterProfileBatchCount + 1)
        .toList(growable: false);
    if (batchEntries.isEmpty) return;
    if (batchEntries.length > _maxOpenRouterProfileBatchCount) {
      throw const FormatException('OpenRouter 模型档案批量写入数量超过安全上限。');
    }
    final rows = <({String modelId, String profileJson})>[];
    final modelIds = <String>{};
    var totalBytes = 0;
    for (final entry in batchEntries) {
      final modelId = entry.key.trim();
      final normalizedId = modelId.toLowerCase();
      if (modelId.isEmpty ||
          modelId != entry.key ||
          modelId.length > _maxOpenRouterModelIdCharacters ||
          !modelIds.add(normalizedId)) {
        throw const FormatException('OpenRouter 模型档案 ID 无效或重复。');
      }
      final payload = entry.value.toJson();
      validateCanonicalJsonSubset(
        payload,
        payload,
        path: 'openrouter_model_profiles.$modelId',
        maxDepth: 16,
        maxContainerItems: 4096,
        maxTotalNodes: 32768,
      );
      final profileJson = jsonEncode(payload);
      final payloadBytes =
          utf8ByteLength(modelId) + utf8ByteLength(profileJson);
      totalBytes += payloadBytes;
      if (payloadBytes > _maxOpenRouterProfileBytes ||
          totalBytes > _maxOpenRouterProfileTotalBytes) {
        throw const FormatException('OpenRouter 模型档案载荷超过安全上限。');
      }
      rows.add((modelId: modelId, profileJson: profileJson));
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final database = DatabaseService.instance.database;
    await database.transaction((transaction) async {
      final batch = transaction.batch();
      for (final row in rows) {
        batch.insert('openrouter_model_profiles', <String, Object?>{
          'model_id': row.modelId,
          'profile_json': row.profileJson,
          'updated_at': updatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      await _validateStorageScale(transaction);
    });
    final updates = <String, AiModelProfile>{
      for (final entry in batchEntries)
        entry.key.trim().toLowerCase(): entry.value,
    };
    _profiles.addAll(updates);
    AiModelCatalog.registerExternalProfiles(updates);
  }

  Future<void> _validateStorageScale(DatabaseExecutor database) async {
    final rows = await database.rawQuery('''
      SELECT COUNT(*) AS entry_count,
             COALESCE(MAX(LENGTH(CAST(model_id AS BLOB)) +
                          LENGTH(CAST(profile_json AS BLOB))), 0)
               AS max_entry_bytes,
             COALESCE(SUM(LENGTH(CAST(model_id AS BLOB)) +
                          LENGTH(CAST(profile_json AS BLOB))), 0)
               AS total_bytes
      FROM openrouter_model_profiles
      ''');
    final row = rows.firstOrNull;
    final entryCount = optionalIntegralIntFromValue(row?['entry_count']);
    final maxEntryBytes = optionalIntegralIntFromValue(row?['max_entry_bytes']);
    final totalBytes = optionalIntegralIntFromValue(row?['total_bytes']);
    if (entryCount == null || maxEntryBytes == null || totalBytes == null) {
      throw const FormatException('OpenRouter 模型档案统计无效。');
    }
    if (entryCount > _maxOpenRouterProfileCount ||
        maxEntryBytes > _maxOpenRouterProfileBytes ||
        totalBytes > _maxOpenRouterProfileTotalBytes) {
      throw const FormatException('OpenRouter 模型档案存储规模超过安全上限。');
    }
  }
}
