import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../model/knowledge_source.dart';

const int _maxPendingKnowledgeSourceCleanups = 2048;
const int _pendingKnowledgeSourceCleanupRetryBatch = 4;
const int _knowledgeSourceIdMaxCharacters = 512;
const Duration _pendingKnowledgeSourceDeleteTimeout = Duration(seconds: 5);
const String _pendingKnowledgeSourceCleanupSettingPrefix =
    'knowledge_source_cleanup:';
final SerialTaskQueue _knowledgeSourceCleanupQueue = SerialTaskQueue();
Future<void>? _scheduledKnowledgeSourceCleanupRetry;

String get knowledgeManagedSourcesDirectoryPath => p.join(
  OpenHandPaths.homeDirectoryPath(),
  '.openhand',
  'knowledge',
  'sources',
);

Future<void> stageManagedKnowledgeSourceFileCleanup(
  KnowledgeSource source,
) async {
  final entry = _managedKnowledgeSourceCleanupEntry(source);
  if (entry == null) return;
  await _knowledgeSourceCleanupQueue.enqueue(() => _stageCleanup(entry));
}

Future<void> cancelManagedKnowledgeSourceFileCleanup(
  KnowledgeSource source,
) async {
  if (source.metadata['copied_to_openhand_storage'] != true) return;
  await _knowledgeSourceCleanupQueue.enqueue(
    () => _deleteCleanupMarker(source.id),
  );
}

Future<void> deleteManagedKnowledgeSourceFile(KnowledgeSource source) async {
  final entry = _managedKnowledgeSourceCleanupEntry(source);
  if (entry == null) return;
  await _knowledgeSourceCleanupQueue.enqueue(() async {
    await _stageCleanup(entry);
    await _completeCleanup(entry);
  });
}

Future<void> completeManagedKnowledgeSourceFileCleanup(
  KnowledgeSource source,
) async {
  final entry = _managedKnowledgeSourceCleanupEntry(source);
  if (entry == null) return;
  await _knowledgeSourceCleanupQueue.enqueue(() => _completeCleanup(entry));
}

void schedulePendingKnowledgeSourceFileCleanups({
  required Future<bool> Function(String sourceId) sourceExists,
}) {
  if (_scheduledKnowledgeSourceCleanupRetry != null) return;
  final future = retryPendingKnowledgeSourceFileCleanups(
    sourceExists: sourceExists,
  );
  _scheduledKnowledgeSourceCleanupRetry = future;
  unawaited(
    future.whenComplete(() {
      if (identical(_scheduledKnowledgeSourceCleanupRetry, future)) {
        _scheduledKnowledgeSourceCleanupRetry = null;
      }
    }),
  );
}

Future<void> retryPendingKnowledgeSourceFileCleanups({
  required Future<bool> Function(String sourceId) sourceExists,
}) {
  return _knowledgeSourceCleanupQueue.enqueue(() async {
    try {
      final pending = await _loadPendingKnowledgeSourceCleanups();
      var attempted = 0;
      for (final entry in pending) {
        try {
          // A staged marker may belong to a deletion that has not committed
          // yet. Keep it until the source row is gone.
          if (await sourceExists(entry.sourceId)) continue;
          if (attempted >= _pendingKnowledgeSourceCleanupRetryBatch) break;
          attempted += 1;
          await _deleteManagedKnowledgeSourcePath(entry.path);
          await _deleteCleanupMarker(entry.sourceId);
        } catch (error, stack) {
          silentLog(
            'knowledge_source_storage',
            'retry pending source cleanup',
            error,
            stack,
          );
        }
      }
    } catch (error, stack) {
      silentLog(
        'knowledge_source_storage',
        'process pending source cleanups',
        error,
        stack,
      );
    }
  });
}

