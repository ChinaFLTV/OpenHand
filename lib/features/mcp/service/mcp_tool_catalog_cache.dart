import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/stable_hash.dart';
import '../model/mcp_server.dart';
import '../model/mcp_tool.dart';

class McpCachedToolCatalog {
  const McpCachedToolCatalog({
    required this.connectionSignature,
    required this.catalog,
  });

  final String connectionSignature;
  final McpToolCatalog catalog;
}

String mcpServerConnectionSignature(McpServer server) {
  return stableJsonSha256(<String, Object?>{
    'type': server.type.storageValue,
    'url': server.url.trim(),
    'command': server.command.trim(),
    'args': server.args,
    'headers': server.headers,
    'environment': server.environment,
    'extra_fields': server.extraFields,
  });
}

String mcpToolCatalogContentSignature(McpToolCatalog catalog) {
  return stableJsonSha256(_catalogToJson(catalog));
}

class McpToolCatalogCacheService {
  McpToolCatalogCacheService({
    Directory? storageDir,
    int maxPersistedBytes = _defaultMaxPersistedBytes,
  }) : _storageDir =
           storageDir ?? Directory(OpenHandPaths.defaultMcpDirectoryPath()),
       _maxPersistedBytes = maxPersistedBytes {
    requirePositiveIntAtMost(
      maxPersistedBytes,
      _maxAllowedPersistedBytes,
      'maxPersistedBytes',
    );
  }

  static const String _fileName = 'tool_catalog_cache.json';
  static const int _defaultMaxPersistedBytes = 32 * kBytesPerMiB;
  static const int _maxAllowedPersistedBytes = 256 * kBytesPerMiB;

  final Directory _storageDir;
  final int _maxPersistedBytes;
  final SerialTaskQueue _queue = SerialTaskQueue();
  Map<String, McpCachedToolCatalog>? _snapshot;
  bool _storageRecovered = false;

  File get _file => File(p.join(_storageDir.path, _fileName));

  Future<Map<String, McpCachedToolCatalog>> load() {
    return _queue.enqueue(() async {
      final loaded = await _loadFromDisk();
      _snapshot = loaded;
      return Map<String, McpCachedToolCatalog>.unmodifiable(loaded);
    });
  }

  Future<void> replace({
    required McpServer server,
    required McpToolCatalog catalog,
  }) {
    if (catalog.status != McpToolCatalogStatus.ready || !catalog.isComplete) {
      return Future<void>.value();
    }
    return _queue.enqueue(() async {
      final current = Map<String, McpCachedToolCatalog>.from(
        _snapshot ?? await _loadFromDisk(),
      );
      current[server.name] = McpCachedToolCatalog(
        connectionSignature: mcpServerConnectionSignature(server),
        catalog: catalog,
      );
      await _persist(current);
      _snapshot = current;
    });
  }

  Future<void> remove(Iterable<String> serverNames) {
    final normalizedNames = serverNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (normalizedNames.isEmpty) return Future<void>.value();
    return _queue.enqueue(() async {
      final current = Map<String, McpCachedToolCatalog>.from(
        _snapshot ?? await _loadFromDisk(),
      );
      var removed = false;
      for (final name in normalizedNames) {
        removed = current.remove(name) != null || removed;
      }
      if (!removed) return;
      await _persist(current);
      _snapshot = current;
    });
  }

  Future<void> flush() => _queue.idle;

