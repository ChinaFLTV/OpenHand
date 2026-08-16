import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import 'harness_role_config.dart';

const int kHarnessTaskMaxCharacters = 256 * kBytesPerKiB;
const int kHarnessPathMaxCharacters = 4 * kBytesPerKiB;

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
      task: clipTextByCodeUnits(
        '${json['task'] ?? ''}',
        kHarnessTaskMaxCharacters,
        suffix: '',
      ),
      workingDirectory: clipTextByCodeUnits(
        '${json['working_directory'] ?? ''}',
        kHarnessPathMaxCharacters,
        suffix: '',
      ),
      persistenceDirectory: clipTextByCodeUnits(
        '${json['persistence_directory'] ?? ''}',
        kHarnessPathMaxCharacters,
        suffix: '',
      ),
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

  /// 初始化持久化目录结构。
  Future<void> initializePersistenceDirectories() async {
    final dirs = [
      p.join(persistenceDirectory, 'steering', 'handoff'),
      p.join(persistenceDirectory, 'steering', 'lesson'),
      p.join(persistenceDirectory, 'steering', 'feedback'),
      p.join(persistenceDirectory, 'steering', 'plan'),
      p.join(persistenceDirectory, 'steering', 'meta'),
    ];
    await Future.wait<Directory>(
      dirs.map((dirPath) => createDirectoryBounded(Directory(dirPath))),
    );
    // 保存配置，供后续会话复用。
    final configFile = File(
      p.join(persistenceDirectory, 'steering', 'meta', 'harness_config.json'),
    );
    await writeFileAtomically(configFile, prettyPrintJson(toJson()));
  }

  /// 元信息文件缺失时返回 true，表示当前上下文需先执行分析阶段。
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
