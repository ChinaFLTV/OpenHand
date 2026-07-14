import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/db/legacy_persistence.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/user_memory_entry.dart';

enum MemoryPersistenceIssueKind { sanitizedInvalidContent, saveFailed }

class MemoryPersistenceIssue {
  const MemoryPersistenceIssue({
    required this.kind,
    required this.filePath,
    this.detail,
  });

  final MemoryPersistenceIssueKind kind;
  final String filePath;
  final String? detail;
}

class MemoryLoadResult {
  const MemoryLoadResult({required this.entries, this.issue});

  final List<UserMemoryEntry> entries;
  final MemoryPersistenceIssue? issue;
}

class MemoryStore {
  MemoryStore({Database? database}) : _database = database;

  final Database? _database;

  static const String _table = 'memories';
  static const String _storageUri = 'db://memories';
  static const String _legacyMigrationKey = 'legacy_user_memory_json_v1';
  static const String _settingsMigrationKey = 'legacy_settings_toml_v1';
  static const Set<String> _allowedTypes = <String>{
    UserMemoryEntry.userType,
    UserMemoryEntry.userProfileType,
  };

  Database get _db => _database ?? DatabaseService.instance.database;

  String get userMemoryFilePath => DatabaseService.defaultDatabasePath();
  String get storageDirectoryPath => p.dirname(userMemoryFilePath);

  Future<MemoryLoadResult> load() async {
    var rows = await _db.query(_table, orderBy: 'created_at DESC');
    if (rows.isEmpty) {
      final migrated = await _migrateLegacyMemories();
      if (migrated != null) return migrated;
      rows = await _db.query(_table, orderBy: 'created_at DESC');
    } else {
      try {
        await _markLegacyMigrationSatisfied();
      } catch (error, stack) {
        silentLog('memory_store', 'mark legacy migration', error, stack);
      }
    }

    final entries = <UserMemoryEntry>[];
    final seenIds = <String>{};
    var didSanitize = false;

    for (final row in rows) {
      final id = stringFromValue(row['id']);
      if (id.isEmpty || !seenIds.add(id)) {
        didSanitize = true;
        continue;
      }

      final createdAt = dateTimeFromValue(row['created_at']);
      if (createdAt == null) {
        didSanitize = true;
        continue;
      }

      final content = UserMemoryEntry.normalizeContent(
        stringFromValue(row['content']),
      );
      if (content.isEmpty) {
        didSanitize = true;
        continue;
      }

      final rawType = stringFromValue(row['type']);
      final String type;
      if (_allowedTypes.contains(rawType)) {
        type = rawType;
      } else {
        type = UserMemoryEntry.userType;
        didSanitize = true;
      }

      final parsedTags = _parseTags(row['tags_json']);
      didSanitize = didSanitize || parsedTags.didSanitize;

      entries.add(
        UserMemoryEntry(
          id: id,
          type: type,
          createdAt: createdAt.toUtc(),
          content: content,
          tags: parsedTags.tags,
          title: UserMemoryEntry.normalizeTitle(stringFromValue(row['title'])),
        ),
      );
    }

    if (didSanitize) {
      return MemoryLoadResult(
        entries: entries,
        issue: const MemoryPersistenceIssue(
          kind: MemoryPersistenceIssueKind.sanitizedInvalidContent,
          filePath: _storageUri,
        ),
      );
    }

    return MemoryLoadResult(entries: entries);
  }

