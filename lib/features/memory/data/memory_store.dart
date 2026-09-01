import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/db/legacy_persistence.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../model/user_memory_entry.dart';

class MemoryPersistenceIssue {
  const MemoryPersistenceIssue({required this.filePath});

  final String filePath;
}

class MemoryLoadResult {
  const MemoryLoadResult({required this.entries, required this.isOverQuota});

  final List<UserMemoryEntry> entries;
  final bool isOverQuota;
}

class MemoryStore {
  MemoryStore({this._database});

  final Database? _database;

  static const String _table = 'memories';
  static const String _legacyMigrationKey = 'legacy_user_memory_json_v1';
  static const String _settingsMigrationKey = 'legacy_settings_toml_v1';
  static const String _multipleProfilesMessage = '存储中存在多个用户资料。';
  static const String _invalidMigrationMarkerMessage = '记忆迁移标记无效。';
  static const int _snapshotPageSize = 64;
  static const int _maxTagsJsonBytes =
      UserMemoryEntry.maxTags * (UserMemoryEntry.maxTagCharacters * 6 + 3) + 2;
  static const int maxEntries = 1024;
  static const int maxTotalPayloadBytes = 16 * kBytesPerMiB;
  static const Set<String> _allowedTypes = <String>{
    UserMemoryEntry.userType,
    UserMemoryEntry.userProfileType,
  };
  static const Set<String> _legacyMigrationStatuses = <String>{
    legacyMigrationStatusNotFound,
    legacyMigrationStatusImported,
    legacyMigrationStatusTargetPresent,
    legacyMigrationStatusExplicitClear,
  };

  Database get _db => _database ?? DatabaseService.instance.database;

  String get userMemoryFilePath => DatabaseService.defaultDatabasePath();
  String get storageDirectoryPath => p.dirname(userMemoryFilePath);

  Future<MemoryLoadResult> load() async {
    final initialUsage = await _queryUsage(_db);
    if (initialUsage.entryCount == 0) {
      final migrated = await _migrateLegacyMemories();
      if (migrated != null) return migrated;
    }

    final snapshot = await _readBoundedSnapshot();
    final entries = <UserMemoryEntry>[];
    final seenIds = <String>{};
    var hasProfile = false;
    for (final row in snapshot.rows) {
      final entry = _parseStoredEntry(row);
      if (!seenIds.add(entry.id)) {
        throw FormatException('记忆 ID 重复：${entry.id}');
      }
      if (entry.isUserProfile) {
        if (hasProfile) {
          throw const FormatException(_multipleProfilesMessage);
        }
        hasProfile = true;
      }
      entries.add(entry);
    }

    if (entries.isNotEmpty) {
      try {
        await markLegacyTargetPresentIfAbsent(_db, key: _legacyMigrationKey);
      } catch (error, stack) {
        silentLog('memory_store', '标记旧版数据迁移', error, stack);
      }
    }

    return MemoryLoadResult(
      entries: entries,
      isOverQuota: snapshot.isOverQuota,
    );
  }

  Future<_MemoryRowsSnapshot> _readBoundedSnapshot() {
    return _db.transaction<_MemoryRowsSnapshot>((txn) async {
      final usage = await _queryUsage(txn);
      final rows = <Map<String, Object?>>[];
      var payloadBytes = 0;
      final profileRows = await txn.query(
        _table,
        where: 'type = ?',
        whereArgs: const <Object?>[UserMemoryEntry.userProfileType],
        limit: 1,
      );
      if (profileRows.isNotEmpty) {
        final profileBytes = _rowPayloadBytes(profileRows.single);
        rows.add(profileRows.single);
        payloadBytes = profileBytes;
      }
      var offset = 0;
      while (rows.length < maxEntries) {
        final remaining = maxEntries - rows.length;
        final limit = remaining < _snapshotPageSize
            ? remaining
            : _snapshotPageSize;
        final page = await txn.query(
          _table,
          where: 'type != ?',
          whereArgs: const <Object?>[UserMemoryEntry.userProfileType],
          orderBy: 'created_at DESC, id ASC',
          limit: limit,
          offset: offset,
        );
        if (page.isEmpty) break;
        for (final row in page) {
          final rowBytes = _rowPayloadBytes(row);
          if (payloadBytes + rowBytes > maxTotalPayloadBytes) {
            return _MemoryRowsSnapshot(rows: rows, isOverQuota: true);
          }
          rows.add(row);
          payloadBytes += rowBytes;
        }
        offset += page.length;
        if (page.length < limit) break;
      }
      return _MemoryRowsSnapshot(
        rows: rows,
        isOverQuota: rows.length < usage.entryCount,
      );
    });
  }

