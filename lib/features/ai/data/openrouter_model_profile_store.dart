import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../model/ai_model_catalog.dart';
import '../model/ai_model_config.dart';

const int _maxOpenRouterProfileCount = 10000;
const int _maxOpenRouterProfileBatchCount = 5000;
const int _maxOpenRouterModelIdCharacters = 1024;
const int _maxOpenRouterProfileBytes = 512 * kBytesPerKiB;
const int _maxOpenRouterProfileTotalBytes = 64 * kBytesPerMiB;
const String _profileTable = 'openrouter_model_profiles';
const BoundedJsonConversionConfig _profileJsonConversionConfig =
    BoundedJsonConversionConfig(
      maxDepth: 16,
      maxContainerItems: 4096,
      maxTotalNodes: 32768,
    );

/// OpenRouter 模型档案的本地缓存。缓存独立于应用设置，避免设置 JSON 过大。
class OpenRouterModelProfileStore {
  OpenRouterModelProfileStore._();

  static final OpenRouterModelProfileStore instance =
      OpenRouterModelProfileStore._();

  late final _initialization = OpenHandRetryableAsyncCache<void>(_load);

  Future<void> ensureLoaded() => _initialization.load();

  Future<void> _load() async {
    final database = DatabaseService.instance.database;
    await _validateStorageScale(database);
    final rows = await database.query(
      _profileTable,
      columns: const <String>['model_id', 'profile_json'],
      orderBy: 'updated_at DESC, model_id ASC',
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
      final normalizedId = modelId.toLowerCase();
      // 兼容旧版本已写入的大小写别名，以最近更新的档案为准。
      if (loaded.containsKey(normalizedId)) continue;
      final source = decodeJsonObjectTextUsingConfig(
        encoded,
        maxTextCodeUnits: _maxOpenRouterProfileBytes,
        config: _profileJsonConversionConfig,
        invalidRootMessage: 'OpenRouter 模型档案必须为对象：$modelId',
      );
      final profile = AiModelProfile.fromJson(source);
      validateCanonicalJsonSubset(
        source,
        profile.toJson(),
        path: '$_profileTable.$modelId',
        maxDepth: _profileJsonConversionConfig.maxDepth,
        maxContainerItems: _profileJsonConversionConfig.maxContainerItems,
        maxTotalNodes: _profileJsonConversionConfig.maxTotalNodes,
      );
      loaded[normalizedId] = profile;
    }
    AiModelCatalog.registerExternalProfiles(loaded, replace: true);
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
        path: '$_profileTable.$modelId',
        maxDepth: _profileJsonConversionConfig.maxDepth,
        maxContainerItems: _profileJsonConversionConfig.maxContainerItems,
        maxTotalNodes: _profileJsonConversionConfig.maxTotalNodes,
      );
      final profileJson = jsonEncode(payload);
      final payloadBytes =
          utf8ByteLength(modelId) + utf8ByteLength(profileJson);
      totalBytes += payloadBytes;
      if (payloadBytes > _maxOpenRouterProfileBytes ||
          totalBytes > _maxOpenRouterProfileTotalBytes) {
        throw const FormatException('OpenRouter 模型档案载荷超过安全上限。');
      }
      rows.add((modelId: normalizedId, profileJson: profileJson));
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final database = DatabaseService.instance.database;
    await database.transaction((transaction) async {
      final storedIds = await transaction.query(
        _profileTable,
        columns: const <String>['model_id'],
        limit: _maxOpenRouterProfileCount + 1,
      );
      if (storedIds.length > _maxOpenRouterProfileCount) {
        throw const FormatException('OpenRouter 模型档案数量超过安全上限。');
      }
      final batch = transaction.batch();
      // 旧版本保留了 ID 大小写；更新时按主键删除别名，避免重启加载冲突。
      for (final stored in storedIds) {
        final id = stored['model_id'] as String;
        final normalizedId = id.toLowerCase();
        if (id != normalizedId && modelIds.contains(normalizedId)) {
          batch.delete(_profileTable, where: 'model_id = ?', whereArgs: [id]);
        }
      }
      for (final row in rows) {
        batch.insert(_profileTable, <String, Object?>{
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
      FROM $_profileTable
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