  Future<MemoryLoadResult?> _migrateLegacyMemories() async {
    final markerRows = await _db.query(
      'migration_meta',
      where: 'key = ?',
      whereArgs: <Object?>[_legacyMigrationKey],
      limit: 1,
    );
    if (markerRows.isNotEmpty) return null;

    final configuredPath = await _legacyConfiguredMemoryPath();
    final sourceFile = await findLegacyMemoryFile(
      configuredPath: configuredPath,
    );

    _LegacyMemoryParseResult? parsed;
    if (sourceFile != null) {
      final raw = await readBoundedFileString(
        sourceFile,
        maxBytes: maxLegacyMemoryBytes,
      );
      parsed = _parseLegacyMemories(jsonDecode(raw));
    }

    final didMigrate = await _db.transaction<bool>((txn) async {
      final currentMarkerRows = await txn.query(
        'migration_meta',
        columns: const <String>['key'],
        where: 'key = ?',
        whereArgs: <Object?>[_legacyMigrationKey],
        limit: 1,
      );
      if (currentMarkerRows.isNotEmpty) return false;
      final countRows = await txn.rawQuery('SELECT COUNT(*) FROM $_table');
      final count = countRows.isEmpty
          ? 0
          : intFromValue(countRows.first.values.first, fallback: 0);
      if (count != 0) return false;

      final batch = txn.batch();
      for (final entry in parsed?.entries ?? const <UserMemoryEntry>[]) {
        batch.insert(
          _table,
          _entryToRow(entry),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      batch.insert('migration_meta', <String, Object?>{
        'key': _legacyMigrationKey,
        'value': jsonEncode(<String, Object?>{
          'status': sourceFile == null ? 'not_found' : 'imported',
          if (sourceFile != null) 'source_path': sourceFile.path,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        }),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await batch.commit(noResult: true);
      return true;
    });

    if (!didMigrate || parsed == null) return null;
    return MemoryLoadResult(
      entries: parsed.entries,
      issue: parsed.didSanitize
          ? MemoryPersistenceIssue(
              kind: MemoryPersistenceIssueKind.sanitizedInvalidContent,
              filePath: sourceFile!.path,
            )
          : null,
    );
  }

  Future<String?> _legacyConfiguredMemoryPath() async {
    final rows = await _db.query(
      'migration_meta',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_settingsMigrationKey],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final value = rows.first['value'];
      if (value is! String) {
        throw const FormatException('Settings migration marker is invalid.');
      }
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        throw const FormatException('Settings migration marker is invalid.');
      }
      final path = optionalStringFromValue(decoded['memory_file_path']);
      if (path != null) return path;
    }

    final settingsFile = await findLegacySettingsFile();
    if (settingsFile == null) return null;
    return readLegacyConfiguredMemoryFilePath(settingsFile);
  }

  Future<void> _markLegacyMigrationSatisfied() async {
    await _db.insert('migration_meta', <String, Object?>{
      'key': _legacyMigrationKey,
      'value': jsonEncode(<String, Object?>{
        'status': 'target_present',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  _LegacyMemoryParseResult _parseLegacyMemories(Object? decoded) {
    if (decoded is! List) {
      throw const FormatException('Legacy memory root must be a JSON array.');
    }

    final entries = <UserMemoryEntry>[];
    final seenIds = <String>{};
    var hasProfile = false;
    var didSanitize = false;
    for (final raw in decoded) {
      if (raw is! Map) {
        didSanitize = true;
        continue;
      }
      final id = stringFromValue(raw['id']).trim();
      final createdAt = dateTimeFromValue(raw['created_at']);
      final content = UserMemoryEntry.normalizeContent(
        stringFromValue(raw['content']),
      );
      if (id.isEmpty ||
          createdAt == null ||
          content.isEmpty ||
          !seenIds.add(id)) {
        didSanitize = true;
        continue;
      }

      final rawType = stringFromValue(raw['type']).trim();
      final type = _allowedTypes.contains(rawType)
          ? rawType
          : UserMemoryEntry.userType;
      if (type != rawType) didSanitize = true;
      if (type == UserMemoryEntry.userProfileType && hasProfile) {
        didSanitize = true;
        continue;
      }
      hasProfile = hasProfile || type == UserMemoryEntry.userProfileType;

      final rawTags = raw['tags'];
      final tags = rawTags is List
          ? UserMemoryEntry.normalizeTags(
              rawTags.map((value) => stringFromValue(value)),
            )
          : const <String>[];
      if (rawTags != null && rawTags is! List ||
          rawTags is List && tags.length != rawTags.length) {
        didSanitize = true;
      }
      entries.add(
        UserMemoryEntry(
          id: id,
          type: type,
          createdAt: createdAt.toUtc(),
          content: content,
          title: UserMemoryEntry.normalizeTitle(stringFromValue(raw['title'])),
          tags: tags,
        ),
      );
    }
    if (decoded.isNotEmpty && entries.isEmpty) {
      throw const FormatException('Legacy memory contains no valid entries.');
    }
    entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return _LegacyMemoryParseResult(entries: entries, didSanitize: didSanitize);
  }

  Future<void> insertEntry(UserMemoryEntry entry) async {
    await _db.insert(
      _table,
      _entryToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Deletes a single entry by id.
  Future<void> deleteEntry(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Updates a single entry.
  Future<void> updateEntry(UserMemoryEntry entry) async {
    final updated = await _db.update(
      _table,
      _entryToRow(entry),
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
    if (updated != 1) {
      throw StateError('Memory no longer exists: ${entry.id}');
    }
  }

  /// Upserts the single user profile entry. Keeps at most one profile row.
  Future<UserMemoryEntry> upsertUserProfile({
    required String content,
    List<String> tags = const <String>[],
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        'Profile content cannot be empty.',
      );
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(tags);

    // Wrap the read-modify-write in a transaction so concurrent callers
    // cannot race between the SELECT, DELETE-extras, and INSERT steps.
    return _db.transaction<UserMemoryEntry>((txn) async {
      final existingRows = await txn.query(
        _table,
        where: 'type = ?',
        whereArgs: <Object?>[UserMemoryEntry.userProfileType],
      );

      String entryId;
      if (existingRows.isEmpty) {
        entryId = UserMemoryEntry.userProfileEntryId;
      } else {
        entryId =
            (existingRows.first['id'] as String?) ??
            UserMemoryEntry.userProfileEntryId;
        if (existingRows.length > 1) {
          await txn.delete(
            _table,
            where: 'type = ? AND id != ?',
            whereArgs: <Object?>[UserMemoryEntry.userProfileType, entryId],
          );
        }
      }

      final entry = UserMemoryEntry(
        id: entryId,
        type: UserMemoryEntry.userProfileType,
        createdAt: DateTime.now().toUtc(),
        content: normalizedContent,
        tags: normalizedTags,
      );

      await txn.insert(
        _table,
        _entryToRow(entry),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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

  ({List<String> tags, bool didSanitize}) _parseTags(Object? raw) {
    final tagsJson = optionalStringFromValue(raw);
    if (tagsJson == null) {
      return (tags: const <String>[], didSanitize: false);
    }
    final tags = optionalStringListFromJsonText(tagsJson, requireList: true);
    if (tags == null) {
      return (tags: const <String>[], didSanitize: true);
    }
    return (tags: UserMemoryEntry.normalizeTags(tags), didSanitize: false);
  }
}

class _LegacyMemoryParseResult {
  const _LegacyMemoryParseResult({
    required this.entries,
    required this.didSanitize,
  });

  final List<UserMemoryEntry> entries;
  final bool didSanitize;
}
