import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/db/atomic_file_operations.dart';
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

  final String _filePath;

  String get filePath => _filePath;

  Future<List<AgentProfile>> load() async {
    final file = File(_filePath);
    await recoverAtomicWriteBackupIfNeeded(file);
    if (!await file.exists()) {
      await save(const <AgentProfile>[]);
      return const <AgentProfile>[];
    }
    final raw = await file.readAsString();
    final decoded = optionalStringKeyedMapFromJsonText(raw);
    if (decoded == null) {
      final backup = File(
        '$_filePath.invalid.${DateTime.now().millisecondsSinceEpoch}',
      );
      await file.rename(backup.path);
      await save(const <AgentProfile>[]);
      return const <AgentProfile>[];
    }
    final rawAgents = decoded[_rootKey];
    if (rawAgents is! List) {
      await save(const <AgentProfile>[]);
      return const <AgentProfile>[];
    }
    final agents = rawAgents
        .map(AgentProfile.fromJson)
        .where((agent) => nullIfBlank(agent.id) != null)
        .toList(growable: false);
    return agents;
  }

  Future<void> save(List<AgentProfile> agents) async {
    final file = File(_filePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final content = const JsonEncoder.withIndent('  ').convert(
      <String, Object?>{
        _rootKey: agents.map((agent) => agent.toJson()).toList(growable: false),
      },
    );
    await writeFileAtomically(file, '$content\n');
  }
}
