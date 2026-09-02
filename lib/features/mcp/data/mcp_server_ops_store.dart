import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/text_clip.dart';
import '../model/mcp_server_ops.dart';

class McpServerOpsStore {
  McpServerOpsStore({required String storageDirectoryPath})
    : _filePath = p.join(storageDirectoryPath, 'mcp_server_ops.json');

  static const String _configKey = 'config';
  static const String _runtimeKey = 'runtime';
  static const String _updatedAtKey = 'updated_at';
  static const int _maxStoreBytes = 16 * kBytesPerMiB;
  static const int _maxConfigCollectionItems = 4096;
  static const int _maxJsonNodes = 131072;

  final String _filePath;
  final SerialTaskQueue _writeQueue = SerialTaskQueue();

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
    if (data.auditEntries.length > mcpOpsMaxPersistedAuditEntries) {
      throw const FormatException('MCP 运维审计记录超过安全上限。');
    }
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
    final bytes = utf8ByteLength(prettyPrintJson(data.toJson()));
    return McpOpsPersistenceReport(bytes: bytes, itemCount: data.itemCount);
  }

  Future<void> flush() => _writeQueue.idle;

  Future<T> _enqueueWrite<T>(Future<T> Function() task) {
    return _writeQueue.enqueue(task);
  }

  Future<Map<String, Object?>?> _readRoot() async {
    final file = File(_filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await regularFileExistsBounded(file)) {
      return null;
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxStoreBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('MCP 运维存储根节点必须为对象。');
    }
    final root = stringKeyedMapFromValue(decoded);
    validateCanonicalJsonSubset(
      root,
      root,
      path: 'MCP 运维存储',
      maxDepth: 32,
      maxContainerItems: _maxConfigCollectionItems,
      maxTotalNodes: _maxJsonNodes,
    );
    _validateCollections(root);
    return root;
  }

  Future<void> _writeRoot(Map<String, Object?> root) async {
    final file = File(_filePath);
    validateCanonicalJsonSubset(
      root,
      root,
      path: 'MCP 运维存储',
      maxDepth: 32,
      maxContainerItems: _maxConfigCollectionItems,
      maxTotalNodes: _maxJsonNodes,
    );
    _validateCollections(root);
    final content = prettyPrintJson(root);
    if (utf8ByteLength(content) > _maxStoreBytes) {
      throw const FileSystemException('MCP 运维存储超过大小上限。');
    }
    await writeFileAtomically(file, content);
  }

  void _validateCollections(Map<String, Object?> root) {
    final config = _optionalMap(root[_configKey], 'MCP 运维配置');
    if (config != null) {
      for (final key in const <String>[
        'allowed_clients',
        'allowed_ip_cidrs',
        'allowed_time_windows',
        'exposed_surfaces',
        'hidden_item_ids',
        'hidden_endpoint_ids',
      ]) {
        _validateList(
          config[key],
          path: 'MCP 运维配置.$key',
          maxItems: _maxConfigCollectionItems,
          requireTextItems: true,
        );
      }
    }

    final runtime = _optionalMap(root[_runtimeKey], 'MCP 运维运行数据');
    if (runtime == null) return;
    _validateList(
      runtime['audit_entries'],
      path: 'MCP 运维运行数据.audit_entries',
      maxItems: mcpOpsMaxPersistedAuditEntries,
      requireMapItems: true,
    );
    final snapshot = _optionalMap(runtime['snapshot'], 'MCP 运维运行数据.snapshot');
    if (snapshot == null) return;
    _validateList(
      snapshot['traffic_series'],
      path: 'MCP 运维运行数据.snapshot.traffic_series',
      maxItems: mcpOpsTrafficWindowMinutes,
      requireMapItems: true,
    );
    for (final key in const <String>[
      'ip_distribution',
      'client_distribution',
      'request_distribution',
      'protocol_distribution',
    ]) {
      final distribution = _optionalMap(
        snapshot[key],
        'MCP 运维运行数据.snapshot.$key',
      );
      if (distribution != null &&
          distribution.length > mcpOpsMaxMetricDistributionKeys) {
        throw FormatException('MCP 运维运行数据.snapshot.$key 超过安全上限。');
      }
    }
  }

  Map<String, Object?>? _optionalMap(Object? value, String path) {
    if (value == null) return null;
    if (value is! Map) throw FormatException('$path 必须为对象。');
    return stringKeyedMapFromValue(value);
  }

  void _validateList(
    Object? value, {
    required String path,
    required int maxItems,
    bool requireTextItems = false,
    bool requireMapItems = false,
  }) {
    if (value == null) return;
    if (value is! List ||
        value.length > maxItems ||
        (requireTextItems && value.any((item) => item is! String)) ||
        (requireMapItems && value.any((item) => item is! Map))) {
      throw FormatException('$path 无效或超过安全上限。');
    }
  }
}
