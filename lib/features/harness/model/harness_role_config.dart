import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';

const int _maxHarnessRoleValueCharacters = 1024;

/// Harness 工程角色的执行模式。
///
/// - [cli]：调用外部命令行工具。
/// - [url]：通过 HTTP 调用 OpenHand 设置中的模型。
enum HarnessExecutionMode {
  cli('cli'),
  url('url');

  const HarnessExecutionMode(this.storageValue);

  final String storageValue;

  static HarnessExecutionMode fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (mode) => mode.storageValue,
      fallback: HarnessExecutionMode.cli,
      normalize: (item) => item.toLowerCase(),
    );
  }
}

class HarnessRoleConfig {
  const HarnessRoleConfig({
    required this.cliName,
    required this.modelId,
    this.executionMode = HarnessExecutionMode.cli,
    this.aiModelConfigId,
    this.urlModeModelId,
  });

  /// 命令行或接口执行模式。
  final HarnessExecutionMode executionMode;

  /// 命令行工具显示名称，仅用于命令行模式。
  final String cliName;

  /// 命令行调用的模型标识；接口模式下仅供展示。
  final String modelId;

  /// 接口模式使用的模型配置标识。
  final String? aiModelConfigId;

  /// 接口模式使用的提供商模型标识；为空时采用提供商默认模型。
  final String? urlModeModelId;

  bool get isConfigured {
    if (executionMode == HarnessExecutionMode.url) {
      return nullIfBlank(aiModelConfigId) != null;
    }
    return nullIfBlank(cliName) != null && nullIfBlank(modelId) != null;
  }

  bool get isUrlMode => executionMode == HarnessExecutionMode.url;
  bool get isCliMode => executionMode == HarnessExecutionMode.cli;

  HarnessRoleConfig copyWith({
    String? cliName,
    String? modelId,
    HarnessExecutionMode? executionMode,
    String? aiModelConfigId,
    bool clearAiModelConfigId = false,
    String? urlModeModelId,
    bool clearUrlModeModelId = false,
  }) {
    return HarnessRoleConfig(
      cliName: cliName ?? this.cliName,
      modelId: modelId ?? this.modelId,
      executionMode: executionMode ?? this.executionMode,
      aiModelConfigId: clearAiModelConfigId
          ? null
          : aiModelConfigId ?? this.aiModelConfigId,
      urlModeModelId: clearUrlModeModelId
          ? null
          : urlModeModelId ?? this.urlModeModelId,
    );
  }

  Map<String, Object?> toJson() => {
    'cli_name': cliName,
    'model_id': modelId,
    'execution_mode': executionMode.storageValue,
    'ai_model_config_id': aiModelConfigId,
    'url_mode_model_id': urlModeModelId,
  };

  static HarnessRoleConfig fromJson(Map<String, Object?> json) {
    return HarnessRoleConfig(
      cliName: clipTextByCodeUnits(
        '${json['cli_name'] ?? ''}',
        _maxHarnessRoleValueCharacters,
        suffix: '',
      ),
      modelId: clipTextByCodeUnits(
        '${json['model_id'] ?? ''}',
        _maxHarnessRoleValueCharacters,
        suffix: '',
      ),
      executionMode: HarnessExecutionMode.fromStorage(
        json['execution_mode']?.toString(),
      ),
      aiModelConfigId: json['ai_model_config_id'] == null
          ? null
          : clipTextByCodeUnits(
              '${json['ai_model_config_id']}',
              _maxHarnessRoleValueCharacters,
              suffix: '',
            ),
      urlModeModelId: json['url_mode_model_id'] == null
          ? null
          : clipTextByCodeUnits(
              '${json['url_mode_model_id']}',
              _maxHarnessRoleValueCharacters,
              suffix: '',
            ),
    );
  }

  static HarnessRoleConfig get empty =>
      const HarnessRoleConfig(cliName: '', modelId: '');

  @override
  String toString() => jsonEncode(toJson());
}
