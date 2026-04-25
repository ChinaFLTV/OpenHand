import 'package:flutter/material.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_builtin_tool_config.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../model/app_language.dart';
import '../model/dialog_animation_settings.dart';
import '../model/editor_code_theme.dart';
import '../model/editor_indent.dart';
import '../model/editor_shortcut.dart';
import '../support/openhand_paths.dart';
import '../theme/openhand_theme_preset.dart';
import 'openhand_shortcut.dart';

class AppSettingsSnapshot {
  factory AppSettingsSnapshot.defaults() {
    return AppSettingsSnapshot(
      themeMode: ThemeMode.system,
      themePreset: OpenHandThemePreset.deepSeaBlue,
      language: AppLanguage.simplifiedChinese,
      skillsStoragePath: OpenHandPaths.defaultSkillsDirectoryPath(),
      mcpEnabled: true,
      mcpServersFilePath: OpenHandPaths.defaultMcpServersFilePath(),
      memoryEnabled: true,
      userMemoryFilePath: OpenHandPaths.defaultUserMemoryFilePath(),
      editorWordWrap: true,
      editorIndentSpaces: defaultEditorIndentSpaces,
      editorCodeTheme: EditorCodeTheme.materialYou,
      editorLspSettings: const <String, AiLspLanguageSettings>{},
      editorShortcutBindings: defaultEditorShortcutBindings(),
      aiMessageCompressionThresholdChars:
          defaultAiMessageCompressionThresholdChars,
      aiSingleRoundToolCallLimit: defaultAiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: defaultAiSequentialToolRoundLimit,
      aiImageSizeLimitBytes: defaultAiImageSizeLimitBytes,
      aiWriteCommandConfirmationEnabled: true,
      aiAllowCommandRules: const <AiAllowCommandRule>[],
      aiDenyCommandRules: const <AiDenyCommandRule>[],
      aiConnectTimeoutSeconds: defaultAiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds: defaultAiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds: defaultAiStreamIdleTimeoutSeconds,
      aiAutoTitleEnabled: true,
      aiDefaultSessionMode: defaultAiDefaultSessionMode,
      aiDefaultFullAccessPermission: false,
      aiModels: const <AiModelConfig>[],
      selectedAiModelId: null,
      recentModelSelections: const <RecentModelSelection>[],
      shortcutBindings: defaultOpenHandShortcutBindings(),
      dialogAnimationSettings: const DialogAnimationSettings(),
      menuAnimationSettings: const DialogAnimationSettings(),
      pageAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.fade,
        exitStyle: DialogAnimationStyle.fade,
        durationMs: 800,
        curve: DialogAnimationCurve.easeInOutCubicEmphasized,
      ),
      panelAnimationSettings: const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.fade,
        exitStyle: DialogAnimationStyle.fade,
        durationMs: 600,
        curve: DialogAnimationCurve.easeInOutCubicEmphasized,
      ),
      builtinToolConfigs: AiBuiltinToolConfig.defaults(),
      telemetryDebugEnabled: false,
      telemetryCaptureRawPayload: true,
      telemetryCaptureEnvironment: false,
      telemetryMaxPayloadChars: defaultTelemetryMaxPayloadChars,
    );
  }
  const AppSettingsSnapshot({
    required this.themeMode,
    required this.themePreset,
    required this.language,
    required this.skillsStoragePath,
    required this.mcpEnabled,
    required this.mcpServersFilePath,
    required this.memoryEnabled,
    required this.userMemoryFilePath,
    required this.editorWordWrap,
    required this.editorIndentSpaces,
    required this.editorCodeTheme,
    required this.editorLspSettings,
    required this.editorShortcutBindings,
    required this.aiMessageCompressionThresholdChars,
    required this.aiSingleRoundToolCallLimit,
    required this.aiSequentialToolRoundLimit,
    required this.aiImageSizeLimitBytes,
    required this.aiWriteCommandConfirmationEnabled,
    required this.aiAllowCommandRules,
    required this.aiDenyCommandRules,
    required this.aiConnectTimeoutSeconds,
    required this.aiResponseTimeoutSeconds,
    required this.aiStreamIdleTimeoutSeconds,
    required this.aiAutoTitleEnabled,
    required this.aiDefaultSessionMode,
    required this.aiDefaultFullAccessPermission,
    required this.aiModels,
    required this.selectedAiModelId,
    required this.recentModelSelections,
    required this.shortcutBindings,
    required this.dialogAnimationSettings,
    required this.menuAnimationSettings,
    required this.pageAnimationSettings,
    required this.panelAnimationSettings,
    required this.builtinToolConfigs,
    required this.telemetryDebugEnabled,
    required this.telemetryCaptureRawPayload,
    required this.telemetryCaptureEnvironment,
    required this.telemetryMaxPayloadChars,
    this.selfLearningEnabled = true,
    this.selfLearningConcurrency = defaultSelfLearningConcurrency,
    this.showSelfLearningMessages = true,
  });

  /// Default and bounds for Hermes Talker self-learning concurrency (Task 21).
  static const int defaultSelfLearningConcurrency = 5;
  static const int minSelfLearningConcurrency = 1;
  static const int maxSelfLearningConcurrency = 10;

  static const int defaultAiMessageCompressionThresholdChars = 12000;

  /// Default cap for per-message raw payload capture (characters).
  static const int defaultTelemetryMaxPayloadChars = 200000;
  static const int minTelemetryMaxPayloadChars = 4000;
  static const int maxTelemetryMaxPayloadChars = 2000000;
  static const int defaultAiSingleRoundToolCallLimit = 40;
  static const int defaultAiSequentialToolRoundLimit = 24;

  /// Default per-image attachment size cap (1 MiB).
  ///
  /// When a user attaches an image larger than this threshold, the attachment
  /// pipeline downscales it before the editor opens so that storage, prompt
  /// payload and clipboard handoff remain bounded.
  static const int defaultAiImageSizeLimitBytes = 1024 * 1024;

  /// Hard floor to prevent users from saving an unusable threshold.
  static const int minAiImageSizeLimitBytes = 64 * 1024;

  /// Hard ceiling so a misconfigured value cannot blow up memory at runtime.
  static const int maxAiImageSizeLimitBytes = 64 * 1024 * 1024;

  /// Timeout (seconds) for establishing the HTTP connection and receiving
  /// initial response headers from the AI provider.
  static const int defaultAiConnectTimeoutSeconds = 60;
  static const int minAiConnectTimeoutSeconds = 5;
  static const int maxAiConnectTimeoutSeconds = 300;

  /// Timeout (seconds) for receiving a complete non-streaming AI response.
  static const int defaultAiResponseTimeoutSeconds = 120;
  static const int minAiResponseTimeoutSeconds = 10;
  static const int maxAiResponseTimeoutSeconds = 600;

  /// Per-chunk idle timeout (seconds) for streaming AI responses.
  /// When the stream receives no new data within this window, the request
  /// is aborted and an error is shown (the "Request timed out." case).
  static const int defaultAiStreamIdleTimeoutSeconds = 120;
  static const int minAiStreamIdleTimeoutSeconds = 10;
  static const int maxAiStreamIdleTimeoutSeconds = 600;

  /// Default session mode string: 'chat' or 'plan'.
  static const String defaultAiDefaultSessionMode = 'chat';

  final ThemeMode themeMode;
  final OpenHandThemePreset themePreset;
  final AppLanguage language;
  final String skillsStoragePath;
  final bool mcpEnabled;
  final String mcpServersFilePath;
  final bool memoryEnabled;
  final String userMemoryFilePath;
  final bool editorWordWrap;
  final int editorIndentSpaces;
  final EditorCodeTheme editorCodeTheme;
  final Map<String, AiLspLanguageSettings> editorLspSettings;
  final Map<EditorShortcutAction, List<int>> editorShortcutBindings;
  final int aiMessageCompressionThresholdChars;
  final int aiSingleRoundToolCallLimit;
  final int aiSequentialToolRoundLimit;
  final int aiImageSizeLimitBytes;
  final bool aiWriteCommandConfirmationEnabled;
  final List<AiAllowCommandRule> aiAllowCommandRules;
  final List<AiDenyCommandRule> aiDenyCommandRules;
  final int aiConnectTimeoutSeconds;
  final int aiResponseTimeoutSeconds;
  final int aiStreamIdleTimeoutSeconds;
  final bool aiAutoTitleEnabled;
  final String aiDefaultSessionMode;
  final bool aiDefaultFullAccessPermission;
  final List<AiModelConfig> aiModels;
  final String? selectedAiModelId;
  final List<RecentModelSelection> recentModelSelections;
  final Map<OpenHandShortcutAction, List<int>> shortcutBindings;
  final DialogAnimationSettings dialogAnimationSettings;
  final DialogAnimationSettings menuAnimationSettings;
  final DialogAnimationSettings pageAnimationSettings;
  final DialogAnimationSettings panelAnimationSettings;
  final List<AiBuiltinToolConfig> builtinToolConfigs;
  final bool telemetryDebugEnabled;
  final bool telemetryCaptureRawPayload;

  /// Controls whether a session/message-level environment snapshot
  /// (working directory, OS env variables, platform info) is persisted
  /// into message metadata for audit. Off by default because
  /// `Platform.environment` can contain secrets (tokens, API keys).
  final bool telemetryCaptureEnvironment;
  final int telemetryMaxPayloadChars;

  /// Whether the Hermes Talker self-learning scheduler is active.
  /// When false, [SelfLearningScheduler.tick] short-circuits to a no-op.
  final bool selfLearningEnabled;

  /// Upper bound on concurrent self-learning sub-agent dispatches.
  /// Clamped to [minSelfLearningConcurrency] .. [maxSelfLearningConcurrency].
  final int selfLearningConcurrency;

  /// Whether self-learning (Hermes Talker) cards are rendered in the chat
  /// transcript. Independent of [selfLearningEnabled]: the scheduler may
  /// still produce cards in the background; this flag only controls UI
  /// visibility. Default true.
  final bool showSelfLearningMessages;

  AppSettingsSnapshot copyWith({
    ThemeMode? themeMode,
    OpenHandThemePreset? themePreset,
    AppLanguage? language,
    String? skillsStoragePath,
    bool? mcpEnabled,
    String? mcpServersFilePath,
    bool? memoryEnabled,
    String? userMemoryFilePath,
    bool? editorWordWrap,
    int? editorIndentSpaces,
    EditorCodeTheme? editorCodeTheme,
    Map<String, AiLspLanguageSettings>? editorLspSettings,
    Map<EditorShortcutAction, List<int>>? editorShortcutBindings,
    int? aiMessageCompressionThresholdChars,
    int? aiSingleRoundToolCallLimit,
    int? aiSequentialToolRoundLimit,
    int? aiImageSizeLimitBytes,
    bool? aiWriteCommandConfirmationEnabled,
    List<AiAllowCommandRule>? aiAllowCommandRules,
    List<AiDenyCommandRule>? aiDenyCommandRules,
    int? aiConnectTimeoutSeconds,
    int? aiResponseTimeoutSeconds,
    int? aiStreamIdleTimeoutSeconds,
    bool? aiAutoTitleEnabled,
    String? aiDefaultSessionMode,
    bool? aiDefaultFullAccessPermission,
    List<AiModelConfig>? aiModels,
    String? selectedAiModelId,
    List<RecentModelSelection>? recentModelSelections,
    Map<OpenHandShortcutAction, List<int>>? shortcutBindings,
    DialogAnimationSettings? dialogAnimationSettings,
    DialogAnimationSettings? menuAnimationSettings,
    DialogAnimationSettings? pageAnimationSettings,
    DialogAnimationSettings? panelAnimationSettings,
    List<AiBuiltinToolConfig>? builtinToolConfigs,
    bool? telemetryDebugEnabled,
    bool? telemetryCaptureRawPayload,
    bool? telemetryCaptureEnvironment,
    int? telemetryMaxPayloadChars,
    bool? selfLearningEnabled,
    int? selfLearningConcurrency,
    bool? showSelfLearningMessages,
    bool clearSelectedAiModelId = false,
  }) {
    return AppSettingsSnapshot(
      themeMode: themeMode ?? this.themeMode,
      themePreset: themePreset ?? this.themePreset,
      language: language ?? this.language,
      skillsStoragePath: skillsStoragePath ?? this.skillsStoragePath,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      mcpServersFilePath: mcpServersFilePath ?? this.mcpServersFilePath,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      userMemoryFilePath: userMemoryFilePath ?? this.userMemoryFilePath,
      editorWordWrap: editorWordWrap ?? this.editorWordWrap,
      editorIndentSpaces: editorIndentSpaces ?? this.editorIndentSpaces,
      editorCodeTheme: editorCodeTheme ?? this.editorCodeTheme,
      editorLspSettings: editorLspSettings ?? this.editorLspSettings,
      editorShortcutBindings:
          editorShortcutBindings ?? this.editorShortcutBindings,
      aiMessageCompressionThresholdChars:
          aiMessageCompressionThresholdChars ??
          this.aiMessageCompressionThresholdChars,
      aiSingleRoundToolCallLimit:
          aiSingleRoundToolCallLimit ?? this.aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit:
          aiSequentialToolRoundLimit ?? this.aiSequentialToolRoundLimit,
      aiImageSizeLimitBytes:
          aiImageSizeLimitBytes ?? this.aiImageSizeLimitBytes,
      aiWriteCommandConfirmationEnabled:
          aiWriteCommandConfirmationEnabled ??
          this.aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: aiAllowCommandRules ?? this.aiAllowCommandRules,
      aiDenyCommandRules: aiDenyCommandRules ?? this.aiDenyCommandRules,
      aiConnectTimeoutSeconds:
          aiConnectTimeoutSeconds ?? this.aiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds:
          aiResponseTimeoutSeconds ?? this.aiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds:
          aiStreamIdleTimeoutSeconds ?? this.aiStreamIdleTimeoutSeconds,
      aiAutoTitleEnabled: aiAutoTitleEnabled ?? this.aiAutoTitleEnabled,
      aiDefaultSessionMode: aiDefaultSessionMode ?? this.aiDefaultSessionMode,
      aiDefaultFullAccessPermission:
          aiDefaultFullAccessPermission ?? this.aiDefaultFullAccessPermission,
      aiModels: aiModels ?? this.aiModels,
      selectedAiModelId: clearSelectedAiModelId
          ? null
          : selectedAiModelId ?? this.selectedAiModelId,
      recentModelSelections:
          recentModelSelections ?? this.recentModelSelections,
      shortcutBindings: shortcutBindings ?? this.shortcutBindings,
      dialogAnimationSettings:
          dialogAnimationSettings ?? this.dialogAnimationSettings,
      menuAnimationSettings:
          menuAnimationSettings ?? this.menuAnimationSettings,
      pageAnimationSettings:
          pageAnimationSettings ?? this.pageAnimationSettings,
      panelAnimationSettings:
          panelAnimationSettings ?? this.panelAnimationSettings,
      builtinToolConfigs: builtinToolConfigs ?? this.builtinToolConfigs,
      telemetryDebugEnabled:
          telemetryDebugEnabled ?? this.telemetryDebugEnabled,
      telemetryCaptureRawPayload:
          telemetryCaptureRawPayload ?? this.telemetryCaptureRawPayload,
      telemetryCaptureEnvironment:
          telemetryCaptureEnvironment ?? this.telemetryCaptureEnvironment,
      telemetryMaxPayloadChars:
          telemetryMaxPayloadChars ?? this.telemetryMaxPayloadChars,
      selfLearningEnabled: selfLearningEnabled ?? this.selfLearningEnabled,
      selfLearningConcurrency:
          selfLearningConcurrency ?? this.selfLearningConcurrency,
      showSelfLearningMessages:
          showSelfLearningMessages ?? this.showSelfLearningMessages,
    );
  }
}

/// A recently selected model entry for quick access in the model selector.
class RecentModelSelection {
  const RecentModelSelection({required this.configId, required this.modelId});

  factory RecentModelSelection.fromJson(Map<String, Object?> json) {
    return RecentModelSelection(
      configId: '${json['config_id'] ?? ''}'.trim(),
      modelId: '${json['model_id'] ?? ''}'.trim(),
    );
  }

  final String configId;
  final String modelId;

  Map<String, Object?> toJson() {
    return <String, Object?>{'config_id': configId, 'model_id': modelId};
  }

  @override
  bool operator ==(Object other) {
    return other is RecentModelSelection &&
        other.configId == configId &&
        other.modelId == modelId;
  }

  @override
  int get hashCode => Object.hash(configId, modelId);
}
