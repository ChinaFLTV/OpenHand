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
      throw const FormatException('Agents root must be a JSON object.');
    }
    final root = stringKeyedMapFromValue(decoded);
    if (root.length != 1 || !root.containsKey(_rootKey)) {
      throw const FormatException('Agents root contains unsupported fields.');
    }
    final rawAgents = root[_rootKey];
    if (rawAgents is! List) {
      throw const FormatException('Agents field must be a JSON array.');
    }
    final agents = <AgentProfile>[];
    final seenIds = <String>{};
    for (var index = 0; index < rawAgents.length; index++) {
      final value = rawAgents[index];
      if (value is! Map) {
        throw FormatException('Agent at index $index must be an object.');
      }
      final source = stringKeyedMapFromValue(value);
      if (_listLength(source['activities']) > _maxActivityEvents ||
          _listLength(source['audit_events']) > _maxAuditEvents) {
        throw FormatException('Agent at index $index exceeds event limits.');
      }
      final agent = AgentProfile.fromJson(source);
      _validateCanonicalFields(source, agent.toJson(), 'agents[$index]');
      final id = nullIfBlank(agent.id);
      if (id == null || id != agent.id || !seenIds.add(id)) {
        throw FormatException('Agent at index $index has an invalid id.');
      }
      agents.add(agent);
    }
    return agents;
  }

  Future<void> save(List<AgentProfile> agents) async {
    final file = File(_filePath);
    final content = prettyPrintJson(<String, Object?>{
      _rootKey: agents.map((agent) => agent.toJson()).toList(growable: false),
    });
    final output = '$content\n';
    if (utf8.encode(output).length > _maxStoreBytes) {
      throw const FileSystemException('Agents data exceeds the size limit.');
    }
    await writeFileAtomically(file, output);
  }

  int _listLength(Object? value) => value is List ? value.length : 0;

  void _validateCanonicalFields(
    Object? source,
    Object? canonical,
    String path,
  ) {
    if (source is Map) {
      if (canonical is! Map) {
        throw FormatException('$path must be an object.');
      }
      for (final entry in source.entries) {
        final key = '${entry.key}';
        if (!canonical.containsKey(key)) {
          throw FormatException('$path contains unsupported field $key.');
        }
        _validateCanonicalFields(entry.value, canonical[key], '$path.$key');
      }
      return;
    }
    if (source is List) {
      if (canonical is! List || canonical.length != source.length) {
        throw FormatException('$path contains invalid items.');
      }
      for (var index = 0; index < source.length; index++) {
        _validateCanonicalFields(
          source[index],
          canonical[index],
          '$path[$index]',
        );
      }
      return;
    }
    if (source != canonical) {
      throw FormatException('$path contains an invalid value.');
    }
  }
}
