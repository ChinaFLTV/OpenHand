import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/input_value_parsing.dart';
import 'harness_role_config.dart';

class HarnessSessionConfig {
  const HarnessSessionConfig({
    required this.task,
    required this.workingDirectory,
    required this.persistenceDirectory,
    required this.profilerConfig,
    required this.readerConfig,
    required this.plannerConfig,
    required this.implementerConfig,
    required this.reviewerConfig,
  });

  final String task;
  final String workingDirectory;
  final String persistenceDirectory;
  final HarnessRoleConfig profilerConfig;
  final HarnessRoleConfig readerConfig;
  final HarnessRoleConfig plannerConfig;
  final HarnessRoleConfig implementerConfig;
  final HarnessRoleConfig reviewerConfig;

  HarnessSessionConfig copyWith({
    String? task,
    String? workingDirectory,
    String? persistenceDirectory,
    HarnessRoleConfig? profilerConfig,
    HarnessRoleConfig? readerConfig,
    HarnessRoleConfig? plannerConfig,
    HarnessRoleConfig? implementerConfig,
    HarnessRoleConfig? reviewerConfig,
  }) {
    return HarnessSessionConfig(
      task: task ?? this.task,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      persistenceDirectory: persistenceDirectory ?? this.persistenceDirectory,
      profilerConfig: profilerConfig ?? this.profilerConfig,
      readerConfig: readerConfig ?? this.readerConfig,
      plannerConfig: plannerConfig ?? this.plannerConfig,
      implementerConfig: implementerConfig ?? this.implementerConfig,
      reviewerConfig: reviewerConfig ?? this.reviewerConfig,
    );
  }

  Map<String, Object?> toJson() => {
    'task': task,
    'working_directory': workingDirectory,
    'persistence_directory': persistenceDirectory,
    'profiler': profilerConfig.toJson(),
    'reader': readerConfig.toJson(),
    'planner': plannerConfig.toJson(),
    'implementer': implementerConfig.toJson(),
    'reviewer': reviewerConfig.toJson(),
  };

  static HarnessSessionConfig fromJson(Map<String, Object?> json) {
    return HarnessSessionConfig(
      task: '${json['task'] ?? ''}',
      workingDirectory: '${json['working_directory'] ?? ''}',
      persistenceDirectory: '${json['persistence_directory'] ?? ''}',
      profilerConfig: HarnessRoleConfig.fromJson(_requireMap(json['profiler'])),
      readerConfig: HarnessRoleConfig.fromJson(_requireMap(json['reader'])),
      plannerConfig: HarnessRoleConfig.fromJson(_requireMap(json['planner'])),
      implementerConfig: HarnessRoleConfig.fromJson(
        _requireMap(json['implementer']),
      ),
      reviewerConfig: HarnessRoleConfig.fromJson(_requireMap(json['reviewer'])),
    );
  }

  static Map<String, Object?> _requireMap(Object? value) {
    return stringKeyedMapFromValue(value);
  }

  /// Initializes the persistence directory structure.
  Future<void> initializePersistenceDirectories() async {
    final dirs = [
      p.join(persistenceDirectory, 'steering', 'handoff'),
      p.join(persistenceDirectory, 'steering', 'lesson'),
      p.join(persistenceDirectory, 'steering', 'feedback'),
      p.join(persistenceDirectory, 'steering', 'plan'),
      p.join(persistenceDirectory, 'steering', 'meta'),
    ];
    for (final dirPath in dirs) {
      await Directory(dirPath).create(recursive: true);
    }
    // Persist config itself for future reference
    final configFile = File(
      p.join(persistenceDirectory, 'steering', 'meta', 'harness_config.json'),
    );
    await writeFileAtomically(configFile, prettyPrintJson(toJson()));
  }

  /// Returns true if meta files (architecture.md / conventions.md) are missing,
  /// indicating a first-run in this context (profiler phase required).
  Future<bool> isFirstRun() async {
    final metaDirectory = p.join(persistenceDirectory, 'steering', 'meta');
    final results = await Future.wait<bool>(<Future<bool>>[
      isRegularFilePath(
        p.join(metaDirectory, 'architecture.md'),
        followLinks: true,
      ),
      isRegularFilePath(
        p.join(metaDirectory, 'conventions.md'),
        followLinks: true,
      ),
    ]);
    return results.any((exists) => !exists);
  }
}