Future<void> _stageCleanup(({String sourceId, String path}) entry) async {
  final db = DatabaseService.instance.database;
  final markerKey = _cleanupMarkerKey(entry.sourceId);
  await db.transaction((txn) async {
    final existing = await txn.query(
      'app_settings',
      columns: const <String>['key'],
      where: 'key = ?',
      whereArgs: <Object?>[markerKey],
      limit: 1,
    );
    if (existing.isEmpty) {
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS marker_count FROM app_settings WHERE key GLOB ?',
        <Object?>['$_pendingKnowledgeSourceCleanupSettingPrefix*'],
      );
      final rawCount = countRows.isEmpty
          ? null
          : countRows.first['marker_count'];
      final count = rawCount is num ? rawCount.toInt() : 0;
      if (count >= _maxPendingKnowledgeSourceCleanups) {
        throw StateError('Too many pending knowledge-source cleanups.');
      }
    }
    await txn.insert('app_settings', <String, Object?>{
      'key': markerKey,
      'value': jsonEncode(<String, String>{
        'source_id': entry.sourceId,
        'path': entry.path,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
}

Future<List<({String sourceId, String path})>>
_loadPendingKnowledgeSourceCleanups() async {
  final db = DatabaseService.instance.database;
  final rows = await db.query(
    'app_settings',
    columns: const <String>['key', 'value'],
    where: 'key GLOB ?',
    whereArgs: <Object?>['$_pendingKnowledgeSourceCleanupSettingPrefix*'],
    orderBy: 'key ASC',
    limit: _maxPendingKnowledgeSourceCleanups,
  );
  final root = p.absolute(knowledgeManagedSourcesDirectoryPath);
  final entries = <({String sourceId, String path})>[];
  for (final row in rows) {
    final markerKey = row['key'];
    try {
      final decoded = jsonDecode('${row['value']}');
      if (decoded is! Map) throw const FormatException('Invalid marker.');
      final sourceId = '${decoded['source_id'] ?? ''}'.trim();
      final path = p.absolute('${decoded['path'] ?? ''}'.trim());
      if (sourceId.isEmpty ||
          sourceId.length > _knowledgeSourceIdMaxCharacters ||
          markerKey != _cleanupMarkerKey(sourceId) ||
          !p.isWithin(root, path)) {
        throw const FormatException('Invalid marker fields.');
      }
      entries.add((sourceId: sourceId, path: path));
    } catch (error, stack) {
      silentLog(
        'knowledge_source_storage',
        'decode pending source cleanup',
        error,
        stack,
      );
      if (markerKey is String) {
        await db.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: <Object?>[markerKey],
        );
      }
    }
  }
  return entries;
}

Future<void> _deleteCleanupMarker(String sourceId) {
  return DatabaseService.instance.database.delete(
    'app_settings',
    where: 'key = ?',
    whereArgs: <Object?>[_cleanupMarkerKey(sourceId)],
  );
}

Future<void> _deleteManagedKnowledgeSourcePath(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete().timeout(_pendingKnowledgeSourceDeleteTimeout);
  }
}

Future<void> _completeCleanup(({String sourceId, String path}) entry) async {
  await _deleteManagedKnowledgeSourcePath(entry.path);
  await _deleteCleanupMarker(entry.sourceId);
}

({String sourceId, String path})? _managedKnowledgeSourceCleanupEntry(
  KnowledgeSource source,
) {
  if (source.metadata['copied_to_openhand_storage'] != true) return null;
  final sourceId = source.id.trim();
  if (sourceId.isEmpty || sourceId.length > _knowledgeSourceIdMaxCharacters) {
    throw ArgumentError.value(source.id, 'source.id', 'Invalid source id.');
  }
  final root = p.absolute(knowledgeManagedSourcesDirectoryPath);
  final path = p.absolute(source.storedPath.trim());
  if (!p.isWithin(root, path)) {
    throw FileSystemException(
      'Refusing to delete a knowledge source outside managed storage.',
      path,
    );
  }
  return (sourceId: sourceId, path: path);
}

String _cleanupMarkerKey(String sourceId) =>
    '$_pendingKnowledgeSourceCleanupSettingPrefix$sourceId';
