import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/web_gateway_runtime.dart';

const int webGatewayOpsMaxPersistedSnapshots = 720;
const int webGatewayOpsMaxPersistedLogs = 5000;
const int webGatewayOpsMaxCleanupHistory = 80;

class WebGatewayOpsStore {
  WebGatewayOpsStore({String? filePath})
    : filePath =
          filePath ??
          p.join(
            OpenHandPaths.defaultMessageGatewayDirectoryPath(),
            'web_gateway_ops_history.json',
          );

  static const String _snapshotsKey = 'snapshots';
  static const String _logsKey = 'logs';
  static const String _cleanupHistoryKey = 'cleanup_history';
  static const String _updatedAtKey = 'updated_at';
  static const int _maxStoreBytes = 32 * kBytesPerMiB;

  final String filePath;
  String? _expectedContent;
  bool _hasTrustedSnapshot = false;

  Future<WebGatewayOpsHistoryData> load() async {
    _hasTrustedSnapshot = false;
    final file = File(filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await regularFileExistsBounded(file)) {
      _expectedContent = null;
      _hasTrustedSnapshot = true;
      return const WebGatewayOpsHistoryData();
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxStoreBytes);
    final data = _decode(raw);
    _expectedContent = raw;
    _hasTrustedSnapshot = true;
    return data;
  }

  Future<void> save(WebGatewayOpsHistoryData data) async {
    if (!_hasTrustedSnapshot) {
      throw StateError('Web gateway ops history has no trusted snapshot.');
    }
    final file = File(filePath);
    await _verifySourceUnchanged(file);
    if (data.itemCount <= 0) {
      await deleteFileAtomically(file);
      _expectedContent = null;
      return;
    }
    final content = '${prettyPrintJson(data.toJson())}\n';
    if (utf8.encode(content).length > _maxStoreBytes) {
      throw const FileSystemException(
        'Web gateway ops history exceeds size limit.',
      );
    }
    await writeFileAtomically(file, content);
    _expectedContent = content;
  }

  Future<void> clear() async {
    await deleteFileAtomically(File(filePath));
    _expectedContent = null;
    _hasTrustedSnapshot = true;
  }

  Future<WebGatewayOpsPersistenceReport> measure() async {
    if (!_hasTrustedSnapshot) {
      throw StateError('Web gateway ops history has no trusted snapshot.');
    }
    final file = File(filePath);
    if (!await regularFileExistsBounded(file)) {
      if (_expectedContent != null) {
        throw StateError('Web gateway ops history was removed externally.');
      }
      return WebGatewayOpsPersistenceReport.empty;
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxStoreBytes);
    if (_expectedContent == null || raw != _expectedContent) {
      throw StateError('Web gateway ops history changed externally.');
    }
    return WebGatewayOpsPersistenceReport(
      bytes: utf8.encode(raw).length,
      itemCount: _decode(raw).itemCount,
    );
  }

  Future<int> measureBytesOnly() async {
    final file = File(filePath);
    if (!await regularFileExistsBounded(file)) return 0;
    return (await file.stat().timeout(defaultBoundedFileReadIdleTimeout)).size;
  }

