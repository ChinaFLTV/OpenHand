import 'dart:convert';

/// Execution mode for a Harness Engineering agent role.
///
/// - [cli]: Invoke an external CLI tool (claude, codex, gemini, etc.)
/// - [url]: Use an API-based model from OpenHand settings via HTTP
enum HardnessExecutionMode {
  cli('cli'),
  url('url');

  const HardnessExecutionMode(this.storageValue);

  final String storageValue;

  static HardnessExecutionMode fromStorage(String? value) {
    for (final mode in HardnessExecutionMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return HardnessExecutionMode.cli;
  }
}

class HardnessRoleConfig {
  const HardnessRoleConfig({
    required this.cliName,
    required this.modelId,
    this.executionMode = HardnessExecutionMode.cli,
    this.aiModelConfigId,
    this.urlModeModelId,
  });

  /// Execution mode: CLI-based or URL/API-based.
  final HardnessExecutionMode executionMode;

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
    if (executionMode == HardnessExecutionMode.url) {
      return aiModelConfigId?.trim().isNotEmpty == true;
    }
    return cliName.trim().isNotEmpty && modelId.trim().isNotEmpty;
  }

  bool get isUrlMode => executionMode == HardnessExecutionMode.url;
  bool get isCliMode => executionMode == HardnessExecutionMode.cli;

  HardnessRoleConfig copyWith({
    String? cliName,
    String? modelId,
    HardnessExecutionMode? executionMode,
    String? aiModelConfigId,
    bool clearAiModelConfigId = false,
    String? urlModeModelId,
    bool clearUrlModeModelId = false,
  }) {
    return HardnessRoleConfig(
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

  static HardnessRoleConfig fromJson(Map<String, Object?> json) {
    return HardnessRoleConfig(
      cliName: '${json['cli_name'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}',
      executionMode: HardnessExecutionMode.fromStorage(
        json['execution_mode']?.toString(),
      ),
      aiModelConfigId: json['ai_model_config_id']?.toString(),
      urlModeModelId: json['url_mode_model_id']?.toString(),
    );
  }

  static HardnessRoleConfig get empty =>
      const HardnessRoleConfig(cliName: '', modelId: '');

  @override
  String toString() => jsonEncode(toJson());
}