  Future<Map<String, McpCachedToolCatalog>> _loadFromDisk() async {
    try {
      if (!_storageRecovered) {
        await recoverAtomicWriteBackupIfNeeded(_file);
        _storageRecovered = true;
      }
      if (!await regularFileExistsBounded(_file)) {
        return <String, McpCachedToolCatalog>{};
      }
      final raw = await readBoundedFileString(
        _file,
        maxBytes: _maxPersistedBytes,
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, McpCachedToolCatalog>{};
      final root = stringKeyedMapFromValue(decoded);
      final entries = stringKeyedMapFromValue(root['catalogs']);
      if (entries.length > kMcpMaxServerCount) {
        throw const FormatException('MCP 工具目录缓存的服务数量超过安全上限。');
      }
      final result = <String, McpCachedToolCatalog>{};
      for (final entry in entries.entries) {
        final parsed = _entryFromJson(entry.value);
        if (parsed != null) result[entry.key] = parsed;
      }
      return result;
    } catch (error, stack) {
      silentLog('mcp_tool_catalog_cache', '加载工具目录缓存', error, stack);
      return <String, McpCachedToolCatalog>{};
    }
  }

  Future<void> _persist(Map<String, McpCachedToolCatalog> entries) async {
    if (entries.length > kMcpMaxServerCount ||
        entries.values.any(
          (entry) => entry.catalog.tools.length > kMcpMaxCatalogToolCount,
        )) {
      throw StateError('MCP 工具目录缓存超过条目上限。');
    }
    final content = jsonEncode(<String, Object?>{
      'version': 1,
      'catalogs': <String, Object?>{
        for (final entry in entries.entries)
          entry.key: _entryToJson(entry.value),
      },
    });
    if (utf8.encode(content).length + 1 > _maxPersistedBytes) {
      throw StateError('MCP 工具目录缓存超过持久化大小上限。');
    }
    await writeFileAtomically(_file, '$content\n');
  }
}

Map<String, Object?> _entryToJson(McpCachedToolCatalog entry) {
  final catalog = entry.catalog;
  return <String, Object?>{
    'connection_signature': entry.connectionSignature,
    ..._catalogToJson(catalog),
    if (catalog.lastScannedAt != null)
      'last_scanned_at': catalog.lastScannedAt!.toUtc().toIso8601String(),
  };
}

Map<String, Object?> _catalogToJson(
  McpToolCatalog catalog,
) => <String, Object?>{
  'tools': catalog.tools.map(_toolToJson).toList(growable: false),
  if (catalog.warningMessage != null) 'warning_message': catalog.warningMessage,
  if (catalog.serverInstructions.isNotEmpty)
    'server_instructions': catalog.serverInstructions,
};

McpCachedToolCatalog? _entryFromJson(Object? raw) {
  final map = stringKeyedMapFromValue(raw);
  final signature = '${map['connection_signature'] ?? ''}'.trim();
  if (signature.isEmpty || map['tools'] is! List) return null;
  final serverInstructions = '${map['server_instructions'] ?? ''}';
  if (serverInstructions.length > kMcpMaxServerInstructionsCodeUnits) {
    return null;
  }
  final rawTools = map['tools'] as List;
  if (rawTools.length > kMcpMaxCatalogToolCount) return null;
  final tools = <McpTool>[];
  final toolIds = <String>{};
  for (final rawTool in rawTools) {
    final tool = _toolFromJson(rawTool);
    if (tool == null || !toolIds.add(tool.id)) return null;
    tools.add(tool);
  }
  return McpCachedToolCatalog(
    connectionSignature: signature,
    catalog: McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: List<McpTool>.unmodifiable(tools),
      warningMessage: nullIfBlank('${map['warning_message'] ?? ''}'),
      serverInstructions: serverInstructions,
      lastScannedAt: dateTimeFromValue(map['last_scanned_at'])?.toUtc(),
    ),
  );
}

Map<String, Object?> _toolToJson(McpTool tool) => <String, Object?>{
  'id': tool.id,
  'name': tool.name,
  'description': tool.description,
  'input_schema': tool.inputSchema,
  if (tool.outputSchema != null) 'output_schema': tool.outputSchema,
  if (tool.outputDescription != null)
    'output_description': tool.outputDescription,
  'output_description_inferred': tool.outputDescriptionIsInferred,
  'annotations': tool.annotations,
  'execution': tool.execution,
  if (tool.rawInputSchema != null) 'raw_input_schema': tool.rawInputSchema,
  if (tool.rawOutputSchema != null) 'raw_output_schema': tool.rawOutputSchema,
  'raw_metadata': tool.rawMetadata,
  if (tool.metadataWarning != null) 'metadata_warning': tool.metadataWarning,
};

McpTool? _toolFromJson(Object? raw) {
  final map = stringKeyedMapFromValue(raw);
  final rawId = map['id'];
  final rawName = map['name'];
  if (rawId is! String || rawName is! String) return null;
  final id = rawId.trim();
  final name = rawName.trim();
  if (id.isEmpty ||
      id.length > kMcpMaxToolIdCodeUnits ||
      name.isEmpty ||
      measureMcpToolMetadata(map) == null) {
    return null;
  }
  final outputSchema = map['output_schema'] is Map
      ? stringKeyedMapFromValue(map['output_schema'])
      : null;
  return McpTool(
    id: id,
    name: name,
    description: '${map['description'] ?? ''}',
    inputSchema: map['input_schema'] is Map
        ? stringKeyedMapFromValue(map['input_schema'])
        : const <String, Object?>{'type': 'object'},
    outputSchema: outputSchema,
    outputDescription: nullIfBlank('${map['output_description'] ?? ''}'),
    outputDescriptionIsInferred: boolFromValue(
      map['output_description_inferred'],
    ),
    annotations: stringKeyedMapFromValue(map['annotations']),
    execution: stringKeyedMapFromValue(map['execution']),
    rawInputSchema: map['raw_input_schema'],
    rawOutputSchema: map['raw_output_schema'],
    rawMetadata: stringKeyedMapFromValue(map['raw_metadata']),
    metadataWarning: nullIfBlank('${map['metadata_warning'] ?? ''}'),
  );
}