  WebGatewayOpsHistoryData _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Web gateway ops root must be an object.');
    }
    final source = stringKeyedMapFromValue(decoded);
    _requireList(source, _snapshotsKey, webGatewayOpsMaxPersistedSnapshots);
    _requireList(source, _logsKey, webGatewayOpsMaxPersistedLogs);
    _requireList(source, _cleanupHistoryKey, webGatewayOpsMaxCleanupHistory);
    _requireTimestamp(source, _updatedAtKey, 'web_gateway_ops');
    _validateItems(source);
    final data = WebGatewayOpsHistoryData.fromJson(source);
    final canonical = data.toJson()..[_updatedAtKey] = source[_updatedAtKey];
    validateCanonicalJsonSubset(source, canonical, path: 'web_gateway_ops');
    return data;
  }

  void _validateItems(Map<String, Object?> source) {
    final snapshots = source[_snapshotsKey]! as List;
    for (var index = 0; index < snapshots.length; index++) {
      final path = 'web_gateway_ops.$_snapshotsKey[$index]';
      final item = _requireMap(snapshots[index], path);
      _requireFields(item, const <String>['timestamp', 'snapshot'], path);
      _requireTimestamp(item, 'timestamp', path);
      final snapshot = _requireMap(item['snapshot'], '$path.snapshot');
      _requireFields(snapshot, const <String>[
        'state',
        'started_at',
        'uptime_ms',
        'bound_url',
        'accessible_urls',
        'active_requests',
        'total_requests',
        'total_errors',
        'total_bytes_in',
        'total_bytes_out',
        'crash_count',
        'restart_count',
        'process',
        'open_session_count',
        'last_error',
      ], '$path.snapshot');
    }
    final logs = source[_logsKey]! as List;
    final logIds = <int>{};
    for (var index = 0; index < logs.length; index++) {
      final path = 'web_gateway_ops.$_logsKey[$index]';
      final item = _requireMap(logs[index], path);
      _requireFields(item, const <String>[
        'id',
        'timestamp',
        'level',
        'tag',
        'message',
      ], path);
      _requireTimestamp(item, 'timestamp', path);
      final id = item['id'];
      if (id is! int || id <= 0 || !logIds.add(id)) {
        throw FormatException('$path.id must be a unique positive integer.');
      }
    }
    final history = source[_cleanupHistoryKey]! as List;
    for (var index = 0; index < history.length; index++) {
      final path = 'web_gateway_ops.$_cleanupHistoryKey[$index]';
      final item = _requireMap(history[index], path);
      _requireFields(item, const <String>[
        'timestamp',
        'target',
        'expired_only',
        'deleted_files',
        'deleted_directories',
        'bytes_freed',
        'memory_log_entries_cleared',
      ], path);
      _requireTimestamp(item, 'timestamp', path);
    }
  }

  void _requireList(Map<String, Object?> source, String key, int maxItems) {
    final value = source[key];
    if (value is! List) {
      throw FormatException('web_gateway_ops.$key must be a list.');
    }
    if (value.length > maxItems) {
      throw FormatException('web_gateway_ops.$key exceeds item limit.');
    }
  }

  Map<String, Object?> _requireMap(Object? value, String path) {
    if (value is! Map) throw FormatException('$path must be an object.');
    return stringKeyedMapFromValue(value);
  }

  void _requireFields(
    Map<String, Object?> source,
    List<String> fields,
    String path,
  ) {
    for (final field in fields) {
      if (!source.containsKey(field)) {
        throw FormatException('$path is missing $field.');
      }
    }
  }

  void _requireTimestamp(Map<String, Object?> source, String key, String path) {
    final value = source[key];
    if (value is! String || DateTime.tryParse(value) == null) {
      throw FormatException('$path.$key must be an ISO-8601 timestamp.');
    }
  }

  Future<void> _verifySourceUnchanged(File file) async {
    final exists = await regularFileExistsBounded(file);
    if (_expectedContent == null) {
      if (exists) {
        throw StateError('Web gateway ops history changed externally.');
      }
      return;
    }
    if (!exists) {
      throw StateError('Web gateway ops history was removed externally.');
    }
    final current = await readBoundedFileString(file, maxBytes: _maxStoreBytes);
    if (current != _expectedContent) {
      throw StateError('Web gateway ops history changed externally.');
    }
  }

  static Map<String, Object?> rootJson({
    required List<Map<String, Object?>> snapshots,
    required List<Map<String, Object?>> logs,
    required List<Map<String, Object?>> cleanupHistory,
  }) {
    return <String, Object?>{
      _snapshotsKey: snapshots,
      _logsKey: logs,
      _cleanupHistoryKey: cleanupHistory,
      _updatedAtKey: DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class WebGatewayOpsHistoryData {
  const WebGatewayOpsHistoryData({
    this.snapshots = const <WebGatewayOpsSnapshotRecord>[],
    this.logs = const <WebGatewayLogEntry>[],
    this.cleanupHistory = const <WebGatewayCleanupResult>[],
  });

  final List<WebGatewayOpsSnapshotRecord> snapshots;
  final List<WebGatewayLogEntry> logs;
  final List<WebGatewayCleanupResult> cleanupHistory;

  int get itemCount => snapshots.length + logs.length + cleanupHistory.length;

  Map<String, Object?> toJson() {
    return WebGatewayOpsStore.rootJson(
      snapshots: snapshots.map((item) => item.toJson()).toList(growable: false),
      logs: logs.map((item) => item.toJson()).toList(growable: false),
      cleanupHistory: cleanupHistory
          .map((item) => item.toJson())
          .toList(growable: false),
    );
  }

  static WebGatewayOpsHistoryData fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return WebGatewayOpsHistoryData(
      snapshots: stringKeyedMapListFromValue(
        map['snapshots'],
      ).map(WebGatewayOpsSnapshotRecord.fromJson).toList(growable: false),
      logs: stringKeyedMapListFromValue(
        map['logs'],
      ).map(WebGatewayLogEntry.fromJson).toList(growable: false),
      cleanupHistory: stringKeyedMapListFromValue(
        map['cleanup_history'],
      ).map(WebGatewayCleanupResult.fromJson).toList(growable: false),
    );
  }
}

class WebGatewayOpsSnapshotRecord {
  const WebGatewayOpsSnapshotRecord({
    required this.timestamp,
    required this.snapshot,
  });

  final DateTime timestamp;
  final WebGatewayRuntimeSnapshot snapshot;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'snapshot': snapshot.toJson(),
    };
  }

  static WebGatewayOpsSnapshotRecord fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return WebGatewayOpsSnapshotRecord(
      timestamp:
          utcDateTimeFromValue(map['timestamp']) ?? DateTime.now().toUtc(),
      snapshot: WebGatewayRuntimeSnapshot.fromJson(map['snapshot']),
    );
  }
}

class WebGatewayOpsPersistenceReport {
  const WebGatewayOpsPersistenceReport({
    required this.bytes,
    required this.itemCount,
  });

  final int bytes;
  final int itemCount;

  static const WebGatewayOpsPersistenceReport empty =
      WebGatewayOpsPersistenceReport(bytes: 0, itemCount: 0);
}
