import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../shared/data/database_service.dart';
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
  MemoryStore();

  Database get _db => DatabaseService.instance.database;

  /// Retained for backward compatibility with controllers that expose this.
  String get userMemoryFilePath => 'db://memories';
  String get storageDirectoryPath => 'db://openhand';

  Future<MemoryLoadResult> load() async {
    try {
      final rows = await _db.query(
        'memories',
        orderBy: 'created_at DESC',
      );

      final entries = <UserMemoryEntry>[];
      final seenIds = <String>{};
      var didSanitize = false;

      for (final row in rows) {
        final id = (row['id'] as String?) ?? '';
        if (id.isEmpty || !seenIds.add(id)) {
          didSanitize = true;
          continue;
        }

        final createdAtRaw = (row['created_at'] as String?) ?? '';
        final createdAt = DateTime.tryParse(createdAtRaw);
        if (createdAt == null) {
          didSanitize = true;
          continue;
        }

        final content = UserMemoryEntry.normalizeContent(
          (row['content'] as String?) ?? '',
        );
        if (content.isEmpty) {
          didSanitize = true;
          continue;
        }

        final rawType = (row['type'] as String?) ?? '';
        const type = UserMemoryEntry.userType;
        if (rawType != UserMemoryEntry.userType) {
          didSanitize = true;
        }

        List<String> tags;
        final tagsJson = row['tags_json'] as String?;
        if (tagsJson != null && tagsJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(tagsJson);
            if (decoded is List) {
              tags = UserMemoryEntry.normalizeTags(
                decoded.map((item) => '$item'),
              );
            } else {
              tags = const <String>[];
              didSanitize = true;
            }
          } catch (_) {
            tags = const <String>[];
            didSanitize = true;
          }
        } else {
          tags = const <String>[];
        }

        entries.add(
          UserMemoryEntry(
            id: id,
            type: type,
            createdAt: createdAt.toUtc(),
            content: content,
            tags: tags,
          ),
        );
      }

      if (didSanitize) {
        return MemoryLoadResult(
          entries: entries,
          issue: const MemoryPersistenceIssue(
            kind: MemoryPersistenceIssueKind.sanitizedInvalidContent,
            filePath: 'db://memories',
          ),
        );
      }

      return MemoryLoadResult(entries: entries);
    } catch (error) {
      return MemoryLoadResult(
        entries: const <UserMemoryEntry>[],
        issue: MemoryPersistenceIssue(
          kind: MemoryPersistenceIssueKind.saveFailed,
          filePath: 'db://memories',
          detail: '$error',
        ),
      );
    }
  }

  Future<void> save(List<UserMemoryEntry> entries) async {
    await _db.transaction((txn) async {
      await txn.delete('memories');

      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert('memories', _entryToRow(entry));
      }
      await batch.commit(noResult: true);
    });
  }

  /// Inserts a single entry without replacing the entire table.
  Future<void> insertEntry(UserMemoryEntry entry) async {
    await _db.insert(
      'memories',
      _entryToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a single entry by id.
  Future<void> deleteEntry(String id) async {
    await _db.delete(
      'memories',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Updates a single entry.
  Future<void> updateEntry(UserMemoryEntry entry) async {
    await _db.update(
      'memories',
      _entryToRow(entry),
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
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
      'tags_json': jsonEncode(entry.tags),
    };
  }
}
