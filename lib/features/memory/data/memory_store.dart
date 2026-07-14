import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/db/database_service.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/user_memory_entry.dart';

enum MemoryPersistenceIssueKind {
  recoveredInvalidFile,
  sanitizedInvalidContent,
  saveFailed,
}

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
  static const String _storageDirectoryUri = 'db://openhand';
  static const Set<String> _allowedTypes = <String>{
    UserMemoryEntry.userType,
    UserMemoryEntry.userProfileType,
  };

  Database get _db => _database ?? DatabaseService.instance.database;

  /// Retained for backward compatibility with controllers that expose this.
  String get userMemoryFilePath => _storageUri;
  String get storageDirectoryPath => _storageDirectoryUri;

  Future<MemoryLoadResult> load() async {
    try {
      final rows = await _db.query(_table, orderBy: 'created_at DESC');

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
            title: UserMemoryEntry.normalizeTitle(
              stringFromValue(row['title']),
            ),
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
    } catch (error) {
      return MemoryLoadResult(
        entries: const <UserMemoryEntry>[],
        issue: MemoryPersistenceIssue(
          kind: MemoryPersistenceIssueKind.saveFailed,
          filePath: _storageUri,
          detail: '$error',
        ),
      );
    }
  }

  Future<void> save(List<UserMemoryEntry> entries) async {
    await _db.transaction((txn) async {
      await txn.delete(_table);

      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert(_table, _entryToRow(entry));
      }
      await batch.commit(noResult: true);
    });
  }

  /// Deletes a single entry by id.
  Future<void> deleteEntry(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Updates a single entry.
  Future<void> updateEntry(UserMemoryEntry entry) async {
    await _db.update(
      _table,
      _entryToRow(entry),
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
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
    // No file directory to open for DB-backed store.
    // This is a no-op; the caller can check for DB path.
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
