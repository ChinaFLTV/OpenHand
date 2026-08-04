import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/physical_path_safety.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../model/knowledge_source.dart';

const int _maxPendingKnowledgeSourceCleanups = 2048;
const int _pendingKnowledgeSourceCleanupRetryBatch = 4;
const int _knowledgeSourceIdMaxCharacters = 512;
const Duration _pendingKnowledgeSourceDeleteTimeout = Duration(seconds: 5);
const Duration _pendingKnowledgeSourceLookupTimeout = Duration(seconds: 5);
const Duration _pendingKnowledgeSourceRetryTimeout = Duration(seconds: 15);
const Duration _staleKnowledgeSourceCleanupIntentAge = Duration(days: 1);
const Duration _knowledgeSourceCleanupFutureClockTolerance = Duration(
  minutes: 5,
);
const String _pendingKnowledgeSourceCleanupSettingPrefix =
    'knowledge_source_cleanup:';
final SerialTaskQueue _knowledgeSourceCleanupQueue = SerialTaskQueue(
  maxPendingTasks: _maxPendingKnowledgeSourceCleanups,
);
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
  final entry = _managedKnowledgeSourceCleanupEntry(source);
  if (entry == null) return;
  await _knowledgeSourceCleanupQueue.enqueue(
    () => _deleteCleanupMarker(entry.sourceId),
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
    future
        .whenComplete(() {
          if (identical(_scheduledKnowledgeSourceCleanupRetry, future)) {
            _scheduledKnowledgeSourceCleanupRetry = null;
          }
        })
        .catchError((Object error, StackTrace stack) {
          silentLog('knowledge_source_storage', '调度待处理知识源清理', error, stack);
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
      final now = DateTime.now().toUtc();
      final retryStopwatch = Stopwatch()..start();
      for (final entry in pending) {
        final remaining =
            _pendingKnowledgeSourceRetryTimeout - retryStopwatch.elapsed;
        if (remaining <= Duration.zero) break;
        try {
          // 删除可能尚未完成，保留新标记；清理过期意图，避免永久占用容量。
          final lookupTimeout = remaining < _pendingKnowledgeSourceLookupTimeout
              ? remaining
              : _pendingKnowledgeSourceLookupTimeout;
          if (await sourceExists(entry.sourceId).timeout(lookupTimeout)) {
            if (now.difference(entry.createdAt) >=
                _staleKnowledgeSourceCleanupIntentAge) {
              await _deleteCleanupMarker(entry.sourceId);
            }
            continue;
          }
          if (attempted >= _pendingKnowledgeSourceCleanupRetryBatch) break;
          attempted += 1;
          await _deleteManagedKnowledgeSourcePath(entry.path);
          await _deleteCleanupMarker(entry.sourceId);
        } catch (error, stack) {
          silentLog('knowledge_source_storage', '重试待处理知识源清理', error, stack);
          if (error is TimeoutException) break;
        }
      }
    } catch (error, stack) {
      silentLog('knowledge_source_storage', '处理待处理知识源清理', error, stack);
    }
  });
}

Future<void> flushPendingKnowledgeSourceFileCleanups() {
  return _knowledgeSourceCleanupQueue.idle.timeout(
    _pendingKnowledgeSourceRetryTimeout,
  );
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
        throw StateError('待处理的知识源清理任务过多。');
      }
    }
    await txn.insert('app_settings', <String, Object?>{
      'key': markerKey,
      'value': jsonEncode(<String, String>{
        'source_id': entry.sourceId,
        'path': entry.path,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
}

Future<List<({DateTime createdAt, String sourceId, String path})>>
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
  final entries = <({DateTime createdAt, String sourceId, String path})>[];
  final latestAllowedTimestamp = DateTime.now().toUtc().add(
    _knowledgeSourceCleanupFutureClockTolerance,
  );
  for (final row in rows) {
    final markerKey = row['key'];
    try {
      final decoded = jsonDecode('${row['value']}');
      if (decoded is! Map) throw const FormatException('清理标记格式无效。');
      final sourceId = '${decoded['source_id'] ?? ''}'.trim();
      final path = p.absolute('${decoded['path'] ?? ''}'.trim());
      final createdAtText = '${decoded['created_at'] ?? ''}'.trim();
      final parsedCreatedAt = createdAtText.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.tryParse(createdAtText)?.toUtc();
      final createdAt =
          parsedCreatedAt != null &&
              parsedCreatedAt.isAfter(latestAllowedTimestamp)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : parsedCreatedAt;
      if (sourceId.isEmpty ||
          sourceId.length > _knowledgeSourceIdMaxCharacters ||
          createdAt == null ||
          markerKey != _cleanupMarkerKey(sourceId) ||
          !p.isWithin(root, path)) {
        throw const FormatException('清理标记字段无效。');
      }
      entries.add((createdAt: createdAt, sourceId: sourceId, path: path));
    } catch (error, stack) {
      silentLog('knowledge_source_storage', '解码待处理知识源清理', error, stack);
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
  final root = p.absolute(knowledgeManagedSourcesDirectoryPath);
  final candidate = p.absolute(path);
  if (!isPathWithinOrEqual(root, candidate)) {
    throw FileSystemException('拒绝删除托管目录外的知识源。', candidate);
  }
  final type = await FileSystemEntity.type(
    candidate,
    followLinks: false,
  ).timeout(_pendingKnowledgeSourceDeleteTimeout);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.link) {
    final isParentContained = await isPhysicalPathWithinOrEqual(
      root,
      p.dirname(candidate),
    ).timeout(_pendingKnowledgeSourceDeleteTimeout, onTimeout: () => false);
    if (!isParentContained) {
      throw FileSystemException('拒绝删除无效的托管知识源链接。', candidate);
    }
    await Link(
      candidate,
    ).delete().timeout(_pendingKnowledgeSourceDeleteTimeout);
    return;
  }
  if (type != FileSystemEntityType.file ||
      !await isPhysicalPathWithinOrEqual(
        root,
        candidate,
      ).timeout(_pendingKnowledgeSourceDeleteTimeout, onTimeout: () => false)) {
    throw FileSystemException('拒绝删除无效的托管知识源。', candidate);
  }
  await File(candidate).delete().timeout(_pendingKnowledgeSourceDeleteTimeout);
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
    throw ArgumentError.value(source.id, 'source.id', '知识源 ID 无效。');
  }
  final root = p.absolute(knowledgeManagedSourcesDirectoryPath);
  final path = p.absolute(source.storedPath.trim());
  if (!p.isWithin(root, path)) {
    throw FileSystemException('拒绝删除托管目录外的知识源。', path);
  }
  return (sourceId: sourceId, path: path);
}

String _cleanupMarkerKey(String sourceId) =>
    '$_pendingKnowledgeSourceCleanupSettingPrefix$sourceId';
