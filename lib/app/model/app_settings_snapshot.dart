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
      aiToolResultCompressionThresholdChars:
          defaultAiToolResultCompressionThresholdChars,
      aiToolResultCompressionEnabled: true,
      aiToolResultCompressionHeadTailWindowChars:
          defaultAiToolResultCompressionHeadTailWindowChars,
      aiToolResultCompressionMaxPathHits:
          defaultAiToolResultCompressionMaxPathHits,
      aiWriteToolSummaryMaxChars: defaultAiWriteToolSummaryMaxChars,
      aiSingleRoundToolCallLimit: defaultAiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: defaultAiSequentialToolRoundLimit,
      aiMaxRecentErrors: defaultAiMaxRecentErrors,
      aiMaxPlanHistoryEntries: defaultAiMaxPlanHistoryEntries,
      aiMaxTruncationContinuations: defaultAiMaxTruncationContinuations,
      aiEstimatedCharactersPerToken: defaultAiEstimatedCharactersPerToken,
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
    required this.aiToolResultCompressionThresholdChars,
    required this.aiToolResultCompressionEnabled,
    required this.aiToolResultCompressionHeadTailWindowChars,
    required this.aiToolResultCompressionMaxPathHits,
    required this.aiWriteToolSummaryMaxChars,
    required this.aiSingleRoundToolCallLimit,
    required this.aiSequentialToolRoundLimit,
    required this.aiMaxRecentErrors,
    required this.aiMaxPlanHistoryEntries,
    required this.aiMaxTruncationContinuations,
    required this.aiEstimatedCharactersPerToken,
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
    this.cronAutoCleanupEnabled = true,
    this.cronAutoCleanupRetentionDays = defaultCronAutoCleanupRetentionDays,
  });

  /// Default and bounds for Hermes Talker self-learning concurrency (Task 21).
  static const int defaultSelfLearningConcurrency = 5;
  static const int minSelfLearningConcurrency = 1;
  static const int maxSelfLearningConcurrency = 10;

  /// 2026-04-25 — 冷启动后自动清理 cron 历史的默认保留天数。
  static const int defaultCronAutoCleanupRetentionDays = 7;
  static const int minCronAutoCleanupRetentionDays = 1;
  static const int maxCronAutoCleanupRetentionDays = 365;

  static const int defaultAiMessageCompressionThresholdChars = 12000;

  /// 2026-04-27 — 工具调用输出进入 conversation history 前的字符上限。
  /// 超过该上限的工具返回会被压缩为结构化摘要（受影响文件路径
  /// + 行号 + AI 自述 purpose + 首尾片段），避免长篇 raw 输出吞噁
  /// 上下文 token。默认 1024 字符。
  static const int defaultAiToolResultCompressionThresholdChars = 1024;
  static const int minAiToolResultCompressionThresholdChars = 256;
  static const int maxAiToolResultCompressionThresholdChars = 65536;

  /// 2026-04-27 — 压缩摘要首尾片段窗口（字符）。越大保留越多 raw
  /// 上下文，但会占用更多 tokens。0 表示不保留首尾片段。
  static const int defaultAiToolResultCompressionHeadTailWindowChars = 256;
  static const int minAiToolResultCompressionHeadTailWindowChars = 0;
  static const int maxAiToolResultCompressionHeadTailWindowChars = 8192;

  /// 2026-04-27 — 压缩摘要中提取的文件路径条数上限。0 表示不提取。
  static const int defaultAiToolResultCompressionMaxPathHits = 12;
  static const int minAiToolResultCompressionMaxPathHits = 0;
  static const int maxAiToolResultCompressionMaxPathHits = 200;

  /// 2026-04-27 — 写类工具结果摘要中保留原始 summary 文本的字符上限。
  /// 超过该上限的 result_text 会被刪除（不进入 prompt history）。
  static const int defaultAiWriteToolSummaryMaxChars = 280;
  static const int minAiWriteToolSummaryMaxChars = 0;
  static const int maxAiWriteToolSummaryMaxChars = 8192;

  /// Default cap for per-message raw payload capture (characters).
  static const int defaultTelemetryMaxPayloadChars = 200000;
  static const int minTelemetryMaxPayloadChars = 4000;
  static const int maxTelemetryMaxPayloadChars = 2000000;
  static const int defaultAiSingleRoundToolCallLimit = 40;
  static const int defaultAiSequentialToolRoundLimit = 24;

  /// 2026-04-29 — Group A: AI 会话控制参数。
  static const int defaultAiMaxRecentErrors = 20;
  static const int minAiMaxRecentErrors = 0;
  static const int maxAiMaxRecentErrors = 1000;

  static const int defaultAiMaxPlanHistoryEntries = 20;
  static const int minAiMaxPlanHistoryEntries = 0;
  static const int maxAiMaxPlanHistoryEntries = 1000;

  static const int defaultAiMaxTruncationContinuations = 5;
  static const int minAiMaxTruncationContinuations = 0;
  static const int maxAiMaxTruncationContinuations = 100;

  static const int defaultAiEstimatedCharactersPerToken = 4;
  static const int minAiEstimatedCharactersPerToken = 1;
  static const int maxAiEstimatedCharactersPerToken = 32;

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
  final int aiToolResultCompressionThresholdChars;

  /// 2026-04-27 — 总开关：关闭后工具调用输出不再进行压缩。
  final bool aiToolResultCompressionEnabled;

  /// 2026-04-27 — 压缩摘要首尾片段窗口长度（字符）。
  final int aiToolResultCompressionHeadTailWindowChars;

  /// 2026-04-27 — 压缩摘要中提取的文件路径条数上限。
  final int aiToolResultCompressionMaxPathHits;

  /// 2026-04-27 — 写类工具摘要中 result_text 的字符上限。
  final int aiWriteToolSummaryMaxChars;
  final int aiSingleRoundToolCallLimit;
  final int aiSequentialToolRoundLimit;

  /// Group A: 会话错误记录保留上限。
  final int aiMaxRecentErrors;

  /// Group A: plan_history 保留上限。
  final int aiMaxPlanHistoryEntries;

  /// Group A: 超长响应被截断后的自动续接轮次上限。
  final int aiMaxTruncationContinuations;

  /// Group A: token 估算系数（每个 token 平均多少字符）。
  final int aiEstimatedCharactersPerToken;
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

  /// 2026-04-25 — 冷启动后是否异步清理过期 cron 执行历史。
  /// 默认 true，免得历史表不受控增长。
  final bool cronAutoCleanupEnabled;

  /// 2026-04-25 — 保留上限天数；超过该天数的条目在冷启动起动
  /// 的 worker 里被删除。[minCronAutoCleanupRetentionDays] 与
  /// [maxCronAutoCleanupRetentionDays] 是输入安全护栏。
  final int cronAutoCleanupRetentionDays;

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
    int? aiToolResultCompressionThresholdChars,
    bool? aiToolResultCompressionEnabled,
    int? aiToolResultCompressionHeadTailWindowChars,
    int? aiToolResultCompressionMaxPathHits,
    int? aiWriteToolSummaryMaxChars,
    int? aiSingleRoundToolCallLimit,
    int? aiSequentialToolRoundLimit,
    int? aiMaxRecentErrors,
    int? aiMaxPlanHistoryEntries,
    int? aiMaxTruncationContinuations,
    int? aiEstimatedCharactersPerToken,
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
    bool? cronAutoCleanupEnabled,
    int? cronAutoCleanupRetentionDays,
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
      aiToolResultCompressionThresholdChars:
          aiToolResultCompressionThresholdChars ??
          this.aiToolResultCompressionThresholdChars,
      aiToolResultCompressionEnabled:
          aiToolResultCompressionEnabled ?? this.aiToolResultCompressionEnabled,
      aiToolResultCompressionHeadTailWindowChars:
          aiToolResultCompressionHeadTailWindowChars ??
          this.aiToolResultCompressionHeadTailWindowChars,
      aiToolResultCompressionMaxPathHits:
          aiToolResultCompressionMaxPathHits ??
          this.aiToolResultCompressionMaxPathHits,
      aiWriteToolSummaryMaxChars:
          aiWriteToolSummaryMaxChars ?? this.aiWriteToolSummaryMaxChars,
      aiSingleRoundToolCallLimit:
          aiSingleRoundToolCallLimit ?? this.aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit:
          aiSequentialToolRoundLimit ?? this.aiSequentialToolRoundLimit,
      aiMaxRecentErrors: aiMaxRecentErrors ?? this.aiMaxRecentErrors,
      aiMaxPlanHistoryEntries:
          aiMaxPlanHistoryEntries ?? this.aiMaxPlanHistoryEntries,
      aiMaxTruncationContinuations:
          aiMaxTruncationContinuations ?? this.aiMaxTruncationContinuations,
      aiEstimatedCharactersPerToken:
          aiEstimatedCharactersPerToken ?? this.aiEstimatedCharactersPerToken,
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
      cronAutoCleanupEnabled:
          cronAutoCleanupEnabled ?? this.cronAutoCleanupEnabled,
      cronAutoCleanupRetentionDays:
          cronAutoCleanupRetentionDays ?? this.cronAutoCleanupRetentionDays,
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
