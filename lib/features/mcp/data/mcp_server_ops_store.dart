import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../model/mcp_server_ops.dart';

class McpServerOpsStore {
  McpServerOpsStore({required String storageDirectoryPath})
    : _filePath = p.join(storageDirectoryPath, 'mcp_server_ops.json');

  static const String _configKey = 'config';
  static const String _runtimeKey = 'runtime';
  static const String _updatedAtKey = 'updated_at';
  static const int _maxStoreBytes = 16 * kBytesPerMiB;

  final String _filePath;
  final SerialTaskQueue _writeQueue = SerialTaskQueue();

  String get filePath => _filePath;

  Future<McpOpsConfig> loadConfig() async {
    final decoded = await _readRoot();
    if (decoded == null) {
      const config = McpOpsConfig();
      await saveConfig(config);
      return config;
    }
    return McpOpsConfig.fromJson(decoded[_configKey]);
  }

  Future<void> saveConfig(McpOpsConfig config) async {
    await _enqueueWrite(() async {
      final decoded = await _readRoot() ?? const <String, Object?>{};
      final next = <String, Object?>{
        ...decoded,
        _configKey: config.toJson(),
        _updatedAtKey: DateTime.now().toUtc().toIso8601String(),
      };
      await _writeRoot(next);
    });
  }

  Future<McpOpsPersistedRuntimeData> loadRuntimeData() async {
    final decoded = await _readRoot();
    if (decoded == null) {
      return const McpOpsPersistedRuntimeData();
    }
    return McpOpsPersistedRuntimeData.fromJson(decoded[_runtimeKey]);
  }

  Future<void> saveRuntimeData(McpOpsPersistedRuntimeData data) async {
    await _enqueueWrite(() async {
      final decoded = await _readRoot() ?? const <String, Object?>{};
      final config = McpOpsConfig.fromJson(decoded[_configKey]);
      final next = <String, Object?>{
        ...decoded,
        _configKey: config.toJson(),
        _runtimeKey: data.toJson(),
        _updatedAtKey: DateTime.now().toUtc().toIso8601String(),
      };
      await _writeRoot(next);
    });
  }

  Future<McpOpsPersistenceReport> measureRuntimeData() async {
    final data = await loadRuntimeData();
    if (data.itemCount <= 0) {
      return McpOpsPersistenceReport.empty;
    }
    final bytes = prettyPrintJson(data.toJson()).length;
    return McpOpsPersistenceReport(bytes: bytes, itemCount: data.itemCount);
  }

  Future<void> clearRuntimeData() async {
    await _enqueueWrite(() async {
      final decoded = await _readRoot() ?? const <String, Object?>{};
      final config = McpOpsConfig.fromJson(decoded[_configKey]);
      final next = <String, Object?>{
        ...decoded,
        _configKey: config.toJson(),
        _runtimeKey: const McpOpsPersistedRuntimeData().toJson(),
        _updatedAtKey: DateTime.now().toUtc().toIso8601String(),
      };
      await _writeRoot(next);
    });
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() task) {
    return _writeQueue.enqueue(task);
  }

  Future<Map<String, Object?>?> _readRoot() async {
    final file = File(_filePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await file.exists()) {
      return null;
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxStoreBytes);
    return optionalStringKeyedMapFromJsonText(raw);
  }

  Future<void> _writeRoot(Map<String, Object?> root) async {
    final file = File(_filePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final content = prettyPrintJson(root);
    await writeFileAtomically(file, content);
  }
}
