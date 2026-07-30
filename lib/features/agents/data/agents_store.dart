import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/agent_models.dart';

class AgentsStore {
  AgentsStore({String? filePath})
    : _filePath =
          filePath ??
          p.join(
            OpenHandPaths.defaultRootDirectoryPath(),
            'agents',
            'agents.json',
          );

  static const String _rootKey = 'agents';
  static const int _maxStoreBytes = 32 * kBytesPerMiB;
  static const int _maxAgents = 10000;

  final String _filePath;

  String get filePath => _filePath;

  Future<List<AgentProfile>> load() async {
    final file = File(_filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await regularFileExistsBounded(file)) {
      return const <AgentProfile>[];
    }
    final raw = await readBoundedFileString(file, maxBytes: _maxStoreBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('智能体存储根节点必须是 JSON 对象。');
    }
    final root = stringKeyedMapFromValue(decoded);
    if (root.length != 1 || !root.containsKey(_rootKey)) {
      throw const FormatException('智能体存储根节点包含不支持的字段。');
    }
    final rawAgents = root[_rootKey];
    if (rawAgents is! List) {
      throw const FormatException('智能体字段必须是 JSON 数组。');
    }
    if (rawAgents.length > _maxAgents) {
      throw const FormatException('智能体数量超过存储上限。');
    }
    final agents = <AgentProfile>[];
    final seenIds = <String>{};
    for (var index = 0; index < rawAgents.length; index++) {
      final value = rawAgents[index];
      if (value is! Map) {
        throw FormatException('第 $index 个智能体必须是对象。');
      }
      agents.add(_parseAgent(stringKeyedMapFromValue(value), index, seenIds));
    }
    return agents;
  }

  Future<void> save(List<AgentProfile> agents) async {
    if (agents.length > _maxAgents) {
      throw const FileSystemException('智能体数量超过存储上限。');
    }
    final file = File(_filePath);
    final serialized = <Map<String, Object?>>[];
    final seenIds = <String>{};
    try {
      for (var index = 0; index < agents.length; index++) {
        final source = agents[index].toJson();
        _parseAgent(source, index, seenIds);
        serialized.add(source);
      }
    } on FormatException catch (error) {
      throw FileSystemException('智能体数据无效：${error.message}', _filePath);
    }
    final content = prettyPrintJson(<String, Object?>{_rootKey: serialized});
    final output = utf8.encode('$content\n');
    if (output.length > _maxStoreBytes) {
      throw const FileSystemException('智能体数据超过大小上限。');
    }
    await writeBytesFileAtomically(file, output);
  }

  AgentProfile _parseAgent(
    Map<String, Object?> source,
    int index,
    Set<String> seenAgentIds,
  ) {
    final path = 'agents[$index]';
    validateCanonicalJsonSubset(source, source, path: path);
    if (_listLength(source['activities']) > agentStoredActivityEventLimit ||
        _listLength(source['audit_events']) > agentStoredAuditEventLimit) {
      throw FormatException('第 $index 个智能体的事件数量超过上限。');
    }
    final agent = AgentProfile.fromJson(source);
    validateCanonicalJsonSubset(
      source,
      agent.toJson(),
      path: path,
      requireMatchingScalarTypes: false,
    );
    _validateUniqueId(agent.id, '第 $index 个智能体', seenAgentIds);
    _validateItemIds(agent.tasks, '$path.tasks', (item) => item.id);
    _validateItemIds(agent.approvals, '$path.approvals', (item) => item.id);
    _validateItemIds(agent.activities, '$path.activities', (item) => item.id);
    _validateItemIds(
      agent.auditEvents,
      '$path.audit_events',
      (item) => item.id,
    );
    _validateItemIds(agent.kpis, '$path.kpis', (item) => item.id);
    _validateItemIds(agent.workers, '$path.workers', (item) => item.id);
    return agent;
  }

  void _validateItemIds<T>(
    List<T> items,
    String path,
    String Function(T item) idOf,
  ) {
    final seenIds = <String>{};
    for (var index = 0; index < items.length; index++) {
      _validateUniqueId(idOf(items[index]), '$path[$index]', seenIds);
    }
  }

  void _validateUniqueId(String value, String path, Set<String> seenIds) {
    final id = nullIfBlank(value);
    if (id == null || id != value || !seenIds.add(id)) {
      throw FormatException('$path 的 ID 无效或重复。');
    }
  }

  int _listLength(Object? value) => value is List ? value.length : 0;
}
