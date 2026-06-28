import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/util/input_value_parsing.dart';
import '../service/hardness_cli_catalog.dart';
import 'hardness_role_config.dart';

class HardnessSessionConfig {
  const HardnessSessionConfig({
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
  final HardnessRoleConfig profilerConfig;
  final HardnessRoleConfig readerConfig;
  final HardnessRoleConfig plannerConfig;
  final HardnessRoleConfig implementerConfig;
  final HardnessRoleConfig reviewerConfig;

  HardnessSessionConfig copyWith({
    String? task,
    String? workingDirectory,
    String? persistenceDirectory,
    HardnessRoleConfig? profilerConfig,
    HardnessRoleConfig? readerConfig,
    HardnessRoleConfig? plannerConfig,
    HardnessRoleConfig? implementerConfig,
    HardnessRoleConfig? reviewerConfig,
  }) {
    return HardnessSessionConfig(
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

  static HardnessSessionConfig fromJson(Map<String, Object?> json) {
    return HardnessSessionConfig(
      task: '${json['task'] ?? ''}',
      workingDirectory: '${json['working_directory'] ?? ''}',
      persistenceDirectory: '${json['persistence_directory'] ?? ''}',
      profilerConfig: HardnessRoleConfig.fromJson(
        _requireMap(json['profiler']),
      ),
      readerConfig: HardnessRoleConfig.fromJson(_requireMap(json['reader'])),
      plannerConfig: HardnessRoleConfig.fromJson(_requireMap(json['planner'])),
      implementerConfig: HardnessRoleConfig.fromJson(
        _requireMap(json['implementer']),
      ),
      reviewerConfig: HardnessRoleConfig.fromJson(
        _requireMap(json['reviewer']),
      ),
    );
  }

  static Map<String, Object?> _requireMap(Object? value) {
    return stringKeyedMapFromValue(value);
  }

  /// Looks up the CLI executable binary name from the catalog by display name.
  /// Falls back to the first word of the name lowercased if not found.
  static String _executableFor(String cliName) {
    for (final c in kHardnessCliCatalog) {
      if (c.name == cliName) return c.executable;
    }
    // Fallback: lowercase first token
    final first = cliName.split(' ').first.toLowerCase();
    return first.isEmpty ? cliName : first;
  }

  /// Builds the initial user message that seeds the HE session with config.
  /// Includes the CLI executable explicitly so the orchestrator never guesses.
  String toInitialPrompt() {
    String fmt(HardnessRoleConfig cfg, String roleZh, String roleEn) {
      if (cfg.isUrlMode) {
        return '- $roleZh($roleEn)：模式=URL/API, 模型配置ID=${cfg.aiModelConfigId ?? '(未配置)'}';
      }
      final exe = _executableFor(cfg.cliName);
      final cli = findHardnessCliByName(cfg.cliName);
      final modelLabel = describeHardnessCliModel(cli, cfg.modelId, isZh: true);
      return '- $roleZh($roleEn)：CLI名称=${cfg.cliName}, 可执行文件=$exe, 模型=$modelLabel';
    }

    final roleLines = <String>[
      fmt(profilerConfig, '探档者', 'profiler'),
      fmt(readerConfig, '调查者', 'reader'),
      fmt(plannerConfig, '规划者', 'planner'),
      fmt(implementerConfig, '实施者', 'implementer'),
      fmt(reviewerConfig, '验收者', 'reviewer'),
    ];

    return '''[HARDNESS_CONFIG]
工作目录：$workingDirectory
持久化根目录：$persistenceDirectory
首次运行：${isFirstRun()}
角色配置（⚠️ 请严格按照「可执行文件」字段调用对应 CLI，不得自行推断）：
${roleLines.join('\n')}

语言要求：所有角色提示词、分析报告、执行计划、项目结构/架构文档、约定文档、feedback、handoff、lesson 等 Markdown 文档必须使用简体中文；仅代码、命令、路径、文件名、接口名、配置键名、日志原文以及 PASS/FAIL 等技术标识可保留原文。

任务需求：
$task
[/HARDNESS_CONFIG]''';
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
      p.join(persistenceDirectory, 'steering', 'meta', 'hardness_config.json'),
    );
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  /// Returns true if meta files (architecture.md / conventions.md) are missing,
  /// indicating a first-run in this context (profiler phase required).
  bool isFirstRun() {
    final archFile = File(
      p.join(persistenceDirectory, 'steering', 'meta', 'architecture.md'),
    );
    final convFile = File(
      p.join(persistenceDirectory, 'steering', 'meta', 'conventions.md'),
    );
    return !archFile.existsSync() || !convFile.existsSync();
  }
}
