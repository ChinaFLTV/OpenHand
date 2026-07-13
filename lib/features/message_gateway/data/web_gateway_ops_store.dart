import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
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

  Future<WebGatewayOpsHistoryData> load() async {
    final file = File(filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await file.exists()) {
      return const WebGatewayOpsHistoryData();
    }
    try {
      final decoded = optionalStringKeyedMapFromJsonText(
        await readBoundedFileString(file, maxBytes: _maxStoreBytes),
      );
      if (decoded == null) {
        return const WebGatewayOpsHistoryData();
      }
      return WebGatewayOpsHistoryData.fromJson(decoded);
    } catch (error, stack) {
      silentLog('web_gateway_ops_store', 'load', error, stack);
      return const WebGatewayOpsHistoryData();
    }
  }

  Future<void> save(WebGatewayOpsHistoryData data) async {
    final file = File(filePath);
    try {
      if (data.itemCount <= 0) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }
      await file.parent.create(recursive: true);
      await writeFileAtomically(file, '${prettyPrintJson(data.toJson())}\n');
    } catch (error, stack) {
      silentLog('web_gateway_ops_store', 'save', error, stack);
      rethrow;
    }
  }

  Future<WebGatewayOpsPersistenceReport> measure() async {
    final file = File(filePath);
    if (!await file.exists()) {
      return WebGatewayOpsPersistenceReport.empty;
    }
    try {
      final stat = await file.stat();
      final data = await load();
      return WebGatewayOpsPersistenceReport(
        bytes: stat.size,
        itemCount: data.itemCount,
      );
    } catch (error, stack) {
      silentLog('web_gateway_ops_store', 'measure', error, stack);
      return WebGatewayOpsPersistenceReport.empty;
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

  int estimateBytes() {
    return utf8.encode(prettyPrintJson(toJson())).length;
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