  Future<MemoryLoadResult?> _migrateLegacyMemories() async {
    final markerRows = await _db.query(
      legacyMigrationMetaTable,
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_legacyMigrationKey],
      limit: 1,
    );
    if (markerRows.isNotEmpty) {
      _validateLegacyMigrationMarker(markerRows.single);
      return null;
    }

    final configuredPath = await _legacyConfiguredMemoryPath();
    final sourceFile = await findLegacyMemoryFile(
      configuredPath: configuredPath,
    );

    List<UserMemoryEntry>? parsed;
    if (sourceFile != null) {
      final raw = await readBoundedFileString(
        sourceFile,
        maxBytes: maxLegacyMemoryBytes,
      );
      parsed = _parseLegacyMemories(jsonDecode(raw));
    }

    final didMigrate = await _db.transaction<bool>((txn) async {
      final currentMarkerRows = await txn.query(
        legacyMigrationMetaTable,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[_legacyMigrationKey],
        limit: 1,
      );
      if (currentMarkerRows.isNotEmpty) {
        _validateLegacyMigrationMarker(currentMarkerRows.single);
        return false;
      }
      final usage = await _queryUsage(txn);
      if (usage.entryCount != 0) return false;

      final entries = parsed ?? const <UserMemoryEntry>[];
      _validateWriteCollection(entries);

      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert(
          _table,
          _entryToRow(entry),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      batch.insert(legacyMigrationMetaTable, <String, Object?>{
        'key': _legacyMigrationKey,
        'value': encodeLegacyMigrationMarker(
          status: sourceFile == null
              ? legacyMigrationStatusNotFound
              : legacyMigrationStatusImported,
          sourcePath: sourceFile?.path,
        ),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await batch.commit(noResult: true);
      return true;
    });

    if (!didMigrate || parsed == null) return null;
    return MemoryLoadResult(entries: parsed, isOverQuota: false);
  }

  Future<String?> _legacyConfiguredMemoryPath() async {
    final rows = await _db.query(
      legacyMigrationMetaTable,
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_settingsMigrationKey],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final value = rows.first['value'];
      if (value is! String) {
        throw const FormatException('设置迁移标记无效。');
      }
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        throw const FormatException('设置迁移标记无效。');
      }
      final rawPath = decoded['memory_file_path'];
      if (rawPath != null) {
        if (rawPath is! String) {
          throw const FormatException('设置中的记忆路径无效。');
        }
        final path = rawPath.trim();
        if (path.isNotEmpty) return path;
      }
    }

    final settingsFile = await findLegacySettingsFile();
    if (settingsFile == null) return null;
    return readLegacyConfiguredMemoryFilePath(settingsFile);
  }

  List<UserMemoryEntry> _parseLegacyMemories(Object? decoded) {
    if (decoded is! List) {
      throw const FormatException('旧版记忆根节点必须是 JSON 数组。');
    }

    final entries = <UserMemoryEntry>[];
    final seenIds = <String>{};
    var hasProfile = false;
    for (final raw in decoded) {
      if (raw is! Map) {
        throw const FormatException('旧版记忆条目必须是对象。');
      }
      final entry = _parseLegacyEntry(raw);
      if (!seenIds.add(entry.id)) {
        throw FormatException('旧版记忆 ID 重复：${entry.id}');
      }
      if (entry.isUserProfile) {
        if (hasProfile) {
          throw const FormatException('旧版记忆中存在多个用户资料。');
        }
        hasProfile = true;
      }
      entries.add(entry);
    }
    entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return entries;
  }

