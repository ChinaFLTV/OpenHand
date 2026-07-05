import 'dart:convert';

import '../../../shared/util/input_value_parsing.dart';

/// Execution mode for a Harness Engineering agent role.
///
/// - [cli]: Invoke an external CLI tool (claude, codex, gemini, etc.)
/// - [url]: Use an API-based model from OpenHand settings via HTTP
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

  /// Execution mode: CLI-based or URL/API-based.
  final HarnessExecutionMode executionMode;

  /// CLI display name (e.g. "Claude Code"). Used when [executionMode] == cli.
  final String cliName;

  /// Model ID for CLI invocation (e.g. "claude-opus-4-6").
  /// For URL mode, this is informational only (the actual model comes from
  /// the referenced AiModelConfig).
  final String modelId;

  /// ID of the AiModelConfig entry from settings. Used when [executionMode] == url.
  final String? aiModelConfigId;

  /// Specific model ID to use within the provider. Used when [executionMode] == url.
  /// If null, the provider's default [AiModelConfig.modelId] is used.
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
      cliName: '${json['cli_name'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}',
      executionMode: HarnessExecutionMode.fromStorage(
        json['execution_mode']?.toString(),
      ),
      aiModelConfigId: json['ai_model_config_id']?.toString(),
      urlModeModelId: json['url_mode_model_id']?.toString(),
    );
  }

  static HarnessRoleConfig get empty =>
      const HarnessRoleConfig(cliName: '', modelId: '');

  @override
  String toString() => jsonEncode(toJson());
}
