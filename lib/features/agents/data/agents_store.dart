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
  static const int _maxActivityEvents = 200;
  static const int _maxAuditEvents = 500;

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
      final source = stringKeyedMapFromValue(value);
      if (_listLength(source['activities']) > _maxActivityEvents ||
          _listLength(source['audit_events']) > _maxAuditEvents) {
        throw FormatException('第 $index 个智能体的事件数量超过上限。');
      }
      final agent = AgentProfile.fromJson(source);
      validateCanonicalJsonSubset(
        source,
        agent.toJson(),
        path: 'agents[$index]',
        requireMatchingScalarTypes: false,
      );
      final id = nullIfBlank(agent.id);
      if (id == null || id != agent.id || !seenIds.add(id)) {
        throw FormatException('第 $index 个智能体的 ID 无效。');
      }
      agents.add(agent);
    }
    return agents;
  }

  Future<void> save(List<AgentProfile> agents) async {
    if (agents.length > _maxAgents) {
      throw const FileSystemException('智能体数量超过存储上限。');
    }
    final file = File(_filePath);
    final content = prettyPrintJson(<String, Object?>{
      _rootKey: agents.map((agent) => agent.toJson()).toList(growable: false),
    });
    final output = '$content\n';
    if (utf8.encode(output).length > _maxStoreBytes) {
      throw const FileSystemException('智能体数据超过大小上限。');
    }
    await writeFileAtomically(file, output);
  }

  int _listLength(Object? value) => value is List ? value.length : 0;
}