  Future<void> insertEntry(UserMemoryEntry entry) async {
    _validateEntryForWrite(entry);
    final row = _entryToRow(entry);
    await _db.transaction<void>((txn) async {
      final usage = await _queryUsage(txn);
      _ensureInsertWithinQuota(usage, _rowPayloadBytes(row));
      if (entry.isUserProfile) {
        await _ensureNoOtherProfile(txn, excludingId: entry.id);
      }
      await txn.insert(_table, row, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  /// 按 ID 删除单条记录。
  Future<void> deleteEntry(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 更新单条记录。
  Future<void> updateEntry(UserMemoryEntry entry) async {
    _validateEntryForWrite(entry);
    final row = _entryToRow(entry);
    await _db.transaction<void>((txn) async {
      final existingRows = await txn.query(
        _table,
        where: 'id = ?',
        whereArgs: <Object?>[entry.id],
        limit: 1,
      );
      if (existingRows.isEmpty) {
        throw StateError('记忆已不存在：${entry.id}');
      }
      final existing = _parseStoredEntry(existingRows.single);
      if (existing.type != entry.type) {
        throw StateError('记忆类型不可修改：${entry.id}');
      }
      final usage = await _queryUsage(txn);
      _ensureUpdateWithinQuota(
        usage,
        previousBytes: _rowPayloadBytes(existingRows.single),
        nextBytes: _rowPayloadBytes(row),
      );
      final updated = await txn.update(
        _table,
        row,
        where: 'id = ?',
        whereArgs: <Object?>[entry.id],
      );
      if (updated != 1) {
        throw StateError('记忆已不存在：${entry.id}');
      }
    });
  }

  Future<void> clearAll() async {
    await _db.transaction<void>((txn) async {
      await txn.delete(_table);
      await txn.insert(legacyMigrationMetaTable, <String, Object?>{
        'key': _legacyMigrationKey,
        'value': encodeLegacyMigrationMarker(
          status: legacyMigrationStatusExplicitClear,
        ),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// 创建或更新唯一的用户资料记录。
  Future<UserMemoryEntry> upsertUserProfile({
    required String content,
    List<String>? tags,
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      throw ArgumentError.value(content, 'content', '用户资料内容不能为空。');
    }
    return _db.transaction<UserMemoryEntry>((txn) async {
      final existingRows = await txn.query(
        _table,
        where: 'type = ?',
        whereArgs: <Object?>[UserMemoryEntry.userProfileType],
      );

      if (existingRows.length > 1) {
        throw const FormatException(_multipleProfilesMessage);
      }
      final existing = existingRows.isEmpty
          ? null
          : _parseStoredEntry(existingRows.single);
      final normalizedTags = tags == null
          ? existing?.tags ?? const <String>[]
          : UserMemoryEntry.normalizeTags(tags);

      final entry = UserMemoryEntry(
        id: existing?.id ?? UserMemoryEntry.userProfileEntryId,
        type: UserMemoryEntry.userProfileType,
        createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
        content: normalizedContent,
        tags: normalizedTags,
      );
      _validateEntryForWrite(entry);
      final row = _entryToRow(entry);
      final usage = await _queryUsage(txn);

      if (existing == null) {
        _ensureInsertWithinQuota(usage, _rowPayloadBytes(row));
        await txn.insert(
          _table,
          row,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        _ensureUpdateWithinQuota(
          usage,
          previousBytes: _rowPayloadBytes(existingRows.single),
          nextBytes: _rowPayloadBytes(row),
        );
        final updated = await txn.update(
          _table,
          row,
          where: 'id = ?',
          whereArgs: <Object?>[existing.id],
        );
        if (updated != 1) {
          throw StateError('用户资料已不存在：${existing.id}');
        }
      }

      return entry;
    });
  }

  Future<void> openStorageDirectory() async {
    await openDirectoryInFileManager(Directory(storageDirectoryPath));
  }

  Map<String, Object?> _entryToRow(UserMemoryEntry entry) {
    return <String, Object?>{
      'id': entry.id,
      'type': entry.type,
      'created_at': entry.createdAtStorageValue,
      'content': entry.content,
      'title': UserMemoryEntry.normalizeTitle(entry.title),
      'tags_json': jsonEncode(entry.tags),
    };
  }

  UserMemoryEntry _parseStoredEntry(Map<String, Object?> row) {
    return _parseEntry(
      id: row['id'],
      type: row['type'],
      createdAt: row['created_at'],
      content: row['content'],
      title: row['title'],
      tags: _decodeTagsJson(row['tags_json']),
      source: '已存储记忆',
    );
  }

  UserMemoryEntry _parseLegacyEntry(Map<dynamic, dynamic> row) {
    final rawTitle = row.containsKey('title') ? row['title'] : '';
    final rawTags = row.containsKey('tags') ? row['tags'] : const <Object?>[];
    if (rawTags is! List) {
      throw const FormatException('旧版记忆标签必须是数组。');
    }
    return _parseEntry(
      id: row['id'],
      type: row['type'],
      createdAt: row['created_at'],
      content: row['content'],
      title: rawTitle,
      tags: rawTags,
      source: '旧版记忆',
    );
  }

  UserMemoryEntry _parseEntry({
    required Object? id,
    required Object? type,
    required Object? createdAt,
    required Object? content,
    required Object? title,
    required List<dynamic> tags,
    required String source,
  }) {
    if (id is! String ||
        id.isEmpty ||
        id.trim() != id ||
        id.length > UserMemoryEntry.maxIdCharacters) {
      throw FormatException('$source ID 无效。');
    }
    if (type is! String || !_allowedTypes.contains(type)) {
      throw FormatException('$source类型无效：$id');
    }
    if (createdAt is! String) {
      throw FormatException('$source时间戳无效：$id');
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null ||
        !parsedCreatedAt.isUtc ||
        parsedCreatedAt.toIso8601String() != createdAt) {
      throw FormatException('$source时间戳不是规范 UTC 格式：$id');
    }
    if (content is! String ||
        content.isEmpty ||
        UserMemoryEntry.normalizeContent(content) != content ||
        content.length > UserMemoryEntry.maxContentCharacters) {
      throw FormatException('$source内容无效：$id');
    }
    if (title is! String || UserMemoryEntry.normalizeTitle(title) != title) {
      throw FormatException('$source标题无效：$id');
    }
    final parsedTags = <String>[];
    for (final tag in tags) {
      if (tag is! String) {
        throw FormatException('$source标签无效：$id');
      }
      parsedTags.add(tag);
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(parsedTags);
    if (!listEquals(parsedTags, normalizedTags) ||
        parsedTags.length > UserMemoryEntry.maxTags ||
        parsedTags.any(
          (tag) => tag.length > UserMemoryEntry.maxTagCharacters,
        )) {
      throw FormatException('$source标签格式不规范：$id');
    }
    return UserMemoryEntry(
      id: id,
      type: type,
      createdAt: parsedCreatedAt,
      content: content,
      tags: normalizedTags,
      title: title,
    );
  }

  List<dynamic> _decodeTagsJson(Object? raw) {
    if (raw is! String) {
      throw const FormatException('已存储记忆标签必须是 JSON 文本。');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('已存储记忆标签 JSON 无效。');
    }
    if (decoded is! List) {
      throw const FormatException('已存储记忆标签必须是 JSON 数组。');
    }
    return decoded;
  }

  void _validateWriteCollection(List<UserMemoryEntry> entries) {
    if (entries.length > maxEntries) {
      throw StateError('记忆条目超过上限（$maxEntries）。');
    }
    var totalBytes = 0;
    for (final entry in entries) {
      _validateEntryForWrite(entry);
      totalBytes += _rowPayloadBytes(_entryToRow(entry));
      if (totalBytes > maxTotalPayloadBytes) {
        throw StateError('记忆载荷超过上限（$maxTotalPayloadBytes 字节）。');
      }
    }
  }

  void _validateEntryForWrite(UserMemoryEntry entry) {
    if (entry.id.isEmpty ||
        entry.id.trim() != entry.id ||
        entry.id.length > UserMemoryEntry.maxIdCharacters) {
      throw ArgumentError.value(entry.id, 'id', '记忆 ID 无效。');
    }
    if (!_allowedTypes.contains(entry.type)) {
      throw ArgumentError.value(entry.type, 'type', '记忆类型无效。');
    }
    if (!entry.createdAt.isUtc) {
      throw ArgumentError.value(entry.createdAt, 'createdAt', '记忆时间戳必须使用 UTC。');
    }
    if (entry.content.isEmpty ||
        UserMemoryEntry.normalizeContent(entry.content) != entry.content ||
        entry.content.length > UserMemoryEntry.maxContentCharacters) {
      throw ArgumentError.value(entry.content, 'content', '记忆内容无效或过长。');
    }
    if (UserMemoryEntry.normalizeTitle(entry.title) != entry.title) {
      throw ArgumentError.value(entry.title, 'title', '记忆标题无效。');
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(entry.tags);
    if (!listEquals(entry.tags, normalizedTags) ||
        entry.tags.length > UserMemoryEntry.maxTags ||
        entry.tags.any(
          (tag) => tag.length > UserMemoryEntry.maxTagCharacters,
        )) {
      throw ArgumentError.value(entry.tags, 'tags', '记忆标签无效。');
    }
  }

  Future<_MemoryUsage> _queryUsage(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery('''
      SELECT COUNT(*) AS entry_count,
             COALESCE(SUM(
               LENGTH(CAST(IFNULL(id, '') AS BLOB)) +
               LENGTH(CAST(IFNULL(type, '') AS BLOB)) +
               LENGTH(CAST(IFNULL(created_at, '') AS BLOB)) +
               LENGTH(CAST(IFNULL(content, '') AS BLOB)) +
               LENGTH(CAST(IFNULL(title, '') AS BLOB)) +
               LENGTH(CAST(IFNULL(tags_json, '') AS BLOB))
             ), 0) AS total_bytes,
             COALESCE(SUM(CASE WHEN
               TYPEOF(id) != 'text' OR LENGTH(id) > ${UserMemoryEntry.maxIdCharacters} OR
               TYPEOF(type) != 'text' OR LENGTH(type) > 32 OR
               TYPEOF(created_at) != 'text' OR LENGTH(created_at) > 64 OR
               TYPEOF(content) != 'text' OR LENGTH(content) > ${UserMemoryEntry.maxContentCharacters} OR
               TYPEOF(title) != 'text' OR LENGTH(title) > ${UserMemoryEntry.maxTitleLength} OR
               TYPEOF(tags_json) != 'text' OR
                 LENGTH(CAST(tags_json AS BLOB)) > $_maxTagsJsonBytes
             THEN 1 ELSE 0 END), 0) AS invalid_count,
             COALESCE(SUM(CASE WHEN type = '${UserMemoryEntry.userProfileType}'
               THEN 1 ELSE 0 END), 0) AS profile_count
      FROM $_table
    ''');
    if (rows.length != 1) {
      throw const FormatException('记忆用量查询未返回结果。');
    }
    final entryCount = rows.single['entry_count'];
    final totalBytes = rows.single['total_bytes'];
    final invalidCount = rows.single['invalid_count'];
    final profileCount = rows.single['profile_count'];
    if (entryCount is! int ||
        totalBytes is! int ||
        invalidCount is! int ||
        profileCount is! int) {
      throw const FormatException('记忆用量元数据无效。');
    }
    if (invalidCount != 0) {
      throw const FormatException('记忆存储包含无效字段。');
    }
    if (profileCount > 1) {
      throw const FormatException(_multipleProfilesMessage);
    }
    return _MemoryUsage(entryCount: entryCount, totalBytes: totalBytes);
  }

  void _validateLegacyMigrationMarker(Map<String, Object?> row) {
    final value = row['value'];
    if (value is! String) {
      throw const FormatException(_invalidMigrationMarkerMessage);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const FormatException(_invalidMigrationMarkerMessage);
    }
    if (decoded is! Map<String, dynamic> || jsonEncode(decoded) != value) {
      throw const FormatException('记忆迁移标记格式不规范。');
    }
    final status = decoded['status'];
    final completedAt = decoded['completed_at'];
    if (status is! String ||
        !_legacyMigrationStatuses.contains(status) ||
        completedAt is! String) {
      throw const FormatException(_invalidMigrationMarkerMessage);
    }
    final parsedCompletedAt = DateTime.tryParse(completedAt);
    if (parsedCompletedAt == null ||
        !parsedCompletedAt.isUtc ||
        parsedCompletedAt.toIso8601String() != completedAt) {
      throw const FormatException('记忆迁移标记时间无效。');
    }
    final expectedKeys = <String>{'status', 'completed_at'};
    if (status == legacyMigrationStatusImported) {
      final sourcePath = decoded['source_path'];
      if (sourcePath is! String ||
          sourcePath.isEmpty ||
          sourcePath.trim() != sourcePath) {
        throw const FormatException('记忆迁移来源路径无效。');
      }
      expectedKeys.add('source_path');
    }
    if (decoded.length != expectedKeys.length ||
        !expectedKeys.every(decoded.containsKey)) {
      throw const FormatException('记忆迁移标记字段无效。');
    }
  }

  void _ensureInsertWithinQuota(_MemoryUsage usage, int payloadBytes) {
    if (usage.entryCount >= maxEntries) {
      throw StateError('记忆条目超过上限（$maxEntries）。');
    }
    if (usage.totalBytes + payloadBytes > maxTotalPayloadBytes) {
      throw StateError('记忆载荷超过上限（$maxTotalPayloadBytes 字节）。');
    }
  }

  void _ensureUpdateWithinQuota(
    _MemoryUsage usage, {
    required int previousBytes,
    required int nextBytes,
  }) {
    final isHistoricallyOverLimit =
        usage.entryCount > maxEntries ||
        usage.totalBytes > maxTotalPayloadBytes;
    if (isHistoricallyOverLimit) {
      if (nextBytes >= previousBytes) {
        throw StateError('超限记忆更新必须减少载荷大小。');
      }
      return;
    }
    if (usage.totalBytes - previousBytes + nextBytes > maxTotalPayloadBytes) {
      throw StateError('记忆载荷超过上限（$maxTotalPayloadBytes 字节）。');
    }
  }

  Future<void> _ensureNoOtherProfile(
    DatabaseExecutor executor, {
    required String excludingId,
  }) async {
    final rows = await executor.query(
      _table,
      columns: const <String>['id'],
      where: 'type = ? AND id != ?',
      whereArgs: <Object?>[UserMemoryEntry.userProfileType, excludingId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError('用户资料已存在。');
    }
  }

  int _rowPayloadBytes(Map<String, Object?> row) {
    var total = 0;
    for (final key in const <String>[
      'id',
      'type',
      'created_at',
      'content',
      'title',
      'tags_json',
    ]) {
      final value = row[key];
      if (value is! String) {
        throw FormatException('记忆字段 $key 不是文本。');
      }
      total += utf8.encode(value).length;
    }
    return total;
  }
}

class _MemoryUsage {
  const _MemoryUsage({required this.entryCount, required this.totalBytes});

  final int entryCount;
  final int totalBytes;
}

class _MemoryRowsSnapshot {
  const _MemoryRowsSnapshot({required this.rows, required this.isOverQuota});

  final List<Map<String, Object?>> rows;
  final bool isOverQuota;
}
